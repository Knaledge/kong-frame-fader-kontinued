local	_G, assert, ipairs, math, next, pairs, pcall, print, setmetatable, string, table, tonumber, tostring, type, xpcall
=		_G, assert, ipairs, math, next, pairs, pcall, print, setmetatable, string, table, tonumber, tostring, type, xpcall
local	CreateFrame, debugstack, GetMouseFoci, GetMouseFocus, GetRealmName, GetTime, hooksecurefunc, IsAddOnLoaded, StaticPopup_Show, strsplit, UnitName, WOW_PROJECT_CLASSIC, WOW_PROJECT_ID, WOW_PROJECT_MAINLINE
=		CreateFrame, debugstack, GetMouseFoci, GetMouseFocus, GetRealmName, GetTime, hooksecurefunc, IsAddOnLoaded, StaticPopup_Show, strsplit, UnitName, WOW_PROJECT_CLASSIC, WOW_PROJECT_ID, WOW_PROJECT_MAINLINE


local N, A = ... -- Addon (N)ame, (A)ddon Table
local R = A.CLASSES -- Class (R)epository


local DUMMY_FRAME = CreateFrame("frame") -- used for references to avoid abundant rawget calls when dealing with dummy functions
local FADER = R.Fader.construct()
local HiddenFrames, PendingVisibility, PendingRestores = {}, {}, {}
local ConditionStates = setmetatable({}, {__mode = "k"})
local PresetOriginalAlpha = setmetatable({}, {__mode = "k"})
local ChatPresetRegions = {}

local function RememberChatPreset(region, index)
	if not index:match('^%["ChatFrame%d+"%]$') then return end
	ChatPresetRegions[region] = true
	if A.FramePresetTransparency then A.FramePresetTransparency.TrackChatFrame(region) end
end

local function HasPresetTransparencyGuard(region, setting)
	return setting and setting.preset and A.FramePresetTransparency and A.FramePresetTransparency.Handles(region)
end

local function IsPresetTransparencyBlocked(region, setting)
	return HasPresetTransparencyGuard(region, setting) and A.FramePresetTransparency.GetUnavailableReason(region) ~= nil
end

local function WriteGuardedFrameAlpha(fader, region, alpha)
	local setting = KongKontinued_Frames[region]
	return A.FramePresetTransparency.WriteAlpha(fader, region, alpha, setting and setting.preset, R.Fader.setAlpha)
end

local function SetFrameAlpha(region, alpha)
	local writer = A.FramePresetTransparency and A.FramePresetTransparency.Handles(region)
		and WriteGuardedFrameAlpha or R.Fader.setAlpha
	return writer(FADER, region, alpha)
end

local function RestoreOwnedPresetAlpha(region)
	if A.FramePresetTransparency then
		return A.FramePresetTransparency.RestoreOwnedAlpha(
			FADER, region, PresetOriginalAlpha[region], R.Fader.setAlpha)
	end
end

local function GetFadeEventRegion(region)
	if A.MinimapPreset and A.MinimapPreset.GetTarget() == region then return Minimap end
	return region
end

local function SetFrameShown(region, shown)
	if not R.Fader.canAccess(FADER, region) then
		PendingVisibility[region] = shown
		return
	end
	if region.CanChangeProtectedState then
		local allowed = region:CanChangeProtectedState()
		if (issecretvalue and issecretvalue(allowed)) or not allowed then
			PendingVisibility[region] = shown
			return
		end
	end
	PendingVisibility[region] = nil
	if shown then
		DUMMY_FRAME.Show(region)
		HiddenFrames[region] = nil
	else
		DUMMY_FRAME.Hide(region)
		HiddenFrames[region] = true
	end
end

function A.ApplyPendingVisibility()
	if A.MinimapPreset then A.MinimapPreset.RetryRestore() end
	if KongKontinued_Settings and KongKontinued_Settings.enabled then
		for region, setting in pairs(KongKontinued_Frames) do
			if setting.overrideAlpha then KongKontinued_OverrideAlpha(region, true) end
		end
	end
	for region, alpha in pairs(PendingRestores) do
		if IsPresetTransparencyBlocked(region, KongKontinued_Frames[region]) or SetFrameAlpha(region, alpha) then
			PendingRestores[region] = nil
		end
	end
	for region, shown in pairs(PendingVisibility) do
		local setting = KongKontinued_Frames[region]
		local alpha = R.Fader.getAlpha(FADER, region)
		if not IsPresetTransparencyBlocked(region, setting)
			and (shown or (setting and setting.hideAtZeroAlpha and (alpha == nil or alpha == 0))) then
			SetFrameShown(region, shown)
		else
			PendingVisibility[region] = nil
		end
	end
end

R.Fader.addListener(FADER, "FADE_STARTED", 
		function(obj, event, region, fromAlpha, toAlpha, duration, smoothing, startDelay, endDelay)
			region = GetFadeEventRegion(region)
			local setting = KongKontinued_Frames[region]
			PendingRestores[region] = nil
			PendingVisibility[region] = nil
			if ( setting and setting.hideAtZeroAlpha
				and (HiddenFrames[region] or R.Fader.getAlpha(FADER, region) == 0) ) then
				SetFrameShown(region, true)
			end
		end,
		{}
)
R.Fader.addListener(FADER, "FADE_FINISHED", 
		function(obj, event, region, toAlpha)
			local target = GetFadeEventRegion(region)
			if target ~= region then A.MinimapPreset.FinishFade() end
			region = target
			local setting = KongKontinued_Frames[region]
			local alpha = setting and setting.preset and region == Minimap and toAlpha
				or R.Fader.getAlpha(FADER, region)
			if ( setting and setting.hideAtZeroAlpha and (alpha == 0 or (alpha == nil and toAlpha == 0)) ) then
				SetFrameShown(region, false)
			end
		end,
		{}
)


