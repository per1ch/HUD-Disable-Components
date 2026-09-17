-- Lua/Server/AliveCommand.lua — SERVER
--
-- Spec item 10, second half: keep an !alive command for checking who is
-- still alive once the upper HUD crew panel is hidden.
--
-- Answered from the game's real, untouched character list. This module is
-- the reason the crew panel is hidden by rendering only (see
-- Client/Features/UpperHud.lua) — because the list is intact, !alive can
-- report the truth without the mod having to keep a shadow copy.
--
-- Restricted to spectators, dead players, and admins, so a living player
-- cannot use it to scout the round.

HDC = HDC or {}

local Safe        = HDC.Safe
local Permissions = HDC.Permissions

local AliveCommand = {}
HDC.AliveCommand = AliveCommand

local TRIGGERS = { ["!alive"] = true, ["/alive"] = true }

local function isSpectatorOrDead(client)
    local character = Safe.Get(function() return client.Character end)
    if character == nil then return true end -- spectating / not spawned
    local isDead = Safe.Get(function() return character.IsDead end)
    return isDead == true
end

local function mayQuery(client)
    if client == nil then return true end
    if Permissions.CanEditPolicy(client) then return true end
    local hasConsole = Safe.Get(function()
        return client.HasPermission(ClientPermissions.ConsoleCommands)
    end) == true
    if hasConsole then return true end
    return isSpectatorOrDead(client)
end

-- Reads the live character list. Team-agnostic, and reports bots too,
-- matching how the hidden crew panel would have behaved.
local function buildAliveReport()
    local characters = Safe.Get(function() return Character.CharacterList end)
    if characters == nil then return "[HDC] Crew status is unavailable." end

    local alive, dead = {}, {}
    for _, character in pairs(characters) do
        local isPlayerCrew = Safe.Get(function()
            return character.Info ~= nil and character.IsHuman
        end) == true
        if isPlayerCrew then
            local name = Safe.Get(function() return tostring(character.Name) end) or "?"
            local isBot = Safe.Get(function() return character.IsBot end) == true
            local label = name .. (isBot and " (bot)" or "")
            if Safe.Get(function() return character.IsDead end) == true then
                table.insert(dead, label)
            else
                table.insert(alive, label)
            end
        end
    end

    local lines = {}
    table.insert(lines, string.format("Alive (%d): %s", #alive,
        #alive > 0 and table.concat(alive, ", ") or "nobody"))
    table.insert(lines, string.format("Dead (%d): %s", #dead,
        #dead > 0 and table.concat(dead, ", ") or "nobody"))
    return table.concat(lines, "\n")
end

local function sendTo(client, text)
    local sent = Safe.Set(function()
        local message = ChatMessage.Create("", text, ChatMessageType.Server, nil, nil)
        Game.SendDirectChatMessage(message, client)
    end)
    if not sent then
        Safe.Set(function()
            Game.SendDirectChatMessage("", text, nil, ChatMessageType.Server, client)
        end)
    end
end

-- The chatMessage hook hands over a ChatMessage object in some LuaCs
-- versions and a plain string in others, so read both shapes.
local function messageText(message)
    local text = Safe.Get(function() return tostring(message.Text) end)
    if text ~= nil and text ~= "" then return text end
    return Safe.Get(function() return tostring(message) end)
end

Safe.AddHook("chatMessage", "HDC.AliveCommand.Handle", function(message, sender)
    if sender == nil or message == nil then return end
    local text = messageText(message)
    if text == nil then return end
    text = string.lower(text):match("^%s*(.-)%s*$")
    if not TRIGGERS[text] then return end

    if not mayQuery(sender) then
        sendTo(sender, "[HDC] Only spectators, dead players and admins can use !alive.")
        return true
    end

    sendTo(sender, buildAliveReport())
    return true -- consume the command so it is not broadcast as chat
end)

Safe.AddCommand("hdc_alive", "Print who is currently alive (server console).", function()
    print(buildAliveReport())
end, nil, false)

return AliveCommand
