local Config = require 'config'
local Util = require 'shared.util'
local BrandRules = require 'shared.brand'

local ScreenRules = {
    KEYS = {
        'idle',
        'url',
        'lock',
        'name',
        'signal',
        'message',
        'wall',
    },
    DISPLAY_KEYS = {
        'brightness',
        'light',
        'color',
        'sleep',
        'night',
        'nightFrom',
        'nightTo',
    },
    SIGNAL = { 'kind', 'wired', 'wireless' },
    RANGES = {
        brightness = { 20, 100 },
        light = { 0, 200 },
        sleep = { 0, 240 },
        nightFrom = { 0, 1439 },
        nightTo = { 0, 1439 },
        lock = { 0, 120 },
    },
    NAME_LENGTH = 32,
    MESSAGE_LENGTH = 120,
    URL_LENGTH = 300,
    UV_INSET_TEXELS = 1.5,
    SLEEP_DIM = 50,
    SLEEP_SUFFIX = '_sleep.png',
    NEUTRAL_SUFFIX = '_neutral.png',
    NEUTRAL_SLEEP_SUFFIX = '_neutral_sleep.png',
}

local KNOWN, DISPLAY, SIGNALS = {}, {}, {}

for _, key in ipairs(ScreenRules.KEYS) do
    KNOWN[key] = true
end

for _, key in ipairs(ScreenRules.DISPLAY_KEYS) do
    DISPLAY[key] = true
end

for _, mode in ipairs(ScreenRules.SIGNAL) do
    SIGNALS[mode] = true
end

local BASE = {
    url = '',
    name = '',
    signal = 'kind',
    message = '',
    wall = '',
}

local DISPLAY_BASE = {
    brightness = 100,
    light = 100,
    color = '',
    sleep = 3,
    night = false,
    nightFrom = 1320,
    nightTo = 420,
}

local TEXTS = { name = ScreenRules.NAME_LENGTH, message = ScreenRules.MESSAGE_LENGTH }

local function idleConfig()
    local devices = Config.devices

    return type(devices) == 'table' and type(devices.idle) == 'table' and devices.idle or {}
end

function ScreenRules.presets(kind)
    local presets = idleConfig().presets
    local list = type(presets) == 'table' and presets[kind] or nil

    return type(list) == 'table' and list or {}
end

function ScreenRules.preset(kind, id)
    if type(id) ~= 'string' then return nil end

    for _, entry in ipairs(ScreenRules.presets(kind)) do
        if type(entry) == 'table' and entry.id == id then
            return entry
        end
    end

    return nil
end

local function deviceDefaults(kind)
    local value = Util.copy(BASE)
    local first = ScreenRules.presets(kind)[1]

    value.idle = type(first) == 'table' and first.id or 'url'
    value.lock = false

    return value
end

function ScreenRules.displayField(key, value)
    if not DISPLAY[key] then return nil end

    if key == 'night' then
        if type(value) ~= 'boolean' then return nil end

        return value
    end

    if key == 'color' then
        if value == '' or value == false then return '' end

        return ScreenRules.color(value)
    end

    local range = ScreenRules.RANGES[key]

    return Util.integer(value, range[1], range[2])
end

function ScreenRules.display(value)
    local general = type(Config.general) == 'table' and Config.general.display or nil
    local out = Util.copy(DISPLAY_BASE)

    for _, source in ipairs({ general, value }) do
        if type(source) == 'table' then
            for _, key in ipairs(ScreenRules.DISPLAY_KEYS) do
                local clean = ScreenRules.displayField(key, source[key])

                if clean ~= nil then
                    out[key] = clean
                end
            end
        end
    end

    if out.night and out.nightFrom == out.nightTo then
        out.night = false
    end

    return out
end

function ScreenRules.defaults(kind, display)
    local value = deviceDefaults(kind)

    for key, item in pairs(ScreenRules.display(display)) do
        value[key] = item
    end

    return value
end

function ScreenRules.isOs(kind)
    return type(Config.kinds[kind]) == 'table' and Config.kinds[kind].os == true
end

function ScreenRules.takesWall(kind)
    local OsRules = require 'shared.os'

    return OsRules.kind(kind)
end

function ScreenRules.takesPicture(kind)
    return Util.contains(BrandRules.IDLE_KINDS, kind)
end

function ScreenRules.wallFor(kind, wall)
    if ScreenRules.takesWall(kind) then
        return BrandRules.wallpaperId(wall)
    end

    return ScreenRules.takesPicture(kind) and BrandRules.ownId(wall) or nil
end

local PRIVATE_ENDS = { localhost = true, ['local'] = true, internal = true, lan = true, home = true }

