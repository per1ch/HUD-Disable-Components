-- Lua/Server/Features/CrewManager.lua — SERVER
--
-- Hard enforcement for the CrewManager toggle. Client/Features/CrewManager.lua
-- only blocks the local command UI from ever opening (CreateCommandUI /
-- OpenCommandUI) — a modified or vanilla client could still make the
-- underlying request. This patches Character.SetOrder, the method every
-- "give this crew member an order" path funnels through, and refuses it
-- when a real player is behind it.
--
-- Order.OrderGiver is a real player Character only when a human actually
-- issued the order through the UI; the engine's own internal SetOrder
-- calls (bot AI logic, the automatic Dismissal order on a team change,
-- etc.) either pass no OrderGiver or one that never resolves to a
-- connected Client. Gating on "OrderGiver resolves to a connected
-- Client" therefore blocks exactly the player-issued case and leaves
-- every internal call alone — nothing else the mod isn't meant to touch
-- should ever stop working.
--
-- SetOrder's exact overload could not be confirmed against this build
-- from source alone; the probe below logs whether the patch attached so
-- a bad guess is visible immediately instead of silently doing nothing.

HDC = HDC or {}

local Safe        = HDC.Safe
local ServerState = HDC.ServerState

local KEY = "CrewManager"

local function enabled() return ServerState.Get(KEY) == true end

Safe.Set(function()
    local t = CS.Barotrauma.Character
    if t == nil then
        print("[HDC] Character type not visible")
        return
    end
    print("[HDC] Character found, SetOrder =", tostring(t:GetMethod("SetOrder")))
end)

Safe.PatchMethod("Barotrauma.Character", "SetOrder", nil, function(instance, ptable)
    if not enabled() then return end

    local order = Safe.Get(function() return ptable.Args[0] end)
    if order == nil then return end

    local giver = Safe.Get(function() return order.OrderGiver end)
    if giver == nil then return end -- no human behind it (bot AI, internal dismissal, ...)

    local client = Safe.FindClientByCharacter(giver)
    if client == nil then return end -- giver isn't a connected player either

    ptable.PreventExecution = true
    Safe.SendDirectMessage(client, "[HDC] Giving orders is disabled on this server.")
end, Hook.HookMethodType.Before)
