-- Lua/Client/UI/SettingsMenu.lua — CLIENT
--
-- The callable menu required by the spec: a flat list of separate,
-- non-expandable rows, each with a single two-position ON/OFF toggle.
-- Rows are generated from HDC.FeatureRegistry, so adding a feature there
-- adds it here with no UI edits.
--
-- Every player may open the menu and see the current policy. Only a
-- player the server accepts as an editor can actually change it; for
-- everyone else the toggles render dimmed and do nothing. The server is
-- the authority either way (Server/Sync.lua re-broadcasts the true state
-- after any rejected edit).
--
-- EDITS ARE DELTAS
-- Every edit sends only the keys it actually changed, never a full
-- snapshot. A snapshot makes two admins editing different settings
-- overwrite each other with stale values carried inside their own
-- snapshot — that is the "settings are jumpy" bug. Each edit is also
-- registered as pending in ClientState so an in-flight broadcast cannot
-- roll the local value back before the server echoes it.

HDC = HDC or {}

local Safe        = HDC.Safe
local ClientState = HDC.ClientState
local Net         = HDC.Net

local SettingsMenu = {}
HDC.SettingsMenu = SettingsMenu

local PALETTE = {
    toggleOn       = Color(15,  145, 95,  228),
    toggleOnHover  = Color(22,  180, 118, 255),
    toggleOff      = Color(44,  46,  56,  215),
    toggleOffHover = Color(62,  65,  78,  245),
    indicatorOn    = Color(30,  190, 130, 255),
    indicatorOff   = Color(70,  78,  92,  170),
    title          = Color(50,  200, 225, 255),
    subtitle       = Color(145, 162, 172, 195),
    description    = Color(118, 135, 148, 185),
    separator      = Color(35,  162, 198, 150),
    readOnlyNotice = Color(210, 160, 90,  220),
}

local ui = {
    root      = nil,
    rows      = {},
    allRows   = {},   -- ordered list of { key, frame, label, desc, type, widget }
    isOpen    = false,
    canEdit   = true,
    notice    = nil,
    searchBox = nil,
    searchQuery = "",
}

-- The client cannot see the server's permission table, so it optimistically
-- allows edits and lets the server correct it. In singleplayer edits are
-- always local and always allowed.
local function localPlayerMayEdit()
    if not Net.IsMultiplayer() then return true end
    local hasPermission = Safe.Get(function()
        return Game.Client.HasPermission(ClientPermissions.ManageSettings)
    end)
    if hasPermission == true then return true end
    local isOwner = Safe.Get(function() return Game.Client.MyClient.IsOwner end)
    if isOwner == true then return true end
    -- Console-command permission is not queryable client-side; allow the
    -- attempt and let the server accept or reject it.
    return true
end

local function updateRowVisual(key)
    local row = ui.rows[key]
    if row == nil then return end

    -- Float rows carry a number input instead of an on/off button.
    if row.numberInput ~= nil then
        local value = ClientState.GetNumber(key)
        Safe.Set(function() row.numberInput.FloatValue = value end)
        Safe.Set(function() row.indicator.TextColor = PALETTE.indicatorOn end)
        return
    end

    local isOn = ClientState.Get(key) == true
    Safe.Set(function()
        row.toggle.Color          = isOn and PALETTE.toggleOn      or PALETTE.toggleOff
        row.toggle.HoverColor     = isOn and PALETTE.toggleOnHover or PALETTE.toggleOffHover
        row.toggle.TextBlock.Text = isOn and "  ON  " or " OFF  "
    end)
    Safe.Set(function()
        row.indicator.TextColor = isOn and PALETTE.indicatorOn or PALETTE.indicatorOff
    end)
end

function SettingsMenu.Refresh()
    for _, entry in ipairs(HDC.FeatureRegistry) do
        updateRowVisual(entry.key)
    end
end

-- Sends a delta upstream (or does nothing in singleplayer) and refreshes
-- the local visuals. `changes` is a table mapping key -> new value and
-- must contain only the fields this action actually edited.
local function commitChange(changes)
    if Net.IsMultiplayer() and changes ~= nil then
        Net.RequestPolicyChange(changes)
    end
    SettingsMenu.Refresh()
end

-- Records the new value locally, marks it pending, and returns the delta
-- table to hand to commitChange. Doing all three in one place keeps the
-- three steps from drifting out of sync at any call site.
local function applyEdit(key, value)
    ClientState.SetLocalPolicyValue(key, value)
    ClientState.MarkPending(key, value)
    return { [key] = value }
end

