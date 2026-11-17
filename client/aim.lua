local Bridge = require 'bridge'
local Util = require 'shared.util'
local DeviceRules = require 'shared.rules'
local Marker = require 'client.marker'
local Client = require 'client.main'
local Nui = require 'client.nui'
local DeviceUse = require 'client.use'
local PlacementSync = require 'client.placement_sync'
local PlacementSteps = require 'client.placement_steps'
local PlacementCamera = require 'client.placement'

local ItemAim = { active = nil }

local WHEEL_UP, WHEEL_DOWN, FINE_KEY = 15, 14, 19
local CONFIRM_KEYS, CANCEL_KEYS = { 191, 201 }, { 177, 194, 200, 202, 322 }

local BLOCKED = {
    14,
    15,
    16,
    17,
    24,
    25,
    37,
    44,
    45,
    140,
    141,
    142,
    143,
    177,
    191,
    194,
    199,
    200,
    201,
    202,
    257,
    263,
    322,
}

local RAY_REACH = 8.0
local ROOM_CHECK_MS = 250
local LIMIT_MS = 110000
local WARN_MS = 15000

local yes = Util.yes

local function aimDirection(rotation)
    local pitch, yaw = math.rad(rotation.x), math.rad(rotation.z)
    local flat = math.abs(math.cos(pitch))

    return vector3(-math.sin(yaw) * flat, math.cos(yaw) * flat, math.sin(pitch))
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

    local _, hit, at, normal = GetShapeTestResult(handle)

    if yes(hit) and at then
        return at, normal
    end

    return nil
end

local function anyPressed(keys)
    for _, key in ipairs(keys) do
        if IsDisabledControlJustPressed(0, key) then return true end
    end

    return false
end

function ItemAim.faceHeading(from, point)
    local dx, dy = point.x - from.x, point.y - from.y

    if dx * dx + dy * dy < 0.0001 then
        return 0.0
    end

    return math.deg(math.atan(-dx, dy)) % 360.0
end

local function makeGhost(session)
    local hash = session.model and PlacementSync.loadModel(session.model)

    if not hash then return false end

    local at = GetEntityCoords(cache.ped)
    local object = CreateObjectNoOffset(hash, at.x, at.y, at.z - 20.0, false, false, false)

    SetModelAsNoLongerNeeded(hash)

    if not object or object == 0 then return false end

    SetEntityAsMissionEntity(object, true, true)
    SetEntityCollision(object, false, false)
    FreezeEntityPosition(object, true)
    SetEntityAlpha(object, 170, false)
    SetEntityVisible(object, false, false)
    session.ghost = object

    return true
end

local function release(session)
    if session.ghost and DoesEntityExist(session.ghost) then
        DeleteEntity(session.ghost)
    end

    session.ghost = nil
end

local function room(session, point)
    local now = GetGameTimer()
    local last = session.roomAt

    if last and now - session.roomTime < ROOM_CHECK_MS and math.abs(last.x - point.x) + math.abs(last.y - point.y) + math.abs(last.z - point.z) < 0.02 and math.abs(last.w - point.w) < 0.5 then
        return session.above
    end

    session.roomAt, session.roomTime = { x = point.x, y = point.y, z = point.z, w = point.w }, now

    local spot = DeviceRules.useSpot(point, session.spec)

    local floor = probe(
        { x = spot.x, y = spot.y, z = point.z + 0.25 },
        { x = spot.x, y = spot.y, z = point.z - session.rules.tableMax - 0.3 },
        session.ghost
    )

    session.above = floor and point.z - floor.z or nil

    return session.above
end

