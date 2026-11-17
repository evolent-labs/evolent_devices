local Config = require 'config'
local Bridge = require 'bridge'
local Util = require 'shared.util'
local ScreenRules = require 'shared.screen'
local DeviceRules = require 'shared.rules'
local DeviceSound = require 'shared.sound'
local LookRules = require 'shared.look'
local Client = require 'client.main'

local DeviceWorld = {
    spawned = {},
    devices = {},
    access = {},
    space = nil,
    rev = nil,
    PAGE_TEXTURE = 'page',
    watchRange = Config.general.watchRange,
    sound = DeviceSound.settings(Config.general.sound),
    display = ScreenRules.display(nil),
}

local spawned = DeviceWorld.spawned
local listeners = { spawn = {}, despawn = {} }
local pages = {}
local missing = {}
local preloaded = {}
local busy = type(GlobalState['evdev:busy']) == 'table' and GlobalState['evdev:busy'] or {}
local busyEnded = {}
local released = {}
local dirty = true
local stopping = false
local loading = false
local behindAt = nil

local LOAD_MS = 5000
local PAGE_RETRY_MS = 500
local INTERIOR_MS = 1500
local SCAN_MS = 1000
local ROOM_MS = 500
local RELEASE_MS = 3000
local CATCH_UP_MS = 2000

local function emit(event, record)
    for _, handler in ipairs(listeners[event]) do
        local ok, failure = pcall(handler, record)

        if not ok then
            print(('[evolent_devices] device %s handler failed: %s'):format(event, tostring(failure)))
        end
    end
end

