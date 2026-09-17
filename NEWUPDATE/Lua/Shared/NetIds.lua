-- Lua/Shared/NetIds.lua — SHARED (loaded in both SERVER and CLIENT contexts)
--
-- Namespaced network message identifiers. Kept in one place so producer
-- and consumer can never drift apart on the string used.

HDC = HDC or {}

HDC.NetIds = {
    -- Settings policy
    Sync        = "HDC_Sync",        -- server -> client: full policy as JSON
    EditRequest = "HDC_EditRequest", -- client -> server: proposed policy; applied only if permitted

    -- Remote console
    RemoteExec    = "HDC_RemoteExec",    -- admin -> server -> target client: command to run
    ConsoleOutput = "HDC_ConsoleOutput", -- target client -> server -> watching admins: console line
    ConsoleAttach = "HDC_ConsoleAttach", -- admin -> server: start/stop watching a target's console

    -- Integrity
    Heartbeat = "HDC_Heartbeat", -- server <-> client: liveness and version attestation
}

return HDC.NetIds
