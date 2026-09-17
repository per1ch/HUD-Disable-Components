-- Lua/Server/ServerState.lua — SERVER
--
-- Authoritative policy state. The server owns the values; clients only
-- mirror what is pushed to them. Persists as JSON so a restart keeps the
-- admin's choices.
--
-- Every write goes through HDC.CoerceValue, which rejects unknown keys and
-- clamps floats to their declared range. That is the single choke point
-- protecting the state from a malformed or hostile payload — callers do
-- not get to write raw values.

HDC = HDC or {}

local Safe     = HDC.Safe
local Registry = HDC.FeatureRegistry

local ServerState = {}
HDC.ServerState = ServerState

local CONFIG_DIR  = Game.SaveFolder .. "/ModConfigs"
local CONFIG_PATH = CONFIG_DIR .. "/HUDDisableComponents.json"

ServerState.Values = {}
for key, default in pairs(HDC.FeatureDefaults) do
    ServerState.Values[key] = default
end

function ServerState.Get(key)
    local value = ServerState.Values[key]
    if value == nil then return HDC.FeatureDefaults[key] end
    return value
end

function ServerState.GetBool(key)
    return ServerState.Get(key) == true
end

function ServerState.GetNumber(key)
    return tonumber(ServerState.Get(key)) or 0
end

function ServerState.Set(key, value)
    local coerced = HDC.CoerceValue(key, value)
    if coerced == nil then return false end
    ServerState.Values[key] = coerced
    return true
end

-- Applies a whole incoming table, ignoring anything the registry does not
-- describe. Returns how many fields were accepted.
function ServerState.ApplyTable(values)
    if type(values) ~= "table" then return 0 end
    local accepted = 0
    for key, value in pairs(values) do
        if ServerState.Set(key, value) then accepted = accepted + 1 end
    end
    return accepted
end

function ServerState.Serialize()
    return Safe.Get(function() return json.serialize(ServerState.Values) end) or "{}"
end

function ServerState.Save()
    local ok = Safe.Set(function()
        File.CreateDirectory(CONFIG_DIR)
        File.Write(CONFIG_PATH, ServerState.Serialize())
    end)
    if not ok then Safe.Log("could not write config to " .. CONFIG_PATH) end
    return ok
end

function ServerState.Load()
    if Safe.Get(function() return File.Exists(CONFIG_PATH) end) ~= true then return end

    local stored = Safe.Get(function() return json.parse(File.Read(CONFIG_PATH)) end)
    if stored == nil then
        Safe.Log("config at " .. CONFIG_PATH .. " could not be parsed, using defaults")
        return
    end
    ServerState.ApplyTable(stored)
end

function ServerState.SetAllBools(value)
    for _, entry in ipairs(Registry) do
        if entry.type ~= "float" then
            ServerState.Values[entry.key] = (value == true)
        end
    end
end

function ServerState.Describe()
    local lines = {}
    for _, entry in ipairs(Registry) do
        local value = ServerState.Get(entry.key)
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

ServerState.Load()

return ServerState
