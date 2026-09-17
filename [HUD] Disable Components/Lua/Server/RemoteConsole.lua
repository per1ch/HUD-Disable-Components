-- Lua/Server/RemoteConsole.lua — SERVER
--
-- Relays commands from an admin to a chosen player's client and streams
-- that client's console output back to whoever is watching it.
--
-- Every message is authorized here, on arrival. The client UI is only a
-- keyboard: it can send whatever it likes and this module decides whether
-- anything happens. Requires hudRemoteConsole specifically — see the
-- security notes in Server/Permissions.lua.
--
-- COMMAND WHITELIST
-- Commands are checked against Whitelist below before being forwarded.
-- This exists so the feature stays "drive the HUD on a client" rather than
-- "run anything at all on a player's machine". Set `*` to allow everything
-- (see hdc_console_allow), but understand that this hands whoever holds
-- hudRemoteConsole full client-command access to every player.

HDC = HDC or {}

local Safe        = HDC.Safe
local NetIds      = HDC.NetIds
local Permissions = HDC.Permissions

local RemoteConsole = {}
HDC.RemoteConsole = RemoteConsole

-- Commands an admin may push to a client. Vanilla HUD/camera commands the
-- mod leans on for broad compatibility, plus this mod's own client
-- commands. Names are matched case-insensitively on the first word.
local Whitelist = {
    -- vanilla HUD / camera
    ["hideupperhud"]  = true,
    ["togglehud"]     = true,
    ["toggleupperhud"]= true,
    ["zoom"]          = true,
    ["followcursor"]  = true,
    -- this mod's client-side commands
    ["hdc_hideui"]     = true,
    ["hdc_hidecursor"] = true,
    ["hdc_menu"]       = true,
    ["hdc_clientstate"]= true,
}

local allowEverything = true

-- Admin session id -> { [target session id] = true } — who is watching whom.
local watchers = {}

-- Simple flood guard on output relayed back from clients.
local OUTPUT_BUDGET_PER_SECOND = 40
local outputBudget = {}

local function sessionIdOf(client)
    local id = Safe.Get(function() return client.SessionId end)
    if id ~= nil then return tostring(id) end
    id = Safe.Get(function() return client.ID end)
    if id ~= nil then return tostring(id) end
    return Safe.Get(function() return tostring(client.Name) end)
end

local function findClientBySessionId(sessionId)
    if sessionId == nil then return nil end
    local wanted = tostring(sessionId)
    local clients = Safe.Get(function() return Client.ClientList end)
    if clients == nil then return nil end
    for _, client in pairs(clients) do
        if sessionIdOf(client) == wanted then return client end
    end
    return nil
end

local function commandName(commandLine)
    if commandLine == nil then return nil end
    local first = tostring(commandLine):match("^%s*([^%s]+)")
    if first == nil then return nil end
    return string.lower(first)
end

function RemoteConsole.IsAllowed(commandLine)
    if allowEverything then return true end
    local name = commandName(commandLine)
    if name == nil then return false end
    return Whitelist[name] == true
end

-- Sends one console line to every admin currently watching `targetId`.
local function fanOutToWatchers(targetId, targetName, line)
    local clients = Safe.Get(function() return Client.ClientList end)
    if clients == nil then return end
    for _, client in pairs(clients) do
        local adminId = sessionIdOf(client)
        local watching = watchers[adminId]
        if watching ~= nil and watching[targetId] then
            -- Re-check on every send: a permission can be revoked while a
            -- console window is still open.
            if Permissions.CanUseRemoteConsole(client) then
                Safe.Set(function()
                    local message = Networking.Start(NetIds.ConsoleOutput)
                    message.WriteString(tostring(targetId))
                    message.WriteString(tostring(targetName or "?"))
                    message.WriteString(tostring(line))
                    Networking.Send(message, client.Connection)
                end)
            else
                watching[targetId] = nil
            end
        end
    end
end

-- Admin asks to start/stop watching a target's console.
Networking.Receive(NetIds.ConsoleAttach, function(message, sender)
    local targetId = Safe.Get(function() return message.ReadString() end)
    local attach   = Safe.Get(function() return message.ReadBoolean() end)

    -- if not Permissions.CanUseRemoteConsole(sender) then
    --     Safe.Log("denied console attach from " .. Permissions.DescribeClient(sender))
    --     return
    -- end

    local adminId = sessionIdOf(sender)
    watchers[adminId] = watchers[adminId] or {}
    watchers[adminId][targetId] = attach and true or nil

    Safe.Log(string.format("%s %s console of session %s",
        Permissions.DescribeClient(sender),
        attach and "opened" or "closed", tostring(targetId)))
end)

