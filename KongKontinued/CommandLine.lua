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
local HELP_COMMANDS = "|cFFBBBBFFKong Frame Fader Kontinued|r commands ( |cFF33FF99/kong|r ):"
local HELP_TOGGLE = "|cFF33FF99enable / disable / toggle|r: enables or disables fading of the user interface."
local HELP_PROFILE = "|cFF33FF99profile|r: manages saved Kong configurations and allows for configuration sharing between characters."
local HELP_IMPORT = "|cFF33FF99import|r: previews and imports legacy Kong SavedVariables"
local HELP_ADVANCED = "|cFF33FF99advanced|r: opens Advanced Config"
local PROFILE_LOADED = "Profile %q loaded."
local NOW_USING_PROFILE = "Now using profile %q."
local PROFILE_ALREADY_EXISTS = "Profile %q already exists."
local INVALID_COMMAND = " command unknown (Type |cFF33FF99/kong help|r for help)."
local UNKNOWN_OPTION = "Unknown option: %q (Type |cFF33FF99/kong %s|r for help)."
local PROFILE_NAME_REQUIRED = "Profile name required."
local NO_SUCH_PROFILE = "Profile %q does not exist. Use |cFF33FF99/kong profile list|r to see a list of available profiles."

local function CanModifyProfiles()
	if not KongKontinued_Initialized or InCombatLockdown() then
		KongKontinued_Warning("Profile changes are unavailable before login or during combat")
		return false
	end
	if (KongKontinuedConfig and KongKontinuedConfig:IsShown())
		or (KongKontinuedLegacyImportWindow and KongKontinuedLegacyImportWindow:IsShown()) then
		KongKontinued_Warning("Close Advanced Config and legacy import before changing profiles")
		return false
	end
	return KongKontinued_ConfirmLegacyDisabled()
end

function A.NormalizeProfileName(name)
	if type(name) ~= "string" or not name:find("%S") then return nil, "Profile name cannot be empty" end
	if name:find("%c") then return nil, "Profile name cannot contain control characters" end
	name = name:match("^%s*(.-)%s*$"):lower():gsub("%s+", "_")
	if #name > 128 then return nil, "Profile name must be at most 128 bytes" end
	return name
end

local function CurrentProfileTarget()
	local name = KongKontinued_Settings.profile
	return {name = name, profile = KongKontinued_Profiles[name]}
end

local function IsCurrentTarget(target)
	return type(target) == "table" and target.name == KongKontinued_Settings.profile
		and target.profile == KongKontinued_Profiles[target.name]
end

function A.CreateProfile(name)
	if not CanModifyProfiles() then return end
	local normalized, err = A.NormalizeProfileName(name)
	if not normalized then KongKontinued_Error("%s", err); return end
	if KongKontinued_Profiles[normalized] then KongKontinued_Error(PROFILE_ALREADY_EXISTS, normalized); return end
	KongKontinued_Unload()
	KongKontinued_Settings.profile = normalized
	A.LoadSettings()
	if A.RefreshOptions then A.RefreshOptions() end
	KongKontinued_Info(NOW_USING_PROFILE, normalized)
	return normalized
end

local function UpdateAddProfileInput(editBox)
	local name = A.NormalizeProfileName(editBox:GetText())
	local button = editBox:GetParent():GetButton1()
	if name and not KongKontinued_Profiles[name] then button:Enable()
	else button:Disable() end
end

StaticPopupDialogs.KONGKONTINUED_ADD_PROFILE = {
	text = "Add an empty profile\n\nEnter a new name. Names use lowercase letters and spaces become underscores.",
	button1 = "Add Profile",
	button2 = CANCEL,
	hasEditBox = true,
	OnShow = function(self)
		self:GetEditBox():SetText("")
		UpdateAddProfileInput(self:GetEditBox())
	end,
	OnAccept = function(self, target)
		if not IsCurrentTarget(target) then
			KongKontinued_Warning("Current profile changed; no profile was added")
			return
		end
		A.CreateProfile(self:GetEditBox():GetText())
	end,
	OnHide = function(self) self:GetEditBox():SetText("") end,
	EditBoxOnTextChanged = UpdateAddProfileInput,
	EditBoxOnEnterPressed = function(self) self:GetParent():GetButton1():Click() end,
	EditBoxOnEscapePressed = function(self) self:GetParent():GetButton2():Click() end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
}

function A.ShowAddProfile()
	if not CanModifyProfiles() then return end
	StaticPopup_Show("KONGKONTINUED_ADD_PROFILE", nil, nil, CurrentProfileTarget())
end

local function CopyProfileData(source)
	return A.LegacyImport.CopyProfile(source, LibStub("KongKontinuedConditions").Parameters)
end

