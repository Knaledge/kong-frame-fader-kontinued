local addonName, A = ...
local Transparency = {}
A.FramePresetTransparency = Transparency

local records = setmetatable({}, {__mode = "k"})
local chatFrames = setmetatable({}, {__mode = "k"})
local chatTextRecords = setmetatable({}, {__mode = "k"})
local alphaTolerance = .001
local playerTransparencyConflict = "Another addon may be controlling player frame transparency"
local targetTransparencyConflict = "Another addon may be controlling target frame transparency"
local chatTransparencyConflict = "Another addon may be controlling chat frame transparency"
local chatTextTransparencyConflict = "Another addon may be controlling chat text transparency"
local refreshQueued

local function IsPublic(value)
    return not (issecretvalue and issecretvalue(value))
end

local function ReadAlpha(region)
    if type(region.GetAlpha) ~= "function" then return end
    local ok, alpha = pcall(region.GetAlpha, region)
    if ok and IsPublic(alpha) and type(alpha) == "number" and alpha >= 0 and alpha <= 1 then return alpha end
end

local function LikelySource()
    if not debugstack then return end
    local stack = debugstack(3, 10, 0):gsub("\\", "/")
    for name in stack:gmatch("[Aa][Dd][Dd][Oo][Nn][Ss]/([^/\r\n]+)/") do
        if name ~= addonName and name ~= addonName .. "Config" and not name:match("^Blizzard_")
            and name:match("^[%w_. %-]+$") then return name end
    end
end

function Transparency.TrackChatFrame(region)
    chatFrames[region] = true
end

function Transparency.ForEachChatFrame(callback)
    if not FCF_IterateActiveChatWindows then return end
    FCF_IterateActiveChatWindows(function(region, id)
        if KongKontinued_CanAccessFrame(region) and IsPublic(region.isTemporary) and not region.isTemporary then
            Transparency.TrackChatFrame(region)
            callback(region, id)
        end
    end)
end

function Transparency.Handles(region)
    return IsPublic(region) and (region == PlayerFrame or region == TargetFrame or chatFrames[region] ~= nil)
        and KongKontinued_CanAccessFrame(region)
end

local function QueueRefresh()
    if refreshQueued then return end
    refreshQueued = true
    C_Timer.After(0, function()
        refreshQueued = nil
        Transparency.Refresh()
    end)
end

local function GetChatTextConflict(region)
    -- The native line fade and decorative elements use other regions.
    local container = region.FontStringContainer
    if not KongKontinued_CanAccessFrame(container) then return end
    local state = chatTextRecords[container]
    if not state then
        state = {}
        chatTextRecords[container] = state
        if hooksecurefunc and type(container.SetAlpha) == "function" then
            pcall(hooksecurefunc, container, "SetAlpha", function(self)
                local alpha = ReadAlpha(self)
                local source = alpha and alpha < 1 - alphaTolerance and LikelySource() or nil
                if alpha ~= state.alpha or source ~= state.source then
                    state.alpha, state.source = alpha, source
                    QueueRefresh()
                end
            end)
        end
    end

    local alpha = ReadAlpha(container)
    if alpha ~= state.alpha then state.alpha, state.source = alpha, nil end
    if alpha and alpha < 1 - alphaTolerance then return chatTextTransparencyConflict, state.source end
end

local function Observe(region)
    local state = records[region]
    if state then return state end
    state = {}
    records[region] = state
    if hooksecurefunc then
        pcall(hooksecurefunc, region, "SetAlpha", function(self)
            if state.writing or state.externalAlpha then return end
            local alpha = ReadAlpha(self)
            if alpha and math.abs(alpha - (state.lastAlpha or 1)) > alphaTolerance then
                state.externalAlpha, state.alphaSource = true, LikelySource()
                QueueRefresh()
            end
        end)
        pcall(hooksecurefunc, region, "SetParent", function(self)
            state.parent = KongKontinued_GetFrameParent(self)
            state.parentSource = LikelySource()
            QueueRefresh()
        end)
    end
    return state
