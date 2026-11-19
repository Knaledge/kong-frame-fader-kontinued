local addonName, A = ...
local UnitFrames = {}
A.UnitFramePresets = UnitFrames

local records = setmetatable({}, {__mode = "k"})
local alphaTolerance = .001
local alphaConflict = "Another addon may be controlling this frame's transparency"
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

function UnitFrames.Handles(region)
    return IsPublic(region) and (region == PlayerFrame or region == TargetFrame) and KongKontinued_CanAccessFrame(region)
end

local function QueueRefresh()
    if refreshQueued then return end
    refreshQueued = true
    C_Timer.After(0, function()
        refreshQueued = nil
        UnitFrames.Refresh()
    end)
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

function UnitFrames.GetUnavailableReason(region)
    if not UnitFrames.Handles(region) then return "The Blizzard frame is unavailable" end
    local state = Observe(region)
    local parent = KongKontinued_GetFrameParent(region)
    while parent and parent ~= UIParent and parent ~= WorldFrame do
        local shown = parent:IsShown()
        if IsPublic(shown) and not shown then
            return "The Blizzard frame is under a hidden parent", parent == state.parent and state.parentSource or nil
        end
        local alpha = ReadAlpha(parent)
        if alpha and alpha < 1 - alphaTolerance then return "The frame's parent is already faded" end
        parent = KongKontinued_GetFrameParent(parent)
    end

    if state.externalAlpha then return alphaConflict, state.alphaSource end
    local alpha = ReadAlpha(region)
    if not alpha then return "Kong can't read the frame's opacity" end
    if state.lastAlpha then
        -- Animation and shared-method writes can bypass the frame's secure hook.
        if math.abs(alpha - state.lastAlpha) > alphaTolerance then
            state.externalAlpha = true
            QueueRefresh()
            return alphaConflict
        end
    elseif alpha < 1 - alphaTolerance then
        return "The Blizzard frame is already faded"
    end
end

function UnitFrames.CanFade(region)
    if not UnitFrames.GetUnavailableReason(region) then return true end
    local state = records[region]
    if state and not state.paused then
        state.paused = true
        QueueRefresh()
    end
    return false
end

function UnitFrames.WriteAlpha(fader, region, alpha, guarded, writeAlpha)
    if not UnitFrames.Handles(region) then return false end
    local state = Observe(region)
    if guarded then
        if not UnitFrames.CanFade(region) then return false end
    elseif UnitFrames.GetUnavailableReason(region) and not state.lastAlpha then
        local current = ReadAlpha(region)
        if current and current < 1 - alphaTolerance then state.externalAlpha = true end
    end
    state.writing = true
    local applied = writeAlpha(fader, region, alpha)
    state.writing = nil
    if applied then state.lastAlpha = alpha end
    return applied
end

local function RefreshFrame(region)
    if not UnitFrames.Handles(region) then return end
    local state = Observe(region)
    local reason, source = UnitFrames.GetUnavailableReason(region)
    local resumed = state.paused and reason == nil
    if not resumed and reason == state.reason and source == state.source then return end
    local availabilityChanged = resumed or (reason == nil) ~= (state.reason == nil)
    if resumed then state.paused = nil end
    state.reason, state.source = reason, source
    if availabilityChanged then A.OnUnitFramePresetAvailabilityChanged(region, reason == nil) end
    return true
end

function UnitFrames.Refresh()
    local playerChanged = RefreshFrame(PlayerFrame)
    local targetChanged = RefreshFrame(TargetFrame)
    if (playerChanged or targetChanged) and A.RefreshPresetOptions then A.RefreshPresetOptions() end
end

UnitFrames.Refresh()
