local PlacementSteps = {}

PlacementSteps.PLACE = { 191, 201, 24 }
PlacementSteps.STOP = { 25, 177, 194, 200, 202, 322 }

local BACK, CLICK, CTRL, FINE, SURFACE = 194, 24, 36, 19, 23
local WHEEL_UP, WHEEL_DOWN, RAISE, LOWER = 15, 14, 10, 11

function PlacementSteps.pressed(keys, skip)
    for _, key in ipairs(keys) do
        if key ~= skip and IsDisabledControlJustPressed(0, key) then return true end
    end

    return false
end

function PlacementSteps.released(keys)
    for _, key in ipairs(keys) do
        if IsControlJustReleased(0, key) or IsDisabledControlJustReleased(0, key) then return true end
    end

    return false
end

function PlacementSteps.input(session)
    if session.skip and IsDisabledControlJustPressed(0, BACK) then
        return session.skip
    end

    if PlacementSteps.pressed(PlacementSteps.STOP) then return 'cancel' end

    if PlacementSteps.pressed(PlacementSteps.PLACE, not session.click and CLICK or nil) then
        return session.valid and 'confirm' or 'blocked'
    end

    return nil
end

function PlacementSteps.wheel(session)
    local up, down = IsDisabledControlJustPressed(0, WHEEL_UP), IsDisabledControlJustPressed(0, WHEEL_DOWN)

    if not up and not down then return nil end

    local target = session.wheel or 'rotate'

    if session.wheel2 and IsDisabledControlPressed(0, CTRL) then
        target = session.wheel2
    end

    return target, up and 1 or -1, IsDisabledControlPressed(0, FINE)
end

function PlacementSteps.lift(session)
    if not session.lift then return nil end

    local fine = IsDisabledControlPressed(0, FINE)

    if IsDisabledControlJustPressed(0, RAISE) then return 1, fine end
    if IsDisabledControlJustPressed(0, LOWER) then return -1, fine end

    return nil
end

function PlacementSteps.surface(session)
    if not IsDisabledControlJustPressed(0, SURFACE) then return nil end

    return session.snap ~= nil and 'toggle' or 'reset'
end

function PlacementSteps.blocked()
    PlaySoundFrontend(-1, 'ERROR', 'HUD_FRONTEND_DEFAULT_SOUNDSET', true)
end

return PlacementSteps