end

function Transparency.GetUnavailableReason(region)
    if not Transparency.Handles(region) then return "The Blizzard frame is unavailable" end
    if chatFrames[region] and (not IsPublic(region.isTemporary) or region.isTemporary) then
        return "This chat window is unavailable for presets"
    end
    local transparencyConflict = chatFrames[region] and chatTransparencyConflict
        or (region == PlayerFrame and playerTransparencyConflict or targetTransparencyConflict)
    local state = Observe(region)
    local parent = KongKontinued_GetFrameParent(region)
    while parent and parent ~= UIParent and parent ~= WorldFrame do
        local shown = parent:IsShown()
        if IsPublic(shown) and not shown then
            return transparencyConflict, parent == state.parent and state.parentSource or nil
        end
        local alpha = ReadAlpha(parent)
        if alpha and alpha < 1 - alphaTolerance then return transparencyConflict end
        parent = KongKontinued_GetFrameParent(parent)
    end

    if state.externalAlpha then return transparencyConflict, state.alphaSource end
    local alpha = ReadAlpha(region)
    if not alpha then return "Kong can't read the frame's opacity" end
    if state.lastAlpha then
        -- Animation and shared-method writes can bypass the frame's secure hook.
        if math.abs(alpha - state.lastAlpha) > alphaTolerance then
            state.externalAlpha = true
            QueueRefresh()
            return transparencyConflict
        end
    elseif alpha < 1 - alphaTolerance then
        return transparencyConflict
    end
    if chatFrames[region] then return GetChatTextConflict(region) end
end

function Transparency.CanFade(region)
    if not Transparency.GetUnavailableReason(region) then return true end
    local state = records[region]
    if state and not state.paused then
        state.paused = true
        QueueRefresh()
    end
    return false
end

function Transparency.WriteAlpha(fader, region, alpha, guarded, writeAlpha)
    if not Transparency.Handles(region) then return false end
    local state = Observe(region)
    if guarded then
        if not Transparency.CanFade(region) then return false end
    elseif Transparency.GetUnavailableReason(region) and not state.lastAlpha then
        local current = ReadAlpha(region)
        if current and current < 1 - alphaTolerance then state.externalAlpha = true end
    end
    state.writing = true
    local applied = writeAlpha(fader, region, alpha)
    state.writing = nil
    if applied then state.lastAlpha = alpha end
    return applied
end

function Transparency.RestoreChatFrameAlpha(fader, region, alpha, writeAlpha)
    local state = records[region]
    if not chatFrames[region] or alpha == nil or not state or state.lastAlpha == nil or state.lastAlpha == alpha
        or Transparency.GetUnavailableReason(region) ~= chatTextTransparencyConflict then return end
    return Transparency.WriteAlpha(fader, region, alpha, false, writeAlpha)
end

local function RefreshFrame(region)
    if not Transparency.Handles(region) then return end
    local state = Observe(region)
    local reason, source = Transparency.GetUnavailableReason(region)
    local resumed = state.paused and reason == nil
    if not resumed and reason == state.reason and source == state.source then return end
    local availabilityChanged = resumed or (reason == nil) ~= (state.reason == nil)
    local chatTextTookOver = reason == chatTextTransparencyConflict and reason ~= state.reason
    if resumed then state.paused = nil end
    state.reason, state.source = reason, source
    if availabilityChanged or chatTextTookOver then A.OnFramePresetAvailabilityChanged(region, reason == nil) end
    return true
end

function Transparency.Refresh()
    local playerChanged, targetChanged = RefreshFrame(PlayerFrame), RefreshFrame(TargetFrame)
    local chatChanged
    Transparency.ForEachChatFrame(function(region)
        if RefreshFrame(region) then chatChanged = true end
    end)
    if (playerChanged or targetChanged or chatChanged) and A.RefreshPresetOptions then A.RefreshPresetOptions() end
end

Transparency.Refresh()
