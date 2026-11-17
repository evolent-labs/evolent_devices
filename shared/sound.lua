local Config = require 'config'
local Util = require 'shared.util'

local DeviceSound = {
    BATCH_MS = 250,
    PER_BATCH = 8,
    RATE = 5,
    RELAY_SLACK = 2.0,
    FULL_WITHIN = 1.0,
    PAN_WIDTH = 0.8,
    OS_GAP_MS = 120,
}

DeviceSound.OS_SOUNDS = { notice = true }

local MOUSE = { laptop = true, pc = true }
local TOUCH = { terminal = true, tablet = true }

local function clamp(value, low, high, fallback)
    local number = tonumber(value)

    if not Util.isFinite(number) then
        number = fallback
    end

    return math.max(low, math.min(high, number))
end

function DeviceSound.settings(value)
    local base = Config.general.sound

    if type(value) ~= 'table' then
        value = base
    end

    local enabled = value.enabled

    if type(enabled) ~= 'boolean' then
        enabled = base.enabled ~= false
    end

    return {
        enabled = enabled,
        volume = clamp(value.volume, 0, 100, base.volume),
        nearby = clamp(value.nearby, 0, 100, base.nearby),
        range = clamp(value.range, 3, 10, base.range),
    }
end

function DeviceSound.heard(kind)
    local spec = Config.kinds and Config.kinds[kind]

    if type(spec) == 'table' and spec.sound == false then return false end

    return MOUSE[kind] == true or TOUCH[kind] == true
end

function DeviceSound.clickName(kind)
    return TOUCH[kind] and 'tap' or 'click'
end

function DeviceSound.rightClick(kind, button)
    return MOUSE[kind] == true and button == 'right'
end

function DeviceSound.osSound(kind, name)
    return MOUSE[kind] == true and DeviceSound.OS_SOUNDS[name] == true
end

function DeviceSound.batch(kind, clicks, rights)
    if not DeviceSound.heard(kind) then return nil end

    clicks = Util.integer(clicks, 0, DeviceSound.PER_BATCH)
    rights = Util.integer(rights, 0, DeviceSound.PER_BATCH)

    if not clicks or not rights then return nil end

    if not MOUSE[kind] then
        rights = 0
    end

    if clicks + rights == 0 then return nil end

    return { clicks = clicks, rights = rights }
end

function DeviceSound.sounds(kind, batch)
    local list = {}

    if batch.clicks > 0 then
        list[DeviceSound.clickName(kind)] = batch.clicks
    end

    if batch.rights > 0 then
        list.rclick = batch.rights
    end

    return list
end

function DeviceSound.level(percent)
    return clamp(percent, 0, 100, 0) / 100
end

function DeviceSound.falloff(distance, range)
    if not Util.isFinite(distance) or distance >= range then return 0.0 end
    if distance <= DeviceSound.FULL_WITHIN then return 1.0 end

    local share = (range - distance) / (range - DeviceSound.FULL_WITHIN)

    return share * share
end

function DeviceSound.userGain(settings)
    if not settings.enabled then return 0.0 end

    return DeviceSound.level(settings.volume)
end

function DeviceSound.mix(gain, percent)
    return Util.round(gain * DeviceSound.level(percent), 3)
end

function DeviceSound.nearbyGain(distance, settings)
    if not settings.enabled then return 0.0 end

    return Util.round(DeviceSound.level(settings.nearby) * DeviceSound.falloff(distance, settings.range), 3)
end

function DeviceSound.pan(listener, yaw, source)
    if not Util.isFinite(yaw) then return 0.0 end

    local dx, dy = source.x - listener.x, source.y - listener.y
    local length = math.sqrt(dx * dx + dy * dy)

    if length < 0.05 then return 0.0 end

    local angle = math.rad(yaw)
    local side = (dx * math.cos(angle) + dy * math.sin(angle)) / length

    return Util.round(math.max(-1.0, math.min(1.0, side)) * DeviceSound.PAN_WIDTH, 3)
end

function DeviceSound.relayRange(settings)
    return settings.range + DeviceSound.RELAY_SLACK
end

return DeviceSound
