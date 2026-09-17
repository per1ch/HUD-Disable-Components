-- Lua/Client/Features/QuickMarkIcons.lua — CLIENT
-- Spec item 15: hide the quick-mark (report) icons shown next to the chat
-- box. Fire / breach / intruders buttons, each with an order-prefab sprite.
--
-- The chat messages themselves are unaffected — only the clickable icon
-- buttons are hidden. Other players' reports still arrive in chat.
--
-- CrewManager.UpdateReports writes ReportButtonFrame.Visible every frame,
-- so a think hook loses the race. Patch UpdateReports After instead, once
-- the game has made its own decision, and force the frame hidden.
--
-- ReportButtonFrame is a public property on CrewManager; no
-- MakeFieldAccessible needed. Nothing on the server side to enforce — the
-- reports are cosmetic UI, and suppressing the buttons cannot be bypassed
-- to gain information the way the HUD-hiding features can.

HDC = HDC or {}

local Safe        = HDC.Safe
local ClientState = HDC.ClientState

local KEY = "HideQuickMarkIcons"

Safe.PatchMethod("Barotrauma.CrewManager", "UpdateReports", nil, function(instance, ptable)
    if ClientState.Get(KEY) ~= true then return end
    if instance == nil then return end
    Safe.Set(function()
        local frame = instance.ReportButtonFrame
        if frame ~= nil then
            frame.Visible = false
        end
    end)
end, Hook.HookMethodType.After)
