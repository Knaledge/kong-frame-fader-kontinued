local KONG_CONFIG_COLUMN_WIDTH = 166
local COLOR_UNREGISTERED = {.3, .3, 1, .7}
local COLOR_REGISTERED = {.3, 1, .3, .7}
local COLOR_SELECTED = {1, .3, .6, .7}
local COLOR_BORDER_SELECTED = {1, 1, 0, 1}
local COLOR_BORDER_DESELECTED = {1, 1, 1, 1}
local MIN_SIZE = 30
local COVER_BUTTON_BACKDROP = {
    bgFile = "Interface/Tooltips/UI-Tooltip-Background", 
    edgeFile = "Interface/Buttons/WHITE8X8", 
    edgeSize=1
}
local SLIDER_VALUE_NA = "-"
local TRIGGERS = "triggers" -- the array of triggers
local FIELD = "field" -- the trigger field
local TITLE = "title" -- the widget label
local TOOLTIP = "tooltip" -- the widget tooltip
local OWNER = "owner" -- anchor of the tooltip
local VALID = "valid" -- is the macro well formed
local FRAME = "frame" -- last frame to run a memory scan for
local UPDATE = "update" -- the widget update method
local ANCHOR = "anchor" -- the tooltip anchor location
local FADE_OUT_TIME = "Fade Out Time (sec)"
local FADE_IN_TIME = "Fade In Time (sec)"
local FADE_OUT_DELAY = "Fade Out Delay (sec)"
local SHOWN_ALPHA = "Shown Alpha"
local BRING_TO_FRONT = "Bring to Front |cFF00AAFF[Wheel Down]|r"
local SEND_TO_BACK = "Send to Back |cFF00AAFF[Wheel Up]|r"
local CONFIGURE_CHILDREN = "Configure Children"
local CONFIGURE_PARENT = "Configure Parent"
local CANCEL = "|TInterface/Buttons/UI-GroupLoot-Pass-Up:0:0:0:1|t Cancel"


local AceGUI = LibStub("AceGUI-3.0")
local LibUSC = LibStub("KongKontinuedConditions")

local Dropdown = LibStub("AceGUI-3.0"):Create("EasyMenuDropDown")

KongKontinuedConfig_SelectedFrames = {}
KongKontinuedConfig_Frames = {}
KongKontinuedConfig_NumFrames = 0

local KongKontinued_UnloadOriginal = KongKontinued_Unload
function KongKontinued_Unload()

    if KongKontinuedConfig then
        for i=#KongKontinuedConfig_ConditionsGroup.children,1,-1 do
            local Panel = KongKontinuedConfig_ConditionsGroup.children[i]
            local PanelTriggers = Panel:GetUserData("Triggers")
            
            -- For each trigger that was being configured in the panel
            for j=#PanelTriggers,1,-1 do
                local found = false
                local PanelTrigger = PanelTriggers[j]
                
                Panel:GetUserData("ConditionEditor"):RemoveCondition(PanelTrigger.Condition)
                tremove(PanelTriggers, j)
            end
            
            AceGUI:Release(tremove(KongKontinuedConfig_ConditionsGroup.children, i))
        end
    end
    
    KongKontinued_UnloadOriginal()
end

local function Simplify(str)

    str = gsub(str, "%[\"", ".")
    str = gsub(str, "\"%]", "")
    str = gsub(str, ":GetParent%(%)", "Parent")
    return string.sub(str, 2)
end                    

function KongKontinuedConfig_Error(str, ...)
    KongKontinuedConfig:SetStatusText("|cFFFF2222Error:|r "..string.format(str, ...))
end

function KongKontinuedConfig_Warning(str, ...)
    KongKontinuedConfig:SetStatusText("|cFFFF9922Warning:|r "..string.format(str, ...))
end

local KongKontinued_ErrorOriginal
local KongKontinued_WarningOriginal
local function IsPublic(value)
    return not (issecretvalue and issecretvalue(value))
end

local function GetPickerGeometry(Frame)
    if InCombatLockdown() or not KongKontinued_CanAccessFrame(Frame) then return end
    local restricted = Frame:IsAnchoringRestricted()
    local shown = Frame:IsShown()
    if not IsPublic(restricted) or restricted or not IsPublic(shown) or not shown then return end
    local width, height = Frame:GetWidth(), Frame:GetHeight()
    if not IsPublic(width) or not IsPublic(height) or type(width) ~= "number" or type(height) ~= "number" then return end
    return width, height
end

local CombatWatcher = CreateFrame("Frame")
CombatWatcher:RegisterEvent("PLAYER_REGEN_DISABLED")
CombatWatcher:SetScript("OnEvent", function()
    if KongKontinuedConfig and KongKontinuedConfig:IsShown() then
        KongKontinuedConfig:Hide()
        KongKontinued_Warning("Advanced Config closed for combat")
    end
end)

function KongKontinuedConfig_Show()

    if InCombatLockdown() then
        KongKontinued_Warning("Advanced Config cannot be opened during combat")
        return
    end
    if not KongKontinued_ConfirmLegacyDisabled() then return end
    if (not KongKontinuedConfig) or (not KongKontinuedConfig:IsVisible()) then
    
        -- Display registered frames
        for Frame in pairs(KongKontinued_Frames) do
            KongKontinued_Fade(Frame, 1, 1, 0)
        end
    
        -- Redirect errors and warnings to the status bar
        KongKontinued_ErrorOriginal = KongKontinued_Error
        KongKontinued_Error = KongKontinuedConfig_Error
        KongKontinued_WarningOriginal = KongKontinued_Warning
        KongKontinued_Warning = KongKontinuedConfig_Warning
    end
    
    KongKontinuedConfig_CreateComponents()
    KongKontinuedConfig_AutoExpandAndCollapse()
    KongKontinuedConfig:Show()
    
    -- Create the cover buttons
    KongKontinuedConfig_CreateChildCoverButtons(UIParent)
    for Frame in pairs(KongKontinued_Frames) do
        local Parent = KongKontinued_GetFrameParent(Frame)
        if Parent ~= UIParent then
            KongKontinuedConfig_CreateChildCoverButtons(Parent)
            
            -- Hide unregistered parents of registered Kong frames
            while Parent and Parent ~= UIParent do
                if KongKontinuedConfig_Frames[Parent] and not KongKontinued_Frames[Parent] then
                    KongKontinuedConfig_Frames[Parent]:Hide()
                end
                Parent = KongKontinued_GetFrameParent(Parent)
            end
        end
    end
    
    -- Deselect any frames that are no longer onscreen for configuration
    for _, PreviouslySelectedFrame in pairs(KongKontinuedConfig_SelectedFrames) do
        if not PreviouslySelectedFrame:IsShown() then
            KongKontinuedConfig_SelectedFrames[PreviouslySelectedFrame] = nil
        end
    end
    
    -- Make sure the config frame is on top
    KongKontinuedConfig.frame:SetFrameStrata("DIALOG")
    KongKontinuedConfig.frame:SetFrameLevel(KongKontinuedConfig_NumFrames)
    
    -- Update the config widgets' states
    KongKontinuedConfig_UpdateComponents()
    
end

function KongKontinuedConfig_CreateChildCoverButtons(Frame)
    for i,Child in pairs(KongKontinued_GetFrameChildren(Frame)) do
        if Child ~= KongKontinuedConfig.frame and not Child:IsObjectType("GameTooltip") then
            KongKontinuedConfig_CreateCoverButton(Child)
        end
    end
end

function KongKontinuedConfig_CreateCoverButton(Frame)

    local width, height = GetPickerGeometry(Frame)
    if not width then
        local cover = KongKontinuedConfig_Frames[Frame]
        if cover then cover:Hide(); KongKontinuedConfig_SelectedFrames[cover] = nil end
        return
    end
    local name = Frame:GetName()
    if not IsPublic(name) or type(name) ~= "string" then name = tostring(KongKontinuedConfig_NumFrames) end
    local configName = "KongKontinuedConfig_"..name
    if not KongKontinuedConfig_Frames[Frame] then
        local CoverButton
		
		CoverButton = CreateFrame("Button", configName, nil, "BackdropTemplate")
        CoverButton:SetFrameStrata("DIALOG")
        CoverButton:SetFrameLevel(KongKontinuedConfig_NumFrames)
        CoverButton:SetBackdrop(COVER_BUTTON_BACKDROP)
        CoverButton:SetHighlightTexture("Interface\\FullScreenTextures\\OutOfControl", "ADD");
        CoverButton.uiFrame = Frame
        
        -- Mouse wheel used to change frame level
        CoverButton:EnableMouseWheel(true)
        CoverButton:SetScript("OnMouseWheel", KongKontinuedConfig_CoverButton_OnMouseWheel)
        
        CoverButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        CoverButton:SetScript("OnClick", KongKontinuedConfig_CoverButton_OnClick)
        
        local text1 = CoverButton:CreateFontString(configName.."Title", "ARTWORK", "GameFontNormal")
        text1:SetPoint("CENTER")
        text1:SetTextColor(1, 1, 1, 1)
        if KongKontinued_Frames[Frame] then
            text1:SetText(Simplify(KongKontinued_Frames[Frame].index))
        else
            text1:SetText(Simplify(KongKontinued_FindGlobalIndex(Frame) or " <noname>"))
        end
        
        KongKontinuedConfig_Frames[Frame] = CoverButton
        KongKontinuedConfig_NumFrames = KongKontinuedConfig_NumFrames + 1
		
    else
        KongKontinuedConfig_Frames[Frame]:Show()
    end
    
    -- Distinguish between registered and unregistered frames
    if KongKontinuedConfig_SelectedFrames[KongKontinuedConfig_Frames[Frame]] then
        KongKontinuedConfig_Frames[Frame]:SetBackdropColor(unpack(COLOR_SELECTED))
    elseif KongKontinued_Frames[Frame] then 
        KongKontinuedConfig_Frames[Frame]:SetBackdropColor(unpack(COLOR_REGISTERED))
    else
        KongKontinuedConfig_Frames[Frame]:SetBackdropColor(unpack(COLOR_UNREGISTERED))
    end
    
    -- Expand config frame if too small
    local xoff, yoff = 0, 0
    if width < MIN_SIZE then
        xoff = (MIN_SIZE-width)/2
    end
    if height < MIN_SIZE then
        yoff = (MIN_SIZE-height)/2
    end
    KongKontinuedConfig_Frames[Frame]:SetPoint("TOPLEFT", Frame, "TOPLEFT", -xoff, yoff)
    KongKontinuedConfig_Frames[Frame]:SetPoint("BOTTOMRIGHT", Frame, "BOTTOMRIGHT", xoff, -yoff)
