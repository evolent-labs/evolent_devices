local Config = require 'config'
local Util = require 'shared.util'
local ScreenRules = require 'shared.screen'
local DeviceRules = require 'shared.rules'
local Store = require 'server.store'
local Registry = require 'server.registry'
local Sessions = require 'server.sessions'
local Signal = require 'server.signal'

local DeviceScreen = {}

function DeviceScreen.display()
    return Registry.settings and Registry.settings.general.display or nil
end

function DeviceScreen.of(device)
    return ScreenRules.resolve(device.kind, device.screen, DeviceScreen.display())
end

Sessions.on('open', function(_, device, answer)
    local screen = DeviceScreen.of(device)

    if ScreenRules.isOs(device.kind) and screen.lock ~= false then
        answer.lockMinutes = screen.lock
    end

    if type(answer.device) == 'table' and screen.name ~= '' then
        answer.device.name = screen.name
    end

    answer.screen = { brightness = screen.brightness, message = screen.message ~= '' and screen.message or nil }

    return nil
end)

Sessions.on('watch', function(lock, reply)
    local device = Registry.device(lock.id)

    if device then
        local screen = DeviceScreen.of(device)

        reply.extra.screen = {
            brightness = screen.brightness,
            name = screen.name ~= '' and screen.name or nil,
            message = screen.message ~= '' and screen.message or nil,
        }
    end

    return nil
end)

function DeviceScreen.migrateIdle()
    local moved = 0

    for _, device in ipairs(Registry.list()) do
        local stored = device.screen
        local idle = type(stored) == 'table' and stored.idle or nil

        if idle ~= nil and idle ~= 'url' and #ScreenRules.presets(device.kind) > 0 and not ScreenRules.preset(device.kind, idle) then
            local screen = Util.copy(stored)

            screen.idle = nil
            screen = ScreenRules.compact(screen)

            local ok, failure = pcall(Store.saveScreen, device.id, screen)

            if not ok then
                return moved, failure
            end

            device.screen = screen
            moved = moved + 1
        end
    end

    return moved
end

local function hex(light)
    if not light then return nil end

    return ('#%02x%02x%02x'):format(light.r, light.g, light.b)
end

function DeviceScreen.info(kind)
    local spec = Config.kinds[kind] or {}
    local idle = type(Config.devices.idle) == 'table' and Config.devices.idle or {}
    local live = type(idle.live) == 'table' and idle.live or {}
    local presets = {}

    for _, entry in ipairs(ScreenRules.presets(kind)) do
        presets[#presets + 1] = {
            id = entry.id,
            picture = entry.picture,
            label = entry.label,
        }
    end

    local light = DeviceRules.light(spec)

    return {
        presets = presets,
        defaults = ScreenRules.defaults(kind, DeviceScreen.display()),
        ranges = Util.copy(ScreenRules.RANGES),
        limits = { name = ScreenRules.NAME_LENGTH, message = ScreenRules.MESSAGE_LENGTH, url = ScreenRules.URL_LENGTH },
        liveRange = live.enabled ~= false and type(live.range) == 'table' and live.range[kind] or 0,
        lockMinutes = Registry.settings.general.session.lockMinutes,
        wireless = Config.signal.enabled ~= false and Signal.kinds[kind] == true,
        lightColor = hex(light),
        os = spec.os == true,
        kind = kind,
        pictures = ScreenRules.takesPicture(kind),
        size = spec.dui and { width = spec.dui.width, height = spec.dui.height } or nil,
    }
end

return DeviceScreen
