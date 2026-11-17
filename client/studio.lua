local Config = require 'config'
local Integrations = require 'integrations'
local Util = require 'shared.util'
local DeviceRules = require 'shared.rules'
local Nui = require 'client.nui'
local DeviceScreens = require 'client.screens'

local DeviceStudio = {}

local COVER_MS, PAGE_MS, UNCOVER_MS = 200, 300, 200
local FREEZE_MS = 1500
local RETURN_MS, UNFREEZE_MS = 1500, 3000
local MODEL_MS, FLOOR_MS = 10000, 3000
local SETTLE_FIRST_MS, SETTLE_MS, SETTLE_DROP, SETTLE_STILL, SETTLE_FELL = 250, 2500, 0.25, 0.03, 1.0
local SHOW_FRAMES = 2
local SMOOTH = 10.0
local TEXTURE_SIZE = 64
local ROOM_HALF, ROOM_HIGH, POOL_HALF = 45.0, 30.0, 9.0
local FLOOR_DROP, POOL_LIFT, SHADOW_LIFT, SHADOW_SCALE = 0.03, 0.01, 0.02, 1.3
local FAR = 38.0
local FROZEN_CLOCK, DEFAULT_CLOCK = 99999999, 2000
local BEZEL = { 11, 11, 14 }
local WALL = { 10, 10, 15 }
local POOL = { 36, 36, 44 }
local LIGHT = { 225, 232, 245 }
local FLOOR_MODELS = { 'stt_prop_stunt_bblock_huge_01', 'stt_prop_stunt_bblock_lrg1' }
local SET_MODEL, SET_LOD = 'evd_studio_set', 1000
local KEY_BYTES = 40
local CARS = 80
local STAMP = GetGameTimer()
local V = DeviceRules.vector

local textures = nil
local rests = {}

local function current(state, studio, token)
    return state.studio == studio and not studio.ending and (token == nil or studio.token == token)
end

local function send(message)
    DeviceScreens.sendOwn(message)
end

function DeviceStudio.settingsFor(record)
    if type(record) ~= 'table' or type(record.spec) ~= 'table' then return nil end

    return DeviceRules.studio(record.kind)
end

