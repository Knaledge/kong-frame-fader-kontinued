local _, A = ...
local Import = {MAX_BYTES = 4 * 1024 * 1024}
A.LegacyImport = Import

-- Read SavedVariables as data. Never compile or execute pasted Lua.
local Reader = {}
Reader.__index = Reader
local escapes = {a = "\a", b = "\b", f = "\f", n = "\n", r = "\r", t = "\t", v = "\v"}

function Reader:Fail(message)
    error(message .. " at byte " .. self.pos, 0)
end

function Reader:LongString()
    local equals = self.text:match("^%[(=*)%[", self.pos)
    if equals == nil then return nil end
    local start = self.pos + #equals + 2
    local ending, last = self.text:find("]" .. equals .. "]", start, true)
    if not ending then self:Fail("Unterminated long string or comment") end
    local value = self.text:sub(start, ending - 1)
    self.pos = last + 1
    if value:sub(1, 2) == "\r\n" then return value:sub(3) end
    if value:sub(1, 1) == "\n" or value:sub(1, 1) == "\r" then return value:sub(2) end
    return value
end

function Reader:Skip()
    while true do
        local _, last = self.text:find("^%s*", self.pos)
        self.pos = (last or self.pos - 1) + 1
        if self.text:sub(self.pos, self.pos + 1) ~= "--" then return end
        self.pos = self.pos + 2
        if self:LongString() == nil then
            self.pos = self.text:find("[\r\n]", self.pos) or (#self.text + 1)
        end
    end
end

function Reader:Take(token)
    self:Skip()
    if self.text:sub(self.pos, self.pos + #token - 1) == token then
        self.pos = self.pos + #token
        return true
    end
    return false
end

function Reader:Expect(token)
    if not self:Take(token) then self:Fail("Expected '" .. token .. "'") end
end

function Reader:Word()
    self:Skip()
    local word = self.text:match("^[%a_][%w_]*", self.pos)
    if word then self.pos = self.pos + #word end
    return word
end

function Reader:String()
    self:Skip()
    local quote = self.text:sub(self.pos, self.pos)
    if quote ~= '"' and quote ~= "'" then return self:LongString() end
    self.pos = self.pos + 1
    local parts = {}
    while self.pos <= #self.text do
        local char = self.text:sub(self.pos, self.pos)
        self.pos = self.pos + 1
        if char == quote then return table.concat(parts) end
        if char == "\n" or char == "\r" then self:Fail("Unescaped newline in string") end
        if char == "\\" then
            char = self.text:sub(self.pos, self.pos)
            self.pos = self.pos + 1
            if char:match("%d") then
                local digits = char .. (self.text:match("^%d?%d?", self.pos) or "")
                self.pos = self.pos + #digits - 1
                local number = tonumber(digits)
                if number > 255 then self:Fail("Invalid decimal string escape") end
                char = string.char(number)
            elseif escapes[char] then
                char = escapes[char]
            elseif char == "\r" then
                if self.text:sub(self.pos, self.pos) == "\n" then self.pos = self.pos + 1 end
                char = "\n"
            elseif char ~= "\\" and char ~= '"' and char ~= "'" and char ~= "\n" then
                self:Fail("Unsupported string escape")
            end
        end
        parts[#parts + 1] = char
    end
    self:Fail("Unterminated string")
end

local function finite(value)
    return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

function Reader:Number()
    self:Skip()
    local token = self.text:match("^[+-]?0[xX][%da-fA-F]+", self.pos)
        or self.text:match("^[+-]?%d+%.?%d*[eE][+-]?%d+", self.pos)
        or self.text:match("^[+-]?%.%d+[eE][+-]?%d+", self.pos)
        or self.text:match("^[+-]?%d+%.?%d*", self.pos)
        or self.text:match("^[+-]?%.%d+", self.pos)
    if not token then return nil end
    self.pos = self.pos + #token
    local value = tonumber(token)
    if not finite(value) then self:Fail("Numbers must be finite") end
    return value
end

function Reader:Value(depth)
    self:Skip()
    if depth > 64 then self:Fail("Data is nested too deeply") end
    local char = self.text:sub(self.pos, self.pos)
    if char == "{" then
        self.pos = self.pos + 1
        local value, seen, index = {}, {}, 1
        while not self:Take("}") do
            self.entries = self.entries + 1
            if self.entries > 100000 then self:Fail("Too many table entries") end
            local key, item
            self:Skip()
            if not self.text:match("^%[=*%[", self.pos) and self:Take("[") then
                key = self:Value(depth + 1)
                self:Expect("]"); self:Expect("=")
                item = self:Value(depth + 1)
            else
                local saved = self.pos
                local word = self:Word()
                if word and self:Take("=") then
                    key = word
                    item = self:Value(depth + 1)
                else
                    self.pos = saved
                    key = index; index = index + 1
                    item = self:Value(depth + 1)
                end
            end
            if type(key) ~= "string" and type(key) ~= "boolean" and type(key) ~= "number" then
                self:Fail("Table keys must be strings, numbers or booleans")
            end
            if seen[key] then self:Fail("Duplicate table key") end
            seen[key] = true; value[key] = item
            if not self:Take(",") and not self:Take(";") then self:Expect("}"); return value end
        end
        return value
    end
    if char == '"' or char == "'" or self.text:match("^%[=*%[", self.pos) then return self:String() end
    local number = self:Number()
    if number ~= nil then return number end
    local word = self:Word()
    if word == "true" then return true end
    if word == "false" then return false end
    if word == "nil" then return nil end
    self:Fail("Only literal SavedVariables data is accepted")
end

local function reader(text)
    return setmetatable({text = text:gsub("^\239\187\191", ""), pos = 1, entries = 0}, Reader)
end

local function parseSavedVariables(text)
    if type(text) ~= "string" or #text > Import.MAX_BYTES then error("Paste up to 4 MiB of legacy SavedVariables", 0) end
    local r, data, seen = reader(text), {}, {}
    r:Skip()
    while r.pos <= #r.text do
        local name = r:Word()
        if name ~= "Kong_Profiles" and name ~= "Kong_Settings" then
            r:Fail("Expected Kong_Profiles or Kong_Settings")
        end
        if seen[name] then r:Fail("Each legacy variable may be supplied only once") end
        seen[name] = true; r:Expect("=")
        data[name] = r:Value(0)
        r:Take(";"); r:Skip()
    end
    if not next(seen) then error("Paste the contents of legacy Kong.lua SavedVariables files", 0) end
    return data
end

local function framePath(text)
    if type(text) ~= "string" or #text > 4096 then error("Invalid frame path", 0) end
    local r, steps = reader(text), {}
    r:Skip()
    if r.text:sub(r.pos, r.pos) ~= "[" and r.text:sub(r.pos, r.pos) ~= "." then
        local root = r:Word()
        if not root then r:Fail("Expected a frame name") end
        if root ~= "_G" then steps[#steps + 1] = {key = root} end
    end
    while true do
        r:Skip()
        if r.pos > #r.text then break end
        if #steps >= 128 then r:Fail("Frame path is too long") end
        if r:Take("[") then
            local key = r:Value(0)
            if type(key) ~= "string" and type(key) ~= "number" and type(key) ~= "boolean" then r:Fail("Invalid frame-path key") end
            r:Expect("]"); steps[#steps + 1] = {key = key}
        elseif r:Take(".") then
            local key = r:Word()
            if not key then r:Fail("Expected a field name") end
            steps[#steps + 1] = {key = key}
        elseif r:Take(":") then
            if r:Word() ~= "GetParent" then r:Fail("Only GetParent() is allowed in a frame path") end
            r:Expect("("); r:Expect(")")
            steps[#steps + 1] = {parent = true}
        else
            r:Fail("Invalid frame-path syntax")
        end
    end
    if #steps == 0 or steps[1].parent then error("Frame path must start with a global name", 0) end
    return steps
end

function Import.CompileFramePath(text)
    local ok, steps = pcall(framePath, text)
    if not ok then return nil, steps end
    return function()
        local value = _G
        for _, step in ipairs(steps) do
            if (issecretvalue and issecretvalue(value)) or type(value) ~= "table" then return nil end
            if canaccesstable and not canaccesstable(value) then return nil end
            if step.parent then
                if not A.CLASSES.Fader.canAccess(nil, value) or type(value.GetParent) ~= "function" then return nil end
                value = value:GetParent()
            else
                value = value[step.key]
            end
        end
        if issecretvalue and issecretvalue(value) then return nil end
        return value
    end
end

local times = {secondsIn = true, secondsOut = true, secondsTillOut = true}
local alphas = {alphaIn = true, alphaOut = true}
local transient = {refs = true, lastFadeTime = true, Frame = true, loader = true, Mouseover = true,
    value = true, unavailable = true, ValueListeners = true, StructureListeners = true, _check = true}

local function expect(condition, message)
    if not condition then error(message, 0) end
end

local function arrayLength(value, label)
    expect(type(value) == "table", label .. " must be a table")
    local maximum, count = 0, 0
    for key in pairs(value) do
        expect(type(key) == "number" and key >= 1 and key % 1 == 0, label .. " must be an array")
        maximum = math.max(maximum, key); count = count + 1
    end
    expect(maximum == count and maximum <= 4096, label .. " must be a dense array of at most 4096 entries")
    return count
end

local function timing(key, value)
    if times[key] then expect(finite(value) and value >= 0, key .. " must be a nonnegative finite number")
    else expect(finite(value) and value >= 0 and value <= 1, key .. " must be between 0 and 1") end
    return value
end

local function matches(actual, wanted)
    if wanted == "Any" or actual == wanted then return true end
    if type(wanted) == "table" then for _, kind in ipairs(wanted) do if kind == actual then return true end end end
    return false
end

local function condition(source, definitions, expected, report, depth)
    expect(depth <= 48 and type(source) == "table", "Invalid or overly nested condition")
    local definition = definitions[source.name]
    expect(definition ~= nil, "Unsupported legacy condition: " .. tostring(source.name))
    expect(matches(definition.type, expected), "Condition type mismatch: " .. source.name)
    local out = {name = source.name, Parameters = {}}
    for key in pairs(source) do
        expect(key == "name" or key == "Parameters" or transient[key], "Unsupported condition field: " .. tostring(key))
    end
    expect(source.Parameters == nil or type(source.Parameters) == "table", "Condition parameters must be a table")
    local parameters = source.Parameters or {}
    local count = arrayLength(parameters, "Condition parameters")
    local types = definition.ParameterTypes or {}
    expect(count == #types, "Unexpected parameter count for " .. source.name)
    for index, kind in ipairs(types) do out.Parameters[index] = condition(parameters[index], definitions, kind, report, depth + 1) end
    if definition.isUserEntered and source.value ~= nil then
        expect((definition.type == "Number" and finite(source.value)) or (definition.type == "Text" and type(source.value) == "string"),
            "Invalid literal value for " .. source.name)
        out.value = source.value
    end
    report.conditions = report.conditions + 1
    return out
end

local function profile(source, definitions, report)
    expect(type(source) == "table", "Each legacy profile must be a table")
    for key in pairs(source) do expect(key == "Frames" or key == "Groups" or key == "version", "Unsupported profile field: " .. tostring(key)) end
    expect(source.Frames == nil or type(source.Frames) == "table", "Profile frames must be a table")
    expect(source.Groups == nil or type(source.Groups) == "table", "Profile groups must be a table")
    local out = {Frames = {}, Groups = {}}
    local count = arrayLength(source.Frames or {}, "Profile frames")
    local indexes = {}
    for index = 1, count do
        local old = source.Frames[index]
        expect(type(old) == "table", "Frame settings must be a table")
        local compiled, err = Import.CompileFramePath(old.index)
        expect(compiled ~= nil, "Invalid saved frame path: " .. tostring(err))
        expect(not indexes[old.index], "Duplicate frame path in a profile")
        indexes[old.index] = true
        local frame = {index = old.index, TriggerDefaults = {}}
        for key, value in pairs(old) do
            if type(key) == "number" then
                expect(key >= 1 and key % 1 == 0, "Invalid trigger index")
            elseif key == "overrideAlpha" or key == "hideAtZeroAlpha" then
                expect(type(value) == "boolean", key .. " must be a boolean"); frame[key] = value
            else
                expect(key == "index" or key == "version" or key == "TriggerDefaults" or transient[key], "Unsupported frame field: " .. tostring(key))
            end
        end
        expect(old.TriggerDefaults == nil or type(old.TriggerDefaults) == "table", "Invalid trigger defaults")
        for key, value in pairs(old.TriggerDefaults or {}) do
            expect(times[key] or alphas[key] or transient[key], "Unsupported trigger default: " .. tostring(key))
            if times[key] or alphas[key] then frame.TriggerDefaults[key] = timing(key, value) end
        end
        local triggers = {}
        for key, value in pairs(old) do if type(key) == "number" then triggers[key] = value end end
        local triggerCount = arrayLength(triggers, "Frame triggers")
        for triggerIndex = 1, triggerCount do
            local oldTrigger = triggers[triggerIndex]
            expect(type(oldTrigger) == "table", "Trigger must be a table")
            local trigger = {}
            for key, value in pairs(oldTrigger) do
                expect(key == "Condition" or times[key] or alphas[key] or transient[key], "Unsupported trigger field: " .. tostring(key))
                if times[key] or alphas[key] then trigger[key] = timing(key, value) end
            end
            expect(type(oldTrigger.Condition) == "table" and oldTrigger.Condition.name == "Condition", "Triggers must contain a Condition root")
            trigger.Condition = condition(oldTrigger.Condition, definitions, "Truth", report, 0)
            frame[triggerIndex] = trigger
        end
        out.Frames[index] = frame; report.frames = report.frames + 1
    end
    expect(type(source.Groups or {}) == "table", "Profile groups must be a table")
    for name, members in pairs(source.Groups or {}) do
        expect(type(name) == "string" and name ~= "" and type(members) == "table", "Invalid frame group")
        local group = {}
        for path, value in pairs(members) do
            expect(Import.CompileFramePath(path) ~= nil and finite(value) and value >= 0, "Invalid frame-group member")
            group[path] = 0 -- Hover references are runtime state, not configuration.
        end
        out.Groups[name] = group
    end
    return out
end

-- Reuse the data-only validation/copy path for native profile operations.
function Import.CopyProfile(source, definitions)
    local ok, result = pcall(profile, source, definitions, {frames = 0, conditions = 0})
    if ok then return result end
    return nil, tostring(result)
end

function Import.NormalizeProfileName(name)
    if type(name) ~= "string" or not name:find("%S") then return nil, "Profile name cannot be empty" end
    if name:find("%c") then return nil, "Profile name cannot contain control characters" end
    name = name:match("^%s*(.-)%s*$"):lower():gsub("%s+", "_")
    if #name > 128 then return nil, "Profile name must be at most 128 bytes" end
    return name
end

local function uniqueName(base, reserved)
    local name, suffix = base, 1
    while reserved[name] do
        local ending = "_imported" .. (suffix == 1 and "" or "_" .. suffix)
        name = base:sub(1, 128 - #ending) .. ending
        suffix = suffix + 1
    end
    return name
end

function Import.ResolveProfileName(name, existing, renames)
    if type(name) ~= "string" or name == "" then return nil, "Invalid profile name" end
    if type(renames) ~= "table" then return nil, "Profile rename records are invalid; no profile was loaded" end
    local visited = {}
    while existing[name] == nil and renames[name] ~= nil do
        if visited[name] then return nil, "Profile rename cycle detected; no profile was loaded" end
        visited[name] = true
        name = renames[name]
        if type(name) ~= "string" or name == "" then return nil, "Invalid profile rename destination" end
    end
    return name
end

function Import.Prepare(text, existing, definitions, options, renames, currentName)
    local ok, result = pcall(function()
        expect(type(existing) == "table" and type(definitions) == "table", "Profile database or condition definitions unavailable")
        options, renames = options or {}, renames or {}
        expect(type(options) == "table" and type(renames) == "table", "Invalid import options or profile rename records")
        local mode = options.mode or "bulk"
        expect(mode == "bulk" or mode == "current" or mode == "rename" or mode == "separate", "Unknown import action")
        local data = parseSavedVariables(text)
        local settings = data.Kong_Settings
        expect(settings == nil or type(settings) == "table", "Kong_Settings must be a table")
        expect(not settings or settings.profile == nil or type(settings.profile) == "string", "Legacy profile selection must be a string")
        local profiles = data.Kong_Profiles
        if profiles == nil and settings and settings.Frames then
            profiles = {[settings.profile or "legacy"] = {Frames = settings.Frames, Groups = settings.Groups or {}}}
        end
        expect(type(profiles) == "table" and next(profiles) ~= nil, "Paste account-wide Kong_Profiles data; character selection alone contains no profiles")
        local names, reserved, existingNames = {}, {}, {}
        for name in pairs(existing) do reserved[name] = true end
        for name in pairs(renames) do reserved[name] = true end
        for name in pairs(reserved) do existingNames[name] = true end
        for name in pairs(profiles) do
            expect(type(name) == "string" and name:find("%S") and #name <= 128 and not name:find("%c"), "Invalid legacy profile name")
            names[#names + 1] = name
        end
        expect(#names <= 256, "Import at most 256 profiles at a time")
        table.sort(names)
        local plan = {profiles = {}, sources = names, frames = 0, conditions = 0, enabled = true, mode = mode, target = currentName}
        for _, oldName in ipairs(names) do
            local base, err = Import.NormalizeProfileName(oldName)
            expect(base ~= nil, err)
            local name = uniqueName(base, reserved)
            reserved[name] = true
            local report = {frames = 0, conditions = 0}
            local copy = profile(profiles[oldName], definitions, report)
            plan.profiles[#plan.profiles + 1] = {source = oldName, name = name, data = copy, frames = report.frames, conditions = report.conditions}
            plan.frames, plan.conditions = plan.frames + report.frames, plan.conditions + report.conditions
            if settings and settings.profile == oldName then plan.selection, plan.sourceSelection = name, oldName end
        end
        if settings and settings.enabled ~= nil then expect(type(settings.enabled) == "boolean", "Legacy enabled setting must be a boolean"); plan.enabled = settings.enabled end
        if not plan.selection and #plan.profiles == 1 then plan.selection = plan.profiles[1].name end
        if mode ~= "bulk" then
            local sourceName = options.source or plan.sourceSelection or names[1]
            local selected
            for _, entry in ipairs(plan.profiles) do if entry.source == sourceName then selected = entry; break end end
            expect(selected ~= nil, "Select an incoming profile present in the pasted data")
            plan.source = sourceName
            if mode == "current" or mode == "rename" then
                expect(type(currentName) == "string" and type(existing[currentName]) == "table", "Current profile unavailable")
                if mode == "current" then
                    selected.name = currentName
                else
                    local name, err = Import.NormalizeProfileName(options.name)
                    expect(name ~= nil, err)
                    expect(name ~= currentName, "Choose a different name or import into the current profile")
                    expect(existing[name] == nil, "Destination profile name already exists")
                    if renames[name] ~= nil then
                        expect(Import.ResolveProfileName(name, existing, renames) == currentName,
                            "Destination name is reserved by another profile rename")
                    end
                    selected.name, plan.renameFrom = name, currentName
                end
                plan.replaces = true
            else
                selected.name = uniqueName(assert(Import.NormalizeProfileName(sourceName)), existingNames)
            end
            plan.profiles, plan.selection = {selected}, selected.name
            plan.frames, plan.conditions = selected.frames, selected.conditions
        end
        return plan
    end)
    if ok then return result end
    return nil, tostring(result)
end
