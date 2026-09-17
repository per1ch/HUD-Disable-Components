-- Lua/Core/Safe.lua — SHARED (loaded in both SERVER and CLIENT contexts)
--
-- Defensive wrappers used by every other module in the mod, so that one
-- wrong method signature, missing field, or unexpected nil never brings
-- down the whole mod — it logs and the rest keeps running. Generalized
-- from the safeGet/safeSet/patchMethod pattern already proven in this
-- project's original HUDRemover.lua reference code.

HDC = HDC or {}

local Safe = {}
HDC.Safe = Safe

local LOG_PREFIX = "[HDC] "

function Safe.Log(msg)
    print(LOG_PREFIX .. tostring(msg))
end

-- Runs valueFn and returns its result, or nil if it throws.
function Safe.Get(valueFn)
    local ok, result = pcall(valueFn)
    if ok then return result end
    return nil
end

-- Runs setterFn, swallowing any error. Returns true/false for success.
function Safe.Set(setterFn)
    return pcall(setterFn)
end

-- Wraps Hook.Patch so a bad type name / method name / signature logs
-- instead of crashing the autorun chain. `signatures` may be nil to let
-- Hook.Patch resolve the overload itself.
function Safe.PatchMethod(typeName, methodName, signatures, callback, hookType)
    local ok, err = pcall(function()
        if signatures ~= nil then
            Hook.Patch(typeName, methodName, signatures, callback, hookType)
        else
            Hook.Patch(typeName, methodName, callback, hookType)
        end
    end)
    if not ok then
        Safe.Log("patch failed: " .. tostring(typeName) .. "." .. tostring(methodName) ..
                 " -- " .. tostring(err))
    end
    return ok
end

-- Wraps Hook.Add the same way, for named event hooks (think / roundStart /
-- clientConnected / etc).
function Safe.AddHook(eventName, hookId, callback)
    local ok, err = pcall(function()
        Hook.Add(eventName, hookId, callback)
    end)
    if not ok then
        Safe.Log("hook failed: " .. tostring(eventName) .. "/" .. tostring(hookId) ..
                 " -- " .. tostring(err))
    end
    return ok
end

-- Makes a private C# field readable/writable from Lua, tolerating repeat
-- calls and unknown types.
function Safe.MakeFieldAccessible(typeName, fieldName)
    pcall(function()
        local descriptor = Descriptors and Descriptors[typeName] or nil
        if descriptor == nil then
            descriptor = LuaUserData.RegisterType(typeName)
        end
        if descriptor ~= nil then
            LuaUserData.MakeFieldAccessible(descriptor, fieldName)
        end
    end)
end

-- Registers a console command, tolerating a failed registration (e.g. on
-- a hot-reload where the name already exists).
function Safe.AddCommand(name, description, handler, validation, isCheat)
    local ok, err = pcall(function()
        Game.AddCommand(name, description, handler, validation, isCheat == true)
    end)
    if not ok then
        Safe.Log("command registration failed: " .. tostring(name) .. " -- " .. tostring(err))
    end
    return ok
end

-- The C# GUI static class. LuaCs exposes it either directly as the global
-- GUI or nested one level down, so both are tried. Features that flip a
-- vanilla global HUD switch go through here instead of patching a draw
-- call, because the switch is what the game itself checks.
function Safe.GUIStatic()
    local gui = Safe.Get(function() return GUI end)
    if gui == nil then return nil end
    return Safe.Get(function() return gui.GUI end) or gui
end

-- Static-member accessor for a C# type LuaCs does not expose as a global,
-- for the cases where a private static field is the only thing gating a
-- draw. Returns nil if the type cannot be resolved.
function Safe.Static(typeName)
    return Safe.Get(function() return LuaUserData.CreateStatic(typeName) end)
end

-- Walks a GUIComponent tree (depth-first over .Children) and calls
-- visitFn(node) on every node found, including the root. Used by features
-- that need to locate a GUI element generically (by matching text/style)
-- instead of depending on a specific internal field name that may change
-- between game versions — the same spirit as the pause-menu-button search
-- already used in the original HUDRemover.lua reference code.
function Safe.WalkComponents(root, visitFn)
    if root == nil then return end
    local stack = { root }
    while #stack > 0 do
        local node = table.remove(stack)
        if node ~= nil then
            pcall(visitFn, node)
            local children = Safe.Get(function() return node.Children end)
            if children ~= nil then
                pcall(function()
                    for child in children do
                        table.insert(stack, child)
                    end
                end)
            end
        end
    end
end

function Safe.HookUpdateList(addToUpdateList)
    if type(addToUpdateList) ~= "function" then return end
    local handler = function() addToUpdateList() end
    Safe.PatchMethod("Barotrauma.GameSession",    "AddToGUIUpdateList", nil,
        handler, Hook.HookMethodType.After)
    Safe.PatchMethod("Barotrauma.GameScreen",     "AddToGUIUpdateList", nil,
        handler, Hook.HookMethodType.After)
    Safe.PatchMethod("Barotrauma.NetLobbyScreen", "AddToGUIUpdateList", nil,
        handler, Hook.HookMethodType.After)
end

return Safe
