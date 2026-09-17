-- Lua/Client/Features/Camera.lua — CLIENT
--
-- Two synced camera controls:
--   LockCameraZoom + CameraZoomLevel   force a zoom level on every client
--   DisableCameraFollow                stop the camera drifting toward the cursor
--
-- Both are phrased so that "off" means vanilla behaviour, which is why the
-- zoom is a lock plus a value rather than a bare number: with the lock off
-- the mod never touches the camera at all.
--
-- Neither control can be implemented by writing the obvious property every
-- frame, because GameScreen.Update ends with Camera.MoveCamera and that
-- method rewrites both values after everything else has run.

HDC = HDC or {}

local Safe        = HDC.Safe
local ClientState = HDC.ClientState

-- Written directly rather than through the MinZoom / MaxZoom properties:
-- the MaxZoom setter clamps its input to a minimum of 1.0, which makes
-- every locked zoom below 1.0 impossible to express through it.
Safe.MakeFieldAccessible("Barotrauma.Camera", "minZoom")
Safe.MakeFieldAccessible("Barotrauma.Camera", "maxZoom")

local function zoomLocked()
    return ClientState.Get("LockCameraZoom") == true
end

local function targetZoom()
    return ClientState.GetNumber("CameraZoomLevel")
end

local function followDisabled()
    return ClientState.Get("DisableCameraFollow") == true
end

local function activeCamera()
    return Safe.Get(function() return GameMain.GameScreen.Cam end)
        or Safe.Get(function() return Screen.Selected.Cam end)
end

local function setBounds(camera, minimum, maximum)
    Safe.Set(function() camera.minZoom = minimum end)
    Safe.Set(function() camera.maxZoom = maximum end)
end

-- Vanilla bounds, captured the first time a lock is applied so they can be
-- put back when it is released. Captured lazily rather than at load: the
-- camera does not exist yet when this file runs.
local savedBounds = nil

-- The lock works by pinning the camera's own zoom bounds to the target.
-- Camera.Zoom's setter clamps every write to [MinZoom, MaxZoom], so with
-- the two collapsed onto one value the game clamps itself to the target on
-- the mod's behalf and there is nothing left to fight each frame.
--
-- Blocking set_Zoom outright, which is what this module used to do, cannot
-- work: the block applies to this mod's own write as well, so the lock
-- prevented the very assignment that was supposed to enforce it and the
-- zoom never moved.
--
-- Capture and release live in the same hook as the apply. Split across two
-- hooks they raced: whichever ran first decided whether the "original"
-- bounds being saved were the vanilla ones or the ones already pinned.
Safe.AddHook("think", "HDC.Camera.ApplyZoomLock", function()
    local camera = activeCamera()
    if camera == nil then return end

    if not zoomLocked() then
        if savedBounds ~= nil then
            setBounds(camera, savedBounds.min, savedBounds.max)
            savedBounds = nil
        end
        return
    end

    if savedBounds == nil then
        savedBounds = {
            min = Safe.Get(function() return camera.MinZoom end) or 0.1,
            max = Safe.Get(function() return camera.MaxZoom end) or 2.0,
        }
    end

    local zoom = targetZoom()
    setBounds(camera, zoom, zoom)
    -- Snaps to a newly pushed zoom level immediately instead of waiting for
    -- the game's next write to be clamped into place.
    Safe.Set(function() camera.Zoom = zoom end)
end)

-- Camera.MoveCamera multiplies the cursor offset by Camera.OffsetAmount,
-- and Character.ControlLocalPlayer rebuilds OffsetAmount from scratch every
-- frame, ending on a lerp toward its own target. A think hook cannot hold
-- it at zero against that. GameScreen.Update runs the character update
-- before MoveCamera, so the moment ControlLocalPlayer returns is the one
-- window in the frame where a zero survives to be read.
Safe.PatchMethod("Barotrauma.Character", "ControlLocalPlayer", nil, function(instance, ptable)
    if not followDisabled() then return end
    local camera = Safe.Get(function() return ptable["cam"] end) or activeCamera()
    if camera == nil then return end
    Safe.Set(function() camera.OffsetAmount = 0 end)
end, Hook.HookMethodType.After)
