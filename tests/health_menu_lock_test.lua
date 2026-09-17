-- tests/health_menu_lock_test.lua
--
-- Run:  lua tests/health_menu_lock_test.lua
--
-- Guards the LockHealthMenu hard block: Server/Features/HealthMenuLock.lua
-- must cancel a treatment only when the user is treating themselves and
-- the policy is on, must leave treating someone else alone, and must
-- notify the blocked player directly. Hook/ServerState/Client/chat are
-- stand-ins since the Barotrauma API isn't available outside the game.

local ROOT = "[HUD] Disable Components/Lua/"

SERVER, CLIENT = true, false

local hooks = {}
Hook = {
    Add = function(event, id, callback)
        hooks[event] = hooks[event] or {}
        hooks[event][id] = callback
    end,
}

dofile(ROOT .. "Core/Safe.lua")

local lockOn = false
HDC.ServerState = { Get = function(key)
    if key == "LockHealthMenu" then return lockOn end
    return nil
end }

-- Chat stand-ins: record every direct message sent.
local sentMessages = {}
ChatMessageType = { Server = "Server" }
ChatMessage = { Create = function(sender, text, msgType) return { Text = text } end }
Game = { SendDirectChatMessage = function(message, client)
    table.insert(sentMessages, { client = client, text = message.Text })
end }

-- One connected client, whose Character is the "self" in every case below.
local selfClient  = { Character = { Name = "Alice" } }
local otherClient = { Character = { Name = "Bob" } }
Client = { ClientList = { selfClient, otherClient } }

dofile(ROOT .. "Server/Features/HealthMenuLock.lua")

local treat = hooks.itemApplyTreatment["HDC.HealthMenuLock.BlockSelfTreat"]
assert(treat ~= nil, "itemApplyTreatment hook did not register")

local item, limb = {}, {}

-- Policy off: self-treatment goes through untouched.
lockOn = false
sentMessages = {}
assert(treat(item, selfClient.Character, selfClient.Character, limb) ~= true,
    "self-treatment must pass when the lock is off")
assert(#sentMessages == 0, "no message should be sent when the lock is off")

-- Policy on: treating someone else is untouched.
lockOn = true
sentMessages = {}
assert(treat(item, selfClient.Character, otherClient.Character, limb) ~= true,
    "treating another player must never be blocked")
assert(#sentMessages == 0, "no message should be sent for treating someone else")

-- Policy on: self-treatment is cancelled and the treater is notified.
sentMessages = {}
assert(treat(item, selfClient.Character, selfClient.Character, limb) == true,
    "self-treatment must be cancelled when the lock is on")
assert(#sentMessages == 1, "the blocked player must get exactly one direct message")
assert(sentMessages[1].client == selfClient, "the message must go to the player who was blocked")

print("health_menu_lock_test: ok")
