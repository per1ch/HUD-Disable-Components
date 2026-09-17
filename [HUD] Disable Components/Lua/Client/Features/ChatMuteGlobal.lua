--rework to make it to just completely disable anyone from receiving chat messages (by server-side)

HDC = HDC or {}

local Safe        = HDC.Safe
local ClientState = HDC.ClientState

local KEY = "ChatMuteGlobal"

local function enabled()
    return ClientState.Get(KEY)
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