local function build()
    if ui.root ~= nil then return end

    ui.root = GUI.Frame(GUI.RectTransform(Vector2(1, 1)), "GUIBackgroundBlocker")
    ui.root.Visible      = false
    ui.root.CanBeFocused = true

    local panel = GUI.Frame(
        GUI.RectTransform(Vector2(0.50, 0.76), ui.root.RectTransform, GUI.Anchor.Center),
        "GUIFrame")

    local title = GUI.TextBlock(
        GUI.RectTransform(Vector2(0.80, 0.09), panel.RectTransform, GUI.Anchor.TopLeft),
        "[HUD] DISABLE COMPONENTS", nil, GUI.Style.LargeFont, GUI.Alignment.CenterLeft)
    title.RectTransform.RelativeOffset = Vector2(0.04, 0.022)
    Safe.Set(function() title.TextColor = PALETTE.title end)
    local subtitle = GUI.TextBlock(
        GUI.RectTransform(Vector2(0.88, 0.05), panel.RectTransform, GUI.Anchor.TopLeft),
        "Server-wide HUD policy", nil, nil, GUI.Alignment.CenterLeft)
    subtitle.RectTransform.RelativeOffset = Vector2(0.04, 0.100)
    Safe.Set(function() subtitle.TextColor = PALETTE.subtitle end)
    ui.notice = GUI.TextBlock(
        GUI.RectTransform(Vector2(0.88, 0.04), panel.RectTransform, GUI.Anchor.TopLeft),
        "", nil, nil, GUI.Alignment.CenterLeft)
    ui.notice.RectTransform.RelativeOffset = Vector2(0.04, 0.142)
    Safe.Set(function()
        ui.notice.TextColor    = PALETTE.readOnlyNotice
        ui.notice.CanBeFocused = false
    end)

    local searchBox = GUI.TextBox(
    GUI.RectTransform(Vector2(0.92, 0.050), panel.RectTransform, GUI.Anchor.TopLeft),
    "")
    searchBox.RectTransform.RelativeOffset = Vector2(0.04, 0.184)
    Safe.Set(function()
        searchBox.TextScale = 0.95
        searchBox.TextColor = Color(220, 232, 240, 255)
    end)
    ui.searchBox = searchBox

    local separator = GUI.Frame(
        GUI.RectTransform(Vector2(0.92, 0.004), panel.RectTransform, GUI.Anchor.TopCenter),
        "GUIFrameListBox")
    separator.RectTransform.RelativeOffset = Vector2(0, 0.244)
    Safe.Set(function() separator.Color = PALETTE.separator end)

    local listFrame = GUI.Frame(
        GUI.RectTransform(Vector2(0.92, 0.500), panel.RectTransform, GUI.Anchor.TopCenter),
        "GUIFrameListBox")
    listFrame.RectTransform.RelativeOffset = Vector2(0, 0.261)

    local list = GUI.ListBox(
        GUI.RectTransform(Vector2(1, 1), listFrame.RectTransform, GUI.Anchor.Center), false)

    for _, entry in ipairs(HDC.FeatureRegistry) do
        local row = GUI.Frame(
            GUI.RectTransform(Vector2(0.985, 0.150), list.Content.RectTransform, GUI.Anchor.TopCenter),
            "InnerFrame")
        row.ToolTip = entry.desc

        local indicator = GUI.TextBlock(
            GUI.RectTransform(Vector2(0.022, 0.82), row.RectTransform, GUI.Anchor.CenterLeft),
            "|", nil, nil, GUI.Alignment.Center)
        indicator.RectTransform.RelativeOffset = Vector2(0.008, 0)

        local label = GUI.TextBlock(
            GUI.RectTransform(Vector2(0.62, 0.44), row.RectTransform, GUI.Anchor.TopLeft),
            entry.label, nil, nil, GUI.Alignment.CenterLeft)
        label.RectTransform.RelativeOffset = Vector2(0.052, 0.070)
        Safe.Set(function() label.TextScale = 1.06 end)

        local description = GUI.TextBlock(
            GUI.RectTransform(Vector2(0.62, 0.36), row.RectTransform, GUI.Anchor.BottomLeft),
            entry.desc, nil, nil, GUI.Alignment.CenterLeft)
        description.RectTransform.RelativeOffset = Vector2(0.052, -0.070)
        Safe.Set(function()
            description.TextScale = 0.85
            description.TextColor = PALETTE.description
        end)

        local capturedKey = entry.key

        if entry.type == "float" then
            -- Numeric setting (camera zoom): a stepped number input rather
            -- than a two-position toggle.
            local numberInput = GUI.NumberInput(
                GUI.RectTransform(Vector2(0.22, 0.62), row.RectTransform, GUI.Anchor.CenterRight),
                NumberType.Float)
            numberInput.RectTransform.RelativeOffset = Vector2(-0.030, 0)
            Safe.Set(function()
                numberInput.MinValueFloat = entry.min or 0
                numberInput.MaxValueFloat = entry.max or 1
                numberInput.valueStep     = entry.step or 0.05
                numberInput.FloatValue    = ClientState.GetNumber(capturedKey)
            end)
            numberInput.OnValueChanged = function()
                if not ui.canEdit then return end
                local entered = Safe.Get(function() return numberInput.FloatValue end)
                if entered == nil then return end
                if math.abs(entered - ClientState.GetNumber(capturedKey)) < 1e-4 then return end
                commitChange(applyEdit(capturedKey, entered))
            end

            ui.rows[entry.key] = { numberInput = numberInput, indicator = indicator }
            table.insert(ui.allRows, {
                key   = entry.key,
                frame = row,
                label = entry.label or "",
                desc  = entry.desc  or "",
                type  = entry.type  or "bool",
            })
        else
            local toggle = GUI.Button(
                GUI.RectTransform(Vector2(0.17, 0.62), row.RectTransform, GUI.Anchor.CenterRight),
                "  ON  ", GUI.Alignment.Center, "GUIButtonSmall")
            toggle.RectTransform.RelativeOffset = Vector2(-0.050, 0)
            Safe.Set(function() toggle.TextBlock.TextScale = 1.0 end)

            toggle.OnClicked = function()
                if not ui.canEdit then return true end
                local newValue = not (ClientState.Get(capturedKey) == true)
                commitChange(applyEdit(capturedKey, newValue))
                return true
            end

            ui.rows[entry.key] = { toggle = toggle, indicator = indicator }
            table.insert(ui.allRows, {
                key   = entry.key,
                frame = row,
                label = entry.label or "",
                desc  = entry.desc  or "",
                type  = entry.type  or "bool",
            })
        end
        updateRowVisual(entry.key)
    end
    list.RecalculateChildren()

    searchBox.add_OnTextChanged(function(tb, text)
        ui.searchQuery = text or ""
        applySearchFilter()
    end)

    local actionSeparator = GUI.Frame(
        GUI.RectTransform(Vector2(0.92, 0.004), panel.RectTransform, GUI.Anchor.BottomCenter),
        "GUIFrameListBox")
    actionSeparator.RectTransform.RelativeOffset = Vector2(0, -0.190)
    Safe.Set(function() actionSeparator.Color = PALETTE.separator end)

    local actionBar = GUI.Frame(
        GUI.RectTransform(Vector2(0.92, 0.148), panel.RectTransform, GUI.Anchor.BottomCenter), nil)
    actionBar.RectTransform.RelativeOffset = Vector2(0, -0.016)
    local function applyAllBools(value)
        local changes = {}
        for _, entry in ipairs(HDC.FeatureRegistry) do
            if entry.type ~= "float" then
                ClientState.SetLocalPolicyValue(entry.key, value)
                ClientState.MarkPending(entry.key, value)
                changes[entry.key] = value
            end
        end
        return changes
    end
    local enableAll = GUI.Button(
        GUI.RectTransform(Vector2(0.22, 0.82), actionBar.RectTransform, GUI.Anchor.CenterLeft),
        "Enable All", GUI.Alignment.Center, "GUIButton")
    enableAll.OnClicked = function()
        if not ui.canEdit then return true end
        commitChange(applyAllBools(true))
        return true
    end

    local disableAll = GUI.Button(
        GUI.RectTransform(Vector2(0.22, 0.82), actionBar.RectTransform, GUI.Anchor.CenterLeft),
        "Disable All", GUI.Alignment.Center, "GUIButton")
    disableAll.RectTransform.RelativeOffset = Vector2(0.25, 0)
    disableAll.OnClicked = function()
        if not ui.canEdit then return true end
        commitChange(applyAllBools(false))
        return true
    end

    local consoleButton = GUI.Button(
        GUI.RectTransform(Vector2(0.26, 0.82), actionBar.RectTransform, GUI.Anchor.CenterLeft),
        "Remote Console", GUI.Alignment.Center, "GUIButton")
    consoleButton.RectTransform.RelativeOffset = Vector2(0.50, 0)
    consoleButton.ToolTip =
        "Run commands on a player's client and watch their console. Requires the hudRemoteConsole permission."
    consoleButton.OnClicked = function()
        SettingsMenu.Close()
        if HDC.RemoteConsoleUI ~= nil then HDC.RemoteConsoleUI.Open() end
        return true
    end
    local close = GUI.Button(
        GUI.RectTransform(Vector2(0.20, 0.82), actionBar.RectTransform, GUI.Anchor.CenterRight),
        "Close", GUI.Alignment.Center, "GUIButton")
    close.OnClicked = function() SettingsMenu.Close(); return true end
    ui.actionButtons = { enableAll, disableAll, close, consoleButton }
