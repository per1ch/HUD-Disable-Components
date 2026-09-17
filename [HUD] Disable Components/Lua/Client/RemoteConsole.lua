-- Lua/Client/RemoteConsole.lua — CLIENT
--
-- Two jobs on this side:
--   1. Execute commands that arrive FROM THE SERVER, and report the result.
--   2. Mirror local console output back to the server so a watching admin
--      sees errors and state as they happen.
--
-- Commands are only ever taken from the network handler below. Nothing
-- local calls the executor, so a player cannot self-issue a remote command
-- to fake activity in an admin's window.
--
-- Honest limitation: this is an audit trail, not tamper-proofing. The
-- client runs on the player's machine and a patched build could suppress
-- or fabricate these lines. It catches accidents and casual interference;
-- it does not defeat a determined spoofer. Anything that must be
-- guaranteed belongs on the server.

HDC = HDC or {}

local Safe   = HDC.Safe
local NetIds = HDC.NetIds

local RemoteConsole = {}
HDC.RemoteConsole = RemoteConsole

-- Guards against a feedback loop: our own mirrored lines must not be
-- re-captured as new console output and sent again.
local mirroring = false

local MAX_LINE_LENGTH = 400

local function sendLine(text)
    if text == nil then return end
    local line = tostring(text)
    if line == "" then return end
    if #line > MAX_LINE_LENGTH then
        line = string.sub(line, 1, MAX_LINE_LENGTH) .. " [...]"
    end

    mirroring = true
    Safe.Set(function()
        local message = Networking.Start(NetIds.ConsoleOutput)
        message.WriteString(line)
        Networking.Send(message)
    end)
    mirroring = false
end

RemoteConsole.SendLine = sendLine

-- Command pushed by the server. Executed, with both failures and the
-- absence of failure reported back.
Networking.Receive(NetIds.RemoteExec, function(message)
    local commandLine = Safe.Get(function() return message.ReadString() end)
    if commandLine == nil or commandLine == "" then return end

    local ok, err = pcall(function()
        Game.ExecuteCommand(commandLine)
    end)

    if ok then
        sendLine("[ok] " .. commandLine)
    else
        sendLine("[ERROR] " .. commandLine .. " -- " .. tostring(err))
    end
end)

-- Mirror anything written to this client's console.
local function captureConsoleLine(instance, ptable)
    if mirroring then return end
    local text = nil
    if ptable ~= nil then
        text = Safe.Get(function() return tostring(ptable["msg"]) end)
            or Safe.Get(function() return tostring(ptable["text"]) end)
            or Safe.Get(function() return tostring(ptable[1]) end)
    end
    if text == nil or text == "nil" then return end
    sendLine(text)
end

Safe.AddHook("error", "HDC.RemoteConsole.MirrorErrors", function(err)
    sendLine("[LUA ERROR] " .. tostring(err))
end)


return RemoteConsole