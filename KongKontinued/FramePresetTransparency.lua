local _, A = ...
local Transparency = {}
A.FramePresetTransparency = Transparency
local Attribution = A.AddonAttribution

local records = setmetatable({}, {__mode = "k"})
local chatFrames = setmetatable({}, {__mode = "k"})
local chatTextRecords = setmetatable({}, {__mode = "k"})
local alphaTolerance = .001
local attributionInterval = 1
local playerTransparencyConflict = "Another addon may be controlling player frame transparency"
local targetTransparencyConflict = "Another addon may be controlling target frame transparency"
local actionBarTransparencyConflict = "Another addon may be controlling this bar's opacity"
local chatTransparencyConflict = "Another addon may be controlling chat frame transparency"
local chatTextTransparencyConflict = "Another addon may be controlling chat text transparency"
local refreshQueued
local activeActionBarSupport

Transparency.DefaultActionBars = {
    {"MainActionBar", "Action Bar 1"},
    {"MultiBarBottomLeft", "Action Bar 2", "MultiBar1_IsVisible"},
    {"MultiBarBottomRight", "Action Bar 3", "MultiBar2_IsVisible"},
    {"MultiBarRight", "Action Bar 4", "MultiBar3_IsVisible"},
    {"MultiBarLeft", "Action Bar 5", "MultiBar4_IsVisible"},
    {"MultiBar5", "Action Bar 6", "MultiBar5_IsVisible"},
    {"MultiBar6", "Action Bar 7", "MultiBar6_IsVisible"},
    {"MultiBar7", "Action Bar 8", "MultiBar7_IsVisible"},
}
local defaultActionBarNames = {MainMenuBar = true}
for _, bar in ipairs(Transparency.DefaultActionBars) do defaultActionBarNames[bar[1]] = true end

local function IsPublic(value)
    return not (issecretvalue and issecretvalue(value))
end

local function ReadAlpha(region)
    if type(region.GetAlpha) ~= "function" then return end
    local ok, alpha = pcall(region.GetAlpha, region)
    if ok and IsPublic(alpha) and type(alpha) == "number" and alpha >= 0 and alpha <= 1 then return alpha end
end

local function IsReduced(alpha)
    return alpha ~= nil and alpha < 1 - alphaTolerance
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

function Transparency.GetActionBarSupport()
    local support = A.ActionBarPresetSupport
    if support and support.IsActive() then return support end
end

function Transparency.IsManagedActionBar(region)
    local support = A.ActionBarPresetSupport
    return support and support.OwnsBar(region)
end

function Transparency.IsManagedActionBarDisabled(region)
    return Transparency.IsManagedActionBar(region) and A.ActionBarPresetSupport.IsBarDisabled(region)
end

function Transparency.IsDefaultActionBar(region)
    if not KongKontinued_CanAccessFrame(region) or not region.GetName then return false end
    local name = region:GetName()
    return IsPublic(name) and defaultActionBarNames[name] and _G[name] == region
end

function Transparency.IsDefaultActionBarReplaced(region)
    return Transparency.GetActionBarSupport() ~= nil and Transparency.IsDefaultActionBar(region)
end

function Transparency.Tracks(region)
    return IsPublic(region) and (region == PlayerFrame or region == TargetFrame or chatFrames[region] ~= nil
        or Transparency.IsManagedActionBar(region))
end

function Transparency.Handles(region)
    return Transparency.Tracks(region) and KongKontinued_CanAccessFrame(region)
end

local function QueueRefresh()
    if refreshQueued then return end
    refreshQueued = true
    C_Timer.After(0, function()
        refreshQueued = nil
        Transparency.Refresh()
    end)
end

function Transparency.OnNativeActionBarAlphaSet(region)
    local state = records[region]
    if not state or not (state.lastAlpha or state.externalAlpha) or ReadAlpha(region) ~= 1 then return end
    state.lastAlpha, state.externalAlpha, state.alphaSource = nil, nil, nil
    state.paused = true
    A.OnManagedActionBarAlphaRestored(region)
    QueueRefresh()
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
                local reduced, source = IsReduced(alpha), state.source
                if reduced then
                    local now = GetTime()
                    if not state.sampledAt or now - state.sampledAt >= attributionInterval then
                        source, state.sampledAt = Attribution.FromStack(), now
                    end
                else
                    source, state.sampledAt = nil, nil
                end
                local changed = reduced ~= IsReduced(state.alpha) or source ~= state.source
                state.alpha, state.source = alpha, source
                if changed then QueueRefresh() end
            end)
        end
    end

    local alpha = ReadAlpha(container)
    if alpha ~= state.alpha then state.alpha, state.source, state.sampledAt = alpha, nil, nil end
    if IsReduced(alpha) then return chatTextTransparencyConflict, state.source end
