local	pairs, print, string, table
=		pairs, print, string, table
local	strsplit
=		strsplit
local N, A = ...


local CANNOT_DELETE_CURRENT_PROFILE = "Cannot delete the current profile. Use |cFF33FF99/kong profile reset|r to reset it."
local PROFILE_ALREADY_LOADED = "Profile %q is already the current profile."
local PROFILE_DELETED = "Profile %q deleted."
local HELP_PROFILE_COMMANDS = "|cFFBBBBFFKong Frame Fader Kontinued|r profile commands ( |cFF33FF99/kong profile|r ):"
local HELP_PROFILE_LOAD = "|cFF33FF99load <name>|r: loads the specified profile."
local HELP_PROFILE_CREATE = "|cFF33FF99create <name>|r: creates a new profile with the given name."
local HELP_PROFILE_DELETE = "|cFF33FF99delete <name>|r: deletes the specified profile."
local HELP_PROFILE_LIST = "|cFF33FF99list|r: lists all available profiles."
local HELP_PROFILE_CURRENT = "|cFF33FF99current|r: prints the current profile name."
local HELP_PROFILE_RESET = "|cFF33FF99reset|r: resets the current profile."
local ENABLED = "Enabled."
local ALREADY_ENABLED = "Already enabled."
local DISABLED = "Disabled."
local ALREADY_DISABLED = "Already disabled."
local NO_KONG_CONFIG = "Kong Kontinued Config is either disabled or not installed. Defaulting to command-line interface..."
local HELP_COMMANDS = "|cFFBBBBFFKong Frame Fader Kontinued|r commands ( |cFF33FF99/kong|r ):"
local HELP_TOGGLE = "|cFF33FF99enable / disable / toggle|r: enables or disables fading of the user interface."
local HELP_PROFILE = "|cFF33FF99profile|r: manages saved Kong configurations and allows for configuration sharing between characters."
local HELP_IMPORT = "|cFF33FF99import|r: previews and imports legacy Kong SavedVariables"
local PROFILE_LOADED = "Profile %q loaded."
local NOW_USING_PROFILE = "Now using profile %q."
local PROFILE_ALREADY_EXISTS = "Profile %q already exists."
local INVALID_COMMAND = " command unknown (Type |cFF33FF99/kong help|r for help)."
local UNKNOWN_OPTION = "Unknown option: %q (Type |cFF33FF99/kong %s|r for help)."
local PROFILE_NAME_REQUIRED = "Profile name required."
local NO_SUCH_PROFILE = "Profile %q does not exist. Use |cFF33FF99/kong profile list|r to see a list of available profiles."


