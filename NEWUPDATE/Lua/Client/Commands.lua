-- Lua/Client/Commands.lua — CLIENT
--
-- Client-side console commands that are not tied to a single feature.
-- The per-feature self-only toggles register their own commands in
-- Client/FullUIToggle.lua (hdc_hideui) and Client/CursorToggle.lua
-- (hdc_hidecursor).

HDC = HDC or {}

local Safe         = HDC.Safe
local ClientState  = HDC.ClientState
local SettingsMenu = HDC.SettingsMenu

Safe.AddCommand("hdc_menu", "Open or close the [HUD] Disable Components settings list.", function()
    SettingsMenu.Toggle()
end, nil, false)

Safe.AddCommand("hdc_clientstate", "Print the HUD policy this client is currently applying.", function()
    print("[HDC] Current client policy:\n" .. ClientState.Describe())
end, nil, false)

-- Opening this is harmless without the hudRemoteConsole permission: the
-- server refuses every message it sends. See Server/Permissions.lua.
Safe.AddCommand("hdc_console", "Open the remote console (requires the hudRemoteConsole permission).", function()
    if HDC.RemoteConsoleUI == nil then
        print("[HDC] Remote console UI is not loaded.")
        return
    end
    HDC.RemoteConsoleUI.Toggle()
end, nil, false)
