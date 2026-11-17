local Config = require 'config'
local Bridge = require 'bridge'
local Util = require 'shared.util'
local AppRules = require 'shared.apps'
local TabletColours = require 'shared.tablet_colours'
local Guard = require 'server.guard'
local Registry = require 'server.registry'
local Settings = require 'server.settings'
local Apps = require 'server.apps'
local Sessions = require 'server.sessions'
local Signal = require 'server.signal'
local AppHost = require 'server.hosting'
local DeviceOs = require 'server.os'
local Items = require 'server.items'

local Tablets = { open = {}, grants = {} }

Tablets.STATE = 'evdev:tablet'

local GRANT_MS = 15000

local function tintKey(cid)
    return 'evolent_devices:tablet:tint:' .. cid
end

local function publish(source, session)
    local state = Player(source).state

    if session then
        state:set(Tablets.STATE, { holding = true, tint = session.tint, lit = session.dark ~= true }, true)
    elseif state[Tablets.STATE] ~= nil then
        state:set(Tablets.STATE, nil, true)
    end
end

function Tablets.allowed(source)
    return Config.debug == true or Bridge.isAdmin(source)
end

function Tablets.record(session)
    local item = session.item
    local row = item and Registry.bySerial(item.serial) or nil

    return row or { kind = 'tablet', temporary = true }
end

function Tablets.owned(source, token)
    local session = Tablets.open[source]

    if not session or type(token) ~= 'string' or session.token ~= token then return nil end

    return session, Tablets.record(session)
end

function Tablets.notices(session)
    local Notices = require 'server.notices'

    local device = AppHost.tabletDevice()
    local hooks = AppHost.notices(session, device, AppHost.visible(session, device, session.source))

    return Notices.merge(Notices.openFor(session, Tablets.record(session)), hooks)
end

function Tablets.tintOf(cid)
    return TabletColours.index(GetResourceKvpInt(tintKey(cid)))
end

function Tablets.take(source, slot)
    local Notices = require 'server.notices'

    local cid = Bridge.getCharacterId(source)

    if not cid then
        return Util.fail('not_ready')
    end

    local grant = slot == nil and Tablets.grants[source] or nil

    if grant and (GetGameTimer() - grant.at > GRANT_MS or Tablets.allowed(source)) then
        grant = nil
    end

    if slot == nil and not grant and not Tablets.allowed(source) then
        return Util.fail('tablet_not_allowed')
    end

    if not Settings.kindEnabled('tablet') then
        return Util.fail('kind_off')
    end

    if grant then
        local rules = Items.rules('tablet')

        if not rules or rules.enabled == false then
            return Util.fail('item_tablet_off')
        end
    end

    local subject = Bridge.subject(source)

    if subject and subject.dead then
        return Util.fail('tablet_down')
    end

    if GetVehiclePedIsIn(GetPlayerPed(source), false) ~= 0 then
        return Util.fail('tablet_vehicle')
    end

    local item

    if slot ~= nil then
        local reason

        item, reason = Items.tablet(source, slot, subject)

        if not item then
            return Util.fail(reason)
        end
    end

    local previous = Tablets.open[source]

    if previous then
        AppHost.dropAll(previous, 'tablet_closed')
    end

    Tablets.grants[source] = nil

    local name = Bridge.getCharacterName(source) or cid

    local session = {
        source = source,
        cid = cid,
        name = name,
        tint = item and item.colour or Tablets.tintOf(cid),
        token = Util.hex(32),
        apps = {},
        item = item,
        lent = grant and { app = grant.app, resource = grant.resource } or nil,
    }

    local record = Tablets.record(session)

    session.passwordLocked = DeviceOs.hasPassword(record.id)
    Tablets.open[source] = session
    publish(source, session)

    local reading = Signal.forPlayer(source, 'tablet')

    session.signal, session.signalWired = reading.bars, reading.wired

    local apps, notices, installed = AppHost.tabletOpen(source, session)

    return Util.ok({
        token = session.token,
        tint = session.tint,
        recolour = item == nil and Tablets.allowed(source),
        serial = item and item.serial or nil,
        user = { name = name },
        clock = Sessions.clock(),
        apps = apps,
        installed = installed,
        notices = session.passwordLocked and {} or Notices.merge(Notices.openFor(session, record), notices),
        alerts = Notices.allowed(),
        os = DeviceOs.info(session, record),
        signal = reading,
        windows = Config.limits.appWindows,
        protocol = AppRules.PROTOCOL,
    })