function DeviceStudio.offer(state, cars, paints)
    if not state or not state.studioSettings or type(cars) ~= 'table' then return false end
    if paints ~= nil and not DeviceRules.paletteOk(paints) then return false end

    local list, count = {}, 0

    for _, car in ipairs(cars) do
        if type(car) == 'table' and type(car.key) == 'string' and #car.key > 0 and #car.key <= KEY_BYTES and DeviceRules.studioModel(car.model) and count < CARS then
            local own = {}

            for _, id in ipairs(type(car.paints) == 'table' and car.paints or {}) do
                if type(id) == 'string' and #own < CARS then
                    own[#own + 1] = id
                end
            end

            list[car.key] = { model = car.model, paints = own }
            count = count + 1
        end
    end

    state.studioCars = list

    if paints ~= nil then
        state.studioPalette = paints
    end

    return true
end

local function palette(state)
    return state.studioPalette or Config.devices.studio.paints or {}
end

function DeviceStudio.rect(state)
    return state.studio and state.studio.rect or nil
end

function DeviceStudio.holds(state)
    return state.studio ~= nil
end

local function makeTextures()
    if textures ~= nil then
        return textures or nil
    end

    textures = false

    local name = ('evdev_studio_%d'):format(STAMP)
    local txd = CreateRuntimeTxd(name)
    local pool = CreateRuntimeTexture(txd, 'pool', TEXTURE_SIZE, TEXTURE_SIZE)
    local shadow = CreateRuntimeTexture(txd, 'shadow', TEXTURE_SIZE, TEXTURE_SIZE)

    if not pool or pool == 0 or not shadow or shadow == 0 then return nil end

    local middle = (TEXTURE_SIZE - 1) / 2.0

    for y = 0, TEXTURE_SIZE - 1 do
        for x = 0, TEXTURE_SIZE - 1 do
            local distance = math.min(1.0, math.sqrt(((x - middle) / middle) ^ 2 + ((y - middle) / middle) ^ 2))
            local glow = (1.0 - distance * distance) ^ 2

            SetRuntimeTexturePixel(pool, x, y, POOL[1], POOL[2], POOL[3], math.floor(255 * glow + 0.5))

            local edge = math.max(0.0, math.min(1.0, (distance - 0.45) / 0.55))

            SetRuntimeTexturePixel(
                shadow,
                x,
                y,
                0,
                0,
                0,
                math.floor(215 * (1.0 - edge * edge * (3.0 - 2.0 * edge)) + 0.5)
            )
        end
    end

    CommitRuntimeTexture(pool)
    CommitRuntimeTexture(shadow)
    textures = name

    return name
end

local function roomOf(spot)
    local floor, top, half = spot.z - FLOOR_DROP, spot.z - FLOOR_DROP + ROOM_HIGH, ROOM_HALF

    local low = {
        { x = spot.x - half, y = spot.y - half, z = floor },
        { x = spot.x + half, y = spot.y - half, z = floor },
        { x = spot.x + half, y = spot.y + half, z = floor },
        { x = spot.x - half, y = spot.y + half, z = floor },
    }

    local high = {}

    for index, corner in ipairs(low) do
        high[index] = { x = corner.x, y = corner.y, z = top }
    end

    return {
        { low[1], low[2], low[3], low[4] },
        { high[1], high[2], high[3], high[4] },
        { low[1], low[2], high[2], high[1] },
        { low[2], low[3], high[3], high[2] },
        { low[3], low[4], high[4], high[3] },
        { low[4], low[1], high[1], high[4] },
    }
end

local function poly(a, b, c, color)
    DrawPoly(a.x, a.y, a.z, b.x, b.y, b.z, c.x, c.y, c.z, color[1], color[2], color[3], 255)
end

local function textured(a, b, c, ua, va, ub, vb, uc, vc, txd, txn)
    DrawTexturedPoly(
        a.x,
        a.y,
        a.z,
        b.x,
        b.y,
        b.z,
        c.x,
        c.y,
        c.z,
        255,
        255,
        255,
        255,
        txd,
        txn,
        ua + 0.0,
        va + 0.0,
        1.0,
        ub + 0.0,
        vb + 0.0,
        1.0,
        uc + 0.0,
        vc + 0.0,
        1.0
    )
end

local function flatQuad(centre, z, halfX, halfY, txd, txn)
    local a = { x = centre.x - halfX, y = centre.y + halfY, z = z }
    local b = { x = centre.x + halfX, y = centre.y + halfY, z = z }
    local c = { x = centre.x + halfX, y = centre.y - halfY, z = z }
    local d = { x = centre.x - halfX, y = centre.y - halfY, z = z }

    textured(a, b, c, 0, 0, 1, 0, 1, 1, txd, txn)
    textured(a, c, d, 0, 0, 1, 1, 0, 1, txd, txn)
    textured(c, b, a, 1, 1, 1, 0, 0, 0, txd, txn)
    textured(d, c, a, 0, 1, 1, 1, 0, 0, txd, txn)
end

local function drawSet(studio)
    local built = studio.set ~= nil and DoesEntityExist(studio.set)

    for _, face in ipairs(built and {} or studio.room) do
        local a, b, c, d = face[1], face[2], face[3], face[4]

        poly(a, b, c, WALL)
        poly(a, c, d, WALL)
        poly(c, b, a, WALL)
        poly(d, c, a, WALL)
    end

    local txd = textures

    if not txd then return end

    local spot = studio.settings.spot

    flatQuad(spot, spot.z - FLOOR_DROP + POOL_LIFT, POOL_HALF, POOL_HALF, txd, 'pool')

    local car = studio.car

    if car and car.ready and car.size then
        flatQuad(
            car.middle,
            spot.z - FLOOR_DROP + SHADOW_LIFT,
            car.size.x / 2.0 * SHADOW_SCALE,
            car.size.y / 2.0 * SHADOW_SCALE,
            txd,
            'shadow'
        )
    end
end

local function drawLights(fit, from)
    local middle, radius = fit.middle, fit.radius

    DrawSpotLight(
        middle.x + 0.0,
        middle.y + 0.0,
        middle.z + radius * 2.2,
        0.0,
        0.0,
        -1.0,
        LIGHT[1],
        LIGHT[2],
        LIGHT[3],
        radius * 4.0,
        5.0,
        0.0,
        60.0,
        1.0
    )

    local toCamera = V.sub(from, middle)

    toCamera.z = 0.0
    toCamera = V.length(toCamera) > 0.01 and V.unit(toCamera) or { x = 0.0, y = 1.0, z = 0.0 }

    local right = { x = -toCamera.y, y = toCamera.x, z = 0.0 }

    for _, side in ipairs({ -1.0, 1.0 }) do
        local at = V.add(V.add(middle, V.scale(right, side * radius * 1.4)), V.scale(toCamera, radius * 0.9))

        DrawLightWithRange(at.x + 0.0, at.y + 0.0, at.z + 0.9, LIGHT[1], LIGHT[2], LIGHT[3], radius * 3.0, 1.8)
    end

    local rim = V.sub(middle, V.scale(toCamera, radius * 1.3))

    DrawLightWithRange(rim.x + 0.0, rim.y + 0.0, rim.z + 1.2, LIGHT[1], LIGHT[2], LIGHT[3], radius * 2.5, 1.2)
end

local function drawBands(studio)
    if studio.freeze ~= 'off' or (studio.bands or 0) <= 0 then return end

    local alpha = math.floor(math.min(1.0, studio.bands) * 255 + 0.5)

    for _, band in ipairs(studio.bandRects) do
        DrawRect(band.x, band.y, band.w, band.h, BEZEL[1], BEZEL[2], BEZEL[3], alpha)
    end
end

local function holdLook(state, studio)
    local settings = studio.settings
    local from, to, progress = GetWeatherTypeTransition()

    studio.look = { clock = GetMillisecondsPerGameMinute(), from = from, to = to, progress = progress }
    Integrations.weatherPause(true)

    if state.token then
        TriggerServerEvent('evdev:device:studio', state.token, true)
        studio.held = true
    end

    NetworkOverrideClockMillisecondsPerGameMinute(FROZEN_CLOCK)
    NetworkOverrideClockTime(settings.hour, 0, 0)
    ClearWeatherTypePersist()
    SetRainLevel(0.0)
    SetWeatherTypeNowPersist(settings.weather)
    SetOverrideWeather(settings.weather)
end

local function restoreLook(studio)
    local look = studio.look

    studio.look = nil

    if not look then return end

    NetworkClearClockTimeOverride()

    local clock = tonumber(look.clock)

    NetworkOverrideClockMillisecondsPerGameMinute(clock and clock > 0 and math.floor(clock) or DEFAULT_CLOCK)
    ClearOverrideWeather()
    ClearWeatherTypePersist()
    SetRainLevel(-1.0)

    if look.from and look.to then
        SetWeatherTypeTransition(look.from, look.to, (tonumber(look.progress) or 0.0) + 0.0)
    end

    Integrations.weatherPause(false)
end

local function removeCar(studio)
    local car = studio.car

    studio.car = nil

    if car and DoesEntityExist(car.entity) then
        DeleteEntity(car.entity)
    end
end

local function clearScene(state, studio)
    removeCar(studio)

    if studio.floor and DoesEntityExist(studio.floor) then
        DeleteEntity(studio.floor)
    end

    studio.floor = nil

    if studio.set and DoesEntityExist(studio.set) then
        DeleteEntity(studio.set)
    end

    studio.set = nil

    if studio.loaded then
        SetModelAsNoLongerNeeded(studio.loaded.hash)
        studio.loaded = nil
    end

    if studio.focus then
        ClearFocus()
        studio.focus = false
    end

    restoreLook(studio)

    if studio.held then
        studio.held = false

        if state.token then
            TriggerServerEvent('evdev:device:studio', state.token, false)
        end
    end
end

local function unfreezeLater(ped, now)
    local DeviceUse = require 'client.use'

    if not DoesEntityExist(ped) then return end

    if now then
        FreezeEntityPosition(ped, false)

        return
    end

    CreateThread(function()
        local deadline = GetGameTimer() + UNFREEZE_MS

        while DoesEntityExist(ped) and not HasCollisionLoadedAroundEntity(ped) and GetGameTimer() < deadline do
            local at = GetEntityCoords(ped)

            RequestCollisionAtCoord(at.x + 0.0, at.y + 0.0, at.z + 0.0)
            Wait(0)
        end

        if DoesEntityExist(ped) and not DeviceUse.active() then
            FreezeEntityPosition(ped, false)
        end
    end)
end

local function paintCar(vehicle, id, paints)
    for _, paint in ipairs(paints) do
        if paint.id == id then
            SetVehicleColours(vehicle, paint.primary, paint.secondary)

            return true
        end
    end

    return false
end

local function carMessage(car)
    return {
        type = 'studioCar',
        key = car.key,
        doors = car.doors,
        open = car.open,
        lights = car.lights,
        paint = car.paint or '',
        paints = car.paints,
    }
end

local function load(state, studio, token, model)
    CreateThread(function()
        local hash = joaat(model)

        if not IsModelInCdimage(hash) or not IsModelAVehicle(hash) then
            if current(state, studio, token) then
                studio.problem = 'missing'
            end

            return
        end

        RequestModel(hash)

        local deadline = GetGameTimer() + MODEL_MS

        while current(state, studio, token) and not HasModelLoaded(hash) and GetGameTimer() < deadline do
            Wait(0)
        end

        if not current(state, studio, token) or not HasModelLoaded(hash) then
            SetModelAsNoLongerNeeded(hash)

            if current(state, studio, token) then
                studio.problem = 'timeout'
            end

            return
        end

        studio.loaded = { token = token, hash = hash }
    end)
end

local function wantFor(state, data)
    local key = data.key

    if type(key) ~= 'string' or #key == 0 or #key > KEY_BYTES then return nil end

    local car = state.studioCars and state.studioCars[key]

    if not car then return nil end

    local model, own = car.model, car.paints
    local colours = palette(state)
    local paints = DeviceRules.studioPaints(own, colours)
    local preset = type(own) == 'table' and paints[1] ~= nil and Util.contains(own, paints[1]) and paints[1] or nil

    return { key = key, model = model:lower(), paints = paints, preset = preset, palette = colours }
end

local function want(state, studio, wanted)
    if studio.want and studio.want.key == wanted.key then return end

    studio.want = wanted
    studio.token = studio.token + 1
    studio.problem = nil

    if studio.loaded then
        SetModelAsNoLongerNeeded(studio.loaded.hash)
        studio.loaded = nil
    end

    local car = studio.car

    if car and car.ready and car.key == wanted.key then
        car.token = studio.token

        return
    end

    send({ type = 'studio', state = 'loading', key = wanted.key })
    load(state, studio, studio.token, wanted.model)
end

local function ensureFloor(state, studio)
    if studio.floor or studio.noFloor then return end

    local spot = studio.settings.spot

    for _, name in ipairs(FLOOR_MODELS) do
        local hash = joaat(name)

        if IsModelInCdimage(hash) then
            RequestModel(hash)

            local deadline = GetGameTimer() + FLOOR_MS

            while current(state, studio) and not HasModelLoaded(hash) and GetGameTimer() < deadline do
                Wait(0)
            end

            if not current(state, studio) then
                SetModelAsNoLongerNeeded(hash)

                return
            end

            if HasModelLoaded(hash) then
                local low, high = GetModelDimensions(hash)

                local floor = CreateObjectNoOffset(
                    hash,
                    spot.x - (low.x + high.x) / 2.0,
                    spot.y - (low.y + high.y) / 2.0,
                    spot.z - high.z,
                    false,
                    false,
                    false
                )

                SetModelAsNoLongerNeeded(hash)

                if floor and floor ~= 0 then
                    FreezeEntityPosition(floor, true)
                    SetEntityVisible(floor, false, false)
                    studio.floor = floor

                    return
                end
            else
                SetModelAsNoLongerNeeded(hash)
            end
        end
    end

    studio.noFloor = true
end

local function ensureSet(state, studio)
    if studio.set or studio.noSet then return end

    studio.noSet = true

    local hash = joaat(SET_MODEL)

    if not IsModelInCdimage(hash) then return end

    RequestModel(hash)

    local deadline = GetGameTimer() + FLOOR_MS

    while current(state, studio) and not HasModelLoaded(hash) and GetGameTimer() < deadline do
        Wait(0)
    end

    if not current(state, studio) or not HasModelLoaded(hash) then
        SetModelAsNoLongerNeeded(hash)

        return
    end

    local spot = studio.settings.spot
    local set = CreateObjectNoOffset(hash, spot.x, spot.y, spot.z - FLOOR_DROP, false, false, false)

    SetModelAsNoLongerNeeded(hash)

    if not set or set == 0 then return end

    FreezeEntityPosition(set, true)
    SetEntityCollision(set, false, false)
    SetEntityLodDist(set, SET_LOD)
    studio.set, studio.noSet = set, false
end

local function settle(state, studio, car)
    local vehicle, spot = car.entity, studio.settings.spot
    local low = car.low
    local base = spot.z - low.z
    local rest = rests[car.hash]

    if rest or not studio.floor then
        SetEntityCoordsNoOffset(vehicle, spot.x, spot.y, rest and spot.z + rest.z or base, false, false, false)
        SetEntityRotation(vehicle, rest and rest.pitch or 0.0, rest and rest.roll or 0.0, 0.0, 2, false)

        return true
    end

    SetEntityCoordsNoOffset(vehicle, spot.x, spot.y, base + SETTLE_DROP, false, false, false)
    SetEntityRotation(vehicle, 0.0, 0.0, 0.0, 2, false)
    SetEntityCollision(vehicle, true, true)
    FreezeEntityPosition(vehicle, false)
    SetVehicleOnGroundProperly(vehicle)
    Wait(SETTLE_FIRST_MS)

    local deadline = GetGameTimer() + SETTLE_MS

    while current(state, studio, car.token) and DoesEntityExist(vehicle) and GetGameTimer() < deadline and #GetEntityVelocity(vehicle) > SETTLE_STILL do
        Wait(50)
    end

    if not current(state, studio, car.token) or not DoesEntityExist(vehicle) then return false end

    FreezeEntityPosition(vehicle, true)
    SetEntityCollision(vehicle, false, false)

    local at, rotation = GetEntityCoords(vehicle), GetEntityRotation(vehicle, 2)

    if spot.z - (at.z + low.z) < SETTLE_FELL then
        rests[car.hash] = { z = at.z - spot.z, pitch = rotation.x, roll = rotation.y }
        SetEntityCoordsNoOffset(vehicle, spot.x, spot.y, at.z, false, false, false)
    else
        SetEntityCoordsNoOffset(vehicle, spot.x, spot.y, base, false, false, false)
        SetEntityRotation(vehicle, 0.0, 0.0, 0.0, 2, false)
    end

    return true
end

local function dress(car)
    local vehicle = car.entity

    car.valid, car.doors = {}, {}

    for _, part in ipairs(DeviceRules.STUDIO_PARTS) do
        local any = false

        for _, index in ipairs(DeviceRules.studioDoors(part)) do
            car.valid[index] = Util.yes(GetIsDoorValid(vehicle, index))
            any = any or car.valid[index]

            if car.valid[index] then
                SetVehicleDoorShut(vehicle, index, true)
            end
        end

        car.doors[part] = any
    end

    car.open = { front = false, rear = false, bonnet = false, boot = false }
    car.lights = false
    SetVehicleLights(vehicle, 1)
    SetVehicleInteriorlight(vehicle, false)
    car.paint = ''

    if car.preset and paintCar(vehicle, car.preset, car.palette) then
        car.paint = car.preset
    end
end

local function measure(studio, car)
    local low, high = car.low, car.high

    local middle = GetOffsetFromEntityInWorldCoords(
        car.entity,
        (low.x + high.x) / 2.0,
        (low.y + high.y) / 2.0,
        (low.z + high.z) / 2.0
    )

    car.middle = { x = middle.x, y = middle.y, z = middle.z }
    car.radius = V.length(V.sub(high, low)) / 2.0
    car.half = { x = (high.x - low.x) / 2.0, y = (high.y - low.y) / 2.0, z = (high.z - low.z) / 2.0 }
    car.size = { x = high.x - low.x, y = high.y - low.y }
    car.floor = studio.settings.spot.z
end

local function spawn(state, studio, loaded)
    studio.spawning = true

    local wanted = studio.want

    CreateThread(function()
        local token, hash = loaded.token, loaded.hash

        ensureSet(state, studio)
        ensureFloor(state, studio)

        if not current(state, studio, token) then
            SetModelAsNoLongerNeeded(hash)
            studio.spawning = false

            return
        end

        local spot = studio.settings.spot
        local vehicle = CreateVehicle(hash, spot.x, spot.y, spot.z + 1.0, 0.0, false, false)

        SetModelAsNoLongerNeeded(hash)

        if not vehicle or vehicle == 0 then
            studio.problem, studio.spawning = 'spawn', false

            return
        end

        removeCar(studio)

        local low, high = GetModelDimensions(hash)

        local car = {
            entity = vehicle,
            hash = hash,
            token = token,
            key = wanted.key,
            paints = wanted.paints,
            preset = wanted.preset,
            palette = wanted.palette,
            low = low,
            high = high,
        }

        studio.car = car
        FreezeEntityPosition(vehicle, true)
        SetEntityCollision(vehicle, false, false)
        SetVehicleModKit(vehicle, 0)
        SetVehicleDirtLevel(vehicle, 0.0)
        SetVehicleEngineOn(vehicle, false, true, true)

        if settle(state, studio, car) and studio.car == car then
            dress(car)
            measure(studio, car)
            car.ready = true
        end

        studio.spawning = false
    end)
end

local function aim(studio, seconds)
    local view, goal = studio.view, studio.goal
    local share = DeviceRules.easeShare(seconds, SMOOTH)

    view.yaw = (view.yaw + DeviceRules.angleTo(view.yaw, goal.yaw) * share) % 360.0
    view.pitch = view.pitch + (goal.pitch - view.pitch) * share
    view.zoom = view.zoom + (goal.zoom - view.zoom) * share

    local fit, car = studio.fit, studio.car

    if car and car.ready and car.token == studio.token then
        fit.middle = V.add(fit.middle, V.scale(V.sub(car.middle, fit.middle), share))
        fit.half = V.add(fit.half, V.scale(V.sub(car.half, fit.half), share))
        fit.radius = fit.radius + (car.radius - fit.radius) * share
        fit.floor = car.floor
    end

    local fov = studio.settings.fov
    local from, target = DeviceRules.studioFrame(fit, view, fov, GetAspectRatio(false), studio.screen, FAR)

    SetCamCoord(studio.cam, from.x + 0.0, from.y + 0.0, from.z + 0.0)
    PointCamAtCoord(studio.cam, target.x + 0.0, target.y + 0.0, target.z + 0.0)
    SetCamFov(studio.cam, fov + 0.0)

    return from
end

local function uncover(studio, now, phase)
    studio.phase, studio.since = phase or 'return', now
    studio.uncoverAt = now - math.floor((1.0 - math.min(1.0, studio.bands or 0.0)) * UNCOVER_MS)
end

local function start(state, now)
    local settings = state.studioSettings

    local studio = {
        settings = settings,
        phase = 'cover',
        since = now,
        bands = 0.0,
        token = 0,
        rect = state.rect,
        view = { yaw = settings.yaw, pitch = settings.pitch, zoom = 1.0 },
        goal = { yaw = settings.yaw, pitch = settings.pitch, zoom = 1.0 },
    }

    studio.bandRects = DeviceRules.studioBands(studio.rect)
    studio.screen = DeviceRules.studioScreen(studio.rect, state.studioWindow, state.spec.dui)
    studio.freeze, studio.freezeAt = 'wait', now
    state.studio = studio
    Nui.send({ type = 'deviceStudio', on = true, freeze = DeviceRules.freezeRect(studio.rect) })
    want(state, studio, state.studioWant)
end

local function enter(state, studio)
    local settings = studio.settings
    local spot = settings.spot
    local camera = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)

    if not camera or camera == 0 then
        studio.problem = 'camera'

        return
    end

    makeTextures()
    studio.room = roomOf(spot)

    if not state.frozen then
        FreezeEntityPosition(state.ped, true)
        state.frozen, studio.froze = true, true
    end

    SetFocusPosAndVel(spot.x, spot.y, spot.z, 0.0, 0.0, 0.0)
    studio.focus = true
    SetCamFov(camera, settings.fov + 0.0)
    SetCamUseShallowDofMode(camera, false)
    SetCamDofStrength(camera, 0.0)
    SetCamMotionBlurStrength(camera, 0.0)
    SetCamCoord(camera, spot.x, spot.y + 8.0, spot.z + 1.5)
    PointCamAtCoord(camera, spot.x, spot.y, spot.z + 0.6)

    if state.camera then
        SetCamActive(state.camera, false)
    end

    SetCamActive(camera, true)
    RenderScriptCams(true, false, 0, true, true)
    studio.cam, studio.live, studio.entered = camera, true, true
    holdLook(state, studio)
    studio.phase = 'live'
