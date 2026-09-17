-- Lua/Client/Features/GiveInButton.lua — CLIENT
-- Spec item 11: make the Give In (suicide) button non-functional.
--
-- CharacterHealth.UpdateHUD rewrites SuicideButton.Visible every frame
-- based on Character.IsIncapacitated. A think hook runs before UpdateHUD
-- and loses the race — the button flashes back on immediately. Patching
-- UpdateHUD After runs once the game has set the flag, so we win.
-- CharacterHealth.AddToGUIUpdateList then skips the button because
-- Visible is false, so it never enters the draw list.
--
-- This is the cosmetic layer. Server/GiveInBlock.lua is the enforcement
-- layer that stops unmodded clients from actually killing themselves.

HDC = HDC or {}

local Safe        = HDC.Safe
local ClientState = HDC.ClientState

local KEY = "DisableGiveIn"

Safe.PatchMethod("Barotrauma.CharacterHealth", "UpdateHUD", nil, function(instance, ptable)
    if ClientState.Get(KEY) ~= true then return end
    if instance == nil then return end
    Safe.Set(function()
        local button = instance.SuicideButton
        if button == nil then return end
        button.Visible = false
        button.Enabled = false
    end)
end, Hook.HookMethodType.After)
