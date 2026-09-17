-- Lua/Client/Features/ItemHighlights.lua — CLIENT
-- Spec item 7: hide the selection outline / highlight drawn on
-- interactable items.
--
-- Only the outline rendering is suppressed — interaction itself is
-- untouched, so items remain usable, they simply stop glowing.

HDC = HDC or {}

local Safe        = HDC.Safe
local ClientState = HDC.ClientState

local KEY = "HideItemHighlights"

local function enabled()
    return ClientState.Get(KEY)
end

-- The outline pass for a hovered/selected item.
Safe.PatchMethod("Barotrauma.Item", "DrawSelectionIndicator", nil, function(instance, ptable)
    if not enabled() then return end
    ptable.PreventExecution = true
end, Hook.HookMethodType.Before)

-- Vanilla's "highlight everything nearby" sweep.
Safe.PatchMethod("Barotrauma.Item", "UpdateHighlight", nil, function(instance, ptable)
    if not enabled() then return end
    ptable.PreventExecution = true
end, Hook.HookMethodType.Before)

-- Belt and braces: keep the per-item highlight strength at zero while the
-- toggle is on, in case a draw path bypasses the patches above.
Safe.AddHook("think", "HDC.ItemHighlights.ZeroOut", function()
    if not enabled() then return end
    local items = Safe.Get(function() return Item.ItemList end)
    if items == nil then return end
    for _, item in pairs(items) do
        Safe.Set(function() item.HighlightColor = nil end)
        Safe.Set(function() item.IsHighlighted  = false end)
    end
end)
