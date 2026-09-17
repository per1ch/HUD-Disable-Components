-- Lua/Server/Features/ChatMuteGlobal.lua — SERVER
--
-- Spec item 16, global half: the ChatMuteGlobal toggle drops a living
-- player's chat before it is ever broadcast. Independent of the
-- per-player mute in Server/Moderation.lua, which is a targeted
-- moderator action rather than broadcast policy.
--
-- Spectators and dead players are exempt — the toggle locks down the
-- living round, not the whole server — and so is any message that starts
-- with a punctuation character (e.g. "!alive", "/alive"), so commands
-- keep working for the people the mute is meant to leave alone.

HDC = HDC or {}

local Safe        = HDC.Safe
local ServerState = HDC.ServerState

local KEY = "ChatMuteGlobal"

local function isSpectatorOrDead(client)
    local character = Safe.Get(function() return client.Character end)
    if character == nil then return true end -- spectating / not spawned
    return Safe.Get(function() return character.IsDead end) == true
end

-- The chatMessage hook hands over a ChatMessage object in some LuaCs
-- versions and a plain string in others, so read both shapes.
local function messageText(message)
    local text = Safe.Get(function() return tostring(message.Text) end)
    if text ~= nil and text ~= "" then return text end
    return Safe.Get(function() return tostring(message) end)
end

local function looksLikeCommand(text)
    return text ~= nil and text:match("^%s*%p") ~= nil
end

local function shouldBlock(sender, text)
    if sender == nil then return false end
    if ServerState.Get(KEY) ~= true then return false end
    if looksLikeCommand(text) then return false end
    return not isSpectatorOrDead(sender)
end

Safe.AddHook("chatMessage", "HDC.ChatMuteGlobal.FilterChat", function(message, sender)
    if shouldBlock(sender, messageText(message)) then return true end
end)
