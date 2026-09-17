-- Lua/Client/UI/RemoteConsoleUI.lua — CLIENT
--
-- Admin-facing window: a list of connected players on the left, and a
-- console per player on the right — output log plus a command input.
--
-- This UI is available to everyone, on purpose. Every client downloads the
-- whole mod, so hiding the window would be theatre; instead the server
-- authorizes each message and simply refuses to act for anyone without the
-- hudRemoteConsole permission (Server/RemoteConsole.lua). A player without
-- it can open this and type, and nothing will happen.

HDC = HDC or {}

local Safe   = HDC.Safe
local NetIds = HDC.NetIds

local RemoteConsoleUI = {}
HDC.RemoteConsoleUI = RemoteConsoleUI

local PALETTE = {
    title       = Color(50,  200, 225, 255),
    subtitle    = Color(145, 162, 172, 195),
    separator   = Color(35,  162, 198, 150),
    logNormal   = Color(198, 205, 212, 235),
    logCommand  = Color(120, 210, 255, 255),
    logError    = Color(240, 120, 110, 255),
    selectedRow = Color(30,  110, 150, 200),
}

local MAX_LOG_LINES = 300

local ui = {
    root      = nil,
    playerList= nil,
    logList   = nil,
    inputBox  = nil,
    header    = nil,
    isOpen    = false,
}

-- session id -> { name = string, lines = { text } }
local consoles = {}
local selectedId = nil

local function consoleFor(sessionId, name)
    local entry = consoles[sessionId]
    if entry == nil then
        entry = { name = name or "?", lines = {} }
        consoles[sessionId] = entry
    end
    if name ~= nil and name ~= "?" then entry.name = name end
    return entry
end

local function colorForLine(text)
    local lowered = string.lower(tostring(text))
    if string.find(lowered, "[error]", 1, true) or string.find(lowered, "error", 1, true) then
        return PALETTE.logError
    end
    if string.sub(text, 1, 1) == "[" and string.find(text, "] > ", 1, true) then
        return PALETTE.logCommand
    end
    return PALETTE.logNormal
end

local function renderLog()
    if ui.logList == nil then return end
    Safe.Set(function() ui.logList.Content:ClearChildren() end)

    local entry = selectedId ~= nil and consoles[selectedId] or nil
    if entry == nil then return end

    for _, line in ipairs(entry.lines) do
        local block = GUI.TextBlock(
            GUI.RectTransform(Vector2(1, 0.05), ui.logList.Content.RectTransform),
            line, colorForLine(line), nil, GUI.Alignment.CenterLeft, true)
        Safe.Set(function()
            block.TextScale    = 0.85
            block.CanBeFocused = false
        end)
    end
    Safe.Set(function() ui.logList.UpdateScrollBarSize() end)
    Safe.Set(function() ui.logList.ScrollBar.BarScroll = 1 end)
end

-- Client list as seen from this machine.
local function connectedClients()
    local result = {}
    local list = Safe.Get(function() return Game.Client.ConnectedClients end)
                or Safe.Get(function() return GameMain.Client.ConnectedClients end)
    if list == nil then return result end
    pcall(function()
        for client in list do
            local id = Safe.Get(function() return tostring(client.SessionId) end)
                    or Safe.Get(function() return tostring(client.ID) end)
            local name = Safe.Get(function() return tostring(client.Name) end) or "?"
            if id ~= nil then table.insert(result, { id = id, name = name }) end
        end
    end)
    return result
end

local function attach(sessionId, on)
    Safe.Set(function()
        local message = Networking.Start(NetIds.ConsoleAttach)
        message.WriteString(tostring(sessionId))
        message.WriteBoolean(on and true or false)
        Networking.Send(message)
    end)
end

local function selectPlayer(sessionId, name)
    if selectedId ~= nil and selectedId ~= sessionId then
        attach(selectedId, false)
    end
    selectedId = sessionId
    consoleFor(sessionId, name)
    attach(sessionId, true)

    Safe.Set(function()
        ui.header.Text = "Console: " .. tostring(name) .. "  (session " .. tostring(sessionId) .. ")"
    end)
    renderLog()
end

