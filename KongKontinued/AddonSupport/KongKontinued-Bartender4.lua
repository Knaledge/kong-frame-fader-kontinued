local _, A = ...

local Support = {
    noticeTitle = "Bartender4 detected",
    noticeText = "Bartender4 has its own opacity and fade settings. To use Kong's Idle, Mouseover, and Combat settings for a bar:\n"
        .. "• Set the bar's Bartender4 opacity to 100%\n"
        .. "• Turn off Bartender4 fading for that bar\n"
        .. "• Enable the bar's preset in Kong\n\n"
        .. "If Bartender4 takes over opacity, Kong blocks the preset and keeps your settings. An enabled preset takes effect again when the bar is eligible.",
    disabledReason = "This bar is disabled in Bartender4",
}
A.ActionBarPresetSupport = Support

local actionBars

local function IsPublic(value)
    return not (issecretvalue and issecretvalue(value))
end

local function GetActionBars()
    if actionBars then return actionBars end
    if not Bartender4 or not Bartender4.GetModule then return end
    actionBars = Bartender4:GetModule("ActionBars", true)
    return actionBars
end

function Support.IsActive()
    return GetActionBars() ~= nil
end

function Support.OwnsBar(bar)
    local module = GetActionBars()
    if not module or not module.actionbars or not KongKontinued_CanAccessFrame(bar) then return false end
    return IsPublic(bar.module) and bar.module == module and IsPublic(bar.id) and module.actionbars[tonumber(bar.id)] == bar
end

local function GetBarDisplayGroup(id)
    if id == 2 then return 2 end -- Bonus Action Bar
    if id >= 7 and id <= 10 then return 3 end -- Class Bars
    return 1
end

local function GetDisplayBarOrder(module)
    local displayNumbers = module.BLIZZARD_BAR_MAP
    if not (Bartender4.Features and Bartender4.Features.MainlineBarLayout and displayNumbers) then
        return module.LIST_ACTIONBARS
    end

    local ids = {}
    for index, id in ipairs(module.LIST_ACTIONBARS) do ids[index] = id end
    table.sort(ids, function(left, right)
        local leftGroup, rightGroup = GetBarDisplayGroup(left), GetBarDisplayGroup(right)
        if leftGroup ~= rightGroup then return leftGroup < rightGroup end
        local leftNumber, rightNumber = displayNumbers[left] or left, displayNumbers[right] or right
        if leftNumber ~= rightNumber then return leftNumber < rightNumber end
        return left < right
    end)
    return ids
end

function Support.ForEachBar(callback, sortForDisplay)
    local module = GetActionBars()
    if not module or not module.actionbars or not module.LIST_ACTIONBARS then return end
    local ids = sortForDisplay and GetDisplayBarOrder(module) or module.LIST_ACTIONBARS
    for _, id in ipairs(ids) do
        local bar = module.actionbars[id]
        -- Bartender4 creates frames only for bars it has enabled at least once this session.
        local name = "BT4Bar" .. id
        local region = KongKontinued_CanAccessFrame(bar) and _G[name] == bar and bar or nil
        local enabled = bar ~= nil and not bar.disabled
        callback(region, name, bar and bar.name or module:GetBarName(id), enabled)
    end
end

function Support.GetUnavailableReason(bar)
    if bar.disabled then return Support.disabledReason end
    if bar.unlocked then return "Lock the bars in Bartender4 to use Kong fading" end
    local fade = bar:GetAttribute("fade")
    if not IsPublic(fade) then return "Kong can't read the bar's fade state" end
    if bar:GetFadeOut() or fade or bar.faded then
        return "Turn off Bartender4 fading for this bar to use Kong fading"
    end
    if bar:GetConfigAlpha() ~= 1 then
        return "Set this bar's Bartender4 opacity to 100% to use Kong fading"
    end
end

function Support.IsBarDisabled(bar)
    return bar.disabled == true
end

function Support.ObserveBarChanges()
    local prototype = Bartender4 and Bartender4.Bar and Bartender4.Bar.prototype
    local module = GetActionBars()
    local transparency = A.FramePresetTransparency
    Support.ObserveBarChanges = nil
    if not hooksecurefunc then return end

    -- ApplyConfig and the secure fade driver can legitimately reapply the base opacity.
    if prototype and type(prototype.SetConfigAlpha) == "function" then
        pcall(hooksecurefunc, prototype, "SetConfigAlpha", function(bar)
            if Support.OwnsBar(bar) and not bar.faded then
                transparency.OnNativeActionBarAlphaSet(bar, bar:GetConfigAlpha())
            end
        end)
    end

    local function OnBarStateChanged(owner, id)
        local bar = owner.actionbars[tonumber(id)]
        if Support.OwnsBar(bar) then
            transparency.OnNativeActionBarEnabledChanged(bar, not bar.disabled)
        end
    end
    for _, method in ipairs({"EnableBar", "DisableBar"}) do
        if type(module[method]) == "function" then
            pcall(hooksecurefunc, module, method, OnBarStateChanged)
        end
    end
end