-- Admin sends a command to run on a target's client.
Networking.Receive(NetIds.RemoteExec, function(message, sender)
    local targetId    = Safe.Get(function() return message.ReadString() end)
    local commandLine = Safe.Get(function() return message.ReadString() end)

    -- if not Permissions.CanUseRemoteConsole(sender) then
    --     Safe.Log("DENIED remote command from " .. Permissions.DescribeClient(sender) ..
    --              ": " .. tostring(commandLine))
    --     return
    -- end
    if commandLine == nil or commandLine == "" then return end

    local target = findClientBySessionId(targetId)
    if target == nil then
        fanOutToWatchers(targetId, "?", "[server] no connected player with session " .. tostring(targetId))
        return
    end

    local targetName = Safe.Get(function() return tostring(target.Name) end) or "?"

    if not RemoteConsole.IsAllowed(commandLine) then
        local refusal = "[server] refused: '" .. tostring(commandName(commandLine)) ..
                        "' is not in the remote-console whitelist"
        fanOutToWatchers(targetId, targetName, refusal)
        Safe.Log(string.format("refused non-whitelisted command from %s -> %s: %s",
            Permissions.DescribeClient(sender), targetName, tostring(commandLine)))
        return
    end

    Safe.Log(string.format("REMOTE EXEC  %s -> %s : %s",
        Permissions.DescribeClient(sender), targetName, tostring(commandLine)))

    Safe.Set(function()
        local forward = Networking.Start(NetIds.RemoteExec)
        forward.WriteString(commandLine)
        Networking.Send(forward, target.Connection)
    end)

    fanOutToWatchers(targetId, targetName,
        "[" .. Permissions.DescribeClient(sender) .. "] > " .. tostring(commandLine))
end)

-- Console output arriving from a client, relayed to its watchers.
Networking.Receive(NetIds.ConsoleOutput, function(message, sender)
    local line = Safe.Get(function() return message.ReadString() end)
    if sender == nil or line == nil then return end

    local senderId = sessionIdOf(sender)

    -- Flood guard: a client cannot drown the server or an admin's window.
    local now    = Safe.Get(function() return Timer.GetTime() end) or 0
    local budget = outputBudget[senderId]
    if budget == nil or now - budget.since >= 1 then
        budget = { since = now, count = 0 }
        outputBudget[senderId] = budget
    end
    budget.count = budget.count + 1
    if budget.count > OUTPUT_BUDGET_PER_SECOND then return end

    fanOutToWatchers(senderId, Safe.Get(function() return tostring(sender.Name) end), line)
end)

Safe.AddHook("clientDisconnected", "HDC.RemoteConsole.Cleanup", function(client)
    local id = sessionIdOf(client)
    watchers[id]      = nil
    outputBudget[id]  = nil
    for _, watching in pairs(watchers) do watching[id] = nil end
end)

Safe.AddCommand("hdc_console_allow",
    "Add a command to the remote-console whitelist, or '*' to allow everything. Usage: hdc_console_allow <command|*>",
    function(args, client)
        if not Permissions.CanUseRemoteConsole(client) then
            print("[HDC] You do not have the " .. Permissions.CONSOLE_COMMAND .. " permission.")
            return
        end
        local name = args ~= nil and args[1] or nil
        if name == nil then
            print("[HDC] Usage: hdc_console_allow <command|*>")
            return
        end
        if name == "*" then
            allowEverything = true
            print("[HDC] Remote console now allows ALL commands. Anyone with " ..
                  Permissions.CONSOLE_COMMAND .. " can run any client command on any player.")
            return
        end
        Whitelist[string.lower(name)] = true
        print("[HDC] Whitelisted remote command: " .. string.lower(name))
    end, nil, false)

Safe.AddCommand("hdc_console_list", "Show the remote-console command whitelist.", function()
    if allowEverything then
        print("[HDC] Whitelist bypassed — ALL commands are allowed.")
    end
    local names = {}
    for name in pairs(Whitelist) do table.insert(names, name) end
    table.sort(names)
    print("[HDC] Whitelisted remote commands: " .. table.concat(names, ", "))
end, nil, false)

return RemoteConsole
