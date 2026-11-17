local Config = require 'config'
local Bridge = require 'bridge'
local Util = require 'shared.util'
local AppRules = require 'shared.apps'
local OsRules = require 'shared.os'
local Guard = require 'server.guard'
local Registry = require 'server.registry'
local People = require 'server.people'
local Access = require 'server.access'
local Apps = require 'server.apps'
local Sessions = require 'server.sessions'
local Signal = require 'server.signal'

local AppHost = { INTENT_BYTES = 2048 }

local MESSAGE_BYTES = 32768
local CONTEXT_BYTES = 16384
local WATCH_BYTES = 8192
local CAN_OPEN_MS = 5000
local LIST_MS = 5000
local STATE_WATCHERS = 2
local NOTICES_PER_APP = 20

local failed = {}

local function bytes(value)
    local ok, text = pcall(json.encode, value)

    return ok and type(text) == 'string' and #text or math.huge
end

local function call(appId, name, hook, ...)
    local ok, result = pcall(hook, ...)

    if ok then
        return result, true
    end

    local key = appId .. ':' .. name

    if not failed[key] then
        failed[key] = true
        Util.log(('app %s: its %s hook failed: %s'):format(appId, name, tostring(result)))
    end

    return nil, false
end

function AppHost.tabletDevice()
    local tablet = Registry.settings.kinds.tablet
    local apps = tablet and tablet.item and tablet.item.apps or { order = {}, entries = {} }

    return {
        kind = 'tablet',
        label = '',
        origin = 'tablet',
        state = 'carried',
        enabled = true,
        access = { mode = 'everyone' },
        apps = apps,
    }
end

