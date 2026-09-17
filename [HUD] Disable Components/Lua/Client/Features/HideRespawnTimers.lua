-- Lua/Client/Features/RespawnTimers.lua — CLIENT
-- Hides the respawn countdown, the shuttle-leaving countdown, and the
-- "ending the round in ..." text. Only the text is blanked; the death
-- choice frame and its buttons are left intact, so the player can still
-- pick "wait" vs "respawn" as usual.

HDC = HDC or {}
local Safe        = HDC.Safe
local ClientState = HDC.ClientState

local KEY = "HideRespawnTimers"

local function enabled() return ClientState.Get(KEY) == true end

-- Both are private fields on GameSession; without these two lines
-- instance.respawnInfoText is nil from Lua and the blanking is a no-op.
Safe.MakeFieldAccessible("Barotrauma.GameSession", "respawnInfoText")
Safe.MakeFieldAccessible("Barotrauma.GameSession", "deathChoiceInfoFrame")

-- SetRespawnInfo is the single funnel: GameClient.Draw builds the text
-- (respawn timer, shuttle timer, or the ending-round timer) and hands it
-- to this method, which writes it into respawnInfoText every frame.
-- An After hook therefore wins the race on the frame the text is set.
Safe.PatchMethod("Barotrauma.GameSession", "SetRespawnInfo", nil, function(instance, ptable)
    if not enabled() then return end
    if instance == nil then return end
    Safe.Set(function()
        local block = instance.respawnInfoText
        if block ~= nil then
            block.Text = ""
        end
    end)
end, Hook.HookMethodType.After)