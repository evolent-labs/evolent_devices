local Config = require 'config'
local Util = require 'shared.util'
local DeviceRules = require 'shared.rules'
local Marker = require 'client.marker'
local Nui = require 'client.nui'
local PlacementSync = require 'client.placement_sync'
local PlacementSteps = require 'client.placement_steps'

local PlacementCamera = { active = nil }

local V = DeviceRules.vector
local ROOM_CHECK_MS = 250
local STAND_RADIUS, STAND_KNEE = 0.25, 0.3
local HELP_KEY, WALK_KEY = 74, 47
local LEVEL_REACH, RAY_REACH = 80.0, 80.0
local VIEW_UP, VIEW_BACK, VIEW_MARGIN, VIEW_MIN = 1.2, 1.8, 0.2, 0.4
local WALK_MS = 100
local ZONE = { min = 2.0, max = 200.0, step = 2.0, fine = 0.5 }
local TURN, TURN_FINE, LIFT, LIFT_FINE = 5.0, 1.0, 0.05, 0.01
local ADJUST = {
    zone = { 'radius' },
    object = { 'rotate', 'height' },
}

local function direction(pitch, heading)
    local x, z = math.rad(pitch), math.rad(heading)

    return vector3(-math.sin(z) * math.cos(x), math.cos(z) * math.cos(x), math.sin(x))
end

local function flat(a, b)
    local dx, dy = a.x - b.x, a.y - b.y

    return math.sqrt(dx * dx + dy * dy)
end

local function probe(from, to, ignore)
    local handle = StartExpensiveSynchronousShapeTestLosProbe(
        from.x,
        from.y,
        from.z,
        to.x,
        to.y,
        to.z,
        1 + 16,
        ignore or 0,
        7
    )

    local _, hit, at = GetShapeTestResult(handle)

    if Util.yes(hit) and at then
        return at
    end

    return nil
end

local function giveBack(entity)
    if not entity or not DoesEntityExist(entity) then return end

    SetEntityCollision(entity, true, true)
    SetEntityVisible(entity, true, false)
end

local function makeGhost(session)
    local model = session.model
    local hash = model and PlacementSync.loadModel(model)

    if not hash then return end

    local origin = session.position
    local object = CreateObjectNoOffset(hash, origin.x, origin.y, origin.z - 20.0, false, false, false)

    SetModelAsNoLongerNeeded(hash)

    if not object or object == 0 then return end

    SetEntityAsMissionEntity(object, true, true)
    SetEntityCollision(object, false, false)
    FreezeEntityPosition(object, true)
    SetEntityAlpha(object, 170, false)
    session.ghost = object
end

local function releaseGhost(session)
    if session.ghost and DoesEntityExist(session.ghost) then
        DeleteEntity(session.ghost)
    end

    session.ghost, session.ghostShown, session.ghostAt, session.ghostAlpha = nil, nil, nil, nil
end

local function showGhost(session, shown)
    local ghost = session.ghost

    if not ghost or session.ghostShown == shown or not DoesEntityExist(ghost) then return end

    session.ghostShown = shown
    SetEntityVisible(ghost, shown, false)
end

local function hideMoving(session)
    local entity = session.moving

    if not entity or not DoesEntityExist(entity) then return end

    SetEntityCollision(entity, false, false)
    SetEntityVisible(entity, false, false)
end

local function showMoving(session)
    local entity = session.moving

    session.moving = nil
    giveBack(entity)
end

