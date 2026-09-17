--https://github.com/FakeFishGames/Barotrauma/blob/master/Barotrauma/BarotraumaClient/ClientSource/Characters/Health/CharacterHealth.cs
-- Lua/Server/GiveInBlock.lua — SERVER
-- Enforcement layer for spec item 11. The client-side patch hides the
-- Give In button cosmetically on modded clients; this module makes the
-- request itself a no-op for clients that still show the button
-- (unmodded, or mod loaded but disabled).
--
-- Flow when the button is clicked:
--   client: GameMain.Client.CreateEntityEvent(Controlled, new Character.CharacterStatusEventData())
--   server: receives the event, calls Apply on it, which kills the character
-- Patching Apply Before and setting PreventExecution drops the request
-- before the kill happens. The client is not notified, so an unmodded
-- player sees nothing when they click.
--
-- CharacterStatusEventData is a nested type inside Character, so the
-- LuaCs type string uses '+' as the separator (matching .NET reflection
-- for nested classes). If your build expects '.' instead, change the
-- constant below.

HDC = HDC or {}

local Safe        = HDC.Safe
local ServerState = HDC.ServerState

local EVENT_TYPE = "Barotrauma.Character+CharacterStatusEventData"

Safe.PatchMethod(EVENT_TYPE, "Apply", nil, function(instance, ptable)
    if ServerState.GetBool("DisableGiveIn") then
        ptable.PreventExecution = true
    end
end, Hook.HookMethodType.Before)