local function SameProfileData(left, right)
	if type(left) ~= type(right) then return false end
	if type(left) ~= "table" then return left == right end
	for key, value in pairs(left) do
		if not SameProfileData(value, right[key]) then return false end
	end
	for key in pairs(right) do if left[key] == nil then return false end end
	return true
end

StaticPopupDialogs.KONGKONTINUED_COPY_PROFILE = {
	text = "Copy from profile \"%s\" into \"%s\"?\n\nThis permanently replaces the destination's frames, fade settings, conditions and groups. Any characters using the destination profile will be affected.\n\nThe source profile stays unchanged. This cannot be undone.",
	button1 = "Copy Profile",
	button2 = CANCEL,
	OnAccept = function(self, target)
		if not CanModifyProfiles() then return end
		if not IsCurrentTarget(target) or KongKontinued_Profiles[target.sourceName] ~= target.source then
			KongKontinued_Warning("Profiles changed; no configuration was copied")
			return
		end
		local copy, err = CopyProfileData(target.source)
		if not copy then KongKontinued_Error("%s", err); return end
		if not SameProfileData(copy, target.snapshot) then
			KongKontinued_Warning("Source profile changed; no configuration was copied")
			return
		end
		KongKontinued_Unload()
		KongKontinued_Profiles[target.name] = copy
		A.LoadSettings()
		if A.RefreshOptions then A.RefreshOptions() end
		KongKontinued_Info("Copied profile %q into %q", target.sourceName, target.name)
	end,
	showAlert = 1,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
}

function A.ShowCopyProfile(sourceName)
	if not CanModifyProfiles() then return end
	local source = KongKontinued_Profiles[sourceName]
	if not source or sourceName == KongKontinued_Settings.profile
		or source == KongKontinued_Profiles[KongKontinued_Settings.profile] then
		KongKontinued_Warning("Select another existing profile to copy from")
		return
	end
	local snapshot, err = CopyProfileData(source)
	if not snapshot then KongKontinued_Error("%s", err); return end
	local target = CurrentProfileTarget()
	target.sourceName, target.source, target.snapshot = sourceName, source, snapshot
	StaticPopup_Show("KONGKONTINUED_COPY_PROFILE", sourceName, target.name, target)
end


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
		return A.CreateProfile(name)

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
			KongKontinued_Info("%s", name)
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
		KongKontinued_Info("Current profile is: %s", KongKontinued_Settings.profile)
		
	else
		KongKontinued_Error(UNKNOWN_OPTION, command, "profile")
	end
	if A.RefreshOptions then A.RefreshOptions() end
end


function A.ResetCommandHandler()
	if not KongKontinued_Initialized or InCombatLockdown() then
		KongKontinued_Warning("Profile reset is unavailable before login or during combat")
		return
	end
	if not KongKontinued_ConfirmLegacyDisabled() then return end
	local name = KongKontinued_Settings.profile
	StaticPopup_Show("KONGKONTINUED_RESET", name, nil, {
		name = name,
		profile = KongKontinued_Profiles[name],
	})
end


function KongKontinued_EnableCommandHandler()
	if not KongKontinued_Settings.enabled then
		A.Enable()
		KongKontinued_Info(ENABLED)
	else
		KongKontinued_Error(ALREADY_ENABLED)
	end
	if A.RefreshOptions then A.RefreshOptions() end
end


function KongKontinued_DisableCommandHandler()
	if KongKontinued_Settings.enabled then
		A.Disable()
		KongKontinued_Info(DISABLED)
	else
		KongKontinued_Error(ALREADY_DISABLED)
	end
	if A.RefreshOptions then A.RefreshOptions() end
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
		A.ShowOptions()
	elseif ( command == "advanced" ) then
		A.ShowAdvancedConfig()
	elseif ( KongKontinuedConfig and KongKontinuedConfig.frame:IsShown() ) then
		KongKontinued_Error("Advanced Config must be closed to issue /kong commands")
	elseif ( command == "import" ) then
		A.ShowLegacyImport()
	elseif ( command == "enable" ) then
		KongKontinued_EnableCommandHandler()
	elseif ( command == "disable" ) then
		KongKontinued_DisableCommandHandler()
	elseif ( command == "toggle" ) then
		KongKontinued_ToggleCommandHandler()
	elseif ( command == "profile" ) then
		if ( #args > 2 ) then
			local name = table.concat(args, args[2] == "create" and " " or "_", 3)
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
		print(HELP_ADVANCED)
	else
		KongKontinued_Error("%s", '"' .. command .. '"' .. INVALID_COMMAND)
	end
end


SLASH_KONGKONTINUED1 = "/kong"
SLASH_KONGKONTINUED2 = "/kongkontinued"
SlashCmdList["KONGKONTINUED"] = A.CommandHandler
