-- Lua/Client/Features/CrewListEntries.lua — CLIENT
-- Hides the crew roster panel in the TAB menu from living players only —
-- spectators and dead players still see it, same rationale as the
-- respawn/round-end timers (Server/Features/DisableRespawnTimerPacket.lua):
-- it's metagame information a living player shouldn't get from a menu
-- when they'd otherwise have to actually find their crewmates in the
-- world to know their status.
--
-- Rendering suppression only (crewArea.Visible = false), matching the
-- Design note in Config.txt: never prevent entries from being added to
-- the real crew list (CrewManager.AddCharacterToCrewList) — that breaks
-- bot commands, player selection in the tab menu, and makes the
-- round-end screen report a team wipe after a successful mission. The
-- list stays intact; only its rendering is turned off, and only for the
-- viewer this is meant to restrict.

HDC = HDC or {}

local Safe        = HDC.Safe
local ClientState = HDC.ClientState

local KEY = "CrewListEntries"

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

Safe.PatchMethod("Barotrauma.CrewManager", "UpdateProjectSpecific", nil, function(instance, ptable)
    if not enabled() then return end
    if instance == nil then return end
    Safe.Set(function()
        local field = instance:GetType():GetField("crewArea",
            CS.System.Reflection.BindingFlags.NonPublic + CS.System.Reflection.BindingFlags.Instance)
        if field == nil then return end
        local area = field:GetValue(instance)
        if area ~= nil then area.Visible = false end
    end)
end, Hook.HookMethodType.After)