BINDING_HEADER_KONGKONTINUED = "Kong Frame Fader Kontinued"
BINDING_NAME_KONGKONTINUED_ENABLE = "Enable UI Fading"
BINDING_NAME_KONGKONTINUED_DISABLE = "Disable UI Fading"
BINDING_NAME_KONGKONTINUED_TOGGLE = "Toggle UI Fading On/Off"
BINDING_NAME_KONGKONTINUED_CONFIG = "Open Config GUI"
local VERSION = "0.1.0-dev"

KongKontinued_Frames = {}
KongKontinued_Profiles = {}
KongKontinued_ProfileRenames = {}

local lastMouseFocus = nil
local lastMouseStart = nil
local mouseoverRegions, nextMouseoverRegions = {}, {}

local function ReleaseMouseoverRegions()
	for i, region in ipairs(mouseoverRegions) do
		A.MouseoverRegionFader(region, A.FadeOut, -1)
		mouseoverRegions[i] = nil
	end
end

local function InvalidateMouseover()
	ReleaseMouseoverRegions()
	lastMouseFocus, lastMouseStart = nil, nil
end

local CANNOT_SAVE = "Nameless frames cannot be saved."
local PROFILE_RESET = "Current profile %q has been reset."
local WELCOME = "New character detected. Type |cFF33FF99/Kong|r to configure."

local LegacyAddOnIDs = {Kong = true, KongConfig = true}

