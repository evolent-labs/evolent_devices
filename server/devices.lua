local Config = require 'config'
local Integrations = require 'integrations'
local Bridge = require 'bridge'
local Util = require 'shared.util'
local ScreenRules = require 'shared.screen'
local DeviceRules = require 'shared.rules'
local AccessRules = require 'shared.access'
local AppRules = require 'shared.apps'
local OsRules = require 'shared.os'
local Store = require 'server.store'
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

local Devices = {}

local PATCH_KEYS = {
    label = true,
    kind = true,
    variant = true,
    owner = true,
    enabled = true,
    access = true,
    manage = true,
    apps = true,
    page = true,
    screen = true,
    bucket = true,
    propertyId = true,
}

local WORLD_FIELDS = {
    kind = true,
    variant = true,
    enabled = true,
    bucket = true,
    propertyId = true,
    state = true,
    x = true,
    screen = true,
    page = true,
}

local ACCESS_FIELDS = {
    access = true,
    manage = true,
    ownerCid = true,
    kind = true,
    bucket = true,
    propertyId = true,
    state = true,
    enabled = true,
}

local function now()
    return os.time()
end

function Devices.placeable(kind)
    return Config.kinds[kind] ~= nil and kind ~= 'tablet'
end

function Devices.isVariant(kind, variant)
    return DeviceRules.isVariant(Config.kinds[kind], variant)
end

function Devices.keepVariant(kind, position, space, current, exceptId)
    local variant, twin = Devices.pickVariant(kind, position, space, current, exceptId)

    if twin then
        variant, twin = Devices.pickVariant(kind, position, space, nil, exceptId)
    end

    return variant, twin
end

function Devices.pickVariant(kind, position, space, keep, exceptId)
    local spec = Config.kinds[kind]
    local radius = Registry.settings.general.twinRadius
    local nearest = {}

    local function note(name, distance)
        if name and (nearest[name] == nil or distance < nearest[name]) then
            nearest[name] = distance
        end
    end

    for _, entry in ipairs(Registry.placedNear(position, space, radius, kind)) do
        if entry.device.id ~= exceptId then
            note(entry.device.variant, entry.distance)
        end
    end

    if keep and Devices.isVariant(kind, keep) then
        return keep, nearest[keep] ~= nil
    end

    local order = DeviceRules.variantOrder(spec)
    local best, bestDistance = order[1], -1

    for _, name in ipairs(order) do
        local distance = nearest[name]

        if distance == nil then
            return name, false
        end

        if distance > bestDistance then
            best, bestDistance = name, distance
        end
    end

    return best, true
end

function Devices.spacingConflict(kind, position, space, exceptId)
    local own = Config.kinds[kind].spacing or 0.0

    for _, entry in ipairs(Registry.placedNear(position, space, 3.0)) do
        local other = entry.device

        if other.id ~= exceptId then
            local needed = math.max(own, Config.kinds[other.kind] and Config.kinds[other.kind].spacing or 0.0)

            if entry.distance < needed then
                return other
            end
        end
    end

    return nil
end

function Devices.countPlaced(kind, ownerCid)
    local total = 0

    for _, device in pairs(Registry.devices) do
        if device.kind == kind and (device.state == 'placed' or (kind == 'tablet' and device.state == 'carried')) and (not ownerCid or device.ownerCid == ownerCid) then
            total = total + 1
        end
    end

    return total
end

function Devices.onlyApp(device)
    local apps = type(device.apps) == 'table' and device.apps or nil

    if not apps or not OsRules.kind(device.kind) or not AppRules.isId(apps.only) then
        return nil
    end

    return apps.only
end

