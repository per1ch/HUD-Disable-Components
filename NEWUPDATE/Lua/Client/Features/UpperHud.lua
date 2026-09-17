-- Lua/Client/Features/UpperHud.lua — CLIENT
-- Spec item 10: hide the upper HUD crew panel and the respawn / round-end
-- timers.
--
-- IMPORTANT — why this is done by rendering only:
-- The reference mod for this feature hides players by REMOVING them from
-- the underlying crew/client list. That is the cause of its three known
-- bugs: bot commands break, players can no longer be selected in the tab
-- menu (forcing console bans), and the round-end screen reports "your team
-- died on a mission" even after a success, because the game genuinely
-- believes the crew is gone.
--
-- This module never touches the real list. It suppresses visibility only,
-- so the game's own state stays fully intact.
--
-- What this actually patches (the previous version hooked three names that
-- do not exist in the client source):
--   * CrewManager.crewArea — the crew panel. UpdateProjectSpecific sets
--     its Visible every frame, so an After hook forcing it false wins.
--   * GameSession.topLeftButtonGroup — the strip holding the crew-list
--     toggle, command button, tab-menu button, respawn info text and
--     death-choice buttons. AddToGUIUpdateList also queues GameMode,
--     TabMenu, ObjectiveManager and DeathPrompt, so PreventExecution
--     there would break all of those; an After hook that flips Visible
--     hides only the strip.
--
-- crewArea and topLeftButtonGroup are private fields. If LuaCs refuses to
-- read them from this build, make them accessible first with
-- Safe.MakeFieldAccessible("Barotrauma.CrewManager",     "crewArea")
-- Safe.MakeFieldAccessible("Barotrauma.GameSession",     "topLeftButtonGroup")

HDC = HDC or {}

local Safe        = HDC.Safe
local ClientState = HDC.ClientState

local KEY = "HideUpperHud"

local function enabled()
    return ClientState.Get(KEY) == true
end

Safe.PatchMethod("Barotrauma.CrewManager", "UpdateProjectSpecific", nil, function(instance, ptable)
    if not enabled() then return end
    if instance == nil then return end
    Safe.Set(function()
        if instance.crewArea ~= nil then
            instance.crewArea.Visible = false
        end
    end)
end, Hook.HookMethodType.After)

Safe.PatchMethod("Barotrauma.GameSession", "AddToGUIUpdateList", nil, function(instance, ptable)
    if not enabled() then return end
    if instance == nil then return end
    Safe.Set(function()
        if instance.topLeftButtonGroup ~= nil then
            instance.topLeftButtonGroup.Visible = false
        end
    end)
end, Hook.HookMethodType.After)
