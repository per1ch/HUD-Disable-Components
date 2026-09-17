-- Lua/Server/Sync.lua — SERVER
--
-- Pushes the authoritative policy to clients and validates incoming edit
-- requests. The payload is a single JSON string, so adding a setting to
-- the registry needs no protocol change and no field-order agreement
-- between the two sides.
--
-- CONCURRENCY
-- Clients send only the fields they actually changed (see Client/Net.lua),
-- so two admins editing different settings never overwrite each other.
-- Every broadcast carries a monotonically increasing revision number so a
-- client can recognise and drop a stale message if one ever arrives out of
-- order — belt-and-braces, since a single TCP stream already preserves
-- ordering, but cheap and it makes forced resyncs unambiguous.

HDC = HDC or {}

local Safe        = HDC.Safe
local NetIds      = HDC.NetIds
local ServerState = HDC.ServerState
local Permissions = HDC.Permissions

local Sync = {}
HDC.Sync = Sync

-- Monotonic state-broadcast counter, per server session. Incremented on
-- anything that should force clients to accept a fresh payload, including
-- forced resyncs and the rejection echo, so a client is never stuck
-- ignoring a message whose only job is to correct their optimistic view.
local revision = 0

function Sync.SendTo(connection)
    if connection == nil then return end
    Safe.Set(function()
        local message = Networking.Start(NetIds.Sync)
        message.WriteString(tostring(revision))
        message.WriteString(ServerState.Serialize())
        Networking.Send(message, connection)
    end)
end

function Sync.Broadcast()
    local clients = Safe.Get(function() return Client.ClientList end)
    if clients == nil then return end
    for _, client in pairs(clients) do
        local connection = Safe.Get(function() return client.Connection end)
        if connection ~= nil then Sync.SendTo(connection) end
    end
end

-- New arrivals get the policy immediately, so they never render a frame
-- with the wrong HUD state. No revision bump: state has not changed, the
-- client's lastRevision is unset anyway, and we do not want to make an
-- existing client ignore this by accident.
Safe.AddHook("clientConnected", "HDC.Sync.ClientConnected", function(client)
    local connection = Safe.Get(function() return client.Connection end)
    if connection == nil then return end
    Sync.SendTo(connection)
end)

Networking.Receive(NetIds.EditRequest, function(message, sender)
    -- Always consume the payload, even when rejecting, or the stream desyncs.
    local raw = Safe.Get(function() return message.ReadString() end)

    if not Permissions.CanEditPolicy(sender) then
        Safe.Log("rejected settings change from " .. Permissions.DescribeClient(sender) ..
                 " (missing " .. Permissions.POLICY_COMMAND .. " permission)")
        -- Re-send the true state so their menu snaps back. Bump revision so
        -- the client actually accepts the correction instead of discarding
        -- it as a duplicate of a message they already applied.
        revision = revision + 1
        Sync.SendTo(Safe.Get(function() return sender.Connection end))
        return
    end

    local proposed = raw ~= nil and Safe.Get(function() return json.parse(raw) end) or nil
    if proposed == nil then
        Safe.Log("ignored malformed settings payload from " .. Permissions.DescribeClient(sender))
        return
    end

    -- ApplyTable only touches the keys present in the payload, which is why
    -- delta edits are safe: two admins editing different settings never
    -- clobber each other.
    ServerState.ApplyTable(proposed)
    ServerState.Save()

    revision = revision + 1
    Sync.Broadcast()

    Safe.Log("settings updated by " .. Permissions.DescribeClient(sender))
end)

Safe.AddCommand("hdc_serverstate", "Print the current [HUD] Disable Components policy on the server.",
    function()
        print("[HDC] Current server policy:\n" .. ServerState.Describe())
    end, nil, false)

Safe.AddCommand("hdc_resync", "Re-send the current [HUD] Disable Components policy to every client.",
    function()
        -- Bump even though the values may not have changed: this command
        -- exists precisely to force clients to re-apply, which requires a
        -- revision newer than whatever they last saw.
        revision = revision + 1
        Sync.Broadcast()
        print("[HDC] Policy re-sent to all clients.")
    end, nil, false)

return Sync
