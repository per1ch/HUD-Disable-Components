-- Lua/Server/Moderation.lua — SERVER
--
-- Spec item 16, per-player half: silence one named player's chat via a
-- command, independently of the global ChatMuteGlobal toggle.
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

-- A leading punctuation character (!, /, etc.) marks a command rather than
-- a chat line, e.g. "!alive" — the global mute must not eat those, or
-- spectators/admins lose commands along with their chat.
local function looksLikeCommand(text)
    return text ~= nil and text:match("^%s*%p") ~= nil
end

-- An individual hdc_mute is a targeted moderator action and always
-- applies. The global toggle is a blunt "lock the round chat" switch, so
-- it exempts spectators/dead players (who aren't part of the round being
-- locked down) and command text.
function Moderation.IsMuted(client, text)
    if client == nil then return false end

    local key = accountKey(client)
    if key ~= nil and mutedAccounts[key] == true then return true end

    if not ServerState.Get("ChatMuteGlobal") then return false end
    if looksLikeCommand(text) then return false end
    if isSpectatorOrDead(client) then return false end
    return true
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
    if Moderation.IsMuted(sender, messageText(message)) then return true end
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
        if ServerState.Get("ChatMuteGlobal") then
            print("[HDC] Global chat mute is ON — every living player is muted (spectators, dead players, and commands are exempt).")
        end
        local any = false
        for key in pairs(mutedAccounts) do
            print("[HDC] muted: " .. tostring(key))
            any = true
        end
        if not any then print("[HDC] No individually muted players.") end
    end, nil, false)

return Moderation
