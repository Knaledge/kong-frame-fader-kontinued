local N, A = ...
local Preset = {}
A.MinimapPreset = Preset
local Attribution = A.AddonAttribution

local roundMask = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local maskPattern = "Interface\\AddOns\\" .. N .. "\\Textures\\PresetMinimap\\%03d.tga"
local transparencyConflict = "Another addon may be controlling minimap transparency"
local proxy, owner, priorMask, appliedPercent, failed, restoring
local watchedMap, maskHooked, writingMask, maskChanged, opacityChanged, refreshQueued
local maskSource, opacitySource
local alphaHooks = setmetatable({}, {__mode = "k"})

local function CanSetMask(region)
    return KongKontinued_CanAccessFrame(region) and type(region.SetMaskTexture) == "function"
end

local function IsPublic(value)
    return not (issecretvalue and issecretvalue(value))
end

local function ReadOpacity(region)
    local getAlpha = region.GetEffectiveAlpha or region.GetAlpha
    if type(getAlpha) ~= "function" then return end
    local ok, alpha = pcall(getAlpha, region)
    if ok and IsPublic(alpha) and type(alpha) == "number" and alpha >= 0 and alpha <= 1 then return alpha end
end

local function StopSampling()
    if not proxy then return end
    proxy:SetScript("OnUpdate", nil)
    proxy:Hide()
end

local function IsObservedMaskSetter(region)
    return region == watchedMap and region.SetMaskTexture == maskHooked
end

local function WriteMask(region, mask)
    writingMask = mask
    local ok = pcall(region.SetMaskTexture, region, mask)
    writingMask = nil
    return ok
end

local function ReleaseMask()
    if not owner then return end
    StopSampling()
    if appliedPercent ~= 100 or failed then
        local target = owner
        if not KongKontinued_CanAccessFrame(target) then
            restoring = true
            return
        end
        if IsObservedMaskSetter(target) then
            local ok = WriteMask(target, priorMask)
            if owner ~= target then return end
            if not ok then
                restoring = true
                return
            end
        end
    end
    owner, priorMask, appliedPercent, restoring = nil, nil, nil, nil
end

local function QueueRefresh()
    if refreshQueued then return end
    refreshQueued = true
    C_Timer.After(0, function()
        refreshQueued = nil
        -- Let a competing writer finish before deciding who owns the mask.
        if opacityChanged or failed then ReleaseMask() end
        if A.RefreshPresetOptions then A.RefreshPresetOptions() end
    end)
end

local function CheckMaskSetter(region)
    if IsObservedMaskSetter(region) then return true end
    ReleaseMask()
    QueueRefresh()
    return false
end

local function OnMaskWrite(region, mask)
    if region ~= Minimap or (writingMask ~= nil and IsPublic(mask) and rawequal(mask, writingMask)) then return end
    if not maskChanged then
        maskChanged, maskSource = true, Attribution.FromStack()
    elseif not owner then
        return
    end
    StopSampling()
    -- The other writer's mask is already installed. Restoring ours or the
    -- saved baseline here would replace their new mask.
    owner, priorMask, appliedPercent, restoring = nil, nil, nil, nil
    QueueRefresh()
end

local function PauseForOpacityChange(source)
    opacityChanged, opacitySource = true, source
    StopSampling()
    QueueRefresh()
end

local function OnAlphaWrite(_, alpha)
    if opacityChanged or not IsPublic(alpha) or type(alpha) ~= "number" or alpha >= .995 then return end
    if not KongKontinued_CanAccessFrame(Minimap) then return end
    local effective = ReadOpacity(Minimap)
    if effective and effective < .995 then
        PauseForOpacityChange(Attribution.FromStack())
    end
end

local function WatchAlpha(region)
    if not KongKontinued_CanAccessFrame(region) or alphaHooks[region] ~= nil or type(region.SetAlpha) ~= "function" then return end
    local ok = pcall(hooksecurefunc, region, "SetAlpha", OnAlphaWrite)
    alphaHooks[region] = ok and region.SetAlpha
end

local function Observe(region)
    if not CanSetMask(region) then return false end
    if watchedMap ~= region then
        watchedMap = region
        local ok = pcall(hooksecurefunc, region, "SetMaskTexture", OnMaskWrite)
        maskHooked = ok and region.SetMaskTexture
    end
    WatchAlpha(region)
    local parent = KongKontinued_GetFrameParent(region)
    if parent and parent ~= UIParent and parent ~= WorldFrame then
        WatchAlpha(parent)
        if KongKontinued_GetFrameParent(parent) == MinimapCluster then WatchAlpha(MinimapCluster) end
    end
    local alphaHook = alphaHooks[region]
    return IsObservedMaskSetter(region) and alphaHook and alphaHook == region.SetAlpha