local function refreshPlayerList()
    if ui.playerList == nil then return end
    Safe.Set(function() ui.playerList.Content:ClearChildren() end)

    for _, player in ipairs(connectedClients()) do
        local row = GUI.Button(
            GUI.RectTransform(Vector2(1, 0.08), ui.playerList.Content.RectTransform),
            player.name, GUI.Alignment.CenterLeft, "GUIButtonSmall")
        Safe.Set(function() row.TextBlock.TextScale = 0.95 end)
        if player.id == selectedId then
            Safe.Set(function() row.Color = PALETTE.selectedRow end)
        end
        local capturedId, capturedName = player.id, player.name
        row.OnClicked = function()
            selectPlayer(capturedId, capturedName)
            refreshPlayerList()
            return true
        end
    end
end

local function sendCommand()
    if ui.inputBox == nil or selectedId == nil then return end
    local text = Safe.Get(function() return tostring(ui.inputBox.Text) end)
    if text == nil or text:match("^%s*$") then return end

    Safe.Set(function()
        local message = Networking.Start(NetIds.RemoteExec)
        message.WriteString(tostring(selectedId))
        message.WriteString(text)
        Networking.Send(message)
    end)
    Safe.Set(function() ui.inputBox.Text = "" end)
end

local function build()
    if ui.root ~= nil then return end

    ui.root = GUI.Frame(GUI.RectTransform(Vector2(1, 1)), "GUIBackgroundBlocker")
    ui.root.Visible      = false
    ui.root.CanBeFocused = true

    local panel = GUI.Frame(
        GUI.RectTransform(Vector2(0.72, 0.78), ui.root.RectTransform, GUI.Anchor.Center), "GUIFrame")

    local title = GUI.TextBlock(
        GUI.RectTransform(Vector2(0.8, 0.08), panel.RectTransform, GUI.Anchor.TopLeft),
        "REMOTE CONSOLE", nil, GUI.Style.LargeFont, GUI.Alignment.CenterLeft)
    title.RectTransform.RelativeOffset = Vector2(0.03, 0.02)
    Safe.Set(function() title.TextColor = PALETTE.title end)

    local subtitle = GUI.TextBlock(
        GUI.RectTransform(Vector2(0.94, 0.04), panel.RectTransform, GUI.Anchor.TopLeft),
        "Requires the hudRemoteConsole permission. Commands are whitelisted and logged on the server.",
        nil, nil, GUI.Alignment.CenterLeft)
    subtitle.RectTransform.RelativeOffset = Vector2(0.03, 0.093)
    Safe.Set(function()
        subtitle.TextColor    = PALETTE.subtitle
        subtitle.TextScale    = 0.88
        subtitle.CanBeFocused = false
    end)

    local separator = GUI.Frame(
        GUI.RectTransform(Vector2(0.94, 0.004), panel.RectTransform, GUI.Anchor.TopCenter),
        "GUIFrameListBox")
    separator.RectTransform.RelativeOffset = Vector2(0, 0.145)
    Safe.Set(function() separator.Color = PALETTE.separator end)

    -- Left: players
    local playerFrame = GUI.Frame(
        GUI.RectTransform(Vector2(0.28, 0.63), panel.RectTransform, GUI.Anchor.TopLeft),
        "GUIFrameListBox")
    playerFrame.RectTransform.RelativeOffset = Vector2(0.03, 0.163)
    ui.playerList = GUI.ListBox(
        GUI.RectTransform(Vector2(1, 1), playerFrame.RectTransform, GUI.Anchor.Center), false)

    -- Right: console
    ui.header = GUI.TextBlock(
        GUI.RectTransform(Vector2(0.62, 0.04), panel.RectTransform, GUI.Anchor.TopLeft),
        "Select a player", nil, nil, GUI.Alignment.CenterLeft)
    ui.header.RectTransform.RelativeOffset = Vector2(0.34, 0.163)
    Safe.Set(function()
        ui.header.TextColor    = PALETTE.subtitle
        ui.header.CanBeFocused = false
    end)

    local logFrame = GUI.Frame(
        GUI.RectTransform(Vector2(0.63, 0.535), panel.RectTransform, GUI.Anchor.TopLeft),
        "GUIFrameListBox")
    logFrame.RectTransform.RelativeOffset = Vector2(0.34, 0.213)
    ui.logList = GUI.ListBox(
        GUI.RectTransform(Vector2(1, 1), logFrame.RectTransform, GUI.Anchor.Center), false)

    ui.inputBox = GUI.TextBox(
        GUI.RectTransform(Vector2(0.52, 0.055), panel.RectTransform, GUI.Anchor.BottomLeft),
        "", nil, nil, nil, true)
    ui.inputBox.RectTransform.RelativeOffset = Vector2(0.34, -0.075)
    ui.inputBox.OnEnterPressed = function()
        sendCommand()
        return true
    end

    local sendButton = GUI.Button(
        GUI.RectTransform(Vector2(0.10, 0.055), panel.RectTransform, GUI.Anchor.BottomLeft),
        "Send", GUI.Alignment.Center, "GUIButtonSmall")
    sendButton.RectTransform.RelativeOffset = Vector2(0.87, -0.075)
    sendButton.OnClicked = function() sendCommand(); return true end

    local refreshButton = GUI.Button(
        GUI.RectTransform(Vector2(0.13, 0.055), panel.RectTransform, GUI.Anchor.BottomLeft),
        "Refresh", GUI.Alignment.Center, "GUIButtonSmall")
    refreshButton.RectTransform.RelativeOffset = Vector2(0.03, -0.075)
    refreshButton.OnClicked = function() refreshPlayerList(); return true end

    local closeButton = GUI.Button(
        GUI.RectTransform(Vector2(0.13, 0.055), panel.RectTransform, GUI.Anchor.BottomLeft),
        "Close", GUI.Alignment.Center, "GUIButtonSmall")
    closeButton.RectTransform.RelativeOffset = Vector2(0.17, -0.075)
    closeButton.OnClicked = function() RemoteConsoleUI.Close(); return true end
