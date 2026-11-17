local Config = require 'config'
local Integrations = require 'integrations'
local Bridge = require 'bridge'
local Util = require 'shared.util'
local DeviceRules = require 'shared.rules'
local OsRules = require 'shared.os'
local Store = require 'server.store'
local Guard = require 'server.guard'
local Audit = require 'server.audit'
local Registry = require 'server.registry'
local Settings = require 'server.settings'
local People = require 'server.people'
local Spaces = require 'server.spaces'
local Access = require 'server.access'

local Sessions = {
    KEEP_SLACK = 3.0,
    locks = {},
    bySource = {},
    touched = {},
    hooks = { check = {}, open = {}, watch = {}, tick = {}, close = {} },
}

local TOUCH_SECONDS = 60
local REACH_SLACK = 1.0
local STATE_CAP = 20

local function settings()
    return Registry.settings.general
end

local function mirror()
    return Config.devices.mirror
end

function Sessions.on(event, handler)
    local list = Sessions.hooks[event]

    if not list or type(handler) ~= 'function' then return false end

    list[#list + 1] = handler

    return true
end

local function run(event, ...)
    for _, handler in ipairs(Sessions.hooks[event]) do
        local ok, result = pcall(handler, ...)

        if not ok then
            Util.log(('session %s hook failed: %s'):format(event, tostring(result)))
        elseif result ~= nil and result ~= false then
            return result
        end
    end

    return nil
end

function Sessions.user(id)
    local lock = Sessions.locks[id]

    if not lock then return nil end

    return { source = lock.source, name = lock.name, since = lock.since }
end

function Sessions.publish()
    local busy = {}

    for id in pairs(Sessions.locks) do
        busy[id] = true
    end

    GlobalState['evdev:busy'] = busy
end

function Sessions.clock()
    local now = os.time()
    local here, utc = os.date('*t', now), os.date('!*t', now)

    utc.isdst = here.isdst

    return { now = now, offset = math.floor(os.difftime(os.time(here), os.time(utc)) + 0.5) }
end

function Sessions.initials(name)
    local letters = {}

    for word in tostring(name or ''):gmatch('%S+') do
        local first = word:match('^' .. utf8.charpattern)

        if first then
            letters[#letters + 1] = first:upper()
        end

        if #letters == 2 then break end
    end

    return table.concat(letters)
end

function Sessions.cleanState(state, kind)
    local clean = DeviceRules.cleanDeviceState(kind, state, mirror())
    local photos = clean and clean.apps and clean.apps.photos

    if photos and photos.v ~= nil and photos.v ~= '' and not OsRules.shownPhoto(photos.v) then
        photos.v = ''
    end

    return clean
end

local function touch(lock)
    local now = os.time()
    local last = Sessions.touched[lock.id]

    if last and now - last < TOUCH_SECONDS then return end

    Sessions.touched[lock.id] = now

    local device = Registry.device(lock.id)

    if device then
        device.lastUsedAt = now
    end

    if not device or device.temporary then return end

    local ok, failure = pcall(Store.touchUsed, lock.id, now)

    if not ok then
        Util.log(('could not note the last use of device %s: %s'):format(tostring(lock.id), tostring(failure)))
    end
end

local function release(id, reason, tell, quiet)
    local lock = Sessions.locks[id]

    if not lock then return false end

    Sessions.locks[id] = nil

    if lock.source and Sessions.bySource[lock.source] == id then
        Sessions.bySource[lock.source] = nil
    end

    if lock.studio then
        lock.studio = nil
        Integrations.weatherRelease(lock.source)
    end

    for watcher in pairs(lock.watchers or {}) do
        TriggerClientEvent('evdev:client:deviceIdle', watcher, id)
    end

    if tell and lock.source then
        TriggerClientEvent('evdev:client:sessionClosed', lock.source, id, reason)
    end

    if lock.token then
        touch(lock)
        run('close', lock, reason)
    end

    if not quiet then
        Sessions.publish()
    end

    return true
end

function Sessions.close(id, reason)
    return release(id, reason, true)
end

function Sessions.closeApp(appId, reason)
    local AppHost = require 'server.hosting'

    AppHost.closeEverywhere(appId, reason)
end

function Sessions.owned(source, token)
    if type(token) ~= 'string' then return nil end

    local id = Sessions.bySource[source]
    local lock = id and Sessions.locks[id]

    if not lock or lock.token ~= token then return nil end

    return lock
end

function Sessions.lockOf(source)
    local id = Sessions.bySource[source]

    return id and Sessions.locks[id] or nil
end

local function samePlace(device, lock)
    local point = lock.point

    return device.kind == lock.kind and device.x == point.x and device.y == point.y and device.z == point.z and (device.heading or 0.0) == point.h
end

local function canWatch(lock, source, keep)
    if source == lock.source then return false end

    local at = People.coords(source)

    if not at then return false end

    local range = settings().watchRange + (keep and DeviceRules.KEEP_RANGE or 0.0)

    return Util.distance(at, lock.point) <= range and (keep and Spaces.last(source) or Spaces.recent(source)) == lock.space
end

local function watchedChanged(lock, before)
    local now = next(lock.watchers) ~= nil

    if now == before then return end

    if not now then
        lock.state, lock.stateDue, lock.pointer = nil, nil, nil
    end

    if lock.source then
        TriggerClientEvent('evdev:client:deviceWatched', lock.source, lock.id, now)
    end
end

local function forgetWatcher(lock, watcher)
    if not lock.watchers[watcher] then return end

    lock.watchers[watcher] = nil
    watchedChanged(lock, true)
end

local function dropWatcher(lock, watcher)
    forgetWatcher(lock, watcher)
    TriggerClientEvent('evdev:client:deviceUnwatched', watcher, lock.id)
end

function Sessions.fanOut(lock, event, ...)
    for watcher in pairs(lock.watchers) do
        TriggerClientEvent(event, watcher, lock.id, ...)
    end
end

local function answer(lock, device)
    local session = settings().session

    return {
        token = lock.token,
        id = device.id,
        kind = device.kind,
        device = { id = device.id, label = device.label ~= '' and device.label or nil },
        user = { name = lock.name, initials = Sessions.initials(lock.name) },
        clock = Sessions.clock(),
        heartbeat = session.heartbeatSeconds,
        idleMinutes = session.idleMinutes,
        lockMinutes = session.lockMinutes,
    }
end

local function opened(lock, device)
    local reply = answer(lock, device)

    run('open', lock, device, reply)

    return Util.ok(reply)
end

local function usable(source, device)
    if not device or device.state ~= 'placed' or not DeviceRules.spec(device.kind) then
        return 'no_device'
    end

    if not device.enabled then
        return 'device_off'
    end

    if not Settings.kindEnabled(device.kind) then
        return 'kind_off'
    end

    local subject = People.fresh(source)

    if not subject or not subject.cid then
        return 'not_ready'
    end

    if subject.dead then
        return 'device_down'
    end

    local ped = GetPlayerPed(source)

    if not ped or ped == 0 then
        return 'not_ready'
    end

    if GetVehiclePedIsIn(ped, false) ~= 0 then
        return 'device_vehicle'
    end

    if Spaces.recent(source) ~= Spaces.ofDevice(device) then
        return 'device_elsewhere'
    end

    if Util.distance(GetEntityCoords(ped), device) > DeviceRules.spec(device.kind).use.reach + REACH_SLACK then
        return 'device_too_far'
    end

    local held = Sessions.locks[device.id]

    if held and held.source ~= source then
        return 'device_in_use'
    end

    return nil, subject
end

function Sessions.open(source, id)
    if not Guard.rate(source, 'device_open', 1, 1000) then
        return Util.fail('slow_down')
    end

    local device = Registry.device(Guard.idArg(id))
    local reason, subject = usable(source, device)

    if reason then
        return Util.fail(reason)
    end

    local decision = Access.decideUse(source, device, true)

    if not decision.allowed then
        return Util.fail('no_access', { text = Access.refusalText(device, decision.refusal) })
    end

    reason = run('check', source, device, subject)

    if type(reason) ~= 'string' then
        reason = nil
    end

    device = Registry.device(device.id)

    if not reason then
        reason = usable(source, device)
    end

    if reason then
        return Util.fail(reason)
    end

    local leaseMs = settings().session.leaseSeconds * 1000
    local held = Sessions.locks[device.id]

    if held then
        held.lease = GetGameTimer() + leaseMs
        held.token = Util.hex(32)

        return opened(held, device)
    end

    local previous = Sessions.bySource[source]

    if previous then
        release(previous, 'device_closed', false, true)
    end

    local now = GetGameTimer()

    local lock = {
        id = device.id,
        source = source,
        cid = subject.cid,
        name = subject.name or subject.cid,
        token = Util.hex(32),
        kind = device.kind,
        point = { x = device.x, y = device.y, z = device.z, h = device.heading or 0.0 },
        space = Spaces.ofDevice(device),
        since = os.time(),
        lease = now + leaseMs,
        watchers = {},
        apps = {},
    }

    Sessions.locks[device.id] = lock
    Sessions.bySource[source] = device.id
    Sessions.publish()

    if decision.via == 'admin_open' then
        Audit.write(Guard.actor(source), 'admin_open', device.id, { owner = device.ownerCid })
    end

    return opened(lock, device)
end

function Sessions.beat(source, token)
    local lock = Sessions.owned(source, token)

    if not lock then
        return Util.fail('device_closed')
    end

    if not Guard.rate(source, 'device_beat', 1, 2000) then
        return Util.fail('slow_down')
    end

    lock.lease = GetGameTimer() + settings().session.leaseSeconds * 1000

    return Util.ok({})
end

function Sessions.closeOwn(source, token)
    local lock = Sessions.owned(source, token)

    if not lock then
        return Util.fail('device_closed')
    end

    release(lock.id, 'device_closed', false)

    return Util.ok({})
end

function Sessions.check(lock, now)
    if now > lock.lease then
        return 'device_timeout'
    end

    local at = People.coords(lock.source)
    local subject = at and People.fresh(lock.source)

    if not at or not subject or subject.cid ~= lock.cid then
        return 'device_left'
    end

    if not Bridge.isPlayerReady(lock.source, subject) then
        return 'not_ready'
    end

    local device = Registry.device(lock.id)

    if not device or device.state ~= 'placed' or not samePlace(device, lock) then
        return 'no_device'
    end

    if not device.enabled then
        return 'disabled'
    end

    if not Settings.kindEnabled(device.kind) then
        return 'kind_off'
    end

    if Spaces.recent(lock.source) ~= lock.space then
        return 'device_elsewhere'
    end

    if Util.distance(at, lock.point) > DeviceRules.spec(device.kind).use.reach + Sessions.KEEP_SLACK then
        return 'device_too_far'
    end

    if not Access.decideUse(lock.source, device, false).allowed then
        return 'access_lost'
    end

    local reason = run('tick', lock, device, now)

    return type(reason) == 'string' and reason or nil
end

local function pruneWatchers(lock)
    for watcher in pairs(lock.watchers) do
        if not canWatch(lock, watcher, true) then
            dropWatcher(lock, watcher)
        end
    end
end

function Sessions.tick()
    local now = GetGameTimer()
    local freed = false

    for _, id in ipairs(Util.keys(Sessions.locks)) do
        local lock = Sessions.locks[id]

        if lock and lock.token then
            local reason = Sessions.check(lock, now)

            if reason then
                freed = release(id, reason, true, true) or freed
            else
                pruneWatchers(lock)

                if lock.stateDue then
                    lock.stateDue = nil
                    Sessions.fanOut(lock, 'evdev:client:deviceState', lock.state)
                end
            end
        end
    end

    if freed then
        Sessions.publish()
    end
end

function Sessions.recheck(source)
    local freed = false

    for _, id in ipairs(Util.keys(Sessions.locks)) do
        local lock = Sessions.locks[id]

        if lock and lock.token and (source == nil or lock.source == source) then
            local device = Registry.device(id)

            if device and not Access.decideUse(lock.source, device, false).allowed then
                freed = release(id, 'access_lost', true, true) or freed
            end
        end
    end

    if freed then
        Sessions.publish()
    end
end

function Sessions.playerLeft(source)
    local id = Sessions.bySource[source]

    if id then
        release(id, 'device_left', true)
    end

    for _, lock in pairs(Sessions.locks) do
        if lock.watchers then
            forgetWatcher(lock, source)
        end
    end
end

function Sessions.watch(source, id, on)
    id = Guard.idArg(id)

    if not id then
        return Util.fail('no_device')
    end

    local lock = Sessions.locks[id]

    if not on then
        if lock and lock.watchers then
            forgetWatcher(lock, source)
        end

        return Util.ok({})
    end

    if not Guard.rate(source, 'device_watch', 1, 300) then
        return Util.fail('slow_down')
    end

    if not lock or not lock.token or lock.source == source then
        return Util.fail('device_idle')
    end

    if not canWatch(lock, source, lock.watchers[source] == true) then
        forgetWatcher(lock, source)

        return Util.fail('device_too_far')
    end

    if not lock.watchers[source] and Util.count(lock.watchers) >= mirror().maxWatchers then
        return Util.fail('busy')
    end

    local before = next(lock.watchers) ~= nil

    lock.watchers[source] = true
    watchedChanged(lock, before)

    local reply = {
        id = id,
        kind = lock.kind,
        state = lock.state,
        pointer = lock.pointer,
        clock = Sessions.clock(),
        extra = {},
    }

    run('watch', lock, reply, source)

    if next(reply.extra) == nil then
        reply.extra = nil
    end

    return Util.ok(reply)
end

function Sessions.share(source, token, state)
    local lock = Sessions.owned(source, token)

    if not lock or mirror().enabled == false then return false end
    if not Guard.rate(source, 'device_state_cap', STATE_CAP, 1000) then return false end

    if next(lock.watchers) == nil then return false end

    local clean = Sessions.cleanState(state, lock.kind)

    if not clean then return false end

    lock.state = clean

    if not Guard.rate(source, 'device_state', 1, math.floor(mirror().intervalMs * 0.8)) then
        lock.stateDue = true

        return false
    end

    lock.stateDue = nil
    Sessions.fanOut(lock, 'evdev:client:deviceState', clean)

    return true
end

function Sessions.pointer(source, token, u, v)
    local lock = Sessions.owned(source, token)

    if not lock or mirror().enabled == false or next(lock.watchers) == nil then return false end
    if not Guard.rate(source, 'device_pointer', 1, math.floor(1000 / mirror().pointerHz * 0.8)) then return false end

    local cu, cv = DeviceRules.cleanPointer(u, v)

    if not cu then return false end

    lock.pointer = { u = cu, v = cv }
    Sessions.fanOut(lock, 'evdev:client:devicePointer', cu, cv)

    return true
end

function Sessions.studio(source, token, on)
    local lock = Sessions.owned(source, token)

    if not lock then return false end

    if not on then
        if not lock.studio then return false end

        lock.studio = nil
        Integrations.weatherRelease(source)

        return true
    end

    local studio = DeviceRules.studio(lock.kind)

    if not studio or lock.studio then return false end
    if not Guard.rate(source, 'device_studio', 1, 500) then return false end

    lock.studio = true
    Integrations.weatherHold(source, studio.weather)

    return true
end

function Sessions.reset()
    for _, lock in pairs(Sessions.locks) do
        if lock.studio then
            lock.studio = nil
            Integrations.weatherRelease(lock.source)
        end
    end

    Sessions.locks, Sessions.bySource = {}, {}
    Sessions.publish()
end

Guard.register('evdev:device:open', function(source, id)
    return Sessions.open(source, id)
end, { rate = 4 })

Guard.register('evdev:device:beat', function(source, token)
    return Sessions.beat(source, token)
end, { rate = 4 })

Guard.register('evdev:device:close', function(source, token)
    return Sessions.closeOwn(source, token)
end, { rate = 4 })

Guard.register('evdev:device:watch', function(source, id, on)
    return Sessions.watch(source, id, on == true)
end, { rate = 8 })

RegisterNetEvent('evdev:device:state', function(token, state)
    if not Registry.ready then return end

    Sessions.share(source, token, state)
end)

RegisterNetEvent('evdev:device:pointer', function(token, u, v)
    if not Registry.ready then return end

    Sessions.pointer(source, token, u, v)
end)

RegisterNetEvent('evdev:device:studio', function(token, on)
    if not Registry.ready then return end

    Sessions.studio(source, token, on == true)
end)

return Sessions