local function GetInstalledLegacyAddOns()
	local addons = {}
	for index = 1, C_AddOns.GetNumAddOns() do
		local name = C_AddOns.GetAddOnInfo(index)
		if LegacyAddOnIDs[name] then addons[#addons + 1] = name end
	end
	return addons
end

local function GetActiveLegacyAddOns()
	local active = {}
	for _, name in ipairs(GetInstalledLegacyAddOns()) do
		-- The default enable-state query covers all characters, like the AddOns UI.
		if C_AddOns.GetAddOnEnableState(name) > 0 or C_AddOns.IsAddOnLoaded(name) then
			active[#active + 1] = name
		end
	end
	return active
end

function KongKontinued_DisableLegacyAddOns()
	if InCombatLockdown() then
		KongKontinued_Warning("Legacy addons cannot be disabled during combat")
		return
	end
	local addons = GetInstalledLegacyAddOns()
	for _, name in ipairs(addons) do C_AddOns.DisableAddOn(name) end
	C_AddOns.SaveAddOns()
	for _, name in ipairs(addons) do
		if C_AddOns.GetAddOnEnableState(name) > 0 then
			KongKontinued_Error("Could not disable %s; disable legacy Kong in the AddOns screen before importing", name)
			return
		end
	end
	ReloadUI()
end

function KongKontinued_ConfirmLegacyDisabled()
	local active = GetActiveLegacyAddOns()
	if #active == 0 then return true end
	if InCombatLockdown() then
		KongKontinued_Warning("Disable legacy Kong and reload before continuing; this action is unavailable during combat")
		return false
	end
	StaticPopup_Show("KONGKONTINUED_DISABLE_LEGACY", table.concat(active, ", "))
	return false
end

StaticPopupDialogs["KONGKONTINUED_DISABLE_LEGACY"] = {
	text = "Legacy Kong detected: %s\n\nDisable Kong and KongConfig for all characters and reload before continuing? Legacy settings files will be preserved. Any pasted import text will need to be pasted again after reloading.",
	button1 = "Disable and Reload",
	button2 = CANCEL,
	OnAccept = KongKontinued_DisableLegacyAddOns,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
}

StaticPopupDialogs["KONGKONTINUED_RESET"] = {
	text = "Reset profile \"%s\"?\n\nThis permanently removes all configured frames, fade settings, conditions and groups from this profile. Any characters using this shared profile will be affected.\n\nOther profiles and WoW settings are unchanged. This cannot be undone.",
	button1 = "Reset Profile",
	button2 = CANCEL,
	OnAccept = function(self, target)
		if not A.CanModifyProfiles() then return end
		if not A.IsCurrentProfileTarget(target) then
			KongKontinued_Warning("Current profile changed; no profile was reset")
			return
		end

		KongKontinued_Unload()
		KongKontinued_Profiles[target.name] = nil
		A.LoadSettings()
		if A.RefreshOptions then A.RefreshOptions() end

		KongKontinued_Info(PROFILE_RESET, KongKontinued_Settings.profile)
	end,
	showAlert = 1,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
}

-- The defaults for all triggers
local TriggerDefaults = {
	secondsIn = .2,
	secondsOut = 1,
	secondsTillOut = 0,
	alphaIn = 1,
	alphaOut = 0,
}

function KongKontinued_CanAccessFrame(region)
	return R.Fader.canAccess(FADER, region)
end

function KongKontinued_GetFrameParent(region)
	if not KongKontinued_CanAccessFrame(region) or type(region.GetParent) ~= "function" then return nil end
	local parent = region:GetParent()
	if KongKontinued_CanAccessFrame(parent) then return parent end
end

function KongKontinued_GetFrameChildren(region)
	local children = {}
	if KongKontinued_CanAccessFrame(region) and type(region.GetChildren) == "function" then
		for _, child in pairs({region:GetChildren()}) do
			if KongKontinued_CanAccessFrame(child) then children[#children + 1] = child end
		end
	end
	return children
end

function KongKontinued_GetMouseFocus()
	local focus
	if GetMouseFoci then
		local foci = GetMouseFoci()
		if not (issecretvalue and issecretvalue(foci)) and type(foci) == "table" then focus = foci[1] end
	elseif GetMouseFocus then
		focus = GetMouseFocus()
	end
	if KongKontinued_CanAccessFrame(focus) then return focus end
end

function KongKontinued_Error(str, ...)
	print("|cFFFF2222Kong Kontinued Error:|r "..string.format(str, ...))
end

function KongKontinued_Warning(str, ...)
	print("|cFFFF9922Kong Kontinued Warning:|r "..string.format(str, ...))
end

function KongKontinued_Info(str, ...)
	print("|cFF33FF99Kong Kontinued:|r "..string.format(str, ...))
end

local LibUSC = LibStub("KongKontinuedConditions", true)
if not LibUSC then
	KongKontinued_Error("Could not load KongKontinuedConditions. Check the KongKontinued folder and bundled library files.")
	return
end

-- Dummy condition
local MouseoverTypeName = "Frame has Mouse Focus"
LibUSC:RegisterParameter(MouseoverTypeName, {
	type = "Truth",
	isHidden = true,
	value = false,
})

function A.ResolveProfileName(name)
	return A.LegacyImport.ResolveProfileName(name, KongKontinued_Profiles, KongKontinued_ProfileRenames)
end

local function GetProfileRenames()
	local renames = KongKontinued_ProfileRenames
	if type(renames) ~= "table" then return nil, "Profile rename records are invalid" end
	for oldName, name in pairs(renames) do
		if type(oldName) ~= "string" or oldName == "" or type(name) ~= "string" or name == "" then
			return nil, "Profile rename records contain an invalid name"
		end
		local resolved, err = A.ResolveProfileName(oldName)
		if not resolved then return nil, err end
	end
	return renames
end

local function ImportSignature(plan)
	local parts = {plan.mode, plan.target or "", plan.source or "", plan.selection or "",
		tostring(plan.enabled), tostring(plan.frames), tostring(plan.conditions)}
	for _, entry in ipairs(plan.profiles) do
		parts[#parts + 1], parts[#parts + 2] = entry.source, entry.name
	end
	return table.concat(parts, "\n")
end

local importPreviews = setmetatable({}, {__mode = "k"})

local function PrepareImport(text, options)
	local renames, err = GetProfileRenames()
	if not renames then return nil, err end
	return A.LegacyImport.Prepare(text, KongKontinued_Profiles, LibUSC.Parameters,
		options, renames, KongKontinued_Settings and KongKontinued_Settings.profile)
end

-- Tokens bind the preview to its input, action, destination and profile state.
-- Commit always reparses; returned plan tables are never trusted as input.
function KongKontinued_PreviewLegacyImport(text, options)
	local plan, err = PrepareImport(text, options)
	if not plan then return nil, err end
	if KongKontinued_Initialized and A.CurrentProfileTarget then
		local record = {text = text, signature = ImportSignature(plan), target = A.CurrentProfileTarget(), renames = {}, destinations = {}}
		for oldName, name in pairs(KongKontinued_ProfileRenames) do record.renames[oldName] = name end
		for _, entry in ipairs(plan.profiles) do
			record.destinations[#record.destinations + 1] = {name = entry.name, profile = KongKontinued_Profiles[entry.name]}
		end
		plan.token = {}
		importPreviews[plan.token] = record
	elseif plan.replaces then
		return nil, "Current profile is not initialized"
	end
	return plan
end

function KongKontinued_ImportLegacy(text, activate, options, token)
	if InCombatLockdown() then return nil, "Legacy import is unavailable during combat" end
	if #GetActiveLegacyAddOns() > 0 then return nil, "Disable legacy Kong and reload before importing; use /kongkontinued import" end
	if KongKontinuedConfig and KongKontinuedConfig:IsShown() then
		return nil, "Close the configuration screen before importing"
	end
	if activate ~= nil and type(activate) ~= "boolean" then return nil, "Invalid import activation choice" end
	local plan, err = PrepareImport(text, options)
	if not plan then return nil, err end
	if activate and not plan.selection then return nil, "No legacy character profile was selected" end
	if token then
		local record = importPreviews[token]
		if not record or record.text ~= text or record.signature ~= ImportSignature(plan)
			or not A.IsCurrentProfileTarget(record.target) then
			return nil, "Import preview is stale; preview again before importing"
		end
		for oldName, name in pairs(record.renames) do
			if KongKontinued_ProfileRenames[oldName] ~= name then return nil, "Profile renames changed; preview again" end
		end
		for oldName, name in pairs(KongKontinued_ProfileRenames) do
			if record.renames[oldName] ~= name then return nil, "Profile renames changed; preview again" end
		end
		for _, destination in ipairs(record.destinations) do
			if KongKontinued_Profiles[destination.name] ~= destination.profile then return nil, "Destination changed; preview again" end
		end
	elseif plan.replaces then
		return nil, "Preview the replacement import before confirming it"
	end
	local nextRenames
	if plan.renameFrom then
		nextRenames = {}
		for oldName, name in pairs(KongKontinued_ProfileRenames) do
			local resolved = A.ResolveProfileName(oldName)
			if oldName ~= plan.selection then
				nextRenames[oldName] = resolved == plan.renameFrom and plan.selection or name
			end
		end
		nextRenames[plan.renameFrom] = plan.selection
	end
	if token then importPreviews[token] = nil end
	if plan.replaces or activate then KongKontinued_Unload()
	elseif KongKontinued_InvalidateProfileDialogs then KongKontinued_InvalidateProfileDialogs() end
	for _, entry in ipairs(plan.profiles) do
		entry.data.version = VERSION
		for _, setting in ipairs(entry.data.Frames) do setting.version = VERSION end
		KongKontinued_Profiles[entry.name] = entry.data
	end
	if nextRenames then
		KongKontinued_Profiles[plan.renameFrom] = nil
		KongKontinued_ProfileRenames = nextRenames
	end
	if plan.replaces or activate then
		KongKontinued_Settings.profile = plan.selection
		if not plan.replaces then KongKontinued_Settings.enabled = plan.enabled end
		A.LoadSettings()
	end
	if A.RefreshOptions then A.RefreshOptions() end
	return plan
end

local AlphaOverrides = {}

function KongKontinued_OverrideAlpha(region, override)
	assert(KongKontinued_Frames[region] ~= nil)
	local state = AlphaOverrides[region]

	if ( override and KongKontinued_Settings.enabled and R.Fader.canAccess(FADER, region)
		and not IsPresetTransparencyBlocked(region, KongKontinued_Frames[region]) ) then
		if ( state ~= nil ) then return end
		state = {
			original = rawget(region, "SetAlpha"),
			replacement = function() end,
		}
		AlphaOverrides[region] = state
		region.SetAlpha = state.replacement
	elseif ( state ~= nil ) then
		-- Restore only the method Kong still owns, including an inherited default.
		if ( rawget(region, "SetAlpha") == state.replacement ) then
			region.SetAlpha = state.original
		end
		AlphaOverrides[region] = nil
	end
end

local function IsMinimapPreset(region, setting)
	return setting and setting.preset and A.MinimapPreset and region == Minimap
end

local function GetFrameFadeAlpha(region)
	if IsMinimapPreset(region, KongKontinued_Frames[region]) then
		return A.MinimapPreset.GetAlpha()
	end
	return R.Fader.getAlpha(FADER, region)
end

function KongKontinued_Fade(region, fromAlpha, toAlpha, duration, startDelay)
	if ( KongKontinued_Settings.enabled and (KongKontinuedConfig == nil or not KongKontinuedConfig:IsShown()) ) then
		local setting = KongKontinued_Frames[region]
		if HasPresetTransparencyGuard(region, setting) and not A.FramePresetTransparency.CanFade(region) then return end
		local target, writer = region
		if IsMinimapPreset(region, setting) then
			target = A.MinimapPreset.Acquire()
		elseif setting and setting.preset and PresetOriginalAlpha[region] == nil then
			PresetOriginalAlpha[region] = PendingRestores[region] or R.Fader.getAlpha(FADER, region)
			if PresetOriginalAlpha[region] == nil then return end
		end
		if A.FramePresetTransparency and A.FramePresetTransparency.Handles(region) then writer = WriteGuardedFrameAlpha end
		if target then R.Fader.fade(FADER, target, fromAlpha, toAlpha, duration, nil, startDelay, nil, writer) end
	end
end

local function RestoreFrame(region, preserveAlpha)
	-- Finish cleanup before the frame's settings can be removed or replaced.
	R.Fader.stopFade(FADER, region)
	KongKontinued_OverrideAlpha(region, false)
	local setting = KongKontinued_Frames[region]
	preserveAlpha = preserveAlpha or IsPresetTransparencyBlocked(region, setting)
	local reveal = HiddenFrames[region] or (not preserveAlpha and (PendingVisibility[region] == true
		or (setting.hideAtZeroAlpha and R.Fader.getAlpha(FADER, region) == 0)))
	PendingVisibility[region] = nil
	if reveal then
		SetFrameShown(region, true)
	end
	if preserveAlpha then
		if setting.preset then RestoreOwnedPresetAlpha(region) end
		PendingRestores[region], PresetOriginalAlpha[region] = nil, nil
	end
	if IsMinimapPreset(region, setting) then
		local target = A.MinimapPreset.GetTarget()
		if target then R.Fader.stopFade(FADER, target) end
		A.MinimapPreset.Release()
		return
	end
	if preserveAlpha then return end
	local alpha = 1
	if setting.preset then
		alpha = PresetOriginalAlpha[region] or PendingRestores[region]
		PresetOriginalAlpha[region] = nil
		if alpha == nil then return end
	end
	if SetFrameAlpha(region, alpha) then
		PendingRestores[region] = nil
	else
		PendingRestores[region] = alpha
	end
end

function KongKontinued_UpdateFrameVisibility(region)
	if IsPresetTransparencyBlocked(region, KongKontinued_Frames[region]) then return end
	if not KongKontinued_Frames[region].hideAtZeroAlpha then
		local reveal = HiddenFrames[region] or PendingVisibility[region] == true
		PendingVisibility[region] = nil
		if reveal then SetFrameShown(region, true) end
	elseif not R.Fader.isFading(FADER, region) and R.Fader.getAlpha(FADER, region) == 0 then
		SetFrameShown(region, false)
	end
end

function A.FadeIn(region, condition)
	condition.refs = condition.refs + 1
	if ( condition.refs == 1 ) then
		A.CalculateFadeIn(region)
	end
end

local function GetFadeSpeed(trigger, seconds)
	local distance = math.abs(trigger.alphaIn - trigger.alphaOut)
	if ( distance == 0 ) then return 0 end
	if not ( type(seconds) == "number" and seconds > 0 and seconds < math.huge ) then
		return math.huge
	end
	return distance / seconds
end

local function GetFadeDuration(currentAlpha, endAlpha, speed)
	if ( currentAlpha == nil or speed == 0 ) then return 0 end
	local duration = math.abs(currentAlpha - endAlpha) / speed
	return duration >= 0 and duration < math.huge and duration or 0
end

function A.CalculateFadeIn(region)
	local setting = KongKontinued_Frames[region]
	local currentAlpha = GetFrameFadeAlpha(region)
	local chosenTrigger
	
	-- NOTE: choose the trigger with the highest alpha, with the fastest speed
	for i, trigger in ipairs(setting) do
		if ( trigger.refs > 0 ) then
			chosenTrigger = chosenTrigger or trigger
			
			local speed = GetFadeSpeed(trigger, trigger.secondsIn)
			local otherSpeed = GetFadeSpeed(chosenTrigger, chosenTrigger.secondsIn)
			
			if ( trigger.alphaIn > chosenTrigger.alphaIn or (trigger.alphaIn == chosenTrigger.alphaIn and speed > otherSpeed) ) then
				chosenTrigger = trigger
			end
		end
	end
	
	if ( chosenTrigger ~= nil ) then
		local endAlpha = chosenTrigger.alphaIn
		local speed = GetFadeSpeed(chosenTrigger, chosenTrigger.secondsIn)
		local duration = GetFadeDuration(currentAlpha, endAlpha, speed)
		
		KongKontinued_Fade(region, currentAlpha, endAlpha, duration)
	end
end

function A.FadeOut(region, condition)
	condition.refs = condition.refs - 1
	if condition.refs < 0 then
		local setting = KongKontinued_Frames[region]
		error("ref < 0 for region: " .. tostring(setting and setting.index or "<unnamed>"))
	end
	if ( condition.refs == 0 ) then
		local speed = GetFadeSpeed(condition, condition.secondsOut)
		local displacement = 0
		local currentAlpha = GetFrameFadeAlpha(region)
		if ( currentAlpha ~= nil and speed > 0 and speed < math.huge ) then
			local rate = condition.alphaOut > condition.alphaIn and speed or -speed
			local offset = (condition.alphaIn - currentAlpha) / rate
			if ( offset > -math.huge and offset < math.huge ) then
				displacement = offset
			end
		end
		condition.lastFadeTime = GetTime() + displacement
		KongKontinued_CalculateFadeOut(region)
	end
end

function KongKontinued_CalculateFadeOut(region)
	local setting = KongKontinued_Frames[region]
	local currentAlpha = GetFrameFadeAlpha(region)
	local endAlpha = setting.TriggerDefaults.alphaOut
	local activeAlpha
	local duration = 0
	local delay = setting.TriggerDefaults.secondsTillOut
	local chosenTrigger

	for i, trigger in ipairs(setting) do
		if ( trigger.refs > 0 ) then
			if not setting.preset and currentAlpha ~= nil and trigger.alphaIn >= currentAlpha then return end

			activeAlpha = math.max(activeAlpha or 0, trigger.alphaIn)
		elseif ( trigger.lastFadeTime ~= nil ) then
			chosenTrigger = chosenTrigger or trigger

			local now = GetTime()
			local sinceTrue = now - trigger.lastFadeTime
			local otherSinceTrue = now - chosenTrigger.lastFadeTime
			
			local speed = GetFadeSpeed(trigger, trigger.secondsOut)
			local otherSpeed = GetFadeSpeed(chosenTrigger, chosenTrigger.secondsOut)

			if ( sinceTrue < otherSinceTrue or (sinceTrue == otherSinceTrue and speed < otherSpeed) ) then
				chosenTrigger = trigger
			end
		end
	end
	if activeAlpha then
		if setting.preset and (currentAlpha == nil or activeAlpha >= currentAlpha) then
			-- Replace an in-progress reveal when its remaining rule has a different target.
			A.CalculateFadeIn(region)
			return
		end
		endAlpha = setting.preset and activeAlpha or math.max(endAlpha, activeAlpha)
	end

	if ( chosenTrigger ~= nil ) then
		local speed = GetFadeSpeed(chosenTrigger, chosenTrigger.secondsOut)
		duration = GetFadeDuration(currentAlpha, endAlpha, speed)
		delay = chosenTrigger.secondsTillOut
	end

	KongKontinued_Fade(region, currentAlpha, endAlpha, duration, delay)
end

function KongKontinued_FindGlobalIndex(region)
	if not KongKontinued_CanAccessFrame(region) then return nil end
	local name = region:GetName()
	if not (issecretvalue and issecretvalue(name)) and type(name) == "string" then
		return '[' .. string.format("%q", name) .. ']'
	end
	
	for k, v in pairs(_G) do
		if not (issecretvalue and (issecretvalue(k) or issecretvalue(v))) and rawequal(v, region) then
			local keyType = type(k)
			if ( keyType == "string" ) then
				return '[' .. string.format("%q", k) .. ']'
			elseif ( keyType == "number" or keyType == "boolean" ) then
				return "[" .. tostring(k) .. "]"
			end
		end
	end
	
	for i, child in pairs(KongKontinued_GetFrameChildren(region)) do
		name = KongKontinued_FindGlobalIndex(child)
		if ( name ) then
			return name .. ":GetParent()"
		end
	end
end

function A.RefreshPresetFade(region)
	for _, trigger in ipairs(KongKontinued_Frames[region]) do
		if trigger.refs > 0 then
			A.CalculateFadeIn(region)
			return
		end
	end
	KongKontinued_CalculateFadeOut(region)
end

function A.OnFramePresetAvailabilityChanged(region, available)
	local setting = KongKontinued_Frames[region]
	if not HasPresetTransparencyGuard(region, setting) then return end
	if not available then
		R.Fader.stopFade(FADER, region)
		KongKontinued_OverrideAlpha(region, false)
		PendingVisibility[region], PendingRestores[region] = nil, nil
		if RestoreOwnedPresetAlpha(region) and HiddenFrames[region] then SetFrameShown(region, true) end
	elseif KongKontinued_Settings.enabled then
		KongKontinued_OverrideAlpha(region, setting.overrideAlpha)
		A.RefreshPresetFade(region)
	end
end

function A.CreateTrigger(Frame)

	local Trigger = {}
	setmetatable(Trigger, {__index = KongKontinued_Frames[Frame].TriggerDefaults or TriggerDefaults})

	if KongKontinued_Frames[Frame].TriggerDefaults then
		Trigger.refs = 0
	else
		Trigger.Frame = Frame
	end

	return Trigger
end

function KongKontinued_RegisterFrame(region, presetPath)
	if not KongKontinued_CanAccessFrame(region) then return end
	InvalidateMouseover()
	KongKontinued_Frames[region] = {}
	local index = presetPath or KongKontinued_FindGlobalIndex(region)
	if ( index ~= nil ) then
		KongKontinued_Frames[region].index = index
	else
		KongKontinued_Frames[region].index = {}
		KongKontinued_Warning(CANNOT_SAVE)
	end
	KongKontinued_Frames[region].version = VERSION
	if presetPath then
		KongKontinued_Frames[region].preset = true
		RememberChatPreset(region, index)
	end
	KongKontinued_Frames[region].TriggerDefaults = A.CreateTrigger(region)
	if presetPath then KongKontinued_Frames[region].TriggerDefaults.alphaOut = .25 end
	KongKontinued_Frames[region].Mouseover = KongKontinued_AddTrigger(region, LibUSC:Create("Condition", LibUSC:Create(MouseoverTypeName)))
	KongKontinued_AddTrigger(region, LibUSC:Create("Condition", LibUSC:Create("Unit in Combat")))
	if presetPath then A.RefreshPresetFade(region) end
end

function KongKontinued_UnregisterFrame(region, preserveAlpha)
	InvalidateMouseover()
	for i = #KongKontinued_Frames[region], 1, -1 do
		KongKontinued_RemoveTrigger(region, KongKontinued_Frames[region][i], true)
	end
	RestoreFrame(region, preserveAlpha)
	local index = KongKontinued_Frames[region].index
	for name, group in pairs(KongKontinued_Settings.Groups) do
		if ( group[index] ~= nil ) then
			group[index] = nil
			if ( next(group) == nil ) then
				KongKontinued_Settings.Groups[name] = nil
			end
		end
	end
	KongKontinued_Frames[region] = nil
	ChatPresetRegions[region] = nil
end

function A.OnConditionStateChange(region, trigger)
	-- A rule owns one contribution; mouseover and groups may own others.
	local active = not not trigger.Condition:IsMet()
	if active == (ConditionStates[trigger] or false) then return end
	ConditionStates[trigger] = active
	if active then
		A.FadeIn(region, trigger)
	else
		A.FadeOut(region, trigger)
	end
end

function KongKontinued_AddTrigger(region, condition)
	local trigger = A.CreateTrigger(region)
	trigger.Condition = condition
	trigger.Condition:AddListener(A.OnConditionStateChange, region, trigger)
	table.insert(KongKontinued_Frames[region], trigger)
	A.OnConditionStateChange(region, trigger)
	return trigger
end

function KongKontinued_RemoveTrigger(region, trigger, skipFade)
	if KongKontinued_Frames[region].Mouseover == trigger then InvalidateMouseover() end
	local active = ConditionStates[trigger]
	ConditionStates[trigger] = nil
	if active and not skipFade then
		A.FadeOut(region, trigger)
	end
	trigger.Condition:RemoveListener(A.OnConditionStateChange)
	LibUSC:Deflate(trigger.Condition)
	if KongKontinued_Frames[region].Mouseover == trigger then KongKontinued_Frames[region].Mouseover = nil end
	for i, v in ipairs(KongKontinued_Frames[region]) do
		if ( v == trigger ) then
			table.remove(KongKontinued_Frames[region], i)
			break
		end
	end
end

function KongKontinued_AddFrameToGroup(region, name)
	KongKontinued_Settings.Groups[name] = KongKontinued_Settings.Groups[name] or {}
	local group = KongKontinued_Settings.Groups[name]
	local index = KongKontinued_Frames[region].index
	if ( group[index] == nil ) then
		InvalidateMouseover()
		group[index] = region
		return true
	end
end

function KongKontinued_RemoveFrameFromGroup(region, name)
	local group = KongKontinued_Settings.Groups[name]
	local index = KongKontinued_Frames[region].index
	if ( group ~= nil and group[index] ~= nil ) then
		InvalidateMouseover()
		group[index] = nil
		if ( next(group) == nil ) then
			KongKontinued_Settings.Groups[name] = nil
		end
		return true
	end
end

function A.Enable()
	KongKontinued_Settings.enabled = true
	for Frame, setting in pairs(KongKontinued_Frames) do
		KongKontinued_OverrideAlpha(Frame, setting.overrideAlpha)
		KongKontinued_CalculateFadeOut(Frame)
	end
end

function A.Disable()
	KongKontinued_Settings.enabled = false
	for Frame in pairs(KongKontinued_Frames) do
		RestoreFrame(Frame)
	end
end

function KongKontinued_RenameFrame(region, newIndex)
	local index = KongKontinued_Frames[region].index
	for name, group in pairs(KongKontinued_Settings.Groups) do
		if ( group[index] ~= nil ) then
			group[index] = nil
			group[newIndex] = region
		end
	end
	KongKontinued_Frames[region].index = newIndex
end

function A.LoadSettings()
	if ( KongKontinued_Initialized ) then return end
	
	if ( not KongKontinued_Settings or not KongKontinued_Settings.profile ) then
		local playerName = string.lower( UnitName("player") )
		local playerServer = string.lower( string.gsub(GetRealmName(), " ", "_") )
		local profileName = playerName .. "_of_" .. playerServer
		
		KongKontinued_Settings = {
			profile = profileName,
			enabled = true,
		}
	end

	local name, err = A.ResolveProfileName(string.gsub(KongKontinued_Settings.profile, " ", "_"))
	if not name then KongKontinued_Error("%s", err); return end
	KongKontinued_Settings.profile = name
	
	if ( not KongKontinued_Profiles[KongKontinued_Settings.profile] ) then
		KongKontinued_Profiles[KongKontinued_Settings.profile] = {
			Frames = {},
			Groups = {},
		}
	end
	
	setmetatable(KongKontinued_Settings, {__index = KongKontinued_Profiles[KongKontinued_Settings.profile]})

	KongKontinued_Profiles[KongKontinued_Settings.profile].version = VERSION
	KongKontinued_Initialized = true

	A.LoadFrames()

	if ( not KongKontinued_Settings.enabled ) then
	   KongKontinued_Warning("Kong Kontinued is currently disabled. Use |cFF33FF99/kong toggle|r to enable it.")
	end
end

local function NoSavedFrame() end

function A.ResolveSavedFrame(setting)
	if not setting.loader then
		setting.loader = A.LegacyImport.CompileFramePath(setting.index) or NoSavedFrame
	end
	local resolved, region = pcall(setting.loader)
	if resolved then return region end
end

function A.LoadFrames()
	if not KongKontinued_Initialized then return end
	local loadedFrame
	for i = #KongKontinued_Settings.Frames, 1, -1 do
		local setting = KongKontinued_Settings.Frames[i]
		
		local region = A.ResolveSavedFrame(setting)

		if (
				R.Fader.canAccess(FADER, region)
				and type(region.IsObjectType) == "function"
				and region:IsObjectType("Region") -- make sure it is a region; ticket #5
				and not KongKontinued_Frames[region]
		) then
			loadedFrame = true
			setting.loader = nil
			KongKontinued_Frames[region] = setting
			if setting.preset then RememberChatPreset(region, setting.index) end
			table.remove(KongKontinued_Settings.Frames, i)

			setmetatable(setting.TriggerDefaults, {__index = TriggerDefaults})
			setting.TriggerDefaults.Frame = region
			
			if ( setting.overrideAlpha ) then
				KongKontinued_OverrideAlpha(region, true)
			end
			
			for i, trigger in ipairs(setting) do
				setmetatable(trigger, {__index = setting.TriggerDefaults})
				trigger.refs = 0
				ConditionStates[trigger] = nil
				LibUSC:Inflate(trigger.Condition)
				trigger.Condition:AddListener(A.OnConditionStateChange, region, trigger)
				
				if ( MouseoverTypeName == trigger.Condition.Parameters[1]:GetName() ) then
					setting.Mouseover = trigger
				end
			end

			if ( KongKontinued_Settings.enabled ) then
				KongKontinued_CalculateFadeOut(region)
			end
			
			for i, trigger in ipairs(setting) do
				A.OnConditionStateChange(region, trigger)
			end
			
			for name, group in pairs(KongKontinued_Settings.Groups) do
				if ( group[setting.index] ) then
					if setting.Mouseover then
						for i = 1, group[setting.index] do A.FadeIn(region, setting.Mouseover) end
					end
					group[setting.index] = region
				end
			end
		end
	end
	if loadedFrame then InvalidateMouseover() end
end

function KongKontinued_Unload()
	if KongKontinued_InvalidateProfileDialogs then KongKontinued_InvalidateProfileDialogs() end
	for region, settings in pairs(KongKontinued_Frames) do
		RestoreFrame(region)
		
		for i, trigger in ipairs(settings) do
			ConditionStates[trigger] = nil
			trigger.refs = nil
			trigger.lastFadeTime = nil
			trigger.Condition:RemoveListener(A.OnConditionStateChange)
			LibUSC:Deflate(trigger.Condition)
		end
		
		settings.loader = nil
		settings.Mouseover = nil
		settings.TriggerDefaults.Frame = nil
		
		KongKontinued_Frames[region] = nil
		if ( type(settings.index) ~= "table" ) then
			table.insert(KongKontinued_Settings.Frames, settings)
		end
	end
	
	for name, group in pairs(KongKontinued_Settings.Groups or {}) do
		local removedTemporary
		for index in pairs(group) do
			if type(index) == "table" then
				group[index] = nil
				removedTemporary = true
			else
				group[index] = 0
			end
		end
		if removedTemporary and not next(group) then KongKontinued_Settings.Groups[name] = nil end
	end
	
	KongKontinued_Frames = {}
	ChatPresetRegions = {}
	lastMouseFocus = nil
	lastMouseStart = nil
	mouseoverRegions, nextMouseoverRegions = {}, {}
	KongKontinued_Initialized = false
end

function A.FindFirstTrackedRegion(region)
	while KongKontinued_CanAccessFrame(region) do
		if KongKontinued_Frames[region] ~= nil then return region end
		region = KongKontinued_GetFrameParent(region)
	end
end

function A.ForEachTrackedRegion(region, func, ...)
	if issecretvalue and issecretvalue(region) then return end
	while ( region ~= nil ) do
		if ( KongKontinued_Frames[region] ~= nil ) then func(region, ...) end
		region = KongKontinued_GetFrameParent(region)
	end
end

function A.MouseoverRegionFader(region, func, additive)
	local settings = KongKontinued_Frames[region]
	if not settings then return end
	for name, group in pairs(KongKontinued_Settings.Groups) do
		if ( group[settings.index] ~= nil ) then
			for index, groupRegion in pairs(group) do
				if ( type(groupRegion) == "table" ) then -- TODO: remove value-type ambiguity
					local groupSetting = KongKontinued_Frames[groupRegion]
					if groupSetting and groupSetting.Mouseover then func(groupRegion, groupSetting.Mouseover) end
				elseif type(groupRegion) == "number" then
					group[index] = groupRegion + additive
				end
			end
		end
	end
	if settings.Mouseover then func(region, settings.Mouseover) end
end

local FRAME_FIND_PERIOD = 1.0
local frameFindTimer = 0
local transparencyTimer = 0

local function TrackMouseoverRegion(region)
	nextMouseoverRegions[#nextMouseoverRegions + 1] = region
	A.MouseoverRegionFader(region, A.FadeIn, 1)
end

function A.OnUpdate(self, elapsed)
	frameFindTimer = frameFindTimer - elapsed
	if frameFindTimer <= 0 then
		frameFindTimer = FRAME_FIND_PERIOD
		A.LoadFrames()
	end
	transparencyTimer = transparencyTimer - elapsed
	if transparencyTimer <= 0 then
		transparencyTimer = FRAME_FIND_PERIOD
		if A.FramePresetTransparency then A.FramePresetTransparency.Refresh() end
		if A.MinimapPreset then A.MinimapPreset.CheckOwnedMask() end
	end

	local mouseFocus = KongKontinued_GetMouseFocus()
	-- Detached chat can take the wheel while the world still has mouse focus.
	-- Keep the native scrolling and line-fade scripts in charge of the text.
	if mouseFocus == nil or mouseFocus == WorldFrame then
		for region in pairs(ChatPresetRegions) do
			if KongKontinued_CanAccessFrame(region) then
				local over, visible = region:IsMouseOver(), region:IsVisible()
				if not (issecretvalue and (issecretvalue(over) or issecretvalue(visible))) and over and visible then
					mouseFocus = region
					break
				end
			end
		end
	end
	if ( mouseFocus ~= lastMouseFocus ) then
		local mouseStart = mouseFocus ~= nil and A.FindFirstTrackedRegion(mouseFocus) or nil
		if ( mouseStart ~= lastMouseStart ) then
			if ( mouseStart ~= nil ) then
				A.ForEachTrackedRegion(mouseStart, TrackMouseoverRegion)
			end
			ReleaseMouseoverRegions()
			mouseoverRegions, nextMouseoverRegions = nextMouseoverRegions, mouseoverRegions
			lastMouseStart = mouseStart
		end
		lastMouseFocus = mouseFocus
	end
end

function A.OnEvent(self, event, arg1, ...)

	if event == "ADDON_LOADED" then
		if arg1 == "KongKontinued" and not KongKontinued_Settings then
			KongKontinued_Info(WELCOME)
		end
	elseif event == "PLAYER_LOGIN" then

		A.LoadSettings()
		
		hooksecurefunc("CreateFrame", function() frameFindTimer = 0; end)
		KongKontinuedUIFader:SetScript("OnUpdate", A.OnUpdate)
	elseif event == "PLAYER_LOGOUT" then
		xpcall(KongKontinued_Unload, function(message) KongKontinued_Settings.error = message.."\n"..debugstack() end)
	elseif event == "PLAYER_REGEN_ENABLED" or event == "PLAYER_ENTERING_WORLD" then
		A.ApplyPendingVisibility()
	end
end

-- The event receiver frame
KongKontinuedUIFader = CreateFrame("Frame")
KongKontinuedUIFader:SetScript("OnEvent", A.OnEvent)

KongKontinuedUIFader:RegisterEvent("ADDON_LOADED")
KongKontinuedUIFader:RegisterEvent("PLAYER_LOGIN")
KongKontinuedUIFader:RegisterEvent("PLAYER_LOGOUT")
KongKontinuedUIFader:RegisterEvent("PLAYER_REGEN_ENABLED")
KongKontinuedUIFader:RegisterEvent("PLAYER_ENTERING_WORLD")
