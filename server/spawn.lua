local Config = require 'config'
local Util = require 'shared.util'
local AppRules = require 'shared.apps'
local OsRules = require 'shared.os'
local Store = require 'server.store'
local Guard = require 'server.guard'
local Audit = require 'server.audit'
local Registry = require 'server.registry'
local Settings = require 'server.settings'
local Spaces = require 'server.spaces'
local Access = require 'server.access'
local Apps = require 'server.apps'
local Sessions = require 'server.sessions'
local AppStore = require 'server.appstore'
local Devices = require 'server.devices'

local Spawn = { count = 0 }

Spawn.FIRST_ID = 1000000000
Spawn.base = Spawn.FIRST_ID + (os.time() % 1000000) * 1000

local function accessOf(value, owner)
    if value == nil then
        return { mode = owner and 'owner' or 'everyone', rules = {} }
    end

    if value == 'everyone' or value == 'owner' then
        return { mode = value, rules = {} }
    end

    return value
end

local function appList(value, openApp)
    if value ~= nil and type(value) ~= 'table' then
        return nil, 'invalid_apps'
    end

    local order, entries = {}, {}

    for _, item in ipairs(value or {}) do
        local id, settings = item, nil

        if type(item) == 'table' then
            id, settings = item.id, item.settings
        end

        if not AppRules.isId(id) then
            return nil, 'invalid_apps'
        end

        if not entries[id] then
            order[#order + 1] = id
        end

        entries[id] = { on = true, settings = type(settings) == 'table' and settings or {} }
    end

    if openApp ~= nil and not entries[openApp] then
        order[#order + 1] = openApp
        entries[openApp] = { on = true, settings = {} }
    end

    return order, entries
end

local function appsFor(kind, def, owner)
    if def.openApp ~= nil and not AppRules.isId(def.openApp) then
        return nil, 'invalid_open_app'
    end

    if def.onlyApp ~= nil and not AppRules.isId(def.onlyApp) then
        return nil, 'invalid_only_app'
    end

    if def.onlyApp ~= nil and not OsRules.kind(kind) then
        return nil, 'only_app_kind'
    end

    local order, entries = appList(def.apps, def.openApp)

    if not order then
        return nil, entries
    end

    if OsRules.kind(kind) then
        local apps, reason = Apps.normalizeDeviceApps(
            { order = order, entries = entries, only = def.onlyApp },
            nil,
            { kind = kind, origin = 'admin', ownerCid = owner }
        )

        if not apps then
            return nil, reason
        end

        return { apps = apps, openApp = def.openApp }
    end

    local id = order[1]

    if not id then
        return { apps = { order = {}, entries = {} } }
    end

    if #order > 1 then
        return nil, 'terminal_one_app'
    end

    if not Apps.registered[id] and not Apps.rows[id] then
        return nil, 'unknown_app'
    end

    local page, reason = Apps.normalizePage({ app = id, settings = entries[id].settings }, { app = id })

    if not page then
        return nil, reason
    end

    return { apps = { order = {}, entries = {} }, page = page }
end

local function placeOf(def)
    local spot = Util.position(def.coords)

    if not spot then
        return nil, 'invalid_position'
    end

    if def.heading ~= nil then
        if not Util.isFinite(def.heading) then
            return nil, 'invalid_position'
        end

        spot.h = Util.round(def.heading % 360, 2)
    end

    if def.player ~= nil then
        if def.bucket ~= nil or def.propertyId ~= nil then
            return nil, 'invalid_space'
        end

        local source = Util.integer(tonumber(def.player), 1)

        if not source or not GetPlayerName(source) then
            return nil, 'unknown_player'
        end

        local _, home = Spaces.of(source)

        return spot, nil, home and 0 or (GetPlayerRoutingBucket(source) or 0), home
    end

    local bucket = def.bucket == nil and 0 or Util.integer(def.bucket, 0, 2147483647)
    local propertyId = def.propertyId ~= nil and Util.integer(def.propertyId, 1, 2147483647) or nil

    if bucket == nil or (def.propertyId ~= nil and not propertyId) then
        return nil, 'invalid_space'
    end

    return spot, nil, propertyId and 0 or bucket, propertyId
end

local function owned(resource, id, placed)
    local device = Registry.device(Guard.idArg(id))

    if not device or device.state == 'removed' or (placed and device.state ~= 'placed') then
        return nil, 'unknown_device'
    end

    if resource ~= GetCurrentResourceName() and Devices.source(device) ~= resource then
        return nil, 'not_your_device'
    end

    return device
end

function Spawn.create(resource, def)
    if not Registry.ready then
        return nil, 'server_not_ready'
    end

    if type(def) ~= 'table' then
        return nil, 'invalid_definition'
    end

    local kind = def.kind

    if not Devices.placeable(kind) then
        return nil, 'invalid_kind'
    end

    if not Settings.kindEnabled(kind) then
        return nil, 'kind_off'
    end

    local spot, reason, bucket, propertyId = placeOf(def)

    if not spot then
        return nil, reason
    end

    local label = Util.cleanText(def.label or '', Config.limits.labelLength)

    if not label or Util.hasForbidden(label) then
        return nil, 'invalid_label'
    end

    local owner, ownerName = nil, nil

    if def.owner ~= nil then
        if not Util.isCid(def.owner) then
            return nil, 'bad_citizen'
        end

        local found = Access.lookupCitizen(def.owner)

        if not found then
            return nil, 'unknown_citizen'
        end

        owner, ownerName = found.cid, Util.cleanText(found.name or '', 64) or found.cid
    end

    local access, why = Access.validate(accessOf(def.access, owner), { propertyId = propertyId }, {})

    if not access then
        return nil, why
    end

    local apps, failure = appsFor(kind, def, owner)

    if not apps then
        return nil, failure
    end

    local temporary = def.temporary ~= false

    if not temporary then
        local limit = Registry.settings.kinds[kind].max or 0

        if limit > 0 and Devices.countPlaced(kind) >= limit then
            return nil, 'kind_limit'
        end
    end

    local space = propertyId and ('p' .. propertyId) or ('b' .. bucket)
    local variant = Devices.pickVariant(kind, spot, space, nil)
    local now = os.time()

    local device = {
        kind = kind,
        variant = variant,
        label = label,
        state = 'placed',
        x = spot.x,
        y = spot.y,
        z = spot.z,
        heading = spot.h,
        surface = Config.kinds[kind].placeOn == 'surface',
        bucket = bucket,
        propertyId = propertyId,
        origin = 'admin',
        enabled = true,
        ownerCid = owner,
        ownerName = ownerName,
        access = access,
        manage = { mode = 'owner', rules = {} },
        apps = apps.apps,
        page = apps.page,
        openApp = apps.openApp,
    }

    if temporary then
        Spawn.count = Spawn.count + 1
        device.id, device.version = Spawn.base + Spawn.count, 1
        device.temporary, device.resource = true, resource
        device.createdAt, device.updatedAt = now, now
    else
        device.legacyKey = ('res:%s:%s'):format(resource:sub(1, 50), Util.hex(8))

        local ok, id = pcall(Store.insertDevice, device)

        if not ok or not id then
            Util.log(('%s: spawnDevice could not save the %s: %s'):format(resource, kind, tostring(id)))

            return nil, 'internal_error'
        end

        device.id, device.version = id, 1
        device.createdAt, device.updatedAt = now, now
    end

    Registry.put(device)
    Registry.publish(device)
    Access.pushDevice(device)

    if not temporary then
        Audit.write(nil, 'place', device.id, {
            kind = kind,
            resource = resource,
            x = spot.x,
            y = spot.y,
            z = spot.z,
            space = space,
        })
    end

    for _, id in ipairs(apps.apps.order) do
        local row = Apps.rows[id]

        if row and row.status ~= 'allowed' then
            Util.log(('%s: app %s on device #%d waits for approval and does not show yet: /%s, Apps and integrations'):format(resource, id, device.id, Config.commands.admin))
        end
    end

    return device.id
end

function Spawn.drop(device, reason)
    Sessions.close(device.id, reason or 'removed')
    Registry.devices[device.id] = nil
    device.state = 'removed'
    device.removedAt = os.time()
    Registry.publish(device)
    Access.pushDevice(device)
    AppStore.forget(device)
end

function Spawn.remove(resource, id)
    local device, refusal = owned(resource, id, false)

    if not device then
        return false, refusal
    end

    if device.temporary then
        Spawn.drop(device, 'removed')

        return true
    end

    Sessions.close(device.id, 'removed')

    if not Devices.commit(nil, device, { state = 'removed', removedAt = os.time() }, device.version) then
        return false, 'device_changed'
    end

    Audit.write(nil, 'remove', device.id, { mode = 'delete', kind = device.kind, resource = resource })

    return true
end

function Spawn.move(resource, id, coords, heading)
    local device, refusal = owned(resource, id, true)

    if not device then
        return false, refusal
    end

    local spot = Util.position(coords)

    if not spot then
        return false, 'invalid_position'
    end

    if heading ~= nil then
        if not Util.isFinite(heading) then
            return false, 'invalid_position'
        end

        spot.h = Util.round(heading % 360, 2)
    end

    if Sessions.user(device.id) then
        return false, 'device_in_use'
    end

    local space = Spaces.ofDevice(device)

    local result = Guard.exclusive('world', function()
        local other = Devices.spacingConflict(device.kind, spot, space, device.id)

        if other then
            return Util.fail('overlap')
        end

        local variant = Devices.keepVariant(device.kind, spot, space, device.variant, device.id)
        local from = { x = device.x, y = device.y, z = device.z, space = space }
        local fields = { x = spot.x, y = spot.y, z = spot.z, heading = spot.h or device.heading, variant = variant }

        if not Devices.commit(nil, device, fields, device.version) then
            return Util.fail('device_changed')
        end

        if not device.temporary then
            Audit.write(nil, 'move', device.id, {
                from = from,
                to = { x = spot.x, y = spot.y, z = spot.z, space = space },
                resource = resource,
            })
        end

        return Util.ok()
    end)

    if not result.ok then
        return false, result.reason
    end

    return true
end

function Spawn.setOnly(resource, id, appId)
    local device, refusal = owned(resource, id, false)

    if not device then
        return false, refusal
    end

    if appId ~= nil and appId ~= false and not AppRules.isId(appId) then
        return false, 'invalid_only_app'
    end

    if not OsRules.kind(device.kind) then
        return false, 'only_app_kind'
    end

    local apps = Util.copy(type(device.apps) == 'table' and device.apps or { order = {}, entries = {} })

    apps.only = appId or nil

    local result = Devices.save(nil, device, device.version, { apps = apps })

    if not result.ok then
        return false, result.reason
    end

    return true
end

function Spawn.dropResource(resource)
    local count = 0

    for _, device in ipairs(Registry.list(function(entry) return entry.temporary and entry.resource == resource end)) do
        Spawn.drop(device, 'removed')
        count = count + 1
    end

    return count
end

function Spawn.view(device)
    local user = Sessions.user(device.id)

    return {
        id = device.id,
        kind = device.kind,
        label = device.label,
        state = device.state,
        coords = device.x and vector3(device.x, device.y, device.z) or nil,
        heading = device.heading,
        space = Spaces.ofDevice(device),
        enabled = device.enabled == true,
        temporary = device.temporary == true,
        resource = Devices.source(device),
        owner = device.ownerCid,
        serial = device.serial,
        apps = Devices.appsOn(device.apps),
        page = type(device.page) == 'table' and device.page.app or nil,
        openApp = device.openApp,
        onlyApp = Devices.onlyApp(device),
        inUse = user and { source = user.source, name = user.name, since = user.since } or nil,
    }
end

function Spawn.get(id)
    local device = Registry.device(Guard.idArg(id))

    if not device then return nil end

    return Spawn.view(device)
end

local function info(device, lock)
    return {
        kind = device.kind,
        label = device.label,
        temporary = device.temporary == true,
        resource = Devices.source(device),
        cid = lock.cid,
        name = lock.name,
    }
end

Sessions.on('open', function(lock, device, answer)
    if device.openApp and not lock.only then
        for _, view in ipairs(answer.apps or {}) do
            if view.id == device.openApp then
                answer.openApp = device.openApp
            end
        end
    end

    if lock.opened then
        TriggerEvent('evolent_devices:deviceClosed', lock.source, device.id, 'device_reopened')
    end

    lock.opened = info(device, lock)
    TriggerEvent('evolent_devices:deviceOpened', lock.source, device.id, Util.copy(lock.opened))

    return nil
end)

Sessions.on('close', function(lock, reason)
    if not lock.opened then return nil end

    lock.opened = nil
    TriggerEvent('evolent_devices:deviceClosed', lock.source, lock.id, reason or 'device_closed')

    return nil
end)

return Spawn