end

function KongKontinuedConfig_OnClose()

    KongKontinuedConfig_PersistAsCoroutine = nil
    if KongKontinuedConfig_PersistAsDropDown then KongKontinuedConfig_PersistAsDropDown:SetUserData(FRAME, nil) end
       
    CloseDropDownMenus() 
    
    for child, frame in pairs(KongKontinuedConfig_Frames) do
        frame:Hide()
    end
    
    -- Restore the original error display
    KongKontinued_Error = KongKontinued_ErrorOriginal
    KongKontinued_Warning = KongKontinued_WarningOriginal
    
    -- Re-hide registered frames
    for Frame in pairs(KongKontinued_Frames) do
        KongKontinued_CalculateFadeOut(Frame);
    end
    
    if not KongKontinued_Settings.enabled then
        KongKontinued_Warning("Kong Kontinued is currently disabled. Use |cFF33FF99/kong toggle|r to enable it.")
    end
end

function KongKontinuedConfig_ToggleChecked(self)
    local value = self:GetValue()
    if self.tristate then
        --cycle in [greyed,] checked, unchecked order
        if value then
            self:SetValue(false)
        elseif value == nil then
            self:SetValue(true)
        else
            self:SetValue(nil)
        end
    else
        self:SetValue(not self:GetValue())
    end
end

local function NegateBoolean(value)

    if string.sub(value, 1, 2) == "no" then
        return string.sub(value, 3)
    else
        return "no"..value
    end
end

-- GUI Setup ---------------------------------------------------------------------------------------
function KongKontinuedConfig_CreateComponents()

    if not KongKontinuedConfig then
    
        -- Create a container frame
        KongKontinuedConfig = AceGUI:Create("Frame")
        KongKontinuedConfig:SetTitle("Kong Kontinued: Advanced Config")
        KongKontinuedConfig:SetStatusText("Status Bar")
        KongKontinuedConfig:SetLayout("Flow")
        KongKontinuedConfig:SetWidth(264)
        KongKontinuedConfig:SetHeight(472)
        KongKontinuedConfig:SetStatusText("")
        KongKontinuedConfig.frame:SetScript("OnUpdate", KongKontinuedConfig_OnUpdate);
		if ( KongKontinuedConfig.frame.SetResizeBounds ~= nil ) then
			 KongKontinuedConfig.frame:SetResizeBounds(264, 264)
		else
			 KongKontinuedConfig.frame:SetMinResize(264, 264) -- Classic
		end
        tinsert(UISpecialFrames, "KongKontinuedConfig")
--KongKontinuedConfig:SetPoint("TOPLEFT", 0, -7)
        
        -- Make it opaque
        local kongback = KongKontinuedConfig.frame:GetBackdrop()
        kongback.bgFile = "Interface\\ChatFrame\\ChatFrameBackground"
        KongKontinuedConfig.frame:SetBackdrop(kongback)
        KongKontinuedConfig.frame:SetBackdropColor(0, 0, 0, 1)

        -- Register for cleanup
        KongKontinuedConfig:SetCallback("OnClose", KongKontinuedConfig_OnClose)

        -- Fade CheckBox
        KongKontinuedConfig_FadeCheckBox = AceGUI:Create("CheckBox")
        KongKontinuedConfig_FadeCheckBox:SetWidth(205)
        --KongKontinuedConfig_FadeCheckBox:SetHeight(12)
        --KongKontinuedConfig_FadeCheckBox.text:SetJustifyH("RIGHT")
        KongKontinuedConfig_FadeCheckBox:SetLabel("Hide Selected Frame(s)")
        KongKontinuedConfig_FadeCheckBox:SetCallback("OnValueChanged", KongKontinuedConfig_FadeCheckBox_OnValueChanged)
        KongKontinuedConfig_FadeCheckBox:SetCallback("OnEnter", KongKontinuedConfig_UpdateTooltip)
        KongKontinuedConfig_FadeCheckBox:SetCallback("OnLeave", KongKontinuedConfig_UpdateTooltip)
        KongKontinuedConfig_FadeCheckBox:SetUserData(TOOLTIP, "Registers the selected frame(s) to be controlled by Kong")
        --KongKontinuedConfig_FadeCheckBox.frame:SetHitRectInsets(0,0,0,-15)
        KongKontinuedConfig_FadeCheckBox.ToggleChecked = KongKontinuedConfig_ToggleChecked
        
        -- General Settings Scroll pane
        KongKontinuedConfig_ScrollFrame = AceGUI:Create("ScrollFrame")
        KongKontinuedConfig_ScrollFrame:SetFullWidth(true)
        KongKontinuedConfig_ScrollFrame:SetFullHeight(true)
        KongKontinuedConfig_ScrollFrame:SetLayout("List")
        
        KongKontinuedConfig_CreateDefaultComponents()
        KongKontinuedConfig_ScrollFrame:AddChild(KongKontinuedConfig_DefaultsGroup)
        
        KongKontinuedConfig_ConditionsCategoryGroup = AceGUI:Create("CollapsibleGroup")
        KongKontinuedConfig_ConditionsCategoryGroup:SetLayout("List")
        KongKontinuedConfig_ConditionsCategoryGroup:SetTitle("Show When")
        KongKontinuedConfig_ConditionsCategoryGroup:SetFullWidth(true)
        KongKontinuedConfig_ScrollFrame:AddChild(KongKontinuedConfig_ConditionsCategoryGroup)
        
        KongKontinuedConfig_ConditionsGroup = AceGUI:Create("SimpleGroup")
        KongKontinuedConfig_ConditionsGroup:SetLayout("List")
        KongKontinuedConfig_ConditionsGroup:SetFullWidth(true)
        KongKontinuedConfig_ConditionsCategoryGroup:AddChild(KongKontinuedConfig_ConditionsGroup)
        
        KongKontinuedConfig_AddConditionButton = AceGUI:Create("Button")
        KongKontinuedConfig_AddConditionButton:SetText("|TInterface\\LFGFrame\\LFGRole:16:16:0:0:64:16:48:64:0:16|t Add New Condition")
        KongKontinuedConfig_AddConditionButton:SetWidth(188)
        KongKontinuedConfig_AddConditionButton:SetHeight(20)
        KongKontinuedConfig_AddConditionButton:SetUserData(TITLE, "Add New Condition")
        KongKontinuedConfig_AddConditionButton:SetUserData(TOOLTIP, 
            "Creates a new condition that, when met, will cause the selected frame(s) to fade in.")
        KongKontinuedConfig_AddConditionButton:SetUserData(ANCHOR, "ANCHOR_BOTTOM")
        KongKontinuedConfig_AddConditionButton:SetCallback("OnClick",KongKontinuedConfig_AddConditionButton_OnClick)
        KongKontinuedConfig_AddConditionButton:SetCallback("OnEnter", KongKontinuedConfig_UpdateTooltip)
        KongKontinuedConfig_AddConditionButton:SetCallback("OnLeave", KongKontinuedConfig_UpdateTooltip)
        KongKontinuedConfig_ConditionsCategoryGroup:AddChild(KongKontinuedConfig_AddConditionButton)
        
        KongKontinuedConfig_CreateMouseoverGroupComponents()
        KongKontinuedConfig_ScrollFrame:AddChild(KongKontinuedConfig_MouseoverGroupsGroup)
        
        KongKontinuedConfig_CreateAdvancedComponents()
        KongKontinuedConfig_ScrollFrame:AddChild(KongKontinuedConfig_AdvancedGroup)
        
        -- Main panel
        KongKontinuedConfig:AddChild(KongKontinuedConfig_FadeCheckBox)
        KongKontinuedConfig:AddChild(KongKontinuedConfig_ScrollFrame)
    end
    
    -- Set the initial state of these frames
    KongKontinuedConfig_UpdateComponents() 
end

