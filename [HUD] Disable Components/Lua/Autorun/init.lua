-- Lua/Autorun/init.lua — entry point for [HUD] Disable Components
--
-- Load order matters and is explicit here rather than left to the
-- filesystem: Core and Shared must exist before anything reads them, the
-- state modules before the sync layer, and the UI before the feature
-- modules that reference it.
--
-- Everything hangs off one global table, HDC, so the mod occupies a
-- single name in the shared Lua environment.

HDC = HDC or {}

if HDC._initialized then return end
HDC._initialized = true

-- LuaCs passes the mod's root directory as the vararg to an autorun file.
HDC.Path    = ...
HDC.Version = "1.0.0"

local function load(relativePath)
    local ok, err = pcall(function()
        dofile(HDC.Path .. "/Lua/" .. relativePath)
    end)
    if not ok then
        print("[HDC] failed to load " .. relativePath .. " -- " .. tostring(err))
    end
    return ok
end

-- Shared foundation ---------------------------------------------------
load("Core/Safe.lua")
load("Shared/NetIds.lua")
load("Shared/FeatureRegistry.lua")

if SERVER then
    -- Authoritative state, permissions, then everything that depends on them
    load("Server/ServerState.lua")
    load("Server/Permissions.lua")
    load("Server/Sync.lua")
    load("Server/ServerPresets.lua")
    load("Server/Moderation.lua")
    load("Server/AliveCommand.lua")
    load("Server/RemoteConsole.lua")
    load("Server/Integrity.lua")
    load("Server/GiveInBlock.lua")
    load("Server/Features/DisableRespawnTimerPacket.lua")
    load("Server/Features/ChatMuteGlobal.lua")
    load("Server/Features/HealthMenuLock.lua")
    load("Server/Features/CrewManager.lua")


    HDC.Safe.Log("server module loaded (v" .. HDC.Version .. ")")
    return
end

if CLIENT then
    -- State and networking first: the UI and every feature read from them
    load("Client/ClientState.lua")
    load("Client/Net.lua")

    -- Remote console before the UI that opens it
    load("Client/RemoteConsole.lua")

    -- UI before features, because the self-only toggles reference the menu
    load("Client/UI/SettingsMenu.lua")
    load("Client/UI/RemoteConsoleUI.lua")
    load("Client/UI/PauseMenuButton.lua")

    -- Self-only commands (spec items 13 and 14)
    -- Synced features, in spec order
    load("Client/Features/HealthBars.lua")       --  1
    load("Client/Features/PlayerNames.lua")      --  2
    load("Client/Features/SkillXpPopups.lua")    --  3
    load("Client/Features/ChatBubbles.lua")      --  4
    load("Client/Features/VoiceBubbles.lua")     --  5
    load("Client/Features/PrivilegeIcon.lua")    --  6
    load("Client/Features/ItemHighlights.lua")   --  7
    load("Client/Features/HealthMenuLock.lua")   --  8
    load("Client/Features/AltHighlightLock.lua") --  9
    -- load("Client/Features/UpperHud.lua")         -- 10
    load("Client/Features/GiveInButton.lua")     -- 11
    load("Client/Features/ChatNameLink.lua")     -- 12
    load("Client/Features/QuickMarkIcons.lua")   -- 15
    load("Client/Features/ChatMuteGlobal.lua")   -- 16 (client-side chatbox half)
    load("Client/Features/Camera.lua")           -- camera zoom / follow-cursor
    load("Client/Features/HideCharacterOrders.lua")
    load("Client/Features/CrewManager.lua")
    load("Client/Features/HideCursor.lua")
    load("Client/Features/CrewListEntries.lua")
    load("Client/Features/HideRespawnTimers.lua")
    
    HDC.Safe.Log("client module loaded (v" .. HDC.Version .. ")")
end
