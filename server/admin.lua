local Config = require 'config'
local Integrations = require 'integrations'
local Bridge = require 'bridge'
local Util = require 'shared.util'
local AccessRules = require 'shared.access'
local AppRules = require 'shared.apps'
local OsRules = require 'shared.os'
local ConfigRules = require 'shared.config_rules'
local Guard = require 'server.guard'
local Audit = require 'server.audit'
local Registry = require 'server.registry'
local Settings = require 'server.settings'
local People = require 'server.people'
local Spaces = require 'server.spaces'
local Access = require 'server.access'
local Apps = require 'server.apps'
local Sessions = require 'server.sessions'
local Signal = require 'server.signal'
local DeviceScreen = require 'server.screen'
local DeviceOs = require 'server.os'
local Devices = require 'server.devices'
local Items = require 'server.items'
local Brand = require 'server.brand'

local Admin = {}

local register, idArg = Guard.register, Guard.idArg

local function rates()
    return Config.admin.rate
end

local function onDevice(handler)
    return function(actor, id, ...)
        local found = Registry.device(idArg(id))

        if not found then
            return Util.fail('unknown_device')
        end

        return handler(actor, found, ...)
    end
end

function Admin.open(source, focus)
    local level = Guard.level(source)

    if not level then
        Bridge.notify(source, locale('admin_no_access'), 'error')

        return false
    end

    if not Bridge.getCharacterId(source) then return false end

    local token = Guard.issue(source)
    local id = idArg(focus)

    TriggerClientEvent('evdev:client:openAdmin', source, {
        token = token,
        level = level,
        device = id and Registry.device(id) and id or nil,
    })

    return true
end

function Admin.kinds()
    local list = {}

    for _, kind in ipairs(Config.kindOrder) do
        local spec = Config.kinds[kind]

        list[#list + 1] = {
            kind = kind,
            label = locale('kind_' .. kind),
            variants = Util.copy(spec.variants),
            placeOn = spec.placeOn,
            os = spec.os == true,
            placeable = Devices.placeable(kind),
            item = Items.itemName(kind),
            enabled = Settings.kindEnabled(kind),
        }
    end

    return list
end

function Admin.twins(found)
    local list = {}

    if found.state ~= 'placed' or not found.x then
        return list
    end

    for _, entry in ipairs(Registry.placedNear(found, Spaces.ofDevice(found), Registry.settings.general.twinRadius, found.kind)) do
        if entry.device.id ~= found.id and entry.device.variant and not list[entry.device.variant] then
            list[entry.device.variant] = { id = entry.device.id, distance = Util.round(entry.distance, 1) }
        end
    end

    return list
end

local function settingsView()
    local diff = Registry.settings.config or {}

    return {
        settings = Util.copy(Registry.settings),
        defaults = Settings.defaults(),
        rev = Registry.settingsRev,
        aces = { admin = Config.aces.admin, manage = Config.aces.manage },
        items = Items.status(),
        trusted = Util.copy(Config.trustedResources),
        config = ConfigRules.view(diff),
    }
end

function Admin.applyConfig(diff)
    local changed = ConfigRules.apply(diff)

    GlobalState[ConfigRules.KEY] = ConfigRules.compact(Util.copy(diff))

    return changed
end

function Admin.waiting()
    local count = 0

    for _, row in pairs(Apps.rows) do
        if row.status == 'pending' then
            count = count + 1
        end
    end

    return count
end

function Admin.pushCounts(known)
    if not Registry.ready then return 0 end

    local counts, waiting, sent = known or Devices.counts(), Admin.waiting(), 0

    for source in pairs(Guard.tokens) do
        local level = Guard.level(source)

        if level then
            TriggerClientEvent('evdev:client:counts', source, {
                counts = counts,
                waiting = level == 'admin' and waiting or nil,
            })
            sent = sent + 1
        end
    end

    return sent
end

function Admin.framework()
    local info = Bridge.info()

    return {
        id = info.id,
        label = info.label,
        gangs = info.gangs == true,
        multiJob = info.multiJob == true,
        homes = Integrations.propertiesReady(),
        inventory = Integrations.inventoryName(),
        metadata = Integrations.keepsMetadata(),
    }
end

