-- tests/respawn_timer_test.lua
--
-- Run:  lua tests/respawn_timer_test.lua
--
-- Guards the DisableRespawnTimerPacket fix: the respawn/shuttle countdown
-- must be masked only in the packet a LIVING player receives.
-- ServerEventWrite runs once per recipient client, so the Before/After
-- patch pair must read that recipient (ptable.Args[1]) and leave
-- spectators'/dead players' own packets untouched. Hook/ServerState/CS
-- are stand-ins since the Barotrauma API isn't available outside the
-- game.

local ROOT = "[HUD] Disable Components/Lua/"

SERVER, CLIENT = true, false

local patches = {}
Hook = {
    Patch = function(typeName, methodName, callback, hookType)
        local key = typeName .. "." .. methodName
        patches[key] = patches[key] or {}
        table.insert(patches[key], { hookType = hookType, callback = callback })
    end,
    Add = function() end,
    HookMethodType = { Before = "Before", After = "After" },
}

dofile(ROOT .. "Core/Safe.lua")

local timerBlockOn = false
HDC.ServerState = { Get = function(key)
    if key == "DisableRespawnTimerPacket" then return timerBlockOn end
    return nil
end }

dofile(ROOT .. "Server/Features/DisableRespawnTimerPacket.lua")

local KEY = "Barotrauma.Networking.RespawnManager.ServerEventWrite"
local list = patches[KEY]
assert(list ~= nil and #list == 2, "expected one Before and one After patch on ServerEventWrite")

local function fireBefore(instance, ptable)
    for _, p in ipairs(list) do
        if p.hookType == "Before" then p.callback(instance, ptable) end
    end
end

local function fireAfter(instance, ptable)
    for _, p in ipairs(list) do
        if p.hookType == "After" then p.callback(instance, ptable) end
    end
end

local function freshState()
    return { [1] = { RespawnCountdownStarted = true, ReturnCountdownStarted = true } }
end

local living     = { Character = { IsDead = false } }
local dead       = { Character = { IsDead = true } }
local spectating = { Character = nil }

-- Policy off: a living recipient's packet is never touched.
timerBlockOn = false
do
    local states  = freshState()
    local ptable  = { Args = { [1] = living } }
    fireBefore({ teamSpecificStates = states }, ptable)
    assert(states[1].RespawnCountdownStarted == true, "policy off must never mask the timer")
end

timerBlockOn = true

-- A living recipient's packet is masked during the write, then the real
-- state is restored immediately after — the server's own update loop,
-- and every other recipient's write, must keep seeing the truth.
do
    local states   = freshState()
    local instance = { teamSpecificStates = states }
    local ptable   = { Args = { [1] = living } }

    fireBefore(instance, ptable)
    assert(states[1].RespawnCountdownStarted == false and states[1].ReturnCountdownStarted == false,
        "a living recipient's packet must have the countdown masked")

    fireAfter(instance, ptable)
    assert(states[1].RespawnCountdownStarted == true and states[1].ReturnCountdownStarted == true,
        "the real state must be restored immediately after the write")
end

-- Spectators and dead players always get the real countdown.
for _, recipient in ipairs({ dead, spectating }) do
    local states   = freshState()
    local instance = { teamSpecificStates = states }
    local ptable   = { Args = { [1] = recipient } }

    fireBefore(instance, ptable)
    assert(states[1].RespawnCountdownStarted == true,
        "a spectator/dead recipient must never have the countdown masked")
    assert(ptable.Data == nil,
        "a spectator/dead recipient must not even trigger the mask/restore pair")
end

print("respawn_timer_test: ok")
