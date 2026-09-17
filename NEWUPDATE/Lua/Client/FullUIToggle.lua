-- HDC = HDC or {}

-- local Safe        = HDC.Safe
-- local ClientState = HDC.ClientState

-- local KEY = "HideOwnUI"

-- local function enabled()
--     return ClientState.GetLocal(KEY)
-- end

-- Safe.PatchMethod("Barotrauma.CharacterHUD", "Draw", nil, function(instance, ptable)
--     if not enabled() then return end
--     ptable.PreventExecution = true
-- end, Hook.HookMethodType.Before)

-- Safe.PatchMethod("Barotrauma.CharacterHUD", "AddToGUIUpdateList", nil, function(instance, ptable)
--     if not enabled() then return end
--     ptable.PreventExecution = true
-- end, Hook.HookMethodType.Before)

-- Safe.PatchMethod("Barotrauma.CrewManager", "AddToGUIUpdateList", nil, function(instance, ptable)
--     if not enabled() then return end
--     ptable.PreventExecution = true
-- end, Hook.HookMethodType.Before)

-- Safe.AddCommand("hdc_hideui", "Toggle your own interface on/off (affects only you).", function()
--     local now = ClientState.ToggleLocal(KEY)
--     print("[HDC] Your interface is now " .. (now and "HIDDEN" or "visible") .. ".")
-- end, nil, false)