end

local function back(state, studio, now)
    if studio.cam then
        SetCamActive(studio.cam, false)

        if state.camera then
            SetCamActive(state.camera, true)
        end

        RenderScriptCams(true, false, 0, true, true)
        DestroyCam(studio.cam, false)
    end

    studio.cam, studio.live = nil, false
    clearScene(state, studio)
    studio.phase, studio.since, studio.uncoverAt = 'return', now, nil
end

local function finish(state, studio)
    local DeviceUse = require 'client.use'

    clearScene(state, studio)

    if studio.froze and state.frozen then
        FreezeEntityPosition(state.ped, false)
        state.frozen = false
    end

    state.studio = nil
    state.mappingAt = 0
    Nui.send({ type = 'deviceStudio', on = false })

    if studio.thenLeave then
        DeviceUse.leave()
    end
end

local function groundBack(state)
    local ped = state.ped
    local at = GetEntityCoords(ped)

    RequestCollisionAtCoord(at.x + 0.0, at.y + 0.0, at.z + 0.0)

    if not HasCollisionLoadedAroundEntity(ped) then return false end

    local interior = GetInteriorFromEntity(ped)

    return not interior or interior == 0 or IsInteriorReady(interior)
end

local function ready(state)
    local wanted = state.studioWant

    return state.stage == 'using' and state.studioSettings ~= nil and state.hud == true and (state.viewAlpha or 0) >= 1.0
        and state.rect ~= nil and state.studioWindow ~= nil and wanted ~= nil and state.studioFailed ~= wanted.key and DeviceScreens.ready()
