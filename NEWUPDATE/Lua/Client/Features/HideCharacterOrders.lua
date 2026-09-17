HDC = HDC or {}

local Safe        = HDC.Safe
local ClientState = HDC.ClientState

local KEY = "HideCharacterOrders"

local function enabled()
    return ClientState.Get(KEY)
end

-- Crew status panel (the upper-HUD list of crew members).
Safe.PatchMethod("Barotrauma.CrewManager", "DrawCharacterOrder", nil, function(instance, ptable)
    if not enabled() then return end
    ptable.PreventExecution = true
end, Hook.HookMethodType.Before)
