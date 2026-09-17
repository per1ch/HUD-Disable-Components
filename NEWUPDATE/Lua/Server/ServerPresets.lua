-- Lua/Server/ServerPresets.lua — SERVER
--
-- Named snapshots of the HUD policy. A preset is a JSON file on disk
-- holding a complete policy table — every key in HDC.FeatureRegistry, not
-- a partial override — so loading a preset always produces the same
-- policy regardless of what state the server was in beforehand.
--
-- Presets are admin tools, not policy values. They are not in the
-- registry, are not synced to clients, and are not visible in the client
-- menu. Loading a preset goes through ServerState.ApplyTable and
-- Sync.Publish, so clients adopt the new policy the same way they adopt
-- any other edit; they never need to know a preset was involved.
--
-- Authorisation: every command here checks Permissions.CanEditPolicy,
-- same as the settings menu and hdc_serverstate. The server console is
-- always allowed; a connected client needs the hudDisableComponents
-- permission or owner status.

HDC = HDC or {}

local Safe        = HDC.Safe
local ServerState = HDC.ServerState
local Sync        = HDC.Sync
local Permissions = HDC.Permissions

local Presets = {}
HDC.Presets = Presets

local CONFIG_DIR    = Game.SaveFolder .. "/ModConfigs/HUDDisableComponents"
local PRESET_DIR    = CONFIG_DIR .. "/presets"
local INDEX_PATH    = CONFIG_DIR .. "/presets.json"
local AUTOLOAD_PATH = CONFIG_DIR .. "/autoload.json"

-- index: [name] = true — set of known preset names. Kept in a separate
-- JSON file rather than rescanning the directory, so the module does not
-- depend on a File listing API that may not exist across LuaCs versions.
local index    = {}
local autoload = nil

-- --- helpers ---------------------------------------------------------

-- Preset names double as filenames. Reject anything with path separators
-- or characters that are hostile on common filesystems, and refuse the
-- two directory-walk names outright. Trims surrounding whitespace.
local function sanitizeName(name)
    if type(name) ~= "string" then return nil end
    name = name:match("^%s*(.-)%s*$")
    if name == "" or #name > 64 then return nil end
    if name == "." or name == ".." then return nil end
    if name:match("[%c/\\:*?\"<>|]") then return nil end
    return name
end

local function presetPath(name)
    return PRESET_DIR .. "/" .. name .. ".json"
end

local function writeJson(path, tbl)
    return Safe.Set(function()
        File.CreateDirectory(CONFIG_DIR)
        File.CreateDirectory(PRESET_DIR)
        File.Write(path, json.serialize(tbl))
    end)
end

local function readJson(path)
    if Safe.Get(function() return File.Exists(path) end) ~= true then return nil end
    local raw = Safe.Get(function() return File.Read(path) end)
    if raw == nil then return nil end
    return Safe.Get(function() return json.parse(raw) end)
end

local function deleteFile(path)
    return Safe.Set(function() File.Delete(path) end)
end

-- Joins console-command arguments back into a single string so preset
-- names can contain spaces: "hdc_preset_save My Cozy Round" saves under
-- "My Cozy Round". Accepts either a table or a bare string, since the
-- AddCommand callback shape varies between LuaCs versions.
local function nameFromArgs(args)
    if args == nil then return nil end
    if type(args) == "string" then
        local trimmed = args:match("^%s*(.-)%s*$")
        return trimmed ~= "" and trimmed or nil
    end
    local parts = {}
    for _, part in ipairs(args) do table.insert(parts, tostring(part)) end
    if #parts == 0 then return nil end
    return table.concat(parts, " ")
end

-- --- index / autoload persistence ------------------------------------

local function loadIndex()
    index = {}
    local data = readJson(INDEX_PATH)
    if type(data) ~= "table" then return end
    for _, name in ipairs(data) do
        if type(name) == "string" and sanitizeName(name) ~= nil then
            index[name] = true
        end
    end
end

local function saveIndex()
    local list = {}
    for name in pairs(index) do table.insert(list, name) end
    table.sort(list)
    writeJson(INDEX_PATH, list)
end