function KongKontinuedConfig_CreateDefaultComponents()

    KongKontinuedConfig_DefaultsGroup = AceGUI:Create("CollapsibleGroup")
    KongKontinuedConfig_DefaultsGroup:SetFullWidth(true)
    KongKontinuedConfig_DefaultsGroup:SetLayout("Flow")
    KongKontinuedConfig_DefaultsGroup:SetTitle("Defaults")
    KongKontinuedConfig_DefaultsGroup:SetCollapsed(true)
    
    local Triggers = {}
    KongKontinuedConfig_DefaultsGroup:SetUserData(TRIGGERS, Triggers)
    
    -- Hidden Alpha
    KongKontinuedConfig_HiddenAlphaCheckBox, KongKontinuedConfig_HiddenAlphaSlider, KongKontinuedConfig_HiddenAlphaGroup = 
        KongKontinuedConfig_CreateTriggerSliderGroup("Hidden Alpha", Triggers, "alphaOut", 
        "The transparency of the selected frame(s) when hidden by Kong")
    KongKontinuedConfig_HiddenAlphaSlider:SetIsPercent(true)
    KongKontinuedConfig_HiddenAlphaSlider:SetSliderValues(0, 1, .01)
    
    
    -- Shown Alpha
    KongKontinuedConfig_ShownAlphaCheckBox, KongKontinuedConfig_ShownAlphaSlider, KongKontinuedConfig_ShownAlphaGroup = 
        KongKontinuedConfig_CreateTriggerSliderGroup(SHOWN_ALPHA, Triggers, "alphaIn",
        "The default transparency of the selected frame(s) when shown by Kong. This can be overridden on a per-condition basis below.")
    KongKontinuedConfig_ShownAlphaSlider:SetIsPercent(true)
    KongKontinuedConfig_ShownAlphaSlider:SetSliderValues(0, 1, .01)
    
    -- Fade In
    KongKontinuedConfig_FadeInCheckBox, KongKontinuedConfig_FadeInSlider, KongKontinuedConfig_FadeInGroup = 
        KongKontinuedConfig_CreateTriggerSliderGroup(FADE_IN_TIME, Triggers, "secondsIn", 
        "The default duration over which to fade in the selected widget(s). This can be overridden on a per-condition basis below.")
    KongKontinuedConfig_FadeInSlider:SetSliderValues(0, 10, .1)

    -- Fade Out
    KongKontinuedConfig_FadeOutCheckBox, KongKontinuedConfig_FadeOutSlider, KongKontinuedConfig_FadeOutGroup = 
        KongKontinuedConfig_CreateTriggerSliderGroup(FADE_OUT_TIME, Triggers, "secondsOut",
        "The default duration over which to fade out the selected widget(s). This can be overridden on a per-condition basis below.")
    KongKontinuedConfig_FadeOutSlider:SetSliderValues(0, 10, .1)

    -- Fade Out Delay 
     KongKontinuedConfig_FadeOutDelayCheckBox, KongKontinuedConfig_FadeOutDelaySlider, KongKontinuedConfig_FadeOutDelayGroup = 
        KongKontinuedConfig_CreateTriggerSliderGroup(FADE_OUT_DELAY, Triggers, "secondsTillOut",
        "The default duration before which to fade out the selected widget(s). This can be overridden on a per-condition basis below.")
    KongKontinuedConfig_FadeOutDelaySlider:SetSliderValues(0, 60, 1)
	
    KongKontinuedConfig_DefaultsGroup:AddChild(KongKontinuedConfig_HiddenAlphaGroup)
    KongKontinuedConfig_DefaultsGroup:AddChild(KongKontinuedConfig_ShownAlphaGroup)
    KongKontinuedConfig_DefaultsGroup:AddChild(KongKontinuedConfig_FadeInGroup)
    KongKontinuedConfig_DefaultsGroup:AddChild(KongKontinuedConfig_FadeOutGroup)
    KongKontinuedConfig_DefaultsGroup:AddChild(KongKontinuedConfig_FadeOutDelayGroup)
end

function KongKontinuedConfig_CreateMouseoverGroupComponents()

    KongKontinuedConfig_MouseoverGroupsGroup = AceGUI:Create("CollapsibleGroup")
    KongKontinuedConfig_MouseoverGroupsGroup:SetLayout("Flow")
    KongKontinuedConfig_MouseoverGroupsGroup:SetFullWidth(true)
    KongKontinuedConfig_MouseoverGroupsGroup:SetTitle("Mouseover Grouping")
    KongKontinuedConfig_MouseoverGroupsGroup:SetCollapsed(true)
    
    KongKontinuedConfig_GroupsComboBox = AceGUI:Create("Dropdown")
    KongKontinuedConfig_GroupsComboBox:SetWidth(KONG_CONFIG_COLUMN_WIDTH)
    KongKontinuedConfig_GroupsComboBox:SetLabel("Mouseover Groups")
    KongKontinuedConfig_GroupsComboBox:SetMultiselect(true)
    KongKontinuedConfig_GroupsComboBox:SetCallback("OnValueChanged", KongKontinuedConfig_GroupsComboBox_OnValueChanged)
    KongKontinuedConfig_GroupsComboBox:SetUserData(TITLE, "Mouseover Groups Selection")
    KongKontinuedConfig_GroupsComboBox:SetUserData(TOOLTIP, "Lists the available mouseover groups. When the cursor enters any member of a mouseover group, all members of that group are shown. Groups that the selected frame(s) are part of are checked.")
    KongKontinuedConfig_GroupsComboBox:SetCallback("OnEnter", KongKontinuedConfig_UpdateTooltip)
    KongKontinuedConfig_GroupsComboBox:SetCallback("OnLeave", KongKontinuedConfig_UpdateTooltip)
    KongKontinuedConfig_GroupsComboBox.pullout.frame:Hide()
    
    KongKontinuedConfig_NewGroupEditBox = AceGUI:Create("EditBox")
    KongKontinuedConfig_NewGroupEditBox:SetWidth(KONG_CONFIG_COLUMN_WIDTH)
    KongKontinuedConfig_NewGroupEditBox:SetLabel("New Group:")
    KongKontinuedConfig_NewGroupEditBox:SetCallback("OnEnterPressed", KongKontinuedConfig_NewGroupEditBox_OnEnterPressed)
    KongKontinuedConfig_NewGroupEditBox:SetUserData(TITLE, "New Group Field")
    KongKontinuedConfig_NewGroupEditBox:SetUserData(TOOLTIP, "Adds the selected frame(s) to a new group with a given name.")
    KongKontinuedConfig_NewGroupEditBox:SetCallback("OnEnter", KongKontinuedConfig_UpdateTooltip)
    KongKontinuedConfig_NewGroupEditBox:SetCallback("OnLeave", KongKontinuedConfig_UpdateTooltip)
    
    KongKontinuedConfig_MouseoverGroupsGroup:AddChild(KongKontinuedConfig_GroupsComboBox)
    KongKontinuedConfig_MouseoverGroupsGroup:AddChild(KongKontinuedConfig_NewGroupEditBox)
end

function KongKontinuedConfig_CreateAdvancedComponents()

    KongKontinuedConfig_AdvancedGroup = AceGUI:Create("CollapsibleGroup")
    KongKontinuedConfig_AdvancedGroup:SetLayout("Flow")
    KongKontinuedConfig_AdvancedGroup:SetFullWidth(true)
    KongKontinuedConfig_AdvancedGroup:SetTitle("Advanced")
    KongKontinuedConfig_AdvancedGroup:SetCollapsed(true)
    
    KongKontinuedConfig_OverrideAlphaCheckBox = AceGUI:Create("CheckBox")
    KongKontinuedConfig_OverrideAlphaCheckBox:SetWidth(KONG_CONFIG_COLUMN_WIDTH)
    KongKontinuedConfig_OverrideAlphaCheckBox:SetLabel("Dummy SetAlpha Function")
    KongKontinuedConfig_OverrideAlphaCheckBox:SetCallback("OnValueChanged", KongKontinuedConfig_OverrideAlphaCheckBox_OnValueChanged)
    KongKontinuedConfig_OverrideAlphaCheckBox:SetUserData(TOOLTIP, "Add a dummy SetAlpha function to the selected frame(s) to prevent outside alpha changes.")
    KongKontinuedConfig_OverrideAlphaCheckBox:SetCallback("OnEnter", KongKontinuedConfig_UpdateTooltip)
    KongKontinuedConfig_OverrideAlphaCheckBox:SetCallback("OnLeave", KongKontinuedConfig_UpdateTooltip)
    KongKontinuedConfig_OverrideAlphaCheckBox.ToggleChecked = KongKontinuedConfig_ToggleChecked
    
    KongKontinuedConfig_HideAtZeroAlphaCheckBox = AceGUI:Create("CheckBox")
    KongKontinuedConfig_HideAtZeroAlphaCheckBox:SetWidth(KONG_CONFIG_COLUMN_WIDTH)
    KongKontinuedConfig_HideAtZeroAlphaCheckBox:SetLabel("Hide At Zero Alpha")
    KongKontinuedConfig_HideAtZeroAlphaCheckBox:SetCallback("OnValueChanged", KongKontinuedConfig_HideAtZeroAlpha_OnValueChanged)
    KongKontinuedConfig_HideAtZeroAlphaCheckBox:SetUserData(TOOLTIP, "Hides the frame(s) at zero alpha.")
    KongKontinuedConfig_HideAtZeroAlphaCheckBox:SetCallback("OnEnter", KongKontinuedConfig_UpdateTooltip)
    KongKontinuedConfig_HideAtZeroAlphaCheckBox:SetCallback("OnLeave", KongKontinuedConfig_UpdateTooltip)
    KongKontinuedConfig_HideAtZeroAlphaCheckBox.ToggleChecked = KongKontinuedConfig_ToggleChecked
    
    KongKontinuedConfig_PersistAsDropDown = AceGUI:Create("Dropdown")
    KongKontinuedConfig_PersistAsDropDown:SetFullWidth(true)
    KongKontinuedConfig_PersistAsDropDown:SetLabel("Save As")
    KongKontinuedConfig_PersistAsDropDown:SetCallback("OnValueChanged", KongKontinuedConfig_PersistAsComboBox_OnValueChanged)
    KongKontinuedConfig_PersistAsDropDown:SetUserData(TITLE, "Save As Selection")
    KongKontinuedConfig_PersistAsDropDown:SetUserData(TOOLTIP, "The \"name\" with which Kong saves settings associated with the selected widget. Kong will use this name to find the widget again at the next login or /reload, so try to pick something that will be there every session.")
    KongKontinuedConfig_PersistAsDropDown:SetCallback("OnEnter", KongKontinuedConfig_UpdateTooltip)
    KongKontinuedConfig_PersistAsDropDown:SetCallback("OnLeave", KongKontinuedConfig_UpdateTooltip)
    KongKontinuedConfig_PersistAsDropDown:SetList({""})
    KongKontinuedConfig_PersistAsDropDown.button:HookScript("OnClick", KongKontinuedConfig_PersistAsDropDown_OnClick);
    KongKontinuedConfig_PersistAsDropDown.pullout.frame:Hide()
    
    KongKontinuedConfig_AdvancedGroup:AddChild(KongKontinuedConfig_OverrideAlphaCheckBox)
    KongKontinuedConfig_AdvancedGroup:AddChild(KongKontinuedConfig_HideAtZeroAlphaCheckBox)
    KongKontinuedConfig_AdvancedGroup:AddChild(KongKontinuedConfig_PersistAsDropDown)
