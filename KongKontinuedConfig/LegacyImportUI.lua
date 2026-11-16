local AceGUI = LibStub("AceGUI-3.0")
local window, input, summary, activate, importButton, action, incoming, destination
local previewToken, previewPlan
local revision, sourceNames = 0, {}
local actions = {
    bulk = "Copy all profiles (preserve existing)",
    current = "Import into current profile",
    rename = "Rename current profile and import",
    separate = "Import selected as separate profile",
}

local function options()
    return {mode = action:GetValue(), source = incoming:GetValue(), name = destination:GetText()}
end

local function updateControls()
    local mode = action:GetValue()
    incoming:SetDisabled(mode == "bulk" or next(sourceNames) == nil)
    destination:SetDisabled(mode ~= "rename")
end

local function invalidate(clearSources)
    revision = revision + 1
    previewToken, previewPlan = nil, nil
    StaticPopup_Hide("KONGKONTINUED_IMPORT_REPLACE")
    importButton:SetDisabled(true)
    activate:SetValue(false)
    activate:SetDisabled(true)
    summary:SetText("Preview the pasted data and destination before importing")
    if clearSources then
        sourceNames = {}
        incoming:SetList(sourceNames)
        incoming:SetValue(nil)
    end
    updateControls()
end

local function preview()
    if not KongKontinued_ConfirmLegacyDisabled() then invalidate(); return end
    invalidate()
    local plan, err = KongKontinued_PreviewLegacyImport(input:GetText(), options())
    if not plan or not plan.token then
        window:SetStatusText(err or "Current profile is not initialized")
        return
    end
    sourceNames = {}
    for _, name in ipairs(plan.sources) do sourceNames[name] = name end
    incoming:SetList(sourceNames, plan.sources)
    incoming:SetValue(plan.source or plan.sourceSelection or plan.sources[1])
    local lines = {actions[plan.mode],
        string.format("%d profiles, %d frames, %d conditions", #plan.profiles, plan.frames, plan.conditions)}
    if plan.renameFrom then lines[#lines + 1] = "Current profile: " .. plan.renameFrom end
    for _, entry in ipairs(plan.profiles) do
        lines[#lines + 1] = "Incoming profile: " .. entry.source
        lines[#lines + 1] = "Destination profile: " .. entry.name
    end
    if plan.replaces then
        lines[#lines + 1] = "Replaces all configuration in the selected shared profile; character enabled state is retained"
        if plan.renameFrom then lines[#lines + 1] = "Characters selecting the old name will follow the renamed profile" end
    elseif plan.selection then
        activate:SetDisabled(false)
        activate:SetLabel("Switch to " .. plan.selection .. (plan.enabled and " (enabled)" or " (disabled)"))
    end
    summary:SetText(table.concat(lines, "\n"))
    previewPlan, previewToken = plan, plan.token
    importButton:SetText(plan.replaces and "Replace Profile..." or "Import Profiles")
    importButton:SetDisabled(false)
    updateControls()
    window:SetStatusText(plan.replaces and "Review both names; replacement requires confirmation" or "Ready to copy; existing profiles will be preserved")
    window:DoLayout()
end

local function commit(context)
    if context.revision ~= revision or context.token ~= previewToken then return end
    local plan, err = KongKontinued_ImportLegacy(context.text, context.activate, context.options, context.token)
    if not plan then
        invalidate()
        window:SetStatusText(err)
        return
    end
    KongKontinued_Info("Imported %d legacy profile(s)", #plan.profiles)
    window:Hide()
end

StaticPopupDialogs.KONGKONTINUED_IMPORT_REPLACE = {
    text = "%s\n\nThis permanently replaces all frames, fade settings, conditions and groups in the selected shared profile. Other characters using it are affected.\n\nThis cannot be undone.",
    button1 = "Replace Profile",
    button2 = CANCEL,
    OnAccept = function(self, context) commit(context) end,
    showAlert = 1,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

local function import()
    if not previewToken then return end
    if not KongKontinued_ConfirmLegacyDisabled() then invalidate(); return end
    local context = {
        revision = revision, token = previewToken, text = input:GetText(),
        activate = activate:GetValue() == true, options = options(),
    }
    if previewPlan.replaces then
        local entry = previewPlan.profiles[1]
        local description = string.format("Import incoming profile \"%s\" into \"%s\"?", entry.source, entry.name)
        if previewPlan.renameFrom then
            description = description .. string.format("\nRename current profile \"%s\" to \"%s\"", previewPlan.renameFrom, entry.name)
        end
        StaticPopup_Show("KONGKONTINUED_IMPORT_REPLACE", description, nil, context)
    else
        commit(context)
    end
end

local function close()
    input:SetText("")
    input:ClearFocus()
    destination:SetText("")
    invalidate(true)
end

function KongKontinuedConfig_ShowLegacyImport()
    if not KongKontinued_Initialized or InCombatLockdown() then
        KongKontinued_Warning("Legacy import is unavailable before login or during combat")
        return
    end
    if not KongKontinued_ConfirmLegacyDisabled() then return end
    KongKontinued_InvalidateProfileDialogs()
    if KongKontinuedConfig and KongKontinuedConfig:IsShown() then KongKontinuedConfig:Hide() end
    if not window then
        window = AceGUI:Create("Frame")
        window:SetTitle("Kong Kontinued: Import Legacy Profiles")
        window:SetWidth(720)
        window:SetHeight(800)
        window:SetLayout("Flow")
        window.frame:SetFrameStrata("DIALOG")
        window:SetCallback("OnClose", close)
        local label = AceGUI:Create("Label")
        label:SetFullWidth(true)
        label:SetText("Paste legacy Kong_Profiles data, plus optional Kong_Settings. Choose an import action and Preview. Replacing a shared profile requires confirmation.")
        window:AddChild(label)
        input = AceGUI:Create("MultiLineEditBox")
        input:SetLabel("Legacy SavedVariables contents")
        input:SetNumLines(6)
        input:SetMaxLetters(0)
        input:SetFullWidth(true)
        input:DisableButton(true)
        input:SetCallback("OnTextChanged", function() invalidate(true); window:SetStatusText("") end)
        window:AddChild(input)
        action = AceGUI:Create("Dropdown")
        action:SetLabel("Import action")
        action:SetFullWidth(true)
        action:SetList(actions, {"bulk", "current", "rename", "separate"})
        action:SetValue("bulk")
        action:SetCallback("OnValueChanged", function() invalidate() end)
        window:AddChild(action)
        incoming = AceGUI:Create("Dropdown")
        incoming:SetLabel("Incoming profile")
        incoming:SetFullWidth(true)
        incoming:SetCallback("OnValueChanged", function() invalidate() end)
        window:AddChild(incoming)
        destination = AceGUI:Create("EditBox")
        destination:SetLabel("New name for current profile (rename action)")
        destination:SetFullWidth(true)
        destination:DisableButton(true)
        destination:SetCallback("OnTextChanged", function() invalidate() end)
        window:AddChild(destination)
        local previewButton = AceGUI:Create("Button")
        previewButton:SetText("Preview")
        previewButton:SetCallback("OnClick", preview)
        window:AddChild(previewButton)
        local scroll = AceGUI:Create("ScrollFrame")
        scroll:SetFullWidth(true)
        scroll:SetHeight(110)
        scroll:SetLayout("Flow")
        window:AddChild(scroll)
        summary = AceGUI:Create("Label")
        summary:SetFullWidth(true)
        scroll:AddChild(summary)
        activate = AceGUI:Create("CheckBox")
        activate:SetLabel("Switch this character to the imported selection")
        activate:SetFullWidth(true)
        window:AddChild(activate)
        importButton = AceGUI:Create("Button")
        importButton:SetText("Import Profiles")
        importButton:SetCallback("OnClick", import)
        window:AddChild(importButton)
        _G.KongKontinuedLegacyImportWindow = window.frame
        table.insert(UISpecialFrames, "KongKontinuedLegacyImportWindow")
        invalidate(true)
    end
    window:SetStatusText("")
    window:Show()
    input:SetFocus()
end

local watcher = CreateFrame("Frame")
watcher:RegisterEvent("PLAYER_REGEN_DISABLED")
watcher:SetScript("OnEvent", function()
    if window and window:IsShown() then
        window:Hide()
        KongKontinued_Warning("Legacy import closed for combat")
    end
end)
