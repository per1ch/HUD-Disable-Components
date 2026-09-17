-- Lua/Server/Moderation.lua — SERVER
--
-- Spec item 16, per-player half: silence one named player's chat via a
-- command, independently of the global MuteChatGlobal toggle.
--
-- Enforcement happens here on the server — a muted player's messages are
-- dropped before they are ever broadcast, rather than asking clients to
-- politely not display them.

HDC = HDC or {}

local Safe        = HDC.Safe
local ServerState = HDC.ServerState
local Permissions = HDC.Permissions

local Moderation = {}
HDC.Moderation = Moderation

-- Keyed by SteamID/AccountId string so a reconnect keeps the mute.
local mutedAccounts = {}

local function accountKey(client)
    local key = Safe.Get(function() return tostring(client.SteamID) end)
    if key ~= nil and key ~= "" and key ~= "0" then return key end
    key = Safe.Get(function() return tostring(client.AccountId) end)
    if key ~= nil and key ~= "" then return key end
    return Safe.Get(function() return tostring(client.Name) end)
end

local function findClientByName(name)
    if name == nil or name == "" then return nil end
    local wanted = string.lower(tostring(name))
    local clients = Safe.Get(function() return Client.ClientList end)
    if clients == nil then return nil end

    local exact, partial = nil, nil
    for _, client in pairs(clients) do
        local clientName = Safe.Get(function() return tostring(client.Name) end)
        if clientName ~= nil then
            local lowered = string.lower(clientName)
            if lowered == wanted then
                exact = client
            elseif partial == nil and string.find(lowered, wanted, 1, true) ~= nil then
                partial = client
            end
        end
    end
    return exact or partial
end

function Moderation.IsMuted(client)
    if client == nil then return false end
    if ServerState.Get("MuteChatGlobal") then return true end
    local key = accountKey(client)
    return key ~= nil and mutedAccounts[key] == true
end

function Moderation.SetMuted(client, muted)
    local key = accountKey(client)
    if key == nil then return false end
    mutedAccounts[key] = muted and true or nil
    return true
end

-- Drops chat from muted senders. `chatMessage` returning true tells the
-- game the message was handled, which suppresses it.
Safe.AddHook("chatMessage", "HDC.Moderation.FilterChat", function(message, sender)
    if sender == nil then return end
    if Moderation.IsMuted(sender) then return true end
end)

local function requirePermission(client)
    if Permissions.CanEditPolicy(client) then return true end
    print("[HDC] You do not have permission to use this command.")
    return false
end

Safe.AddCommand("hdc_mute", "Mute one player's chat. Usage: hdc_mute <player name>",
    function(args, client)
        if not requirePermission(client) then return end

        local name = args ~= nil and args[1] or nil
        if name == nil then
            print("[HDC] Usage: hdc_mute <player name>")
            return
        end

        local target = findClientByName(name)
        if target == nil then
            print("[HDC] No connected player matching \"" .. tostring(name) .. "\".")
            return
        end

        Moderation.SetMuted(target, true)
        print("[HDC] Muted " .. tostring(Safe.Get(function() return target.Name end)) .. ".")
    end, nil, false)

Safe.AddCommand("hdc_unmute", "Un-mute one player's chat. Usage: hdc_unmute <player name>",
    function(args, client)
        if not requirePermission(client) then return end

        local name = args ~= nil and args[1] or nil
        if name == nil then
            print("[HDC] Usage: hdc_unmute <player name>")
            return
        end

        local target = findClientByName(name)
        if target == nil then
            print("[HDC] No connected player matching \"" .. tostring(name) .. "\".")
            return
        end

        Moderation.SetMuted(target, false)
        print("[HDC] Un-muted " .. tostring(Safe.Get(function() return target.Name end)) .. ".")
    end, nil, false)

Safe.AddCommand("hdc_mutelist", "List players currently muted by [HUD] Disable Components.",
    function()
        if ServerState.Get("MuteChatGlobal") then
            print("[HDC] Global chat mute is ON — every player is muted.")
        end
        local any = false
        for key in pairs(mutedAccounts) do
            print("[HDC] muted: " .. tostring(key))
            any = true
        end
        if not any then print("[HDC] No individually muted players.") end
    end, nil, false)

return Moderation