function ScreenRules.publicHost(host)
    if type(host) ~= 'string' or #host > 253 or not host:find('^[%w%-%.]+$') then return false end
    if host:sub(1, 1) == '.' or host:sub(-1) == '.' or host:find('..', 1, true) then return false end

    local last, count = nil, 0

    for label in host:gmatch('[^%.]+') do
        if #label > 63 or label:sub(1, 1) == '-' or label:sub(-1) == '-' then return false end

        last, count = label:lower(), count + 1
    end

    return count >= 2 and last:find('^%a%a+$') ~= nil and not PRIVATE_ENDS[last]
end

function ScreenRules.url(value)
    if type(value) ~= 'string' or #value < 12 or #value > ScreenRules.URL_LENGTH then return nil end
    if value:find("[^%w%-%._~:/%?#@!%$&%+,;=%%]") then return nil end

    local authority = value:match('^https://([^/%?#]+)')

    if not authority or authority:find('@', 1, true) then return nil end

    local host, port = authority, nil

    if authority:find(':', 1, true) then
        host, port = authority:match('^([^:]+):(%d+)$')
    end

    if not host or (port and not Util.integer(tonumber(port), 1, 65535)) then return nil end

    return ScreenRules.publicHost(host) and value or nil
end

function ScreenRules.color(value)
    if type(value) ~= 'string' or not value:find('^#%x%x%x%x%x%x$') then return nil end

    return value:lower()
end

function ScreenRules.clean(kind, value)
    if type(value) ~= 'table' then
        return nil, 'invalid_screen'
    end

    for key in pairs(value) do
        if not KNOWN[key] and not DISPLAY[key] then
            return nil, 'invalid_screen', tostring(key)
        end
    end

    local base, out = deviceDefaults(kind), {}

    local function keep(key, clean)
        if clean ~= base[key] then
            out[key] = clean
        end
    end

    if value.idle ~= nil then
        if value.idle ~= 'url' and not ScreenRules.preset(kind, value.idle) then
            return nil, 'screen_idle', 'idle'
        end

        keep('idle', value.idle)
    end

    if value.url ~= nil and value.url ~= '' and value.url ~= false then
        local url = ScreenRules.url(value.url)

        if not url and (out.idle or base.idle) == 'url' then
            return nil, 'screen_url', 'url'
        end

        out.url = url
    end

    if (out.idle or base.idle) == 'url' and not out.url then
        return nil, 'screen_url', 'url'
    end

    if value.lock ~= nil and value.lock ~= false then
        local lock = Util.integer(value.lock, ScreenRules.RANGES.lock[1], ScreenRules.RANGES.lock[2])

        if not lock then
            return nil, 'screen_range', 'lock'
        end

        if ScreenRules.isOs(kind) then
            out.lock = lock
        end
    end

    for key, limit in pairs(TEXTS) do
        if value[key] ~= nil then
            local text = Util.cleanText(value[key], limit)

            if not text then
                return nil, 'screen_text', key
            end

            keep(key, text)
        end
    end

    if value.signal ~= nil then
        if not SIGNALS[value.signal] then
            return nil, 'invalid_screen', 'signal'
        end

        keep('signal', value.signal)
    end

    if value.wall ~= nil and value.wall ~= '' and value.wall ~= false then
        local wall = ScreenRules.wallFor(kind, value.wall)

        if not wall then
            return nil, 'screen_wall', 'wall'
        end

        out.wall = wall
    end

    return out
end

function ScreenRules.withoutDisplay(stored)
    if type(stored) ~= 'table' then return nil end

    local out = {}

    for key, value in pairs(stored) do
        if not DISPLAY[key] then
            out[key] = value
        end
    end

    return ScreenRules.compact(out)
end

function ScreenRules.wallOf(kind, wall)
    if wall == nil or wall == '' then return '' end

    if ScreenRules.takesWall(kind) then
        return BrandRules.wallpaperOr(wall) or ''
    end

    return ScreenRules.takesPicture(kind) and BrandRules.ownId(wall) or ''
end

function ScreenRules.resolve(kind, stored, display)
    local value = ScreenRules.defaults(kind, display)
    local copy = type(stored) == 'table' and ScreenRules.withoutDisplay(stored) or {}

    value.wall = ScreenRules.wallOf(kind, copy.wall)
    copy.wall = nil

    for _ = 0, #ScreenRules.KEYS do
        local clean, _, field = ScreenRules.clean(kind, copy)

        if clean then
            for key, item in pairs(clean) do
                value[key] = item
            end

            return value
        end

        if field == 'url' then
            copy.url, copy.idle = nil, nil
        elseif field ~= nil and copy[field] ~= nil then
            copy[field] = nil
        else
            return value
        end
    end

    return value
