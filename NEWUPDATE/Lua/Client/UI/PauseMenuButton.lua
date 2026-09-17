-- Lua/Client/UI/PauseMenuButton.lua — CLIENT
--
-- Adds the "[HUD] Disable Components" entry to the pause menu so the
-- settings list can be opened without typing a console command.
--
-- The button container is located by shape (a layout group holding
-- several text-bearing children) rather than by a hard-coded child index,
-- so a vanilla pause-menu layout change does not silently put the button
-- in the wrong place.

HDC = HDC or {}

local Safe         = HDC.Safe
local SettingsMenu = HDC.SettingsMenu

local PauseMenuButton = {}
HDC.PauseMenuButton = PauseMenuButton

local state = {
    pauseMenu = nil,
    button    = nil,
    wasOpen   = false,
}

local function childrenOf(component)
    local result = {}
    if component == nil then return result end
    local children = Safe.Get(function() return component.Children end)
    if children == nil then return result end
    pcall(function()
        for child in children do table.insert(result, child) end
    end)
    return result
end

local function isLayoutGroup(component)
    return Safe.Get(function()
        local _ = component.AbsoluteSpacing
        return true
    end) == true
end

-- Picks the layout group that holds the most text-bearing children — in
-- practice the pause menu's button column.
local function findButtonContainer(root)
    local best, bestScore = nil, -1
    Safe.WalkComponents(root, function(node)
        if not isLayoutGroup(node) then return end
        local children = childrenOf(node)
        local textChildren = 0
        for _, child in ipairs(children) do
            if Safe.Get(function() return child.TextBlock end) ~= nil then
                textChildren = textChildren + 1
            end
        end
        if textChildren >= 3 then
            local score = textChildren * 10 + #children
            if score > bestScore then
                best, bestScore = node, score
            end
        end
    end)
    return best
end

local function ensureButton()
    local pauseMenu = Safe.Get(function() return GUI.PauseMenu end)
    if pauseMenu == nil then return end

    if state.pauseMenu ~= pauseMenu then
        state.pauseMenu = pauseMenu
        state.button    = nil
    end
    if state.button ~= nil then return end

    local container = findButtonContainer(pauseMenu)
    if container ~= nil then
        state.button = GUI.Button(
            GUI.RectTransform(Vector2(1, 0.09), container.RectTransform),
            "Disable Components", GUI.Alignment.Center, "GUIButtonSmall")
    else
        state.button = GUI.Button(
            GUI.RectTransform(Vector2(0.48, 0.065), pauseMenu.RectTransform, GUI.Anchor.BottomCenter),
            "Disable Components", GUI.Alignment.Center, "GUIButtonSmall")
    end

    state.button.OnClicked = function()
        SettingsMenu.Toggle()
        return true
    end
end

Safe.AddHook("think", "HDC.PauseMenuButton.Track", function()
    local isOpen = Safe.Get(function() return GUI.PauseMenuOpen end) == true
    if isOpen == state.wasOpen then return end
    state.wasOpen = isOpen

    if isOpen then
        ensureButton()
    else
        state.pauseMenu = nil
        state.button    = nil
        SettingsMenu.Close()
    end
end)

return PauseMenuButton
