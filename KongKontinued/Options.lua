local N, A = ...
local category, enabledSetting, profileSetting
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
    if enabledSetting then enabledSetting:NotifyUpdate() end
    if profileSetting then profileSetting:NotifyUpdate() end
end

local function OpenCompanion(show)
    if not CanConfigure() then return end
    if not C_AddOns.LoadAddOn("KongKontinuedConfig") then
        KongKontinued_Warning("Kong Kontinued Config is disabled or not installed")
        return
    end
    HideUIPanel(SettingsPanel)
    CloseCompanionWindows()
    show()
end

function A.ShowAdvancedConfig()
    OpenCompanion(function() KongKontinuedConfig_Show() end)
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

local function GetProfileOptions()
    local names = {}
    for name in pairs(KongKontinued_Profiles) do names[#names + 1] = name end
    table.sort(names)
    local options = Settings.CreateControlTextContainer()
    for _, name in ipairs(names) do options:Add(name, name) end
    return options:GetData()
end

local function UpdateDefaultsButton()
    local button = SettingsPanel:GetSettingsList().Header.DefaultsButton
    if SettingsPanel:GetCurrentCategory() == category then
        defaultsHiddenForKong = true
        button:Hide()
    elseif defaultsHiddenForKong then
        defaultsHiddenForKong = false
        if not SettingsPanel.SearchBox:HasText() then button:Show() end
    end
end

local function RegisterOptions()
    if category then return end
    local layout
    category, layout = Settings.RegisterVerticalLayoutCategory("Kong Frame Fader Kontinued")

    enabledSetting = Settings.RegisterProxySetting(category, N .. "_ENABLED",
        Settings.VarType.Boolean, "Enable UI fading", Settings.CannotDefault,
        function() return KongKontinued_Settings.enabled end,
        function(value)
            if CanConfigure() then
                if value then KongKontinued_EnableCommandHandler()
                else KongKontinued_DisableCommandHandler() end
            end
            -- Settings broadcasts the requested value after this setter returns.
            -- Refresh afterward as well, so a rejected change displays actual state.
            C_Timer.After(0, A.RefreshOptions)
        end)
    ConfigureInitializer(Settings.CreateCheckbox(category, enabledSetting,
        "Enable fading for this character using the selected profile"))

    profileSetting = Settings.RegisterProxySetting(category, N .. "_PROFILE",
        Settings.VarType.String, "Current profile", Settings.CannotDefault,
        function() return KongKontinued_Settings.profile end,
        function(name)
            if CanConfigure() and name ~= KongKontinued_Settings.profile then
                A.ProfileCommandHandler("load", name)
            end
            C_Timer.After(0, A.RefreshOptions)
        end)
    ConfigureInitializer(Settings.CreateDropdown(category, profileSetting, GetProfileOptions,
        "Select an account-wide profile for this character"))

    local import = CreateSettingsButtonInitializer("Legacy profiles", "Import Legacy Profiles",
        A.ShowLegacyImport, "Preview and import legacy Kong SavedVariables", true)
    ConfigureInitializer(import)
    layout:AddInitializer(import)

    local advanced = CreateSettingsButtonInitializer("Frame and rule editor", "Advanced Config",
        A.ShowAdvancedConfig, "Pick UI frames and edit their fade settings, conditions and groups", true)
    ConfigureInitializer(advanced)
    layout:AddInitializer(advanced)

    local reset = CreateSettingsButtonInitializer("Profile configuration", "Reset Profile",
        A.ResetCommandHandler, "Permanently clear all frames, fade settings, conditions and groups from the selected profile", true)
    ConfigureInitializer(reset)
    layout:AddInitializer(reset)

    Settings.RegisterAddOnCategory(category)
    -- Retail exposes one shared Defaults button, with no per-category opt-out.
    -- Hide it only for Kong, including when search clearing tries to show it.
    SettingsPanel:GetSettingsList().Header.DefaultsButton:HookScript("OnShow", function(button)
        if SettingsPanel:GetCurrentCategory() == category then
            defaultsHiddenForKong = true
            button:Hide()
        end
    end)
    SettingsPanel:HookScript("OnShow", A.RefreshOptions)
    hooksecurefunc(SettingsPanel, "DisplayCategory", function(_, selectedCategory)
        UpdateDefaultsButton()
        if selectedCategory == category then
            CloseCompanionWindows()
            A.RefreshOptions()
        end
    end)
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    RegisterOptions()
end)
