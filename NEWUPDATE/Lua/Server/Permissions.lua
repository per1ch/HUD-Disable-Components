-- Lua/Server/Permissions.lua — SERVER
--
-- Two SEPARATE capabilities, deliberately not nested:
--
--   hudDisableComponents  may change the synced HUD policy
--   hudRemoteConsole      may run commands on other players' clients and
--                         read their console output
--
-- Granting the first never grants the second. Driving someone else's game
-- client is a far larger capability than toggling HUD elements, so it is
-- handed out separately and checked separately on every single message.
--
-- Both are ordinary Barotrauma console-command permissions, assigned per
-- client under Manage Permissions -> Console Commands. Registering the
-- anchor commands below is what makes them appear in that list.
--
-- SECURITY MODEL — read before changing anything here.
--
-- Authorization is enforced on every inbound message, never by hiding UI.
-- Every client downloads the whole mod, including the admin UI source, so
-- "they do not have the menu" is not a state that can be created or
-- verified. A non-privileged player may open any window in this mod; the
-- server simply refuses to act on what they send.
--
-- What this does NOT do: a client running patched Lua can ignore
-- client-side HUD restrictions and can lie in the console mirror. The code
-- runs on their machine. Server/Integrity.lua detects the realistic cases
-- (mod disabled, stopped responding, wrong version); it cannot stop a
-- determined spoofer. Anything that must be guaranteed has to be enforced
-- server-side, the way the chat mute in Server/Moderation.lua is.

HDC = HDC or {}

local Safe = HDC.Safe

local Permissions = {}
HDC.Permissions = Permissions

Permissions.POLICY_COMMAND  = "hudDisableComponents"
Permissions.CONSOLE_COMMAND = "hudRemoteConsole"

local function registerAnchor(commandName, description, checkFn)
    Safe.AddCommand(commandName, description, function(args, client)
        if client == nil then
            print("[HDC] Server console always has this permission.")
            return
        end
        print(string.format("[HDC] %s %s this permission.",
            Permissions.DescribeClient(client), checkFn(client) and "HAS" or "does NOT have"))
    end, nil, false)
end

function Permissions.DescribeClient(client)
    if client == nil then return "server console" end
    return tostring(Safe.Get(function() return client.Name end) or "unknown client")
end

local function isOwner(client)
    if Safe.Get(function() return client.IsOwner end) == true then return true end
    if Safe.Get(function() return client.IsServerOwner end) == true then return true end
    return Safe.Get(function()
        local ownerConnection = GameMain.Server ~= nil and GameMain.Server.OwnerConnection
        return ownerConnection ~= nil and client.Connection == ownerConnection
    end) == true
end

local function hasManageSettings(client)
    return Safe.Get(function()
        return client.HasPermission(ClientPermissions.ManageSettings)
    end) == true
end

local function hasCommandPermission(client, commandName)
    local wanted = string.lower(commandName)
    return Safe.Get(function()
        for command in client.PermittedConsoleCommands do
            local name = command.Names ~= nil and command.Names[0] or command.Name
            if name ~= nil and string.lower(tostring(name)) == wanted then
                return true
            end
        end
        return false
    end) == true
end

-- A nil client means no client information was available: either the
-- server console itself (legitimately unrestricted), or a LuaCs build
-- whose Game.AddCommand callback does not forward the caller. Both are
-- treated as allowed, which is safe because the game's own permission
-- system already decided who could invoke a console command at all.
--
-- Network messages always carry a real client, so the UI paths that
-- actually matter are genuinely gated.
function Permissions.CanEditPolicy(client)
    if client == nil then return true end
    if isOwner(client) then return true end
    if hasManageSettings(client) then return true end
    return hasCommandPermission(client, Permissions.POLICY_COMMAND)
end

-- Note this does NOT fall through to ManageSettings. Remote console access
-- is granted only by explicitly ticking hudRemoteConsole, or by owning the
-- server — so a player trusted to change HUD settings does not silently
-- gain the ability to drive other people's clients.
function Permissions.CanUseRemoteConsole(client)
    if client == nil then return true end
    if isOwner(client) then return true end
    return hasCommandPermission(client, Permissions.CONSOLE_COMMAND)
end

registerAnchor(Permissions.POLICY_COMMAND,
    "Grants the right to change [HUD] Disable Components settings. Assign via Manage Permissions -> Console Commands.",
    Permissions.CanEditPolicy)

registerAnchor(Permissions.CONSOLE_COMMAND,
    "Grants the right to run commands on other players' clients and read their console. Assign via Manage Permissions -> Console Commands.",
    Permissions.CanUseRemoteConsole)

return Permissions
