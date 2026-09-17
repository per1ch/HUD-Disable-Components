-- Lua/Client/Features/SkillXpPopups.lua — CLIENT
-- Spec item 3: hide skill-increase and experience-gain notifications.
--
-- These arrive as floating GUI messages attached to the character. The
-- draw call is suppressed and the queue is drained, so nothing pops back
-- into view when the toggle is switched off.

HDC = HDC or {}

local Safe        = HDC.Safe
local ClientState = HDC.ClientState

local KEY = "HideSkillXpPopups"

Safe.MakeFieldAccessible("Barotrauma.Character", "guiMessages")

local function enabled()
    return ClientState.Get(KEY)
end

Safe.PatchMethod("Barotrauma.Character", "DrawGUIMessages", {
    "Microsoft.Xna.Framework.Graphics.SpriteBatch",
    "Barotrauma.Camera"
}, function(instance, ptable)
    if not enabled() then return end
    ptable.PreventExecution = true
end, Hook.HookMethodType.Before)

-- Stop the messages being queued in the first place.
Safe.PatchMethod("Barotrauma.Character", "AddMessage", nil, function(instance, ptable)
    if not enabled() then return end
    ptable.PreventExecution = true
end, Hook.HookMethodType.Before)

-- The skill-up notification also surfaces through the character's skill
-- tracker; block the popup it raises.
Safe.PatchMethod("Barotrauma.CharacterInfo", "OnSkillChanged", nil, function(instance, ptable)
    if not enabled() then return end
    ptable.PreventExecution = true
end, Hook.HookMethodType.Before)

Safe.AddHook("think", "HDC.SkillXpPopups.ClearQueued", function()
    if not enabled() then return end
    local characters = Safe.Get(function() return Character.CharacterList end)
    if characters == nil then return end
    for _, character in pairs(characters) do
        local messages = Safe.Get(function() return character.guiMessages end)
        if messages ~= nil then
            pcall(function() messages:Clear() end)
        end
    end
end)
