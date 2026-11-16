local AceGUI = LibStub("AceGUI-3.0")
local window, input, summary, activate, importButton, previewSignature

local function signature(plan)
    local names = {plan.selection or "", tostring(plan.enabled), tostring(plan.frames), tostring(plan.conditions)}
    for _, entry in ipairs(plan.profiles) do names[#names + 1] = entry.name end
    return table.concat(names, "\n")
end

local function invalidate()
    previewSignature = nil
    importButton:SetDisabled(true)
    activate:SetValue(false)
    activate:SetDisabled(true)
    summary:SetText("Preview the pasted data before importing")
end

local function preview()
    if not KongKontinued_ConfirmLegacyDisabled() then invalidate(); return end
    invalidate()
    local plan, err = KongKontinued_PreviewLegacyImport(input:GetText())
    if not plan then window:SetStatusText(err); return end
    local lines = {string.format("%d profiles, %d frames, %d conditions", #plan.profiles, plan.frames, plan.conditions)}
    for _, entry in ipairs(plan.profiles) do
        lines[#lines + 1] = string.format("%s -> %s", entry.source, entry.name)
    end
    if plan.selection then
        lines[#lines + 1] = "Optional selection: " .. plan.selection .. (plan.enabled and " (enabled)" or " (disabled)")
    end
    summary:SetText(table.concat(lines, "\n"))
    activate:SetDisabled(not plan.selection)
    previewSignature = signature(plan)
    importButton:SetDisabled(false)
    window:SetStatusText("Ready to copy profiles; existing profiles will be preserved")
    window:DoLayout()
end

local function close()
    input:SetText("")
    input:ClearFocus()
    invalidate()
end

function KongKontinuedConfig_ShowLegacyImport()
    if InCombatLockdown() then
        KongKontinued_Warning("Legacy import cannot be opened during combat")
        return
    end
    if not KongKontinued_ConfirmLegacyDisabled() then return end
    if KongKontinuedConfig and KongKontinuedConfig:IsShown() then KongKontinuedConfig:Hide() end
    if not window then
        window = AceGUI:Create("Frame")
        window:SetTitle("Kong Kontinued: Import Legacy Profiles")
        window:SetWidth(680)
        window:SetHeight(650)
        window:SetLayout("Flow")
        window.frame:SetFrameStrata("DIALOG")
        window:SetCallback("OnClose", close)
        local label = AceGUI:Create("Label")
        label:SetFullWidth(true)
        label:SetText("Paste account-wide Kong.lua SavedVariables (Kong_Profiles), plus optional character Kong.lua (Kong_Settings). Preview first. Import copies profiles without overwriting existing ones.")
        window:AddChild(label)
        input = AceGUI:Create("MultiLineEditBox")
        input:SetLabel("Legacy SavedVariables contents")
        input:SetNumLines(10)
        input:SetMaxLetters(0)
        input:SetFullWidth(true)
        input:DisableButton(true)
        input:SetCallback("OnTextChanged", function() invalidate(); window:SetStatusText("") end)
        window:AddChild(input)
        local previewButton = AceGUI:Create("Button")
        previewButton:SetText("Preview")
        previewButton:SetCallback("OnClick", preview)
        window:AddChild(previewButton)
        local scroll = AceGUI:Create("ScrollFrame")
        scroll:SetFullWidth(true)
        scroll:SetHeight(140)
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
        importButton:SetCallback("OnClick", function()
            if not previewSignature then return end
            if not KongKontinued_ConfirmLegacyDisabled() then invalidate(); return end
            local plan, err = KongKontinued_PreviewLegacyImport(input:GetText())
            if not plan then invalidate(); window:SetStatusText(err); return end
            if signature(plan) ~= previewSignature then
                preview()
                window:SetStatusText("Profiles changed since preview; review the updated names before importing")
                return
            end
            plan, err = KongKontinued_ImportLegacy(input:GetText(), activate:GetValue())
            if not plan then window:SetStatusText(err); return end
            KongKontinued_Info("Imported %d legacy profile(s)", #plan.profiles)
            window:Hide()
        end)
        window:AddChild(importButton)
        _G.KongKontinuedLegacyImportWindow = window.frame
        table.insert(UISpecialFrames, "KongKontinuedLegacyImportWindow")
        invalidate()
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
