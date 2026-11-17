local Config = require 'config'
local Util = require 'shared.util'
local ScreenRules = require 'shared.screen'
local AccessRules = require 'shared.access'
local AppRules = require 'shared.apps'
local ConfigRules = require 'shared.config_rules'
local Audit = require 'server.audit'
local Registry = require 'server.registry'
local Spaces = require 'server.spaces'
local Access = require 'server.access'
local Apps = require 'server.apps'

local Settings = {}

local trusting = false

local ITEM_FIELDS = {
    'enabled',
    'place',
    'perPlayer',
    'where',
    'homeKeysOnly',
    'tableMin',
    'tableMax',
    'pickup',
    'onRemove',
    'startAccess',
    'startApps',
}

local TABLET_FIELDS = { 'enabled', 'use', 'apps', 'blocked' }

local function itemDefaults(kind)
    local source = Config.items[kind] or {}
    local fields = kind == 'tablet' and TABLET_FIELDS or ITEM_FIELDS
    local result = {}

    for _, name in ipairs(fields) do
        result[name] = Util.copy(source[name])
    end

    return result
end

function Settings.defaults()
    local kinds = {}

    for _, kind in ipairs(Config.kindOrder) do
        local spec = Config.kinds[kind]

        kinds[kind] = { enabled = spec.enabled ~= false, max = spec.max or 0 }

        if kind ~= 'tablet' then
            kinds[kind].startAccess = Util.copy(spec.startAccess)
        end

        if Config.items[kind] then
            kinds[kind].item = itemDefaults(kind)
        end
    end

    return { general = Util.copy(Config.general), kinds = kinds, zones = {}, config = {} }
end

local function boolean(value)
    if type(value) ~= 'boolean' then return nil end

    return value
end

local function oneOf(...)
    local allowed = { ... }

    return function(value)
        for _, option in ipairs(allowed) do
            if value == option then
                return value
            end
        end

        return nil
    end
end

local function integer(low, high)
    return function(value) return Util.integer(value, low, high) end
end

local function number(low, high)
    return function(value) return Util.number(value, low, high) end
end

local function access(options)
    return function(value, current)
        local settings = { modes = options.modes, types = options.types, template = true, current = current }
        local clean, reason

        if trusting then
            clean, reason = AccessRules.normalize(value, settings)
        else
            clean, reason = Access.validate(value, nil, settings)
        end

        if not clean then
            return nil, reason
        end

        return clean
    end
end

