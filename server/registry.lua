local Util = require 'shared.util'
local ConfigRules = require 'shared.config_rules'
local Store = require 'server.store'

local Registry = {
    ready = false,
    devices = {},
    settings = nil,
    settingsRev = 0,
    rev = 0,
    stored = {},
    holds = 0,
    held = false,
}

local function announce()
    if Registry.holds > 0 then
        Registry.held = true

        return
    end

    Registry.held = false
    GlobalState['evdev:rev'] = Registry.rev
end

function Registry.batch(action)
    Registry.holds = Registry.holds + 1

    local ok, result = pcall(action)

    Registry.holds = Registry.holds - 1

    if Registry.holds == 0 and Registry.held then
        announce()
    end

    if not ok then
        error(result, 0)
    end

    return result
end

function Registry.load(stored)
    local Settings = require 'server.settings'

    Registry.devices = {}

    for _, device in ipairs(Store.loadDevices()) do
        Registry.devices[device.id] = device
    end

    stored = stored or Store.loadSettings()

    local settings, problems = Settings.load(stored)

    Registry.settings = settings
    Registry.stored = stored
    Registry.settingsRev = 1

    return problems
end

function Registry.device(id)
    return id ~= nil and Registry.devices[id] or nil
end

function Registry.list(keep)
    local list = {}

    for _, device in pairs(Registry.devices) do
        if not keep or keep(device) then
            list[#list + 1] = device
        end
    end

    table.sort(list, function(a, b) return a.id < b.id end)

    return list
end

function Registry.put(device)
    Registry.devices[device.id] = device

    return device
end

function Registry.view(device)
    local Spaces = require 'server.spaces'
    local DeviceLook = require 'server.look'

    return {
        id = device.id,
        kind = device.kind,
        model = device.variant,
        x = device.x,
        y = device.y,
        z = device.z,
        h = device.heading,
        space = Spaces.ofDevice(device),
        item = device.origin == 'item',
        enabled = device.enabled == true,
        screen = device.screen,
        used = Registry.idleSeconds(device),
        oos = (device.kind == 'terminal' and type(device.page) ~= 'table') or nil,
        look = DeviceLook.get(device),
    }
end

function Registry.idleSeconds(device)
    local last = math.max(device.lastUsedAt or 0, device.updatedAt or 0, device.createdAt or 0)

    if last <= 0 then
        return 0
    end

    return math.max(0, os.time() - last)
end

local function shown(device)
    return device.state == 'placed' and device.kind ~= 'tablet'
end

function Registry.snapshot(space)
    local Spaces = require 'server.spaces'

    local devices = {}

    for _, device in ipairs(Registry.list(function(entry)
        return shown(entry) and Spaces.ofDevice(entry) == space
    end)) do
        devices[#devices + 1] = Registry.view(device)
    end

    return { rev = Registry.rev, devices = devices }
end

function Registry.publish(device)
    local Spaces = require 'server.spaces'
    local DeviceLook = require 'server.look'

    Registry.rev = Registry.rev + 1
    announce()
    DeviceLook.fresh(device)

    local space = shown(device) and Spaces.ofDevice(device) or nil
    local view = space and Registry.view(device) or nil

    for source, known in pairs(Spaces.known) do
        if known == space then
            TriggerClientEvent('evdev:client:upsert', source, view, Registry.rev)
        else
            TriggerClientEvent('evdev:client:remove', source, device.id, Registry.rev)
        end
    end
end

function Registry.bySerial(serial)
    if type(serial) ~= 'string' then return nil end

    for _, device in pairs(Registry.devices) do
        if device.serial == serial then
            return device
        end
    end

    return nil
end

function Registry.placedNear(position, space, radius, kind)
    local Spaces = require 'server.spaces'

    local list = {}

    for _, device in pairs(Registry.devices) do
        if device.state == 'placed' and device.x and Spaces.ofDevice(device) == space and (not kind or device.kind == kind) then
            local distance = Util.distance(device, position)

            if distance <= radius then
                list[#list + 1] = { device = device, distance = distance }
            end
        end
    end

    table.sort(list, function(a, b) return a.distance < b.distance end)

    return list
end

function Registry.saveSettings(settings)
    Store.saveSetting('general', settings.general)
    Store.saveSetting('kinds', settings.kinds)

    if not Util.same(Registry.settings and Registry.settings.config or {}, settings.config or {}) then
        Store.saveSetting(ConfigRules.STORE, settings.config or {})
    end

    Registry.settings = settings
    Registry.settingsRev = Registry.settingsRev + 1
end

function Registry.saveZones(zones)
    Store.saveSetting('zones', zones)
    Registry.settings.zones = zones
    Registry.settingsRev = Registry.settingsRev + 1
end

return Registry
