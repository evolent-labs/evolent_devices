local Config = require 'config'
local Util = require 'shared.util'
local BrandRules = require 'shared.brand'
local OsRules = require 'shared.os'

local ConfigRules = { KEY = 'evdev:config', STORE = 'config', shipped = {}, byPath = {} }

ConfigRules.GROUPS = {
    { id = 'devices', picture = 'pc' },
    { id = 'use', picture = 'laptop' },
    { id = 'sound', picture = 'laptop' },
    { id = 'screens', picture = 'terminal' },
    { id = 'os', picture = 'pc' },
    { id = 'tablet', picture = 'tablet' },
    { id = 'notifications', picture = 'laptop' },
    { id = 'nearby', picture = 'terminal' },
    { id = 'placing', picture = 'laptop' },
    { id = 'signal', picture = 'tablet' },
    { id = 'advanced', picture = 'pc' },
}

ConfigRules.SECTIONS = {
    { id = 'kinds', group = 'devices' },
    { id = 'start', group = 'devices' },
    { id = 'sessions', group = 'use' },
    { id = 'interaction', group = 'use' },
    { id = 'sound', group = 'sound' },
    { id = 'display', group = 'screens' },
    { id = 'sleep', group = 'screens' },
    { id = 'light', group = 'screens' },
    { id = 'night', group = 'screens' },
    { id = 'live', group = 'screens' },
    { id = 'os_apps', group = 'os' },
    { id = 'notes', group = 'os' },
    { id = 'photos', group = 'os' },
    { id = 'password', group = 'os' },
    { id = 'tablet_look', group = 'tablet' },
    { id = 'tablet_light', group = 'tablet' },
    { id = 'notice_popup', group = 'notifications' },
    { id = 'notice_tablet', group = 'notifications' },
    { id = 'notice_screen', group = 'notifications' },
    { id = 'notice_keep', group = 'notifications' },
    { id = 'nearby', group = 'nearby' },
    { id = 'watching', group = 'nearby' },
    { id = 'markers', group = 'placing' },
    { id = 'surfaces', group = 'placing' },
    { id = 'connection', group = 'advanced' },
    { id = 'history', group = 'advanced' },
    { id = 'walking', group = 'advanced' },
    { id = 'tablet_hold', group = 'advanced' },
}