register('evdev:admin:boot', function(actor)
    return Util.ok({
        level = actor.level,
        me = { id = actor.source, cid = actor.cid, name = actor.name },
        kinds = Admin.kinds(),
        aces = { admin = Config.aces.admin, manage = Config.aces.manage },
        limits = {
            rules = Config.limits.rulesPerList,
            apps = Config.limits.appsPerDevice,
            zones = Config.limits.zones,
            label = Config.limits.labelLength,
            placeRange = Config.admin.placeRange,
        },
        actions = Audit.ACTIONS,
        ruleTypes = AccessRules.TYPES,
        counts = Devices.counts(),
        now = os.time(),
        command = Config.commands.admin,
        debug = Config.debug == true,
        version = GetResourceMetadata(GetCurrentResourceName(), 'version', 0),
        framework = Admin.framework(),
    })
end, { level = 'manage' })

register('evdev:admin:close', function(actor)
    Guard.drop(actor.source)

    return Util.ok({})
end, { level = 'manage' })

register('evdev:admin:list', function(actor, filter)
    local clean = Devices.normalizeFilter(filter)

    if not clean then
        return Util.fail('invalid_filter')
    end

    return Util.ok(Devices.list(clean, Devices.adminSpot(actor.source)))
end, { level = 'manage' })

register('evdev:admin:device', onDevice(function(actor, found)
    local memo = Access.memo()
    local kind = Config.kinds[found.kind].os and found.kind or 'terminal'
    local audit = Audit.list({ deviceId = found.id, limit = 25 })

    return Util.ok({
        device = Devices.detailView(found, memo),
        apps = Apps.forKind(kind, memo),
        builtins = OsRules.apps(found.kind),
        providers = Access.providersView(),
        variants = Util.copy(Config.kinds[found.kind].variants),
        twins = Admin.twins(found),
        keysAllowed = found.propertyId ~= nil,
        restorable = Devices.restorable(found),
        canGiveBack = found.origin == 'item' and found.ownerCid ~= nil and found.state == 'placed' and Config.items[found.kind] ~= nil and found.kind ~= 'tablet',
        canReissue = found.origin == 'item' and found.ownerCid ~= nil and found.state == 'carried' and found.serial ~= nil and Config.items[found.kind] ~= nil and found.kind ~= 'tablet',
        canEditOwner = actor.level == 'admin',
        screen = Devices.placeable(found.kind) and DeviceScreen.info(found.kind) or nil,
        inUse = Sessions.user(found.id),
        audit = audit and audit.rows or {},
    })
end), { level = 'manage' })

register('evdev:admin:password', onDevice(function(actor, found, action, password)
    if not OsRules.hasOs(found.kind) or found.temporary or found.state == 'removed' then
        return Util.fail('password_not_here')
    end

    if action == 'clear' then
        if DeviceOs.hasPassword(found.id) then
            DeviceOs.clearPassword(found.id, actor)
        end

        return Util.ok({ password = false })
    end

    if action ~= 'set' then
        return Util.fail('invalid_password')
    end

    local clean = OsRules.password(password)

    if not clean then
        return Util.fail('invalid_password')
    end

    DeviceOs.setPassword(found.id, clean, actor)

    return Util.ok({ password = true })
end), { level = 'manage', rate = rates().write })

register('evdev:admin:groups', function()
    local groups = Bridge.groups()

    return Util.ok({ jobs = Util.copy(groups.jobs), gangs = Util.copy(groups.gangs), noGangs = not Bridge.info().gangs })
end, { level = 'manage' })

