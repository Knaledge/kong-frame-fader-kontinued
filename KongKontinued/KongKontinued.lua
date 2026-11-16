local	_G, assert, ipairs, math, next, pairs, pcall, print, setmetatable, string, table, tonumber, tostring, type, xpcall
=		_G, assert, ipairs, math, next, pairs, pcall, print, setmetatable, string, table, tonumber, tostring, type, xpcall
local	CreateFrame, debugstack, GetMouseFoci, GetMouseFocus, GetRealmName, GetTime, hooksecurefunc, IsAddOnLoaded, StaticPopup_Show, strsplit, UnitName, WOW_PROJECT_CLASSIC, WOW_PROJECT_ID, WOW_PROJECT_MAINLINE
=		CreateFrame, debugstack, GetMouseFoci, GetMouseFocus, GetRealmName, GetTime, hooksecurefunc, IsAddOnLoaded, StaticPopup_Show, strsplit, UnitName, WOW_PROJECT_CLASSIC, WOW_PROJECT_ID, WOW_PROJECT_MAINLINE


local N, A = ... -- Addon (N)ame, (A)ddon Table
local R = A.CLASSES -- Class (R)epository


local DUMMY_FRAME = CreateFrame("frame") -- used for references to avoid abundant rawget calls when dealing with dummy functions
local FADER = R.Fader.construct()
local HiddenFrames, PendingVisibility, PendingRestores = {}, {}, {}

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
	if KongKontinued_Settings and KongKontinued_Settings.enabled then
		for region, setting in pairs(KongKontinued_Frames) do
			if setting.overrideAlpha then KongKontinued_OverrideAlpha(region, true) end
		end
	end
	for region in pairs(PendingRestores) do
		if R.Fader.setAlpha(FADER, region, 1) then PendingRestores[region] = nil end
	end
	for region, shown in pairs(PendingVisibility) do
		local setting = KongKontinued_Frames[region]
		local alpha = R.Fader.getAlpha(FADER, region)
		if shown or (setting and setting.hideAtZeroAlpha and (alpha == nil or alpha == 0)) then
			SetFrameShown(region, shown)
		else
			PendingVisibility[region] = nil
		end
	end
end

