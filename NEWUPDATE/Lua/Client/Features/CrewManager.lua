HDC = HDC or {}

local Safe        = HDC.Safe
local ClientState = HDC.ClientState

local KEY = "CrewManager"

local function enabled()
    return ClientState.Get(KEY) == true
end

-- Hide the crew HUD elements.
Safe.PatchMethod("Barotrauma.CrewManager", "AddToGUIUpdateList", nil, function(instance, ptable)
    if not enabled() then return end
    ptable.PreventExecution = true
end, Hook.HookMethodType.Before)

Safe.PatchMethod("Barotrauma.CrewManager", "UpdateReports", nil, function(instance, ptable)
    if not enabled() then return end
    ptable.PreventExecution = true
end, Hook.HookMethodType.Before)

-- Block the command interface from ever opening. Do NOT prevent
-- UpdateProjectSpecific: it owns the open/close lifecycle, FollowCursor,
-- and WasCommandInterfaceDisabledThisUpdate. Killing it leaves a dangling
-- commandFrame and locks the player out of inventory + camera.
Safe.PatchMethod("Barotrauma.CrewManager", "CreateCommandUI", nil, function(instance, ptable)
    if not enabled() then return end
    ptable.PreventExecution = true
end, Hook.HookMethodType.Before)

Safe.PatchMethod("Barotrauma.CrewManager", "OpenCommandUI", nil, function(instance, ptable)
    if not enabled() then return end
    ptable.PreventExecution = true
end, Hook.HookMethodType.Before)

--a fallback if commandUI somehow breaks the game
Safe.AddHook("think", "HDC.CrewManagerCleanup", function()
    if not enabled() then return end
    Safe.Set(function()
        local gs = GameMain.GameSession
        local cm = gs and gs.CrewManager
        if cm ~= nil then
            cm:DisableCommandUI()
        end
    end)
end)