ConfigRules.LIST = {
    { 'devices.interaction.useTarget', 'use', 'bool', name = 'use_target', section = 'interaction', restart = true },
    { 'devices.interaction.prompt', 'use', 'select', name = 'prompt', section = 'interaction', options = { 'evolent', 'ox' } },
    { 'devices.light.enabled', 'screens', 'bool', name = 'lights', section = 'light' },
    { 'devices.light.max', 'screens', 'number', name = 'lights_max', section = 'light', min = 1, max = 8, whole = true },
    { 'devices.light.range', 'screens', 'number', name = 'lights_range', section = 'light', min = 5, max = 40, step = 1, unit = 'm' },
    { 'devices.idle.live.enabled', 'screens', 'bool', name = 'live', section = 'live' },
    { 'devices.idle.live.max', 'screens', 'number', name = 'live_max', section = 'live', min = 1, max = 8, whole = true },
    { 'devices.idle.live.range.laptop', 'screens', 'number', name = 'live_range_laptop', section = 'live', min = 0.5, max = 40, step = 0.5, unit = 'm', kind = 'laptop' },
    { 'devices.idle.live.range.pc', 'screens', 'number', name = 'live_range_pc', section = 'live', min = 0.5, max = 40, step = 0.5, unit = 'm', kind = 'pc' },
    { 'devices.idle.live.range.terminal', 'screens', 'number', name = 'live_range_terminal', section = 'live', min = 0.5, max = 40, step = 0.5, unit = 'm', kind = 'terminal' },
    { 'devices.idle.dark.enabled', 'screens', 'bool', name = 'far_faces', section = 'live' },
    { 'devices.idle.dark.max', 'screens', 'number', name = 'far_faces_max', section = 'live', min = 1, max = 16, whole = true },
    { 'os.apps', 'os', 'set', name = 'os_apps', section = 'os_apps', options = 'apps' },
    { 'os.preinstalled', 'os', 'set', name = 'os_preinstalled', section = 'os_apps', options = 'removable', optional = true },
    { 'limits.appWindows', 'os', 'number', name = 'app_windows', section = 'os_apps', min = 1, max = 8, whole = true },
    { 'os.notes.max', 'os', 'number', name = 'notes_max', section = 'notes', min = 1, max = 200, whole = true },
    { 'os.notes.title', 'os', 'number', name = 'notes_title', section = 'notes', min = 10, max = 120, whole = true },
    { 'os.notes.body', 'os', 'number', name = 'notes_body', section = 'notes', min = 100, max = 10000, step = 100, whole = true },
    { 'os.notes.trash', 'os', 'number', name = 'notes_trash', section = 'notes', min = 0, max = 100, whole = true },
    { 'os.notes.trashDays', 'os', 'number', name = 'notes_trash_days', section = 'notes', min = 1, max = 365, whole = true, unit = 'days', restart = true },
    { 'os.photos.links', 'os', 'bool', name = 'photo_links', section = 'photos' },
    { 'os.photos.hosts', 'os', 'hosts', name = 'photo_hosts', section = 'photos', optional = true },
    { 'os.photos.max', 'os', 'number', name = 'photos_max', section = 'photos', min = 1, max = 100, whole = true },
    { 'os.photos.name', 'os', 'number', name = 'photo_name', section = 'photos', min = 10, max = 60, whole = true },
    { 'os.password.min', 'os', 'number', name = 'password_min', section = 'password', min = 1, max = 16, whole = true },
    { 'os.password.max', 'os', 'number', name = 'password_max', section = 'password', min = 4, max = 64, whole = true },
    { 'os.password.tries', 'os', 'number', name = 'password_tries', section = 'password', min = 1, max = 20, whole = true },
    { 'os.password.waitSeconds', 'os', 'number', name = 'password_wait', section = 'password', min = 5, max = 600, whole = true, unit = 's' },
    { 'tablet.look.enabled', 'tablet', 'bool', name = 'tablet_look', section = 'tablet_look' },
    { 'tablet.look.others', 'tablet', 'bool', name = 'tablet_look_others', section = 'tablet_look' },
    { 'tablet.look.range', 'tablet', 'number', name = 'tablet_look_range', section = 'tablet_look', min = 1, max = 50, step = 1, unit = 'm' },
    { 'tablet.light.enabled', 'tablet', 'bool', name = 'tablet_light', section = 'tablet_light' },
    { 'tablet.light.intensity', 'tablet', 'number', name = 'tablet_light_strength', section = 'tablet_light', min = 0.05, max = 2, step = 0.05 },
    { 'tablet.light.max', 'tablet', 'number', name = 'tablet_light_max', section = 'tablet_light', min = 1, max = 8, whole = true },
    { 'tablet.light.viewRange', 'tablet', 'number', name = 'tablet_light_range', section = 'tablet_light', min = 1, max = 50, step = 1, unit = 'm' },
    { 'notifications.popup.enabled', 'notifications', 'bool', name = 'notice_popup', section = 'notice_popup' },
    { 'notifications.popup.position', 'notifications', 'select', name = 'notice_position', section = 'notice_popup', options = { 'top_right', 'top_center', 'top_left', 'bottom_right' } },
    { 'notifications.popup.seconds', 'notifications', 'number', name = 'notice_seconds', section = 'notice_popup', min = 3, max = 20, whole = true, unit = 's' },
    { 'notifications.sound', 'notifications', 'bool', name = 'notice_sound', section = 'notice_popup' },
    { 'notifications.tablet.enabled', 'notifications', 'bool', name = 'notice_tablet', section = 'notice_tablet' },
    { 'notifications.screen.enabled', 'notifications', 'bool', name = 'notice_screen', section = 'notice_screen' },
    { 'notifications.screen.blink', 'notifications', 'bool', name = 'notice_blink', section = 'notice_screen' },
    { 'notifications.keepDays', 'notifications', 'number', name = 'notice_keep_days', section = 'notice_keep', min = 1, max = 60, whole = true, unit = 'days' },
    { 'notifications.keep', 'notifications', 'number', name = 'notice_keep', section = 'notice_keep', min = 5, max = 50, whole = true },
    { 'devices.mirror.enabled', 'nearby', 'bool', name = 'mirror', section = 'watching' },
    { 'devices.mirror.maxWatchers', 'nearby', 'number', name = 'mirror_watchers', section = 'watching', min = 1, max = 64, whole = true },
    { 'devices.mirror.pointerHz', 'nearby', 'number', name = 'mirror_pointer', section = 'watching', min = 1, max = 20, whole = true },
    { 'marker.color', 'placing', 'colour', name = 'marker_colour', section = 'markers', optional = true },
    { 'marker.scale', 'placing', 'number', name = 'marker_scale', section = 'markers', min = 0.5, max = 2, step = 0.1 },
    { 'marker.motion', 'placing', 'bool', name = 'marker_motion', section = 'markers' },
    { 'marker.draw', 'placing', 'select', name = 'marker_draw', section = 'markers', options = { 'poly', 'marker' } },
    { 'devices.flatSlope', 'placing', 'number', name = 'flat_slope', section = 'surfaces', min = 0, max = 10, step = 0.5, unit = 'deg' },
    { 'devices.maxSlope', 'placing', 'number', name = 'max_slope', section = 'surfaces', min = 5, max = 45, step = 1, unit = 'deg' },
    { 'admin.placeRange', 'placing', 'number', name = 'place_range', section = 'surfaces', min = 10, max = 200, step = 5, unit = 'm' },
    { 'signal.enabled', 'signal', 'bool', name = 'signal' },
    { 'signal.homeLoss', 'signal', 'number', name = 'signal_home_loss', min = 0, max = 3, whole = true },
    { 'signal.radius', 'signal', 'number', name = 'signal_radius', min = 50, max = 5000, step = 50, unit = 'm' },
    { 'signal.strength', 'signal', 'number', name = 'signal_strength', min = 1, max = 100, whole = true, unit = 'percent' },
    { 'signal.streamDistance', 'signal', 'number', name = 'signal_stream', min = 50, max = 1000, step = 10, unit = 'm' },
    { 'admin.tokenIdleMinutes', 'advanced', 'number', name = 'token_minutes', section = 'connection', min = 5, max = 240, whole = true, unit = 'min' },
    { 'devices.session.walkMs', 'advanced', 'number', name = 'walk_ms', section = 'walking', min = 1000, max = 15000, step = 500, whole = true, unit = 'ms' },
    { 'devices.session.damage', 'advanced', 'number', name = 'walk_damage', section = 'walking', min = 0, max = 100, whole = true },
    { 'devices.session.cancelReach', 'advanced', 'number', name = 'cancel_reach', section = 'walking', min = 0.5, max = 3, step = 0.1, unit = 'm' },
    { 'devices.session.darkGlass', 'advanced', 'bool', name = 'dark_glass', section = 'walking' },
    { 'devices.session.clearTimecycle', 'advanced', 'bool', name = 'clear_timecycle', section = 'walking' },
    { 'tablet.activityHoldMs', 'advanced', 'number', name = 'tablet_hold_ms', section = 'tablet_hold', min = 500, max = 10000, step = 100, whole = true, unit = 'ms' },
    { 'tablet.useMinimumMs', 'advanced', 'number', name = 'tablet_use_ms', section = 'tablet_hold', min = 0, max = 10000, step = 100, whole = true, unit = 'ms' },
    { 'tablet.range', 'advanced', 'number', name = 'tablet_range', section = 'tablet_hold', min = 10, max = 200, step = 5, unit = 'm' },
}

