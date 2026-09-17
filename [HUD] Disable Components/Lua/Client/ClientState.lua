-- Lua/Client/ClientState.lua — CLIENT
--
-- Local mirror of the server's policy, plus the two self-only toggles
-- (items 13 and 14) which never leave this machine.
--
-- Feature modules read from here every frame rather than being patched and
-- unpatched as values change: patches install once at load and simply
-- consult the current value, which makes toggling instant and free of
-- re-patch races.
--
-- PENDING EDITS
-- When the local user changes a setting the menu shows the new value
-- immediately ("optimistic") and asks the server to adopt it. Until the
-- server's broadcast for that field arrives, an incoming broadcast for a
-- DIFFERENT field must not be allowed to reset the local value by
-- carrying the server's still-old view of it. Pending entries shadow the
-- field for that window and are cleared the moment the server echoes back
-- the value we sent.

HDC = HDC or {}

local Safe = HDC.Safe

local ClientState = {}
HDC.ClientState = ClientState

ClientState.Values = {}
for key, default in pairs(HDC.FeatureDefaults) do
    ClientState.Values[key] = default
end

-- key -> { value = <value>, token = <identity token> }.
-- Present only while an edit is in flight; cleared on server confirmation
-- or after a timeout.
ClientState.Pending = {}

-- How long an unconfirmed edit keeps shadowing incoming broadcasts before
-- we give up and accept the server's value. Long enough to cover a normal
-- round-trip even on a laggy connection; short enough that a rejected edit
-- does not leave the UI lying for the rest of the round.
local PENDING_TIMEOUT_MS = 3000

local listeners = {}

local function notifyListeners()
    for _, listener in ipairs(listeners) do
        pcall(listener)
    end
end

function ClientState.Get(key)
    local value = ClientState.Values[key]
    if value == nil then return HDC.FeatureDefaults[key] end
    return value
end

function ClientState.GetNumber(key)
    return tonumber(ClientState.Get(key)) or 0
end

function ClientState.SetLocal(key, value)
    if ClientState.Local[key] == nil then return false end
    ClientState.Local[key] = (value == true)
    return true
end

function ClientState.ToggleLocal(key)
    if ClientState.Local[key] == nil then return nil end
    ClientState.Local[key] = not ClientState.Local[key]
    return ClientState.Local[key]
end

-- Local edit made from the settings menu, before it is sent upstream.
-- Values are coerced against the registry here too, so the menu cannot
-- push an out-of-range float even momentarily.
function ClientState.SetLocalPolicyValue(key, value)
    local coerced = HDC.CoerceValue(key, value)
    if coerced == nil then return false end
    ClientState.Values[key] = coerced
    return true
end

-- Records that `value` for `key` has just been sent to the server and that
-- broadcasts carrying a different value for this key should be ignored
-- until either the server confirms this value or the timeout fires.
--
-- Call this AFTER SetLocalPolicyValue and BEFORE Net.RequestPolicyChange.
-- key -> last value the server actually broadcast for this key. Updated on
-- every accepted broadcast, whether or not we applied it (a dropped
-- broadcast due to a pending edit still teaches us what the server thinks
-- the value is). Used as the fallback when a pending edit times out.
ClientState.LastServerValue = {}

function ClientState.MarkPending(key, value)
    local token = {}
    ClientState.Pending[key] = { value = value, token = token }
    Safe.Set(function()
        Timer.Wait(function()
            local entry = ClientState.Pending[key]
            if entry ~= nil and entry.token == token then
                -- Server never echoed this value back: our edit was either
                -- rejected or lost a same-field race to another admin.
                -- Stop shadowing and adopt the server's last known value so
                -- the UI does not lie about what is actually in effect.
                ClientState.Pending[key] = nil
                local serverValue = ClientState.LastServerValue[key]
                if serverValue ~= nil then
                    ClientState.Values[key] = serverValue
                end
                notifyListeners()
            end
        end, PENDING_TIMEOUT_MS)
    end)
end

function ClientState.ApplyFromServer(values)
    if type(values) ~= "table" then return end
    for key, value in pairs(values) do
        local coerced = HDC.CoerceValue(key, value)
        if coerced ~= nil then
            ClientState.LastServerValue[key] = coerced

            local pending = ClientState.Pending[key]
            if pending == nil then
                ClientState.Values[key] = coerced
            elseif pending.value == coerced then
                -- Server confirmed our edit. Adopt and stop shadowing.
                ClientState.Pending[key] = nil
                ClientState.Values[key] = coerced
            end
            -- else: our edit is still in flight (or lost). Keep the
            -- optimistic value; the pending timeout above will adopt
            -- LastServerValue if confirmation never arrives.
        end
    end
    notifyListeners()
end

function ClientState.AddChangeListener(callback)
    if type(callback) == "function" then
        table.insert(listeners, callback)
    end
end

function ClientState.Snapshot()
    local snapshot = {}
    for _, key in ipairs(HDC.FeatureKeyOrder) do
        snapshot[key] = ClientState.Get(key)
    end
    return snapshot
end

function ClientState.Describe()
    local lines = {}
    for _, entry in ipairs(HDC.FeatureRegistry) do
        local value = ClientState.Get(entry.key)
        local shown
        if entry.type == "float" then
            shown = string.format("%.2f", tonumber(value) or 0)
        else
            shown = value == true and "ON" or "off"
        end
        local pending = ClientState.Pending[entry.key] ~= nil and " (pending)" or ""
        table.insert(lines, string.format("  %-22s %s%s", entry.key, shown, pending))
    end
    table.insert(lines, string.format("  %-22s %s", "HideOwnUI (local)",
        ClientState.GetLocal("HideOwnUI") and "ON" or "off"))
    table.insert(lines, string.format("  %-22s %s", "HideOwnCursor (local)",
        ClientState.GetLocal("HideOwnCursor") and "ON" or "off"))
    return table.concat(lines, "\n")
end

return ClientState
