-- Safe.PatchMethod("Barotrauma.CharacterHUD", "Draw", nil, function(instance, ptable)
--     if not enabled() then return end
--     ptable.PreventExecution = true
-- end, Hook.HookMethodType.Before)

-- Safe.PatchMethod("Barotrauma.CharacterHUD", "AddToGUIUpdateList", nil, function(instance, ptable)
--     if not enabled() then return end
--     ptable.PreventExecution = true
-- end, Hook.HookMethodType.Before)