end

function Tablets.lend(source, appId, intent, invoker)
    if not Bridge.getCharacterId(source) then
        return false, 'not_ready'
    end

    if not AppRules.isId(appId) then
        return false, 'unknown_app'
    end

    local entry, reason = AppHost.owned(appId, invoker)

    if not entry then
        return false, reason
    end

    if not Apps.supports(appId, 'tablet') then
        return false, 'app_wrong_kind'
    end

    if intent ~= nil and (type(intent) ~= 'table' or #json.encode(intent) > AppHost.INTENT_BYTES) then
        return false, 'invalid_intent'
    end

    if not Guard.rate(source, 'tablet_lend', 2, 2000) then
        return false, 'slow_down'
    end

    if not Tablets.open[source] then
        Tablets.grants[source] = { app = appId, resource = entry.resource, at = GetGameTimer() }
    end

    TriggerClientEvent('evdev:client:openTablet', source, appId, intent)

    return true
end

function Tablets.holderOf(serial)
    for source, session in pairs(Tablets.open) do
        if session.item and session.item.serial == serial then
            return source
        end
    end

    return nil
end

function Tablets.putAway(source)
    local session = Tablets.open[source]

    Tablets.open[source] = nil

    if session then
        AppHost.dropAll(session, 'tablet_closed')
    end

    publish(source, nil)
end

function Tablets.setColour(source, value)
    local cid = Bridge.getCharacterId(source)

    if not cid then
        return Util.fail('not_ready')
    end

    local current = Tablets.tintOf(cid)
    local open = Tablets.open[source]

    if open and open.item then
        return Util.fail('tablet_colour_item', { colour = open.tint })
    end

    if not Tablets.allowed(source) then
        return Util.fail('tablet_not_allowed', { colour = current })
    end

    local index = Util.integer(tonumber(value), 0, #TabletColours - 1)

    if not index then
        return Util.fail('invalid_colour', { colour = current })
    end

    SetResourceKvpInt(tintKey(cid), index)

    local session = Tablets.open[source]

    if session and session.cid == cid then
        session.tint = index
        publish(source, session)
    end

    return Util.ok({ colour = index })
end

function Tablets.setScreen(source, on)
    local session = Tablets.open[source]

    if not session or (session.dark == true) ~= on then return false end
    if not Guard.rate(source, 'tablet_screen', 4, 1000) then return false end

    session.dark = not on
    publish(source, session)

    return true
end

function Tablets.clearStale()
    for _, id in ipairs(GetPlayers()) do
        local source = tonumber(id)

        if source and not Tablets.open[source] then
            publish(source, nil)
        end
    end
end

function Tablets.reset()
    for source, session in pairs(Tablets.open) do
        AppHost.dropAll(session, 'device_closed')
        publish(source, nil)
    end

    Tablets.open = {}
end

function Tablets.tick(now)
    Signal.tickTablets()
    AppHost.tickTablets(now)
    Items.checkTablets(now)
end

Guard.register('evdev:tablet:open', function(source, slot)
    return Tablets.take(source, slot)
end, { rate = 2 })

Guard.register('evdev:tablet:colour', function(source, value)
    return Tablets.setColour(source, value)
end, { rate = 4 })

RegisterNetEvent('evdev:tablet:close', function()
    Tablets.putAway(source)
end)

RegisterNetEvent('evdev:tablet:screen', function(on)
    Tablets.setScreen(source, on == true)
end)

Bridge.onCharacterUnloaded(function(source)
    Tablets.putAway(source)
end)

AddEventHandler('playerDropped', function()
    local session = Tablets.open[source]

    Tablets.open[source] = nil
    Tablets.grants[source] = nil

    if session then
        AppHost.dropAll(session, 'device_left')
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        Tablets.reset()
    end
end)

Tablets.clearStale()

return Tablets
