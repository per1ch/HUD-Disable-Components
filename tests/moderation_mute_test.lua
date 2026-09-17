-- tests/moderation_mute_test.lua
--
-- Run:  lua tests/moderation_mute_test.lua
--
-- Guards the ChatMuteGlobal rework: the global toggle must silence living
-- players' broadcast chat but leave spectators, dead players, and
-- command-shaped text (e.g. "!alive") untouched, while a targeted
-- hdc_mute still blocks everything from its target. Loads the real
-- Core/Safe.lua and Server/Moderation.lua; Hook/Game/ServerState are
-- stand-ins since neither the Barotrauma API nor persistence is available
-- outside the game.

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

local Moderation  = HDC.Moderation
local filterChat  = hooks.chatMessage["HDC.Moderation.FilterChat"]
assert(filterChat ~= nil, "FilterChat hook did not register")

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

local function blocked(text, who)
    return filterChat({ Text = text }, who) == true
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

-- A per-player hdc_mute is unconditional: it overrides every exemption.
globalMuteOn = false
local troll = client({ steamId = 111 })
Moderation.SetMuted(troll, true)
assert(blocked("hello", troll), "an individually muted player must stay muted")
assert(blocked("!alive", troll), "an individual mute blocks commands too")
Moderation.SetMuted(troll, false)
assert(not blocked("hello", troll), "un-muting must restore normal chat")

print("moderation_mute_test: ok")
