-- Lua/Server/Integrity.lua — SERVER
--
-- Detects clients that are not running the mod, have stopped responding,
-- or report a different version.
--
-- READ THIS BEFORE RELYING ON IT.
--
-- This is DETECTION, not prevention. A client that answers the heartbeat
-- correctly while ignoring the HUD policy locally is indistinguishable
-- from a compliant one, because the check runs on their machine and a
-- patched build can say whatever it likes. What this reliably catches:
--
--   * players who never installed or have disabled the mod
--   * players whose mod crashed or failed to load
--   * version mismatches after a mod update
--
-- What it cannot catch: someone who deliberately keeps the heartbeat
-- answering while suppressing the client-side restrictions. Treat a clean
-- report as "no evidence of a problem", never as proof of compliance.
-- Anything that must be guaranteed has to be enforced server-side, the way
-- the chat mute in Server/Moderation.lua is.

HDC = HDC or {}

local Safe        = HDC.Safe
local NetIds      = HDC.NetIds
local Permissions = HDC.Permissions

local Integrity = {}
HDC.Integrity = Integrity

local EXPECTED_VERSION = HDC.Version or "1.0.0"
local PROBE_INTERVAL   = 30    -- seconds between sweeps
local GRACE_PERIOD     = 20    -- seconds a client has to answer

-- session key -> { name, lastReply, version, missed }
local status = {}
local autoKick = false

local function keyOf(client)
    local id = Safe.Get(function() return tostring(client.SessionId) end)
    if id ~= nil then return id end
    return Safe.Get(function() return tostring(client.Name) end)
end

local function now()
    return Safe.Get(function() return Timer.GetTime() end) or 0
end

Networking.Receive(NetIds.Heartbeat, function(message, sender)
    if sender == nil then return end
    local version = Safe.Get(function() return message.ReadString() end)
    local key = keyOf(sender)
    if key == nil then return end

    status[key] = status[key] or { missed = 0 }
    status[key].name      = Safe.Get(function() return tostring(sender.Name) end)
    status[key].lastReply = now()
    status[key].version   = version
    status[key].missed    = 0
end)

local function probeAll()
    local clients = Safe.Get(function() return Client.ClientList end)
    if clients == nil then return end

    local currentTime = now()
    for _, client in pairs(clients) do
        local key = keyOf(client)
        if key ~= nil then
            local entry = status[key]
            if entry == nil then
                status[key] = { name = Safe.Get(function() return tostring(client.Name) end),
                                lastReply = 0, missed = 0 }
                entry = status[key]
            end

            -- Judge the previous round before sending a new probe.
            if entry.lastReply > 0 and currentTime - entry.lastReply > GRACE_PERIOD then
                entry.missed = entry.missed + 1
            elseif entry.lastReply == 0 and currentTime > GRACE_PERIOD then
                entry.missed = entry.missed + 1
            end

            if entry.missed == 2 then
                Safe.Log("client not responding to integrity probe: " .. tostring(entry.name) ..
                         " (mod missing, disabled, or failed to load)")
                if autoKick then
                    Safe.Set(function()
                        Game.SendDirectChatMessage("", "[HDC] Kicked: the required HUD mod is not responding.",
                            nil, ChatMessageType.Server, client)
                    end)
                    Safe.Set(function() client.Kick("[HDC] Required HUD mod not responding.") end)
                end
            end

            if entry.version ~= nil and entry.version ~= EXPECTED_VERSION then
                Safe.Log(string.format("version mismatch for %s: reports %s, server expects %s",
                    tostring(entry.name), tostring(entry.version), EXPECTED_VERSION))
            end

            Safe.Set(function()
                local probe = Networking.Start(NetIds.Heartbeat)
                Networking.Send(probe, client.Connection)
            end)
        end
    end
end

local function scheduleProbe()
    Safe.Set(function()
        Timer.Wait(function()
            probeAll()
            scheduleProbe()
        end, PROBE_INTERVAL * 1000)
    end)
end
scheduleProbe()

Safe.AddHook("clientDisconnected", "HDC.Integrity.Cleanup", function(client)
    local key = keyOf(client)
    if key ~= nil then status[key] = nil end
end)

Safe.AddCommand("hdc_integrity", "Show which clients are answering the mod integrity probe.", function()
    local currentTime = now()
    local any = false
    for _, entry in pairs(status) do
        any = true
        local age = entry.lastReply > 0 and string.format("%.0fs ago", currentTime - entry.lastReply)
                                         or "never"
        print(string.format("[HDC] %-24s last reply: %-12s version: %-8s missed: %d",
            tostring(entry.name), age, tostring(entry.version or "?"), entry.missed or 0))
    end
    if not any then print("[HDC] No clients tracked yet.") end
    print("[HDC] Detection only — a clean report is not proof of compliance.")
end, nil, false)

Safe.AddCommand("hdc_integrity_autokick",
    "Toggle auto-kicking clients that stop answering the integrity probe.",
    function(args, client)
        if not Permissions.CanEditPolicy(client) then
            print("[HDC] You do not have permission for this.")
            return
        end
        autoKick = not autoKick
        print("[HDC] Integrity auto-kick is now " .. (autoKick and "ON" or "off") .. ".")
    end, nil, false)

return Integrity