end

local function failed(state, studio, now)
    local key = studio.want and studio.want.key or nil

    studio.problem = nil
    send({ type = 'studio', state = 'failed', key = key })
    state.studioFailed = key

    if studio.phase == 'cover' then
        studio.ending = true
        uncover(studio, now)
    end
end

local function liveFrame(state, studio)
    if GetRenderingCam() ~= studio.cam then
        SetCamActive(studio.cam, true)
        RenderScriptCams(true, false, 0, true, true)
    end

    BusyspinnerOff()
    ThefeedHideThisFrame()
    NetworkOverrideClockTime(studio.settings.hour, 0, 0)

    local loaded = studio.loaded

    if loaded and not studio.spawning and studio.phase == 'live' then
        studio.loaded = nil
        spawn(state, studio, loaded)
    end

    local car = studio.car

    if studio.phase == 'live' and car and car.ready and car.token == studio.token and studio.shown ~= car.token then
        if not studio.fit then
            studio.fit = { middle = car.middle, half = car.half, radius = car.radius, floor = car.floor }
        end

        studio.showFrames = (studio.showFrames or 0) + 1

        if studio.showFrames > SHOW_FRAMES then
            studio.showFrames, studio.shown = 0, car.token
            studio.openAt = studio.openAt or GetGameTimer()
            send(carMessage(car))
            send({ type = 'studio', state = 'on', key = car.key })
        end
    end

    drawSet(studio)

    if studio.fit then
        drawLights(studio.fit, aim(studio, GetFrameTime()))
    end