end

local function FindPriorMask(region)
    -- A shape provider may own a mask installed before Kong could observe it.
    -- Our opacity masks are round, so do not take over a custom shape provider.
    if GetMinimapShape then
        return nil, "Another addon may be customizing the minimap shape", Attribution.FromGlobal("GetMinimapShape")
    end

    if type(region.GetMaskTexture) == "function" then
        local ok, mask = pcall(region.GetMaskTexture, region)
        if ok and IsPublic(mask)
            and (type(mask) == "string" or type(mask) == "number") then return mask end
    end
    if MinimapCluster and MinimapCluster.MinimapContainer
        and KongKontinued_GetFrameParent(region) == MinimapCluster.MinimapContainer then return roundMask end
    return nil, "Kong can't determine which minimap mask to restore"
end

local function CheckAvailability()
    if maskChanged then return nil, transparencyConflict, maskSource end
    if opacityChanged then return nil, transparencyConflict, opacitySource end
    if restoring then return nil, "Waiting to restore the previous minimap mask" end
    if failed then return nil, "Kong couldn't update the minimap mask" end
    if not CanSetMask(Minimap) then return nil, "The minimap frame is unavailable" end
    if not Observe(Minimap) then return nil, "Kong can't monitor changes to the minimap mask and opacity" end
    local alpha = ReadOpacity(Minimap)
    if alpha == nil then return nil, "Kong can't read the minimap opacity" end
    if alpha < .995 then
        if owner then PauseForOpacityChange() end
        return nil, "The minimap or its parent is already faded"
    end
    if owner == Minimap then return priorMask end
    return FindPriorMask(Minimap)
end

function Preset.GetUnavailableReason()
    local _, reason, source = CheckAvailability()
    return reason, source
end

function Preset.CheckOwnedMask()
    if not owner or opacityChanged or restoring or not KongKontinued_CanAccessFrame(owner)
        or not CheckMaskSetter(owner) then return end
    local alpha = ReadOpacity(owner)
    if alpha and alpha < .995 then PauseForOpacityChange() end
end

local function ApplyMask()
    if not owner or maskChanged or opacityChanged then return end
    local percent = math.floor(proxy:GetAlpha() * 100 + .5)
    if percent == appliedPercent then return end
    local target = owner
    local alpha = target == Minimap and KongKontinued_CanAccessFrame(target) and ReadOpacity(target)
    if not alpha or alpha < .995 then
        PauseForOpacityChange()
        return
    end
    if not CheckMaskSetter(target) then return end
    local mask = percent == 100 and priorMask or string.format(maskPattern, percent)
    local ok = WriteMask(target, mask)
    if owner ~= target then return end
    if ok then
        appliedPercent = percent
    else
        failed = true
        StopSampling()
        QueueRefresh()
    end
end

function Preset.Acquire()
    local mask = CheckAvailability()
    if not mask then return end
    if not owner then
        if not proxy then proxy = CreateFrame("Frame", nil, UIParent) end
        owner, priorMask, appliedPercent = Minimap, mask, 100
        proxy:SetAlpha(1)
    end
    proxy:SetScript("OnUpdate", ApplyMask)
    proxy:Show()
    return proxy
end

function Preset.GetTarget()
    if owner then return proxy end
end

function Preset.GetAlpha()
    return owner and proxy:GetAlpha() or 1
end

function Preset.FinishFade()
    if not failed then ApplyMask() end
    StopSampling()
end

function Preset.Release()
    ReleaseMask()
    failed = nil
end

function Preset.RetryRestore()
    if restoring then ReleaseMask() end
end

-- Install the observers as early as possible, including on clients that
-- load Blizzard's minimap after Kong.
if not Observe(Minimap) then
    local events = CreateFrame("Frame")
    events:RegisterEvent("ADDON_LOADED")
    events:RegisterEvent("PLAYER_LOGIN")
    events:SetScript("OnEvent", function(self, event)
        if Observe(Minimap) or event == "PLAYER_LOGIN" then
            self:UnregisterEvent("ADDON_LOADED")
            self:UnregisterEvent("PLAYER_LOGIN")
        end
    end)
end
