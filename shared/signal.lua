local Config = require 'config'
local Util = require 'shared.util'

local SignalRules = { MAX_BARS = 4 }

local RADIUS_MIN, RADIUS_MAX = 50.0, 6000.0
local POINTS = { table = true, vector3 = true, vector4 = true }
local STRENGTH_MIN, STRENGTH_MAX = 10, 100

function SignalRules.config()
    return Config.signal
end

function SignalRules.tower(id)
    if type(id) ~= 'string' then return nil end

    for _, tower in ipairs(Config.towers or {}) do
        if tower.id == id then
            return tower
        end
    end

    return nil
end

function SignalRules.towerDefaults(tower)
    local types = SignalRules.config().towerTypes or {}
    local entry = tower and types[tower.type] or nil

    return {
        radius = entry and entry.radius or SignalRules.config().radius,
        strength = entry and entry.strength or SignalRules.config().strength,
    }
end

function SignalRules.isMast(model)
    return type(model) == 'string' and Util.contains(SignalRules.config().masts or {}, model)
end

function SignalRules.quality(antenna, point)
    if not antenna.on then
        return 0
    end

    local dx, dy = point.x - antenna.x, point.y - antenna.y
    local share = (dx * dx + dy * dy) / (antenna.radius * antenna.radius)

    if share >= 1.0 then
        return 0
    end

    return antenna.strength * (1.0 - share)
end

function SignalRules.barsFor(quality, thresholds)
    thresholds = thresholds or SignalRules.config().bars

    local bars = 0

    for index = 1, SignalRules.MAX_BARS do
        if quality >= (thresholds[index] or math.huge) then
            bars = index
        end
    end

    return bars
end

function SignalRules.reading(antennas, point, space, config)
    config = config or SignalRules.config()

    if config.enabled == false then
        return { bars = SignalRules.MAX_BARS, quality = 100 }
    end

    if not POINTS[type(point)] or not Util.isFinite(point.x) or not Util.isFinite(point.y) then
        return { bars = 0, quality = 0 }
    end

    local best, from = 0, nil

    for _, antenna in ipairs(antennas or {}) do
        local quality = SignalRules.quality(antenna, point)

        if quality > best then
            best, from = quality, antenna.id
        end
    end

    local bars = SignalRules.barsFor(best, config.bars)

    if type(space) == 'string' and space:sub(1, 1) == 'p' then
        bars = math.max(0, bars - (config.homeLoss or 0))
    end

    return { bars = bars, quality = math.floor(best + 0.5), antenna = from }
end

local function label(value, fallback)
    if value == nil then
        return fallback
    end

    local text = Util.cleanText(value, 40)

    if not text or Util.hasForbidden(text) then return nil end

    return text
end

function SignalRules.cleanAntenna(entry)
    if type(entry) ~= 'table' then
        return nil, 'invalid_antenna'
    end

    local id = Util.integer(entry.id, 1, 1000000)
    local radius = Util.number(tonumber(entry.radius), RADIUS_MIN, RADIUS_MAX)
    local strength = Util.integer(tonumber(entry.strength), STRENGTH_MIN, STRENGTH_MAX)

    if not radius or not strength then
        return nil, 'invalid_antenna'
    end

    local clean = { id = id, radius = Util.round(radius, 1), strength = strength, on = entry.on ~= false }

    if entry.source == 'tower' then
        local tower = SignalRules.tower(entry.tower)

        if not tower then
            return nil, 'unknown_tower'
        end

        clean.source, clean.tower = 'tower', tower.id
        clean.x, clean.y, clean.z, clean.h = tower.x, tower.y, tower.z, tower.h or 0.0
        clean.label = label(entry.label, '')
    elseif entry.source == 'mast' then
        if not SignalRules.isMast(entry.model) then
            return nil, 'invalid_mast'
        end

        local position = Util.position({ x = entry.x, y = entry.y, z = entry.z, h = entry.h })

        if not position then
            return nil, 'invalid_position'
        end

        clean.source, clean.model = 'mast', entry.model
        clean.x, clean.y, clean.z, clean.h = position.x, position.y, position.z, position.h
        clean.label = label(entry.label, '')
    else
        return nil, 'invalid_antenna'
    end

    if clean.label == nil then
        return nil, 'invalid_label'
    end

    return clean
end

function SignalRules.normalize(list, limit)
    limit = limit or (Config.limits and Config.limits.antennas) or 200

    if type(list) ~= 'table' or #list > limit then
        return nil, 'too_many_antennas'
    end

    local clean, used, highest, towers = {}, {}, 0, {}

    for index, entry in ipairs(list) do
        local antenna, reason = SignalRules.cleanAntenna(entry)

        if not antenna then
            return nil, reason, index
        end

        if antenna.source == 'tower' then
            if towers[antenna.tower] then
                return nil, 'tower_twice', index
            end

            towers[antenna.tower] = true
        end

        if antenna.id and not used[antenna.id] then
            used[antenna.id] = true
            highest = math.max(highest, antenna.id)
        else
            antenna.id = nil
        end

        clean[index] = antenna
    end

    for _, antenna in ipairs(clean) do
        if not antenna.id then
            highest = highest + 1
            antenna.id = highest
        end
    end

    return clean
end

function SignalRules.cleanKinds(value, current)
    if type(value) ~= 'table' then return nil end

    local clean = Util.copy(current or {})

    for kind, wireless in pairs(value) do
        if not Config.kinds[kind] or type(wireless) ~= 'boolean' then return nil end

        clean[kind] = wireless
    end

    return clean
end

function SignalRules.defaultKinds()
    local kinds = {}

    for _, kind in ipairs(Config.kindOrder) do
        kinds[kind] = Config.kinds[kind].wireless == true
    end

    return kinds
end

function SignalRules.starter()
    local list = {}

    for _, entry in ipairs(SignalRules.config().starter or {}) do
        local wide = type(entry) == 'table'
        local tower = SignalRules.tower(wide and entry.tower or entry)

        if tower then
            local values = SignalRules.towerDefaults(tower)

            list[#list + 1] = {
                source = 'tower',
                tower = tower.id,
                on = true,
                radius = wide and entry.radius or values.radius,
                strength = wide and entry.strength or values.strength,
            }
        end
    end

    return SignalRules.normalize(list) or {}
end

return SignalRules