end

function KongKontinuedConfig_CreateTriggerPanel(Trigger, isMouseover)

    local ConditionEditor = AceGUI:Create("KongKontinuedConditionEditor")
    ConditionEditor:SetFullWidth(true)
    ConditionEditor:SetEnabled(not isMouseover)
    ConditionEditor:AddCondition(Trigger.Condition)
    
    local Triggers = {Trigger}
    
    local Group = AceGUI:Create("CollapsibleGroup")
    Group:SetFullWidth(true)
    Group:SetLayout("Flow")
    if isMouseover then
        Group:SetTitle("[Frame has Mouse Focus]")
    else
        Group:SetTitle(ConditionEditor)
    end
    Group:SetCollapsed(true)
    Group:SetUserData("Triggers", Triggers)
    Group:SetUserData("ConditionEditor", ConditionEditor)
    
    if isMouseover then
    
        local MouseoverText = AceGUI:Create("Label")
        MouseoverText:SetText("Mouseover fading is always\nenabled for registered frames.")
        MouseoverText:SetWidth(KONG_CONFIG_COLUMN_WIDTH)
        Group:SetUserData("MouseoverText", MouseoverText)
        
        Group:AddChild(MouseoverText)
    else
    
        local SyncButton = AceGUI:Create("Button")
        SyncButton:SetText("|TInterface/Buttons/UI-CheckBox-Check:0|t Sync")
        SyncButton:SetWidth(KONG_CONFIG_COLUMN_WIDTH/2)
        SyncButton:SetHeight(20)
        SyncButton:SetUserData(TITLE, "Synchronize Condition")
        SyncButton:SetUserData(TOOLTIP, 
            "Applies this condition to any selected frames that do not already have it")
        SyncButton:SetCallback("OnClick", KongKontinuedConfig_SyncButton_OnClick)
        SyncButton:SetCallback("OnEnter", KongKontinuedConfig_UpdateTooltip)
        SyncButton:SetCallback("OnLeave", KongKontinuedConfig_UpdateTooltip)
        SyncButton.frame:SetMotionScriptsWhileDisabled(true)
        Group:SetUserData("SyncButton", SyncButton)
        
        local DeleteButton = AceGUI:Create("Button")
        DeleteButton:SetText("|TInterface/Buttons/UI-GroupLoot-Pass-Up:0|tDelete")
        DeleteButton:SetWidth(KONG_CONFIG_COLUMN_WIDTH/2)
        DeleteButton:SetHeight(20)
        DeleteButton:SetUserData(TITLE, "Delete Condition")
        DeleteButton:SetUserData(TOOLTIP, "Removes this condition from the selected frame(s)")
        DeleteButton:SetCallback("OnClick", KongKontinuedConfig_DeleteButton_OnClick)
        DeleteButton:SetCallback("OnEnter", KongKontinuedConfig_UpdateTooltip)
        DeleteButton:SetCallback("OnLeave", KongKontinuedConfig_UpdateTooltip)
        Group:SetUserData("DeleteButton", DeleteButton)
    
        Group:AddChild(SyncButton)
        Group:AddChild(DeleteButton)
    end
    
    -- Alpha
    local AlphaCheckBox, AlphaSlider, AlphaGroup =
        KongKontinuedConfig_CreateTriggerSliderGroup(SHOWN_ALPHA, Triggers, "alphaIn",
        "The transparency of the selected frame(s) while the given condition is met")
    AlphaSlider:SetIsPercent(true)
    AlphaSlider:SetSliderValues(0, 1, .01)
    Group:SetUserData("AlphaCheckBox", AlphaCheckBox)
    Group:SetUserData("AlphaSlider", AlphaSlider)
      
    -- Fade In
    local FadeInCheckBox, FadeInSlider, FadeInGroup =
        KongKontinuedConfig_CreateTriggerSliderGroup(FADE_IN_TIME, Triggers, "secondsIn",
        "The duration over which to fade in the selected frame(s) when the given condition is met")
    FadeInSlider:SetSliderValues(0, 10, .1)
    Group:SetUserData("FadeInCheckBox", FadeInCheckBox)
    Group:SetUserData("FadeInSlider", FadeInSlider)

    -- Fade Out
    local FadeOutCheckBox, FadeOutSlider, FadeOutGroup =
        KongKontinuedConfig_CreateTriggerSliderGroup(FADE_OUT_TIME, Triggers, "secondsOut",
        "The duration over which to fade out the selected frame(s) when the given condition is no longer met")
    FadeOutSlider:SetSliderValues(0, 10, .1)
    Group:SetUserData("FadeOutCheckBox", FadeOutCheckBox)
    Group:SetUserData("FadeOutSlider", FadeOutSlider)
    
	-- Fade Out Delay
    local FadeOutDelayCheckBox, FadeOutDelaySlider, FadeOutDelayGroup =
        KongKontinuedConfig_CreateTriggerSliderGroup(FADE_OUT_DELAY, Triggers, "secondsTillOut",
        "The duration until which the selected frame(s) starts to fade out when the given condition is no longer met")
    FadeOutDelaySlider:SetSliderValues(0, 60, 1)
    Group:SetUserData("FadeOutDelayCheckBox", FadeOutDelayCheckBox)
    Group:SetUserData("FadeOutDelaySlider", FadeOutDelaySlider)
	
    Group:AddChild(AlphaGroup)
    Group:AddChild(FadeInGroup)
    Group:AddChild(FadeOutGroup)
    Group:AddChild(FadeOutDelayGroup)
	
    return Group
end

function KongKontinuedConfig_CreateTriggerSliderGroup(text, triggers, field, tooltip)

    local checkbox = AceGUI:Create("CheckBox")
    checkbox:SetLabel(text)
    checkbox:SetHeight(0)
    checkbox:SetUserData(TRIGGERS, triggers)
    checkbox:SetUserData(FIELD, field)
    checkbox:SetUserData(TITLE, text)
    checkbox:SetUserData(TOOLTIP, tooltip)
    checkbox:SetCallback("OnValueChanged", KongKontinuedConfig_SliderCheckBox_OnValueChanged)
    checkbox:SetCallback("OnEnter", KongKontinuedConfig_UpdateTooltip)
    checkbox:SetCallback("OnLeave", KongKontinuedConfig_UpdateTooltip)
    checkbox.ToggleChecked = KongKontinuedConfig_ToggleChecked
   
    local slider = AceGUI:Create("Slider")
    slider:SetLabel("")
    slider:SetUserData(TRIGGERS, triggers)
    slider:SetUserData(FIELD, field)
    slider:SetUserData(TITLE, text)
    slider:SetUserData(TOOLTIP, tooltip)
    slider:SetCallback("OnMouseUp", KongKontinuedConfig_TriggerSlider_OnMouseUp)
    slider:SetCallback("OnEnter", KongKontinuedConfig_UpdateTooltip)
    slider:SetCallback("OnLeave", KongKontinuedConfig_UpdateTooltip)
    slider.slider:SetHitRectInsets(0,0,0,0)

    local group = AceGUI:Create("SimpleGroup")
    group:SetWidth(KONG_CONFIG_COLUMN_WIDTH)
    group:SetLayout("Flow")
    group:AddChild(checkbox)
    group:AddChild(slider)
    
    checkbox:SetUserData(OWNER, group.frame)
    slider:SetUserData(OWNER, group.frame)
    
    return checkbox, slider, group
end

function KongKontinuedConfig_CoverButton_OnMouseWheel(self, dir)
    if InCombatLockdown() then return end

    if (dir == 1) then
        KongKontinuedConfig_SendToBack(self)
    else
        local lowestFrame
        for child, frame in pairs(KongKontinuedConfig_Frames) do
            if frame:IsMouseOver() and frame:IsShown() then
                if (not lowestFrame) or frame:GetFrameLevel() < lowestFrame:GetFrameLevel() then
                    lowestFrame = frame
                end
            end
        end
        if lowestFrame then
            KongKontinuedConfig_BringToFront(lowestFrame)
        end
    end
    
    -- Make wow re-assign mouse focus
    self:Hide()
    self:Show()
end

function KongKontinuedConfig_BringToFront(focus)
    local level = focus:GetFrameLevel()
    for child, frame in pairs(KongKontinuedConfig_Frames) do
        if frame:GetFrameLevel() > level then
            frame:SetFrameLevel(frame:GetFrameLevel() - 1)
        end
    end
    focus:SetFrameLevel(KongKontinuedConfig_NumFrames-1)
end

function KongKontinuedConfig_SendToBack(self) 
    local level = self:GetFrameLevel()
    for child, frame in pairs(KongKontinuedConfig_Frames) do
        if frame:GetFrameLevel() < level then
            frame:SetFrameLevel(frame:GetFrameLevel() + 1)
        end
    end
    self:SetFrameLevel(0)
end

