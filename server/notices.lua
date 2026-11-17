local Config = require 'config'
local Integrations = require 'integrations'
local Bridge = require 'bridge'
local Util = require 'shared.util'
local AppRules = require 'shared.apps'
local OsRules = require 'shared.os'
local Store = require 'server.store'
local Guard = require 'server.guard'
local Registry = require 'server.registry'
local Settings = require 'server.settings'
local Apps = require 'server.apps'
local Sessions = require 'server.sessions'
local AppHost = require 'server.hosting'
local DeviceOs = require 'server.os'
local Items = require 'server.items'
local Tablets = require 'server.tablet'

local Notices = { byCid = {}, byDevice = {}, blinks = {}, published = nil, purgedAt = 0, trimmedAt = 0, ready = false }

Notices.STATE = 'evdev:unread'
Notices.KINDS = OsRules.KINDS
Notices.JOIN_SHOWN = 3
Notices.MAX_COUNT = 99

local PURGE_SECONDS = 3600
local TRIM_SECONDS = 60
local DAY = 86400
local serial = 0

function Notices.settings()
    local config = type(Config.notifications) == 'table' and Config.notifications or {}
    local popup = type(config.popup) == 'table' and config.popup or {}
    local tablet = type(config.tablet) == 'table' and config.tablet or {}
    local screen = type(config.screen) == 'table' and config.screen or {}

    return {
        popup = popup.enabled ~= false,
        tablet = tablet.enabled ~= false,
        screen = screen.enabled ~= false,
        blink = screen.enabled ~= false and screen.blink ~= false,
        sound = config.sound ~= false,
        keep = Util.integer(config.keep, 5, 50) or 30,
        days = Util.integer(config.keepDays, 1, 60) or 7,
    }
end

function Notices.allowed()
    local config = Notices.settings()

    return { popup = config.popup or config.tablet, sound = config.sound and (config.popup or config.tablet) }
end

function Notices.reset()
    Notices.byCid, Notices.byDevice, Notices.blinks = {}, {}, {}
    Notices.published, Notices.purgedAt, Notices.trimmedAt, Notices.ready = nil, 0, 0, false
end

local function listFor(target, create)
    local map, key = Notices.byCid, target.cid

    if not key then
        map, key = Notices.byDevice, target.deviceId
    end

    if key == nil then return nil end

    local list = map[key]

    if not list and create then
        list = {}
        map[key] = list
    end

    return list
end

