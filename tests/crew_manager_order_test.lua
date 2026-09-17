-- tests/crew_manager_order_test.lua
--
-- Run:  lua tests/crew_manager_order_test.lua
--
-- Guards the CrewManager hard block: Server/Features/CrewManager.lua must
-- cancel Character.SetOrder only when a connected human actually gave the
-- order, must leave every internal/engine call (no OrderGiver, or an
-- OrderGiver with no connected Client — bot AI, the automatic Dismissal
-- order on a team change, etc.) alone, and must notify the player who was
-- blocked. Hook/ServerState/Client/chat/CS are stand-ins since the
-- Barotrauma API isn't available outside the game.

local ROOT = "[HUD] Disable Components/Lua/"

SERVER, CLIENT = true, false

local patches = {}
Hook = {
    Patch = function(typeName, methodName, callback, hookType)
        patches[typeName .. "." .. methodName] = callback
    end,
    HookMethodType = { Before = "Before", After = "After" },
}

dofile(ROOT .. "Core/Safe.lua")

local crewManagerOn = false
HDC.ServerState = { Get = function(key)
    if key == "CrewManager" then return crewManagerOn end
    return nil
end }

local sentMessages = {}
ChatMessageType = { Server = "Server" }
ChatMessage = { Create = function(sender, text, msgType) return { Text = text } end }
Game = { SendDirectChatMessage = function(message, client)
    table.insert(sentMessages, { client = client, text = message.Text })
end }

local playerClient = { Character = { Name = "Alice" } }
Client = { ClientList = { playerClient } }

dofile(ROOT .. "Server/Features/CrewManager.lua")

local setOrder = patches["Barotrauma.Character.SetOrder"]
assert(setOrder ~= nil, "Character.SetOrder patch did not register")

local function fire(order)
    local ptable = { Args = { [0] = order }, PreventExecution = false }
    setOrder({}, ptable)
    return ptable.PreventExecution
end

-- Policy off: a player-issued order goes through untouched.
crewManagerOn = false
sentMessages = {}
assert(not fire({ OrderGiver = playerClient.Character }),
    "an order must pass when CrewManager is off")
assert(#sentMessages == 0, "no message should be sent when the toggle is off")

crewManagerOn = true

-- Internal engine calls (no OrderGiver, e.g. bot AI logic) are untouched.
sentMessages = {}
assert(not fire({ OrderGiver = nil }), "an order with no OrderGiver must never be blocked")
assert(#sentMessages == 0, "no message for an orderless internal call")

-- An OrderGiver that isn't a connected player (a bot dismissing itself on
-- a team change, say) is also untouched.
sentMessages = {}
assert(not fire({ OrderGiver = { Name = "SomeBot" } }),
    "an OrderGiver with no connected Client must never be blocked")
assert(#sentMessages == 0, "no message when the giver isn't a connected player")

-- A real, connected human giving an order is blocked and notified.
sentMessages = {}
assert(fire({ OrderGiver = playerClient.Character }),
    "a player-issued order must be cancelled when CrewManager is on")
assert(#sentMessages == 1, "the blocked player must get exactly one direct message")
assert(sentMessages[1].client == playerClient, "the message must go to the order giver")

print("crew_manager_order_test: ok")