local function appIds(value)
    if type(value) ~= 'table' or #value > Config.limits.appsPerDevice then return nil end

    local clean, seen = {}, {}

    for _, id in ipairs(value) do
        if not AppRules.isId(id) then return nil end

        if not seen[id] then
            seen[id] = true
            clean[#clean + 1] = id
        end
    end

    return clean
end

local function serials(value)
    if type(value) ~= 'table' or #value > Config.limits.blockedSerials then return nil end

    local clean, seen = {}, {}

    for _, serial in ipairs(value) do
        if type(serial) ~= 'string' then return nil end

        serial = serial:upper():match('^%s*(.-)%s*$')

        if not serial:match('^EV[A-Z]%-%x%x%x%x%x%x$') then return nil end

        if not seen[serial] then
            seen[serial] = true
            clean[#clean + 1] = serial
        end
    end

    return clean
end

local function deviceApps(value, current)
    local clean, reason

    if trusting then
        clean, reason = AppRules.normalizeDeviceApps(value)
    else
        clean, reason = Apps.normalizeDeviceApps(value, current, { kind = 'tablet' })
    end

    if not clean then
        return nil, reason
    end

    return clean
end

local GENERAL = {
    adminsOpenAny = boolean,
    auditDays = integer(7, 365),
    removedDays = integer(1, 365),
    twinRadius = number(5, 60),
    watchRange = number(4, 30),
    forceCover = boolean,
}

local SESSION = {
    idleMinutes = integer(0, 240),
    lockMinutes = integer(0, 120),
    leaseSeconds = integer(5, 120),
    heartbeatSeconds = integer(2, 30),
}

local SOUND = {
    enabled = boolean,
    volume = integer(0, 100),
    nearby = integer(0, 100),
    range = number(3, 10),
}

local function displayField(key)
    return function(value) return ScreenRules.displayField(key, value) end
end

local DISPLAY = {}

for _, key in ipairs(ScreenRules.DISPLAY_KEYS) do
    DISPLAY[key] = displayField(key)
end

local KIND = {
    enabled = boolean,
    max = integer(0, 500),
    startAccess = access({}),
}

local ITEM = {
    enabled = boolean,
    place = access({ modes = { 'everyone', 'rules' }, types = { 'job', 'gang', 'citizen', 'provider' } }),
    perPlayer = integer(0, 20),
    where = oneOf('anywhere', 'homes'),
    homeKeysOnly = boolean,
    tableMin = number(0, 3),
    tableMax = number(0, 3),
    pickup = oneOf('owner', 'manage'),
    onRemove = oneOf('return', 'delete'),
    startAccess = access({}),
    startApps = appIds,
}

local TABLET = {
    enabled = boolean,
    use = access({ modes = { 'everyone', 'rules' }, types = { 'job', 'gang', 'citizen', 'provider' } }),
    apps = deviceApps,
    blocked = serials,
}

local function applyFields(target, patch, validators, path)
    if type(patch) ~= 'table' then
        return nil, 'invalid_settings', path
    end

    for key, value in pairs(patch) do
        local check = validators[key]

        if not check then
            return nil, 'invalid_settings', path .. '.' .. tostring(key)
        end

        local clean, reason = check(value, target[key])

        if clean == nil then
            return nil, reason or 'invalid_settings', path .. '.' .. key
        end

        target[key] = clean
    end

    return target
end

function Settings.apply(current, patch)
    if type(patch) ~= 'table' then
        return nil, 'invalid_settings', ''
    end

    local result = Util.copy(current)

    for key in pairs(patch) do
        if key ~= 'general' and key ~= 'kinds' and key ~= 'config' then
            return nil, 'invalid_settings', key
        end
    end

    if patch.config ~= nil then
        local diff, reason, path = ConfigRules.clean(patch.config)

        if not diff then
            return nil, reason, path
        end

        result.config = diff
    end

    if patch.general ~= nil then
        local general = Util.copy(patch.general)

        if type(general) ~= 'table' then
            return nil, 'invalid_settings', 'general'
        end

        local session, sound, display = general.session, general.sound, general.display

        general.session, general.sound, general.display = nil, nil, nil

        local ok, reason, path = applyFields(result.general, general, GENERAL, 'general')

        if not ok then
            return nil, reason, path
        end

        if session ~= nil then
            ok, reason, path = applyFields(result.general.session, session, SESSION, 'general.session')

            if not ok then
                return nil, reason, path
            end
        end

        if sound ~= nil then
            ok, reason, path = applyFields(result.general.sound, sound, SOUND, 'general.sound')

            if not ok then
                return nil, reason, path
            end
        end

        if display ~= nil then
            ok, reason, path = applyFields(result.general.display, display, DISPLAY, 'general.display')

            if not ok then
                return nil, reason, path
            end

            local screen = result.general.display

            if screen.night and screen.nightFrom == screen.nightTo then
                return nil, 'screen_night', 'general.display.nightTo'
            end
        end

        local timings = result.general.session

        if timings.heartbeatSeconds * 2 > timings.leaseSeconds then
            return nil, 'invalid_settings', 'general.session.heartbeatSeconds'
        end
    end

    if patch.kinds ~= nil then
        if type(patch.kinds) ~= 'table' then
            return nil, 'invalid_settings', 'kinds'
        end

        for kind, kindPatch in pairs(patch.kinds) do
            local target = result.kinds[kind]

            if not target or type(kindPatch) ~= 'table' then
                return nil, 'invalid_settings', 'kinds.' .. tostring(kind)
            end

            local fields = Util.copy(kindPatch)
            local item = fields.item

            fields.item = nil

            if kind == 'tablet' and fields.startAccess ~= nil then
                return nil, 'invalid_settings', 'kinds.tablet.startAccess'
            end

            local ok, reason, path = applyFields(target, fields, KIND, 'kinds.' .. kind)

            if not ok then
                return nil, reason, path
            end

            if item ~= nil then
                if not target.item then
                    return nil, 'invalid_settings', 'kinds.' .. kind .. '.item'
                end

                ok, reason, path = applyFields(
                    target.item,
                    item,
                    kind == 'tablet' and TABLET or ITEM,
                    'kinds.' .. kind .. '.item'
                )

                if not ok then
                    return nil, reason, path
                end

                if target.item.tableMin and target.item.tableMax and target.item.tableMin >= target.item.tableMax then
                    return nil, 'invalid_settings', 'kinds.' .. kind .. '.item.tableMin'
                end
            end
        end
    end

    return result
end

function Settings.load(stored)
    local result = Settings.defaults()
    local problems = {}

    local patch = {
        general = type(stored.general) == 'table' and stored.general or nil,
        kinds = type(stored.kinds) == 'table' and stored.kinds or nil,
    }

    for key, value in pairs(patch) do
        trusting = true

        local ok, merged, reason, path = pcall(Settings.apply, result, { [key] = value })

        trusting = false

        if not ok then
            merged, reason = nil, tostring(merged)
        end

        if merged then
            result = merged
        else
            problems[#problems + 1] = ('%s (%s): the saved value is ignored, the config value is used'):format(
                path or key,
                reason
            )
        end
    end

    local diff, overlay = ConfigRules.load(stored.config)

    result.config = diff

    for _, problem in ipairs(overlay) do
        problems[#problems + 1] = problem
    end

    if type(stored.zones) == 'table' then
        local zones, reason = Settings.normalizeZones(stored.zones)

        if zones then
            result.zones = zones
        else
            problems[#problems + 1] = ('zones (%s): the saved zones are ignored'):format(reason)
        end
    end

    return result, problems
end

function Settings.normalizeZones(list)
    if type(list) ~= 'table' or #list > Config.limits.zones then
        return nil, 'too_many_zones'
    end

    local clean, used, highest = {}, {}, 0

    for _, zone in ipairs(list) do
        local id = type(zone) == 'table' and Util.integer(zone.id, 1, 1000000) or nil

        if id and not used[id] then
            used[id] = true
            highest = math.max(highest, id)
        end
    end

    local taken = {}

    for index, zone in ipairs(list) do
        if type(zone) ~= 'table' then
            return nil, 'invalid_zone', index
        end

        local position = Util.position({ x = zone.x, y = zone.y, z = zone.z })
        local radius = Util.number(zone.radius, 2, 200)
        local label = Util.cleanText(zone.label or '', Config.limits.labelLength)
        local space = type(zone.space) == 'string' and zone.space:match('^[bp]%d+$') and zone.space or nil

        if not position or not radius or not label or not space then
            return nil, 'invalid_zone', index
        end

        local id = Util.integer(zone.id, 1, 1000000)

        if not id or taken[id] then
            highest = highest + 1
            id = highest
        end

        taken[id] = true

        clean[index] = {
            id = id,
            label = label,
            x = position.x,
            y = position.y,
            z = position.z,
            radius = Util.round(radius, 2),
            space = space,
        }
    end

    return clean
end

local AUDIT_CHANGES = 40

local function changeWalk(before, after, path, out)
    local keys = {}

    for key in pairs(type(before) == 'table' and before or {}) do
        keys[key] = true
    end

    for key in pairs(type(after) == 'table' and after or {}) do
        keys[key] = true
    end

    local names = Util.keys(keys)

    table.sort(names, function(a, b) return tostring(a) < tostring(b) end)

    for _, key in ipairs(names) do
        local old, new = before and before[key], after and after[key]
        local where = path == '' and tostring(key) or path .. '.' .. tostring(key)

        if not Util.same(old, new) then
            if type(old) == 'table' and type(new) == 'table' and #old == 0 and #new == 0 and key ~= 'startAccess' and key ~= 'place' and key ~= 'use' and key ~= 'apps' then
                changeWalk(old, new, where, out)
            elseif #out < AUDIT_CHANGES then
                local entry = { path = where }

                if type(old) ~= 'table' and type(new) ~= 'table' then
                    entry.from, entry.to = old, new
                end

                out[#out + 1] = entry
            end
        end
    end
end

local function configChanges(before, after, out)
    local paths = {}

    for path in pairs(type(before) == 'table' and before or {}) do
        paths[path] = true
    end

    for path in pairs(type(after) == 'table' and after or {}) do
        paths[path] = true
    end

    for _, path in ipairs(Util.keys(paths)) do
        local entry = ConfigRules.byPath[path]
        local old, new = before and before[path], after and after[path]

        if old == nil then old = ConfigRules.shipped[path] end
        if new == nil then new = ConfigRules.shipped[path] end

        if entry and not Util.same(old, new) and #out < AUDIT_CHANGES then
            local change = { path = 'config.' .. path, label = 'ui_cfg_' .. entry.name, kind = entry.kind }

            if type(old) ~= 'table' and type(new) ~= 'table' then
                change.from, change.to = old, new
            end

            out[#out + 1] = change
        end
    end
end

function Settings.changes(before, after)
    local out = {}

    changeWalk(
        { general = before.general, kinds = before.kinds },
        { general = after.general, kinds = after.kinds },
        '',
        out
    )

    configChanges(before.config, after.config, out)

    return out
end

local function zoneText(zone)
    local label = zone.label ~= '' and zone.label or ('#' .. zone.id)

    return Util.clip(('%s (%s)'):format(label, Spaces.describe(zone.space).text), 60)
end

function Settings.zoneChanges(before, after)
    return Audit.listChanges(before, after, zoneText)
end

function Settings.zoneAt(position, space)
    for _, zone in ipairs(Registry.settings.zones) do
        if zone.space == space and Util.distance({ x = zone.x, y = zone.y }, { x = position.x, y = position.y }) <= zone.radius then
            return zone
        end
    end

    return nil
end

function Settings.kindEnabled(kind)
    local entry = Registry.settings.kinds[kind]

    return entry ~= nil and entry.enabled == true
end

return Settings