end

function DeviceStudio.frame(state, now)
    local studio = state.studio

    if not studio then
        if ready(state) then
            start(state, now)
        end

        return
    end

    if studio.problem then
        failed(state, studio, now)
    end

    local phase = studio.phase

    if phase == 'cover' and studio.freeze == 'wait' and now - studio.freezeAt >= FREEZE_MS then
        studio.freeze, studio.since = 'off', now
    end

    if phase == 'cover' then
        if studio.freeze == 'off' then
            studio.bands = DeviceRules.fadeShare(now - studio.since, COVER_MS)
        elseif studio.freeze == 'on' then
            studio.bands = 1.0
        end

        if studio.bands >= 1.0 and studio.loaded and studio.loaded.token == studio.token then
            enter(state, studio)
        end
    elseif phase == 'live' then
        if studio.freeze == 'off' and studio.openAt then
            studio.bands = 1.0 - DeviceRules.fadeShare(now - studio.openAt, UNCOVER_MS)
        end
    elseif phase == 'exit' then
        studio.bands = math.max(studio.bands or 0.0, DeviceRules.fadeShare(now - studio.since, PAGE_MS))

        if now - studio.since >= PAGE_MS then
            back(state, studio, now)
        end
    elseif phase == 'return' then
        if not studio.uncoverAt and (groundBack(state) or now - studio.since >= RETURN_MS) then
            studio.uncoverAt = now
        end

        if studio.uncoverAt then
            studio.bands = studio.freeze == 'off' and 1.0 - DeviceRules.fadeShare(now - studio.uncoverAt, UNCOVER_MS) or 0.0

            if studio.bands <= 0 then
                drawBands(studio)
                finish(state, studio)

                return
            end
        end
    end

    if studio.live then
        liveFrame(state, studio)
    end

    drawBands(studio)
