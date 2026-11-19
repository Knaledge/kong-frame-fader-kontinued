local addonName, A = ...
local Attribution = {}
A.AddonAttribution = Attribution

local ownName = addonName:lower()
local configName = ownName .. "config"

local function IsExternalName(name)
    if (issecretvalue and issecretvalue(name)) or type(name) ~= "string"
        or name == "" or name:find("[/\\|%c]") then return false end
    local lowerName = name:lower()
    return lowerName ~= ownName and lowerName ~= configName and not lowerName:match("^blizzard_")
end

local function GetVerifiedName(candidate)
    if not IsExternalName(candidate) or not C_AddOns
        or not C_AddOns.GetAddOnInfo or not C_AddOns.IsAddOnLoaded then return end
    local found, name = pcall(C_AddOns.GetAddOnInfo, candidate)
    if not found or not IsExternalName(name) then return end
    -- The first result also includes addons executing their load-time code.
    local checked, loadedOrLoading = pcall(C_AddOns.IsAddOnLoaded, name)
    if checked and loadedOrLoading then return name end
end

function Attribution.FromStack()
    if not debugstack then return end
    local stack = debugstack(3, 10, 0):gsub("\\", "/")
    for folder in stack:gmatch("[Aa][Dd][Dd][Oo][Nn][Ss]/([^/\r\n]+)/") do
        if IsExternalName(folder) then
            -- A deeper caller is not evidence that it made the write.
            return GetVerifiedName(folder)
        end
    end
end

function Attribution.FromGlobal(name)
    if not issecurevariable then return end
    local secure, source = issecurevariable(name)
    if not secure then return GetVerifiedName(source) end
end
