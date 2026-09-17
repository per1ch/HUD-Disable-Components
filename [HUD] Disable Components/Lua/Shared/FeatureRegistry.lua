-- Lua/Shared/FeatureRegistry.lua — SHARED (loaded in both SERVER and CLIENT contexts)
--
-- Single source of truth for every setting that appears in the settings
-- menu and is synced server -> client. Both Server/ServerState.lua and
-- Client/UI/SettingsMenu.lua build themselves from this list, so adding an
-- entry here is the only edit needed to add a setting.
--
-- Entry shape:
--   key    unique identifier, also the JSON field name on the wire
--   label  menu row title
--   desc   menu row subtitle / tooltip
--   type   "bool" | "float"
--   min    float only: lower bound (clamped on both sides of the wire)
--   max    float only: upper bound
--   step   float only: menu increment
--
-- Every setting defaults to the value that changes nothing, so installing
-- the mod is a no-op until an admin turns something on. That is why the
-- camera entries are phrased as locks and disables rather than as the
-- underlying values.
--
-- Not in this list, deliberately:
--   items 13/14  self-only view preferences (Client/FullUIToggle.lua,
--                Client/CursorToggle.lua) — never leave the local machine
--   per-player mute  a targeted moderation action, not broadcast policy
--                (Server/Moderation.lua)
--   remote console  an admin capability, not a policy value
--                (Server/RemoteConsole.lua)

HDC = HDC or {}

HDC.FeatureRegistry = {
    { key = "CrewManager",        type = "bool", label = "CrewManager",                     desc = "Disables CrewManager execution." },
    { key = "HideRespawnTimers",  type = "bool", label = "Hide respawn timers",             desc = "Hides the respawn countdown and shuttle-leaving timer, on the server side."},
    { key = "DisableRespawnTimerPacket",  type = "bool", label = "DisableRespawnTimerPacket",             desc = "Hides the respawn countdown and shuttle-leaving timer, on the server side."},

    { key = "HideHealthBars",     type = "bool", label = "Health bars",                     desc = "Hides HP bars floating above characters." },
    { key = "HidePlayerNames",    type = "bool", label = "Player names",                    desc = "Hides names above characters, in the health scanner readout, and in the health menu." },
    { key = "HideSkillXpPopups",  type = "bool", label = "Skill / XP popups",               desc = "Hides the floating skill-up and experience-gain notices." },
    { key = "HideChatBubbles",    type = "bool", label = "Chat bubbles",                    desc = "Hides the speech bubble shown above a character typing in chat." },
    { key = "HideVoiceBubbles",   type = "bool", label = "Voice bubbles",                   desc = "Hides the microphone/voice-chat bubble shown above other characters." },
    { key = "HidePrivilegeIcon",  type = "bool", label = "Privilege / host icon",           desc = "Removes the host/permission icon next to names in the player list." },
    { key = "HideItemHighlights", type = "bool", label = "Item highlights",                 desc = "Hides the selection outline drawn on interactable items." },
    { key = "LockHealthMenu",     type = "bool", label = "Own health menu",                 desc = "Stops a player opening their own health menu. Other players' health menus still open normally, so medics keep working." },
    { key = "LockAltOverlay",     type = "bool", label = "Alt highlight overlay",           desc = "Disables the name/tooltip highlight overlay shown while holding Alt." },
    { key = "HideUpperHud",       type = "bool", label = "Upper HUD & timers",              desc = "Hides the crew status panel and the respawn/round-end timers (use !alive to check crew status)." },
    { key = "DisableGiveIn",      type = "bool", label = "\"Give In\" button",              desc = "Makes the Give In (suicide) button non-functional." },
    { key = "HideChatNameLink",   type = "bool", label = "Chat name links",                 desc = "Removes the clickable player-profile link on chat names." },
    { key = "HideQuickMarkIcons", type = "bool", label = "Quick-mark icons",                desc = "Hides fire/breach/etc. icon markers next to chat, leaving the messages themselves visible." },
    { key = "ChatMuteGlobal",     type = "bool", label = "Chat (all players)",              desc = "Blocks chat for every living player. Spectators, dead players, and command messages are exempt." },
    { key = "HideCursor",         type = "bool", label = "Hide Cursor",                     desc = "Hide cursor for players who control a character and not in the Escape menu." },
    
    -- { key = "CrewListEntries",    type = "bool", label = "Hide Crew List",                  desc = "Hide living players from TAB" },
    -- { key = "CrewList",           type = "bool", label = "CrewList",                        desc = "Hide living players from TAB" },

    -- Camera controls
    { key = "LockCameraZoom",      type = "bool",  label = "Lock camera zoom",       desc = "Forces every player's camera to the zoom level set below." },
    { key = "CameraZoomLevel",     type = "float", label = "Camera zoom level",      desc = "Zoom applied while the lock above is on. 1.0 is the normal view.",
      default = 1.0, min = 0.3, max = 3.0, step = 0.05 },
    { key = "DisableCameraFollow", type = "bool",  label = "Camera follows cursor",  desc = "Turns off the camera drifting toward the mouse cursor." },
}

-- Stable UI ordering. The wire format is JSON and therefore order-free, so
-- this exists purely so the menu renders consistently.
HDC.FeatureKeyOrder = {}
HDC.FeatureByKey    = {}
HDC.FeatureDefaults = {}

for _, entry in ipairs(HDC.FeatureRegistry) do
    table.insert(HDC.FeatureKeyOrder, entry.key)
    HDC.FeatureByKey[entry.key] = entry
    if entry.type == "float" then
        HDC.FeatureDefaults[entry.key] = entry.default or 0
    else
        HDC.FeatureDefaults[entry.key] = entry.default == true
    end
end

-- Coerces an arbitrary incoming value to the entry's declared type and
-- range. Returns nil for unknown keys, so a malformed or hostile payload
-- can never inject state the registry does not describe.
function HDC.CoerceValue(key, value)
    local entry = HDC.FeatureByKey[key]
    if entry == nil then return nil end

    if entry.type == "float" then
        local number = tonumber(value)
        if number == nil then return nil end
        local minimum = entry.min or 0
        local maximum = entry.max or 1
        if number < minimum then number = minimum end
        if number > maximum then number = maximum end
        return number
    end

    return value == true
end

return HDC.FeatureRegistry