end

function DeviceStudio.frozen(state, ok)
    local studio = state and state.studio

    if not studio or studio.freeze ~= 'wait' then return end

    studio.freeze = ok == true and 'on' or 'off'
    studio.since = GetGameTimer()
end

function DeviceStudio.action(state, data)
    if not state.studioSettings or type(data) ~= 'table' then return end

    local act = data.act
    local studio = state.studio

    if act == 'window' then
        local window = DeviceRules.studioWindow(data, state.spec.dui)

        if not window then return end

        state.studioWindow = window

        if studio then
            studio.screen = DeviceRules.studioScreen(studio.rect, window, state.spec.dui)
        end

        return
    end

    if act == 'car' then
        local wanted = wantFor(state, data)

        if not wanted then return end

        state.studioWant = wanted

        if studio and not studio.ending and (studio.phase == 'cover' or studio.phase == 'live') then
            want(state, studio, wanted)
        end

        return
    end

    if not studio or studio.phase ~= 'live' then return end

    if act == 'view' then
        studio.goal = DeviceRules.studioView(data, studio.settings, studio.goal)

        return
    end

    if act == 'reset' then
        studio.goal = { yaw = studio.settings.yaw, pitch = studio.settings.pitch, zoom = 1.0 }

        return
    end

    local car = studio.car

    if not car or not car.ready or car.token ~= studio.token or not DoesEntityExist(car.entity) then return end

    local vehicle = car.entity

    if act == 'door' then
        local indexes = DeviceRules.studioDoors(data.part)

        if not indexes or not car.doors[data.part] then return end

        local open = data.open == true

        for _, index in ipairs(indexes) do
            if car.valid[index] then
                if open then
                    SetVehicleDoorOpen(vehicle, index, false, false)
                else
                    SetVehicleDoorShut(vehicle, index, false)
                end
            end
        end

        car.open[data.part] = open
        SetVehicleInteriorlight(vehicle, car.open.front or car.open.rear)
    elseif act == 'lights' then
        car.lights = data.on == true
        SetVehicleLights(vehicle, car.lights and 2 or 1)
    elseif act == 'paint' then
        if type(data.id) ~= 'string' or not Util.contains(car.paints, data.id) then return end
        if not paintCar(vehicle, data.id, car.palette) then return end

        car.paint = data.id
    else
        return
    end

    send(carMessage(car))