function Devices.appsOn(apps)
    local list = {}

    for _, id in ipairs(type(apps) == 'table' and apps.order or {}) do
        if apps.entries and apps.entries[id] and apps.entries[id].on then
            list[#list + 1] = id
        end
    end

    return list
end

function Devices.source(device)
    if device.resource then
        return device.resource
    end

    return type(device.legacyKey) == 'string' and device.legacyKey:match('^res:(.+):%x+$') or nil
end

local function stoppedProvider(access)
    for _, rule in ipairs(type(access) == 'table' and access.rules or {}) do
        if rule.type == 'provider' and not Access.providerRunning(rule.provider) then return true end
    end

    return false
end

function Devices.attention(device)
    local codes = {}

    if device.state == 'removed' then
        return codes
    end

    if stoppedProvider(device.access) or stoppedProvider(device.manage) then
        codes[#codes + 1] = 'provider_stopped'
    end

    local access = type(device.access) == 'table' and device.access or {}

    if not device.ownerCid and (access.mode == 'owner' or (access.mode == 'rules' and #(access.rules or {}) == 0)) then
        codes[#codes + 1] = 'no_access'
    end

    if OsRules.hasOs(device.kind) then
        local missing, pending = false, false

        for id, entry in pairs(type(device.apps) == 'table' and device.apps.entries or {}) do
            if entry.on then
                if not Apps.registered[id] then
                    missing = true
                end

                if Apps.rows[id] and Apps.rows[id].status == 'pending' then
                    pending = true
                end
            end
        end

        if missing then
            codes[#codes + 1] = 'app_missing'
        end

        if pending then
            codes[#codes + 1] = 'app_pending'
        end
    elseif type(device.page) ~= 'table' then
        codes[#codes + 1] = 'no_page'
    elseif not Apps.registered[device.page.app] then
        codes[#codes + 1] = 'app_missing'
    end

    if Signal.dark(device) then
        codes[#codes + 1] = 'no_signal'
    end

    return codes
end

local function position(device)
    if not device.x then return nil end

    return { x = device.x, y = device.y, z = device.z, h = device.heading or 0.0 }
end

function Devices.ownerView(device)
    if not device.ownerCid then return nil end

    local _, subject = People.sourceOf(device.ownerCid)
    local name = subject and subject.name ~= subject.cid and subject.name or device.ownerName

    return { cid = device.ownerCid, name = name or device.ownerCid, online = subject ~= nil }
end

local function holderView(device)
    local Tablets = require 'server.tablet'

    if device.kind ~= 'tablet' or device.state ~= 'carried' or not device.serial then
        return nil
    end

    local source = Tablets.holderOf(device.serial)

    if not source then return nil end

    return { id = source, name = Bridge.getCharacterName(source) or Bridge.getCharacterId(source) or tostring(source) }
end

function Devices.summaryView(device, memo, from)
    local space = Spaces.ofDevice(device)
    local user = Sessions.user(device.id)
    local distance = nil

    if from and device.state == 'placed' and device.x and from.space == space then
        distance = Util.round(Util.distance(device, from.position), 1)
    end

    local apps = {}

    if OsRules.hasOs(device.kind) then
        apps = Devices.appsOn(device.apps)
    elseif type(device.page) == 'table' then
        apps[1] = device.page.app
    end

    return {
        id = device.id,
        kind = device.kind,
        variant = device.variant,
        label = device.label,
        state = device.state,
        origin = device.origin,
        temporary = device.temporary == true or nil,
        from = Devices.source(device),
        serial = device.serial,
        enabled = device.enabled,
        owner = Devices.ownerView(device),
        position = position(device),
        space = space,
        spaceLabel = Spaces.describe(space).text,
        access = Access.summary(device, memo),
        apps = apps,
        inUse = user,
        holder = holderView(device),
        signal = ScreenRules.signalMode(device.screen) ~= 'kind' and ScreenRules.signalMode(device.screen) or nil,
        distance = distance,
        lastUsedAt = device.lastUsedAt,
        createdAt = device.createdAt,
        removedAt = device.removedAt,
        attention = Devices.attention(device),
        password = DeviceOs.hasPassword(device.id) or nil,
        version = device.version,
    }
end

function Devices.detailView(device, memo)
    memo = memo or Access.memo()

    local view = Devices.summaryView(device, memo)

    view.surface = device.surface
    view.bucket = device.bucket
    view.propertyId = device.propertyId
    view.access = Access.describe(device.access, memo)
    view.accessSummary = Access.summary(device, memo)
    view.manage = Access.describe(device.manage, memo)
    view.apps = Util.copy(type(device.apps) == 'table' and device.apps or { order = {}, entries = {} })

    for _, entry in pairs(view.apps.entries or {}) do
        if entry.access then
            entry.access = Access.describe(entry.access, memo)
        end
    end

    view.page = Util.copy(device.page)
    view.screen = ScreenRules.resolve(device.kind, device.screen, DeviceScreen.display())
    view.legacyKey = device.legacyKey
    view.createdBy = device.createdBy
    view.updatedBy = device.updatedBy
    view.updatedAt = device.updatedAt

    if device.propertyId then
        local keys = Integrations.propertyKeys(device.propertyId, false)

        view.home = { id = device.propertyId, name = keys and keys.name or nil }
    end

    return view
end

function Devices.restorable(device)
    if device.temporary or device.state ~= 'removed' or not device.removedAt then return false end

    return now() - device.removedAt <= Registry.settings.general.removedDays * 86400
end

local function matches(device, filter, text)
    if filter.kind and device.kind ~= filter.kind then return false end

    if filter.state == 'all' then
    elseif filter.state then
        if device.state ~= filter.state then return false end
    elseif device.state == 'removed' then
        return false
    end

    if filter.owner == 'server' and device.ownerCid then return false end
    if filter.owner == 'player' and not Apps.isPlayerDevice(device) then return false end
    if filter.owner and filter.owner ~= 'server' and filter.owner ~= 'player' and device.ownerCid ~= filter.owner then return false end
    if filter.space and Spaces.ofDevice(device) ~= filter.space then return false end
    if filter.inUse and not Sessions.user(device.id) then return false end

    if filter.unusedDays then
        local last = device.lastUsedAt or device.createdAt or 0

        if now() - last < filter.unusedDays * 86400 then return false end
    end

    if filter.attention and #Devices.attention(device) == 0 then return false end

    if text then
        local owner = Devices.ownerView(device)
        local haystack = table.concat({ tostring(device.id), '#' .. tostring(device.id), device.label or '', owner and owner.name or '', owner and owner.cid or '', device.serial or '', Devices.source(device) or '' }, '\n'):lower()

        if not haystack:find(text, 1, true) then return false end
    end

    return true
end

function Devices.normalizeFilter(filter)
    if filter == nil then
        return {}
    end

    if type(filter) ~= 'table' then return nil end

    local clean = {}

    if filter.kind ~= nil then
        if not Config.kinds[filter.kind] then return nil end

        clean.kind = filter.kind
    end

    if filter.state ~= nil then
        if filter.state ~= 'placed' and filter.state ~= 'carried' and filter.state ~= 'removed' and filter.state ~= 'all' then return nil end

        clean.state = filter.state
    end

    if filter.owner ~= nil then
        if filter.owner ~= 'server' and filter.owner ~= 'player' and not Util.isCid(filter.owner) then return nil end

        clean.owner = filter.owner
    end

    if filter.space ~= nil then
        if type(filter.space) ~= 'string' or not filter.space:match('^[bp]%d+$') then return nil end

        clean.space = filter.space
    end

    if filter.unusedDays ~= nil then
        clean.unusedDays = Util.integer(filter.unusedDays, 1, 3650)

        if not clean.unusedDays then return nil end
    end

    clean.inUse = filter.inUse == true or nil
    clean.attention = filter.attention == true or nil

    if filter.search ~= nil then
        local text = Util.cleanText(filter.search, 64)

        if not text then return nil end

        if text ~= '' then
            clean.search = text:lower()
        end
    end

    clean.limit = Util.integer(filter.limit or 500, 1, 1000)

    if not clean.limit then return nil end

    return clean
end

function Devices.counts()
    local counts = {
        all = 0,
        laptop = 0,
        pc = 0,
        terminal = 0,
        tablet = 0,
        player = 0,
        inUse = 0,
        removed = 0,
        attention = 0,
    }

    for _, device in pairs(Registry.devices) do
        if device.state == 'removed' then
            counts.removed = counts.removed + 1
        else
            counts.all = counts.all + 1
            counts[device.kind] = (counts[device.kind] or 0) + 1

            if Apps.isPlayerDevice(device) then
                counts.player = counts.player + 1
            end

            if Sessions.user(device.id) then
                counts.inUse = counts.inUse + 1
            end

            if #Devices.attention(device) > 0 then
                counts.attention = counts.attention + 1
            end
        end
    end

    return counts
end

function Devices.list(filter, from)
    local memo = Access.memo()
    local list, total = {}, 0

    for _, device in ipairs(Registry.list()) do
        if matches(device, filter, filter.search) then
            total = total + 1

            if #list < filter.limit then
                list[#list + 1] = Devices.summaryView(device, memo, from)
            end
        end
    end

    return { devices = list, total = total, counts = Devices.counts() }
end

function Devices.adminSpot(source)
    local ped = GetPlayerPed(source)

    if not ped or ped == 0 then return nil end

    local coords = GetEntityCoords(ped)
    local space, propertyId = Spaces.of(source)

    return {
        position = { x = coords.x, y = coords.y, z = coords.z },
        space = space,
        propertyId = propertyId,
        bucket = GetPlayerRoutingBucket(source) or 0,
    }
end

local function inRange(spot, position)
    return spot ~= nil and Util.distance(spot.position, position) <= Config.admin.placeRange + Config.admin.placeTolerance
end

local function startAccess(kind, propertyId)
    local access = Registry.settings.kinds[kind].startAccess or { mode = 'rules', rules = {} }

    if not propertyId then
        return Access.withoutKeys(access)
    end

    return Util.copy(access)
end

local function startChoices(kind, propertyId, args)
    local chosen = {}
    local target = { kind = kind, propertyId = propertyId }

    if args.access ~= nil then
        local access, reason, index = Access.validate(args.access, target)

        if not access then
            return nil, Util.fail(reason, { field = 'access', rule = index })
        end

        chosen.access = access
    end

    if args.apps ~= nil then
        if not OsRules.hasOs(kind) then
            return nil, Util.fail('apps_not_os')
        end

        local apps, reason, id = Apps.normalizeDeviceApps(args.apps, nil, target)

        if not apps then
            return nil, Util.fail(reason, { field = 'apps', app = id })
        end

        chosen.apps = apps
    end

    if args.page ~= nil and args.page ~= false then
        if kind ~= 'terminal' then
            return nil, Util.fail('page_terminal_only')
        end

        local page, reason = Apps.normalizePage(args.page, nil)

        if page == nil then
            return nil, Util.fail(reason, { field = 'page' })
        end

        chosen.page = page or nil
    end

    return chosen
end

function Devices.place(actor, kind, args)
    if not Devices.placeable(kind) then
        return Util.fail('invalid_kind')
    end

    if not Settings.kindEnabled(kind) then
        return Util.fail('kind_off')
    end

    if type(args) ~= 'table' then
        return Util.fail('invalid_position')
    end

    local spot = Util.position(args.position)

    if not spot then
        return Util.fail('invalid_position')
    end

    local admin = Devices.adminSpot(actor.source)

    if not inRange(admin, spot) then
        return Util.fail('out_of_range')
    end

    local label = Util.cleanText(args.name or '', Config.limits.labelLength)

    if not label then
        return Util.fail('invalid_label')
    end

    if args.variant ~= nil and args.variant ~= 'auto' and not Devices.isVariant(kind, args.variant) then
        return Util.fail('invalid_variant')
    end

    local limit = Registry.settings.kinds[kind].max or 0

    if limit > 0 and Devices.countPlaced(kind) >= limit then
        return Util.fail('kind_limit', { max = limit })
    end

    local chosen, failure = startChoices(kind, admin.propertyId, args)

    if not chosen then
        return failure
    end

    return Guard.exclusive('world', function()
        local other = Devices.spacingConflict(kind, spot, admin.space)

        if other then
            return Util.fail('overlap', { id = other.id })
        end

        local warnings = {}

        local variant, twin = Devices.pickVariant(
            kind,
            spot,
            admin.space,
            args.variant ~= 'auto' and args.variant or nil
        )

        if twin then
            warnings[#warnings + 1] = 'twin'
        end

        local zone = Settings.zoneAt(spot, admin.space)

        if zone then
            warnings[#warnings + 1] = 'in_zone'
        end

        local device = {
            kind = kind,
            variant = variant,
            label = label,
            state = 'placed',
            x = spot.x,
            y = spot.y,
            z = spot.z,
            heading = spot.h,
            surface = Config.kinds[kind].placeOn == 'surface' and args.surface ~= false,
            bucket = admin.propertyId and 0 or admin.bucket,
            propertyId = admin.propertyId,
            origin = 'admin',
            enabled = true,
            access = chosen.access or startAccess(kind, admin.propertyId),
            manage = { mode = 'owner', rules = {} },
            apps = chosen.apps or { order = {}, entries = {} },
            page = chosen.page,
            createdBy = actor.cid,
            updatedBy = actor.cid,
        }

        local id = Store.insertDevice(device)

        if not id then
            return Util.fail('internal_error')
        end

        device.id = id
        device.version = 1
        device.createdAt, device.updatedAt = now(), now()
        Registry.put(device)
        Registry.publish(device)
        Access.pushDevice(device)

        Audit.write(actor, 'place', id, {
            kind = kind,
            variant = variant,
            x = spot.x,
            y = spot.y,
            z = spot.z,
            space = admin.space,
        })

        if chosen.access then
            Audit.write(actor, 'access', id, Access.changes(nil, chosen.access))
        end

        if chosen.apps then
            Audit.write(actor, 'apps', id, { on = Devices.appsOn(chosen.apps) })
        end

        if chosen.page then
            Audit.write(actor, 'page', id, { app = chosen.page.app })
        end

        return Util.ok({ device = Devices.detailView(device), warnings = warnings })
    end)
end

local function applyFields(device, fields)
    for key, value in pairs(fields) do
        if value == false and key ~= 'enabled' and key ~= 'surface' then
            device[key] = nil
        else
            device[key] = value
        end
    end
end

local function commit(actor, device, fields, expected)
    if expected ~= device.version then return false end

    if fields.state == 'carried' then
        fields.x, fields.y, fields.z, fields.heading = false, false, false, false
    end

    local by = actor and actor.cid or nil

    if not device.temporary then
        fields.updatedBy = by or false

        local changed = Store.updateDevice(device.id, expected, fields)

        if changed ~= 1 then
            local fresh = Store.loadDevice(device.id)

            if fresh then
                Registry.put(fresh)
            end

            return false
        end

        fields.updatedBy = nil
    end

    applyFields(device, fields)
    device.updatedBy = by
    device.updatedAt = now()
    device.version = device.version + 1

    local world, access = false, false

    for key in pairs(fields) do
        if WORLD_FIELDS[key] then
            world = true
        end

        if ACCESS_FIELDS[key] then
            access = true
        end
    end

    if world then
        Registry.publish(device)
    end

    if access then
        Access.pushDevice(device)
    end

    return true
end

Devices.commit = commit

function Devices.move(actor, device, value, version)
    if device.state ~= 'placed' or not Devices.placeable(device.kind) then
        return Util.fail('not_placed')
    end

    if version ~= nil and Util.integer(version) ~= device.version then
        return Util.fail('device_changed', { version = device.version })
    end

    if Sessions.user(device.id) then
        return Util.fail('device_in_use')
    end

    local expected = device.version
    local spot = Util.position(value)

    if not spot then
        return Util.fail('invalid_position')
    end

    local admin = Devices.adminSpot(actor.source)

    if not inRange(admin, spot) then
        return Util.fail('out_of_range')
    end

    return Guard.exclusive('world', function()
        local other = Devices.spacingConflict(device.kind, spot, admin.space, device.id)

        if other then
            return Util.fail('overlap', { id = other.id })
        end

        local warnings = {}
        local variant, twin = Devices.keepVariant(device.kind, spot, admin.space, device.variant, device.id)

        if twin then
            warnings[#warnings + 1] = 'twin'
        end

        if Settings.zoneAt(spot, admin.space) then
            warnings[#warnings + 1] = 'in_zone'
        end

        local from = { x = device.x, y = device.y, z = device.z, space = Spaces.ofDevice(device) }

        local fields = {
            x = spot.x,
            y = spot.y,
            z = spot.z,
            heading = spot.h,
            variant = variant,
            bucket = admin.propertyId and 0 or admin.bucket,
            propertyId = admin.propertyId or false,
        }

        if not commit(actor, device, fields, expected) then
            return Util.fail('device_changed', { version = Registry.device(device.id).version })
        end

        Audit.write(actor, 'move', device.id, {
            from = from,
            to = { x = spot.x, y = spot.y, z = spot.z, space = admin.space },
        })

        return Util.ok({ device = Devices.detailView(device), warnings = warnings })
    end)
end

local function kindFull(kind)
    local limit = Registry.settings.kinds[kind].max or 0

    if limit > 0 and Devices.countPlaced(kind) >= limit then
        return Util.fail('kind_limit', { max = limit })
    end

    return nil
end

local function change(actor, device, version, patch)
    local expected = Util.integer(version)

    if expected ~= device.version then
        return Util.fail('device_changed', { version = device.version })
    end

    if type(patch) ~= 'table' then
        return Util.fail('invalid_patch')
    end

    for key in pairs(patch) do
        if not PATCH_KEYS[key] then
            return Util.fail('invalid_patch', { field = tostring(key) })
        end
    end

    if device.state == 'removed' then
        return Util.fail('already_removed')
    end

    local fields, audits, warnings = {}, {}, {}
    local target = Util.copy(device)

    if patch.label ~= nil then
        local label = Util.cleanText(patch.label, Config.limits.labelLength)

        if not label then
            return Util.fail('invalid_label')
        end

        if label ~= device.label then
            fields.label = label
            audits[#audits + 1] = { 'rename', { from = device.label, to = label } }
        end
    end

    if patch.owner ~= nil then
        if actor.level ~= 'admin' then
            return Util.fail('owner_admin_only')
        end

        local cid = patch.owner

        if cid == false or cid == '' then
            if device.ownerCid then
                fields.ownerCid, fields.ownerName = false, false
                audits[#audits + 1] = { 'owner', { from = device.ownerCid } }
            end
        else
            if not Util.isCid(cid) then
                return Util.fail('bad_citizen')
            end

            if cid ~= device.ownerCid then
                local found = Access.lookupCitizen(cid)

                if not found then
                    return Util.fail('unknown_citizen')
                end

                cid = found.cid

                if cid ~= device.ownerCid then
                    fields.ownerCid, fields.ownerName = cid, (Util.cleanText(found.name, 64) or cid)
                    audits[#audits + 1] = { 'owner', { from = device.ownerCid, to = cid } }
                end
            end
        end

        target.ownerCid = fields.ownerCid == false and nil or (fields.ownerCid or target.ownerCid)
    end

    if patch.enabled ~= nil then
        if type(patch.enabled) ~= 'boolean' then
            return Util.fail('invalid_patch', { field = 'enabled' })
        end

        if patch.enabled ~= device.enabled then
            fields.enabled = patch.enabled
            audits[#audits + 1] = { 'enable', { on = patch.enabled } }
        end
    end

    if patch.bucket ~= nil or patch.propertyId ~= nil then
        local bucket = patch.bucket == nil and device.bucket or Util.integer(patch.bucket, 0, 2147483647)

        if bucket == nil then
            return Util.fail('invalid_space')
        end

        local property = device.propertyId

        if patch.propertyId == false then
            property = nil
        elseif patch.propertyId ~= nil then
            property = Util.integer(patch.propertyId, 1, 2147483647)

            if not property then
                return Util.fail('invalid_space')
            end
        end

        if property then
            bucket = 0
        end

        if bucket ~= device.bucket or property ~= device.propertyId then
            if Sessions.user(device.id) then
                return Util.fail('device_in_use')
            end

            fields.bucket, fields.propertyId = bucket, property or false
            target.bucket, target.propertyId = bucket, property
            audits[#audits + 1] = { 'space', { from = Spaces.ofDevice(device), to = Spaces.ofDevice(target) } }
        end
    end

    if patch.kind ~= nil and patch.kind ~= device.kind then
        if not Devices.placeable(patch.kind) or not Devices.placeable(device.kind) then
            return Util.fail('invalid_kind')
        end

        if device.origin == 'item' then
            return Util.fail('kind_locked')
        end

        if not Settings.kindEnabled(patch.kind) then
            return Util.fail('kind_off')
        end

        local full = device.state == 'placed' and kindFull(patch.kind)

        if full then
            return full
        end

        if Sessions.user(device.id) then
            return Util.fail('device_in_use')
        end

        fields.kind = patch.kind
        target.kind = patch.kind
    end

    if patch.variant ~= nil or fields.kind or fields.bucket ~= nil then
        local wanted = patch.variant

        if wanted ~= nil and wanted ~= 'auto' and not Devices.isVariant(target.kind, wanted) then
            return Util.fail('invalid_variant')
        end

        if wanted == nil and fields.kind then
            wanted = 'auto'
        end

        if target.state == 'placed' and target.x then
            local variant, twin

            if wanted == nil then
                variant, twin = Devices.keepVariant(
                    target.kind,
                    target,
                    Spaces.ofDevice(target),
                    device.variant,
                    device.id
                )
            else
                variant, twin = Devices.pickVariant(
                    target.kind,
                    target,
                    Spaces.ofDevice(target),
                    wanted ~= 'auto' and wanted or nil,
                    device.id
                )
            end

            if twin then
                warnings[#warnings + 1] = 'twin'
            end

            if variant ~= device.variant then
                fields.variant = variant
            end
        elseif wanted ~= 'auto' and wanted ~= device.variant then
            fields.variant = wanted
        end

        if fields.kind or fields.variant then
            audits[#audits + 1] = { 'model', { kind = target.kind, variant = fields.variant or device.variant } }
        end
    end

    if patch.access ~= nil then
        local access, reason, index = Access.validate(patch.access, target, { current = device.access })

        if not access then
            return Util.fail(reason, { field = 'access', rule = index })
        end

        fields.access = access
        target.access = access
        audits[#audits + 1] = { 'access', Access.changes(device.access, access) }
    elseif fields.propertyId == false and AccessRules.usesType(device.access, 'keys') then
        return Util.fail('keys_not_home', { field = 'access' })
    end

    if patch.manage ~= nil then
        local manage, reason, index = Access.validate(patch.manage, target, {
            modes = { 'owner', 'rules' },
            current = device.manage,
        })

        if not manage then
            return Util.fail(reason, { field = 'manage', rule = index })
        end

        fields.manage = manage
        audits[#audits + 1] = { 'manage', Access.changes(device.manage, manage) }
    elseif fields.propertyId == false and AccessRules.usesType(device.manage, 'keys') then
        return Util.fail('keys_not_home', { field = 'manage' })
    end

    if patch.apps ~= nil then
        if not OsRules.hasOs(target.kind) then
            return Util.fail('apps_not_os')
        end

        local apps, reason, id = Apps.normalizeDeviceApps(patch.apps, device.apps, target)

        if not apps then
            return Util.fail(reason, { field = 'apps', app = id })
        end

        local before = Devices.onlyApp(device)

        if apps.only ~= before then
            if actor and not Guard.allows(actor.level, 'manage') then
                return Util.fail('only_app_admin', { field = 'apps' })
            end

            audits[#audits + 1] = { 'only_app', { app = apps.only, from = before } }
        end

        fields.apps = apps
        audits[#audits + 1] = { 'apps', { on = Devices.appsOn(apps) } }
    end

    if patch.page ~= nil then
        if target.kind ~= 'terminal' then
            return Util.fail('page_terminal_only')
        end

        local page, reason = Apps.normalizePage(patch.page, device.page)

        if page == nil then
            return Util.fail(reason, { field = 'page' })
        end

        fields.page = page
        audits[#audits + 1] = { 'page', { app = page and page.app or nil } }
    end

    if patch.screen ~= nil then
        if not Devices.placeable(target.kind) then
            return Util.fail('invalid_patch', { field = 'screen' })
        end

        local screen, reason, setting = ScreenRules.clean(target.kind, patch.screen)

        if not screen then
            return Util.fail(reason, { field = 'screen', setting = setting })
        end

        if type(patch.screen) == 'table' and patch.screen.wall == nil and type(device.screen) == 'table' and ScreenRules.takesPicture(target.kind) then
            screen.wall = device.screen.wall
        end

        local changed = ScreenRules.changes(device.screen, screen, target.kind)

        if #changed > 0 then
            fields.screen = ScreenRules.compact(screen) or false
            audits[#audits + 1] = { 'screen', { changed = changed } }
        end
    end

    if next(fields) == nil then
        return nil, warnings
    end

    if not commit(actor, device, fields, expected) then
        return Util.fail('device_changed', { version = Registry.device(device.id).version })
    end

    if fields.enabled == false then
        Sessions.close(device.id, 'disabled')
    end

    for _, entry in ipairs(audits) do
        Audit.write(actor, entry[1], device.id, entry[2])
    end

    return nil, warnings
end

function Devices.save(actor, device, version, patch)
    local failure, warnings = change(actor, device, version, patch)

    if failure then
        return failure
    end

    return Util.ok({ device = Devices.detailView(device), warnings = warnings })
end

function Devices.remove(actor, device, mode, typed)
    local Items = require 'server.items'
    local Spawn = require 'server.spawn'

    if tostring(typed) ~= tostring(device.id) then
        return Util.fail('confirm_mismatch')
    end

    if device.state == 'removed' then
        return Util.fail('already_removed')
    end

    if device.temporary then
        Spawn.drop(device, 'removed')

        Audit.write(actor, 'remove', nil, {
            mode = 'delete',
            kind = device.kind,
            from = device.resource,
            temporary = true,
        })

        return Util.ok({ device = Devices.detailView(device) })
    end

    local giveBack = device.origin == 'item' and device.ownerCid ~= nil and device.kind ~= 'tablet' and Config.items[device.kind] ~= nil

    if mode == nil then
        local rules = Registry.settings.kinds[device.kind].item

        mode = giveBack and rules and rules.onRemove or 'delete'
    end

    if mode ~= 'return' and mode ~= 'delete' then
        return Util.fail('invalid_mode')
    end

    if mode == 'return' and not giveBack then
        return Util.fail('not_player_device')
    end

    if mode == 'return' and device.state ~= 'placed' then
        return Util.fail('not_placed')
    end

    local expected, was = device.version, device.state
    local spot = { state = 'placed', x = device.x, y = device.y, z = device.z, heading = device.heading }

    Sessions.close(device.id, 'removed')

    local fields = mode == 'delete' and { state = 'removed', removedAt = now() } or { state = 'carried' }

    if not commit(actor, device, fields, expected) then
        return Util.fail('device_changed', { version = Registry.device(device.id).version })
    end

    local returned = nil

    if mode == 'return' then
        returned = Items.giveBack(device)
        Audit.write(actor, 'return', device.id, { owner = device.ownerCid, delivered = returned or 'failed' })

        if not returned then
            return Util.fail('return_failed', { placed = commit(actor, device, spot, device.version) })
        end
    end

    Audit.write(actor, 'remove', device.id, { mode = mode, kind = device.kind, from = was })

    return Util.ok({ device = Devices.detailView(device), returned = returned })
end

function Devices.restore(actor, device)
    if device.state ~= 'removed' then
        return Util.fail('not_removed')
    end

    if not Devices.restorable(device) then
        return Util.fail('restore_expired')
    end

    local state = device.x and device.kind ~= 'tablet' and 'placed' or 'carried'
    local expected = device.version

    return Guard.exclusive('world', function()
        if state == 'placed' or device.kind == 'tablet' then
            if not Settings.kindEnabled(device.kind) then
                return Util.fail('kind_off')
            end

            local full = kindFull(device.kind)

            if full then
                return full
            end
        end

        local fields, warnings = { state = state, removedAt = false }, {}

        if state == 'placed' then
            local space = Spaces.ofDevice(device)
            local other = Devices.spacingConflict(device.kind, device, space, device.id)

            if other then
                return Util.fail('overlap', { id = other.id })
            end

            local variant, twin = Devices.keepVariant(device.kind, device, space, device.variant, device.id)

            if twin then
                warnings[#warnings + 1] = 'twin'
            end

            if variant ~= device.variant then
                fields.variant = variant
            end
        end

        if not commit(actor, device, fields, expected) then
            return Util.fail('device_changed', { version = Registry.device(device.id).version })
        end

        Audit.write(actor, 'restore', device.id, { state = state, variant = fields.variant })

        return Util.ok({ device = Devices.detailView(device), warnings = warnings })
    end)
end

local BULK_MAX = 500

local function appOn(device, id)
    if device.kind == 'terminal' then
        return type(device.page) == 'table' and device.page.app == id, true
    end

    local entries = type(device.apps) == 'table' and type(device.apps.entries) == 'table' and device.apps.entries or {}
    local entry = entries[id]

    if entry then
        return entry.on == true, true
    end

    return Apps.options(id).kinds[device.kind] == true, false
end

local function idList(value)
    if value == nil then
        return {}
    end

    if type(value) ~= 'table' or #value > BULK_MAX then
        return nil
    end

    local list, seen = {}, {}

    for key, raw in pairs(value) do
        if math.type(key) ~= 'integer' then return nil end

        local id = Guard.idArg(raw)

        if not id then return nil end

        if not seen[id] then
            seen[id] = true
            list[#list + 1] = id
        end
    end

    table.sort(list)

    return list
end

local function bulkEach(actor, wanted, dryRun, build)
    local result = { changes = {}, skipped = {}, unchanged = 0 }

    for _, item in ipairs(wanted) do
        local device = Registry.device(item.id)
        local entry = { id = item.id }
        local patch, reason = nil, 'unknown_device'

        if device then
            entry.kind, entry.label = device.kind, device.label
            reason = nil

            if device.state == 'removed' then
                reason = 'already_removed'
            elseif device.temporary then
                reason = 'temporary_device'
            else
                patch, reason = build(device, item)
            end
        end

        if reason then
            entry.reason = reason
            result.skipped[#result.skipped + 1] = entry
        elseif patch == false then
            result.unchanged = result.unchanged + 1
        elseif dryRun then
            entry.to = item.on
            result.changes[#result.changes + 1] = entry
        else
            local failure = change(actor, device, device.version, patch)

            entry.to = item.on

            if failure then
                entry.reason = failure.reason
                result.skipped[#result.skipped + 1] = entry
            else
                result.changes[#result.changes + 1] = entry
            end
        end
    end

    return result
end

local function bulkRun(actor, wanted, dryRun, build)
    return Registry.batch(function()
        return bulkEach(actor, wanted, dryRun, build)
    end)
end

local function fitsApp(registered, id, kind)
    if registered.def.terminal then
        return kind == 'terminal'
    end

    return OsRules.hasOs(kind) and Apps.supports(id, kind)
end

function Devices.appDevices(id)
    local registered = Apps.registered[id]

    if not registered then
        return nil, Apps.rows[id] and 'app_stopped' or 'unknown_app'
    end

    local memo = Access.memo()
    local list = {}

    for _, device in ipairs(Registry.list()) do
        if device.state ~= 'removed' and not device.temporary and fitsApp(registered, id, device.kind) then
            local on, explicit = appOn(device, id)

            list[#list + 1] = {
                id = device.id,
                kind = device.kind,
                label = device.label,
                state = device.state,
                enabled = device.enabled,
                on = on,
                explicit = explicit,
                player = Apps.isPlayerDevice(device),
                owner = Devices.ownerView(device),
                from = Devices.source(device),
                space = Spaces.ofDevice(device),
                position = position(device),
                access = Access.summary(device, memo),
            }
        end
    end

    return { devices = list }
end

function Devices.appCounts()
    local counts = {}

    for id, registered in pairs(Apps.registered) do
        local count = 0

        for _, device in pairs(Registry.devices) do
            if device.state ~= 'removed' and not device.temporary and fitsApp(registered, id, device.kind) and appOn(device, id) then
                count = count + 1
            end
        end

        counts[id] = count
    end

    return counts
end

function Devices.applyApp(actor, id, wanted, dryRun)
    local registered = Apps.registered[id]

    if not registered then
        return Util.fail(Apps.rows[id] and 'app_stopped' or 'unknown_app')
    end

    if type(wanted) ~= 'table' then
        return Util.fail('invalid_patch')
    end

    local on, off = idList(wanted.on), idList(wanted.off)

    if not on or not off or #on + #off > BULK_MAX then
        return Util.fail('invalid_patch')
    end

    local items, seen = {}, {}

    for _, deviceId in ipairs(on) do
        seen[deviceId] = true
        items[#items + 1] = { id = deviceId, on = true }
    end

    for _, deviceId in ipairs(off) do
        if seen[deviceId] then
            return Util.fail('invalid_patch')
        end

        items[#items + 1] = { id = deviceId, on = false }
    end

    local terminal = registered.def.terminal == true

    return Util.ok(bulkRun(actor, items, dryRun, function(device, item)
        if not fitsApp(registered, id, device.kind) then
            return nil, 'app_wrong_kind'
        end

        if appOn(device, id) == item.on then
            return false
        end

        if not item.on and Devices.onlyApp(device) == id then
            return nil, 'only_app_on'
        end

        if terminal then
            local page = item.on and { app = id, settings = {} } or false

            if dryRun then
                local clean, reason = Apps.normalizePage(page, device.page)

                if clean == nil then
                    return nil, reason
                end
            end

            return { page = page }
        end

        local apps = Util.copy(type(device.apps) == 'table' and device.apps or {})

        apps.order = apps.order or {}
        apps.entries = apps.entries or {}
        apps.entries[id] = apps.entries[id] or { settings = {} }
        apps.entries[id].on = item.on

        if not Util.contains(apps.order, id) then
            apps.order[#apps.order + 1] = id
        end

        if dryRun then
            local clean, reason = Apps.normalizeDeviceApps(apps, device.apps, device)

            if not clean then
                return nil, reason
            end
        end

        return { apps = apps }
    end))
end

function Devices.applyPicture(actor, picture, ids, dryRun)
    if type(picture) ~= 'table' or type(picture.idle) ~= 'string' or #picture.idle > 32 then
        return Util.fail('invalid_screen')
    end

    local list = idList(ids)

    if not list then
        return Util.fail('invalid_patch')
    end

    local url = nil

    if picture.idle == 'url' then
        url = ScreenRules.url(picture.url)

        if not url then
            return Util.fail('screen_url')
        end
    end

    local items = {}

    for _, deviceId in ipairs(list) do
        items[#items + 1] = { id = deviceId, on = true }
    end

    return Util.ok(bulkRun(actor, items, dryRun, function(device)
        if not Devices.placeable(device.kind) then
            return nil, 'invalid_kind'
        end

        if not url and not ScreenRules.preset(device.kind, picture.idle) then
            return nil, 'screen_idle'
        end

        local screen = ScreenRules.resolve(device.kind, device.screen)

        if screen.idle == picture.idle and (not url or screen.url == url) then
            return false
        end

        screen.idle = picture.idle

        if url then
            screen.url = url
        end

        if dryRun then
            local clean, reason = ScreenRules.clean(device.kind, screen)

            if not clean then
                return nil, reason
            end
        end

        return { screen = screen }
    end))
end

return Devices
