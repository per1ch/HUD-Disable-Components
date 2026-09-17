-- Lua/Server/Features/DisableRespawnTimerPacket.lua — SERVER
-- Suppress the respawn / shuttle countdown and the round-end countdown
-- for living players only — spectators and dead players still see them,
-- since they're the ones actually waiting to respawn.
--
-- The RespawnManager half of this file masks two flags only in the
-- packet written to a living recipient, restoring them immediately
-- afterwards so the server's own update loop, and every spectator/dead
-- client, keep seeing the real state. ServerEventWrite runs once per
-- connected client with that client passed in, which is what makes the
-- per-recipient scoping possible (confirmed against the game's own
-- source: `ServerEventWrite(IWriteMessage msg, Client c, ...)`).
--
-- The round-end half filters by content: any message routed through
-- GUI.AddMessage, or any visible GUITextBlock, whose text matches the
-- pattern list is suppressed. That GUI only exists on whichever machine
-- is running this code (a listen/host server), so the same "living
-- players only" rule is applied to that machine's own controlled
-- character instead of a network recipient.

print("[HDC] RespawnTimers.lua loaded")

HDC = HDC or {}
local Safe        = HDC.Safe
local ServerState = HDC.ServerState

local KEY = "DisableRespawnTimerPacket"

-- Server-side policy read. ClientState is client-only and is nil here;
-- the authoritative store on the server is ServerState (see Sync.lua).
local function enabled() return ServerState.Get(KEY) == true end

local function isSpectatorOrDead(client)
    local character = Safe.Get(function() return client.Character end)
    if character == nil then return true end -- spectating / not spawned
    return Safe.Get(function() return character.IsDead end) == true
end

local function localCharacterIsSpectatorOrDead()
    return Safe.Get(function()
        local c = Character.Controlled
        return c == nil or c.IsDead == true
    end) == true
end

-- Patterns are matched case-insensitively and as plain substrings.
-- Extend the list if your build phrases the countdown differently.
local PATTERNS = {
    "ending the round",
    "round ending",
    "round is ending",
    "roundend",
    "end in ",
}

local function matches(s)
    if s == nil then return false end
    s = tostring(s):lower()
    for _, p in ipairs(PATTERNS) do
        if s:find(p, 1, true) then return true end
    end
    return false
end

-- --- Probe: confirm the method is reachable from Lua --------------------

Safe.Set(function()
    local t = CS.Barotrauma.Networking.RespawnManager
    if t == nil then
        print("[HDC] RespawnManager type not visible")
        return
    end
    print("[HDC] RespawnManager found, ServerEventWrite =",
        tostring(t:GetMethod("ServerEventWrite")))
end)

-- --- Respawn / shuttle countdown (wire-level) ---------------------------

Safe.MakeFieldAccessible("Barotrauma.Networking.RespawnManager", "teamSpecificStates")

Safe.PatchMethod("Barotrauma.Networking.RespawnManager", "ServerEventWrite", nil,
    function(instance, ptable)
        if not enabled() then return end
        if instance == nil then return end

        -- ServerEventWrite runs once per recipient; Args[1] is that
        -- recipient (Client). Only mask the countdown in the packet a
        -- living player receives, so spectators/dead players still see
        -- the real timer.
        local recipient = Safe.Get(function() return ptable.Args[1] end)
        if recipient == nil or isSpectatorOrDead(recipient) then return end

        local saved = {}
        Safe.Set(function()
            for key, state in pairs(instance.teamSpecificStates) do
                saved[key] = { state.RespawnCountdownStarted, state.ReturnCountdownStarted }
                state.RespawnCountdownStarted = false
                state.ReturnCountdownStarted  = false
            end
        end)
        ptable.Data = saved
    end,
    Hook.HookMethodType.Before)

Safe.PatchMethod("Barotrauma.Networking.RespawnManager", "ServerEventWrite", nil,
    function(instance, ptable)
        if not enabled() then return end
        if instance == nil or ptable.Data == nil then return end
        Safe.Set(function()
            for key, flags in pairs(ptable.Data) do
                local state = instance.teamSpecificStates[key]
                if state ~= nil then
                    state.RespawnCountdownStarted = flags[1]
                    state.ReturnCountdownStarted  = flags[2]
                end
            end
        end)
    end,
    Hook.HookMethodType.After)

-- --- Round-end countdown (message path) ---------------------------------

-- All GUI.AddMessage overloads funnel through this signature, so one patch
-- catches both the string form and the LocalizedString form.
Safe.PatchMethod("Barotrauma.GUI", "AddMessage", nil, function(instance, ptable)
    if not enabled() or localCharacterIsSpectatorOrDead() then return end
    local msg = ptable.Args[0]
    if msg ~= nil and matches(tostring(msg)) then
        ptable.PreventExecution = true
    end
end, Hook.HookMethodType.Before)

-- --- Round-end countdown (persistent text block path) -------------------

-- Some builds hold the countdown in a long-lived text block rather than
-- re-adding it via GUI.AddMessage every tick. Blank any that match.
Safe.AddHook("think", "HDC.RespawnTimers.HideRoundEndText", function()
    if not enabled() or localCharacterIsSpectatorOrDead() then return end
    Safe.Set(function()
        local canvas = GUI.Canvas
        if canvas == nil then return end
        Safe.WalkComponents(canvas, function(node)
            local text = node.Text
            if text ~= nil and matches(tostring(text)) then
                node.Visible = false
            end
        end)
    end)
end)