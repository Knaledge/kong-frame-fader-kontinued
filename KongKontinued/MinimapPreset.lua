local N, A = ...
local Preset = {}
A.MinimapPreset = Preset

local roundMask = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local maskPattern = "Interface\\AddOns\\" .. N .. "\\Textures\\PresetMinimap\\%03d.tga"
local proxy, owner, priorMask, appliedPercent, failed, restoring

local function CanSetMask(region)
    return KongKontinued_CanAccessFrame(region) and type(region.SetMaskTexture) == "function"
end

local function FindPriorMask(region)
    if not CanSetMask(region) then return end
    if C_AddOns.IsAddOnLoaded("Mappy") or C_AddOns.IsAddOnLoaded("SexyMap")
        or C_AddOns.IsAddOnLoaded("FarmHud") then return end

    -- Some clients or providers may expose a readable mask. Otherwise only
    -- take the stock round map, whose mask we can restore by shape.
    if type(region.GetMaskTexture) == "function" then
        local ok, mask = pcall(region.GetMaskTexture, region)
        if ok and not (issecretvalue and issecretvalue(mask))
            and (type(mask) == "string" or type(mask) == "number") then return mask end
    end
    if not GetMinimapShape and MinimapCluster and MinimapCluster.MinimapContainer
        and KongKontinued_GetFrameParent(region) == MinimapCluster.MinimapContainer then return roundMask end
end

function Preset.IsAvailable()
    return not failed and not restoring and (owner ~= nil or FindPriorMask(Minimap) ~= nil)
end

local function ApplyMask()
    local percent = math.floor(proxy:GetAlpha() * 100 + .5)
    if percent == appliedPercent then return end
    local mask = percent == 100 and priorMask or string.format(maskPattern, percent)
    if CanSetMask(owner) and pcall(owner.SetMaskTexture, owner, mask) then
        appliedPercent = percent
    else
        failed = true
        proxy:Hide()
    end
end

function Preset.Acquire()
    if failed or restoring then return end
    if not owner then
        local mask = FindPriorMask(Minimap)
        if not mask then return end
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
    proxy:SetScript("OnUpdate", nil)
    proxy:Hide()
end

function Preset.Release()
    if not owner then return end
    proxy:SetScript("OnUpdate", nil)
    proxy:Hide()
    if appliedPercent ~= 100 then
        if not CanSetMask(owner) or not pcall(owner.SetMaskTexture, owner, priorMask) then
            restoring = true
            return
        end
    end
    owner, priorMask, appliedPercent, failed, restoring = nil, nil, nil, nil, nil
end

function Preset.RetryRestore()
    if restoring then Preset.Release() end
end
