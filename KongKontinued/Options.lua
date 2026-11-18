local N, A = ...
local category, profileCategory, profileSetting, copySetting
local copyInitializer
local defaultsHiddenForKong = false

BINDING_NAME_KONGKONTINUED_CONFIG = "Open Options"

local function CanModifyOptions()
    return KongKontinued_Initialized and not InCombatLockdown()
end

local function CanConfigure()
    if not CanModifyOptions() then
        KongKontinued_Warning("Configuration is unavailable before login or during combat")
        return false
    end
    return KongKontinued_ConfirmLegacyDisabled()
end

local function CloseCompanionWindows()
    if KongKontinuedConfig and KongKontinuedConfig:IsShown() then
        KongKontinuedConfig:Hide()
    end
    if KongKontinuedLegacyImportWindow and KongKontinuedLegacyImportWindow:IsShown() then
        KongKontinuedLegacyImportWindow:Hide()
    end
end

function A.RefreshOptions()
    if profileSetting then profileSetting:NotifyUpdate() end
    if copySetting then copySetting:NotifyUpdate() end
    if copyInitializer and SettingsPanel:IsShown() then
        local row = SettingsPanel:GetSettingsList().ScrollBox:FindFrame(copyInitializer)
        if row then row:EvaluateState() end
    end
    if A.RefreshPresetOptions then A.RefreshPresetOptions() end
end

function A.SetFadingFromOptions(enabled)
    if not CanConfigure() or enabled == KongKontinued_Settings.enabled then return end
    if enabled then KongKontinued_EnableCommandHandler()
    else KongKontinued_DisableCommandHandler() end
end

local function OpenCompanion(show)
    if not CanConfigure() then return end
    if not C_AddOns.LoadAddOn("KongKontinuedConfig") then
        KongKontinued_Warning("Kong Kontinued Config is disabled or not installed")
        return
    end
    KongKontinued_InvalidateProfileDialogs()
    HideUIPanel(SettingsPanel)
    CloseCompanionWindows()
    show()
end

function A.ShowAdvancedConfig(region)
    OpenCompanion(function() KongKontinuedConfig_Show(region) end)
end

function A.ShowLegacyImport()
    OpenCompanion(function() KongKontinuedConfig_ShowLegacyImport() end)
end

function A.ShowOptions()
    if not CanConfigure() then return end
    if not category then
        KongKontinued_Warning("Kong Kontinued Options is not available yet")
        return
    end
    CloseCompanionWindows()
    A.RefreshOptions()
    Settings.OpenToCategory(category:GetID())
end

local function ConfigureInitializer(initializer)
    initializer:AddModifyPredicate(CanModifyOptions)
    initializer:AddEvaluateStateFrameEvent("PLAYER_REGEN_DISABLED")
    initializer:AddEvaluateStateFrameEvent("PLAYER_REGEN_ENABLED")
end

local function GetProfileOptions(copyFrom)
    local names = {}
    for name in pairs(KongKontinued_Profiles) do names[#names + 1] = name end
    table.sort(names)
    local options = Settings.CreateControlTextContainer()
    if copyFrom then options:Add("", "Select a source profile") end
    for _, name in ipairs(names) do
        if not copyFrom or name ~= KongKontinued_Settings.profile then options:Add(name, name) end
    end
    return options:GetData()
end

local function IsKongCategory()
    local selected = SettingsPanel:GetCurrentCategory()
    return selected == category or selected == profileCategory
end

local function UpdateDefaultsButton()
    local button = SettingsPanel:GetSettingsList().Header.DefaultsButton
    if IsKongCategory() then
        defaultsHiddenForKong = true
        button:Hide()
    elseif defaultsHiddenForKong then
        defaultsHiddenForKong = false
        if not SettingsPanel.SearchBox:HasText() then button:Show() end
    end
end

local function RegisterOptions()
    if category then return end
    local title = "Kong Frame Fader Kontinued"
    category = Settings.RegisterCanvasLayoutCategory(A.CreatePresetOptions(title), title)
    local layout
    profileCategory, layout = Settings.RegisterVerticalLayoutSubcategory(category, "Profile")

    profileSetting = Settings.RegisterProxySetting(profileCategory, N .. "_PROFILE",
        Settings.VarType.String, "Current profile", Settings.CannotDefault,
        function() return KongKontinued_Settings.profile end,
        function(name)
            if CanConfigure() and name ~= KongKontinued_Settings.profile then
                A.ProfileCommandHandler("load", name)
            end
            C_Timer.After(0, A.RefreshOptions)
        end)
    ConfigureInitializer(Settings.CreateDropdown(profileCategory, profileSetting, function() return GetProfileOptions(false) end,
        "Select an account-wide profile for this character"))

    local add = CreateSettingsButtonInitializer("New profile", "Add Profile",
        A.ShowAddProfile, "Create and select an empty profile with a new name", true)
    ConfigureInitializer(add)
    layout:AddInitializer(add)

    copySetting = Settings.RegisterProxySetting(profileCategory, N .. "_COPY_PROFILE",
        Settings.VarType.String, "Copy from", Settings.CannotDefault,
        function() return "" end,
        function(name)
            if name ~= "" then A.ShowCopyProfile(name) end
            C_Timer.After(0, A.RefreshOptions)
        end)
    copyInitializer = Settings.CreateDropdown(profileCategory, copySetting, function() return GetProfileOptions(true) end,
        "Replace the selected profile's configuration with an independent copy of another profile after confirmation")
    ConfigureInitializer(copyInitializer)
    copyInitializer:AddModifyPredicate(function()
        for name in pairs(KongKontinued_Profiles) do
            if name ~= KongKontinued_Settings.profile then return true end
        end
        return false
    end)

    local import = CreateSettingsButtonInitializer("Profile import", "Import Legacy Profiles",
        A.ShowLegacyImport, "Preview incoming and destination profile names before copying or replacing legacy settings", true)
    ConfigureInitializer(import)
    layout:AddInitializer(import)

    local reset = CreateSettingsButtonInitializer("Profile configuration", "Reset Profile",
        A.ResetCommandHandler, "Permanently clear all frames, fade settings, conditions and groups from the selected profile", true)
    ConfigureInitializer(reset)
    layout:AddInitializer(reset)

    Settings.RegisterAddOnCategory(category)
    -- Retail exposes one shared Defaults button, with no per-category opt-out.
    -- Hide it only for Kong, including when search clearing tries to show it.
    SettingsPanel:GetSettingsList().Header.DefaultsButton:HookScript("OnShow", function(button)
        if IsKongCategory() then
            defaultsHiddenForKong = true
            button:Hide()
        end
    end)
    SettingsPanel:HookScript("OnShow", A.RefreshOptions)
    hooksecurefunc(SettingsPanel, "DisplayCategory", function()
        UpdateDefaultsButton()
        if IsKongCategory() then
            CloseCompanionWindows()
            A.RefreshOptions()
        end
    end)
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        self:UnregisterEvent("PLAYER_LOGIN")
        RegisterOptions()
    elseif event == "PLAYER_REGEN_DISABLED" then
        KongKontinued_InvalidateProfileDialogs()
    end
end)