function ItemAim.validate(session)
    local point = session.point

    session.blocker = nil

    if not point then
        return false, locale('item_aim_surface')
    end

    local ped = GetEntityCoords(cache.ped)

    if #(vector3(point.x, point.y, point.z) - ped) > session.rules.range then
        return false, locale('item_aim_far')
    end

    local notes = {}

    if session.rules.surface then
        local surface = DeviceRules.surface(session.normal)

        if surface == 'steep' then
            return false, locale('item_aim_steep')
        end

        if surface == 'sloped' then
            notes[#notes + 1] = locale('device_kept_level')
        end

        local above = room(session, point)
        local rules = session.rules

        if not above or above < rules.tableMin or above > rules.tableMax then
            return false, locale('item_aim_table', ('%g'):format(rules.tableMin), ('%g'):format(rules.tableMax)), notes
        end
    end

    local spaced, blocker = DeviceRules.spacingOk(session.devices, point, session.kind)

    if not spaced then
        session.blocker = blocker

        return false, locale('reason_overlap'), notes
    end

    return true, nil, notes
end

local function aim(session)
    local fine = IsDisabledControlPressed(0, FINE_KEY)
    local turn = fine and 1.0 or 5.0

    if IsDisabledControlJustPressed(0, WHEEL_UP) then
        session.turn = (session.turn + turn) % 360.0
    end

    if IsDisabledControlJustPressed(0, WHEEL_DOWN) then
        session.turn = (session.turn - turn) % 360.0
    end

    local from = GetFinalRenderedCamCoord()
    local to = from + aimDirection(GetFinalRenderedCamRot(2)) * RAY_REACH
    local hit, normal = probe(from, to, session.ghost)

    if not hit then
        session.point, session.normal = nil, nil

        return
    end

    local base = ItemAim.faceHeading(GetEntityCoords(cache.ped), hit)

    session.point = { x = hit.x + 0.0, y = hit.y + 0.0, z = hit.z + 0.0, w = (base + session.turn) % 360.0 }
    session.normal = normal
end

local function toneOf(session)
    if not session.valid then return 'bad' end
    if session.notes and #session.notes > 0 then return 'warn' end

    return nil
end

local function draw(session)
    local ghost = session.ghost
    local point = session.point
    local stand = nil

    if point then
        stand = DeviceRules.useSpot(point, session.spec)
        stand.z = session.above and point.z - session.above or point.z - 1.0
    end

    Marker.placement(session.marks, {
        point = point,
        tone = point and toneOf(session) or nil,
        model = session.model,
        front = true,
        stand = stand,
        others = session.devices,
        blocker = session.blocker,
    })

    if not point then
        if ghost and DoesEntityExist(ghost) then
            SetEntityVisible(ghost, false, false)
        end

        return
    end

    if ghost and DoesEntityExist(ghost) then
        SetEntityVisible(ghost, true, false)
        SetEntityCoordsNoOffset(ghost, point.x, point.y, point.z, false, false, false)
        SetEntityHeading(ghost, point.w)
        SetEntityAlpha(ghost, session.valid and 180 or 110, false)
    end
end

local function hud(session, now)
    local remain = LIMIT_MS - (now - session.since)

    PlacementSync.push(session, {
        loading = false,
        valid = session.valid == true,
        reason = session.reason or '',
        notes = table.concat(session.notes or {}, '\n'),
        table = session.point and session.above or 0.0,
        h = session.point and session.point.w or 0.0,
        left = remain <= WARN_MS and math.max(0, math.ceil(remain / 1000)) or -1,
    })
end

local function stopReason(session)
    local ped = cache.ped

    if IsEntityDead(ped) or Bridge.isDown() then
        return 'device_down'
    end

    if IsPedInAnyVehicle(ped, false) then
        return 'device_vehicle'
    end

    if IsPedRagdoll(ped) or Nui.visible or DeviceUse.active() or PlacementCamera.busy() then
        return 'cancelled'
    end

    if GetGameTimer() - session.since > LIMIT_MS then
        return 'item_ticket'
    end

    return nil
end

function ItemAim.tick(session)
    for _, control in ipairs(BLOCKED) do
        DisableControlAction(0, control, true)
    end

    DisablePlayerFiring(cache.playerId, true)

    local stop = stopReason(session)

    if stop then
        return 'cancel', stop
    end

    aim(session)
    session.valid, session.reason, session.notes = ItemAim.validate(session)
    draw(session)
    hud(session, GetGameTimer())

    if anyPressed(CANCEL_KEYS) then
        return 'cancel'
    end

    if anyPressed(CONFIRM_KEYS) then
        if session.valid then
            return 'confirm'
        end

        PlacementSteps.blocked()
    end

    return nil
end

function ItemAim.busy()
    return ItemAim.active ~= nil
end

function ItemAim.cancel()
    ItemAim.active = nil
end

function ItemAim.start(request, done)
    if ItemAim.active then
        return false, 'item_busy'
    end

    local spec = DeviceRules.spec(request.kind)

    if not spec or type(request.rules) ~= 'table' then
        return false, 'invalid_kind'
    end

    local session = {
        kind = request.kind,
        spec = spec,
        model = request.model,
        rules = request.rules,
        devices = request.devices or {},
        marks = {},
        turn = 0.0,
        since = GetGameTimer(),
    }

    ItemAim.active = session

    PlacementSync.start(session, function(message)
        message.type = 'placement'
        Nui.send(message)
    end, {
        mode = 'walkup',
        kind = 'item',
        title = request.title or locale('kind_' .. request.kind),
        loading = true,
    })

    CreateThread(function()
        local ok, outcome, reason = pcall(function()
            if not makeGhost(session) then
                return 'cancel', 'model_missing'
            end

            while ItemAim.active == session do
                local result, why = ItemAim.tick(session)

                if result then
                    return result, why
                end

                Wait(0)
            end

            return 'cancel'
        end)

        release(session)

        if ItemAim.active == session then
            ItemAim.active = nil
        end

        Nui.send({ type = 'placement', state = 'end', result = { ok = ok and outcome == 'confirm' } })

        if not ok then
            print(('[evolent_devices] placing failed: %s'):format(tostring(outcome)))
        end

        if ok and outcome == 'confirm' then
            done(session.point)

            return
        end

        if reason and reason ~= 'cancelled' then
            Client.notify(Client.reasonText(reason), 'error')
        end

        done(nil, reason or 'cancelled')
    end)

    return true
end

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end

    local session = ItemAim.active

    if not session then return end

    ItemAim.active = nil
    release(session)
end)

return ItemAim