function DeviceWorld.on(event, handler)
    if listeners[event] and type(handler) == 'function' then
        listeners[event][#listeners[event] + 1] = handler
    end
end

function DeviceWorld.get(key)
    return spawned[key]
end

function DeviceWorld.refresh()
    dirty = true
end

function DeviceWorld.isStopping()
    return stopping
end

function DeviceWorld.busy(key)
    if busy[key] ~= true then return false end

    local untilAt = released[key]

    if untilAt then
        if GetGameTimer() < untilAt then return false end

        released[key] = nil
    end

    return true
end

function DeviceWorld.released(key)
    if busy[key] == true then
        released[key] = GetGameTimer() + RELEASE_MS
    end
end

AddStateBagChangeHandler('evdev:busy', 'global', function(_, _, value)
    local fresh = type(value) == 'table' and value or {}
    local now = GetGameTimer()

    for key, on in pairs(busy) do
        if on == true and fresh[key] ~= true then
            busyEnded[key] = now
        end
    end

    busy = fresh

    for key in pairs(released) do
        if busy[key] ~= true then
            released[key] = nil
        end
    end
end)

function DeviceWorld.lastUseEnded(key)
    return busyEnded[key]
end

function DeviceWorld.flags(id)
    return DeviceWorld.access[id]
end

function DeviceWorld.nearest(coords, radius, filter)
    local best, bestDistance = nil, radius

    for _, record in pairs(spawned) do
        if DoesEntityExist(record.entity) and (not filter or filter(record)) then
            local distance = #(coords - record.at)

            if distance <= bestDistance then
                best, bestDistance = record, distance
            end
        end
    end

    return best, best and bestDistance or nil
end

function DeviceWorld.screen(entity, spec)
    local corners = {}

    for name, offset in pairs(DeviceRules.screenCorners(spec)) do
        corners[name] = GetOffsetFromEntityInWorldCoords(entity, offset.x + 0.0, offset.y + 0.0, offset.z + 0.0)
    end

    return corners
end

function DeviceWorld.corners(record)
    local mode = DeviceRules.screenMode(record.spec)

    if record.cornersMode ~= mode and DoesEntityExist(record.entity) then
        record.corners, record.cornersMode = DeviceWorld.screen(record.entity, record.spec), mode
    end

    return record.corners
end

function DeviceWorld.useSpot(record)
    local offset = record.spec.use.offset

    return GetOffsetFromEntityInWorldCoords(record.entity, offset.x + 0.0, offset.y + 0.0, offset.z + 0.0), GetEntityHeading(record.entity)
end

function DeviceWorld.expectPage(browser, secret, handler)
    pages[tostring(browser)] = { secret = secret, handler = handler }
end

function DeviceWorld.forgetPage(browser)
    pages[tostring(browser)] = nil
end

function DeviceWorld.startPage(page, browser, dictionary, urlOf, width, height, onReady)
    page.browser, page.secret = browser, Util.hex(32)
    page.txdName = dictionary .. browser
    page.txd = CreateRuntimeTxd(page.txdName)
    page.created = GetGameTimer()

    DeviceWorld.expectPage(browser, page.secret, function()
        page.pageReady = true

        if onReady then
            onReady()
        end
    end)

    page.dui = CreateDui(urlOf(page), width, height)

    return page
end

function DeviceWorld.pageTexture(page, now)
    if page.texture then return true end
    if not page.pageReady or not IsDuiAvailable(page.dui) or now < (page.nextAttempt or 0) then return false end

    page.nextAttempt = now + PAGE_RETRY_MS

    local handle = GetDuiHandle(page.dui)

    if handle and handle ~= '' then
        local made = CreateRuntimeTextureFromDuiHandle(page.txd, DeviceWorld.PAGE_TEXTURE, handle)

        if made and made ~= 0 then
            page.texture = made
        end
    end

    return page.texture ~= nil
end

function DeviceWorld.tellPage(page, message)
    local stamped = {}

    for key, value in pairs(message) do
        stamped[key] = value
    end

    stamped.__s = page.secret
    SendDuiMessage(page.dui, json.encode(stamped))
end

function DeviceWorld.endPage(page)
    DeviceWorld.forgetPage(page.browser)

    if page.dui then
        DestroyDui(page.dui)
    end

    page.dui, page.texture = nil, nil
end

RegisterNUICallback('device:ready', function(data, respond)
    respond({ ok = true })

    local browser = type(data) == 'table' and data.browser ~= nil and tostring(data.browser) or nil
    local waiting = browser and pages[browser]

    if not waiting or data.s ~= waiting.secret then return end

    pages[browser] = nil
    waiting.handler(data)
end)

function DeviceWorld.waitInterior(coords)
    local interior = GetInteriorAtCoords(coords.x + 0.0, coords.y + 0.0, coords.z + 0.0)

    if not interior or interior == 0 then
        return 0
    end

    PinInteriorInMemory(interior)

    local deadline = GetGameTimer() + INTERIOR_MS

    while not IsInteriorReady(interior) and GetGameTimer() < deadline do
        Wait(0)
    end

    return interior
end

function DeviceWorld.bindRoom(entity, coords)
    local interior = GetInteriorAtCoords(coords.x + 0.0, coords.y + 0.0, coords.z + 0.0)

    if not interior or interior == 0 then return false end

    PinInteriorInMemory(interior)

    local ped = cache.ped
    local room = 0

    if GetInteriorFromEntity(ped) == interior then
        room = GetRoomKeyFromEntity(ped)
    end

    if room == 0 then
        room = GetRoomKeyFromEntity(entity)
    end

    if room == 0 then return false end

    ForceRoomForEntity(entity, interior, room)

    return true
end

function DeviceWorld.loadModel(name)
    local hash = joaat(name)

    if not IsModelInCdimage(hash) then
        if not missing[name] then
            missing[name] = true
            print(('[evolent_devices] device model %s is not streamed: its ytyp needs a server restart with nobody on.'):format(name))
        end

        return nil
    end

    RequestModel(hash)

    local deadline = GetGameTimer() + LOAD_MS

    while not HasModelLoaded(hash) and GetGameTimer() < deadline do
        Wait(0)
    end

    if not HasModelLoaded(hash) then return nil end

    return hash
end

function DeviceWorld.loadVariant(spec, model)
    local base = DeviceRules.baseModel(spec)

    model = model or base

    local hash = model and DeviceWorld.loadModel(model) or nil

    if hash or model == base or not base then
        return hash, model
    end

    return DeviceWorld.loadModel(base), base
end

local function pointOf(view)
    return { x = view.x, y = view.y, z = view.z, w = view.h or 0.0, kind = view.kind, variant = view.model }
end

local function signature(view)
    return ('%s:%s:%.3f:%.3f:%.3f:%.2f'):format(
        view.kind,
        DeviceRules.variantOf(pointOf(view)) or '',
        view.x,
        view.y,
        view.z,
        view.h or 0.0
    )
end

local function despawn(key)
    local record = spawned[key]

    if not record then return end

    spawned[key] = nil
    emit('despawn', record)

    if DoesEntityExist(record.entity) then
        SetEntityAsMissionEntity(record.entity, true, true)
        DeleteEntity(record.entity)
    end
end

local function spawn(view, spec)
    local point = pointOf(view)
    local interior = DeviceWorld.waitInterior(point)
    local hash, model = DeviceWorld.loadVariant(spec, DeviceRules.variantOf(point))

    if not hash or stopping or spawned[view.id] or DeviceWorld.devices[view.id] ~= view then return end

    local entity = CreateObjectNoOffset(hash, point.x + 0.0, point.y + 0.0, point.z + 0.0, false, false, false)

    SetModelAsNoLongerNeeded(hash)

    if not entity or entity == 0 then return end

    SetEntityHeading(entity, point.w + 0.0)
    FreezeEntityPosition(entity, true)
    SetEntityAsMissionEntity(entity, true, true)
    DeviceWorld.bindRoom(entity, point)

    local record = {
        key = view.id,
        id = view.id,
        entity = entity,
        kind = view.kind,
        model = model,
        spec = spec,
        point = point,
        at = GetEntityCoords(entity),
        corners = DeviceWorld.screen(entity, spec),
        cornersMode = DeviceRules.screenMode(spec),
        interior = interior,
        signature = signature(view),
        item = view.item == true,
        enabled = view.enabled ~= false,
        screen = view.screen,
        usedAt = view.usedAt,
        oos = view.oos,
        look = view.look,
    }

    spawned[view.id] = record
    emit('spawn', record)
end

local function preload(near)
    for _, kind in ipairs(DeviceRules.kinds()) do
        for _, dict in ipairs(DeviceRules.animDicts(Config.kinds[kind].anim)) do
            if near and not preloaded[dict] then
                preloaded[dict] = true
                RequestAnimDict(dict)
            elseif not near and preloaded[dict] then
                preloaded[dict] = nil
                RemoveAnimDict(dict)
            end
        end
    end
end

local function stream()
    local DeviceScreens = require 'client.screens'
    local DeviceBrand = require 'client.brand'

    local settings = Config.devices
    local wanted = {}
    local coords = GetEntityCoords(cache.ped)
    local closest = math.huge
    local space = DeviceWorld.space or 'b0'

    for id, view in pairs(DeviceWorld.devices) do
        local spec = DeviceRules.spec(view.kind)

        if spec and view.space == space then
            local distance = #(coords - vector3(view.x, view.y, view.z))

            closest = math.min(closest, distance)

            local current = spawned[id]

            if distance <= settings.streamDistance then
                wanted[id] = true

                if current and current.signature ~= signature(view) then
                    despawn(id)
                end

                if spawned[id] then
                    local record = spawned[id]
                    local wall = DeviceBrand.wallOf(record)

                    record.enabled, record.item = view.enabled ~= false, view.item == true
                    record.screen, record.usedAt, record.oos = view.screen, view.usedAt, view.oos

                    if LookRules.stamp(record.look) ~= LookRules.stamp(view.look) or wall ~= DeviceBrand.wallOf(record) then
                        record.look = view.look
                        DeviceScreens.lookChanged(record.key)
                    end
                else
                    spawn(view, spec)
                end
            elseif current and distance <= settings.despawnDistance and current.signature == signature(view) then
                wanted[id] = true
            end
        end
    end

    preload(closest <= settings.animPreloadDistance)

    for key in pairs(spawned) do
        if not wanted[key] then
            despawn(key)
        end
    end
end

local function bindRooms()
    local ped = cache.ped
    local interior = GetInteriorFromEntity(ped)

    if not interior or interior == 0 then return end

    local room = GetRoomKeyFromEntity(ped)

    for _, record in pairs(spawned) do
        if record.interior == interior and DoesEntityExist(record.entity) and (room == 0 or GetRoomKeyFromEntity(record.entity) ~= room) then
            DeviceWorld.bindRoom(record.entity, record.point)
        end
    end
end

local function cleanView(view)
    if type(view) ~= 'table' or not Util.integer(view.id, 1) or not DeviceRules.spec(view.kind) then return nil end
    if not (Util.isFinite(view.x) and Util.isFinite(view.y) and Util.isFinite(view.z)) then return nil end

    return {
        id = view.id,
        kind = view.kind,
        model = type(view.model) == 'string' and view.model or nil,
        x = view.x + 0.0,
        y = view.y + 0.0,
        z = view.z + 0.0,
        h = (Util.isFinite(view.h) and view.h or 0.0) + 0.0,
        space = type(view.space) == 'string' and view.space or 'b0',
        item = view.item == true,
        enabled = view.enabled ~= false,
        screen = type(view.screen) == 'table' and view.screen or nil,
        oos = view.oos == true,
        look = LookRules.clean(view.look),
        usedAt = GetGameTimer() - math.floor((Util.number(view.used, 0, 31536000) or 0) * 1000),
    }
end

function DeviceWorld.apply(snapshot)
    if type(snapshot) ~= 'table' then return false end

    local devices = {}

    for _, view in ipairs(type(snapshot.devices) == 'table' and snapshot.devices or {}) do
        local clean = cleanView(view)

        if clean then
            devices[clean.id] = clean
        end
    end

    DeviceWorld.devices = devices
    DeviceWorld.rev = tonumber(snapshot.rev)

    if type(snapshot.space) == 'string' then
        DeviceWorld.space = snapshot.space
    end

    if Util.isFinite(snapshot.watchRange) then
        DeviceWorld.watchRange = snapshot.watchRange
    end

    if type(snapshot.sound) == 'table' then
        DeviceWorld.sound = DeviceSound.settings(snapshot.sound)
    end

    if type(snapshot.display) == 'table' then
        DeviceWorld.display = ScreenRules.display(snapshot.display)
    end

    behindAt = nil
    dirty = true

    return true
end

function DeviceWorld.load()
    if loading or stopping then return false end

    loading = true

    local world = Client.call('evdev:world')

    if world.ok then
        DeviceWorld.apply(world.data)
    end

    local access = Client.call('evdev:access')

    if access.ok and type(access.data) == 'table' then
        DeviceWorld.access = type(access.data.map) == 'table' and access.data.map or {}

        if type(access.data.space) == 'string' then
            DeviceWorld.space = access.data.space
        end
    end

    loading = false
    dirty = true

    return world.ok == true
end

function DeviceWorld.clear()
    for key in pairs(spawned) do
        despawn(key)
    end

    preload(false)
end

RegisterNetEvent('evdev:client:upsert', function(view, rev)
    local clean = cleanView(view)

    if not clean then return end

    DeviceWorld.devices[clean.id] = clean

    if tonumber(rev) then
        DeviceWorld.rev = tonumber(rev)
    end

    dirty = true
end)

RegisterNetEvent('evdev:client:remove', function(id, rev)
    id = tonumber(id)

    if id then
        DeviceWorld.devices[id] = nil
    end

    if tonumber(rev) then
        DeviceWorld.rev = tonumber(rev)
    end

    dirty = true
end)

RegisterNetEvent('evdev:client:space', function(space, snapshot)
    if type(space) ~= 'string' or not space:match('^[bp]%d+$') then return end

    DeviceWorld.space = space

    if type(snapshot) == 'table' then
        DeviceWorld.apply({ rev = snapshot.rev, devices = snapshot.devices, space = space })
    end

    dirty = true
end)

RegisterNetEvent('evdev:client:access', function(map, full)
    if type(map) ~= 'table' then return end

    if full then
        DeviceWorld.access = map

        return
    end

    for id, flags in pairs(map) do
        id = tonumber(id)

        if id then
            DeviceWorld.access[id] = flags ~= false and flags or nil
        end
    end
end)

AddStateBagChangeHandler('evdev:rev', 'global', function(_, _, value)
    value = tonumber(value)

    if value and DeviceWorld.rev and value > DeviceWorld.rev then
        behindAt = behindAt or GetGameTimer() + CATCH_UP_MS
    end
end)

Bridge.onReady(function()
    CreateThread(DeviceWorld.load)
end)

Bridge.onLogout(function()
    DeviceWorld.devices, DeviceWorld.access, DeviceWorld.rev = {}, {}, nil

    for key in pairs(spawned) do
        despawn(key)
    end
end)

CreateThread(function()
    local last, rooms, started = 0, 0, false

    while true do
        Wait(100)

        if stopping then return end

        if not started and Bridge.isPlayerReady() then
            started = true
            DeviceWorld.load()
        end

        local now = GetGameTimer()

        if behindAt and now >= behindAt then
            local target = tonumber(GlobalState['evdev:rev'])

            behindAt = nil

            if target and DeviceWorld.rev and target > DeviceWorld.rev then
                CreateThread(DeviceWorld.load)
            end
        end

        if dirty or now - last >= SCAN_MS then
            dirty = false
            last = now
            stream()
        end

        if now - rooms >= ROOM_MS then
            rooms = now
            bindRooms()
        end
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end

    stopping = true
    DeviceWorld.clear()
end)

return DeviceWorld