end

function ScreenRules.compact(value)
    if type(value) ~= 'table' or next(value) == nil then return nil end

    return value
end

function ScreenRules.changes(before, after, kind)
    local list, seen = {}, {}
    local own = kind ~= nil and not ScreenRules.takesWall(kind)

    for _, key in ipairs(ScreenRules.KEYS) do
        local a = type(before) == 'table' and before[key] or nil
        local b = type(after) == 'table' and after[key] or nil

        if a ~= b and not seen[key] then
            seen[key] = true
            list[#list + 1] = own and key == 'wall' and 'own' or key
        end
    end

    return list
end

function ScreenRules.signalMode(stored)
    local mode = type(stored) == 'table' and stored.signal or nil

    return SIGNALS[mode] and mode or 'kind'
end

function ScreenRules.wireless(kindWireless, stored)
    local mode = ScreenRules.signalMode(stored)

    if mode == 'wired' then return false end
    if mode == 'wireless' then return true end

    return kindWireless == true
end

function ScreenRules.inNight(minute, from, to)
    if not Util.isFinite(minute) or from == to then return false end

    if from < to then
        return minute >= from and minute < to
    end

    return minute >= from or minute < to
end

function ScreenRules.rest(value, idleMs, minute)
    if type(value) ~= 'table' then return nil end
    if value.night and ScreenRules.inNight(minute, value.nightFrom, value.nightTo) then return 'off' end

    if value.sleep > 0 and Util.isFinite(idleMs) and idleMs >= value.sleep * 60000 then
        return 'sleep'
    end

    return nil
end

function ScreenRules.sleepPicture(picture)
    if type(picture) ~= 'string' or not picture:find('^web/build/[%w_/%-]+%.[%a]+$') then return nil end

    return (picture:gsub('%.[%a]+$', ScreenRules.SLEEP_SUFFIX))
end

function ScreenRules.stillPicture(picture, sleep, neutral)
    if not neutral then
        return sleep and ScreenRules.sleepPicture(picture) or nil
    end

    if type(picture) ~= 'string' or not picture:find('^web/build/[%w_/%-]+%.[%a]+$') then return nil end

    return (picture:gsub('%.[%a]+$', sleep and ScreenRules.NEUTRAL_SLEEP_SUFFIX or ScreenRules.NEUTRAL_SUFFIX))
end

function ScreenRules.rgb(hex)
    local color = ScreenRules.color(hex)

    if not color then return nil end

    return { tonumber(color:sub(2, 3), 16), tonumber(color:sub(4, 5), 16), tonumber(color:sub(6, 7), 16) }
end

function ScreenRules.light(light, value, own)
    if type(light) ~= 'table' then return nil end

    if type(value) ~= 'table' then
        return light
    end

    local share = (value.light or 100) / 100

    if share <= 0 then return nil end

    local out = Util.copy(light)

    out.intensity = light.intensity * share

    local rgb = type(own) == 'table' and own or ScreenRules.rgb(value.color)

    if rgb then
        out.r, out.g, out.b = rgb[1], rgb[2], rgb[3]
    end

    return out
end

function ScreenRules.lookWall(kind, value, brand)
    if type(value) ~= 'table' or value.idle == 'url' then return nil end

    local wall = ScreenRules.wallOf(kind, value.wall)

    if wall ~= '' then
        return BrandRules.wallpaperOf(wall), false
    end

    return BrandRules.idleOf(kind, brand), true
end

function ScreenRules.look(kind, value, state, brand)
    local wall, shared = ScreenRules.lookWall(kind, value, brand)
    local stock = value.idle ~= 'url' and ScreenRules.preset(kind, value.idle) or nil
    local preset = not wall and stock or nil
    local spare = wall and wall.own and (shared or not ScreenRules.takesWall(kind)) and stock or nil

    return {
        state = state or 'idle',
        preset = preset and preset.id or nil,
        picture = wall and wall.file or preset and preset.picture or nil,
        url = value.idle == 'url' and value.url or nil,
        wall = wall and wall.id or nil,
        plain = wall and wall.own or nil,
        spare = spare and spare.picture or nil,
        name = value.name ~= '' and value.name or nil,
        brightness = value.brightness,
        dim = state == 'sleep' and ScreenRules.SLEEP_DIM or nil,
        message = value.message ~= '' and value.message or nil,
    }
end

function ScreenRules.lookKey(look)
    return table.concat(
        {
            look.state or '',
            look.preset or '',
            look.url or '',
            look.wall or '',
            look.picture or '',
            tostring(look.plain or false),
            look.spare or '',
            look.name or '',
            tostring(look.brightness or ''),
            look.message or '',
            tostring(look.unread or 0),
        },
        '\31'
    )
end

function ScreenRules.detailLevel(full, shown, detail, current)
    if not Util.isFinite(shown) or shown <= 0 or not Util.isFinite(full) or full <= 0 then
        return 0
    end

    local raw = math.log(full / (shown * (detail or 1.0)), 2) * 4

    if raw <= 0 then
        return 0
    end

    local level = math.floor(raw)

    if current and level ~= current and raw > current - 0.35 and raw < current + 1.35 then
        return current
    end

    return level
end

function ScreenRules.uvInset(width, height)
    if not Util.isFinite(width) or width <= 0 or not Util.isFinite(height) or height <= 0 then
        return 0.0, 0.0
    end

    return ScreenRules.UV_INSET_TEXELS / width, ScreenRules.UV_INSET_TEXELS / height
end

function ScreenRules.levelSize(full, level)
    if not level or level <= 0 then
        return full
    end

    return math.max(16, math.floor(full / 2 ^ (level / 4)))
end

function ScreenRules.checkConfig(idle, kinds)
    local problems = {}

    local function fail(text)
        problems[#problems + 1] = 'idle.' .. text
    end

    if idle == nil then
        return problems
    end

    if type(idle) ~= 'table' then
        return { 'idle must be a table' }
    end

    local live = idle.live

    if live ~= nil then
        if type(live) ~= 'table' then
            fail('live must be a table')
        else
            if live.enabled ~= nil and type(live.enabled) ~= 'boolean' then
                fail('live.enabled must be true or false')
            end

            if not Util.integer(live.max, 0, 8) then
                fail('live.max must be a whole number from 0 to 8')
            end

            if type(live.range) ~= 'table' then
                fail('live.range must give metres per kind')
            else
                for kind, range in pairs(live.range) do
                    if type(kinds[kind]) ~= 'table' or not Util.number(range, 0.5, 40) then
                        fail('live.range.' .. tostring(kind) .. ' must be a screen kind with metres from 0.5 to 40')
                    end
                end
            end

            if live.keep ~= nil and not Util.number(live.keep, 0, 10) then
                fail('live.keep must be metres from 0 to 10')
            end

            if live.lingerMs ~= nil and not Util.integer(live.lingerMs, 0, 120000) then
                fail('live.lingerMs must be milliseconds from 0 to 120000')
            end

            if live.fadeMs ~= nil and not Util.integer(live.fadeMs, 0, 2000) then
                fail('live.fadeMs must be milliseconds from 0 to 2000')
            end

            if live.detail ~= nil and not Util.number(live.detail, 0.75, 2) then
                fail('live.detail must be from 0.75 to 2')
            end

            if live.upscale ~= nil and live.upscale ~= 'sharp' and live.upscale ~= 'smooth' then
                fail("live.upscale must be 'sharp' or 'smooth'")
            end
        end
    end

    local dark = idle.dark

    if dark ~= nil and (type(dark) ~= 'table' or (dark.enabled ~= nil and type(dark.enabled) ~= 'boolean') or not Util.integer(dark.max, 0, 16)) then
        fail('dark needs enabled true or false and max, a whole number from 0 to 16')
    end

    local presets = idle.presets

    if type(presets) ~= 'table' then
        fail('presets must list the pictures of each kind')

        return problems
    end

    for kind, list in pairs(presets) do
        if type(kinds[kind]) ~= 'table' or type(list) ~= 'table' or #list == 0 then
            fail('presets.' .. tostring(kind) .. ' must be a screen kind with at least one picture')
        else
            local seen = {}

            for index, entry in ipairs(list) do
                local where = ('presets.%s[%d]'):format(kind, index)

                if type(entry) ~= 'table' or type(entry.id) ~= 'string' or not entry.id:find('^[a-z][a-z0-9_]*$') or entry.id == 'url' then
                    fail(where .. ' needs a lower-case id (not url)')
                elseif seen[entry.id] then
                    fail(where .. ' repeats the id ' .. entry.id)
                else
                    seen[entry.id] = true

                    local picture = entry.picture
                    local inside = type(picture) == 'string' and picture:find('^web/build/[%w_/%-]+%.[%a]+$')

                    if not inside or picture:find('..', 1, true) then
                        fail(where .. '.picture must be an image file of this resource under web/build/')
                    end
                end
            end
        end
    end

    return problems
end

return ScreenRules
