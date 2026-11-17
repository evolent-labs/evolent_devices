local Config = require 'config'
local Bridge = require 'bridge'
local Util = require 'shared.util'
local ScreenRules = require 'shared.screen'
local SignalRules = require 'shared.signal'
local Store = require 'server.store'
local Audit = require 'server.audit'
local Spaces = require 'server.spaces'
local Sessions = require 'server.sessions'

local Signal = { antennas = {}, kinds = {}, rev = 0 }

Signal.STATE = 'evdev:masts'

function Signal.stored()
    return { antennas = Util.copy(Signal.antennas), kinds = Util.copy(Signal.kinds) }
end

function Signal.load(stored)
    local problems = {}

    Signal.kinds = SignalRules.defaultKinds()

    if type(stored) ~= 'table' then
        Signal.antennas = SignalRules.starter()

        local ok, failure = pcall(Store.saveSetting, 'signal', Signal.stored())

        if not ok then
            problems[#problems + 1] = 'the starter antennas could not be saved: ' .. tostring(failure)
        end
    else
        local list = {}

        for index, entry in ipairs(type(stored.antennas) == 'table' and stored.antennas or {}) do
            local antenna, reason = SignalRules.cleanAntenna(entry)

            if antenna then
                list[#list + 1] = antenna
            else
                problems[#problems + 1] = ('antenna %d (%s) is ignored'):format(index, reason)
            end
        end

        Signal.antennas = SignalRules.normalize(list, math.max(#list, Config.limits.antennas)) or {}

        if type(stored.kinds) == 'table' then
            Signal.kinds = SignalRules.cleanKinds(stored.kinds, Signal.kinds) or Signal.kinds
        end
    end

    Signal.rev = Signal.rev + 1
    Signal.publish()

    return problems
end

function Signal.publish()
    local masts = {}

    for _, antenna in ipairs(Signal.antennas) do
        if antenna.source == 'mast' then
            masts[#masts + 1] = {
                id = antenna.id,
                model = antenna.model,
                x = antenna.x,
                y = antenna.y,
                z = antenna.z,
                h = antenna.h,
            }
        end
    end

    GlobalState[Signal.STATE] = masts
end

function Signal.wireless(kind)
    return Config.signal.enabled ~= false and Signal.kinds[kind] == true
end

function Signal.at(point, space)
    return SignalRules.reading(Signal.antennas, point, space)
end

function Signal.deviceWireless(device)
    return Config.signal.enabled ~= false and ScreenRules.wireless(Signal.kinds[device.kind] == true, device.screen)
end

function Signal.forDevice(device)
    if not Signal.deviceWireless(device) then
        return { bars = SignalRules.MAX_BARS, wired = true }
    end

    if not device.x then
        return { bars = 0, wired = false }
    end

    local reading = Signal.at(device, Spaces.ofDevice(device))

    return { bars = reading.bars, wired = false }
end

function Signal.forPlayer(source, kind)
    if not Signal.wireless(kind) then
        return { bars = SignalRules.MAX_BARS, wired = true }
    end

    local ped = GetPlayerPed(source)

    if not ped or ped == 0 then
        return { bars = 0, wired = false }
    end

    local coords = GetEntityCoords(ped)
    local reading = Signal.at({ x = coords.x, y = coords.y, z = coords.z }, Spaces.last(source))

    return { bars = reading.bars, wired = false }
end

local function changed(session, reading)
    return reading.bars ~= session.signal or reading.wired ~= session.signalWired
end

local function tell(session, reading)
    session.signal, session.signalWired, session.signalRev = reading.bars, reading.wired, Signal.rev
    TriggerClientEvent('evdev:client:signal', session.source, reading)
end

Sessions.on('open', function(lock, device, answer)
    local reading = Signal.forDevice(device)

    lock.signal, lock.signalWired, lock.signalRev = reading.bars, reading.wired, Signal.rev
    lock.signalMode = ScreenRules.signalMode(device.screen)
    answer.signal = reading
end)

Sessions.on('tick', function(lock, device)
    local mode = ScreenRules.signalMode(device.screen)

    if lock.signalRev == Signal.rev and lock.signalMode == mode then return nil end

    lock.signalMode = mode

    local reading = Signal.forDevice(device)

    if changed(lock, reading) then
        tell(lock, reading)
    else
        lock.signalRev = Signal.rev
    end

    return nil
end)

function Signal.tickTablets()
    local Tablets = require 'server.tablet'

    for source, session in pairs(Tablets.open) do
        if session.token then
            local reading = Signal.forPlayer(source, 'tablet')

            if changed(session, reading) then
                tell(session, reading)
            end
        end
    end
end

local function towerView(tower)
    local defaults = SignalRules.towerDefaults(tower)

    return {
        id = tower.id,
        type = tower.type,
        model = tower.model,
        x = tower.x,
        y = tower.y,
        z = tower.z,
        height = tower.height,
        radius = defaults.radius,
        strength = defaults.strength,
    }
end

function Signal.view(actor)
    local Devices = require 'server.devices'

    local towers = {}

    for _, tower in ipairs(Config.towers or {}) do
        towers[#towers + 1] = towerView(tower)
    end

    local here = actor and Devices.adminSpot(actor.source) or nil

    return {
        antennas = Util.copy(Signal.antennas),
        kinds = Util.copy(Signal.kinds),
        towers = towers,
        masts = Util.copy(Config.signal.masts),
        defaults = {
            kinds = SignalRules.defaultKinds(),
            radius = Config.signal.radius,
            strength = Config.signal.strength,
            towerTypes = Util.copy(Config.signal.towerTypes),
        },
        bars = Util.copy(Config.signal.bars),
        homeLoss = Config.signal.homeLoss,
        enabled = Config.signal.enabled ~= false,
        limit = Config.limits.antennas,
        here = here and here.position and { x = here.position.x, y = here.position.y, z = here.position.z } or nil,
        rev = Signal.rev,
    }
end

local function antennaText(antenna)
    if antenna.label and antenna.label ~= '' then
        return Util.clip(antenna.label, 40)
    end

    if antenna.source == 'tower' then
        return antenna.tower
    end

    return ('#%d %s'):format(antenna.id, antenna.model)
end

function Signal.changes(before, after, kindsBefore, kindsAfter)
    local detail = Audit.listChanges(before, after, antennaText)

    detail.kinds = {}

    for _, kind in ipairs(Config.kindOrder) do
        if kindsBefore[kind] ~= kindsAfter[kind] then
            detail.kinds[#detail.kinds + 1] = { kind = kind, wireless = kindsAfter[kind] == true }
        end
    end

    return detail
end

function Signal.placedHere(actor, antennas)
    local Devices = require 'server.devices'

    local old = {}

    for _, antenna in ipairs(Signal.antennas) do
        old[antenna.id] = antenna
    end

    local admin

    for index, antenna in ipairs(antennas) do
        local was = old[antenna.id]

        if antenna.source == 'mast' and not (was and was.source == 'mast' and was.x == antenna.x and was.y == antenna.y and was.z == antenna.z) then
            admin = admin or Devices.adminSpot(actor.source)

            if not admin then
                return 'out_of_range', index
            end

            if admin.space ~= 'b0' then
                return 'mast_open_world', index
            end

            if Util.distance(admin.position, antenna) > Config.admin.placeRange + Config.admin.placeTolerance then
                return 'out_of_range', index
            end
        end
    end

    return nil
end

function Signal.save(actor, patch, rev)
    if type(patch) ~= 'table' then
        return Util.fail('invalid_signal')
    end

    for key in pairs(patch) do
        if key ~= 'antennas' and key ~= 'kinds' then
            return Util.fail('invalid_signal')
        end
    end

    if rev ~= nil and Util.integer(rev) ~= Signal.rev then
        return Util.fail('signal_changed', { rev = Signal.rev })
    end

    local antennas, kinds = Signal.antennas, Signal.kinds

    if patch.antennas ~= nil then
        local clean, reason, index = SignalRules.normalize(patch.antennas)

        if not clean then
            return Util.fail(reason, { antenna = index })
        end

        reason, index = Signal.placedHere(actor, clean)

        if reason then
            return Util.fail(reason, { antenna = index })
        end

        antennas = clean
    end

    if patch.kinds ~= nil then
        kinds = SignalRules.cleanKinds(patch.kinds, Signal.kinds)

        if not kinds then
            return Util.fail('invalid_signal')
        end
    end

    local detail = Signal.changes(Signal.antennas, antennas, Signal.kinds, kinds)

    Store.saveSetting('signal', { antennas = antennas, kinds = kinds })
    Signal.antennas, Signal.kinds = antennas, kinds
    Signal.rev = Signal.rev + 1
    Signal.publish()
    Audit.write(actor, 'signal', nil, detail)
    Signal.tickTablets()

    return Util.ok(Signal.view(actor))
end

function Signal.spotOf(device)
    local Tablets = require 'server.tablet'

    if device.state == 'placed' and device.x then
        return { x = device.x, y = device.y, z = device.z }, Spaces.ofDevice(device), nil
    end

    if device.kind ~= 'tablet' or device.state ~= 'carried' or not device.serial then
        return nil
    end

    local holder = Tablets.holderOf(device.serial)
    local ped = holder and GetPlayerPed(holder)

    if not ped or ped == 0 then
        return nil
    end

    local coords = GetEntityCoords(ped)

    return { x = coords.x, y = coords.y, z = coords.z }, Spaces.recent(holder), holder
end

function Signal.dark(device)
    if device.state == 'removed' or not Signal.deviceWireless(device) then
        return false
    end

    local point, space = Signal.spotOf(device)

    if not point then return false end

    return Signal.at(point, space).bars == 0
end

local function flat(a, b)
    local dx, dy = a.x - b.x, a.y - b.y

    return math.sqrt(dx * dx + dy * dy)
end

local function radiusFor(antenna, distance)
    local first = Config.signal.bars[1] or 0

    if antenna.strength <= first then
        return nil
    end

    local radius = math.ceil(distance / math.sqrt(1.0 - first / antenna.strength) / 10.0 + 1.0) * 10

    return radius <= 6000 and radius or nil
end

function Signal.why(device)
    local view = {
        enabled = Config.signal.enabled ~= false,
        kindWireless = Signal.kinds[device.kind] == true,
        mode = ScreenRules.signalMode(device.screen),
        wireless = Signal.deviceWireless(device),
        homeLoss = Config.signal.homeLoss or 0,
        bars = SignalRules.MAX_BARS,
    }

    if not view.wireless then
        return view
    end

    local point, space, holder = Signal.spotOf(device)

    if not point then
        view.bars = nil

        return view
    end

    local reading = Signal.at(point, space)

    view.bars = reading.bars
    view.quality = reading.quality
    view.position = point
    view.space = space

    if holder then
        view.holder = { id = holder, name = Bridge.getCharacterName(holder) or Bridge.getCharacterId(holder) }
    end

    local nearest, best

    for _, antenna in ipairs(Signal.antennas) do
        local distance = flat(antenna, point)

        if not nearest or distance < best then
            nearest, best = antenna, distance
        end
    end

    if nearest then
        local tower = nearest.source == 'tower' and SignalRules.tower(nearest.tower) or nil

        view.nearest = {
            id = nearest.id,
            label = antennaText(nearest),
            name = nearest.label ~= '' and nearest.label or nil,
            towerType = tower and tower.type or nil,
            source = nearest.source,
            x = nearest.x,
            y = nearest.y,
            radius = nearest.radius,
            strength = nearest.strength,
            on = nearest.on,
            distance = math.floor(best + 0.5),
            reach = radiusFor(nearest, best),
        }
    end

    return view
end

return Signal
