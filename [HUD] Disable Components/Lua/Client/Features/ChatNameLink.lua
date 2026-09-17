-- Lua/Client/Features/ChatNameLink.lua — CLIENT
-- Spec item 12: remove the clickable player-profile link from chat names.
--
-- Two independent paths exist and both must be closed:
--   * the sender name is a transparent GUIButton layered over the text,
--     whose OnClicked calls NetLobbyScreen.SelectPlayer;
--   * any player reference inside the message body becomes an entry in
--     the GUITextBlock's ClickableAreas collection.
--
-- CanBeFocused is NOT the lever here - it governs keyboard focus, not
-- mouse picking. The button fires its OnClicked regardless of that flag,
-- which is why the previous version had no visible effect.

HDC = HDC or {}

local Safe        = HDC.Safe
local ClientState = HDC.ClientState

local KEY = "HideChatNameLink"

local function enabled()
    return ClientState.Get(KEY) == true
end

-- Replaces a click handler with a no-op that still reports "consumed",
-- so the event does not fall through to any parent component.
local function deafen(node)
    Safe.Set(function()
        if node.OnClicked ~= nil then
            node.OnClicked = function() return true end
        end
        if node.OnSecondaryClicked ~= nil then
            node.OnSecondaryClicked = function() return true end
        end
    end)
end

local function stripLinks(root)
    if root == nil then return end
    Safe.WalkComponents(root, function(node)
        deafen(node)
        Safe.Set(function()
            -- ClickableAreas only exists on GUITextBlock; guard for the rest.
            if node.ClickableAreas ~= nil then
                node.ClickableAreas.Clear()
            end
        end)
    end)
end

-- Resolve the message list box, whichever field name this build uses.
-- The class is <c>ChatBox</c>; the list box holding the message rows has
-- been called <c>chatBox</c> historically but is not guaranteed. Fall back
-- to the ChatBox instance itself if the field lookup misses, and let the
-- walk find the text blocks anyway - it costs a little more per message
-- but never misses.
local function messageContainer(instance)
    local field = Safe.Get(function() return instance.chatBox end)
    if field ~= nil then return field end
    return instance
end

Safe.PatchMethod("Barotrauma.ChatBox", "AddMessage", nil, function(instance, ptable)
    if not enabled() then return end
    if instance == nil then return end
    stripLinks(messageContainer(instance))
end, Hook.HookMethodType.After)

-- Belt and braces: some builds attach the clickable areas on the next
-- layout pass rather than inside AddMessage. Re-strip each frame while the
-- setting is on. Chat holds sixty messages at most, so the walk is cheap.
Safe.AddHook("think", "HDC.ChatNameLink.Strip", function()
    if not enabled() then return end
    local boxes = Safe.Get(function() return ChatBox.ChatBoxes end)
    if boxes == nil then return end
    for _, box in pairs(boxes) do
        stripLinks(messageContainer(box))
    end
end)

Safe.PatchMethod("Barotrauma.ChatBox", "AddMessage", nil, function(instance, ptable)
    Safe.Set(function()
        local container = messageContainer(instance)
        Safe.WalkComponents(container, function(node)
            print("[chat] node:", tostring(node:GetType().Name),
                  "OnClicked=", tostring(node.OnClicked ~= nil),
                  "ClickableAreas=", tostring(node.ClickableAreas ~= nil),
                  "CanBeFocused=", tostring(node.CanBeFocused))
        end)
    end)
end, Hook.HookMethodType.After)