end

function DeviceStudio.leave(state)
    local DeviceUse = require 'client.use'

    local studio = state.studio

    if not studio then return false end

    if studio.thenLeave then
        DeviceUse.close()

        return true
    end

    studio.thenLeave = true

    local now = GetGameTimer()

    if studio.phase == 'cover' then
        studio.ending = true
        send({ type = 'studio', state = 'off' })
        uncover(studio, now)
    elseif studio.phase == 'live' then
        studio.ending = true
        send({ type = 'studio', state = 'off' })
        studio.phase, studio.since = 'exit', now
    end

    return true
end

function DeviceStudio.stop(state, now)
    local studio = state.studio

    if not studio then return false end

    state.studio = nil
    studio.ending = true
    studio.token = studio.token + 1

    local live = studio.live == true

    if studio.cam then
        SetCamActive(studio.cam, false)
        DestroyCam(studio.cam, false)
        studio.cam = nil
    end

    studio.live = false
    clearScene(state, studio)
    Nui.send({ type = 'deviceStudio', on = false })

    if studio.entered and state.frozen then
        state.frozen = false
        unfreezeLater(state.ped, now)
    end

    return live
end

exports('studioCars', function(cars, paints)
    local DeviceUse = require 'client.use'

    local state = DeviceUse.session()

    if not state or GetInvokingResource() ~= DeviceScreens.ownResource() then return false end

    return DeviceStudio.offer(state, cars, paints)
end)

return DeviceStudio
