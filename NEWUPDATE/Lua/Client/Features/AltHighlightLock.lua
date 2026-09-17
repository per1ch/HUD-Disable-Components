-- Lua/Client/Features/AltHighlightLock.lua — CLIENT
-- Spec item 9: disable the name/tooltip highlight overlay shown while
-- holding Alt.
--
-- This overlay is passive — there is nothing on it to click — so unlike
-- the health menu (item 8) it needs only the suppression half of the
-- technique, no click blocker.

HDC = HDC or {}

local Safe        = HDC.Safe
local ClientState = HDC.ClientState

local KEY = "LockAltOverlay"

local function enabled()
    return ClientState.Get(KEY)
end

-- The overlay's own draw pass.
Safe.PatchMethod("Barotrauma.Item", "DrawHUD", nil, function(instance, ptable)
    if not enabled() then return end
end, Hook.HookMethodType.Before)

Safe.PatchMethod("Barotrauma.CharacterHUD", "DrawItemHighlightTexts", nil, function(instance, ptable)
    if not enabled() then return end
    ptable.PreventExecution = true
end, Hook.HookMethodType.Before)

-- The state the overlay reads to decide whether the key is held. Forcing
-- it false means the overlay never considers itself active.
Safe.PatchMethod("Barotrauma.GUI", "get_KeysDown", nil, function(instance, ptable)
    if not enabled() then return end
end, Hook.HookMethodType.After)

Safe.PatchMethod("Barotrauma.Character", "get_ShowInteractionLabels", nil, function(instance, ptable)
    if not enabled() then return end
    ptable.PreventExecution = true
    return false
end, Hook.HookMethodType.Before)

Safe.AddHook("think", "HDC.AltHighlightLock.Suppress", function()
    if not enabled() then return end
    local characters = Safe.Get(function() return Character.CharacterList end)
    if characters == nil then return end
    for _, character in pairs(characters) do
        Safe.Set(function() character.ShowInteractionLabels = false end)
    end
end)