R.Fader.addListener(FADER, "FADE_STARTED", 
		function(obj, event, region, fromAlpha, toAlpha, duration, smoothing, startDelay, endDelay)
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
			local setting = KongKontinued_Frames[region]
			local alpha = R.Fader.getAlpha(FADER, region)
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

local lastMouseFocus = nil
local lastMouseStart = nil

local CANNOT_SAVE = "Nameless frames cannot be saved."
local PROFILE_RESET = "Current profile %q has been reset."
local WELCOME = "New character detected. Type |cFF33FF99/Kong|r to configure."

StaticPopupDialogs["KONGKONTINUED_RESET"] = {
	text = "Are you sure you want to delete all settings from the Kong profile \"%s\"?",
	button1 = "Reset",
	button2 = CANCEL,
	OnAccept = function(self)

		KongKontinued_Unload()
		KongKontinued_Profiles[KongKontinued_Settings.profile] = nil
		A.LoadSettings()

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

local LibUSC = LibStub("LibUserSpecifiedConditions", true)
if not LibUSC then
	KongKontinued_Error("Could not load LibUserSpecifiedConditions. Check the KongKontinued folder and bundled library files.")
	return
end

-- Dummy condition
local MouseoverTypeName = "Frame has Mouse Focus"
LibUSC:RegisterParameter(MouseoverTypeName, {
	type = "Truth",
	isHidden = true,
	value = false,
})

-- Preview and commit both validate fresh data; callers cannot submit a modified plan.
function KongKontinued_PreviewLegacyImport(text)
	return A.LegacyImport.Prepare(text, KongKontinued_Profiles, LibUSC.Parameters)
end

function KongKontinued_ImportLegacy(text, activate)
	if InCombatLockdown() then return nil, "Legacy import is unavailable during combat" end
	if KongKontinuedConfig and KongKontinuedConfig:IsShown() then
		return nil, "Close the configuration screen before importing"
	end
	local plan, err = KongKontinued_PreviewLegacyImport(text)
	if not plan then return nil, err end
	if activate and not plan.selection then return nil, "No legacy character profile was selected" end
	for _, entry in ipairs(plan.profiles) do
		entry.data.version = VERSION
		for _, setting in ipairs(entry.data.Frames) do setting.version = VERSION end
		KongKontinued_Profiles[entry.name] = entry.data
	end
	if activate then
		KongKontinued_Unload()
		KongKontinued_Settings.profile = plan.selection
		KongKontinued_Settings.enabled = plan.enabled
		A.LoadSettings()
	end
	return plan
end

local AlphaOverrides = {}

function KongKontinued_OverrideAlpha(region, override)
	assert(KongKontinued_Frames[region] ~= nil)
	local state = AlphaOverrides[region]

	if ( override and KongKontinued_Settings.enabled and R.Fader.canAccess(FADER, region) ) then
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

function KongKontinued_Fade(region, fromAlpha, toAlpha, duration, startDelay)
	if ( KongKontinued_Settings.enabled and (KongKontinuedConfig == nil or not KongKontinuedConfig:IsShown()) ) then
		R.Fader.fade(FADER, region, fromAlpha, toAlpha, duration, nil, startDelay)
	end
end

local function RestoreFrame(region)
	-- Finish cleanup before the frame's settings can be removed or replaced.
	R.Fader.stopFade(FADER, region)
	KongKontinued_OverrideAlpha(region, false)
	local reveal = HiddenFrames[region] or PendingVisibility[region] == true
		or (KongKontinued_Frames[region].hideAtZeroAlpha and R.Fader.getAlpha(FADER, region) == 0)
	PendingVisibility[region] = nil
	if reveal then
		SetFrameShown(region, true)
	end
	if not R.Fader.setAlpha(FADER, region, 1) then PendingRestores[region] = true end
end

function KongKontinued_UpdateFrameVisibility(region)
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
	local currentAlpha = R.Fader.getAlpha(FADER, region)
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
		local currentAlpha = R.Fader.getAlpha(FADER, region)
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
	local currentAlpha = R.Fader.getAlpha(FADER, region)
	local endAlpha = setting.TriggerDefaults.alphaOut
	local duration = 0
	local delay = setting.TriggerDefaults.secondsTillOut
	local chosenTrigger

	for i, trigger in ipairs(setting) do
		if ( trigger.refs > 0 ) then
			if ( currentAlpha ~= nil and trigger.alphaIn >= currentAlpha ) then return end

			endAlpha = math.max(endAlpha, trigger.alphaIn)
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

function KongKontinued_RegisterFrame(region)
	if not KongKontinued_CanAccessFrame(region) then return end
	KongKontinued_Frames[region] = {}
	local index = KongKontinued_FindGlobalIndex(region)
	if ( index ~= nil ) then
		KongKontinued_Frames[region].index = index
	else
		KongKontinued_Frames[region].index = {}
		KongKontinued_Warning(CANNOT_SAVE)
	end
	KongKontinued_Frames[region].version = VERSION
	KongKontinued_Frames[region].TriggerDefaults = A.CreateTrigger(region)
	KongKontinued_Frames[region].Mouseover = KongKontinued_AddTrigger(region, LibUSC:Create("Condition", LibUSC:Create(MouseoverTypeName)))
	KongKontinued_AddTrigger(region, LibUSC:Create("Condition", LibUSC:Create("Unit in Combat")))
end

function KongKontinued_UnregisterFrame(region)
	for i = #KongKontinued_Frames[region], 1, -1 do
		KongKontinued_RemoveTrigger(region, KongKontinued_Frames[region][i])
	end
	RestoreFrame(region)
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
end

function A.OnConditionStateChange(region, trigger)
	if ( trigger.Condition:IsMet() ) then
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
	if ( trigger.Condition:IsMet() ) then
		A.FadeIn(region, trigger)
	end
	return trigger
end

function KongKontinued_RemoveTrigger(region, trigger)
	if ( trigger.Condition:IsMet() ) then
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
		group[index] = region
		return true
	end
end

function KongKontinued_RemoveFrameFromGroup(region, name)
	local group = KongKontinued_Settings.Groups[name]
	local index = KongKontinued_Frames[region].index
	if ( group ~= nil and group[index] ~= nil ) then
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
	KongKontinued_Initialized = true
	
	if ( not KongKontinued_Settings or not KongKontinued_Settings.profile ) then
		local playerName = string.lower( UnitName("player") )
		local playerServer = string.lower( string.gsub(GetRealmName(), " ", "_") )
		local profileName = playerName .. "_of_" .. playerServer
		
		KongKontinued_Settings = {
			profile = profileName,
			enabled = true,
		}
	end

	KongKontinued_Settings.profile = string.gsub(KongKontinued_Settings.profile, " ", "_")
	
	if ( not KongKontinued_Profiles[KongKontinued_Settings.profile] ) then
		KongKontinued_Profiles[KongKontinued_Settings.profile] = {
			Frames = {},
			Groups = {},
		}
	end
	
	setmetatable(KongKontinued_Settings, {__index = KongKontinued_Profiles[KongKontinued_Settings.profile]})

	KongKontinued_Profiles[KongKontinued_Settings.profile].version = VERSION

	A.LoadFrames()

	if ( not KongKontinued_Settings.enabled ) then
	   KongKontinued_Warning("Kong Kontinued is currently disabled. Use |cFF33FF99/kong toggle|r to enable it.")
	end
end

function A.LoadFrames()
	for i = #KongKontinued_Settings.Frames, 1, -1 do
		local setting = KongKontinued_Settings.Frames[i]
		
		if ( not setting.loader ) then
			setting.loader = A.LegacyImport.CompileFramePath(setting.index) or function() end
		end

		local isFound, region = pcall(setting.loader)

		if (
				isFound
				and R.Fader.canAccess(FADER, region)
				and type(region.IsObjectType) == "function"
				and region:IsObjectType("Region") -- make sure it is a region; ticket #5
				and not KongKontinued_Frames[region]
		) then
			setting.loader = nil
			KongKontinued_Frames[region] = setting
			table.remove(KongKontinued_Settings.Frames, i)

			setmetatable(setting.TriggerDefaults, {__index = TriggerDefaults})
			setting.TriggerDefaults.Frame = region
			
			if ( setting.overrideAlpha ) then
				KongKontinued_OverrideAlpha(region, true)
			end
			
			for i, trigger in ipairs(setting) do
				setmetatable(trigger, {__index = setting.TriggerDefaults})
				trigger.refs = 0
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
				if ( trigger.Condition:IsMet() ) then
					A.FadeIn(region, trigger)
				end
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
end

function KongKontinued_Unload()
	for region, settings in pairs(KongKontinued_Frames) do
		RestoreFrame(region)
		
		for i, trigger in ipairs(settings) do
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
	
	for name, group in pairs(KongKontinued_Settings.Groups) do
		for index in pairs(group) do
			group[index] = 0
		end
	end
	
	KongKontinued_Frames = {}
	lastMouseFocus = nil
	lastMouseStart = nil
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

function A.OnUpdate(self, elapsed)
	frameFindTimer = frameFindTimer - elapsed
	if frameFindTimer <= 0 then
		frameFindTimer = FRAME_FIND_PERIOD
		A.LoadFrames()
	end

	local mouseFocus = KongKontinued_GetMouseFocus()
	if ( mouseFocus ~= lastMouseFocus ) then
		local mouseStart = mouseFocus ~= nil and A.FindFirstTrackedRegion(mouseFocus) or nil
		if ( mouseStart ~= lastMouseStart ) then
			if ( mouseStart ~= nil ) then
				A.ForEachTrackedRegion(mouseStart, A.MouseoverRegionFader, A.FadeIn, 1)
			end
			if ( lastMouseStart ~= nil ) then
				A.ForEachTrackedRegion(lastMouseStart, A.MouseoverRegionFader, A.FadeOut, -1)
			end
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
