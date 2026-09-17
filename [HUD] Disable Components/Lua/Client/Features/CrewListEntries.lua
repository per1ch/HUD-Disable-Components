HDC = HDC or {}

local Safe        = HDC.Safe
local ClientState = HDC.ClientState

local KEY = "CrewListEntries"

Safe.PatchMethod("Barotrauma.CrewManager", "AddCharacterToCrewList", nil, function(instance, ptable)
    if ClientState.Get(KEY) ~= true then return end
    ptable.PreventExecution = true
end, Hook.HookMethodType.Before)

local KEY = "CrewList"

Safe.PatchMethod("Barotrauma.CrewManager", "UpdateProjectSpecific", nil, function(instance, ptable)
    if ClientState.Get(KEY) ~= true then return end
    Safe.Set(function()
        local field = instance:GetType():GetField("crewArea",
            CS.System.Reflection.BindingFlags.NonPublic + CS.System.Reflection.BindingFlags.Instance)
        if field == nil then return end
        local area = field:GetValue(instance)
        if area ~= nil then area.Visible = false end
    end)
end, Hook.HookMethodType.After)