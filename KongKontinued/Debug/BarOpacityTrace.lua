local _, A = ...
local transparency = A.FramePresetTransparency
if type(SlashCmdList) ~= "table" then return end

local capture, companionLoadWatcher, report, reportText
local coreHooked, companionHooked, companionFrame
local hookedBars = setmetatable({}, {__mode = "k"})
local maxEntries = 48

local function IsTarget(region)
    return capture and not (issecretvalue and issecretvalue(region)) and rawequal(region, capture.region)
end

local function PublicText(value)
    if (issecretvalue and issecretvalue(value)) or value == nil then return "-" end
    return type(value) == "number" and string.format("%.4f", value) or tostring(value)
end

local function ReadOpacity(region, method)
    if KongKontinued_CanAccessFrame(region) then
        local ok, value = pcall(region[method], region)
        if ok then return PublicText(value) end
    end
    return "-"
end

local function Record(event, value)
    if not capture then return end
    local region = capture.region
    local last, external, source, reason = transparency.GetBarOpacityTraceState(region)
    local line = string.format("+%.3fs %s  live=%s last=%s native=%s external=%s source=%s value=%s reason=%s",
        GetTime() - capture.started, event, ReadOpacity(region, "GetAlpha"), PublicText(last),
        ReadOpacity(region, "GetConfigAlpha"), PublicText(external), PublicText(source), PublicText(value), PublicText(reason))
    local entries = capture.entries
    if event == capture.lastEvent then
        entries[#entries] = line
    else
        if #entries == maxEntries then table.remove(entries, 1) end
        entries[#entries + 1] = line
        capture.lastEvent = event
    end
    capture.external, capture.reason = external, reason
end

local function HiddenAlpha(region)
    local setting = KongKontinued_Frames and KongKontinued_Frames[region]
    return setting and setting.TriggerDefaults and setting.TriggerDefaults.alphaOut
end

local function HookCompanionClose()
    local frame = KongKontinuedConfig and KongKontinuedConfig.frame
    if frame and frame ~= companionFrame then
        pcall(frame.HookScript, frame, "OnHide", function() Record("Advanced Config closed") end)
        companionFrame = frame
    end
end

local function HookCompanion()
    if companionHooked then return true end
    if type(KongKontinuedConfig_Show) ~= "function" then return false end
    pcall(hooksecurefunc, "KongKontinuedConfig_Show", function()
        if capture then
            HookCompanionClose()
            Record("Advanced Config opened")
        end
    end)
    pcall(hooksecurefunc, "KongKontinuedConfig_UpdateComponents", function()
        if not capture then return end
        local alpha = HiddenAlpha(capture.region)
        if alpha ~= capture.hiddenAlpha then
            capture.hiddenAlpha = alpha
            Record("Advanced Config Hidden Alpha changed", alpha)
        end
    end)
    companionHooked = true
    return true
end

local function HookOpacity(region)
    if not coreHooked then
        pcall(hooksecurefunc, transparency, "GetUnavailableReason", function(bar)
            if not IsTarget(bar) then return end
            local _, external = transparency.GetBarOpacityTraceState(bar)
            if external and not capture.external then Record("Conflict recorded during eligibility check") end
        end)
        pcall(hooksecurefunc, transparency, "Refresh", function()
            if not capture then return end
            local _, _, _, reason = transparency.GetBarOpacityTraceState(capture.region)
            if reason ~= capture.reason then Record("Availability changed") end
        end)
        pcall(hooksecurefunc, transparency, "WriteAlpha", function(_, bar, alpha)
            if IsTarget(bar) then Record("Kong opacity write attempt", alpha) end
        end)
        pcall(hooksecurefunc, transparency, "OnNativeActionBarAlphaSet", function(bar, alpha)
            if IsTarget(bar) then Record("Provider opacity notification", alpha) end
        end)
        coreHooked = true
    end
    if not hookedBars[region] then
        hookedBars[region] = pcall(hooksecurefunc, region, "SetAlpha", function(bar, alpha)
            if not IsTarget(bar) then return end
            local _, _, _, _, writing = transparency.GetBarOpacityTraceState(bar)
            if not writing then Record("SetAlpha outside Kong write", alpha) end
        end)
    end
    if HookCompanion() then return end
    if not companionLoadWatcher then
        companionLoadWatcher = CreateFrame("Frame")
        companionLoadWatcher:SetScript("OnEvent", function(self, _, addon)
            if addon == "KongKontinuedConfig" and HookCompanion() then self:UnregisterEvent("ADDON_LOADED") end
        end)
    end
    companionLoadWatcher:RegisterEvent("ADDON_LOADED")
end

local function ShowReport(text)
    local aceGUI = LibStub and LibStub("AceGUI-3.0", true)
    if not aceGUI then return false end
    if not report then
        report = aceGUI:Create("Frame")
        report:SetTitle("Kong bar opacity trace (Ctrl+C to copy)")
        report:SetWidth(760)
        report:SetHeight(390)
        report:SetLayout("Fill")
        reportText = aceGUI:Create("MultiLineEditBox")
        reportText:DisableButton(true)
        report:AddChild(reportText)
    end
    report:Show()
    reportText:SetText(text)
    reportText:SetFocus()
    reportText:HighlightText()
    return true
end

SLASH_KONGCONTINUEDALPHATRACE1 = "/kongalphatrace"
SlashCmdList.KONGCONTINUEDALPHATRACE = function(input)
    local command, barName = input:match("^%s*(%S+)%s*(%S*)%s*$")
    if command == "start" then
        if type(hooksecurefunc) ~= "function" or not transparency
            or type(transparency.IsManagedActionBar) ~= "function"
            or type(transparency.GetBarOpacityTraceState) ~= "function" then
            print("Kong opacity trace is unavailable in this client")
            return
        end
        barName = barName ~= "" and barName or "BT4Bar7" -- Class Bar 1 in Bartender4's Mainline layout.
        local region = barName:match("^BT4Bar%d+$") and _G[barName]
        if not region or not transparency.IsManagedActionBar(region) then
            print("Kong opacity trace: no accessible Bartender4 bar named " .. barName)
            return
        end
        HookOpacity(region)
        capture = {region = region, name = barName, entries = {}, started = GetTime(), hiddenAlpha = HiddenAlpha(region)}
        HookCompanionClose()
        Record("Trace started")
        print("Kong opacity trace started for " .. barName .. ". Use /kongalphatrace stop to copy the report")
    elseif command == "stop" and capture then
        Record("Trace stopped")
        local text = "Kong bar opacity trace for " .. capture.name .. "\n" .. table.concat(capture.entries, "\n")
        capture = nil
        if companionLoadWatcher then companionLoadWatcher:UnregisterEvent("ADDON_LOADED") end
        local ok, shown = pcall(ShowReport, text)
        if not ok or not shown then
            if report then pcall(report.Hide, report) end
            report, reportText = nil, nil
            for line in text:gmatch("[^\n]+") do print(line) end
        end
    else
        print("Kong opacity trace: /kongalphatrace start [BT4Bar7] or /kongalphatrace stop")
    end
end