register('evdev:admin:players', function()
    local list = {}

    for _, source in ipairs(People.online()) do
        local subject = People.subject(source)

        if subject and subject.cid then
            list[#list + 1] = { id = source, name = subject.name or subject.cid, cid = subject.cid }
        end
    end

    table.sort(list, function(a, b)
        if a.name == b.name then
            return a.id < b.id
        end

        return a.name < b.name
    end)

    return Util.ok({ players = list })
end, { level = 'manage' })

register('evdev:admin:citizen', function(_, cid)
    if not Util.isCid(cid) then
        return Util.fail('bad_citizen')
    end

    local found = Access.lookupCitizen(cid)

    if not found then
        return Util.fail('unknown_citizen')
    end

    return Util.ok({ cid = found.cid, name = found.name, online = found.online == true, id = found.source })
end, { level = 'manage', rate = rates().lookup })

register('evdev:admin:providers', function()
    return Util.ok({ providers = Access.providersView() })
end, { level = 'manage' })

register('evdev:admin:place', function(actor, kind, args)
    return Devices.place(actor, Guard.stringArg(kind, 16), args)
end, { level = 'manage', rate = rates().write })

register('evdev:admin:move', onDevice(function(actor, found, position, version)
    return Devices.move(actor, found, Guard.tableArg(position), version)
end), { level = 'manage', rate = rates().write })

register('evdev:admin:save', onDevice(function(actor, found, version, patch)
    return Devices.save(actor, found, version, patch)
end), { level = 'manage', rate = rates().write })

register('evdev:admin:remove', onDevice(function(actor, found, mode, typed)
    return Devices.remove(actor, found, mode ~= nil and Guard.stringArg(mode, 16) or nil, typed)
end), { level = 'manage', rate = rates().write })

register('evdev:admin:reissue', onDevice(function(actor, found)
    return Items.reissue(actor, found)
end), { level = 'manage', rate = rates().write })

register('evdev:admin:restore', onDevice(function(actor, found)
    return Devices.restore(actor, found)
end), { level = 'manage', rate = rates().write })

register('evdev:admin:kick', onDevice(function(actor, found)
    local user = Sessions.user(found.id)
    local closed = Sessions.close(found.id, 'admin')

    if closed then
        Audit.write(actor, 'kick', found.id, { user = user and user.name or nil })
    end

    return Util.ok({ closed = closed })
end), { level = 'manage', rate = rates().write })

register('evdev:admin:check', onDevice(function(_, found, serverId, access)
    local target = idArg(serverId)

    if not target or not GetPlayerName(target) then
        return Util.fail('unknown_player')
    end

    local draft

    if access ~= nil then
        local reason, index

        draft, reason, index = Access.validate(access, found, { current = found.access })

        if not draft then
            return Util.fail(reason, { field = 'access', rule = index })
        end
    end

    local result, reason = Access.check(found, target, draft)

    if not result then
        return Util.fail(reason)
    end

    return Util.ok(result)
end), { level = 'manage', rate = rates().write })

register('evdev:admin:signal:why', onDevice(function(_, found)
    return Util.ok(Signal.why(found))
end), { level = 'manage' })

register('evdev:admin:screen:bulk', function(actor, picture, ids, dryRun)
    return Devices.applyPicture(actor, Guard.tableArg(picture), ids, dryRun == true)
end, { level = 'manage', rate = rates().write })

register('evdev:admin:audit', function(_, filter)
    local result, reason = Audit.list(filter)

    if not result then
        return Util.fail(reason)
    end

    return Util.ok(result)
end, { level = 'manage' })

register('evdev:admin:give', function(actor, kind, serverId)
    local target = idArg(serverId)

    if not target or not GetPlayerName(target) then
        return Util.fail('unknown_player')
    end

    return Items.give(actor, Guard.stringArg(kind, 16), target)
end, { level = 'admin', rate = rates().write })

register('evdev:admin:settings', function()
    return Util.ok(settingsView())
end, { level = 'admin' })

register('evdev:admin:settings:save', function(actor, patch, rev)
    return Guard.exclusive('settings', function()
        if rev ~= nil and Util.integer(rev) ~= Registry.settingsRev then
            return Util.fail('settings_changed', { rev = Registry.settingsRev })
        end

        local before = Registry.settings
        local settings, reason, path = Settings.apply(before, patch)

        if not settings then
            return Util.fail(reason, { field = path })
        end

        Registry.saveSettings(settings)
        Audit.write(actor, 'settings', nil, { changes = Settings.changes(before, settings) })

        if not Util.same(before.config or {}, settings.config or {}) then
            Admin.applyConfig(settings.config or {})
        end

        if before.general.adminsOpenAny ~= settings.general.adminsOpenAny then
            Access.pushAll()
        end

        local old, new = before.general, settings.general

        if old.watchRange ~= new.watchRange or not Util.same(old.sound, new.sound) or not Util.same(old.display, new.display) then
            Registry.rev = Registry.rev + 1
            GlobalState['evdev:rev'] = Registry.rev
        end

        for _, kind in ipairs(Config.kindOrder) do
            if before.kinds[kind].enabled ~= settings.kinds[kind].enabled then
                TriggerClientEvent('evdev:client:kinds', -1, Admin.kinds())
                break
            end
        end

        return Util.ok(settingsView())
    end)
end, { level = 'admin', rate = rates().write })

register('evdev:admin:zones:save', function(actor, list, rev)
    return Guard.exclusive('settings', function()
        if rev ~= nil and Util.integer(rev) ~= Registry.settingsRev then
            return Util.fail('settings_changed', { rev = Registry.settingsRev })
        end

        local zones, reason, index = Settings.normalizeZones(list)

        if not zones then
            return Util.fail(reason, { zone = index })
        end

        local before = Registry.settings.zones

        Registry.saveZones(zones)
        Audit.write(actor, 'zones', nil, Settings.zoneChanges(before, zones))

        return Util.ok(settingsView())
    end)
end, { level = 'admin', rate = rates().write })

register('evdev:admin:brand', function()
    return Util.ok(Brand.view())
end, { level = 'admin' })

register('evdev:admin:brand:save', function(actor, input)
    return Guard.exclusive('brand', function()
        return Brand.save(actor, Guard.tableArg(input))
    end)
end, { level = 'admin', rate = rates().write })

register('evdev:admin:brand:reset', function(actor)
    return Guard.exclusive('brand', function()
        return Brand.reset(actor)
    end)
end, { level = 'admin', rate = rates().write })

register('evdev:admin:apps', function()
    local memo = Access.memo()
    local list = Apps.list(memo)
    local counts = Devices.appCounts()

    for _, view in ipairs(list) do
        view.devices = counts[view.id]
    end

    return Util.ok({
        apps = list,
        providers = Access.providersView(),
        trusted = Util.copy(Config.trustedResources),
    })
end, { level = 'admin' })

register('evdev:admin:apps:save', function(actor, id, patch)
    if not AppRules.isId(id) then
        return Util.fail('unknown_app')
    end

    local before = Apps.rows[id] and Apps.rows[id].status
    local view, reason = Apps.save(actor, id, patch)

    if not view then
        return Util.fail(reason)
    end

    local counts = Devices.counts()

    if before ~= (Apps.rows[id] and Apps.rows[id].status) then
        Admin.pushCounts(counts)
    end

    return Util.ok({ app = view, counts = counts, waiting = Admin.waiting() })
end, { level = 'admin', rate = rates().write })

register('evdev:admin:apps:devices', function(_, id)
    if not AppRules.isId(id) then
        return Util.fail('unknown_app')
    end

    local result, reason = Devices.appDevices(id)

    if not result then
        return Util.fail(reason)
    end

    return Util.ok(result)
end, { level = 'admin' })

register('evdev:admin:apps:bulk', function(actor, id, wanted, dryRun)
    if not AppRules.isId(id) then
        return Util.fail('unknown_app')
    end

    return Devices.applyApp(actor, id, Guard.tableArg(wanted), dryRun == true)
end, { level = 'admin', rate = rates().write })

register('evdev:admin:signal', function(actor)
    return Util.ok(Signal.view(actor))
end, { level = 'admin' })

register('evdev:admin:signal:save', function(actor, patch, rev)
    return Guard.exclusive('signal', function()
        return Signal.save(actor, patch, rev)
    end)
end, { level = 'admin', rate = rates().write })

register('evdev:admin:goto', onDevice(function(actor, found)
    if found.state ~= 'placed' or not found.x then
        return Util.fail('no_position')
    end

    local here = Spaces.of(actor.source)
    local space = Spaces.ofDevice(found)

    TriggerClientEvent('evdev:client:goto', actor.source, {
        x = found.x,
        y = found.y,
        z = found.z,
        h = found.heading or 0.0,
        kind = found.kind,
    })

    return Util.ok({ space = space, sameSpace = here == space })
end), { level = 'admin', rate = rates().write })

RegisterCommand(Config.commands.admin, function(source, args)
    if source <= 0 then
        print(('[evolent_devices] /%s works in game only.'):format(Config.commands.admin))

        return
    end

    if not Registry.ready then
        local text = locale(Registry.failed and 'admin_failed' or 'admin_not_ready')

        if Bridge.notify then
            Bridge.notify(source, text, 'error')
        else
            TriggerClientEvent('ox_lib:notify', source, { title = locale('brand'), description = text, type = 'error' })
        end

        return
    end

    Admin.open(source, args and args[1])
end, false)

RegisterNetEvent('evdev:server:openAdmin', function(id)
    local source = source

    if not Registry.ready or not Guard.rate(source, 'openAdmin', 1, 2000) then return end

    Admin.open(source, id)
end)

return Admin
