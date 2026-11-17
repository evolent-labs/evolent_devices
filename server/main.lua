local Config = require 'config'
local Integrations = require 'integrations'
local Bridge = require 'bridge'
local Util = require 'shared.util'
local ScreenRules = require 'shared.screen'
local DeviceRules = require 'shared.rules'
local DeviceSound = require 'shared.sound'
local ConfigRules = require 'shared.config_rules'
local Store = require 'server.store'
local Guard = require 'server.guard'
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
local AppStore = require 'server.appstore'
local Devices = require 'server.devices'
local Items = require 'server.items'
local Spawn = require 'server.spawn'
local Tablets = require 'server.tablet'
local Notices = require 'server.notices'
local Brand = require 'server.brand'
local Admin = require 'server.admin'

Guard.register('evdev:world', function(source)
    local space = Spaces.of(source)
    local snapshot = Registry.snapshot(space)

    snapshot.space = space
    snapshot.watchRange = Registry.settings.general.watchRange
    snapshot.sound = DeviceSound.settings(Registry.settings.general.sound)
    snapshot.display = ScreenRules.display(Registry.settings.general.display)

    return Util.ok(snapshot)
end, { rate = 2 })

Guard.register('evdev:access', function(source)
    return Util.ok({ map = Access.mapFor(source), space = Spaces.of(source) })
end, { rate = 2 })

Bridge.onCharacterLoaded(function(source)
    People.forget(source)

    if not Registry.ready then return end

    Spaces.refresh(source)
    Access.push(source)

    local ok, failure = pcall(Items.deliverReturns, source)

    if not ok then
        Util.log('returns failed: ' .. tostring(failure))
    end
end)

Bridge.onCharacterUnloaded(function(source)
    People.gone(source)
    Sessions.playerLeft(source)
    Guard.drop(source)
    Spaces.forget(source)
    TriggerClientEvent('evdev:client:access', source, {}, true)
end)

Bridge.onGroupsChanged(function(source)
    People.forget(source)

    if not Registry.ready then return end

    Access.push(source)

    if Sessions.recheck then
        Sessions.recheck(source)
    end
end)

Bridge.onPropertyChanged(function(source, propertyId)
    People.forget(source)

    if not Registry.ready then return end

    if propertyId then
        Integrations.propertyKeys(propertyId, true)
    end

    Spaces.refresh(source)
    Access.push(source)
end)

AddEventHandler('playerDropped', function()
    local source = source

    Sessions.playerLeft(source)
    Guard.forget(source)
    Spaces.forget(source)
    People.gone(source)
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        Sessions.reset()
        GlobalState['evdev:busy'] = nil

        return
    end

    Apps.dropResource(resource)
    Access.dropResource(resource)

    if Registry.ready then
        Spawn.dropResource(resource)
    end
end)

local function start()
    Bridge.validate('server')
    Bridge.assertReady()
    MySQL.ready.await()

    local missing = Store.missing()

    if #missing > 0 and Config.database.autoMigrate then
        local ok, failure = pcall(Store.install)

        if ok then
            Util.log(('Database tables created: %s.'):format(table.concat(missing, ', ')))
        else
            Util.log('Creating the database tables failed: ' .. tostring(failure))
        end

        missing = Store.missing()
    end

    if #missing > 0 then
        local advice = Config.database.autoMigrate
            and 'Check the error above and that the database user may create tables.'
            or ('Import %s, or set Config.database.autoMigrate = true and restart.'):format(Store.schema)

        Util.log(('Database tables missing: %s. %s The resource stays idle until then.'):format(
            table.concat(missing, ', '),
            advice
        ))

        return false
    end

    local general = Settings.defaults().general
    local stored = Store.loadSettings()

    if type(stored.general) == 'table' then
        general = Util.merge(general, stored.general)
    end

    local overlay = ConfigRules.load(stored.config)

    pcall(Store.purgeRemoved, Util.integer(general.removedDays, 1, 365) or Config.general.removedDays)
    pcall(Store.purgeAudit, Util.integer(general.auditDays, 7, 365) or Config.general.auditDays)
    pcall(Store.purgeOs, overlay['os.notes.trashDays'] or Config.os.notes.trashDays)

    local problems = Registry.load(stored)

    for _, problem in ipairs(problems) do
        Util.log('Settings: ' .. problem)
    end

    local changed = Admin.applyConfig(Registry.settings.config or {})

    if #changed > 0 then
        Util.log(('Settings: the panel changes %d %s of config.lua.'):format(#changed, #changed == 1 and 'value' or 'values'))
    end

    for _, problem in ipairs(Brand.load(Registry.stored)) do
        Util.log('Brand: ' .. problem)
    end

    local moved, failure = DeviceScreen.migrateIdle()

    if moved > 0 then
        Util.log(('Idle pictures: %d devices showed a picture that is gone and now show the default one.'):format(moved))
    end

    if failure then
        Util.log('Idle pictures: could not save the default picture: ' .. tostring(failure))
    end

    Items.load()

    for _, problem in ipairs(DeviceRules.checkConfig()) do
        Util.log('config/kinds.lua: ' .. problem)
    end

    for _, problem in ipairs(Signal.load(stored.signal)) do
        Util.log('Signal: ' .. problem)
    end

    Apps.load()
    DeviceOs.load()
    AppStore.load()

    local noticed, noticeFailure = pcall(Notices.load)

    if not noticed then
        Util.log('notifications failed to load: ' .. tostring(noticeFailure))
    end

    Sessions.reset()
    GlobalState['evdev:rev'] = Registry.rev
    Registry.ready = true

    local hooked = Items.hook()
    local inventory = Integrations.inventoryName()
    local framework = Bridge.active()

    Util.log(('Framework: %s. Inventory: %s.'):format(framework.label, inventory or 'none'))

    if not inventory then
        Util.log('No supported inventory is running (ox_inventory, qb-inventory or the ESX inventory): players get no device items.')
    elseif not Integrations.keepsMetadata() then
        Util.log('The ESX inventory keeps no item metadata: serials stay on the server with the character who carries the device.')
    elseif not hooked then
        Util.log(('%s has no item hook: new device items get their serial when first used.'):format(inventory))
    end

    local counts = Devices.counts()

    Util.log(('Ready. Devices: %d (%d laptops, %d computers, %d terminals, %d tablets), %d removed. Apps known: %d.'):format(
        counts.all,
        counts.laptop,
        counts.pc,
        counts.terminal,
        counts.tablet,
        counts.removed,
        #Apps.ids()
    ))

    TriggerEvent('evolent_devices:ready')

    for _, source in ipairs(People.online()) do
        Spaces.refresh(source)
        Access.push(source)
    end

    return true
end

CreateThread(function()
    local ok, started = xpcall(start, debug.traceback)

    if not ok or not started then
        Registry.failed = true

        if not ok then
            Util.log('Could not start: ' .. tostring(started))
        end

        return
    end

    local cycle = 0

    while true do
        Wait(1000)
        cycle = cycle + 1
        Guard.sweep()

        if Sessions.tick then
            local ok, failure = pcall(Sessions.tick)

            if not ok then
                Util.log('session tick failed: ' .. tostring(failure))
            end
        end

        local ok, failure = pcall(Tablets.tick, GetGameTimer())

        if not ok then
            Util.log('tablet tick failed: ' .. tostring(failure))
        end

        Spaces.poll(cycle)

        if cycle % 5 == 0 then
            local noticed, noticeFailure = pcall(Notices.tick, os.time())

            if not noticed then
                Util.log('notification tick failed: ' .. tostring(noticeFailure))
            end
        end
    end
end)
