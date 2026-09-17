-- Lua/Client/Features/PrivilegeIcon.lua — CLIENT
-- Spec item 6: remove the host/permission icon shown next to names in the
-- tab player list.
--
-- The icon is removed at its source rather than by hiding GUI elements,
-- and the client list itself is never touched. Mutating the real list is
-- what breaks bot commands and admin actions in other mods that attempt
-- this; here the row and the client stay entirely intact and only the
-- sprite the row was going to draw goes missing.

HDC = HDC or {}

local Safe        = HDC.Safe
local ClientState = HDC.ClientState

local KEY = "HidePrivilegeIcon"

local function enabled()
    return ClientState.Get(KEY)
end

-- TabMenu builds each player row through CreateNameWithPermissionIcon,
-- which takes its sprite from GetPermissionIcon, and TabMenu.Update pushes
-- that same call's result back into every existing row each tick via
-- TryPermissionIconRefresh. Suppressing the one method therefore covers the
-- initial build, the per-tick refresh, and rows that already existed when
-- the setting was switched on — with no GUI tree to walk.
--
-- Returning no icon is a state the game already produces on its own:
-- GetPermissionIcon returns null for any client without permissions, and
-- the GUIImage that receives it draws nothing when its sprite is null.
--
-- The previous approach walked the whole canvas every frame looking for
-- images whose style name contained "permission", "owner", "host" or
-- "admin". Nothing in the row carries such a style — the icon is an
-- unstyled GUIImage constructed from a sprite — so the search matched
-- nothing while still costing a full tree walk per frame.
Safe.PatchMethod("Barotrauma.TabMenu", "GetPermissionIcon", nil, function(instance, ptable)
    if not enabled() then return end
    ptable.PreventExecution = true
end, Hook.HookMethodType.Before)