ConfigRules.CHECKS = {
    { low = 'config.os.password.min', high = 'config.os.password.max', strict = false },
    { low = 'config.devices.flatSlope', high = 'config.devices.maxSlope', strict = false },
}

local SETS = {
    apps = function() return Util.copy(OsRules.APPS) end,
    removable = function()
        local list = {}

        for _, id in ipairs(OsRules.APPS) do
            if not OsRules.FIXED[id] then
                list[#list + 1] = id
            end
        end

        return list
    end,
}

local function split(path)
    local parts = {}

    for part in path:gmatch('[^%.]+') do
        parts[#parts + 1] = part
    end

    return parts
end

function ConfigRules.raw(path, root)
    local node = root or Config

    for _, part in ipairs(split(path)) do
        if type(node) ~= 'table' then return nil end

        node = node[part]
    end

    return node
end

local function write(path, value)
    local parts = split(path)
    local node = Config

    for index = 1, #parts - 1 do
        if type(node[parts[index]]) ~= 'table' then
            node[parts[index]] = {}
        end

        node = node[parts[index]]
    end

    node[parts[#parts]] = value
end

function ConfigRules.options(entry)
    if type(entry.options) == 'string' then
        return SETS[entry.options]()
    end

    return entry.options and Util.copy(entry.options) or nil
end

local function toField(entry, value)
    if entry[3] == 'set' then
        local list = {}

        for _, id in ipairs(ConfigRules.options(entry)) do
            if type(value) == 'table' and value[id] == true then
                list[#list + 1] = id
            end
        end

        return list
    end

    if entry[3] == 'colour' then
        return type(value) == 'string' and (BrandRules.colour(value) or '') or ''
    end

    return Util.copy(value)
end

local function toConfig(entry, value)
    if entry[3] == 'set' then
        local map = {}

        for _, id in ipairs(value) do
            map[id] = true
        end

        if entry.options == 'apps' then
            for _, id in ipairs(ConfigRules.options(entry)) do
                map[id] = map[id] == true
            end
        end

        return map
    end

    return Util.copy(value)
end

local function stepped(value, entry)
    if entry.step and not entry.whole then
        value = Util.round(Util.round(value / entry.step, 0) * entry.step, 3)
    end

    return value
end

function ConfigRules.value(entry, value)
    local kind = entry[3]

    if kind == 'bool' then
        if type(value) ~= 'boolean' then return nil end

        return value
    end

    if kind == 'number' then
        if entry.whole then
            return Util.integer(value, entry.min, entry.max)
        end

        local number = Util.number(value, entry.min, entry.max)

        return number and stepped(number, entry) or nil
    end

    if kind == 'select' then
        return Util.contains(ConfigRules.options(entry), value) and value or nil
    end

    if kind == 'colour' then
        if value == '' or value == false then
            return entry.optional and '' or nil
        end

        return BrandRules.colour(value)
    end

    if kind == 'hosts' then
        return OsRules.hosts(value)
    end

    if kind == 'set' then
        if type(value) ~= 'table' then return nil end

        local options, seen, list = ConfigRules.options(entry), {}, {}

        for _, id in ipairs(value) do
            if not Util.contains(options, id) then return nil end

            seen[id] = true
        end

        for _, id in ipairs(options) do
            if seen[id] then
                list[#list + 1] = id
            end
        end

        return list
    end

    return nil
end

local function effective(diff, path)
    if type(diff) == 'table' and diff[path] ~= nil then
        return diff[path]
    end

    return ConfigRules.shipped[path]
end

local function checked(diff)
    for _, rule in ipairs(ConfigRules.CHECKS) do
        local low = effective(diff, rule.low:sub(8))
        local high = effective(diff, rule.high:sub(8))

        if type(low) == 'number' and type(high) == 'number' and (low > high or (rule.strict and low == high)) then
            return false, rule.low
        end
    end

    return true
end

function ConfigRules.clean(patch)
    if type(patch) ~= 'table' then
        return nil, 'invalid_settings', 'config'
    end

    local diff = {}

    for path, value in pairs(patch) do
        local entry = type(path) == 'string' and ConfigRules.byPath[path] or nil

        if not entry then
            return nil, 'invalid_settings', 'config.' .. tostring(path)
        end

        local clean = ConfigRules.value(entry, value)

        if clean == nil then
            return nil, 'invalid_settings', 'config.' .. path
        end

        if not Util.same(clean, ConfigRules.shipped[path]) then
            diff[path] = clean
        end
    end

    local ok, field = checked(diff)

    if not ok then
        return nil, 'invalid_settings', field
    end

    return diff
end

local function forget(entry, value)
    if entry[3] ~= 'set' or type(value) ~= 'table' then
        return value
    end

    local options, kept = ConfigRules.options(entry), {}

    for _, id in ipairs(value) do
        if Util.contains(options, id) or not OsRules.FIXED[id] then
            kept[#kept + 1] = id
        end
    end

    return kept
end

function ConfigRules.load(stored)
    local diff, problems = {}, {}

    if type(stored) ~= 'table' then
        return diff, problems
    end

    for _, path in ipairs(Util.keys(stored)) do
        local entry = type(path) == 'string' and ConfigRules.byPath[path] or nil
        local clean = nil

        if entry then
            clean = ConfigRules.value(entry, forget(entry, stored[path]))
        end

        if clean == nil then
            problems[#problems + 1] = ('config.%s: the saved value is ignored, the config value is used'):format(tostring(path))
        elseif not Util.same(clean, ConfigRules.shipped[path]) then
            diff[path] = clean
        end
    end

    local ok, field = checked(diff)

    if not ok then
        problems[#problems + 1] = ('%s: the saved values do not fit together and are ignored'):format(field)

        return {}, problems
    end

    return diff, problems
end

function ConfigRules.apply(diff)
    local changed = {}

    for _, entry in ipairs(ConfigRules.LIST) do
        local path = entry[1]
        local value = effective(diff, path)

        if not Util.same(toField(entry, ConfigRules.raw(path)), value) then
            write(path, toConfig(entry, value))
            changed[#changed + 1] = path
        end
    end

    return changed
end

function ConfigRules.compact(diff)
    if type(diff) ~= 'table' or next(diff) == nil then
        return false
    end

    return diff
end

local function labelOf(entry)
    return 'ui_cfg_' .. entry.name
end

local function view(entry, value)
    local path = entry[1]

    return {
        id = path,
        path = path,
        kind = entry[3],
        group = entry[2],
        section = entry.section or entry[2],
        label = labelOf(entry),
        help = labelOf(entry) .. '_help',
        value = Util.copy(value),
        default = Util.copy(ConfigRules.shipped[path]),
        shipped = Util.copy(ConfigRules.shipped[path]),
        min = entry.min,
        max = entry.max,
        step = entry.step or (entry.whole and 1 or nil),
        whole = entry.whole == true or nil,
        unit = entry.unit,
        options = ConfigRules.options(entry),
        optional = entry.optional == true or nil,
        restart = entry.restart == true or nil,
        needsRestart = entry.restart == true or nil,
        maxItems = entry[3] == 'hosts' and OsRules.HOSTS_MAX or nil,
        kindOf = entry.kind,
    }
end

function ConfigRules.fields(diff)
    local list = {}

    for _, entry in ipairs(ConfigRules.LIST) do
        list[#list + 1] = view(entry, effective(diff, entry[1]))
    end

    return list
end

function ConfigRules.view(diff)
    return {
        fields = ConfigRules.fields(diff),
        saved = Util.copy(type(diff) == 'table' and diff or {}),
        checks = ConfigRules.checks(),
    }
end

function ConfigRules.checks()
    return Util.copy(ConfigRules.CHECKS)
end

function ConfigRules.snapshot()
    ConfigRules.byPath, ConfigRules.shipped = {}, {}

    for _, entry in ipairs(ConfigRules.LIST) do
        ConfigRules.byPath[entry[1]] = entry
        ConfigRules.shipped[entry[1]] = toField(entry, ConfigRules.raw(entry[1]))
    end
end

ConfigRules.snapshot()

return ConfigRules