end

local function applyEditability()
    ui.canEdit = localPlayerMayEdit()

    Safe.Set(function()
        ui.notice.Text = ui.canEdit and "" or
            "View only - you do not have permission to change these settings."
    end)
    for _, row in pairs(ui.rows) do
        if row.toggle ~= nil then
            Safe.Set(function() row.toggle.Enabled = ui.canEdit end)
        end
        if row.numberInput ~= nil then
            Safe.Set(function() row.numberInput.Enabled = ui.canEdit end)
        end
    end
    if ui.actionButtons ~= nil then
        Safe.Set(function()
            ui.actionButtons[1].Enabled = ui.canEdit
            ui.actionButtons[2].Enabled = ui.canEdit
        end)
    end
end

applySearchFilter = function()
    local q = string.lower(ui.searchQuery or "")

    -- Fuzzy subsequence matcher with scoring. Returns nil on no match,
    -- otherwise a number where higher = better match. Bonuses:
    --   +12  matched at start of string
    --   +10  matched at a word boundary (after space / _ / - / . / /)
    --    +8  matched immediately after the previous match (consecutive)
    --   +0..20  matches earlier in the target rank higher
    --   -len/4  shorter targets outrank longer ones on ties
    local function fuzzyScore(target, needle)
        if needle == "" then return 0 end
        if target == nil or target == "" then return nil end
        local t   = string.lower(target)
        local tn, nn = #t, #needle
        if nn > tn then return nil end

        local score     = 0
        local ti        = 1
        local prevMatch = -2
        for ni = 1, nn do
            local c = needle:sub(ni, ni)
            local found = nil
            while ti <= tn do
                if t:sub(ti, ti) == c then
                    found = ti
                    break
                end
                ti = ti + 1
            end
            if found == nil then return nil end

            if found == prevMatch + 1 then
                score = score + 8
            end
            if found == 1 then
                score = score + 12
            else
                local prev = t:sub(found - 1, found - 1)
                if prev == " " or prev == "_" or prev == "-"
                   or prev == "." or prev == "/" then
                    score = score + 10
                end
            end
            score = score + math.max(0, 20 - found)
            prevMatch = found
            ti = found + 1
        end
        score = score - math.floor(tn / 4)
        return score
    end

    -- Score every row against label, description and key; keep the best.
    for _, r in ipairs(ui.allRows) do
        local best = nil
        local function consider(s)
            local sc = fuzzyScore(s, q)
            if sc ~= nil and (best == nil or sc > best) then
                best = sc
            end
        end
        consider(r.label)
        consider(r.desc)
        consider(r.key)

        local visible = (q == "") or (best ~= nil)
        Safe.Set(function() r.frame.Visible = visible end)
    end

    -- Collapse any empty space left by hidden rows.
    Safe.Set(function()
        local content = ui.allRows[1] ~= nil and ui.allRows[1].frame.Parent
        if content ~= nil and content.Recalculate ~= nil then
            content.Recalculate()
        end
    end)
