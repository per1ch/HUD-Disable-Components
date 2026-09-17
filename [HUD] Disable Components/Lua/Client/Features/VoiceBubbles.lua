-- Lua/Client/Features/VoiceBubbles.lua — CLIENT
-- Spec item 5: hide the voice-chat bubble above speaking characters.
--
-- Built to match ChatBubbles.lua, the one bubble feature that works, with
-- the one difference the game forces. Chat bubbles live in a static list
-- with its own draw method, so that module suppresses the draw, suppresses
-- the spawn, and clears the queue. The voice bubble has no draw method of
-- its own: Character.textlessSpeechBubble is a single field drawn inline at
-- the end of Character.DrawFront, so the draw half is done by clearing the
-- field as DrawFront begins instead of by preventing a call.
--
-- VoipClient calls ShowTextlessSpeechBubble on every incoming voice packet,
-- which is why clearing the field on a think hook alone is not enough — a
-- packet landing between the sweep and the draw puts the bubble straight
-- back. Both ends are covered here.
--
-- Signatures are left to Hook.Patch to resolve, exactly as ChatBubbles.lua
-- does. The previous version named the ShowTextlessSpeechBubble overload
-- explicitly and only fell back to resolution if Hook.Patch threw — which
-- it does not do for a signature that simply matches nothing, so the
-- fallback never ran and the method went unpatched.

HDC = HDC or {}

local Safe        = HDC.Safe
local ClientState = HDC.ClientState

local KEY = "HideVoiceBubbles"

Safe.MakeFieldAccessible("Barotrauma.Character", "textlessSpeechBubble")

local function enabled()
    return ClientState.Get(KEY)
end

-- Speaking bubble
Safe.PatchMethod("Barotrauma.Character", "ShowTextlessSpeechBubble", nil, function(instance, ptable)
    if not enabled() then return end
    ptable.PreventExecution = true
end, Hook.HookMethodType.Before)

-- the field is read at the end of DrawFront
Safe.PatchMethod("Barotrauma.Character", "DrawFront", nil, function(instance, ptable)
    if not enabled() then return end
    if instance == nil then return end
    Safe.Set(function() instance.textlessSpeechBubble = nil end)
end, Hook.HookMethodType.Before)

Safe.AddHook("think", "HDC.VoiceBubbles.ClearQueued", function()
    if not enabled() then return end
    local characters = Safe.Get(function() return Character.CharacterList end)
    if characters == nil then return end
    for _, character in pairs(characters) do
        Safe.Set(function() character.textlessSpeechBubble = nil end)
    end
end)
