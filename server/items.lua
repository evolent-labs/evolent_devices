local Config = require 'config'
local Integrations = require 'integrations'
local Bridge = require 'bridge'
local Util = require 'shared.util'
local DeviceRules = require 'shared.rules'
local AccessRules = require 'shared.access'
local AppRules = require 'shared.apps'
local TabletColours = require 'shared.tablet_colours'
local Store = require 'server.store'
local Guard = require 'server.guard'
local Audit = require 'server.audit'
local Registry = require 'server.registry'
local Settings = require 'server.settings'
local Spaces = require 'server.spaces'
local Access = require 'server.access'
local Sessions = require 'server.sessions'
local Devices = require 'server.devices'

local Items = { issued = {}, dead = {}, tickets = {}, hooked = false, checkedAt = 0 }

Items.REACH = 4.0
Items.PICKUP_REACH = 2.5

local REACH_SLACK, PICKUP_SLACK, HEIGHT = 1.5, 1.0, 2.0
local TICKET_MS, BEGIN_MS, TABLET_CHECK_MS = 120000, 3000, 2000

function Items.itemName(kind)
    local entry = Config.items[kind]

    return entry and entry.item or nil
end

function Items.kindOfItem(name)
    for kind, entry in pairs(Config.items) do
        if entry.item == name then
            return kind
        end
    end

    return nil
end

function Items.rules(kind)
    local entry = Registry.settings.kinds[kind]

    return entry and entry.item or nil
end

