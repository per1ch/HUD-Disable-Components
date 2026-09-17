--https://github.com/FakeFishGames/Barotrauma/blob/master/Barotrauma/BarotraumaClient/ClientSource/GUI/GUI.cs
--https://github.com/FakeFishGames/Barotrauma/blob/master/Barotrauma/BarotraumaClient/ClientSource/Characters/Character.cs
-- Lua/Client/CursorToggle.lua — CLIENT
-- Policy is synced like any other feature. When on, the cursor is hidden
-- while the player holds the Aim input (ranged weapon or turret).
--
-- Aiming is not a Character property; vanilla checks the Aim input via
-- Character.IsKeyDown(InputType.Aim). We do the same.
--
-- GUI.HideCursor is a public static bool, not a method — write the flag,
-- do not patch. DrawCursor is also patched as a belt-and-braces suppress
-- in case the flag alone isn't enough in a given build.

HDC = HDC or {}

local Safe        = HDC.Safe
local ClientState = HDC.ClientState

local KEY = "HideCursor"

local function isAiming()
    return Safe.Get(function()
        local c = Character.Controlled
        if c == nil or c.IsDead == true then return false end
        return c.IsKeyDown(InputType.Aim) == true
    end) == true
end

--WIP
--currently here is a problem "attempt to call a nil value"
-- local function hasRangedWeapon()
--     return Safe.Get(function()
--         local c = Character.Controlled
--         if c == nil or c.IsDead == true then return false end
--         local item = Safe.Get(function()
--             local prop = c:GetType():GetProperty("SelectedItem")
--             if prop == nil then return nil end
--             return prop:GetValue(c)
--         end)
--         if item == nil then return false end
--         return item.GetComponent("RangedWeapon") ~= nil
--     end) == true
-- end


local function shouldHideCursor()
    if ClientState.Get(KEY) ~= true then return false end
    if Safe.Get(function() return GUI.PauseMenuOpen end) == true then return false end
    return isAiming()
    -- return isAiming() and hasRangedWeapon()
end

Safe.AddHook("think", "HDC.HideCursor.Think", function()
    if ClientState.Get(KEY) ~= true then return end
    local want = shouldHideCursor()
    Safe.Set(function()
        if GUI.HideCursor ~= want then GUI.HideCursor = want end
    end)
end)

Safe.PatchMethod("Barotrauma.GUI", "DrawCursor", nil, function(instance, ptable)
    if shouldHideCursor() then
        ptable.PreventExecution = true
    end
end, Hook.HookMethodType.Before)
