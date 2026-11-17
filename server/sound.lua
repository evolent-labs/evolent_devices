local Util = require 'shared.util'
local DeviceRules = require 'shared.rules'
local DeviceSound = require 'shared.sound'
local Guard = require 'server.guard'
local Registry = require 'server.registry'
local People = require 'server.people'
local Spaces = require 'server.spaces'
local Sessions = require 'server.sessions'

local DeviceSounds = {}

local LISTEN_MS = 1000

local function settings()
    return DeviceSound.settings(Registry.settings.general.sound)
end

local function outOfService(device)
    return device.kind == 'terminal' and type(device.page) ~= 'table'
end

function DeviceSounds.listeners(lock, sender, range)
    local list = {}

    for _, target in ipairs(People.near(lock.point, range, sender)) do
        if Spaces.last(target) == lock.space then
            list[#list + 1] = target
        end
    end

    return list
end

function DeviceSounds.relay(source, token, clicks, rights)
    local lock = Sessions.owned(source, token)

    if not lock then return false end

    local current = settings()

    if not current.enabled or current.nearby <= 0 then return false end
    if not Guard.rate(source, 'device_sound', DeviceSound.RATE, 1000) then return false end

    local batch = DeviceSound.batch(lock.kind, clicks, rights)

    if not batch then return false end

    local device = Registry.device(lock.id)

    if not device or device.state ~= 'placed' then return false end
    if not device.enabled or outOfService(device) then return false end

    local at = People.coords(source)
    local reach = DeviceRules.spec(lock.kind).use.reach + Sessions.KEEP_SLACK

    if not at or Util.distance(at, lock.point) > reach then return false end
    if Spaces.recent(source) ~= lock.space then return false end

    local now = GetGameTimer()

    if not lock.heard or now - lock.heardAt >= LISTEN_MS then
        lock.heard, lock.heardAt = DeviceSounds.listeners(lock, source, DeviceSound.relayRange(current)), now
    end

    local listeners = lock.heard

    for _, target in ipairs(listeners) do
        TriggerClientEvent('evdev:client:deviceSound', target, lock.id, lock.kind, lock.point, batch.clicks, batch.rights)
    end

    return #listeners
end

RegisterNetEvent('evdev:device:sound', function(token, clicks, rights)
    if not Registry.ready then return end

    DeviceSounds.relay(source, token, clicks, rights)
end)

return DeviceSounds
