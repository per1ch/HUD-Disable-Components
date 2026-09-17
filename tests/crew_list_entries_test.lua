-- tests/crew_list_entries_test.lua
--
-- Run:  lua tests/crew_list_entries_test.lua
--
-- Guards the CrewListEntries feature: the TAB crew roster panel must be
-- hidden only for a living local player, with the policy off or the
-- viewer spectating/dead leaving it alone. Hook/ClientState/Character/CS
-- are stand-ins since the Barotrauma API isn't available outside the
-- game.

local ROOT = "[HUD] Disable Components/Lua/"

SERVER, CLIENT = false, true

local patches = {}
Hook = {
    Patch = function(typeName, methodName, callback, hookType)
        patches[typeName .. "." .. methodName] = callback
    end,
    HookMethodType = { Before = "Before", After = "After" },
}

dofile(ROOT .. "Core/Safe.lua")

local policyOn = false
HDC.ClientState = { Get = function(key)
    if key == "CrewListEntries" then return policyOn end
    return nil
end }

CS = { System = { Reflection = { BindingFlags = { NonPublic = 1, Instance = 2 } } } }

local crewArea
local function makeInstance()
    crewArea = { Visible = true }
    local typeObj = { GetField = function(self, name, flags)
        return { GetValue = function(self2, inst) return crewArea end }
    end }
    return { GetType = function(self) return typeObj end }
end

dofile(ROOT .. "Client/Features/CrewListEntries.lua")

local update = patches["Barotrauma.CrewManager.UpdateProjectSpecific"]
assert(update ~= nil, "UpdateProjectSpecific patch did not register")

-- Policy off: the roster stays visible regardless of the viewer's state.
policyOn = false
Character = { Controlled = { IsDead = false } }
update(makeInstance(), {})
assert(crewArea.Visible == true, "the roster must stay visible when the policy is off")

policyOn = true

-- A living local player has the roster hidden.
Character = { Controlled = { IsDead = false } }
update(makeInstance(), {})
assert(crewArea.Visible == false, "a living player must have the crew roster hidden")

-- A dead local player keeps seeing it.
Character = { Controlled = { IsDead = true } }
update(makeInstance(), {})
assert(crewArea.Visible == true, "a dead player must still see the crew roster")

-- A spectator (no controlled character) keeps seeing it.
Character = { Controlled = nil }
update(makeInstance(), {})
assert(crewArea.Visible == true, "a spectator must still see the crew roster")

print("crew_list_entries_test: ok")
