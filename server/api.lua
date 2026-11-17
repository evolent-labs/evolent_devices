local Util = require 'shared.util'
local AppRules = require 'shared.apps'
local Registry = require 'server.registry'
local Access = require 'server.access'
local Apps = require 'server.apps'
local Signal = require 'server.signal'
local AppHost = require 'server.hosting'
local DeviceLook = require 'server.look'
local Spawn = require 'server.spawn'
local Tablets = require 'server.tablet'
local Notices = require 'server.notices'
local Admin = require 'server.admin'

local reported = {}

local function caller()
    return GetInvokingResource() or GetCurrentResourceName()
end

local function reportOnce(resource, id, reason)
    local key = ('%s:%s:%s'):format(resource, tostring(id), tostring(reason))

    if reported[key] then return end

    reported[key] = true

    if reason == 'unsupported_api' then
        print(('[evolent_devices] %s: app %s needs a newer evolent_devices (this one speaks api %d).'):format(
            resource,
            tostring(id),
            AppRules.API
        ))
    else
        print(('[evolent_devices] %s: app or provider %s was refused: %s.'):format(
            resource,
            tostring(id),
            tostring(reason)
        ))
    end
end

exports('apiVersion', function()
    return AppRules.API
end)

exports('registerApp', function(def)
    local resource = caller()
    local ok, reason = Apps.register(def, resource)

    if not ok then
        reportOnce(resource, type(def) == 'table' and def.id or nil, reason)
    end

    return ok, reason
end)

exports('unregisterApp', function(id)
    return Apps.unregister(id, caller())
end)

exports('registerAccess', function(def)
    local resource = caller()
    local ok, reason = Access.registerProvider(def, resource)

    if not ok then
        reportOnce(resource, type(def) == 'table' and def.id or nil, reason)
    end

    return ok, reason
end)

exports('unregisterAccess', function(id)
    return Access.unregisterProvider(id, caller())
end)

exports('accessChanged', function(providerId, value)
    if type(providerId) ~= 'string' then
        return 0
    end

    return Access.changed(providerId, type(value) == 'string' and value or nil)
end)

exports('lookChanged', function()
    return DeviceLook.changed(caller())
end)

exports('getApps', function()
    return Apps.list()
end)

exports('devicesNear', function(coords, radius, kind)
    local spot = Util.position(coords)
    local range = Util.number(radius, 0, 200)

    if not spot or not range then
        return {}
    end

    local list = {}

    for _, entry in ipairs(Registry.placedNear(spot, type(coords) == 'table' and coords.space or 'b0', range, kind)) do
        list[#list + 1] = {
            id = entry.device.id,
            kind = entry.device.kind,
            x = entry.device.x,
            y = entry.device.y,
            z = entry.device.z,
            distance = entry.distance,
        }
    end

    return list
end)

exports('appUser', function(source, appId)
    if type(appId) ~= 'string' or not AppHost.owned(appId, caller()) then return nil end

    return AppHost.user(tonumber(source), appId)
end)

exports('closeApp', function(source, appId, reason)
    if type(appId) ~= 'string' then return false end

    return AppHost.closeFor(tonumber(source), appId, reason, caller())
end)

exports('sendAppMessage', function(source, appId, message)
    if type(appId) ~= 'string' then
        return false, 'unknown_app'
    end

    return AppHost.message(tonumber(source), appId, message, caller())
end)

exports('notify', function(source, appId, notice)
    if type(appId) ~= 'string' then
        return false, 'unknown_app'
    end

    return Notices.send(tonumber(source), appId, notice, caller())
end)

exports('notifyDevice', function(deviceId, appId, notice)
    if type(appId) ~= 'string' then
        return false, 'unknown_app'
    end

    return Notices.sendDevice(deviceId, appId, notice, caller())
end)

exports('openTablet', function(source, options)
    local player = tonumber(source)

    if not player or type(options) ~= 'table' or type(options.app) ~= 'string' then
        return false, 'invalid_definition'
    end

    return Tablets.lend(player, options.app, options.intent, caller())
end)

exports('signalAt', function(coords, space)
    local spot = Util.position(coords)

    if not spot then
        return 0
    end

    return Signal.at(spot, type(space) == 'string' and space or 'b0').bars
end)

exports('openAdmin', function(source, deviceId)
    return Admin.open(source, deviceId)
end)

exports('spawnDevice', function(def)
    local resource = caller()
    local ok, id, reason = pcall(Spawn.create, resource, def)

    if not ok then
        print(('[evolent_devices] %s: spawnDevice failed: %s'):format(resource, tostring(id)))

        return nil, 'internal_error'
    end

    local key = ('%s:spawn:%s'):format(resource, tostring(reason))

    if not id and not reported[key] then
        reported[key] = true
        print(('[evolent_devices] %s: spawnDevice was refused: %s.'):format(resource, tostring(reason)))
    end

    return id, reason
end)

exports('removeDevice', function(id)
    return Spawn.remove(caller(), id)
end)

exports('moveDevice', function(id, coords, heading)
    local resource = caller()
    local ok, done, reason = pcall(Spawn.move, resource, id, coords, heading)

    if not ok then
        print(('[evolent_devices] %s: moveDevice failed: %s'):format(resource, tostring(done)))

        return false, 'internal_error'
    end

    return done, reason
end)

exports('getDevice', function(id)
    return Spawn.get(id)
end)

exports('setOnlyApp', function(id, appId)
    local ok, done, reason = pcall(Spawn.setOnly, caller(), id, appId)

    if not ok then
        print(('[evolent_devices] %s: setOnlyApp failed: %s'):format(caller(), tostring(done)))

        return false, 'internal_error'
    end

    return done, reason
end)