function A.ProfileCommandHandler(command, name)
	if ( command == nil ) then
		print(HELP_PROFILE_COMMANDS)
		print(HELP_PROFILE_LOAD)
		print(HELP_PROFILE_CREATE)
		print(HELP_PROFILE_DELETE)
		print(HELP_PROFILE_LIST)
		print(HELP_PROFILE_CURRENT)
		print(HELP_PROFILE_RESET)
		
	elseif ( command == "create" ) then
		if ( name == nil ) then KongKontinued_Error(PROFILE_NAME_REQUIRED) return end
		if ( KongKontinued_Profiles[name] ~= nil ) then KongKontinued_Error(PROFILE_ALREADY_EXISTS, name) return end
		
		KongKontinued_Unload()
		KongKontinued_Settings.profile = name
		A.LoadSettings()
		KongKontinued_Info(NOW_USING_PROFILE, name)

	elseif ( command == "delete" ) then
		if ( name == nil ) then KongKontinued_Error(PROFILE_NAME_REQUIRED) return end
		if ( name == KongKontinued_Settings.profile ) then KongKontinued_Error(CANNOT_DELETE_CURRENT_PROFILE) return end
		if ( KongKontinued_Profiles[name] == nil ) then KongKontinued_Error(NO_SUCH_PROFILE, name) return end
		
		KongKontinued_Profiles[name] = nil
		KongKontinued_Info(PROFILE_DELETED, name)
		
	elseif ( command == "list" ) then
		local names = {}
		for name in pairs(KongKontinued_Profiles) do
			table.insert(names, name)
		end
		table.sort(names)
		for i, name in pairs(names) do
			KongKontinued_Info(name)
		end
		KongKontinued_Info(#names .. " profile(s)")
		
	elseif ( command == "load" ) then
		if ( name == nil ) then KongKontinued_Error(PROFILE_NAME_REQUIRED) return end
		if ( KongKontinued_Profiles[name] == nil ) then KongKontinued_Error(NO_SUCH_PROFILE, name) return end
		if ( name == KongKontinued_Settings.profile ) then KongKontinued_Error(PROFILE_ALREADY_LOADED, name) return end
		
		KongKontinued_Unload()
		KongKontinued_Settings.profile = name
		A.LoadSettings()
		KongKontinued_Info(PROFILE_LOADED, name)
		
	elseif ( command == "reset" ) then
		A.ResetCommandHandler()

	elseif ( command == "current" ) then
		KongKontinued_Info("Current profile is: " .. KongKontinued_Settings.profile)
		
	else
		KongKontinued_Error(UNKNOWN_OPTION, command, "profile")
	end
end


function A.ResetCommandHandler()
	StaticPopup_Show("KONGKONTINUED_RESET", KongKontinued_Settings.profile)
end


function KongKontinued_EnableCommandHandler()
	if not KongKontinued_Settings.enabled then
		A.Enable()
		KongKontinued_Info(ENABLED)
	else
		KongKontinued_Error(ALREADY_ENABLED)
	end
end


function KongKontinued_DisableCommandHandler()
	if KongKontinued_Settings.enabled then
		A.Disable()
		KongKontinued_Info(DISABLED)
	else
		KongKontinued_Error(ALREADY_DISABLED)
	end
end


function KongKontinued_ToggleCommandHandler()
	if KongKontinued_Settings.enabled then
		KongKontinued_DisableCommandHandler()
	else
		KongKontinued_EnableCommandHandler()
	end
end


function A.CommandHandler(args)
	local args = {strsplit(" ", string.lower(args))}
	local command = args[1]

	if ( command == nil or command == "" ) then
		if InCombatLockdown() then
			KongKontinued_Warning("Configuration cannot be opened during combat")
			return
		end
		if ( C_AddOns.LoadAddOn("KongKontinuedConfig") ) then
			KongKontinuedConfig_Show()
		else
			KongKontinued_Warning(NO_KONG_CONFIG)
			print(HELP_COMMANDS)
			print(HELP_TOGGLE)
			print(HELP_PROFILE)
			print(HELP_IMPORT)
		end
	elseif ( KongKontinuedConfig and KongKontinuedConfig.frame:IsShown() ) then
		KongKontinued_Error("The config screen must be closed to issue /kong commands.")
	elseif ( command == "import" ) then
		if InCombatLockdown() then
			KongKontinued_Warning("Legacy import cannot be opened during combat")
		elseif not KongKontinued_ConfirmLegacyDisabled() then
			return
		elseif C_AddOns.LoadAddOn("KongKontinuedConfig") then
			KongKontinuedConfig_ShowLegacyImport()
		else
			KongKontinued_Warning(NO_KONG_CONFIG)
		end
	elseif ( command == "enable" ) then
		KongKontinued_EnableCommandHandler()
	elseif ( command == "disable" ) then
		KongKontinued_DisableCommandHandler()
	elseif ( command == "toggle" ) then
		KongKontinued_ToggleCommandHandler()
	elseif ( command == "profile" ) then
		if ( #args > 2 ) then
			local name = table.concat(args, "_", 3)
			A.ProfileCommandHandler(args[2], name)
		else
			A.ProfileCommandHandler(args[2])
		end
	elseif ( command == "reset" ) then
		A.ResetCommandHandler()
	elseif ( command == "help" ) then
		print(HELP_COMMANDS)
		print(HELP_TOGGLE)
		print(HELP_PROFILE)
		print(HELP_IMPORT)
	else
		KongKontinued_Error('"' .. command .. '"' .. INVALID_COMMAND)
	end
end


SLASH_KONGKONTINUED1 = "/kong"
SLASH_KONGKONTINUED2 = "/kongkontinued"
SlashCmdList["KONGKONTINUED"] = A.CommandHandler