function KongKontinuedConfig_CoverButton_OnClick(self, button)
    if InCombatLockdown() then return end

    if button == "RightButton" then
        for frame in pairs(KongKontinuedConfig_SelectedFrames) do
            KongKontinuedConfig_SelectedFrames[frame] = nil
            KongKontinuedConfig_CoverButton_Update(frame)
        end
        
        CloseDropDownMenus()
        
        Dropdown:SetMenuList({})
        Dropdown:AddItem(BRING_TO_FRONT)
        Dropdown:AddItem(SEND_TO_BACK)
        
        local parent = KongKontinued_GetFrameParent(self.uiFrame)
        if parent and parent ~= UIParent then
            Dropdown:AddItem(CONFIGURE_PARENT)
        end
        if #KongKontinued_GetFrameChildren(self.uiFrame) > 0 then
            Dropdown:AddItem(CONFIGURE_CHILDREN)
        end
        Dropdown:AddItem(CANCEL)

        Dropdown.obj = self
        ToggleDropDownMenu(nil, nil, Dropdown.dropdown, "cursor", 0, 0, 
            Dropdown.menuList)
    else
        KongKontinuedConfig_BringToFront(self)
    end
    
    -- Recolor Kong config frames
    if IsControlKeyDown() or IsShiftKeyDown() then
        if KongKontinuedConfig_SelectedFrames[self] then
            KongKontinuedConfig_SelectedFrames[self] = nil
        else
            KongKontinuedConfig_SelectedFrames[self] = self
        end
        KongKontinuedConfig_CoverButton_Update(self)
    else
        for frame in pairs(KongKontinuedConfig_SelectedFrames) do
            KongKontinuedConfig_SelectedFrames[frame] = nil
            KongKontinuedConfig_CoverButton_Update(frame)
        end
        KongKontinuedConfig_SelectedFrames[self] = self
        KongKontinuedConfig_CoverButton_Update(self)
    end

    KongKontinuedConfig_UpdateComponents() 
    KongKontinuedConfig_AutoExpandAndCollapse()
    
    if nil == next(KongKontinuedConfig_SelectedFrames) then
        KongKontinuedConfig:SetStatusText("Select a widget to configure.")
    else
        for child, frame in pairs(KongKontinuedConfig_Frames) do
            if frame:IsMouseOver() and frame ~= self then
                KongKontinuedConfig:SetStatusText("Use mouse wheel to uncover frames.")
                return
            end
        end
        if nil == next(KongKontinuedConfig_SelectedFrames, next(KongKontinuedConfig_SelectedFrames)) then
            KongKontinuedConfig:SetStatusText("Shift-click to select multiple frames.")
        else
            KongKontinuedConfig:SetStatusText("")
        end
    end
end

-- GUI Update --------------------------------------------------------------------------------------
function KongKontinuedConfig_AutoExpandAndCollapse()

    KongKontinuedConfig_ConditionsCategoryGroup:SetCollapsed(KongKontinuedConfig_FadeCheckBox:GetValue() == false)

    local hasAdvancedSettings = false
    for _, SelectedFrame in pairs(KongKontinuedConfig_SelectedFrames) do
        if KongKontinued_Frames[SelectedFrame.uiFrame] then
            if KongKontinued_Frames[SelectedFrame.uiFrame].overrideAlpha 
            or KongKontinued_Frames[SelectedFrame.uiFrame].hideAtZeroAlpha
            or type(KongKontinued_Frames[SelectedFrame.uiFrame].index) == "table" then 
                hasAdvancedSettings = true
            end
        end
    end
    if hasAdvancedSettings then
        KongKontinuedConfig_AdvancedGroup:SetCollapsed(false)
    end
end

local SelectedBackdrop = CopyTable(COVER_BUTTON_BACKDROP)
function KongKontinuedConfig_CoverButton_Update(button)
    
    if KongKontinuedConfig_SelectedFrames[button] then
        button:SetBackdrop(SelectedBackdrop)
        button:SetBackdropColor(unpack(COLOR_SELECTED))
        button:SetBackdropBorderColor(unpack(COLOR_BORDER_SELECTED))
        button:LockHighlight()
        _G[button:GetName().."Title"]:SetTextColor(1, 1, 0, 1)
    else
        button:SetBackdrop(COVER_BUTTON_BACKDROP)
        if KongKontinued_Frames[button.uiFrame] then 
            button:SetBackdropColor(unpack(COLOR_REGISTERED))
        else
            button:SetBackdropColor(unpack(COLOR_UNREGISTERED))
        end
        button:SetBackdropBorderColor(unpack(COLOR_BORDER_DESELECTED))
        button:GetHighlightTexture():SetVertexColor(1, 1, 1, 1)
        button:UnlockHighlight()
        _G[button:GetName().."Title"]:SetTextColor(1, 1, 1, 1)
    end
end

local SELECTION_BLINK_PERIOD = 1;
local updateTimer = 0;
function KongKontinuedConfig_OnUpdate(self, elapsed)
    
    updateTimer = updateTimer - elapsed;
    if updateTimer <= 0 then
        updateTimer = SELECTION_BLINK_PERIOD;
    end
    
    local numSelected = 0;
    SelectedBackdrop.edgeSize = 1 + math.abs(4*(updateTimer/SELECTION_BLINK_PERIOD)-2)
    for Frame in pairs(KongKontinuedConfig_SelectedFrames) do
        KongKontinuedConfig_CoverButton_Update(Frame)
        Frame:GetHighlightTexture():SetVertexColor(1, 1, 1, math.abs(2*(updateTimer/SELECTION_BLINK_PERIOD)-1))
        numSelected = numSelected + 1
    end
    
    local showTip
    local Focus = KongKontinued_GetMouseFocus()
    local numUnderCursor = 0
    for child, Frame in pairs(KongKontinuedConfig_Frames) do 
        showTip = (Frame == Focus)
        if Frame:IsMouseOver() then
            numUnderCursor = numUnderCursor + 1
        end
    end
    local unselectedUnderCursor = not KongKontinuedConfig_SelectedFrames[Focus]

    if showTip then
        GameTooltip:SetOwner(KongKontinuedConfig.frame, "ANCHOR_CURSOR")
        if (numUnderCursor > 0) and numSelected == 0 then
            GameTooltip:AddLine("Click to configure.")
        elseif (numUnderCursor > 0) and unselectedUnderCursor then
            GameTooltip:AddLine("Shift-click to select multiple widgets.")
        elseif numUnderCursor > 1 then
            GameTooltip:AddLine("Use the mouse wheel to uncover widgets.")
        end
    elseif GameTooltip:IsOwned(KongKontinuedConfig.frame) then
        GameTooltip:Hide()
    end
    
    if KongKontinuedConfig_PersistAsCoroutine
    and coroutine.status(KongKontinuedConfig_PersistAsCoroutine) == "suspended" then
        local status, err = coroutine.resume(KongKontinuedConfig_PersistAsCoroutine)
        if not status then
            error(err)
        end
    end
end

local MAX_DEPTH = 4
local searchSteps = 0
function KongKontinuedConfig_RecursiveFrameSearch(Frame, tbl, depth, path, numParents, ancestors)
    if not IsPublic(tbl) or (canaccesstable and not canaccesstable(tbl)) then return end
    ancestors = ancestors or {}
    if ancestors[tbl] then return end
    ancestors[tbl] = true
    for name, value in pairs(tbl) do
        searchSteps = searchSteps + 1
        if searchSteps >= 200 and KongKontinuedConfig_PersistAsCoroutine and coroutine.running() == KongKontinuedConfig_PersistAsCoroutine then
            searchSteps = 0
            coroutine.yield()
        end
        if IsPublic(name) and IsPublic(value) and ((type(name) == "string") or (type(name) == "number") or (type(name) == "boolean")) then
            if (type(value) == "table") and not rawequal(value, tbl) and (not canaccesstable or canaccesstable(value)) then
                table.insert(path, name)
                if rawequal(Frame, value) then
                    local root = tostring(path[1])
                    if (string.sub(root, 1, 4) ~= "Kong") and (string.sub(root, 1, 6) ~= "AceGUI") then
                        local code = "";
                        for i = 1,#path do
                            if type(path[i]) == "string" then
                                code = code .. "[" .. string.format("%q", path[i]) .. "]"
                            else
                                code = code .. "[" .. tostring(path[i]) .. "]"
                            end
                        end
                        code = code..string.rep(":GetParent()", numParents)
                        KongKontinuedConfig_PersistAsDropDown:AddItem(code, Simplify(code))
                    end
                elseif depth <= MAX_DEPTH then
                    KongKontinuedConfig_RecursiveFrameSearch(Frame, value, depth+1, path, numParents, ancestors)
                end
                table.remove(path)
            end
        end
    end
    ancestors[tbl] = nil
end

function KongKontinuedConfig_PersistableFramePathSearch(frame, numParents)
    searchSteps = 0
    KongKontinuedConfig_RecursiveFrameSearch(frame, _G, 1, {}, numParents)
    
    KongKontinuedConfig_UpdatePersistAsPullout(KongKontinuedConfig_PersistAsDropDown.pullout);
    coroutine.yield()
    for _, child in pairs(KongKontinued_GetFrameChildren(frame)) do
       KongKontinuedConfig_PersistableFramePathSearch(child, numParents+1)
    end
end

function KongKontinuedConfig_UpdatePersistAsPullout(pullout)
    local items = pullout.items
    local frame = pullout.frame
    local itemFrame = pullout.itemFrame
    
    local height = 8
    for i, item in pairs(items) do
        if i == 1 then
            item:SetPoint("TOP", itemFrame, "TOP", 0, -2)
        else
            item:SetPoint("TOP", items[i-1].frame, "BOTTOM", 0, 1)
        end
        
        item:Show()
        
        if item:GetText() == KongKontinuedConfig_PersistAsDropDown.text:GetText() then
            item.check:Show();
        end
        
        height = height + 16
    end
    itemFrame:SetHeight(height)
end

