-- Lua/Client/Features/ChatMuteGlobal.lua — CLIENT
--
-- Visual/interactive half of the global mute: hides and disables the
-- local chat box so a muted player cannot even try to type. The real
-- enforcement is server-side (Server/Moderation.lua drops the message
-- before broadcast), so this is belt-and-braces, not the source of truth
-- — a modified client can ignore it and still gets dropped server-side.
--
-- Spectators and dead players are exempt, matching the server-side rule:
-- the global toggle locks down the living round, not the whole server.

HDC = HDC or {}

local Safe        = HDC.Safe
local ClientState = HDC.ClientState

local KEY = "ChatMuteGlobal"

local function isSpectatorOrDead()
    return Safe.Get(function()
        local c = Character.Controlled
        return c == nil or c.IsDead == true
    end) == true
end

local function enabled()
    if ClientState.Get(KEY) ~= true then return false end
    return not isSpectatorOrDead()
end

local chatBoxType = nil
local function chatBox()
    if chatBoxType == nil then
        chatBoxType = Safe.Static("Barotrauma.ChatBox")
    end
    if chatBoxType == nil then return nil end
    return Safe.Get(function() return chatBoxType.GetChatBox() end)
end

local hiddenByUs = false

Safe.AddHook("think", "HDC.ChatMuteGlobal.Apply", function()
    local box = chatBox()
    if box == nil then return end

    if not enabled() then
        if hiddenByUs then
            Safe.Set(function() box.SetVisibility(true) end)
            Safe.Set(function() box.InputBox.Enabled = true end)
            hiddenByUs = false
        end
        return
    end

    Safe.Set(function() box.SetVisibility(false) end)
    Safe.Set(function() box.InputBox.Enabled = false end)
    hiddenByUs = true
    local typed = Safe.Get(function() return tostring(box.InputBox.Text) end)
    if typed ~= nil and typed ~= "" then
        Safe.Set(function() box.InputBox.Text = "" end)
    end

    if Safe.Get(function() return box.InputBox.Selected end) == true then
        Safe.Set(function() box.InputBox.Deselect() end)
    end
end)