end

-- Console output relayed by the server.
Networking.Receive(NetIds.ConsoleOutput, function(message)
    local sessionId = Safe.Get(function() return message.ReadString() end)
    local name      = Safe.Get(function() return message.ReadString() end)
    local line      = Safe.Get(function() return message.ReadString() end)
    if sessionId == nil or line == nil then return end

    local entry = consoleFor(sessionId, name)
    table.insert(entry.lines, line)
    while #entry.lines > MAX_LOG_LINES do table.remove(entry.lines, 1) end

    if sessionId == selectedId and ui.root ~= nil and ui.root.Visible then
        renderLog()
    end
end)

function RemoteConsoleUI.Open()
    build()
    refreshPlayerList()
    renderLog()
    ui.isOpen       = true
    ui.root.Visible = true
end

function RemoteConsoleUI.Close()
    if selectedId ~= nil then attach(selectedId, false) end
    if ui.root ~= nil then ui.root.Visible = false end
    ui.isOpen = false
end

function RemoteConsoleUI.Toggle()
    if ui.isOpen then RemoteConsoleUI.Close() else RemoteConsoleUI.Open() end
end

function RemoteConsoleUI.IsOpen()
    return ui.isOpen
end

local function addToUpdateList()
    if ui.root == nil or ui.root.Visible ~= true then return end
    local added = Safe.Set(function() ui.root.AddToGUIUpdateList(false, 1000) end)
    if not added then Safe.Set(function() ui.root.AddToGUIUpdateList() end) end
end

Safe.PatchMethod("Barotrauma.GameSession", "AddToGUIUpdateList", nil,
    function() addToUpdateList() end, Hook.HookMethodType.After)

Safe.PatchMethod("Barotrauma.GameScreen", "AddToGUIUpdateList", nil,
    function() addToUpdateList() end, Hook.HookMethodType.After)

Safe.PatchMethod("Barotrauma.NetLobbyScreen", "AddToGUIUpdateList", nil,
    function() addToUpdateList() end, Hook.HookMethodType.After)

ClientState.AddChangeListener(function()
    if ui.root ~= nil then SettingsMenu.Refresh() end
end)

return RemoteConsoleUI
