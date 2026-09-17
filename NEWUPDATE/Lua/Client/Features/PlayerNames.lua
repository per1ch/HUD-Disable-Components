-- Lua/Client/Features/PlayerNames.lua — CLIENT
-- Spec item 2: hide player names — above the character, in the health
-- scanner readout, and in the health menu.
--
-- The overhead name is suppressed three ways because different code paths
-- reach it: the global DisableCharacterNames switch, a transparent name
-- colour, and the hover-text draw call. The scanner and health-menu
-- readouts are separate UI text elements, handled by blanking the name
-- text on the health interface after it is built.

HDC = HDC or {}

local Safe        = HDC.Safe
local ClientState = HDC.ClientState

local KEY = "HidePlayerNames"

local transparent = nil

local function enabled()
    return ClientState.Get(KEY)
end

local function transparentColor()
    if transparent ~= nil then return transparent end
    transparent = Safe.Get(function() return Color(255, 255, 255, 0) end)
               or Safe.Get(function() return Color.Transparent end)
    return transparent
end

-- The vanilla switch that hides names above heads.
Safe.AddHook("think", "HDC.PlayerNames.ToggleGlobalSwitch", function()
    local static = Safe.GUIStatic()
    if static == nil then return end
    Safe.Set(function() static.DisableCharacterNames = enabled() end)
end)

Safe.PatchMethod("Barotrauma.Character", "GetNameColor", nil, function(instance, ptable)
    if not enabled() then return end
    local color = transparentColor()
    if color == nil then return end
    ptable.PreventExecution = true
    return color
end, Hook.HookMethodType.Before)

Safe.PatchMethod("Barotrauma.CharacterHUD", "DrawCharacterHoverTexts", {
    "Microsoft.Xna.Framework.Graphics.SpriteBatch",
    "Barotrauma.Camera",
    "Barotrauma.Character"
}, function(instance, ptable)
    if not enabled() then return end
    ptable.PreventExecution = true
end, Hook.HookMethodType.Before)

-- Health menu / health scanner readout: the character's name is shown as
-- a text element on the health interface. Blank it once the UI exists,
-- rather than trying to prevent the whole interface from drawing.
local function blankNameOnHealthUI(healthInterface)
    if healthInterface == nil then return end
    Safe.WalkComponents(healthInterface, function(node)
        local text = Safe.Get(function() return node.Text end)
        if text == nil or tostring(text) == "" then return end

        local characters = Safe.Get(function() return Character.CharacterList end)
        if characters == nil then return end
        for _, character in pairs(characters) do
            local name = Safe.Get(function() return tostring(character.Name) end)
            if name ~= nil and name ~= "" and tostring(text) == name then
                Safe.Set(function() node.Text = "" end)
                return
            end
        end
    end)
end

Safe.PatchMethod("Barotrauma.CharacterHealth", "UpdateClientSpecific", nil, function(instance, ptable)
    if not enabled() then return end
    if instance == nil then return end
    local healthWindow = Safe.Get(function() return instance.InventoryContainer end)
                      or Safe.Get(function() return instance.HealthWindow end)
    blankNameOnHealthUI(healthWindow)
end, Hook.HookMethodType.After)

Safe.PatchMethod("Barotrauma.CharacterHealth", "AddToGUIUpdateList", nil, function(instance, ptable)
    if not enabled() then return end
    if instance == nil then return end
    local healthWindow = Safe.Get(function() return instance.HealthWindow end)
    blankNameOnHealthUI(healthWindow)
end, Hook.HookMethodType.After)