function Items.isSerial(value, kind)
    local entry = Config.items[kind]

    if type(value) ~= 'string' or not entry then return false end

    local prefix = entry.serialPrefix .. '-'

    return value:sub(1, #prefix) == prefix and value:sub(#prefix + 1):match('^%x%x%x%x%x%x$') ~= nil
end

function Items.load()
    Items.issued, Items.dead = {}, {}

    local ok, rows = pcall(Store.loadSerials)

    if not ok or type(rows) ~= 'table' then
        Util.log('could not read the issued serials: ' .. tostring(rows))

        return 0
    end

    for _, row in ipairs(rows) do
        Items.issued[row.serial] = true

        if row.dead then
            Items.dead[row.serial] = true
        end
    end

    return #rows
end

local function note(serial, kind)
    local ok, failure = pcall(Store.noteSerial, serial, kind)

    if not ok then
        Util.log(('could not note the serial %s: %s'):format(serial, tostring(failure)))
    end
end

function Items.newSerial(kind, memoryOnly)
    local entry = Config.items[kind]

    if not entry then return nil end

    for _ = 1, 20 do
        local serial = ('%s-%s'):format(entry.serialPrefix, Util.hex(6):upper())

        if not Items.issued[serial] and not Registry.bySerial(serial) and (memoryOnly or not Store.serialTaken(serial)) then
            Items.issued[serial] = true

            if memoryOnly then
                CreateThread(function() note(serial, kind) end)
            else
                note(serial, kind)
            end

            return serial
        end
    end

    return nil
end

function Items.isDead(serial)
    local row = Registry.bySerial(serial)

    return Items.dead[serial] == true or (row ~= nil and row.state == 'removed')
end

function Items.colour(value)
    if type(value) == 'string' then
        local wanted = value:lower()

        for index, entry in ipairs(TabletColours) do
            if entry.id == wanted then
                return index - 1
            end
        end
    end

    local index = math.tointeger(tonumber(value))

    if index and index >= 0 and index < #TabletColours then
        return index
    end

    return nil
end

local function tabletLook(metadata, colour)
    local entry = TabletColours[colour + 1]

    metadata.colour = colour
    metadata.type = locale('tablet_colour_' .. entry.id)
    metadata.imageurl = ('nui://%s/web/build/items/evolent_tablet_%s.png'):format(GetCurrentResourceName(), entry.id)
end

function Items.metadata(kind, serial, label)
    local metadata = { serial = serial }

    if type(label) == 'string' and label ~= '' then
        metadata.label = locale('item_label', locale('kind_' .. kind), label)
    end

    return metadata
end

function Items.stamp(name, metadata)
    local kind = Items.kindOfItem(name)

    if not kind then return nil end

    local data = type(metadata) == 'table' and Util.copy(metadata) or {}

    if not Items.isSerial(data.serial, kind) then
        local serial = Items.newSerial(kind, true)

        if not serial then return nil end

        data.serial = serial
    end

    if kind == 'tablet' then
        tabletLook(data, Items.colour(data.colour) or Items.colour(data.type) or 0)
    end

    return data
end

function Items.hook()
    local names = {}

    for _, kind in ipairs(Config.kindOrder) do
        local name = Items.itemName(kind)

        if name then
            names[#names + 1] = name
        end
    end

    Integrations.onItemUsed(names, function(source, name, slot)
        local kind = Items.kindOfItem(name)

        if kind and Util.integer(tonumber(slot), 1, 10000) then
            TriggerClientEvent('evdev:client:useItem', source, kind, slot)
        end
    end)

    Items.hooked = Integrations.onItemCreated(names, Items.stamp)

    return Items.hooked
end

function Items.status()
    local list = {}

    for _, kind in ipairs(Config.kindOrder) do
        local entry = Config.items[kind]

        if entry then
            list[#list + 1] = {
                kind = kind,
                item = entry.item,
                serialPrefix = entry.serialPrefix,
                defined = Integrations.itemDefined(entry.item),
            }
        end
    end

    return {
        inventory = Integrations.inventoryReady(),
        name = Integrations.inventoryName(),
        metadata = Integrations.keepsMetadata(),
        items = list,
    }
end

function Items.give(actor, kind, target)
    local name = Items.itemName(kind)

    if not name then
        return Util.fail('not_item_kind')
    end

    if not Integrations.inventoryReady() then
        return Util.fail('inventory_missing')
    end

    if not Integrations.itemDefined(name) then
        return Util.fail('item_missing', { item = name })
    end

    local cid = Bridge.getCharacterId(target)

    if not cid then
        return Util.fail('target_not_ready')
    end

    if not Integrations.canCarry(target, name) then
        return Util.fail('cannot_carry')
    end

    local serial = Items.newSerial(kind)

    if not serial then
        return Util.fail('internal_error')
    end

    local metadata = Items.metadata(kind, serial)

    if kind == 'tablet' then
        tabletLook(metadata, 0)
    end

    if not Integrations.addItem(target, name, metadata) then
        return Util.fail('give_failed')
    end

    Bridge.notify(target, locale('item_given', locale('kind_' .. kind)), 'success')

    Audit.write(actor, 'give', nil, {
        kind = kind,
        serial = serial,
        to = cid,
        toName = Bridge.getCharacterName(target),
    })

    return Util.ok({ serial = serial, item = name })
end

function Items.giveBack(device)
    local name = Items.itemName(device.kind)
    local metadata = Items.metadata(device.kind, device.serial, device.label)
    local source = Bridge.getSourceByCharacterId(device.ownerCid)

    if source and Integrations.addItem(source, name, metadata) then
        Bridge.notify(source, locale('item_returned', locale('kind_' .. device.kind)), 'inform')

        return 'online'
    end

    local ok, result = pcall(Store.insertReturn, device.ownerCid, name, metadata, 'admin_remove')

    if not ok or not result then
        Util.log(('could not queue the return of device %d to %s: %s'):format(device.id, device.ownerCid, tostring(result)))

        return nil
    end

    return 'queued'
end

function Items.deliverReturns(source)
    local cid = Bridge.getCharacterId(source)

    if not cid then
        return 0
    end

    local delivered = 0

    for _, row in ipairs(Store.loadReturns(cid)) do
        if Store.deleteReturn(row.id) == 1 then
            if Integrations.addItem(source, row.item, row.metadata) then
                delivered = delivered + 1
            else
                pcall(Store.insertReturn, cid, row.item, row.metadata, row.reason)
            end
        end
    end

    if delivered > 0 then
        Bridge.notify(source, locale('items_returned', delivered), 'inform')
    end

    return delivered
end

function Items.pickable(device)
    return device.state == 'placed' and device.origin == 'item' and not device.temporary and device.serial ~= nil
        and device.kind ~= 'tablet' and Config.items[device.kind] ~= nil
end

function Items.pickupBy(device)
    local rules = Items.rules(device.kind)

    return rules and rules.pickup or 'owner'
end

local function carriedBy(source, kind, name)
    local cid = Bridge.getCharacterId(source)
    local found = nil

    if not cid then return nil end

    for _, device in pairs(Registry.devices) do
        local mine = device.kind == kind and device.state == 'carried' and device.origin == 'item' and device.ownerCid == cid

        if mine and device.serial and not Items.isDead(device.serial) and (not found or device.id < found.id)
            and not Integrations.findItem(source, name, device.serial) then
            found = device
        end
    end

    return found
end

local function serialOf(source, slot, kind, item)
    local metadata = type(item.metadata) == 'table' and Util.copy(item.metadata) or {}

    if Items.isSerial(metadata.serial, kind) then
        return metadata.serial, metadata
    end

    local kept = not Integrations.keepsMetadata() and carriedBy(source, kind, item.name) or nil
    local stamped = nil

    if kept then
        stamped = Items.metadata(kind, kept.serial, kept.label)

        if kind == 'tablet' then
            tabletLook(stamped, 0)
        end
    else
        stamped = Items.stamp(item.name, metadata)
    end

    if not stamped or not Integrations.setMetadata(source, slot, stamped) then return nil end

    return stamped.serial, stamped
end

local function onFoot(source, subject)
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

    return nil
end

local function ownPlaced(kind, cid)
    local total = 0

    for _, device in pairs(Registry.devices) do
        if device.kind == kind and device.state == 'placed' and device.origin == 'item' and device.ownerCid == cid then
            total = total + 1
        end
    end

    return total
end

local function placeRules(source, subject, kind, rules)
    if not Settings.kindEnabled(kind) then
        return 'kind_off'
    end

    if not rules or not rules.enabled then
        return 'item_place_off'
    end

    local context = Access.context({ kind = kind }, source, false, false)

    if not AccessRules.passes(rules.place, subject, context) then
        return 'item_place_rules'
    end

    local limit = rules.perPlayer or 0

    if limit > 0 and ownPlaced(kind, subject.cid) >= limit then
        return 'item_limit', { max = limit }
    end

    local max = Registry.settings.kinds[kind].max or 0

    if max > 0 and Devices.countPlaced(kind) >= max then
        return 'kind_limit', { max = max }
    end

    local _, propertyId = Spaces.of(source)

    if rules.where == 'homes' and not propertyId then
        return 'item_homes_only'
    end

    if propertyId and rules.homeKeysOnly then
        local keys = Integrations.propertyKeys(propertyId, true)

        if not keys or (keys.owner ~= subject.cid and not keys.keyholders[subject.cid]) then
            return 'item_home_keys'
        end
    end

    return nil
end

local function aimRules(kind, rules)
    local spec = Config.kinds[kind]

    return {
        surface = spec.placeOn == 'surface',
        tableMin = rules and rules.tableMin or 0.4,
        tableMax = rules and rules.tableMax or 1.4,
        range = Items.REACH,
    }
end

local function issue(source, entry)
    entry.ticket, entry.at = Util.hex(32), GetGameTimer()
    Items.tickets[source] = entry

    return entry.ticket
end

local function take(source, ticket, mode)
    local entry = Items.tickets[source]

    if not entry or type(ticket) ~= 'string' or entry.ticket ~= ticket or entry.mode ~= mode then return nil end

    Items.tickets[source] = nil

    if GetGameTimer() - entry.at > TICKET_MS then return nil end

    return entry
end

function Items.begin(source, slot)
    slot = Util.integer(tonumber(slot), 1, 10000)

    if not slot then
        return Util.fail('item_gone')
    end

    if not Integrations.inventoryReady() then
        return Util.fail('inventory_missing')
    end

    local subject = Bridge.subject(source)
    local refusal = onFoot(source, subject)

    if refusal then
        return Util.fail(refusal)
    end

    local item = Integrations.getSlot(source, slot)
    local kind = item and Items.kindOfItem(item.name)

    if not kind or kind == 'tablet' then
        return Util.fail('item_gone')
    end

    if not Guard.rate(source, 'item_begin', 1, BEGIN_MS) then
        return Util.fail('slow_down')
    end

    local serial = serialOf(source, slot, kind, item)

    if not serial then
        return Util.fail('internal_error')
    end

    local row = Registry.bySerial(serial)

    if row and row.state == 'placed' then
        return Util.fail('serial_placed')
    end

    if Items.isDead(serial) then
        return Util.fail('serial_dead')
    end

    local rules = Items.rules(kind)
    local reason, data = placeRules(source, subject, kind, rules)

    if reason then
        return Util.fail(reason, data)
    end

    local ticket = issue(source, { mode = 'place', slot = slot, serial = serial, kind = kind })
    local spec = Config.kinds[kind]

    return Util.ok({
        ticket = ticket,
        kind = kind,
        model = row and row.variant or DeviceRules.baseModel(spec),
        rules = aimRules(kind, rules),
    })
end

local function spotFor(source, value)
    local spot = Util.position(value)

    if not spot then
        return nil, 'invalid_position'
    end

    local ped = GetPlayerPed(source)

    if not ped or ped == 0 then
        return nil, 'not_ready'
    end

    local at = GetEntityCoords(ped)

    if Util.distance(at, spot) > Items.REACH + REACH_SLACK or math.abs(at.z - spot.z) > HEIGHT then
        return nil, 'out_of_range'
    end

    local space, propertyId = Spaces.of(source)

    if Settings.zoneAt(spot, space) then
        return nil, 'item_zone'
    end

    return spot, nil, space, propertyId
end

local function startAccess(kind, propertyId)
    local rules = Items.rules(kind)
    local access = Util.copy(rules and rules.startAccess or { mode = 'owner', rules = {} })

    access.rules = access.rules or {}

    if not propertyId then
        access = Access.withoutKeys(access)
    end

    return access
end

local function startApps(kind)
    local rules = Items.rules(kind)
    local apps = { order = {}, entries = {} }

    for _, id in ipairs(rules and rules.startApps or {}) do
        if AppRules.isId(id) and not apps.entries[id] then
            apps.order[#apps.order + 1] = id
            apps.entries[id] = { on = true, settings = {} }
        end
    end

    return apps
end

local function refund(source, name, metadata, cid)
    if Integrations.addItem(source, name, metadata) then return true end

    local ok = pcall(Store.insertReturn, cid, name, metadata, 'place_failed')

    Util.log(('placing failed and the %s could not go back to %s: %s'):format(
        name,
        tostring(cid),
        ok and 'it waits for the next login' or 'it is lost, the console has the serial ' .. tostring(metadata.serial)
    ))

    return false
end

function Items.place(source, ticket, value)
    local entry = take(source, ticket, 'place')

    if not entry then
        return Util.fail('item_ticket')
    end

    return Guard.exclusive('item:' .. tostring(source), function()
        local subject = Bridge.subject(source)
        local refusal = onFoot(source, subject)

        if refusal then
            return Util.fail(refusal)
        end

        local actor = Guard.actor(source)
        local kind, serial = entry.kind, entry.serial
        local name = Items.itemName(kind)
        local item = Integrations.getSlot(source, entry.slot)
        local metadata = item and type(item.metadata) == 'table' and item.metadata or {}

        if not item or item.name ~= name or metadata.serial ~= serial then
            return Util.fail('item_gone')
        end

        local known = Registry.bySerial(serial)

        if known and known.state ~= 'carried' then
            return Util.fail(known.state == 'placed' and 'serial_placed' or 'serial_dead')
        end

        if Items.dead[serial] then
            return Util.fail('serial_dead')
        end

        local spot, reason, space, propertyId = spotFor(source, value)

        if not spot then
            return Util.fail(reason)
        end

        local rules = Items.rules(kind)
        local data

        reason, data = placeRules(source, subject, kind, rules)

        if reason then
            return Util.fail(reason, data)
        end

        return Guard.exclusive('world', function()
            local row = Registry.bySerial(serial)

            if row and row.state ~= 'carried' then
                return Util.fail(row.state == 'placed' and 'serial_placed' or 'serial_dead')
            end

            if Devices.spacingConflict(kind, spot, space) then
                return Util.fail('overlap')
            end

            local variant, twin = Devices.keepVariant(kind, spot, space, row and row.variant or nil)

            if twin then
                return Util.fail('item_too_close', { kind = kind })
            end

            if not Integrations.removeItem(source, name, entry.slot, serial) then
                return Util.fail('item_gone')
            end

            local back = Util.copy(metadata)
            local bucket = propertyId and 0 or (GetPlayerRoutingBucket(source) or 0)

            local fields = {
                state = 'placed',
                x = spot.x,
                y = spot.y,
                z = spot.z,
                heading = spot.h,
                variant = variant,
                surface = Config.kinds[kind].placeOn == 'surface',
                bucket = bucket,
                propertyId = propertyId or false,
            }

            local device

            if row then
                if row.ownerCid ~= subject.cid then
                    fields.ownerCid, fields.ownerName = subject.cid, Util.cleanText(subject.name or '', 64) or subject.cid
                    fields.access, fields.manage = startAccess(kind, propertyId), { mode = 'owner', rules = {} }
                elseif not propertyId then
                    if AccessRules.usesType(row.access, 'keys') then
                        fields.access = Access.withoutKeys(row.access)
                    end

                    if AccessRules.usesType(row.manage, 'keys') then
                        fields.manage = Access.withoutKeys(row.manage)
                    end
                end

                local ok, saved = pcall(Devices.commit, actor, row, fields, row.version)

                if not ok or not saved then
                    refund(source, name, back, subject.cid)

                    return Util.fail(ok and 'device_changed' or 'internal_error')
                end

                device = row

                if fields.ownerCid then
                    Audit.write(actor, 'owner', device.id, { to = subject.cid, by = 'place' })
                end
            else
                device = {
                    kind = kind,
                    variant = variant,
                    label = '',
                    state = 'placed',
                    x = spot.x,
                    y = spot.y,
                    z = spot.z,
                    heading = spot.h,
                    surface = fields.surface,
                    bucket = bucket,
                    propertyId = propertyId,
                    origin = 'item',
                    serial = serial,
                    ownerCid = subject.cid,
                    ownerName = Util.cleanText(subject.name or '', 64) or subject.cid,
                    enabled = true,
                    access = startAccess(kind, propertyId),
                    manage = { mode = 'owner', rules = {} },
                    apps = startApps(kind),
                    createdBy = subject.cid,
                }

                local ok, id = pcall(Store.insertDevice, device)

                if not ok or not id then
                    Util.log(('could not store the %s %s: %s'):format(kind, serial, tostring(id)))
                    refund(source, name, back, subject.cid)

                    return Util.fail('internal_error')
                end

                device.id, device.version = id, 1
                device.createdAt, device.updatedAt = os.time(), os.time()
                Registry.put(device)
                Registry.publish(device)
                Access.pushDevice(device)
            end

            Audit.write(actor, 'place', device.id, {
                kind = kind,
                serial = serial,
                item = true,
                x = spot.x,
                y = spot.y,
                z = spot.z,
                space = space,
            })

            return Util.ok({ id = device.id, kind = kind, label = device.label })
        end)
    end)
end

local function placedDevice(id)
    local device = Registry.device(Guard.idArg(id))

    if not device or device.state ~= 'placed' then
        return nil, Util.fail('no_device')
    end

    if device.origin ~= 'item' or device.temporary or not Devices.placeable(device.kind) then
        return nil, Util.fail('not_player_device')
    end

    return device
end

local function mayManage(source, device)
    return Access.decideManage(source, device).allowed == true
end

local function near(source, device, reach)
    local ped = GetPlayerPed(source)

    if not ped or ped == 0 then
        return 'not_ready'
    end

    if Spaces.of(source) ~= Spaces.ofDevice(device) then
        return 'device_elsewhere'
    end

    if Util.distance(GetEntityCoords(ped), device) > reach then
        return 'device_too_far'
    end

    return nil
end

function Items.mayPickup(source, device)
    if not Items.pickable(device) then return false end

    local cid = Bridge.getCharacterId(source)

    if cid and cid == device.ownerCid then return true end
    if Guard.level(source) then return true end

    return Items.pickupBy(device) == 'manage' and mayManage(source, device)
end

function Items.holder(name, serial)
    for _, other in ipairs(Bridge.onlinePlayers()) do
        if Integrations.findItem(other, name, serial) then
            return other
        end
    end

    return nil
end

function Items.pickup(source, id)
    local device, failure = placedDevice(id)

    if not device then
        return failure
    end

    if not Items.pickable(device) then
        return Util.fail('not_player_device')
    end

    local subject = Bridge.subject(source)
    local refusal = onFoot(source, subject)

    if refusal then
        return Util.fail(refusal)
    end

    if not Items.mayPickup(source, device) then
        return Util.fail('pickup_not_allowed')
    end

    if Sessions.user(device.id) then
        return Util.fail('device_in_use')
    end

    refusal = near(source, device, Items.PICKUP_REACH + PICKUP_SLACK)

    if refusal then
        return Util.fail(refusal)
    end

    local name = Items.itemName(device.kind)

    return Guard.exclusive('device:' .. tostring(device.id), function()
        local holder = Items.holder(name, device.serial)

        if not holder and not Integrations.canCarry(source, name) then
            return Util.fail('cannot_carry_self')
        end

        local actor = Guard.actor(source)
        local spot = { state = 'placed', x = device.x, y = device.y, z = device.z, heading = device.heading }

        if not Devices.commit(actor, device, { state = 'carried' }, device.version) then
            return Util.fail('device_changed')
        end

        if holder then
            local held = holder == source and 'self' or 'other'

            Util.log(('device %d was picked up while player %s already holds the item %s: no second item'):format(
                device.id,
                tostring(holder),
                device.serial
            ))

            Audit.write(actor, 'pickup', device.id, {
                by = actor.name,
                serial = device.serial,
                owner = device.ownerCid,
                held = held,
            })

            return Util.ok({ id = device.id, serial = device.serial, held = held })
        end

        if not Integrations.addItem(source, name, Items.metadata(device.kind, device.serial, device.label)) then
            if not Devices.commit(actor, device, spot, device.version) then
                Util.log(('device %d was picked up but neither the item nor the spot came back; it waits as carried for serial %s'):format(device.id, device.serial))
            end

            return Util.fail('give_failed')
        end

        Audit.write(actor, 'pickup', device.id, { by = actor.name, serial = device.serial, owner = device.ownerCid })

        return Util.ok({ id = device.id, serial = device.serial })
    end)
end

function Items.reissue(actor, device)
    if device.state ~= 'carried' or device.origin ~= 'item' or device.kind == 'tablet' or not device.serial then
        return Util.fail('not_carried_item')
    end

    if not device.ownerCid or not Config.items[device.kind] then
        return Util.fail('not_carried_item')
    end

    if not Integrations.inventoryReady() then
        return Util.fail('inventory_missing')
    end

    local holder = Items.holder(Items.itemName(device.kind), device.serial)

    if holder then
        return Util.fail('item_exists', {
            name = Bridge.getCharacterName(holder) or ('#' .. tostring(holder)),
            source = holder,
        })
    end

    local delivered = Items.giveBack(device)

    Audit.write(actor, 'return', device.id, {
        owner = device.ownerCid,
        delivered = delivered or 'failed',
        again = true,
    })

    if not delivered then
        return Util.fail('reissue_failed')
    end

    return Util.ok({ returned = delivered })
end

function Items.tablet(source, slot, subject)
    slot = Util.integer(tonumber(slot), 1, 10000)

    if not slot then
        return nil, 'item_gone'
    end

    if not Integrations.inventoryReady() then
        return nil, 'inventory_missing'
    end

    local name = Items.itemName('tablet')
    local item = Integrations.getSlot(source, slot)

    if not item or item.name ~= name then
        return nil, 'item_gone'
    end

    local rules = Items.rules('tablet')

    if not rules or rules.enabled == false then
        return nil, 'item_tablet_off'
    end

    local serial, metadata = serialOf(source, slot, 'tablet', item)

    if not serial then
        return nil, 'internal_error'
    end

    if Util.contains(rules.blocked or {}, serial) then
        return nil, 'tablet_blocked'
    end

    local row = Registry.bySerial(serial)

    if Items.isDead(serial) or (row and row.enabled == false) then
        return nil, 'tablet_blocked'
    end

    if not AccessRules.passes(rules.use, subject, Access.context({ kind = 'tablet' }, source, false, false)) then
        return nil, 'tablet_rules'
    end

    if not row then
        local device = {
            kind = 'tablet',
            variant = Config.kinds.tablet.variants[1],
            label = '',
            state = 'carried',
            surface = false,
            bucket = 0,
            origin = 'item',
            serial = serial,
            ownerCid = subject.cid,
            ownerName = Util.cleanText(subject.name or '', 64) or subject.cid,
            enabled = true,
            access = { mode = 'everyone', rules = {} },
            manage = { mode = 'owner', rules = {} },
            apps = { order = {}, entries = {} },
            createdBy = subject.cid,
        }

        local ok, id = pcall(Store.insertDevice, device)

        if ok and id then
            device.id, device.version = id, 1
            device.createdAt, device.updatedAt = os.time(), os.time()
            Registry.put(device)
        else
            Util.log(('could not note the tablet %s: %s'):format(serial, tostring(id)))
        end
    end

    return { slot = slot, serial = serial, name = name, colour = Items.colour(metadata.colour) or 0 }
end

function Items.checkTablets(now)
    local Tablets = require 'server.tablet'

    if now - Items.checkedAt < TABLET_CHECK_MS then return end

    Items.checkedAt = now

    for source, session in pairs(Tablets.open) do
        local item = session.item

        if item and not Integrations.findItem(source, item.name, item.serial) then
            Tablets.putAway(source)
            TriggerClientEvent('evdev:client:tabletAway', source, 'lost')
        end
    end
end

Guard.register('evdev:item:begin', function(source, slot)
    return Items.begin(source, slot)
end, { rate = 2 })

Guard.register('evdev:item:place', function(source, ticket, position)
    return Items.place(source, ticket, Guard.tableArg(position))
end, { rate = 2 })

Guard.register('evdev:item:pickup', function(source, id)
    return Items.pickup(source, id)
end, { rate = 2 })

AddEventHandler('playerDropped', function()
    Items.tickets[source] = nil
end)

return Items