end

function SettingsMenu.Open()
    build()
    applyEditability()
    SettingsMenu.Refresh()
    ui.isOpen = true
    ui.root.Visible = true
end

function SettingsMenu.Close()
    if ui.root ~= nil then ui.root.Visible = false end
    ui.isOpen = false
end

function SettingsMenu.Toggle()
    if ui.isOpen then SettingsMenu.Close() else SettingsMenu.Open() end
end

function SettingsMenu.IsOpen()
    return ui.isOpen
end

local function addToUpdateList()
    if ui.root == nil or ui.root.Visible ~= true then return end
    local added = Safe.Set(function() ui.root.AddToGUIUpdateList(false, 999) end)
    if not added then Safe.Set(function() ui.root.AddToGUIUpdateList() end) end
end

Safe.PatchMethod("Barotrauma.GameSession", "AddToGUIUpdateList", nil,
    function() addToUpdateList() end, Hook.HookMethodType.After)

Safe.PatchMethod("Barotrauma.GameScreen", "AddToGUIUpdateList", nil,
    function() addToUpdateList() end, Hook.HookMethodType.After)

Safe.PatchMethod("Barotrauma.NetLobbyScreen", "AddToGUIUpdateList", nil,
    function() addToUpdateList() end, Hook.HookMethodType.After)

ClientState.AddChangeListener(function()
    if ui.root ~= nil then SettingsMenu.Refresh() end
end)

return SettingsMenu