function KongKontinuedConfig_UpdateComponents()

    KongKontinuedConfig_FadeCheckBox:SetUserData(true, nil)
    KongKontinuedConfig_FadeCheckBox:SetUserData(false, nil)
    
    KongKontinuedConfig_HiddenAlphaCheckBox:SetUserData(true, nil)
    KongKontinuedConfig_HiddenAlphaCheckBox:SetUserData(false, nil)
    KongKontinuedConfig_ShownAlphaCheckBox:SetUserData(true, nil)
    KongKontinuedConfig_ShownAlphaCheckBox:SetUserData(false, nil)
    KongKontinuedConfig_FadeInCheckBox:SetUserData(true, nil)
    KongKontinuedConfig_FadeInCheckBox:SetUserData(false, nil)
    KongKontinuedConfig_FadeOutCheckBox:SetUserData(true, nil)
    KongKontinuedConfig_FadeOutCheckBox:SetUserData(false, nil)
	KongKontinuedConfig_FadeOutDelayCheckBox:SetUserData(true, nil)
	KongKontinuedConfig_FadeOutDelayCheckBox:SetUserData(false, nil)
    
    KongKontinuedConfig_OverrideAlphaCheckBox:SetUserData(true, nil)
    KongKontinuedConfig_OverrideAlphaCheckBox:SetUserData(false, nil)
    
    KongKontinuedConfig_HideAtZeroAlphaCheckBox:SetUserData(true, nil)
    KongKontinuedConfig_HideAtZeroAlphaCheckBox:SetUserData(false, nil)
    
    local Defaults = KongKontinuedConfig_DefaultsGroup:GetUserData(TRIGGERS)
    table.wipe(Defaults)
    
    for _, SelectedFrame in pairs(KongKontinuedConfig_SelectedFrames) do
        
        if KongKontinued_Frames[SelectedFrame.uiFrame] then
            
            KongKontinuedConfig_FadeCheckBox:SetUserData(true, true)
            
            local TriggerDefaults = KongKontinued_Frames[SelectedFrame.uiFrame].TriggerDefaults
            KongKontinuedConfig_HiddenAlphaCheckBox:SetUserData(nil ~= rawget(TriggerDefaults, "alphaOut"), true)
            KongKontinuedConfig_ShownAlphaCheckBox:SetUserData(nil ~= rawget(TriggerDefaults, "alphaIn"), true)
            KongKontinuedConfig_FadeInCheckBox:SetUserData(nil ~= rawget(TriggerDefaults, "secondsIn"), true)
            KongKontinuedConfig_FadeOutCheckBox:SetUserData(nil ~= rawget(TriggerDefaults, "secondsOut"), true)
			KongKontinuedConfig_FadeOutDelayCheckBox:SetUserData(nil ~= rawget(TriggerDefaults, "secondsTillOut"), true)
            tinsert(Defaults, TriggerDefaults)
              
            KongKontinuedConfig_OverrideAlphaCheckBox:SetUserData(true == KongKontinued_Frames[SelectedFrame.uiFrame].overrideAlpha, true) 
            KongKontinuedConfig_HideAtZeroAlphaCheckBox:SetUserData(true == KongKontinued_Frames[SelectedFrame.uiFrame].hideAtZeroAlpha, true) 
        else
           KongKontinuedConfig_FadeCheckBox:SetUserData(false, true)
        end
    end
    
    KongKontinuedConfig_SetCheckBox(KongKontinuedConfig_FadeCheckBox)
    
    KongKontinuedConfig_SetCheckBox(KongKontinuedConfig_HiddenAlphaCheckBox)
    KongKontinuedConfig_SetCheckBox(KongKontinuedConfig_ShownAlphaCheckBox)
    KongKontinuedConfig_SetCheckBox(KongKontinuedConfig_FadeInCheckBox)
    KongKontinuedConfig_SetCheckBox(KongKontinuedConfig_FadeOutCheckBox)
    KongKontinuedConfig_SetCheckBox(KongKontinuedConfig_FadeOutDelayCheckBox)
    
    KongKontinuedConfig_SetCheckBox(KongKontinuedConfig_OverrideAlphaCheckBox)
    KongKontinuedConfig_SetCheckBox(KongKontinuedConfig_HideAtZeroAlphaCheckBox)
    
    local fade = KongKontinuedConfig_FadeCheckBox:GetValue()
    
    KongKontinuedConfig_FadeCheckBox:SetDisabled(nil == next(KongKontinuedConfig_SelectedFrames))

    KongKontinuedConfig_HiddenAlphaCheckBox:SetDisabled(not fade)
    KongKontinuedConfig_HiddenAlphaSlider:SetDisabled(not (fade and KongKontinuedConfig_HiddenAlphaCheckBox:GetValue()))
    KongKontinuedConfig_ShownAlphaCheckBox:SetDisabled(not fade)
    KongKontinuedConfig_ShownAlphaSlider:SetDisabled(not (fade and KongKontinuedConfig_ShownAlphaCheckBox:GetValue()))
    KongKontinuedConfig_FadeInCheckBox:SetDisabled(not fade)
    KongKontinuedConfig_FadeInSlider:SetDisabled(not (fade and KongKontinuedConfig_FadeInCheckBox:GetValue()))
    KongKontinuedConfig_FadeOutCheckBox:SetDisabled(not fade)
    KongKontinuedConfig_FadeOutSlider:SetDisabled(not (fade and KongKontinuedConfig_FadeOutCheckBox:GetValue()))
	KongKontinuedConfig_FadeOutDelayCheckBox:SetDisabled(not fade)
	KongKontinuedConfig_FadeOutDelaySlider:SetDisabled(not (fade and KongKontinuedConfig_FadeOutDelayCheckBox:GetValue()))
    
    KongKontinuedConfig_AddConditionButton:SetDisabled(not fade)
    
    KongKontinuedConfig_GroupsComboBox:SetDisabled(not fade)
    KongKontinuedConfig_NewGroupEditBox:SetDisabled(not fade)
    
    KongKontinuedConfig_OverrideAlphaCheckBox:SetDisabled(not fade)
    KongKontinuedConfig_HideAtZeroAlphaCheckBox:SetDisabled(not fade)
    local selectedFrame = next(KongKontinuedConfig_SelectedFrames)
    KongKontinuedConfig_PersistAsDropDown:SetDisabled(not (fade and selectedFrame and not next(KongKontinuedConfig_SelectedFrames, selectedFrame)))
    
    -- Slider display
    KongKontinuedConfig_UpdateTriggerSlider(KongKontinuedConfig_HiddenAlphaSlider)
    KongKontinuedConfig_UpdateTriggerSlider(KongKontinuedConfig_ShownAlphaSlider)
    KongKontinuedConfig_UpdateTriggerSlider(KongKontinuedConfig_FadeInSlider)
    KongKontinuedConfig_UpdateTriggerSlider(KongKontinuedConfig_FadeOutSlider)
	KongKontinuedConfig_UpdateTriggerSlider(KongKontinuedConfig_FadeOutDelaySlider)
    
    -- Hidden and Shown alpha are constrained by one another
    if KongKontinuedConfig_FadeCheckBox:GetValue() then
        KongKontinuedConfig_ShownAlphaSlider:SetSliderValues(floor(KongKontinuedConfig_HiddenAlphaSlider:GetValue()*100+.5)/100, 1, .01)
        KongKontinuedConfig_HiddenAlphaSlider:SetSliderValues(0, floor(KongKontinuedConfig_ShownAlphaSlider:GetValue()*100+.5)/100, .01)
    end
    
    KongKontinuedConfig_UpdateConditions()
    
    KongKontinuedConfig_UpdateGroups()
    
    KongKontinuedConfig_UpdateAdvanced()
end