local function drop(list, index, gone)
    local entry = table.remove(list, index)

    if entry.row then
        gone[#gone + 1] = entry.row
    end

    return entry
end

local function forget(rows)
    if #rows == 0 then return end

    local ok, failure = pcall(Store.deleteNotices, rows)

    if not ok then
        Util.log('could not remove old notifications: ' .. tostring(failure))
    end
end

local function trim(list, config, now, gone)
    for index = #list, 1, -1 do
        if list[index].at < now - config.days * DAY then
            drop(list, index, gone)
        end
    end

    while #list > config.keep do
        drop(list, 1, gone)
    end
end

local function entryOf(row)
    return {
        row = row.id,
        key = 'n' .. row.id,
        app = row.app,
        id = row.noticeId,
        title = row.title,
        body = row.body or '',
        action = row.action,
        intent = type(row.intent) == 'table' and row.intent or nil,
        at = tonumber(row.at) or os.time(),
        seen = row.seen == true,
        popped = false,
    }
end

function Notices.load()
    Notices.reset()

    local config = Notices.settings()
    local purged, failure = pcall(Store.purgeNotices, config.days)

    if not purged then
        Util.log('could not clear old notifications: ' .. tostring(failure))
    end

    local loaded, rows = pcall(Store.loadNotices)

    if not loaded then
        Util.log('could not read the notifications: ' .. tostring(rows))
        rows = {}
    end

    local gone, now = {}, os.time()

    for _, row in ipairs(rows) do
        local id = Util.integer(row.id, 1)
        local target = Util.isCid(row.cid) and { cid = row.cid } or Util.integer(row.deviceId, 1) and { deviceId = Util.integer(row.deviceId, 1) } or nil

        if id and target and AppRules.isId(row.app) and type(row.noticeId) == 'string' and type(row.title) == 'string' then
            row.id = id
            local list = listFor(target, true)

            list[#list + 1] = entryOf(row)
        elseif id then
            gone[#gone + 1] = id
        end
    end

    for _, map in ipairs({ Notices.byCid, Notices.byDevice }) do
        for _, list in pairs(map) do
            trim(list, config, now, gone)
        end
    end

    forget(gone)
    Notices.purgedAt = now
    Notices.ready = true
    Notices.publish()
end

local function unseen(list)
    local count = 0

    for _, entry in ipairs(list or {}) do
        if not entry.seen then
            count = count + 1
        end
    end

    return count
end

local function shows(device)
    return device.state == 'placed' and Notices.KINDS[device.kind] == true and device.enabled ~= false
end

local function owns(device, cid)
    return device.origin == 'item' and device.ownerCid ~= nil and device.ownerCid == cid
end

function Notices.counts()
    local map = {}

    if not Notices.settings().screen then
        return map
    end

    for id, device in pairs(Registry.devices) do
        if shows(device) then
            local count = unseen(Notices.byDevice[id])

            if owns(device, device.ownerCid) then
                count = count + unseen(Notices.byCid[device.ownerCid])
            end

            if count > 0 then
                map[tostring(id)] = { n = math.min(count, Notices.MAX_COUNT), b = Notices.blinks[id] or 0 }
            end
        end
    end

    return map
end

function Notices.publish()
    local map = Notices.counts()

    if Notices.published and Util.same(map, Notices.published) then return false end

    Notices.published = map
    GlobalState[Notices.STATE] = map

    return true
end

function Notices.ownDevices(cid)
    local list = {}

    for id, device in pairs(Registry.devices) do
        if owns(device, cid) and shows(device) then
            list[#list + 1] = id
        end
    end

    table.sort(list)

    return list
end

local function blink(ids)
    if not Notices.settings().blink then return end

    for _, id in ipairs(ids) do
        Notices.blinks[id] = (Notices.blinks[id] or 0) + 1
    end
end

local function stamp(at, now)
    if Util.isFinite(at) and at <= now and at > now - DAY then
        return math.floor(at)
    end

    return now
end

local function store(target, appId, clean, seen)
    local config = Notices.settings()
    local list = listFor(target, true)
    local gone, now = {}, os.time()

    for index = #list, 1, -1 do
        if list[index].app == appId and list[index].id == clean.id then
            drop(list, index, gone)
        end
    end

    serial = serial + 1

    local entry = {
        key = 'm' .. serial,
        app = appId,
        id = clean.id,
        title = clean.title,
        body = clean.body or '',
        action = clean.action,
        intent = clean.intent,
        at = stamp(clean.at, now),
        seen = seen == true,
        popped = seen == true,
    }

    local ok, row = pcall(Store.insertNotice, target, entry)
    local id = ok and Util.integer(row, 1) or nil

    if id then
        entry.row, entry.key = id, 'n' .. id
    elseif not ok then
        Util.log('could not keep a notification: ' .. tostring(row))
    end

    list[#list + 1] = entry
    trim(list, config, now, gone)
    forget(gone)

    return entry
end

function Notices.view(entry)
    local registered = Apps.registered[entry.app]
    local def = registered and registered.def or nil

    return {
        key = entry.key,
        id = entry.id,
        app = entry.app,
        title = entry.title,
        body = entry.body,
        action = entry.action,
        intent = entry.intent and Util.copy(entry.intent) or nil,
        at = entry.at,
        label = def and def.label or entry.app,
        icon = def and Util.copy(def.icon) or nil,
    }
end

function Notices.osSession(source)
    local lock = Sessions.lockOf(source)
    local device = lock and lock.token and Registry.device(lock.id) or nil

    if device and OsRules.kind(device.kind) then
        return lock, device
    end

    local tablet = Tablets.open[source]

    if tablet and tablet.token then
        return tablet, Tablets.record(tablet)
    end

    return nil
end

local function shownIn(session)
    return session ~= nil and session.token ~= nil and not session.passwordLocked and not AppHost.onlyApp(session)
end

function Notices.carriesTablet(source)
    if Tablets.open[source] or not Settings.kindEnabled('tablet') then return false end

    local rules = Items.rules('tablet')

    if not rules or rules.enabled == false then return false end

    return Integrations.hasItem(source, Items.itemName('tablet'))
end

function Notices.alert(source, views, options)
    options = options or {}

    local config = Notices.settings()

    if options.popup == false or #views == 0 then return nil end

    local pocket = config.tablet and Notices.carriesTablet(source)

    if not pocket and not config.popup then return nil end

    local payload = {
        mode = pocket and 'pocket' or 'popup',
        sound = config.sound and options.sound ~= false,
        list = views,
        more = options.more or 0,
        late = options.late == true or nil,
    }

    TriggerClientEvent('evdev:client:notices', source, payload)

    return payload.mode
end

local function live(source, appId, view)
    TriggerClientEvent('evdev:client:appNotice', source, appId, view)
end

local function options(notice)
    return { popup = notice.popup ~= false, sound = notice.sound ~= false }
end

local function marked(view, wanted)
    if wanted.popup == false then
        view.quiet = true
    end

    if wanted.sound == false then
        view.silent = true
    end

    return view
end

function Notices.send(source, appId, notice, invoker)
    local entry, reason = AppHost.owned(appId, invoker)

    if not entry then
        return false, reason
    end

    local clean = AppHost.cleanNotice(notice)

    if not clean then
        return false, 'invalid_notice'
    end

    local cid = Bridge.getCharacterId(source)

    if not cid then
        return false, 'not_ready'
    end

    if not Guard.rate(source, 'app_notice:' .. appId, 5, 1000) then
        return false, 'slow_down'
    end

    clean.id = clean.id or (appId .. ':' .. Util.hex(8))

    local wanted = options(notice)
    local session = Notices.osSession(source)
    local inside = shownIn(session)
    local stored = store({ cid = cid }, appId, clean, inside)
    local view = marked(Notices.view(stored), wanted)

    if inside then
        live(source, appId, view)
    else
        if not session then
            stored.popped = Notices.alert(source, { view }, wanted) ~= nil
        end

        blink(Notices.ownDevices(cid))
    end

    Notices.publish()

    return true
end

function Notices.sendDevice(deviceId, appId, notice, invoker)
    local entry, reason = AppHost.owned(appId, invoker)

    if not entry then
        return false, reason
    end

    local clean = AppHost.cleanNotice(notice)

    if not clean then
        return false, 'invalid_notice'
    end

    local id = Util.integer(tonumber(deviceId), 1)
    local device = id and Registry.device(id) or nil

    if not device or device.state == 'removed' then
        return false, 'unknown_device'
    end

    if not Notices.KINDS[device.kind] then
        return false, 'notice_wrong_kind'
    end

    if not Guard.rate('device:' .. id, 'app_notice:' .. appId, 5, 1000) then
        return false, 'slow_down'
    end

    clean.id = clean.id or (appId .. ':' .. Util.hex(8))

    local lock = Sessions.locks[id]
    local inside = shownIn(lock)
    local stored = store({ deviceId = id }, appId, clean, inside)

    if inside then
        live(lock.source, appId, marked(Notices.view(stored), options(notice)))
    elseif shows(device) then
        blink({ id })
    end

    Notices.publish()

    return true
end

local function newestFirst(a, b)
    if a.at ~= b.at then
        return a.at > b.at
    end

    return (a.row or 0) > (b.row or 0)
end

function Notices.openFor(session, device)
    if not Notices.ready or not shownIn(session) then
        return {}
    end

    local lists = {}

    if Util.isCid(session.cid) then
        lists[#lists + 1] = Notices.byCid[session.cid]
    end

    if device and device.id and Notices.KINDS[device.kind] then
        lists[#lists + 1] = Notices.byDevice[device.id]
    end

    local entries, rows = {}, {}

    for _, list in ipairs(lists) do
        for _, entry in ipairs(list) do
            entries[#entries + 1] = entry

            if not entry.seen then
                entry.seen, entry.popped = true, true

                if entry.row then
                    rows[#rows + 1] = entry.row
                end
            end
        end
    end

    if #rows > 0 then
        local ok, failure = pcall(Store.seeNotices, rows)

        if not ok then
            Util.log('could not mark notifications as seen: ' .. tostring(failure))
        end
    end

    table.sort(entries, newestFirst)

    local views = {}

    for index, entry in ipairs(entries) do
        views[index] = Notices.view(entry)
    end

    Notices.publish()

    return views
end

function Notices.merge(stored, hooks)
    local list, seen = {}, {}

    for _, group in ipairs({ stored or {}, hooks or {} }) do
        for _, notice in ipairs(group) do
            local key = tostring(notice.app) .. '\31' .. tostring(notice.id)

            if not seen[key] and #list < 50 then
                seen[key] = true
                list[#list + 1] = notice
            end
        end
    end

    return list
end

function Notices.dismiss(session, device, action, key)
    if action ~= 'dismiss' and action ~= 'clear' then
        return Util.fail('unknown_action')
    end

    if action == 'dismiss' and (type(key) ~= 'string' or not key:match('^[nm]%d+$')) then
        return Util.ok({ removed = 0 })
    end

    local lists = { Util.isCid(session.cid) and Notices.byCid[session.cid] or nil }

    if device and device.id and Notices.KINDS[device.kind] and DeviceOs.mayManage(session, device) then
        lists[#lists + 1] = Notices.byDevice[device.id]
    end

    local gone, removed = {}, 0

    for _, list in pairs(lists) do
        for index = #list, 1, -1 do
            if action == 'clear' or list[index].key == key then
                drop(list, index, gone)
                removed = removed + 1
            end
        end
    end

    forget(gone)
    Notices.publish()

    return Util.ok({ removed = removed })
end

function Notices.joined(source)
    if not Notices.ready then return nil end

    local cid = Bridge.getCharacterId(source)
    local list = cid and Notices.byCid[cid] or nil

    if not list then return nil end

    local fresh = {}

    for index = #list, 1, -1 do
        local entry = list[index]

        if not entry.seen and not entry.popped then
            fresh[#fresh + 1] = entry
        end
    end

    if #fresh == 0 then return nil end

    local views = {}

    for index = 1, math.min(Notices.JOIN_SHOWN, #fresh) do
        views[index] = Notices.view(fresh[index])
    end

    local mode = Notices.alert(source, views, { more = #fresh - #views, late = true })

    if mode then
        for _, entry in ipairs(fresh) do
            entry.popped = true
        end
    end

    return mode
end

function Notices.tick(now)
    if not Notices.ready then return end

    now = now or os.time()

    local config = Notices.settings()

    if now - Notices.trimmedAt >= TRIM_SECONDS then
        Notices.trimmedAt = now

        local gone = {}

        for _, map in ipairs({ Notices.byCid, Notices.byDevice }) do
            for key, list in pairs(map) do
                trim(list, config, now, gone)

                if #list == 0 then
                    map[key] = nil
                end
            end
        end

        forget(gone)
    end

    if now - Notices.purgedAt >= PURGE_SECONDS then
        Notices.purgedAt = now

        local ok, failure = pcall(Store.purgeNotices, config.days)

        if not ok then
            Util.log('could not clear old notifications: ' .. tostring(failure))
        end
    end

    Notices.publish()
end

Sessions.on('open', function(lock, device, answer)
    if not OsRules.kind(device.kind) then return nil end

    answer.alerts = Notices.allowed()

    local stored = Notices.openFor(lock, device)

    if #stored > 0 then
        answer.notices = Notices.merge(stored, answer.notices)
    end

    return nil
end)

DeviceOs.register('notice', function(_, session, device, action, key)
    return Notices.dismiss(session, device, action, key)
end, { rate = 8 })

Bridge.onCharacterLoaded(function(source)
    if not Registry.ready then return end

    local ok, failure = pcall(Notices.joined, source)

    if not ok then
        Util.log('notifications on join failed: ' .. tostring(failure))
    end
end)

return Notices
