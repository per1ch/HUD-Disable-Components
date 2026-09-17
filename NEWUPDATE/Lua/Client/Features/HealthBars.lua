-- Lua/Client/Features/HealthBars.lua — CLIENT
-- Spec item 1: hide the HP bars floating above characters.
--
-- Two layers, because the bar is drawn from two directions: the per-frame
-- hudInfoVisible flag on each character, and the CharacterParams property
-- the renderer consults before drawing.

HDC = HDC or {}

local Safe        = HDC.Safe
local ClientState = HDC.ClientState

local KEY = "HideHealthBars"

Safe.MakeFieldAccessible("Barotrauma.Character", "hudInfoVisible")

local function enabled()
    return ClientState.Get(KEY)
end

Safe.AddHook("think", "HDC.HealthBars.Suppress", function()
    if not enabled() then return end
    local characters = Safe.Get(function() return Character.CharacterList end)
    if characters == nil then return end
    for _, character in pairs(characters) do
        Safe.Set(function() character.hudInfoVisible = false end)
    end
end)

Safe.PatchMethod("Barotrauma.CharacterParams", "get_ShowHealthBar", nil, function(instance, ptable)
    if not enabled() then return end
    ptable.PreventExecution = true
    return false
end, Hook.HookMethodType.Before)

Safe.PatchMethod("Barotrauma.Character", "DrawFront", {
    "Microsoft.Xna.Framework.Graphics.SpriteBatch",
    "Barotrauma.Camera"
}, function(instance, ptable)
    if not enabled() then return end
    if instance == nil then return end
    Safe.Set(function() instance.hudInfoVisible = false end)
end, Hook.HookMethodType.Before)