end

local function Observe(region)
    local state = records[region]
    if state then return state end
    state = {}
    records[region] = state
    if hooksecurefunc then
        pcall(hooksecurefunc, region, "SetAlpha", function(self)
            if state.writing then return end
            local isActionBar = Transparency.IsManagedActionBar(self)
            if state.externalAlpha and (not isActionBar or state.lastAlpha == nil) then return end
            local alpha = ReadAlpha(self)
            local changed = alpha and math.abs(alpha - (state.lastAlpha or 1)) > alphaTolerance
            -- A write by another owner ends our claim even if the value matches.
            if changed or (isActionBar and state.lastAlpha ~= nil) then
                if isActionBar then state.lastAlpha = nil end
                if state.externalAlpha then return end
                state.externalAlpha, state.alphaSource = true, Attribution.FromStack()
                QueueRefresh()
            end
        end)
        pcall(hooksecurefunc, region, "SetParent", function(self)
            state.parent = KongKontinued_GetFrameParent(self)
            state.parentSource = Attribution.FromStack()
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
    local isActionBar = Transparency.IsManagedActionBar(region)
    if isActionBar then
        local reason = A.ActionBarPresetSupport.GetUnavailableReason(region)
        if reason then return reason end
    end
    local transparencyConflict = isActionBar and actionBarTransparencyConflict or chatFrames[region] and chatTransparencyConflict
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

local function ApplyAlpha(state, fader, region, alpha, writeAlpha)
    state.writing = true
    local applied = writeAlpha(fader, region, alpha)
    state.writing = nil
    if applied then state.lastAlpha = alpha end
    return applied
end

function Transparency.WriteAlpha(fader, region, alpha, guarded, writeAlpha)
    if not Transparency.Handles(region) then return false end
    if Transparency.IsManagedActionBarDisabled(region) then return false end
    local state = Observe(region)
    if guarded then
        if not Transparency.CanFade(region) then return false end
    elseif Transparency.GetUnavailableReason(region) and not state.lastAlpha then
        local current = ReadAlpha(region)
        if current and current < 1 - alphaTolerance then state.externalAlpha = true end
    end
    return ApplyAlpha(state, fader, region, alpha, writeAlpha)
end

function Transparency.RestoreOwnedAlpha(fader, region, alpha, writeAlpha)
    local state = records[region]
    if alpha == nil or not state or state.writing
        or (state.externalAlpha and not Transparency.IsManagedActionBar(region))
        or state.lastAlpha == nil or state.lastAlpha == alpha or not Transparency.Tracks(region) then return end
    -- False keeps the restore pending. Nil means there is nothing left to restore.
    if not KongKontinued_CanAccessFrame(region) then return false end
    if chatFrames[region] and (not IsPublic(region.isTemporary) or region.isTemporary) then return end
    local current = ReadAlpha(region)
    if current == nil then return false end
    if math.abs(current - state.lastAlpha) > alphaTolerance then return end
    return ApplyAlpha(state, fader, region, alpha, writeAlpha)
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
    local support = Transparency.GetActionBarSupport()
    local actionBarsChanged = support ~= activeActionBarSupport
    activeActionBarSupport = support
    if actionBarsChanged then A.OnDefaultActionBarSupportChanged() end
    if support then
        if support.ObserveNativeAlpha then support.ObserveNativeAlpha() end
        support.ForEachBar(function(region, name, title, enabled)
            if not region then return end
            if RefreshFrame(region) then actionBarsChanged = true end
            local state = records[region]
            if state and state.listed ~= enabled then
                local wasListed = state.listed
                state.listed = enabled
                if wasListed ~= nil then A.OnManagedActionBarEnabledChanged(region, enabled) end
                actionBarsChanged = true
            end
        end)
    end
    if (playerChanged or targetChanged or chatChanged or actionBarsChanged) and A.RefreshPresetOptions then
        A.RefreshPresetOptions()
    end
end

Transparency.Refresh()
