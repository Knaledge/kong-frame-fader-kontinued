local _, A = ...

local RESET_DIALOG = "KONGKONTINUED_RESET_PRESETS"
local advancedTitle = "Advanced config applied"
local advancedTooltip = "This frame already has an advanced config applied. Select 'Config' to edit it."
local sliderLabels = {"Idle", "Mouseover", "Combat"}
local sliderTop, entryTop, sectionGap = 63, 109, 38
local introTop, columnGutter, maxRowWidth = 54, 24, 264
local nativeBars = {
    {"MainActionBar", "Action Bar 1"},
    {"MultiBarBottomLeft", "Action Bar 2", "MultiBar1_IsVisible"},
    {"MultiBarBottomRight", "Action Bar 3", "MultiBar2_IsVisible"},
    {"MultiBarRight", "Action Bar 4", "MultiBar3_IsVisible"},
    {"MultiBarLeft", "Action Bar 5", "MultiBar4_IsVisible"},
    {"MultiBar5", "Action Bar 6", "MultiBar5_IsVisible"},
    {"MultiBar6", "Action Bar 7", "MultiBar6_IsVisible"},
    {"MultiBar7", "Action Bar 8", "MultiBar7_IsVisible"},
}
local actionBarSection = {title = "Action Bars", group = true}
local sections = {
    {title = "Objective Tracker", global = "ObjectiveTrackerFrame"},
    {title = "Minimap", global = "Minimap", getUnavailableReason = A.MinimapPreset.GetUnavailableReason},
    {title = "Player", global = "PlayerFrame", getUnavailableReason = A.FramePresetTransparency.GetUnavailableReason},
    {title = "Target", global = "TargetFrame", getUnavailableReason = A.FramePresetTransparency.GetUnavailableReason},
    {title = "Player Buffs", global = "BuffFrame"},
    actionBarSection,
    {title = "Chat Frames", group = true, getUnavailableReason = A.FramePresetTransparency.GetUnavailableReason},
}
local panel, body, intro, enableFading, enableFadingLabel, advanced, refreshing

local function IsPublic(value)
    return not (issecretvalue and issecretvalue(value))
end

local function FramePath(name)
    return "[" .. string.format("%q", name) .. "]"
end

