-- Lua/Client/Features/ChatBubbles.lua — CLIENT
-- Spec item 4: hide the speech bubble carrying a typed chat message.
--
-- Both the draw call and the spawn call are suppressed: preventing the
-- draw alone would still leave bubbles queued on the character, which
-- would then pop into view the moment the toggle is turned off.

HDC = HDC or {}

local Safe        = HDC.Safe
local ClientState = HDC.ClientState

local KEY = "HideChatBubbles"

Safe.MakeFieldAccessible("Barotrauma.Character", "speechBubbles")

local function enabled()
    return ClientState.Get(KEY)
end

Safe.PatchMethod("Barotrauma.Character", "DrawSpeechBubbles", {
    "Microsoft.Xna.Framework.Graphics.SpriteBatch",
    "Barotrauma.Camera"
}, function(instance, ptable)
    if not enabled() then return end
    ptable.PreventExecution = true
end, Hook.HookMethodType.Before)

Safe.PatchMethod("Barotrauma.Character", "ShowSpeechBubble", nil, function(instance, ptable)
    if not enabled() then return end
    ptable.PreventExecution = true
end, Hook.HookMethodType.Before)

-- Clear anything already queued while the toggle is on.
Safe.AddHook("think", "HDC.ChatBubbles.ClearQueued", function()
    if not enabled() then return end
    local characters = Safe.Get(function() return Character.CharacterList end)
    if characters == nil then return end
    for _, character in pairs(characters) do
        local bubbles = Safe.Get(function() return character.speechBubbles end)
        if bubbles ~= nil then
            pcall(function() bubbles:Clear() end)
        end
    end
end)