local function loadAutoload()
    autoload = nil
    local data = readJson(AUTOLOAD_PATH)
    if type(data) ~= "table" then return end
    autoload = sanitizeName(data.autoload)
    -- Autoload pointing at a preset that no longer exists is not an error
    -- worth clearing: the file may live on another machine, or the index
    -- may be rebuilt later. Keep the value; Load will report it.
end

local function saveAutoload()
    if autoload == nil then
        deleteFile(AUTOLOAD_PATH)
        return
    end
    writeJson(AUTOLOAD_PATH, { autoload = autoload })
end

-- --- public API ------------------------------------------------------

-- Captures the current policy under a name and writes it to disk.
function Presets.Save(name)
    name = sanitizeName(name)
    if name == nil then return nil, "invalid preset name" end

    local snapshot = {}
    for _, entry in ipairs(HDC.FeatureRegistry) do
        snapshot[entry.key] = ServerState.Get(entry.key)
    end

    local payload = {
        name    = name,
        version = HDC.Version,
        values  = snapshot,
    }

    if not writeJson(presetPath(name), payload) then
        return nil, "could not write preset file"
    end

    index[name] = true
    saveIndex()
    return name
end

-- Applies a stored preset as the new policy. Fills in registry defaults
-- for any key the preset file omits, so the resulting policy is always
-- complete and deterministic — a preset is a full statement of intent,
-- not a patch on top of whatever happened to be configured at the time.
function Presets.Load(name)
    name = sanitizeName(name)
    if name == nil then return nil, "invalid preset name" end
    if index[name] ~= true then return nil, "no such preset" end

    local payload = readJson(presetPath(name))
    if type(payload) ~= "table" or type(payload.values) ~= "table" then
        return nil, "preset file is missing or unreadable"
    end

    local resolved = {}
    for _, entry in ipairs(HDC.FeatureRegistry) do
        resolved[entry.key] = HDC.FeatureDefaults[entry.key]
    end
    for key, value in pairs(payload.values) do
        resolved[key] = value
    end

    -- ApplyTable runs each value through CoerceValue, so a preset file
    -- edited by hand cannot inject unknown keys or out-of-range floats.
    ServerState.ApplyTable(resolved)
    ServerState.Save()
    Sync.Publish()

    return name
end

function Presets.Delete(name)
    name = sanitizeName(name)
    if name == nil then return nil, "invalid preset name" end
    if index[name] ~= true then return nil, "no such preset" end

    deleteFile(presetPath(name))
    index[name] = nil
    saveIndex()

    if autoload == name then
        autoload = nil
        saveAutoload()
    end
    return name
end

function Presets.List()
    local names = {}
    for name in pairs(index) do table.insert(names, name) end
    table.sort(names)
    return names
end

-- Returns a printable description of a preset, or nil + reason.
function Presets.Describe(name)
    name = sanitizeName(name)
    if name == nil then return nil, "invalid preset name" end
    if index[name] ~= true then return nil, "no such preset" end

    local payload = readJson(presetPath(name))
    if type(payload) ~= "table" or type(payload.values) ~= "table" then
        return nil, "preset file is unreadable"
    end

    local lines = { "[HDC] Preset '" .. name .. "':" }
    for _, entry in ipairs(HDC.FeatureRegistry) do
        local value = payload.values[entry.key]
        if value == nil then
            value = HDC.FeatureDefaults[entry.key]
        end
        local shown
        if entry.type == "float" then
            shown = string.format("%.2f", tonumber(value) or 0)
        else
            shown = value == true and "ON" or "off"
        end
        table.insert(lines, string.format("  %-22s %s", entry.key, shown))
    end
    return table.concat(lines, "\n")
end

function Presets.GetAutoload()
    return autoload
end

-- name == nil / "off" / "none" clears the autoload setting.
function Presets.SetAutoload(name)
    if name == nil or name == "off" or name == "none" then
        autoload = nil
        saveAutoload()
        return nil
    end
    name = sanitizeName(name)
    if name == nil then return nil, "invalid preset name" end
    if index[name] ~= true then return nil, "no such preset" end
    autoload = name
    saveAutoload()
    return name
end

-- --- console commands -----------------------------------------------