function KongKontinuedConfig_UpdateConditions()
    
    -- Check for new conditions in each selected frame
    for Frame in pairs(KongKontinuedConfig_SelectedFrames) do
        -- If registered
        if KongKontinued_Frames[Frame.uiFrame] then
            -- For each trigger in the frame
            for _, FrameTrigger in ipairs(KongKontinued_Frames[Frame.uiFrame]) do
                local found = false
                -- Check the trigger against each panel in the GUI
                for i, TriggerPanel in ipairs(KongKontinuedConfig_ConditionsGroup.children) do
                    local GUITrigger = TriggerPanel:GetUserData("Triggers")[1]
                    -- If the triggers have the same structure
                    if GUITrigger.Condition:Equals(FrameTrigger.Condition) then
                        local duplicate = false
                        -- Check if the trigger is already being configured by the panel
                        for _, GUITrigger in ipairs(TriggerPanel:GetUserData("Triggers")) do
                            if FrameTrigger == GUITrigger then
                                found = true
                                break
                            elseif FrameTrigger.Frame == GUITrigger.Frame then
                                -- Each panel should only have one trigger for any single frame
                                duplicate = true
                            end
                        end
                        -- Otherwise
                        if (not found) and (not duplicate) then
                            tinsert(TriggerPanel:GetUserData("Triggers"), FrameTrigger)
                            TriggerPanel:GetUserData("ConditionEditor"):AddCondition(
                                FrameTrigger.Condition)
                            found = true
                            break
                        end
                    end
                end
                -- Add a panel for the trigger if one doesn't exist
                if not found then
                    KongKontinuedConfig_ConditionsGroup:AddChild(KongKontinuedConfig_CreateTriggerPanel(
                        FrameTrigger, FrameTrigger == KongKontinued_Frames[Frame.uiFrame].Mouseover))
                end
            end
        end
    end
    
    -- Remove old or duplicate panels, disable panels that aren't used by all selected frames
    for i=#KongKontinuedConfig_ConditionsGroup.children,1,-1 do
        local Panel = KongKontinuedConfig_ConditionsGroup.children[i]
        local PanelTriggers = Panel:GetUserData("Triggers")
        
        -- For each trigger that was being configured in the panel
        for j=#PanelTriggers,1,-1 do
            local found = false
            local PanelTrigger = PanelTriggers[j]
            
            -- For each selected frame
            for Frame in pairs(KongKontinuedConfig_SelectedFrames) do
                
                -- If registered
                if KongKontinued_Frames[Frame.uiFrame] then
                
                    -- Does the trigger belong to this frame?
                    for _, FrameTrigger in ipairs(KongKontinued_Frames[Frame.uiFrame]) do
                        if PanelTrigger == FrameTrigger then
                            found = true
                            break
                        end
                    end
                end
                if found then
                    break
                end
            end
            -- Remove the trigger if its frame was deselected or unregistered
            if not found then
                Panel:GetUserData("ConditionEditor"):RemoveCondition(PanelTrigger.Condition)
                tremove(PanelTriggers, j)
            end
        end
        
        -- Remove the panel if all its triggers were removed
        if #PanelTriggers == 0 then
            AceGUI:Release(tremove(KongKontinuedConfig_ConditionsGroup.children, i))
            KongKontinuedConfig_ScrollFrame:DoLayout()
        else
            -- Update panels state
            local AlphaCheckBox = Panel:GetUserData("AlphaCheckBox")
            local FadeInCheckBox = Panel:GetUserData("FadeInCheckBox")
            local FadeOutCheckBox = Panel:GetUserData("FadeOutCheckBox")
			local FadeOutDelayCheckBox = Panel:GetUserData("FadeOutDelayCheckBox")
            
            AlphaCheckBox:SetUserData(true, nil)
            AlphaCheckBox:SetUserData(false, nil)
            FadeInCheckBox:SetUserData(true, nil)
            FadeInCheckBox:SetUserData(false, nil)
            FadeOutCheckBox:SetUserData(true, nil)
            FadeOutCheckBox:SetUserData(false, nil)
			FadeOutDelayCheckBox:SetUserData(true, nil)
			FadeOutDelayCheckBox:SetUserData(false, nil)
            
            local foundInAllFrames = true
			for Frame in pairs(KongKontinuedConfig_SelectedFrames) do
                local found = false	
                if KongKontinued_Frames[Frame.uiFrame] then
                
                    -- Check if there's a trigger being configured for this frame
                    for _, PanelTrigger in ipairs(PanelTriggers) do
                        if PanelTrigger.Frame == Frame.uiFrame then
                            found = true
                            AlphaCheckBox:SetUserData(nil ~= rawget(PanelTrigger, "alphaIn"), true)
                            FadeInCheckBox:SetUserData(nil ~= rawget(PanelTrigger, "secondsIn"), true)
                            FadeOutCheckBox:SetUserData(nil ~= rawget(PanelTrigger, "secondsOut"), true)
							FadeOutDelayCheckBox:SetUserData(nil ~= rawget(PanelTrigger, "secondsTillOut"), true)
                            break
                        end
                    end
                end
                foundInAllFrames = foundInAllFrames and found
            end
            
            local MouseoverText = Panel:GetUserData("MouseoverText")
            if MouseoverText then
                if foundInAllFrames then 
                    Panel:SetTitle("Frame has Mouse Focus")
                    MouseoverText.label:SetTextColor(1,1,1);
                else
                    Panel:SetTitle("|cFF888888Frame has Mouse Focus")
                    MouseoverText.label:SetTextColor(.5,.5,.5);
                end
            else
                Panel:GetUserData("ConditionEditor"):SetEnabled(foundInAllFrames)
            
                local SyncButton = Panel:GetUserData("SyncButton")
                local fade = KongKontinuedConfig_FadeCheckBox:GetValue()
                SyncButton:SetDisabled((not fade) or foundInAllFrames)
            end
            
            AlphaCheckBox:SetDisabled(not foundInAllFrames)
            KongKontinuedConfig_SetCheckBox(AlphaCheckBox)
            
            FadeInCheckBox:SetDisabled(not foundInAllFrames)
            KongKontinuedConfig_SetCheckBox(FadeInCheckBox)
            
            FadeOutCheckBox:SetDisabled(not foundInAllFrames)
            KongKontinuedConfig_SetCheckBox(FadeOutCheckBox)
            
			FadeOutDelayCheckBox:SetDisabled(not foundInAllFrames)
			KongKontinuedConfig_SetCheckBox(FadeOutDelayCheckBox)
			
            local AlphaSlider = Panel:GetUserData("AlphaSlider")
            AlphaSlider:SetDisabled(not (foundInAllFrames and AlphaCheckBox:GetValue()))
            AlphaSlider:SetSliderValues(floor(KongKontinuedConfig_HiddenAlphaSlider:GetValue()*100+.5)/100, 1, .01)
            KongKontinuedConfig_UpdateTriggerSlider(AlphaSlider)
            
            local FadeInSlider = Panel:GetUserData("FadeInSlider")
            FadeInSlider:SetDisabled(not (foundInAllFrames and FadeInCheckBox:GetValue()))
            KongKontinuedConfig_UpdateTriggerSlider(FadeInSlider)
            
            local FadeOutSlider = Panel:GetUserData("FadeOutSlider")
            FadeOutSlider:SetDisabled(not (foundInAllFrames and FadeOutCheckBox:GetValue()))
            KongKontinuedConfig_UpdateTriggerSlider(FadeOutSlider)
			
			local FadeOutDelaySlider = Panel:GetUserData("FadeOutDelaySlider")
			FadeOutDelaySlider:SetDisabled(not (foundInAllFrames and FadeOutDelayCheckBox:GetValue()))
			KongKontinuedConfig_UpdateTriggerSlider(FadeOutDelaySlider)
        end
    end
    
    -- Fix for crazy empty group sizes
    if #KongKontinuedConfig_ConditionsGroup.children == 0 then
        if KongKontinuedConfig_ConditionsCategoryGroup.children[1] == KongKontinuedConfig_ConditionsGroup then
            tremove(KongKontinuedConfig_ConditionsCategoryGroup.children, 1)
            KongKontinuedConfig_ConditionsGroup.frame:Hide()
            KongKontinuedConfig_ConditionsCategoryGroup:DoLayout()
        end
    elseif KongKontinuedConfig_ConditionsCategoryGroup.children[1] ~= KongKontinuedConfig_ConditionsGroup then
        tinsert(KongKontinuedConfig_ConditionsCategoryGroup.children, 1, KongKontinuedConfig_ConditionsGroup)
        KongKontinuedConfig_ConditionsGroup.frame:Show()
        KongKontinuedConfig_ConditionsCategoryGroup:DoLayout()
    end
end

function KongKontinuedConfig_UpdateGroups()

    if KongKontinuedConfig_FadeCheckBox:GetValue() then
        -- Populate the group pulldown
        local groups = {}
        for name in pairs(KongKontinued_Settings.Groups) do 
            groups[name] = name
        end
        KongKontinuedConfig_GroupsComboBox:SetList(groups)
        
        -- Select items based on state
        for i, widget in KongKontinuedConfig_GroupsComboBox.pullout:IterateItems() do
            if widget.type == "Dropdown-Item-Toggle" then
            
                widget:SetUserData(true, nil)
                widget:SetUserData(false, nil)
                
                for _, SelectedFrame in pairs(KongKontinuedConfig_SelectedFrames) do
                    if KongKontinued_Frames[SelectedFrame.uiFrame] then
                        
                        widget:SetUserData(nil ~= 
                            KongKontinued_Settings.Groups[widget:GetText()][KongKontinued_Frames[SelectedFrame.uiFrame].index], true)
                    end
                end
                
                local set, clear = widget:GetUserData(true), widget:GetUserData(false)
                if set and clear then
                    widget.value = nil
                    widget.check:Show()
                    SetDesaturation(widget.check, true)
                else
                    KongKontinuedConfig_GroupsComboBox:SetItemValue(widget:GetText(), set)
                    SetDesaturation(widget.check, false)
                end
            end
        end
        
        if KongKontinuedConfig_GroupsComboBox.open then
            KongKontinuedConfig_GroupsComboBox.pullout:Open("TOPLEFT", KongKontinuedConfig_GroupsComboBox.frame, "BOTTOMLEFT", 0, KongKontinuedConfig_GroupsComboBox.label:IsShown() and -2 or 0)
        end
    else
        KongKontinuedConfig_GroupsComboBox:SetList({})
        KongKontinuedConfig_GroupsComboBox.pullout:Close()
    end
    
    KongKontinuedConfig_NewGroupEditBox.editbox:ClearFocus()
    KongKontinuedConfig_NewGroupEditBox:SetText("")
end

function KongKontinuedConfig_UpdateAdvanced()
    
    local selectedFrame = next(KongKontinuedConfig_SelectedFrames)
    if selectedFrame then
        if not next(KongKontinuedConfig_SelectedFrames, selectedFrame) then
        
            KongKontinuedConfig_PersistAsDropDown:SetText(_G[selectedFrame:GetName().."Title"]:GetText())
        else
            KongKontinuedConfig_PersistAsDropDown:SetText("Too many widgets selected");
            KongKontinuedConfig_PersistAsDropDown.pullout:Close()
        end
    else
        KongKontinuedConfig_PersistAsDropDown:SetText("");
        KongKontinuedConfig_PersistAsDropDown.pullout:Close()
    end

    if not KongKontinuedConfig_FadeCheckBox:GetValue() then
        KongKontinuedConfig_PersistAsDropDown.pullout:Close()
    end
end

function KongKontinuedConfig_SetCheckBox(checkbox)
    
    local set, clear = checkbox:GetUserData(true), checkbox:GetUserData(false)
    if set and clear then
        checkbox:SetTriState(true)
        checkbox:SetValue(nil)
    else
        checkbox:SetTriState(false)
        checkbox:SetValue(set == true)
    end
end

