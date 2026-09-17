-- tests/chat_mute_test.lua
--
-- Run:  lua tests/chat_mute_test.lua
--
-- Guards the split ChatMuteGlobal feature: Server/Features/ChatMuteGlobal.lua
-- owns the global toggle (living players muted, spectators/dead/commands
-- exempt) and Server/Moderation.lua owns the independent per-player mute.
-- Both hook the same "chatMessage" event, exactly as they do when the mod
-- loads for real, so this drives every registered hook the way the game
-- would. Hook/Game/ServerState are stand-ins since neither the Barotrauma
-- API nor persistence is available outside the game.

local ROOT = "[HUD] Disable Components/Lua/"

SERVER, CLIENT = true, false

-- Captures every hook so the test can drive them directly.
local hooks = {}
Hook = {
    Add = function(event, id, callback)
        hooks[event] = hooks[event] or {}
        hooks[event][id] = callback
    end,
}

dofile(ROOT .. "Core/Safe.lua")

local globalMuteOn = false
HDC.ServerState = { Get = function(key)
    if key == "ChatMuteGlobal" then return globalMuteOn end
    return nil
end }
HDC.Permissions = { CanEditPolicy = function() return false end }
Game = { AddCommand = function() end }

dofile(ROOT .. "Server/Moderation.lua")
dofile(ROOT .. "Server/Features/ChatMuteGlobal.lua")

local Moderation = HDC.Moderation

-- Fires every registered chatMessage hook, the way the real event does:
-- the message is dropped if any subscriber returns true.
local function blocked(text, who)
    for _, callback in pairs(hooks.chatMessage) do
        if callback({ Text = text }, who) == true then return true end
    end
    return false
end

local function client(opts)
    opts = opts or {}
    local character = nil
    if not opts.spectating then
        character = { IsDead = opts.dead == true }
    end
    return {
        SteamID   = opts.steamId or 0,
        AccountId = opts.accountId,
        Name      = opts.name or "Player",
        Character = character,
    }
end

-- Global mute off: nobody is filtered.
globalMuteOn = false
assert(not blocked("hello", client()), "chat must pass when the global mute is off")

-- Global mute on: living players are silenced...
globalMuteOn = true
assert(blocked("hello", client()), "global mute must block a living player's chat")

-- ...but spectators and dead players chat freely...
assert(not blocked("hello", client({ spectating = true })), "spectators must not be muted")
assert(not blocked("hello", client({ dead = true })), "dead players must not be muted")

-- ...and command-shaped text (leading punctuation) is never eaten by the
-- global toggle, living sender or not.
assert(not blocked("!alive", client()), "commands must pass through the global mute")
assert(not blocked("  /alive", client()), "commands must pass even with leading whitespace")

-- A per-player hdc_mute (Moderation.lua) is unconditional and independent
-- of the global toggle: it overrides every exemption above.
globalMuteOn = false
local troll = client({ steamId = 111 })
Moderation.SetMuted(troll, true)
assert(blocked("hello", troll), "an individually muted player must stay muted")
assert(blocked("!alive", troll), "an individual mute blocks commands too")
Moderation.SetMuted(troll, false)
assert(not blocked("hello", troll), "un-muting must restore normal chat")

print("chat_mute_test: ok")