local function FindEntries(section)
    local entries = {}
    if section.global then
        entries[1] = {name = section.global, title = section.title, region = _G[section.global],
            getUnavailableReason = section.getUnavailableReason}
    elseif section == actionBarSection then
        for _, bar in ipairs(nativeBars) do
            local name, title, predicate = unpack(bar)
            local region = _G[name]
            if name == "MainActionBar" and not KongKontinued_CanAccessFrame(region) then
                name, region = "MainMenuBar", MainMenuBar
            end
            if KongKontinued_CanAccessFrame(region) then
                local isEnabled = predicate and _G[predicate]
                local shown
                if isEnabled then shown = isEnabled()
                elseif not predicate then shown = true
                else shown = region:IsShown() end
                if IsPublic(shown) and shown then
                    entries[#entries + 1] = {name = name, title = title, region = region}
                end
            end
        end
    elseif FCF_GetChatWindowInfo then
        A.FramePresetTransparency.ForEachChatFrame(function(region, id)
            local name = "ChatFrame" .. id
            local title = FCF_GetChatWindowInfo(id)
            if not IsPublic(title) or type(title) ~= "string" or title == "" then title = "Chat " .. id end
            entries[#entries + 1] = {name = name, title = title, region = region,
                getUnavailableReason = section.getUnavailableReason}
        end)
    end
    return entries
end

local function FindSetting(entry, resolvedFrames)
    local setting = KongKontinued_Frames[entry.region]
    if setting then return setting end
    local path = FramePath(entry.name)
    -- A different saved path can refer to the same frame. Never seed a
    -- second configuration while that frame's existing rule is pending.
    for _, candidate in ipairs(KongKontinued_Settings.Frames) do
        if candidate.index == path then return candidate end
        local region = resolvedFrames and resolvedFrames[candidate]
        if region == nil then
            region = A.ResolveSavedFrame(candidate) or false
            if resolvedFrames then resolvedFrames[candidate] = region end
        end
        if region == entry.region then return candidate end
    end
end

local fadeKeys = {"secondsIn", "secondsOut", "secondsTillOut", "alphaIn", "alphaOut"}

local function ContainsOnlyOpacityChanges(setting, entry)
    if not setting.preset or setting.index ~= FramePath(entry.name)
        or setting.overrideAlpha or setting.hideAtZeroAlpha or #setting ~= 2 then return false end
    for _, group in pairs(KongKontinued_Settings.Groups) do
        if group[setting.index] ~= nil then return false end
    end
    local defaults = setting.TriggerDefaults
    for _, key in ipairs(fadeKeys) do
        if key ~= "alphaOut" and key ~= "alphaIn" and rawget(defaults, key) ~= nil then return false end
    end
    local expected = {"Frame has Mouse Focus", "Unit in Combat"}
    for i, name in ipairs(expected) do
        local trigger = setting[i]
        local root = trigger.Condition
        local condition = root and root.Parameters and root.Parameters[1]
        if not condition or root.name ~= "Condition" or #root.Parameters ~= 1
            or condition.name ~= name or (condition.Parameters and next(condition.Parameters)) then return false end
        for _, key in ipairs(fadeKeys) do
            if key ~= "alphaIn" and rawget(trigger, key) ~= nil then return false end
        end
    end
    return true
end

local function GetState(entry, resolvedFrames)
    local region = entry.region
    if not KongKontinued_Initialized or not KongKontinued_CanAccessFrame(region) then return "unavailable" end
    local setting = FindSetting(entry, resolvedFrames)
    local reason, source
    if entry.getUnavailableReason then reason, source = entry.getUnavailableReason(region) end
    if not setting then return reason and "unavailable" or "off", nil, reason, source end
    if KongKontinued_Frames[region] ~= setting then return "unavailable", nil, reason, source end
    if reason then return "suspended", setting, reason, source end
    if not ContainsOnlyOpacityChanges(setting, entry) then return "advanced", setting end
    return "on", setting
end

local function SetEnabled(entry, enabled)
    local state = GetState(entry)
    if enabled and state == "off" then
        KongKontinued_RegisterFrame(entry.region, FramePath(entry.name))
    elseif not enabled and state == "on" then
        KongKontinued_UnregisterFrame(entry.region)
    end
end

local function GetValues(setting)
    return setting.TriggerDefaults.alphaOut, setting[1].alphaIn, setting[2].alphaIn
end

local function SetOpacity(section, index, alpha)
    if refreshing or not A.CanModifyProfiles() then return end
    alpha = math.floor(alpha + .5) / 100
    for _, entry in ipairs(FindEntries(section)) do
        local state, setting = GetState(entry)
        if state == "on" then
            if index == 1 then setting.TriggerDefaults.alphaOut = alpha
            else setting[index - 1].alphaIn = alpha end
            A.RefreshPresetFade(entry.region)
        end
    end
    A.RefreshPresetOptions()
end

local function GetResetMode(entry, state, setting, individual)
    if not setting or not (individual or setting.preset == true) then return end
    if state == "on" or state == "advanced" then return "defaults" end
    if individual and state == "suspended" and not ContainsOnlyOpacityChanges(setting, entry) then return "clear" end
end

local function GetResetGroupImpact(entries)
    local selected = {}
    for _, candidate in ipairs(entries) do
        selected[candidate.setting.index] = true
    end

    local memberships, emptiedGroups = 0, 0
    for _, group in pairs(KongKontinued_Settings.Groups) do
        local removed, hasRemainingMember = 0, false
        for index in pairs(group) do
            if selected[index] then
                removed = removed + 1
            else
                hasRemainingMember = true
            end
        end
        memberships = memberships + removed
        if removed > 0 and not hasRemainingMember then emptiedGroups = emptiedGroups + 1 end
    end
    return memberships, emptiedGroups
end

local function ResetEntries(request)
    if not panel:IsVisible() or not A.CanModifyProfiles() or not A.IsCurrentProfileTarget(request.profile) then return end
    local current = FindEntries(request.section)
    local listed = {}
    for _, entry in ipairs(current) do listed[entry.region or entry.name] = true end
    for _, candidate in ipairs(request.entries) do
        local entry = candidate.entry
        local state, setting = GetState(entry)
        if not listed[entry.region] or setting ~= candidate.setting then return end
        if GetResetMode(entry, state, setting, request.individual) ~= candidate.mode then
            KongKontinued_Warning("Preset availability changed. Open Reset again to review the changes.")
            return
        end
    end
    local memberships, emptiedGroups = GetResetGroupImpact(request.entries)
    if memberships ~= request.memberships or emptiedGroups ~= request.emptiedGroups then
        KongKontinued_Warning("Mouseover groups changed. Open Reset again to review the changes.")
        return
    end
    for _, candidate in ipairs(request.entries) do
        local entry = candidate.entry
        local region = entry.region
        KongKontinued_UnregisterFrame(region, candidate.mode == "clear")
        if candidate.mode == "defaults" then KongKontinued_RegisterFrame(region, FramePath(entry.name)) end
    end
    A.RefreshPresetOptions()
end

StaticPopupDialogs[RESET_DIALOG] = {
    text = "%s%s",
    button1 = "Reset",
    button2 = CANCEL,
    OnAccept = function(_, request) ResetEntries(request) end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    showAlert = true,
}

local function RequestReset(section, entry)
    if not A.CanModifyProfiles() then return end
    local request = {
        section = section,
        entries = {},
        profile = A.CurrentProfileTarget(),
        individual = entry ~= nil or not section.group,
    }
    for _, candidate in ipairs(entry and {entry} or FindEntries(section)) do
        local state, setting = GetState(candidate)
        local mode = GetResetMode(candidate, state, setting, request.individual)
        if mode then
            table.insert(request.entries, {entry = candidate, setting = setting, mode = mode})
        end
    end
    if #request.entries > 0 then
        request.memberships, request.emptiedGroups = GetResetGroupImpact(request.entries)
        local groupWarning = ""
        if request.memberships > 0 then
            groupWarning = "\n\nThe selected frames will also be removed from their mouseover groups."
            if request.emptiedGroups > 0 then
                groupWarning = groupWarning .. " Groups that lose their last member will be deleted."
            end
        end
        local title = entry and entry.title or section.title
        local confirmation
        if request.entries[1].mode == "clear" then
            confirmation = "Clear Kong's settings for " .. title .. " in the current profile? The preset will stay disabled."
        else
            confirmation = "Reset " .. title .. " to preset defaults? This replaces the selected frames' settings in the current profile."
        end
        StaticPopup_Show(RESET_DIALOG, confirmation, groupWarning, request)
    end
end

local function CreateButton(parent, label, onClick)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(58, 21)
    button:SetText(label)
    button:SetScript("OnClick", onClick)
    return button
end

local function CreateLabel(parent, text, font)
    local label = parent:CreateFontString(nil, "ARTWORK", font or "GameFontHighlight")
    label:SetJustifyH("LEFT")
    label:SetText(text)
    return label
end

local function CreateCheckbox(parent, onClick)
    local checkbox = CreateFrame("CheckButton", nil, parent, "SettingsCheckboxTemplate")
    if checkbox.HoverBackground then
        checkbox.HoverBackground:ClearAllPoints()
        checkbox.HoverBackground:SetAllPoints(checkbox)
    end
    checkbox:SetScript("OnClick", onClick)
    return checkbox
end

local function ShowAdvancedConfigTooltip()
    Settings.InitTooltip(advancedTitle, advancedTooltip)
end

local function ShowMixedPresetTooltip()
    Settings.InitTooltip("Some presets enabled",
        "Some presets in this section are enabled. Select 'All' to enable the remaining available presets")
end

local function ShowUnavailableTooltip(frame)
    if not frame.reason then return end
    GameTooltip:SetOwner(frame, "ANCHOR_RIGHT")
    GameTooltip:SetText(frame.title)
    GameTooltip:AddLine(frame.reason, 1, 1, 1, true)
    if frame.source then GameTooltip:AddLine("Likely source: " .. frame.source, .75, .75, .75, true) end
    if frame.showConfigWarning then
        if frame.source then GameTooltip:AddLine(" ") end
        GameTooltip:AddLine("Config is still available, though transparency may behave unexpectedly", 1, 1, 1, true)
    end
    GameTooltip:Show()
end

local function HideUnavailableTooltip(frame)
    if GameTooltip:IsOwned(frame) then GameTooltip:Hide() end
end

local function CreateUnavailableTooltip(parent, checkbox, label)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetPoint("TOPLEFT", checkbox, "TOPLEFT")
    frame:SetPoint("BOTTOMLEFT", checkbox, "BOTTOMLEFT")
    frame:SetPoint("RIGHT", label, "RIGHT", 2, 0)
    frame:SetFrameLevel(checkbox:GetFrameLevel() + 1)
    frame:EnableMouse(true)
    frame:SetScript("OnEnter", ShowUnavailableTooltip)
    frame:SetScript("OnLeave", HideUnavailableTooltip)
    frame:SetScript("OnHide", HideUnavailableTooltip)
    frame:Hide()
    return frame
end

local function UpdateUnavailableTooltip(tooltip, title, reason, source, showConfigWarning)
    tooltip.title, tooltip.reason, tooltip.source = title, reason, source
    tooltip.showConfigWarning = showConfigWarning
    tooltip:SetShown(reason ~= nil)
    if reason and GameTooltip:IsOwned(tooltip) then ShowUnavailableTooltip(tooltip) end
end

local function CreateFrameRow(section)
    local row = CreateFrame("Frame", nil, section.frame)
    row:SetHeight(33)
    row.check = CreateCheckbox(row, function(check)
        if A.CanModifyProfiles() then SetEnabled(row.entry, check:GetChecked()) end
        A.RefreshPresetOptions()
    end)
    row.check:SetPoint("LEFT", row, "LEFT")
    row.reset = CreateButton(row, "Reset", function() RequestReset(section, row.entry) end)
    row.reset:SetPoint("RIGHT", row, "RIGHT")
    row.config = CreateButton(row, "Config", function() A.ShowAdvancedConfig(row.entry.region) end)
    row.config:SetPoint("RIGHT", row.reset, "LEFT", -3, 0)
    row.label = CreateLabel(row, "", "GameFontHighlightSmall")
    row.label:SetPoint("LEFT", row.check, "RIGHT", 2, 4)
    row.label:SetPoint("RIGHT", row.config, "LEFT", -3, 4)
    row.label:SetWordWrap(false)
    if section.getUnavailableReason then row.unavailableTooltip = CreateUnavailableTooltip(row, row.check, row.label) end
    row.status = CreateLabel(row, "", "GameFontHighlightSmall")
    row.status:SetTextColor(.65, .65, .65)
    row.status:SetPoint("TOPLEFT", row.label, "BOTTOMLEFT", 0, -1)
    row.status:SetWordWrap(false)
    return row
end

local function CreateSection(section)
    local frame = CreateFrame("Frame", nil, body)
    section.frame = frame
    section.titleLabel = CreateLabel(frame, section.title, "GameFontHighlightLarge")
    section.titleLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -5)
    section.reset = CreateButton(frame, "Reset", function() RequestReset(section) end)
    section.reset:SetPoint("TOPRIGHT", frame, "TOPRIGHT")
    if not section.group then
        section.config = CreateButton(frame, "Config", function()
            local entry = FindEntries(section)[1]
            if entry then A.ShowAdvancedConfig(entry.region) end
        end)
        section.config:SetPoint("RIGHT", section.reset, "LEFT", -4, 0)
    end
    section.checkLabel = CreateLabel(frame, section.group and "All" or "Enable", "GameFontHighlightSmall")
    section.check = CreateCheckbox(frame, function(check)
        local enabled = section.mixed:IsShown() or check:GetChecked()
        if A.CanModifyProfiles() then
            local entries = FindEntries(section)
            if section.group and section.getUnavailableReason then
                for _, entry in ipairs(entries) do
                    if select(3, GetState(entry)) then
                        A.RefreshPresetOptions()
                        return
                    end
                end
            end
            for _, entry in ipairs(entries) do SetEnabled(entry, enabled) end
        end
        A.RefreshPresetOptions()
    end)
    -- Reserve room for the label and optional Config button.
    section.check:SetPoint("RIGHT", section.reset, "LEFT", -110, 0)
    section.checkLabel:SetPoint("LEFT", section.check, "RIGHT", 1, 0)
    if section.getUnavailableReason then section.unavailableTooltip = CreateUnavailableTooltip(frame, section.check, section.checkLabel) end
    section.mixed = section.check:CreateTexture(nil, "OVERLAY")
    section.mixed:SetColorTexture(.82, .82, .82, 1)
    section.mixed:SetSize(10, 2)
    section.mixed:SetPoint("CENTER")
    section.mixed:Hide()
    local divider = frame:CreateTexture(nil, "ARTWORK")
    divider:SetAtlas("Options_HorizontalDivider")
    divider:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -26)
    divider:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -26)
    divider:SetHeight(2)

    section.sliders, section.rows = {}, {}
    for index, label in ipairs(sliderLabels) do
        local sliderIndex = index
        local control = CreateFrame("Frame", nil, frame, "MinimalSliderWithSteppersTemplate")
        control:Init(0, 0, 100, 100)
        control:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged, function(_, value)
            SetOpacity(section, sliderIndex, value)
        end, control)
        control.label = CreateLabel(frame, label, "GameFontHighlightSmall")
        control.label:SetJustifyH("CENTER")
        control.label:SetPoint("BOTTOM", control, "TOP", 0, 2)
        if control.Slider.SetNarrationLabelRegion then control.Slider:SetNarrationLabelRegion(control.label) end
        section.sliders[index] = control
    end
    section.status = CreateLabel(frame, "", "GameFontHighlightSmall")
    section.status:SetTextColor(.65, .65, .65)
    section.status:SetJustifyH("CENTER")
    section.status:SetPoint("TOP", frame, "TOP", 0, -entryTop)