function AppHost.sessions(source)
    local Tablets = require 'server.tablet'

    local list = {}
    local lock = Sessions.lockOf(source)

    if lock and lock.token then
        local device = Registry.device(lock.id)

        if device then
            list[#list + 1] = { session = lock, device = device }
        end
    end

    local tablet = Tablets.open[source]

    if tablet and tablet.token then
        list[#list + 1] = { session = tablet, device = AppHost.tabletDevice() }
    end

    return list
end

function AppHost.find(source, token)
    if type(token) ~= 'string' then return nil end

    for _, entry in ipairs(AppHost.sessions(source)) do
        if entry.session.token == token then
            return entry.session, entry.device
        end
    end

    return nil
end

function AppHost.settingsFor(device, appId)
    local values

    if device.kind == 'terminal' then
        values = type(device.page) == 'table' and device.page.app == appId and device.page.settings or nil
    else
        local entries = type(device.apps) == 'table' and device.apps.entries or nil

        values = type(entries) == 'table' and entries[appId] and entries[appId].settings or nil
    end

    local result = Util.copy(type(values) == 'table' and values or {})
    local entry = Apps.registered[appId]

    for _, field in ipairs(entry and entry.def.settings or {}) do
        if result[field.key] == nil and field.default ~= nil then
            result[field.key] = field.default
        end
    end

    return result
end

function AppHost.context(session, device, appId)
    return {
        app = appId,
        kind = device.kind,
        device = device.id and { id = device.id, label = device.label ~= '' and device.label or nil, owner = device.ownerCid } or nil,
        settings = AppHost.settingsFor(device, appId),
        user = { source = session.source, cid = session.cid },
    }
end

function AppHost.allows(appId, source, ctx)
    local entry = Apps.registered[appId]

    if not entry then return false end
    if not entry.def.canOpen then return true end

    return call(appId, 'canOpen', entry.def.canOpen, source, Util.copy(ctx)) == true
end

function AppHost.url(appId, kind, mode)
    local entry = Apps.registered[appId]

    if not entry then return nil end

    return ('https://cfx-nui-%s/%s?host=%s&app=%s&kind=%s&mode=%s&v=%s'):format(
        entry.resource,
        entry.def.page,
        GetCurrentResourceName(),
        appId,
        kind,
        mode,
        entry.def.version
    )
end

function AppHost.pictures(resource, list)
    local links = {}

    for index, path in ipairs(list or {}) do
        links[index] = AppRules.isLink(path) and path or ('https://cfx-nui-%s/%s'):format(resource, path)
    end

    return links
end

function AppHost.appView(appId, kind)
    local entry = Apps.registered[appId]
    local def = entry.def

    return {
        id = appId,
        label = def.label,
        version = def.version,
        icon = Util.copy(def.icon),
        canvas = Util.copy(def.canvas),
        window = def.window[kind] and Util.copy(def.window[kind]) or nil,
        network = def.network,
        watch = def.watch,
        resource = entry.resource,
        description = def.description,
        size = def.size,
        category = def.category or AppRules.defaultCategory(entry.resource),
        about = def.about,
        can = Util.copy(def.can or {}),
        pictures = AppHost.pictures(entry.resource, def.pictures),
        cover = def.cover and AppHost.pictures(entry.resource, { def.cover })[1] or nil,
        accent = def.accent,
        kinds = Util.copy(def.kinds),
    }
end

function AppHost.lentApp(session)
    local lent = type(session) == 'table' and session.lent or nil

    return type(lent) == 'table' and lent.app or nil
end

function AppHost.onlyApp(session)
    return AppHost.lentApp(session) or (type(session) == 'table' and session.only or nil)
end

function AppHost.visible(session, device, source)
    if not OsRules.hasOs(device.kind) then
        return {}
    end

    local subject = People.subject(source)

    if not subject then
        return {}
    end

    local context = Access.context(device, source, false, false)
    local ids, seen = {}, {}
    local only = AppHost.onlyApp(session)

    if only then
        if Apps.registered[only] then
            ids[1] = only
        end
    else
        for _, id in ipairs(type(device.apps) == 'table' and type(device.apps.order) == 'table' and device.apps.order or {}) do
            if Apps.registered[id] and not seen[id] then
                seen[id] = true
                ids[#ids + 1] = id
            end
        end

        local rest = {}

        for id, entry in pairs(Apps.registered) do
            if not seen[id] and Util.contains(entry.def.kinds, device.kind) then
                rest[#rest + 1] = id
            end
        end

        table.sort(rest, function(a, b)
            local la, lb = Apps.registered[a].def.label, Apps.registered[b].def.label

            if la == lb then
                return a < b
            end

            return la < lb
        end)

        for _, id in ipairs(rest) do
            ids[#ids + 1] = id
        end
    end

    local list = {}

    for _, id in ipairs(ids) do
        if Apps.decide(device, id, subject, context) and AppHost.allows(id, source, AppHost.context(session, device, id)) then
            list[#list + 1] = AppHost.appView(id, device.kind)
        end
    end

    return list
end

local function text(value, limit)
    if type(value) == 'number' then
        value = tostring(value)
    end

    if type(value) ~= 'string' then return nil end

    local clean = Util.cleanText(value, limit)

    if not clean or clean == '' then return nil end

    return clean
end

function AppHost.cleanNotice(value)
    if type(value) ~= 'table' then return nil end

    local title = text(value.title, 80)

    if not title then return nil end

    local notice = {
        id = text(value.id, 64),
        title = title,
        body = text(value.body, 240) or '',
        action = text(value.action, 32),
    }

    if Util.isFinite(value.at) then
        notice.at = math.floor(value.at)
    end

    if type(value.intent) == 'table' and bytes(value.intent) <= AppHost.INTENT_BYTES then
        notice.intent = Util.copy(value.intent)
    end

    return notice
end

function AppHost.notices(session, device, visible)
    local AppStore = require 'server.appstore'

    local list = {}

    for _, view in ipairs(visible) do
        local entry = Apps.registered[view.id]

        if entry and entry.def.notices and AppStore.shown(session, device, view.id) then
            local result = call(
                view.id,
                'notices',
                entry.def.notices,
                session.source,
                AppHost.context(session, device, view.id)
            )

            local count = 0

            for _, raw in ipairs(type(result) == 'table' and result or {}) do
                local notice = AppHost.cleanNotice(raw)

                if notice and count < NOTICES_PER_APP then
                    count = count + 1
                    notice.app = view.id
                    notice.id = notice.id or (view.id .. ':' .. count)
                    list[#list + 1] = notice
                end
            end
        end
    end

    return list
end

local function begin(session, device, appId)
    local ctx = AppHost.context(session, device, appId)
    local entry = Apps.registered[appId]
    local context = {}

    if entry.def.onOpen then
        local result = call(appId, 'onOpen', entry.def.onOpen, session.source, Util.copy(ctx))

        if type(result) == 'table' and bytes(result) <= CONTEXT_BYTES then
            context = result
        end
    end

    local open = { token = Util.hex(32), since = os.time(), ctx = ctx, context = context, checkedAt = GetGameTimer() }

    session.apps[appId] = open
    TriggerEvent('evolent_devices:appOpened', session.source, appId, Util.copy(ctx))

    return open
end

function AppHost.drop(session, appId, reason, tell, key)
    local open = session.apps and session.apps[appId]

    if not open then return false end

    session.apps[appId] = nil

    local entry = Apps.registered[appId]

    if entry and entry.def.onClose then
        call(appId, 'onClose', entry.def.onClose, session.source, Util.copy(open.ctx), reason)
    end

    TriggerEvent('evolent_devices:appClosed', session.source, appId, reason)

    if tell then
        TriggerClientEvent('evdev:client:appClosed', session.source, key or session.id or 'tablet', appId, reason)
    end

    return true
end

function AppHost.dropAll(session, reason)
    for _, appId in ipairs(Util.keys(session.apps or {})) do
        AppHost.drop(session, appId, reason, false)
    end
end

function AppHost.closeEverywhere(appId, reason)
    local Tablets = require 'server.tablet'

    for _, id in ipairs(Util.keys(Sessions.locks)) do
        local lock = Sessions.locks[id]

        if lock and type(lock.apps) == 'table' and lock.apps[appId] then
            if lock.kind == 'terminal' and lock.token then
                Sessions.close(id, reason)
            else
                AppHost.drop(lock, appId, reason, true, id)
            end
        end
    end

    for _, tablet in pairs(Tablets.open) do
        if type(tablet.apps) == 'table' and tablet.apps[appId] then
            AppHost.drop(tablet, appId, reason, true, 'tablet')
        end
    end
end

function AppHost.signal(session, device)
    if session.signal == nil then
        local reading = device.kind == 'tablet' and Signal.forPlayer(session.source, 'tablet') or Signal.forDevice(device)

        session.signal = reading.bars
    end

    return session.signal
end

function AppHost.open(source, token, appId, intent)
    local session, device = AppHost.find(source, token)

    if not session then
        return Util.fail('device_closed')
    end

    if not AppRules.isId(appId) then
        return Util.fail('unknown_app')
    end

    if not Guard.rate(source, 'app_open', 4, 1000) then
        return Util.fail('slow_down')
    end

    if session.passwordLocked then
        return Util.fail('device_locked')
    end

    local lent = AppHost.lentApp(session)

    if lent and lent ~= appId then
        return Util.fail('app_access')
    end

    if session.only and session.only ~= appId then
        return Util.fail('single_app')
    end

    if not OsRules.hasOs(device.kind) then
        return Util.fail('app_wrong_kind')
    end

    local subject = Bridge.subject(source)

    if not subject then
        return Util.fail('not_ready')
    end

    local allowed, reason = Apps.decide(device, appId, subject, Access.context(device, source, false, false))

    if not allowed then
        return Util.fail(reason)
    end

    local entry = Apps.registered[appId]
    local open = session.apps[appId]

    if not open and Util.count(session.apps) >= Config.limits.appWindows then
        return Util.fail('too_many_windows')
    end

    if entry.def.network and AppHost.signal(session, device) == 0 then
        return Util.fail('no_signal')
    end

    if not AppHost.allows(appId, source, AppHost.context(session, device, appId)) then
        return Util.fail('app_access')
    end

    open = open or begin(session, device, appId)

    local reply = AppHost.appView(appId, device.kind)

    reply.resource = nil
    reply.token, reply.context, reply.url, reply.protocol = open.token, open.context, AppHost.url(appId, device.kind, 'use'), AppRules.PROTOCOL

    if type(intent) == 'table' and bytes(intent) <= AppHost.INTENT_BYTES then
        reply.intent = intent
    end

    return Util.ok(reply)
end

function AppHost.close(source, token, appId)
    local session = AppHost.find(source, token)

    if not session then
        return Util.fail('device_closed')
    end

    return Util.ok({ closed = AppHost.drop(session, appId, 'app_closed', false) })
end

function AppHost.pageApp(device)
    local page = type(device.page) == 'table' and device.page or nil

    if not page or not AppRules.isId(page.app) then
        return nil, 'no_page'
    end

    local entry, row = Apps.registered[page.app], Apps.rows[page.app]

    if not entry or not Apps.running(page.app) then
        return nil, 'app_stopped'
    end

    if not row or row.status ~= 'allowed' then
        return nil, row and row.status == 'blocked' and 'app_blocked' or 'app_pending'
    end

    if not row.enabled then
        return nil, 'app_off'
    end

    if not entry.def.terminal then
        return nil, 'app_wrong_kind'
    end

    return page.app
end

function AppHost.watchView(device, appId)
    local entry = Apps.registered[appId]

    if not entry or entry.def.watch ~= 'state' then
        return 'cover'
    end

    if Registry.settings.general.forceCover == true then
        return 'cover'
    end

    if Apps.options(appId).watch == 'cover' then
        return 'cover'
    end

    local apps = type(device.apps) == 'table' and device.apps or {}

    if apps.watch == 'cover' then
        return 'cover'
    end

    local own = type(apps.entries) == 'table' and apps.entries[appId] or nil

    if own and own.watch == 'cover' then
        return 'cover'
    end

    return 'state'
end

local function watchData(appId, open)
    local entry = Apps.registered[appId]

    if not entry or not entry.def.watchData then return nil end

    local data = call(appId, 'watchData', entry.def.watchData, Util.copy(open.ctx))

    if type(data) == 'table' and bytes(data) <= WATCH_BYTES then
        return data
    end

    return nil
end

local function openTerminal(lock, device, answer)
    local appId = AppHost.pageApp(device)

    if not appId then return end

    local ctx = AppHost.context(lock, device, appId)

    if not AppHost.allows(appId, lock.source, ctx) then return end

    local entry = Apps.registered[appId]
    local open = begin(lock, device, appId)

    answer.page = { resource = entry.resource, path = entry.def.page, app = appId, version = entry.def.version }

    answer.app = {
        id = appId,
        label = entry.def.label,
        token = open.token,
        context = open.context,
        protocol = AppRules.PROTOCOL,
    }
end

function AppHost.listed(visible, id)
    for _, view in ipairs(visible) do
        if view.id == id then return true end
    end

    return false
end

function AppHost.signature(visible, installed)
    return json.encode({ visible, installed })
end

function AppHost.onlyView(session, device, visible)
    local id = session.only

    if not id then return nil end

    local view = { id = id }

    if Apps.isBuiltin(id) then
        if not OsRules.enabled(id) then
            view.reason = 'app_off'
        end

        return view
    end

    local entry, row = Apps.registered[id], Apps.rows[id]

    view.label = entry and entry.def.label or row and row.label or id
    view.icon = entry and Util.copy(entry.def.icon) or nil

    if AppHost.listed(visible, id) then
        return view
    end

    if not entry and not row then
        view.reason = 'unknown_app'

        return view
    end

    local subject = People.subject(session.source)

    if not subject then
        view.reason = 'not_ready'

        return view
    end

    local ok, reason = Apps.decide(device, id, subject, Access.context(device, session.source, false, false))

    view.reason = ok and 'app_access' or reason

    return view
end

Sessions.on('open', function(lock, device, answer)
    local AppStore = require 'server.appstore'
    local Devices = require 'server.devices'

    lock.apps = lock.apps or {}
    AppHost.dropAll(lock, 'device_reopened')
    lock.listAt = GetGameTimer()
    lock.only = Devices.onlyApp(device)

    if device.kind == 'terminal' then
        openTerminal(lock, device, answer)

        return nil
    end

    local visible = AppHost.visible(lock, device, lock.source)
    local installed = AppStore.ids(lock, device, visible)

    lock.listSig = AppHost.signature(visible, installed)
    lock.onlyView = AppHost.onlyView(lock, device, visible)
    answer.only = lock.onlyView and Util.copy(lock.onlyView) or nil
    answer.apps = visible
    answer.installed = installed
    answer.notices = AppHost.notices(lock, device, visible)
    answer.windows = Config.limits.appWindows
    answer.protocol = AppRules.PROTOCOL

    return nil
end)

function AppHost.sweep(session, device, now, key)
    if not next(session.apps or {}) then return nil end

    if device.kind == 'terminal' then
        local appId, reason = AppHost.pageApp(device)

        for id, open in pairs(session.apps) do
            if id ~= appId then
                return reason or 'app_stopped'
            end

            if now - (open.checkedAt or 0) >= CAN_OPEN_MS then
                open.checkedAt = now

                if not AppHost.allows(id, session.source, open.ctx) then
                    return 'app_access'
                end
            end
        end

        return nil
    end

    local subject = People.subject(session.source)

    if not subject then return nil end

    local context = Access.context(device, session.source, false, false)

    for _, appId in ipairs(Util.keys(session.apps)) do
        local open = session.apps[appId]
        local ok, reason = Apps.decide(device, appId, subject, context)

        if ok and now - (open.checkedAt or 0) >= CAN_OPEN_MS then
            open.checkedAt = now

            if not AppHost.allows(appId, session.source, open.ctx) then
                ok, reason = false, 'app_access'
            end
        end

        if not ok then
            AppHost.drop(session, appId, reason, true, key)
        end
    end

    return nil
end

function AppHost.refreshList(session, device, now)
    local AppStore = require 'server.appstore'

    if now - (session.listAt or 0) < LIST_MS then return end

    session.listAt = now

    local visible = AppHost.visible(session, device, session.source)
    local installed = AppStore.ids(session, device, visible)
    local signature = AppHost.signature(visible, installed)

    if signature == session.listSig then return end

    session.listSig = signature
    TriggerClientEvent('evdev:client:apps', session.source, visible, installed)
end

Sessions.on('tick', function(lock, device, now)
    local reason = AppHost.sweep(lock, device, now, lock.id)

    if reason then
        return reason
    end

    if OsRules.hasOs(device.kind) then
        AppHost.refreshList(lock, device, now)
    end

    return nil
end)

Sessions.on('close', function(lock, reason)
    AppHost.dropAll(lock, reason or 'device_closed')
end)

Sessions.on('watch', function(lock, reply)
    local DeviceLook = require 'server.look'

    local device = Registry.device(lock.id)

    if not device then return nil end

    if device.kind == 'terminal' then
        local appId = AppHost.pageApp(device)
        local open = appId and lock.apps[appId]

        if not open then return nil end

        local entry = Apps.registered[appId]

        if AppHost.watchView(device, appId) == 'state' then
            reply.page = { resource = entry.resource, path = entry.def.page, app = appId, version = entry.def.version }
            reply.extra.app = { id = appId, data = watchData(appId, open) }
        else
            local look = DeviceLook.get(device)
            local icon = Util.copy(entry.def.icon)

            if look then
                icon.color = look.accent
            end

            reply.page = { resource = GetCurrentResourceName(), path = 'web/build/os.html' }
            reply.extra.cover = { id = appId, label = entry.def.label, icon = icon }
        end

        return nil
    end

    local ids = Util.keys(lock.apps or {})

    table.sort(ids, function(a, b) return (lock.apps[a].since or 0) < (lock.apps[b].since or 0) end)

    local list, states = {}, 0

    for _, appId in ipairs(ids) do
        local entry = Apps.registered[appId]

        if entry then
            local item = AppHost.appView(appId, device.kind)

            item.resource, item.view = nil, 'cover'

            if AppHost.watchView(device, appId) == 'state' and states < STATE_WATCHERS then
                states = states + 1

                item.view, item.url, item.data = 'state', AppHost.url(appId, device.kind, 'watch'), watchData(
                    appId,
                    lock.apps[appId]
                )
            end

            list[#list + 1] = item
        end
    end

    reply.extra.apps = list
    reply.extra.only = lock.onlyView and Util.copy(lock.onlyView) or nil

    return nil
end)

function AppHost.tabletOpen(source, session)
    local AppStore = require 'server.appstore'

    session.apps = {}

    local device = AppHost.tabletDevice()
    local visible = AppHost.visible(session, device, source)
    local installed = AppStore.ids(session, device, visible)

    session.listSig, session.listAt = AppHost.signature(visible, installed), GetGameTimer()

    return visible, AppHost.notices(session, device, visible), installed
end

function AppHost.tickTablets(now)
    local Tablets = require 'server.tablet'

    local device = AppHost.tabletDevice()

    for _, session in pairs(Tablets.open) do
        if session.token then
            AppHost.sweep(session, device, now, 'tablet')
            AppHost.refreshList(session, device, now)
        end
    end
end

function AppHost.user(source, appId)
    for _, entry in ipairs(AppHost.sessions(source)) do
        local open = entry.session.apps and entry.session.apps[appId]

        if open then
            local registered = Apps.registered[appId]

            if registered and registered.def.network and AppHost.signal(entry.session, entry.device) == 0 then return nil end

            local ctx = Util.copy(open.ctx)

            ctx.token, ctx.since = open.token, open.since

            return ctx
        end
    end

    return nil
end

local function owned(appId, invoker)
    local entry = Apps.registered[appId]

    if not entry then
        return nil, 'unknown_app'
    end

    if invoker and invoker ~= entry.resource and invoker ~= GetCurrentResourceName() then
        return nil, 'not_your_app'
    end

    return entry
end

AppHost.owned = owned

function AppHost.isOpen(source, appId)
    for _, entry in ipairs(AppHost.sessions(source)) do
        if entry.session.apps and entry.session.apps[appId] then return true end
    end

    return false
end

function AppHost.message(source, appId, message, invoker)
    local entry, reason = owned(appId, invoker)

    if not entry then
        return false, reason
    end

    if type(message) ~= 'table' then
        return false, 'invalid_message'
    end

    if bytes(message) > MESSAGE_BYTES then
        return false, 'message_too_big'
    end

    if not AppHost.isOpen(source, appId) then
        return false, 'not_open'
    end

    if not Guard.rate(source, 'app_message:' .. appId, 30, 1000) then
        return false, 'slow_down'
    end

    TriggerClientEvent('evdev:client:appMessage', source, appId, message)

    return true
end

function AppHost.closeFor(source, appId, reason, invoker)
    local entry, refusal = owned(appId, invoker)

    if not entry then
        return false, refusal
    end

    local closed = false
    local key = Sessions.bySource[source]

    for _, item in ipairs(AppHost.sessions(source)) do
        local isTablet = item.device.kind == 'tablet'

        closed = AppHost.drop(item.session, appId, type(reason) == 'string' and reason:sub(1, 32) or 'app_closed', true, isTablet and 'tablet' or key) or closed
    end

    return closed
end

Guard.register('evdev:app:open', function(source, token, appId, intent)
    return AppHost.open(source, token, appId, intent)
end, { rate = 6 })

Guard.register('evdev:app:close', function(source, token, appId)
    return AppHost.close(source, token, appId)
end, { rate = 8 })

return AppHost