function KongKontinuedConfig_UpdateTriggerSlider(slider)

    slider:SetValue((slider.min+slider.max)/2)
    slider.editbox:SetText(SLIDER_VALUE_NA)

    -- N/A if not all selected frames are registered
    for _, SelectedFrame in pairs(KongKontinuedConfig_SelectedFrames) do
        if not KongKontinued_Frames[SelectedFrame.uiFrame] then
            slider:SetValue((slider.min+slider.max)/2)
            slider.editbox:SetText(SLIDER_VALUE_NA)
            return
        end
    end
    
    -- N/A if not all Trigger values match
    local Triggers, field = slider:GetUserData(TRIGGERS), slider:GetUserData(FIELD)
    local sliderValue, currentValue
    for _, Trigger in ipairs(Triggers) do
    
        currentValue = Trigger[field]
        
        if not sliderValue then
            sliderValue = currentValue
            slider:SetValue(sliderValue)
        elseif sliderValue ~= currentValue then
            slider:SetValue((slider.min+slider.max)/2)
            slider.editbox:SetText(SLIDER_VALUE_NA)
            break
        end
    end
end

-- Callbacks ---------------------------------------------------------------------------------------
function KongKontinuedConfig_SliderCheckBox_OnValueChanged(self) 
    
    KongKontinuedConfig:SetStatusText("")

    local triggers, field = self:GetUserData(TRIGGERS), self:GetUserData(FIELD)

    if self:GetValue() then
        for i, trigger in ipairs(triggers) do 
            trigger[field] = trigger[field] -- Read from metatable
        end
    else
        for i, trigger in ipairs(triggers) do 
            rawset(trigger, field, nil)
        end
    end
    
    KongKontinuedConfig_UpdateComponents()
end

function KongKontinuedConfig_TriggerSlider_OnMouseUp(self, _, value)
  
    KongKontinuedConfig:SetStatusText("")

    self:SetValue(value)
    
    local triggers, field = self:GetUserData(TRIGGERS), self:GetUserData(FIELD)
    for i, trigger in ipairs(triggers) do
        trigger[field] = value
    end
    
    KongKontinuedConfig_UpdateComponents()
end

function KongKontinuedConfig_FadeCheckBox_OnValueChanged() 
    
    KongKontinuedConfig:SetStatusText("")

    local hide = KongKontinuedConfig_FadeCheckBox:GetValue()
    if hide then
        for frame in pairs(KongKontinuedConfig_SelectedFrames) do
            if not KongKontinued_Frames[frame.uiFrame] then
                KongKontinued_RegisterFrame(frame.uiFrame)
            end
        end
    else
        for frame in pairs(KongKontinuedConfig_SelectedFrames) do
            if KongKontinued_Frames[frame.uiFrame] then
                KongKontinued_UnregisterFrame(frame.uiFrame)
            end
        end
    end

    KongKontinuedConfig_UpdateComponents()
    KongKontinuedConfig_AutoExpandAndCollapse()
end

function KongKontinuedConfig_AddConditionButton_OnClick()

    for Frame in pairs(KongKontinuedConfig_SelectedFrames) do
        KongKontinued_AddTrigger(Frame.uiFrame, LibUSC:Create("Condition", LibUSC:Create("False")))
    end
    
    KongKontinuedConfig_UpdateComponents()
end

function KongKontinuedConfig_SyncButton_OnClick(self, button, down)

    local ConfigPanel = self.parent
    local Triggers = ConfigPanel:GetUserData("Triggers")
    
    for Frame in pairs(KongKontinuedConfig_SelectedFrames) do
        local found = false
        
        for _, Trigger in ipairs(Triggers) do
            if Frame.uiFrame == Trigger.Frame then
                found = true
                break
            end
        end
        
        if not found then
            KongKontinued_AddTrigger(Frame.uiFrame, Triggers[1].Condition:Clone())
            
            -- TODO Copy fade settings if selected triggers are in agreement on them
        end
    end
    
    KongKontinuedConfig_UpdateComponents()
end

function KongKontinuedConfig_DeleteButton_OnClick(self, button, down)

    local ConfigPanel = self.parent
    local Triggers = ConfigPanel:GetUserData("Triggers")
    
    for i, child in ipairs(KongKontinuedConfig_ConditionsGroup.children) do 
        if child == ConfigPanel then
            AceGUI:Release(tremove(KongKontinuedConfig_ConditionsGroup.children, i))
            break
        end
    end

    for i=#Triggers,1,-1 do
        local Trigger = Triggers[i]
        KongKontinued_RemoveTrigger(Trigger.Frame, Trigger)
        tremove(Triggers, i)
    end
    
    KongKontinuedConfig_UpdateComponents()
    GameTooltip:Hide()
end

function KongKontinuedConfig_GroupsComboBox_OnValueChanged(self, _, group, checked)
    
    KongKontinuedConfig:SetStatusText("")

    for frame in pairs(KongKontinuedConfig_SelectedFrames) do
        if checked then
            KongKontinued_AddFrameToGroup(frame.uiFrame, group)
        else
            KongKontinued_RemoveFrameFromGroup(frame.uiFrame, group)
        end
    end
    
    KongKontinuedConfig_UpdateComponents()
end

function KongKontinuedConfig_NewGroupEditBox_OnEnterPressed(self, _, text)
    
    if text == "" then
        KongKontinuedConfig_Error("Group name cannot be empty.")
        return
    else
        KongKontinuedConfig:SetStatusText("")
    end
    
    for frame in pairs(KongKontinuedConfig_SelectedFrames) do
        KongKontinued_AddFrameToGroup(frame.uiFrame, string.lower(text))
    end
    
    KongKontinuedConfig_UpdateComponents()
end

function KongKontinuedConfig_OverrideAlphaCheckBox_OnValueChanged(self)
    
    KongKontinuedConfig:SetStatusText("")
    
    local override = self:GetValue()

    for Frame in pairs(KongKontinuedConfig_SelectedFrames) do
        KongKontinued_Frames[Frame.uiFrame].overrideAlpha = override
        KongKontinued_OverrideAlpha(Frame.uiFrame, override)
    end
    
    KongKontinuedConfig_UpdateComponents()
end

function KongKontinuedConfig_HideAtZeroAlpha_OnValueChanged(self)
	KongKontinuedConfig:SetStatusText("")
	
	for frame in pairs(KongKontinuedConfig_SelectedFrames) do
		KongKontinued_Frames[frame.uiFrame].hideAtZeroAlpha = self:GetValue()
		KongKontinued_UpdateFrameVisibility(frame.uiFrame)
	end
	
	KongKontinuedConfig_UpdateComponents()
end

function KongKontinuedConfig_PersistAsDropDown_OnClick(self, button, down)
    if InCombatLockdown() then return end

    KongKontinuedConfig_PersistAsDropDown.pullout:SetWidth(KongKontinuedConfig_PersistAsDropDown.frame:GetWidth() - 30);
    
    -- Scan memory if a new frame was selected since last time
    local Frame = next(KongKontinuedConfig_SelectedFrames)
    if Frame ~= KongKontinuedConfig_PersistAsDropDown:GetUserData(FRAME) then
        KongKontinuedConfig_PersistAsDropDown:SetUserData(FRAME, Frame)
        KongKontinuedConfig_PersistAsDropDown:SetList({})
        KongKontinuedConfig_PersistAsCoroutine = coroutine.create(KongKontinuedConfig_PersistableFramePathSearch)
        local status, err = coroutine.resume(KongKontinuedConfig_PersistAsCoroutine, Frame.uiFrame, 0)
        if not status then
            error(err)
        end
    end
end

function KongKontinuedConfig_PersistAsComboBox_OnValueChanged(self, _, code)

    KongKontinuedConfig:SetStatusText("")
    
    local Frame = next(KongKontinuedConfig_SelectedFrames)
    
    KongKontinued_RenameFrame(Frame.uiFrame, code)
    _G[Frame:GetName().."Title"]:SetText(Simplify(code))
    
    KongKontinuedConfig_UpdateComponents()
end

function KongKontinuedConfig_UpdateTooltip(self, event)
    
    if event == "OnEnter" then
        GameTooltip:SetOwner(self:GetUserData(OWNER) or self.frame, 
            self:GetUserData(ANCHOR) or "ANCHOR_TOP")
        GameTooltip:AddLine(self:GetUserData(TITLE) or self.text:GetText())
        
        GameTooltip:AddLine(self:GetUserData(TOOLTIP) or 
            self:GetUserData(TOOLTIP..self:GetUserData(TRIGGER)), 1,1,1,1,1)
        
        GameTooltip:Show()
    else
        GameTooltip:Hide()
    end
end

function KongKontinuedConfig_OnDropdownValueChanged(Dropdown, _, value)
    if InCombatLockdown() then return end
    
    local CoverButton = Dropdown.obj;
    if value == BRING_TO_FRONT then
        KongKontinuedConfig_BringToFront(CoverButton)
    elseif value == SEND_TO_BACK then
        KongKontinuedConfig_SendToBack(CoverButton)
    elseif value == CONFIGURE_CHILDREN then
        KongKontinuedConfig_CreateChildCoverButtons(CoverButton.uiFrame)
        if KongKontinued_Frames[CoverButton.uiFrame] then
            KongKontinuedConfig_SendToBack(CoverButton)
        else
            CoverButton:Hide();
        end
    elseif value == CONFIGURE_PARENT then
        local Parent = KongKontinued_GetFrameParent(CoverButton.uiFrame)
        if not Parent then return end
        for _, Child in pairs(KongKontinued_GetFrameChildren(Parent)) do
            if KongKontinuedConfig_Frames[Child] and not KongKontinued_Frames[Child] then
                KongKontinuedConfig_Frames[Child]:Hide()
            end
        end
        KongKontinuedConfig_CreateCoverButton(Parent)
        KongKontinuedConfig_BringToFront(KongKontinuedConfig_Frames[Parent])
    end
end
Dropdown:SetCallback("OnValueChanged", KongKontinuedConfig_OnDropdownValueChanged)