Safe.AddCommand("hdc_preset_save",
    "Save the current policy as a named preset. Usage: hdc_preset_save <name>",
    function(args, client)
        if not Permissions.CanEditPolicy(client) then
            print("[HDC] You do not have permission to change the policy.")
            return
        end
        local name = nameFromArgs(args)
        if name == nil then
            print("[HDC] Usage: hdc_preset_save <name>")
            return
        end
        local ok, err = Presets.Save(name)
        if ok == nil then
            print("[HDC] Could not save preset: " .. tostring(err))
            return
        end
        print("[HDC] Saved preset '" .. ok .. "'.")
    end, nil, false)

Safe.AddCommand("hdc_preset_load",
    "Apply a stored preset as the current policy. Usage: hdc_preset_load <name>",
    function(args, client)
        if not Permissions.CanEditPolicy(client) then
            print("[HDC] You do not have permission to change the policy.")
            return
        end
        local name = nameFromArgs(args)
        if name == nil then
            print("[HDC] Usage: hdc_preset_load <name>")
            return
        end
        local ok, err = Presets.Load(name)
        if ok == nil then
            print("[HDC] Could not load preset: " .. tostring(err))
            return
        end
        print("[HDC] Loaded preset '" .. ok .. "'. Clients will adopt it immediately.")
    end, nil, false)

Safe.AddCommand("hdc_preset_delete",
    "Delete a stored preset. Usage: hdc_preset_delete <name>",
    function(args, client)
        if not Permissions.CanEditPolicy(client) then
            print("[HDC] You do not have permission to change the policy.")
            return
        end
        local name = nameFromArgs(args)
        if name == nil then
            print("[HDC] Usage: hdc_preset_delete <name>")
            return
        end
        local ok, err = Presets.Delete(name)
        if ok == nil then
            print("[HDC] Could not delete preset: " .. tostring(err))
            return
        end
        print("[HDC] Deleted preset '" .. ok .. "'.")
    end, nil, false)

Safe.AddCommand("hdc_preset_list", "List stored presets.",
    function()
        local names = Presets.List()
        if #names == 0 then
            print("[HDC] No presets stored yet.")
            return
        end
        print("[HDC] Stored presets:")
        local current = Presets.GetAutoload()
        for _, name in ipairs(names) do
            local marker = (name == current) and "  [autoload]" or ""
            print("  " .. name .. marker)
        end
    end, nil, false)

Safe.AddCommand("hdc_preset_show",
    "Print the values stored in a preset. Usage: hdc_preset_show <name>",
    function(args)
        local name = nameFromArgs(args)
        if name == nil then
            print("[HDC] Usage: hdc_preset_show <name>")
            return
        end
        local body, err = Presets.Describe(name)
        if body == nil then
            print("[HDC] " .. tostring(err))
            return
        end
        print(body)
    end, nil, false)

Safe.AddCommand("hdc_preset_autoload",
    "Set which preset to load on server start. Usage: hdc_preset_autoload <name|off>",
    function(args, client)
        if not Permissions.CanEditPolicy(client) then
            print("[HDC] You do not have permission to change the policy.")
            return
        end
        local name = nameFromArgs(args)
        if name == nil then
            local current = Presets.GetAutoload()
            if current == nil then
                print("[HDC] Autoload is off.")
            else
                print("[HDC] Autoload is set to '" .. current .. "'.")
            end
            print("[HDC] Usage: hdc_preset_autoload <name|off>")
            return
        end
        local ok, err = Presets.SetAutoload(name)
        if ok == nil then
            if err ~= nil then
                print("[HDC] " .. tostring(err))
            else
                print("[HDC] Autoload disabled.")
            end
            return
        end
        print("[HDC] Autoload set to '" .. ok .. "'. It will be applied on the next server start.")
    end, nil, false)

-- --- startup ---------------------------------------------------------

-- Load the index and, if an autoload preset is configured, apply it. Runs
-- once at module load, after ServerState has already read its own config
-- from disk, so the autoload preset overrides the persisted values as
-- intended. No clients are connected yet, so Sync.Publish during startup
-- is a no-op on the wire.
Safe.Set(function() File.CreateDirectory(PRESET_DIR) end)
loadIndex()
loadAutoload()

if autoload ~= nil then
    local ok, err = Presets.Load(autoload)
    if ok == nil then
        Safe.Log("autoload preset '" .. tostring(autoload) .. "' could not be applied: " .. tostring(err))
    else
        Safe.Log("autoloaded preset '" .. ok .. "'")
    end
end

return Presets