end

function A.RefreshPresetOptions()
    if refreshing or not panel or not panel:IsVisible() then return end
    local width = body:GetWidth() - 24
    if width <= 0 then return end
    refreshing = true
    local locked = InCombatLockdown()
    local usable = KongKontinued_Initialized and not locked
    enableFading:SetEnabled(usable)
    enableFading:SetChecked(KongKontinued_Initialized and KongKontinued_Settings.enabled)
    enableFadingLabel:SetAlpha(usable and 1 or .55)
    advanced:SetEnabled(usable)
    local _, introHeight = intro:GetSize()
    local y = math.max(introHeight, 16) + introTop + 17
    local resolvedFrames = {}
    for _, section in ipairs(sections) do
        if not locked then section.entries = FindEntries(section) end
        local entries = section.entries or {}
        local columnCount = width >= 440 and 2 or 1
        local columnWidth = (width - (columnCount - 1) * columnGutter) / columnCount
        local rowWidth = math.min(columnWidth, maxRowWidth)
        local sliderWidth = (width - 32) / 3
        local enabled, eligible, resettable, blocked = 0, 0, 0, 0
        local values, mixed = {}, {}
        local advancedConfig, unavailableReason, likelySource, showConfigWarning
        section.status:SetText("")
        if not section.group then section.config:SetEnabled(false) end
        for i, entry in ipairs(entries) do
            local state, setting, reason, source = GetState(entry, resolvedFrames)
            if state == "on" or state == "off" then eligible = eligible + 1 end
            local resetMode = GetResetMode(entry, state, setting, not section.group)
            if resetMode then resettable = resettable + 1 end
            if state == "on" then
                enabled = enabled + 1
                local idle, hover, combat = GetValues(setting)
                for j, value in ipairs({idle, hover, combat}) do
                    if values[j] == nil then values[j] = value
                    elseif values[j] ~= value then mixed[j] = true end
                end
            end
            local status = state == "advanced" and advancedTitle
                or (state == "unavailable" or state == "suspended") and "Unavailable" or ""
            local configurable = usable and KongKontinued_CanAccessFrame(entry.region)
            if section.group then
                local row = section.rows[i]
                if not row then
                    row = CreateFrameRow(section)
                    section.rows[i] = row
                end
                row.entry = entry
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", section.frame, "TOPLEFT",
                    ((i - 1) % columnCount) * (columnWidth + columnGutter), -entryTop - math.floor((i - 1) / columnCount) * 33)
                row:SetWidth(rowWidth)
                row.label:SetText(entry.title:gsub("|", "||"))
                row.status:SetWidth(rowWidth - 32)
                row.status:SetText(status)
                row.check:SetChecked(state == "on" or state == "advanced" or state == "suspended")
                row.check:SetEnabled(usable and (state == "on" or state == "off"))
                row.check:SetTooltipFunc(state == "advanced" and ShowAdvancedConfigTooltip or nil)
                row.config:SetEnabled(configurable)
                row.reset:SetEnabled(usable and GetResetMode(entry, state, setting, true) ~= nil)
                if row.unavailableTooltip then
                    if reason then
                        blocked = blocked + 1
                        if blocked == 1 then unavailableReason = reason
                        elseif unavailableReason ~= reason then unavailableReason = "See the blocked chat frames below for details" end
                    end
                    row.check:SetAlpha(reason and .55 or 1)
                    row.label:SetAlpha(reason and .55 or 1)
                    UpdateUnavailableTooltip(row.unavailableTooltip, row.label:GetText() .. " preset unavailable",
                        reason, source, configurable and reason ~= nil)
                end
                row:Show()
            else
                advancedConfig = state == "advanced"
                section.status:SetText(status)
                section.config:SetEnabled(configurable)
                section.check:SetChecked(state == "on" or advancedConfig or state == "suspended")
                if section.unavailableTooltip then
                    if state == "unavailable" or state == "suspended" then
                        unavailableReason, likelySource = reason or "The frame configuration is unavailable", source
                        showConfigWarning = configurable
                    elseif advancedConfig then
                        unavailableReason = advancedTooltip
                    end
                end
            end
        end
        if section.group then section.check:SetChecked(blocked == 0 and eligible > 0 and enabled == eligible) end
        local partiallyEnabled = section.group and blocked == 0 and enabled > 0 and enabled < eligible
        section.mixed:SetShown(partiallyEnabled)
        section.check:SetTooltipFunc(advancedConfig and ShowAdvancedConfigTooltip
            or partiallyEnabled and ShowMixedPresetTooltip or nil)
        local canToggle = usable and eligible > 0 and blocked == 0
        section.check:SetEnabled(canToggle)
        local tooltip = section.unavailableTooltip
        if tooltip and section.group then
            section.check:SetAlpha(blocked > 0 and .55 or 1)
            section.checkLabel:SetAlpha(blocked > 0 and .55 or 1)
            local title = blocked == #entries and "All chat frames are blocked" or "Some chat frames are blocked"
            UpdateUnavailableTooltip(tooltip, title, unavailableReason)
        elseif tooltip then
            section.check:SetAlpha(canToggle and 1 or .55)
            section.checkLabel:SetAlpha(canToggle and 1 or .55)
            local title = advancedConfig and advancedTitle or section.title .. " preset unavailable"
            local reason = not canToggle and (unavailableReason
                or (locked and "Preset settings are unavailable during combat")
                or "The frame is unavailable") or nil
            UpdateUnavailableTooltip(tooltip, title, reason, not canToggle and likelySource or nil, showConfigWarning)
        end
        section.reset:SetEnabled(usable and resettable > 0)
        for i = #entries + 1, #section.rows do section.rows[i]:Hide() end
        for i, slider in ipairs(section.sliders) do
            local value = values[i]
            local display = mixed[i] and "Mixed" or value and string.format("%d%%", math.floor(value * 100 + .5)) or nil
            slider.label:SetText(display and (sliderLabels[i] .. "  " .. display) or sliderLabels[i])
            slider:SetWidth(sliderWidth)
            slider:ClearAllPoints()
            slider:SetPoint("TOPLEFT", section.frame, "TOPLEFT", (i - 1) * (sliderWidth + 16), -sliderTop)
            slider:SetValue(value and value * 100 or 0)
            slider:SetEnabled(usable and enabled > 0)
            slider.label:SetAlpha(usable and enabled > 0 and 1 or .5)
        end
        local height = entryTop + 3
        if section.group then height = height + math.ceil(#entries / columnCount) * 33
        elseif section.status:GetText() ~= "" then height = height + 14 end
        section.frame:ClearAllPoints()
        section.frame:SetPoint("TOPLEFT", body, "TOPLEFT", 12, -y)
        section.frame:SetWidth(width)
        section.frame:SetHeight(height)
        y = y + height + sectionGap
    end
    body:SetHeight(y)
    refreshing = false
end

function A.CreatePresetOptions(title)
    panel = CreateFrame("Frame")
    panel:Hide()
    local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -40)
    scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -30, 8)
    local heading = CreateLabel(panel, title, "GameFontNormalHuge")
    heading:SetPoint("TOPLEFT", panel, "TOPLEFT", 20, -8)
    body = CreateFrame("Frame", nil, scroll)
    body:SetSize(1, 1)
    scroll:SetScrollChild(body)

    enableFading = CreateCheckbox(body, function(check)
        A.SetFadingFromOptions(not not check:GetChecked())
        A.RefreshPresetOptions()
    end)
    enableFading:SetTooltipFunc(function()
        Settings.InitTooltip("Enable UI fading", "Enable fading for this character using the selected profile")
    end)
    enableFading:SetPoint("TOPLEFT", body, "TOPLEFT", 8, -5)
    enableFadingLabel = CreateLabel(body, "Enable UI fading")
    enableFadingLabel:SetPoint("LEFT", enableFading, "RIGHT", 3, 0)
    advanced = CreateButton(body, "Advanced Config", function() A.ShowAdvancedConfig() end)
    advanced:SetWidth(122)
    advanced:SetPoint("TOPRIGHT", body, "TOPRIGHT", -12, -9)

    intro = CreateLabel(body, "Use these presets to get started with frame fading. Each preset sets up the rules you can fine-tune in Advanced Config.", "GameFontHighlightSmall")
    intro:SetPoint("TOPLEFT", body, "TOPLEFT", 12, -introTop)
    intro:SetPoint("TOPRIGHT", body, "TOPRIGHT", -12, -introTop)
    intro:SetWordWrap(true)
    for _, section in ipairs(sections) do CreateSection(section) end
    scroll:SetScript("OnSizeChanged", function(_, width)
        if width > 0 then body:SetWidth(width) end
        A.RefreshPresetOptions()
    end)
    panel:SetScript("OnShow", A.RefreshPresetOptions)
    panel:SetScript("OnHide", function() StaticPopup_Hide(RESET_DIALOG) end)
    panel:RegisterEvent("PLAYER_REGEN_DISABLED")
    panel:RegisterEvent("PLAYER_REGEN_ENABLED")
    panel:RegisterEvent("UPDATE_CHAT_WINDOWS")
    panel:RegisterEvent("ACTIONBAR_PAGE_CHANGED")
    panel:RegisterEvent("CVAR_UPDATE")
    panel:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_DISABLED" then StaticPopup_Hide(RESET_DIALOG) end
        A.RefreshPresetOptions()
    end)
    return panel
end
