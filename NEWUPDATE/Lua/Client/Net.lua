-- Lua/Client/Net.lua — CLIENT
--
-- Receives policy pushes from the server, sends edit requests upstream,
-- and answers the integrity heartbeat.
--
-- The policy payload is a single JSON string preceded by a revision
-- number, so clients can drop stale messages, and new settings need no
-- protocol change.
--
-- EDITS ARE DELTAS
-- Net.RequestPolicyChange expects a table containing only the keys the
-- user just changed, e.g. { MuteChatGlobal = true }. Sending a full
-- snapshot causes two admins editing different settings to overwrite each
-- other's changes with stale values carried in their own snapshot. The
-- server treats the payload as a patch, so deltas are the correct shape.

HDC = HDC or {}

local Safe        = HDC.Safe
local NetIds      = HDC.NetIds
local ClientState = HDC.ClientState

local Net = {}
HDC.Net = Net

-- Highest revision we have applied. Anything <= this is a duplicate or an
-- out-of-order arrival and is discarded. Starts below any real revision so
-- the very first message (revision 0) is accepted.
local lastRevision = -1

Networking.Receive(NetIds.Sync, function(message)
    local revRaw = Safe.Get(function() return message.ReadString() end)
    local rev    = tonumber(revRaw)
    local raw    = Safe.Get(function() return message.ReadString() end)
    if raw == nil then return end

    -- If the revision field is present and not newer than what we already
    -- have, drop the message. A nil revision (missing field, older server)
    -- is treated as valid so a version skew does not wedge the client.
    if rev ~= nil then
        if rev <= lastRevision then return end
        lastRevision = rev
    end

    local values = Safe.Get(function() return json.parse(raw) end)
    if values == nil then
        Safe.Log("malformed policy payload from server, ignoring")
        return
    end
    ClientState.ApplyFromServer(values)
end)

-- Sends a delta of the local view of the policy upstream. The server
-- decides whether to honour it (Server/Permissions.lua) and re-broadcasts
-- either way, so an unauthorised client's menu simply snaps back.
--
-- Pass ONLY the changed keys. Callers should mark the change pending in
-- ClientState first so an in-flight broadcast for the same field does not
-- undo the optimistic local value before the server confirms it:
--
--   ClientState.SetLocalPolicyValue(key, value)
--   ClientState.MarkPending(key, value)
--   Net.RequestPolicyChange({ [key] = value })
function Net.RequestPolicyChange(changes)
    Safe.Set(function()
        local message = Networking.Start(NetIds.EditRequest)
        message.WriteString(json.serialize(changes))
        Networking.Send(message)
    end)
end

-- Integrity probe: reply with the mod version so the server can spot
-- clients that are missing, stale, or not running the mod at all.
Networking.Receive(NetIds.Heartbeat, function(message)
    Safe.Set(function()
        local reply = Networking.Start(NetIds.Heartbeat)
        reply.WriteString(tostring(HDC.Version or "unknown"))
        Networking.Send(reply)
    end)
end)

function Net.IsMultiplayer()
    return Safe.Get(function() return Game.IsMultiplayer end) == true
end

return Net
