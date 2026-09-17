-- Lua/Client/Features/HealthMenuLock.lua — CLIENT
-- Spec item 8: stop a player opening their OWN health menu, while leaving
-- other players' health menus fully usable — so medics keep working and
-- nobody can sit in their own menu.
--
-- Character.DisableHealthWindow is a vanilla field that does exactly this.
-- CharacterHealth's OpenHealthWindow setter refuses to open a window whose
-- character has it set:
--
--     if (!value.UseHealthWindow || value.Character.DisableHealthWindow) { return; }
--
-- and it is checked against the character being OPENED, not the one doing
-- the opening. Setting it on Character.Controlled therefore blocks exactly
-- the own-menu case and nothing else. Every route in reaches that one
-- setter — the Health keybind, clicking your own health bar, selecting a
-- character — so there is no second path to cover.
--
-- Nothing in the game ever writes the field; it is read-only from
-- Barotrauma's side and exists for content and mods to set, so holding it
-- each frame fights nothing.
--
-- This replaces the previous approach, which blocked the menu for everyone
-- by suppressing OpenHealthWindow / ToggleHealthWindow outright and then
-- walking the open window to strip focus from every control in it.
--
-- One side effect worth knowing: Character.CanBeHealedBy also reads this
-- field, so on this client the local character reads as un-healable. It is
-- a client-local write — every other player's copy of your character still
-- has the field clear — so it does not stop anyone from treating you.

HDC = HDC or {}

local Safe        = HDC.Safe
local ClientState = HDC.ClientState

local KEY = "LockHealthMenu"

local function enabled()
    return ClientState.Get(KEY)
end

local healthType = nil

Safe.AddHook("think", "HDC.HealthMenuLock.Apply", function()
    local controlled = Safe.Get(function() return Character.Controlled end)
    if controlled == nil then return end

    Safe.Set(function() controlled.DisableHealthWindow = enabled() end)
    if not enabled() then return end

    -- The field only refuses new opens. A menu already on screen when the
    -- policy arrives has to be closed here, through the same setter, which
    -- always accepts nil.
    if healthType == nil then
        healthType = Safe.Static("Barotrauma.CharacterHealth")
    end
    if healthType == nil then return end

    local open = Safe.Get(function() return healthType.OpenHealthWindow end)
    if open == nil then return end
    if Safe.Get(function() return open.Character end) == controlled then
        Safe.Set(function() healthType.OpenHealthWindow = nil end)
    end
end)