local function startView(session, start)
    local base = vector3(start.x, start.y, start.z)
    local from = base + vector3(0.0, 0.0, VIEW_UP * 0.5)
    local want = base + vector3(0.0, 0.0, VIEW_UP) - direction(0.0, session.yaw) * VIEW_BACK
    local hit = probe(from, want, session.moving)

    if hit then
        local span = want - from
        local room = #(vector3(hit.x, hit.y, hit.z) - from) - VIEW_MARGIN

        want = from + span * (math.max(VIEW_MIN, room) / #span)
    end

    return want, -math.deg(math.atan(want.z - base.z, math.max(0.01, flat(want, base))))
end

local function beginCamera(session)
    local ped = cache.ped

    session.ped = ped
    session.wasFrozen = Util.yes(IsEntityPositionFrozen(ped))
    FreezeEntityPosition(ped, true)
    session.anchor = GetEntityCoords(ped)
    session.relativeHeading, session.relativePitch = GetGameplayCamRelativeHeading(), GetGameplayCamRelativePitch()

    local camCoord, rotation = GetGameplayCamCoord(), GetGameplayCamRot(2)

    session.position = vector3(camCoord.x, camCoord.y, camCoord.z + 0.4)
    session.pitch, session.yaw = math.min(-30.0, rotation.x + 0.0), rotation.z + 0.0

    local start = session.start

    if start and #(vector3(start.x, start.y, start.z) - session.anchor) < session.range - 10.0 then
        session.yaw = (start.w or 0.0) + 0.0
        session.position, session.pitch = startView(session, start)
    end

    session.cam = CreateCamWithParams(
        'DEFAULT_SCRIPTED_CAMERA',
        session.position.x,
        session.position.y,
        session.position.z,
        session.pitch,
        0.0,
        session.yaw,
        60.0,
        true,
        2
    )

    RenderScriptCams(true, false, 0, true, true)
end

local function endCamera(session)
    if session.cam then
        RenderScriptCams(false, false, 0, true, true)
        DestroyCam(session.cam, false)
        session.cam = nil
    end

    ClearFocus()

    if session.ped and DoesEntityExist(session.ped) then
        FreezeEntityPosition(session.ped, session.wasFrozen == true)
        SetGameplayCamRelativeHeading(session.relativeHeading or 0.0)
        SetGameplayCamRelativePitch(session.relativePitch or 0.0, 1.0)
    end
end

local function cameraTick(session)
    DisableAllControlActions(0)

    local dt = math.min(GetFrameTime(), 0.05)

    session.yaw = (session.yaw - GetDisabledControlNormal(0, 1) * 8.0) % 360.0
    session.pitch = math.max(-85.0, math.min(60.0, session.pitch - GetDisabledControlNormal(0, 2) * 8.0))

    local speed = IsDisabledControlPressed(0, 21) and 12.0 or 4.0

    local function held(control)
        return IsDisabledControlPressed(0, control) and 1.0 or 0.0
    end

    local forward = direction(0.0, session.yaw)
    local right = vector3(forward.y, -forward.x, 0.0)

    local step = forward * (held(32) - held(33)) + right * (held(35) - held(34)) + vector3(
        0.0,
        0.0,
        held(38) - held(44)
    )

    if #step > 1.0 then
        step = step / #step
    end

    local at = session.position + step * speed * dt
    local delta = at - session.anchor

    session.atEdge = #delta > session.range - 0.5

    if #delta > session.range then
        at = session.anchor + delta / #delta * session.range
    end

    session.position = at
    SetCamCoord(session.cam, at.x, at.y, at.z)
    SetCamRot(session.cam, session.pitch, 0.0, session.yaw, 2)
    SetFocusPosAndVel(at.x, at.y, at.z, 0.0, 0.0, 0.0)
    SetEntityLocallyInvisible(session.ped)
    DisablePlayerFiring(cache.playerId, true)
end

local function castRay(session)
    if not session.ray then
        local origin = session.position
        local target = origin + direction(session.pitch, session.yaw) * RAY_REACH

        session.ray = StartShapeTestLosProbe(
            origin.x,
            origin.y,
            origin.z,
            target.x,
            target.y,
            target.z,
            1 + 16,
            session.ghost or 0,
            7
        )

        return
    end

    local status, hit, point, normal = GetShapeTestResult(session.ray)

    if status == 1 then return end

    session.ray = nil

    local minimum = session.kind == 'zone' and 0.7 or -1.0

    if status == 2 and Util.yes(hit) and normal and normal.z >= minimum then
        session.ground = point
        session.normal = normal
        session.surface = true
    else
        session.surface = false
    end
end

local function deviceRoom(session, point)
    local spec = session.deviceSpec
    local spot = DeviceRules.useSpot(point, spec)
    local notes = {}

    if spec.placeOn == 'floor' then
        local floor = probe(
            { x = spot.x, y = spot.y, z = point.z + 0.6 },
            { x = spot.x, y = spot.y, z = point.z - 0.6 },
            session.ghost
        )

        session.useFloor = floor and floor.z or nil

        if not floor or math.abs(floor.z - point.z) > 0.35 then
            notes[#notes + 1] = locale('device_no_stand_spot')
        end

        local basis = DeviceRules.screenBasis(DeviceRules.worldCorners(point, spec))

        if probe(basis.centre, V.add(basis.centre, V.scale(basis.normal, spec.clearFront)), session.ghost) then
            notes[#notes + 1] = locale('device_front_blocked', spec.clearFront)
        end

        return notes
    end

    local range = spec.use.floor or { min = 0.3, max = 1.4 }

    local floor = probe(
        { x = spot.x, y = spot.y, z = point.z + 0.25 },
        { x = spot.x, y = spot.y, z = point.z - range.max - 0.1 },
        session.ghost
    )

    session.useFloor = floor and floor.z or nil

    local drop = floor and point.z - floor.z or nil

    if not drop or drop < range.min or drop > range.max then
        notes[#notes + 1] = locale('device_needs_table')

        return notes
    end

    local toward = V.unit({ x = point.x - spot.x, y = point.y - spot.y, z = 0.0 })
    local edge = V.add(spot, V.scale(toward, STAND_RADIUS))

    if probe({ x = edge.x, y = edge.y, z = point.z + 0.25 }, { x = edge.x, y = edge.y, z = floor.z + STAND_KNEE }, session.ghost) then
        notes[#notes + 1] = locale('device_stand_blocked')
    end

    return notes
end

local function slopeCheck(session, notes)
    if not session.snap then return true end

    local surface = DeviceRules.surface(session.normal)

    if surface == 'steep' then
        return false, locale('device_surface_steep', ('%g'):format(Config.devices.maxSlope))
    end

    if surface == 'sloped' then
        notes[#notes + 1] = locale('device_kept_level')
    end

    return true
end

local function validateDevice(session, point)
    local notes = {}
    local ok, reason = slopeCheck(session, notes)

    if not ok then
        return false, reason, notes
    end

    local spaced, blocker = DeviceRules.spacingOk(session.devices, point, session.device)

    if not spaced then
        session.blocker = blocker

        return false, locale('reason_overlap'), notes
    end

    local now = GetGameTimer()
    local last = session.roomAt

    if not last or now - session.roomTime >= ROOM_CHECK_MS or V.length(V.sub(last, point)) > 0.02 or math.abs(last.w - point.w) > 0.5 then
        session.roomAt = { x = point.x, y = point.y, z = point.z, w = point.w }
        session.roomTime = now
        session.roomNotes = deviceRoom(session, point)
    end

    for _, note in ipairs(session.roomNotes or {}) do
        notes[#notes + 1] = note
    end

    return true, nil, notes
end

local function validate(session)
    local free = session.snap == false

    session.blocker = nil

    if not session.point or not (free or session.surface) then
        if session.atEdge then
            return false, locale('placement_walk_closer')
        end

        if free and session.level > session.position.z then
            return false, locale('device_aim_higher')
        end

        if free then
            return false, locale('device_aim_level')
        end

        return false, session.kind == 'zone' and locale('placement_aim') or locale('device_aim_surface')
    end

    local point = session.point

    if #(vector3(point.x, point.y, point.z) - session.anchor) > session.range then
        return false, locale('placement_walk_closer')
    end

    if session.kind == 'device' then
        return validateDevice(session, point)
    end

    if session.kind == 'prop' then
        local notes = {}
        local ok, reason = slopeCheck(session, notes)

        return ok, reason, notes
    end

    return true
end

local function toneOf(session)
    if not session.valid then return 'bad' end
    if session.notes and #session.notes > 0 then return 'warn' end

    return nil
end

local function standSpot(session, point)
    local spec = session.deviceSpec

    if not spec then return nil end

    local spot = DeviceRules.useSpot(point, spec)

    spot.z = session.useFloor or (spec.placeOn == 'floor' and point.z or point.z - 1.0)

    return spot
end

local function moveGhost(session, point)
    local ghost = session.ghost
    local at = session.ghostAt

    if not at or at.x ~= point.x or at.y ~= point.y or at.z ~= point.z or at.w ~= point.w then
        SetEntityCoordsNoOffset(ghost, point.x, point.y, point.z, false, false, false)
        SetEntityHeading(ghost, point.w)
        session.ghostAt = { x = point.x, y = point.y, z = point.z, w = point.w }
    end

    local alpha = session.valid and 180 or 110

    if session.ghostAlpha ~= alpha then
        SetEntityAlpha(ghost, alpha, false)
        session.ghostAlpha = alpha
    end
end

local function drawContext(session)
    local point = session.point
    local zone = session.kind == 'zone'

    Marker.placement(session.marks, {
        point = point,
        tone = point and toneOf(session) or nil,
        accent = session.accent,
        model = not zone and session.model or nil,
        front = session.deviceSpec ~= nil,
        stand = point and standSpot(session, point) or nil,
        ring = session.ring and session.ring.radius or session.reach,
        others = session.devices,
        blocker = session.blocker,
    })

    if not point then
        showGhost(session, false)

        return
    end

    if zone or not session.ghost or not DoesEntityExist(session.ghost) then return end

    showGhost(session, true)
    moveGhost(session, point)
end

local function push(session)
    local point = session.point
    local free = session.snap == false
    local floor = free and point and session.useFloor
    local height = session.height

    if floor then
        height = point.z - floor
    elseif free then
        height = session.level - session.anchor.z
    end

    PlacementSync.push(session, {
        loading = session.surface == nil,
        valid = session.valid == true,
        reason = session.reason or '',
        notes = table.concat(session.notes or {}, '\n'),
        edge = session.atEdge == true,
        help = session.help == true,
        d = point and #(session.position - vector3(point.x, point.y, point.z)) or 0.0,
        h = session.heading,
        snap = session.snap,
        y = height,
        ymode = free and (floor and 'floor' or 'feet') or 'offset',
        r = session.ring and session.ring.radius or 0.0,
    })
end

local function turn(session)
    local target, delta, fine = PlacementSteps.wheel(session)

    if target == 'rotate' then
        session.heading = (session.heading + delta * (fine and TURN_FINE or TURN)) % 360.0

        return
    end

    local ring = session.ring

    if target ~= 'radius' or not ring then return end

    local radius = ring.radius + delta * (fine and ZONE.fine or ZONE.step)

    ring.radius = math.max(ring.min, math.min(ring.max, radius))
end

local function surface(session)
    local action = PlacementSteps.surface(session)

    if action == 'reset' then
        session.height = 0.0

        return
    end

    if action ~= 'toggle' then return end

    session.snap = not session.snap

    if session.snap then
        session.height = 0.0
    else
        session.level = session.point and session.point.z or session.anchor.z
    end
end

local function tick(session)
    cameraTick(session)
    castRay(session)
    turn(session)

    if IsDisabledControlJustPressed(0, HELP_KEY) then
        session.help = not session.help
    end

    if IsDisabledControlJustPressed(0, WALK_KEY) then
        return 'walk'
    end

    surface(session)

    local free = session.snap == false
    local lift, fine = PlacementSteps.lift(session)
    local step = fine and LIFT_FINE or LIFT
    local raise, lower = lift == 1, lift == -1

    if free then
        local span = session.range

        if raise then
            session.level = session.level + step
        end

        if lower then
            session.level = session.level - step
        end

        session.level = math.max(session.anchor.z - span, math.min(session.anchor.z + span, session.level))

        local spot = DeviceRules.levelPoint(
            session.position,
            direction(session.pitch, session.yaw),
            session.level,
            LEVEL_REACH
        )

        session.point = spot and { x = spot.x, y = spot.y, z = spot.z, w = session.heading + 0.0 } or nil
    else
        if raise then
            session.height = math.min(3.0, session.height + step)
        end

        if lower then
            session.height = math.max(-2.0, session.height - step)
        end

        if session.ground then
            session.point = {
                x = session.ground.x + 0.0,
                y = session.ground.y + 0.0,
                z = session.ground.z + session.height,
                w = session.heading + 0.0,
            }
        end
    end

    local point = session.point

    if session.faceStand and point then
        session.faceStand = nil

        local dx, dy = point.x - session.anchor.x, point.y - session.anchor.y

        if dx * dx + dy * dy > 0.01 then
            session.heading = math.deg(math.atan(-dx, dy)) % 360.0
            point.w = session.heading
        end
    end

    session.valid, session.reason, session.notes = validate(session)
    drawContext(session)

    local result = PlacementSteps.input(session)

    if result == 'blocked' then
        PlacementSteps.blocked()
    elseif result then
        return result
    end

    push(session)
end

local SLOT_STATES = { done = true, active = true, todo = true, add = true }

local function slotText(value)
    return type(value) == 'string' and value:sub(1, 48) or nil
end

local function slotsOf(value)
    if type(value) ~= 'table' or type(value.items) ~= 'table' then return nil end

    local items = {}
    local first = math.max(1, #value.items - 39)

    for index = first, #value.items do
        local item = value.items[index]

        if type(item) == 'table' and slotText(item.label) then
            items[#items + 1] = {
                label = slotText(item.label),
                state = SLOT_STATES[item.state] and item.state or 'todo',
                optional = item.optional == true,
                count = Util.isFinite(item.count) and math.floor(item.count) or nil,
                max = Util.isFinite(item.max) and math.floor(item.max) or nil,
            }
        end
    end

    if #items == 0 then return nil end

    local function number(key)
        return Util.isFinite(value[key]) and math.floor(value[key]) or nil
    end

    return {
        title = slotText(value.title) or '',
        items = items,
        placed = number('placed'),
        max = number('max'),
        least = number('least'),
        plural = slotText(value.plural),
        from = first > 1 and first or nil,
    }
end

PlacementCamera.slots = slotsOf
PlacementCamera.ZONE = ZONE

local function walkCloser(session, target)
    session.walking = true

    if session.ped and DoesEntityExist(session.ped) then
        FreezeEntityPosition(session.ped, false)
        SetEntityVisible(session.ped, true, false)
    end

    local spot = vector3(target.x, target.y, target.z)
    local resume, nextAt = false, 0

    while PlacementCamera.active == session and not IsEntityDead(cache.ped) do
        if IsControlJustReleased(0, 191) or IsControlJustReleased(0, 201) then
            resume = true
            break
        end

        if IsControlJustReleased(0, 73) then break end

        local now = GetGameTimer()

        if now >= nextAt then
            nextAt = now + WALK_MS
            PlacementSync.push(session, { d = #(GetEntityCoords(cache.ped) - spot) })
        end

        Wait(0)
    end

    session.walking = false

    return resume
end

function PlacementCamera.busy()
    return PlacementCamera.active ~= nil
end

function PlacementCamera.start(request, done)
    if PlacementCamera.active then
        return false, 'busy'
    end

    local ped = cache.ped

    if IsPedInAnyVehicle(ped, false) then
        return false, 'leave_vehicle'
    end

    local kind = request.kind
    local deviceSpec = kind == 'device' and DeviceRules.spec(request.device) or nil

    if kind == 'device' and not deviceSpec then
        return false, 'invalid_kind'
    end

    if kind ~= 'device' and kind ~= 'zone' and kind ~= 'prop' then
        return false, 'invalid_kind'
    end

    if kind == 'prop' and (type(request.model) ~= 'string' or not IsModelInCdimage(joaat(request.model))) then
        return false, 'model_missing'
    end

    local ring = nil

    if type(request.ring) == 'table' and Util.isFinite(request.ring.radius) then
        local low, high = request.ring.min or ZONE.min, request.ring.max or ZONE.max

        ring = { radius = math.max(low, math.min(high, request.ring.radius)), min = low, max = high }
    end

    local model = request.model

    if deviceSpec then
        model = DeviceRules.isVariant(deviceSpec, model) and model or DeviceRules.baseModel(deviceSpec)
    end

    local session = {
        kind = kind,
        adjust = kind == 'zone' and ADJUST.zone or ADJUST.object,
        lift = kind ~= 'zone',
        click = true,
        wheel = kind == 'zone' and 'radius' or nil,
        device = request.device,
        deviceSpec = deviceSpec,
        devices = request.devices or {},
        model = model,
        ring = ring,
        reach = Util.isFinite(request.reach) and request.reach > 0 and request.reach or nil,
        accent = Marker.parse(request.accent),
        marks = {},
        start = request.start,
        moving = request.moving,
        range = Util.isFinite(request.range) and request.range or Config.admin.placeRange,
        heading = (request.start and request.start.w) or GetEntityHeading(ped),
        height = 0.0,
        level = 0.0,
        snap = kind ~= 'zone' or nil,
        faceStand = deviceSpec ~= nil and request.start == nil or nil,
    }

    PlacementCamera.active = session

    local sizes = { turn = TURN, turnFine = TURN_FINE, lift = LIFT, liftFine = LIFT_FINE }

    if kind == 'zone' then
        sizes = { radius = ZONE.step, radiusFine = ZONE.fine }
    end

    local title = request.title or ''
    local slots = slotsOf(request.slots) or {
        title = request.start and locale('placement_slots_move') or locale('placement_slots_place'),
        items = { { label = title ~= '' and title or locale('placement_slots_item'), state = 'active' } },
    }

    PlacementSync.start(session, function(message)
        message.type = 'placement'
        Nui.send(message)
    end, {
        mode = 'camera',
        kind = kind,
        title = title,
        slots = slots,
        adjust = session.adjust,
        keys = { snap = session.snap ~= nil, walk = true, click = true, zone = false, skip = '' },
        sizes = sizes,
        loading = true,
        snap = session.snap,
        h = session.heading,
        r = ring and ring.radius or 0.0,
    })

    CreateThread(function()
        local ok, result = pcall(function()
            beginCamera(session)
            hideMoving(session)
            makeGhost(session)

            while PlacementCamera.active == session and not IsEntityDead(cache.ped) do
                local outcome = tick(session)

                if outcome == 'walk' then
                    local target = session.point or session.position

                    releaseGhost(session)
                    endCamera(session)
                    session.ray, session.ground, session.point, session.surface = nil, nil, nil, nil
                    Nui.send({ type = 'placement', state = 'walk' })

                    if not walkCloser(session, target) then
                        return 'cancel'
                    end

                    beginCamera(session)
                    makeGhost(session)
                    Nui.send({ type = 'placement', state = 'resume' })
                elseif outcome then
                    return outcome
                end

                Wait(0)
            end

            return 'cancel'
        end)

        releaseGhost(session)

        local confirmed = ok and result == 'confirm'

        if not confirmed then
            showMoving(session)
        end

        if PlacementCamera.active == session then
            PlacementCamera.active = nil
        end

        endCamera(session)
        Nui.send({ type = 'placement', state = 'end', result = { ok = confirmed } })
        Wait(150)

        if not ok then
            print(('[evolent_devices] placement failed: %s'):format(tostring(result)))
        end

        if confirmed then
            local point = session.point

            point.snap = session.snap

            if ring then
                point.radius = ring.radius
            end

            done(point, 'confirm', session.moving)
        else
            done(nil, 'cancelled')
        end
    end)

    return true
end

function PlacementCamera.cancel()
    PlacementCamera.active = nil
end

function PlacementCamera.restore(entity)
    giveBack(entity)
end

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end

    local session = PlacementCamera.active

    if not session then return end

    PlacementCamera.active = nil
    releaseGhost(session)
    showMoving(session)
    endCamera(session)

    if session.ped and DoesEntityExist(session.ped) then
        FreezeEntityPosition(session.ped, false)
        SetEntityVisible(session.ped, true, false)
    end
end)

return PlacementCamera
