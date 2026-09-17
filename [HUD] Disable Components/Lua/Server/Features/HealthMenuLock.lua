-- Lua/Server/Features/HealthMenuLock.lua — SERVER
--
-- Hard enforcement for LockHealthMenu. Client/Features/HealthMenuLock.lua
-- covers the same key by setting Character.DisableHealthWindow, which is
-- a client-local field (see that file's own header) — it stops an honest
-- client from opening the window, but a modified client can simply not
-- set it and self-heal anyway. This is the part that cannot be bypassed:
-- the treatment itself never applies.
--
-- Hooks the LuaCs "itemApplyTreatment" event, which fires for every item
-- used as a treatment (bandages, medkits, etc.) with the item, the
-- character applying it, the character receiving it, and the limb.
-- Returning true cancels the treatment. Self-treatment is simply
-- user == target; nothing here touches treatment given to anyone else.

HDC = HDC or {}

local Safe        = HDC.Safe
local ServerState = HDC.ServerState

local KEY = "LockHealthMenu"

local function enabled() return ServerState.Get(KEY) == true end

Safe.AddHook("itemApplyTreatment", "HDC.HealthMenuLock.BlockSelfTreat",
    function(item, user, target, limb)
        if not enabled() then return end
        if user == nil or target == nil or user ~= target then return end

        Safe.SendDirectMessage(Safe.FindClientByCharacter(user),
            "[HDC] Self-treatment is disabled on this server.")
        return true
    end)
