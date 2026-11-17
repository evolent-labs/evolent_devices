local Config = require 'config'
local Util = require 'shared.util'
local ScreenRules = require 'shared.screen'
local AccessRules = require 'shared.access'

local AppRules = {}

AppRules.API = 1
AppRules.PROTOCOL = 1
AppRules.HOOKS = { 'canOpen', 'onOpen', 'onClose', 'watchData', 'notices', 'look' }
AppRules.FIELD_TYPES = { select = true, text = true, number = true, toggle = true }
AppRules.TERMINAL_ASPECT = 8 / 3
AppRules.MAX_FIELDS = 8
AppRules.MAX_SETTINGS = 16
AppRules.DESCRIPTION = 120
AppRules.ABOUT = 400
AppRules.CAN = 6
AppRules.CAN_TEXT = 80
AppRules.PICTURES = 5
AppRules.PICTURE_PATH = 128
AppRules.CATEGORIES = { 'dealership', 'work', 'tools', 'fun' }
AppRules.CAN_ICONS = { 'check', 'wifi', 'offline', 'eye', 'cover', 'bell', 'key', 'lock', 'shield', 'devices', 'pin', 'disk' }
AppRules.MEDIA = {
    cover = { minWidth = 1200, maxWidth = 3840, minHeight = 500, maxHeight = 1600, minRatio = 2, maxRatio = 3, bytes = 2097152 },
    picture = { minWidth = 640, maxWidth = 3840, minHeight = 400, maxHeight = 2400, minRatio = 1, maxRatio = 2.5, bytes = 2097152 },
}

local PICTURE_TYPES = { webp = 'webp', png = 'png', jpg = 'jpg', jpeg = 'jpg' }
local JPEG_FRAMES = { [0xC0] = true, [0xC1] = true, [0xC2] = true, [0xC3] = true, [0xC5] = true, [0xC6] = true, [0xC7] = true, [0xC9] = true, [0xCA] = true, [0xCB] = true, [0xCD] = true, [0xCE] = true, [0xCF] = true }
local CATEGORY, CAN_ICON = {}, {}

for _, id in ipairs(AppRules.CATEGORIES) do
    CATEGORY[id] = true
end

for _, id in ipairs(AppRules.CAN_ICONS) do
    CAN_ICON[id] = true
end

function AppRules.isCategory(value)
    return CATEGORY[value] == true
end

function AppRules.defaultCategory(resource)
    if type(resource) == 'string' and resource:lower():find('dealer', 1, true) then
        return 'dealership'
    end

    return 'tools'
end

function AppRules.isLink(value)
    return type(value) == 'string' and value:sub(1, 8) == 'https://' and ScreenRules ~= nil and ScreenRules.url(value) ~= nil
end

function AppRules.isColour(value)
    return type(value) == 'string' and value:match('^#%x%x%x%x%x%x$') ~= nil
end

function AppRules.isLocalPicture(value)
    if type(value) ~= 'string' then return false end
    if #value > AppRules.PICTURE_PATH or not value:match('^[%w_%-%./]+$') then return false end
    if value:find('..', 1, true) or value:sub(1, 1) == '/' or value:find('//', 1, true) then return false end

    local ending = value:match('%.(%a+)$')

    return ending ~= nil and PICTURE_TYPES[ending:lower()] ~= nil
end

function AppRules.isPicture(value)
    if type(value) ~= 'string' then return false end
    if value:sub(1, 8) == 'https://' then return AppRules.isLink(value) end

    return AppRules.isLocalPicture(value)
end

local function jpegSize(data)
    local at = 3

    while at + 8 <= #data do
        if data:byte(at) ~= 0xFF then return nil end

        local marker = data:byte(at + 1)

        if marker == 0xFF then
            at = at + 1
        elseif marker == 0x01 or (marker >= 0xD0 and marker <= 0xD8) then
            at = at + 2
        elseif marker == 0xD9 or marker == 0xDA then
            return nil
        elseif JPEG_FRAMES[marker] then
            local height, width = string.unpack('>I2I2', data, at + 5)

            return width, height
        else
            local length = string.unpack('>I2', data, at + 2)

            if length < 2 then return nil end

            at = at + 2 + length
        end
    end

    return nil
end

function AppRules.imageSize(data)
    if type(data) ~= 'string' then return nil end

    if #data >= 24 and data:sub(1, 8) == '\137PNG\r\n\26\n' and data:sub(13, 16) == 'IHDR' then
        local width, height = string.unpack('>I4I4', data, 17)

        return 'png', width, height
    end

    if #data >= 30 and data:sub(1, 4) == 'RIFF' and data:sub(9, 12) == 'WEBP' then
        local chunk = data:sub(13, 16)

        if chunk == 'VP8 ' and data:sub(24, 26) == '\157\1\42' then
            local width, height = string.unpack('<I2I2', data, 27)

            return 'webp', width & 0x3FFF, height & 0x3FFF
        end

        if chunk == 'VP8L' and data:byte(21) == 0x2F then
            local bits = string.unpack('<I4', data, 22)

            return 'webp', (bits & 0x3FFF) + 1, ((bits >> 14) & 0x3FFF) + 1
        end

        if chunk == 'VP8X' then
            local width, height = string.unpack('<I3I3', data, 25)

            return 'webp', width + 1, height + 1
        end

        return nil
    end

    if #data >= 12 and data:sub(1, 2) == '\255\216' then
        local width, height = jpegSize(data)

        if width then
            return 'jpg', width, height
        end
    end

    return nil
end

function AppRules.mediaFault(kind, path, data)
    local rule = AppRules.MEDIA[kind]

    if not rule or type(path) ~= 'string' or type(data) ~= 'string' then
        return 'missing'
    end

    if #data > rule.bytes then
        return 'bytes'
    end

    local format, width, height = AppRules.imageSize(data)
    local ending = path:match('%.(%a+)$')

    if not format or not ending or PICTURE_TYPES[ending:lower()] ~= format then
        return 'format'
    end

    if width < rule.minWidth or width > rule.maxWidth or height < rule.minHeight or height > rule.maxHeight then
        return 'size', width, height
    end

    local ratio = width / height

    if ratio < rule.minRatio * 0.99 or ratio > rule.maxRatio * 1.01 then
        return 'shape', width, height
    end

    return nil
end

local function pictures(list)
    if list == nil then
        return {}
    end

    if type(list) ~= 'table' or #list > AppRules.PICTURES or next(list) ~= nil and #list == 0 then return nil end

    local clean = {}

    for index, value in ipairs(list) do
        if not AppRules.isPicture(value) then return nil end

        clean[index] = value
    end

    return clean
end

local function abilities(list)
    if list == nil then
        return {}
    end

    if type(list) ~= 'table' or #list > AppRules.CAN or next(list) ~= nil and #list == 0 then return nil end

    local clean = {}

    for index, entry in ipairs(list) do
        local icon, text = 'check', entry

        if type(entry) == 'table' then
            icon, text = entry.icon == nil and 'check' or entry.icon, entry.text
        end

        text = Util.label(text, AppRules.CAN_TEXT)

        if not text or not CAN_ICON[icon] then return nil end

        clean[index] = { icon = icon, text = text }
    end

    return clean
end

function AppRules.isId(id)
    return type(id) == 'string' and #id >= 2 and #id <= 32 and id:match('^[a-z][a-z0-9_]+$') ~= nil
end

function AppRules.isCallable(value)
    return type(value) == 'function' or (type(value) == 'table' and value.__cfx_functionReference ~= nil)
end

function AppRules.isPage(page)
    return type(page) == 'string' and #page <= 128 and page:match('^[%w_%-%./]+%.html$') ~= nil
        and not page:find('..', 1, true) and page:sub(1, 1) ~= '/' and not page:find('//', 1, true)
end

function AppRules.isIcon(icon)
    if type(icon) ~= 'table' then return false end
    if type(icon.path) ~= 'string' or #icon.path < 1 or #icon.path > 4096 then return false end
    if not icon.path:match('^[MmLlHhVvCcSsQqTtAaZz%d%.,%-%s]+$') then return false end

    return type(icon.color) == 'string' and icon.color:match('^#%x%x%x%x%x%x$') ~= nil
end

local function size(value, minWidth, minHeight)
    if type(value) ~= 'table' then return nil end

    local width, height = Util.integer(value.width, minWidth, 3840), Util.integer(value.height, minHeight, 2160)

    if not width or not height then return nil end

    return { width = width, height = height }
end

local function settingKey(key)
    return type(key) == 'string' and #key <= 32 and key:match('^[a-z][%w_]*$') ~= nil
end

local function fields(list)
    if list == nil then
        return {}
    end

    if type(list) ~= 'table' or #list > AppRules.MAX_FIELDS then return nil end

    local clean, seen = {}, {}

    for index, field in ipairs(list) do
        if type(field) ~= 'table' or not settingKey(field.key) or seen[field.key] then return nil end
        if not AppRules.FIELD_TYPES[field.type] then return nil end

        local label = Util.label(field.label, 40)

        if not label then return nil end

        seen[field.key] = true

        local entry = { key = field.key, type = field.type, label = label }

        if field.type == 'select' then
            if AppRules.isCallable(field.options) then
                entry.options = field.options
            elseif type(field.options) == 'table' then
                entry.options = {}

                for position, option in ipairs(field.options) do
                    if type(option) ~= 'table' then return nil end
                    if type(option.value) ~= 'string' and not Util.isFinite(option.value) then return nil end

                    local text = Util.cleanText(option.label or tostring(option.value), 64)

                    if not text or Util.hasForbidden(text) then return nil end

                    entry.options[position] = { value = option.value, label = text }
                end
            else
                return nil
            end
        elseif field.type == 'number' then
            entry.min = field.min ~= nil and Util.number(field.min) or nil
            entry.max = field.max ~= nil and Util.number(field.max) or nil

            if (field.min ~= nil and not entry.min) or (field.max ~= nil and not entry.max) then return nil end
            if entry.min and entry.max and entry.min > entry.max then return nil end
        elseif field.type == 'text' then
            entry.maxLength = Util.integer(field.maxLength or 64, 1, 64)

            if not entry.maxLength then return nil end
        end

        if field.default ~= nil then
            if type(field.default) ~= 'string' and type(field.default) ~= 'boolean' and not Util.isFinite(field.default) then return nil end

            entry.default = field.default
        end

        clean[index] = entry
    end

    return clean
end

local function defaults(value, kinds)
    if value == nil then
        return { kinds = {}, preinstalled = {}, playerDevices = false }
    end

    if type(value) ~= 'table' then return nil end

    local clean = { kinds = {}, preinstalled = {}, playerDevices = value.playerDevices == true }

    if value.preinstalled == true then
        for kind in pairs(kinds) do
            clean.preinstalled[kind] = kind ~= 'terminal'
        end
    elseif type(value.preinstalled) == 'table' then
        for kind, on in pairs(value.preinstalled) do
            if not kinds[kind] or kind == 'terminal' or type(on) ~= 'boolean' then return nil end

            clean.preinstalled[kind] = on
        end
    elseif value.preinstalled ~= nil and value.preinstalled ~= false then
        return nil
    end

    if value.kinds ~= nil then
        if type(value.kinds) ~= 'table' then return nil end

        for kind, on in pairs(value.kinds) do
            if not kinds[kind] or type(on) ~= 'boolean' then return nil end

            clean.kinds[kind] = on
        end
    end

    if value.access ~= nil then
        local access = AccessRules.normalize(value.access, {
            modes = { 'rules' },
            types = { 'job', 'gang', 'citizen', 'provider' },
        })

        if not access then return nil end

        clean.access = access
    end

    return clean
end

function AppRules.validate(def)
    local OsRules = require 'shared.os'

    if type(def) ~= 'table' then
        return nil, 'invalid_definition'
    end

    if math.type(def.api) ~= 'integer' then
        return nil, 'invalid_api'
    end

    if def.api > AppRules.API then
        return nil, 'unsupported_api'
    end

    if def.api < 1 then
        return nil, 'invalid_api'
    end

    if not AppRules.isId(def.id) then
        return nil, 'invalid_id'
    end

    local label = Util.label(def.label, 32)

    if not label then
        return nil, 'invalid_label'
    end

    if type(def.version) ~= 'string' or #def.version < 1 or #def.version > 32 then
        return nil, 'invalid_version'
    end

    if not def.version:match('^[%w%.%-%+]+$') then
        return nil, 'invalid_version'
    end

    if not AppRules.isIcon(def.icon) then
        return nil, 'invalid_icon'
    end

    if not AppRules.isPage(def.page) then
        return nil, 'invalid_page'
    end

    if type(def.kinds) ~= 'table' or #def.kinds < 1 or #def.kinds > 4 then
        return nil, 'invalid_kinds'
    end

    local kinds, terminal = {}, false

    for _, kind in ipairs(def.kinds) do
        if kinds[kind] or not (OsRules.hasOs(kind) or kind == 'terminal') then
            return nil, 'invalid_kinds'
        end

        kinds[kind] = true

        if kind == 'terminal' then
            terminal = true
        end
    end

    if terminal and #def.kinds > 1 then
        return nil, 'invalid_kinds'
    end

    local canvas = size(def.canvas, 160, 120)

    if not canvas then
        return nil, 'invalid_canvas'
    end

    if terminal and math.abs(canvas.width / canvas.height / AppRules.TERMINAL_ASPECT - 1) > 0.015 then
        return nil, 'canvas_aspect'
    end

    local window = {}

    if def.window ~= nil then
        if type(def.window) ~= 'table' then
            return nil, 'invalid_window'
        end

        for kind, value in pairs(def.window) do
            if not kinds[kind] or kind == 'terminal' then
                return nil, 'invalid_window'
            end

            window[kind] = size(value, 160, 120)

            if not window[kind] then
                return nil, 'invalid_window'
            end
        end
    end

    local watch = def.watch == nil and 'cover' or def.watch

    if watch ~= 'cover' and watch ~= 'state' then
        return nil, 'invalid_watch'
    end

    if def.network ~= nil and type(def.network) ~= 'boolean' then
        return nil, 'invalid_network'
    end

    local description = nil

    if def.description ~= nil then
        description = Util.cleanText(def.description, AppRules.DESCRIPTION)

        if not description or Util.hasForbidden(description) then
            return nil, 'invalid_description'
        end
    end

    if def.category ~= nil and not AppRules.isCategory(def.category) then
        return nil, 'invalid_category'
    end

    local about = nil

    if def.about ~= nil then
        about = Util.cleanText(def.about, AppRules.ABOUT)

        if not about or Util.hasForbidden(about) then
            return nil, 'invalid_about'
        end
    end

    local shots = pictures(def.pictures)

    if not shots then
        return nil, 'invalid_pictures'
    end

    if def.cover ~= nil and not AppRules.isLocalPicture(def.cover) then
        return nil, 'invalid_cover'
    end

    if def.accent ~= nil and not AppRules.isColour(def.accent) then
        return nil, 'invalid_accent'
    end

    local can = abilities(def.can)

    if not can then
        return nil, 'invalid_can'
    end

    local weight = nil

    if def.size ~= nil then
        weight = Util.integer(def.size, 1, 9999)

        if not weight then
            return nil, 'invalid_app_size'
        end
    end

    local settings = fields(def.settings)

    if not settings then
        return nil, 'invalid_settings_fields'
    end

    local starting = defaults(def.defaults, kinds)

    if not starting then
        return nil, 'invalid_defaults'
    end

    local clean = {
        api = def.api,
        id = def.id,
        label = label,
        description = description,
        category = def.category,
        about = about,
        pictures = shots,
        cover = def.cover,
        accent = def.accent and def.accent:upper() or nil,
        can = can,
        size = weight,
        version = def.version,
        icon = { path = def.icon.path, color = def.icon.color },
        page = def.page,
        kinds = Util.copy(def.kinds),
        terminal = terminal,
        canvas = canvas,
        window = window,
        watch = watch,
        network = def.network ~= false,
        settings = settings,
        defaults = starting,
    }

    for _, hook in ipairs(AppRules.HOOKS) do
        if def[hook] ~= nil and not AppRules.isCallable(def[hook]) then
            return nil, 'invalid_hook'
        end

        clean[hook] = def[hook]
    end

    return clean
end

function AppRules.cleanValues(values)
    if values == nil then
        return {}
    end

    if type(values) ~= 'table' then return nil end

    local clean, count = {}, 0

    for key, value in pairs(values) do
        if not settingKey(key) then return nil end

        count = count + 1

        if count > AppRules.MAX_SETTINGS then return nil end

        if type(value) == 'string' then
            if #value > 64 then return nil end

            clean[key] = value
        elseif type(value) == 'boolean' or Util.isFinite(value) then
            clean[key] = value
        else
            return nil
        end
    end

    return clean
end

function AppRules.checkValues(values, fieldList, optionsOf)
    local clean = {}

    for _, field in ipairs(fieldList or {}) do
        local value = values[field.key]

        if value ~= nil then
            if field.type == 'toggle' then
                if type(value) ~= 'boolean' then
                    return nil, field.key
                end
            elseif field.type == 'number' then
                if not Util.isFinite(value) or (field.min and value < field.min) then
                    return nil, field.key
                end

                if field.max and value > field.max then
                    return nil, field.key
                end
            elseif field.type == 'text' then
                value = Util.cleanText(value, field.maxLength or 64)

                if not value then
                    return nil, field.key
                end
            else
                local found = false

                for _, option in ipairs(optionsOf(field) or {}) do
                    if option.value == value then
                        found = true
                        break
                    end
                end

                if not found then
                    return nil, field.key
                end
            end

            clean[field.key] = value
        end
    end

    return clean
end

function AppRules.normalizeDeviceApps(apps, checkEntry)
    local maxApps = Config.limits.appsPerDevice or 16

    if apps == nil then
        return { order = {}, entries = {} }
    end

    if type(apps) ~= 'table' then
        return nil, 'invalid_apps'
    end

    local order, seen = {}, {}

    if apps.order ~= nil then
        if type(apps.order) ~= 'table' or #apps.order > maxApps * 2 then
            return nil, 'invalid_apps'
        end

        for _, id in ipairs(apps.order) do
            if not AppRules.isId(id) then
                return nil, 'invalid_apps'
            end

            if not seen[id] then
                seen[id] = true
                order[#order + 1] = id
            end
        end
    end

    local entries, count = {}, 0

    if apps.entries ~= nil then
        if type(apps.entries) ~= 'table' then
            return nil, 'invalid_apps'
        end

        local ids = {}

        for id in pairs(apps.entries) do
            if not AppRules.isId(id) then
                return nil, 'invalid_apps'
            end

            ids[#ids + 1] = id
        end

        table.sort(ids)

        for _, id in ipairs(ids) do
            local entry = apps.entries[id]

            if type(entry) ~= 'table' then
                return nil, 'invalid_apps'
            end

            count = count + 1

            if count > maxApps then
                return nil, 'too_many_apps'
            end

            local clean = { on = entry.on == true }

            if entry.access ~= nil and entry.access ~= false then
                local access, reason = AccessRules.normalize(entry.access, { modes = { 'rules' } })

                if not access then
                    return nil, reason
                end

                clean.access = access
            end

            if entry.watch ~= nil and entry.watch ~= false and entry.watch ~= 'app' then
                if entry.watch ~= 'cover' then
                    return nil, 'invalid_apps'
                end

                clean.watch = 'cover'
            end

            local values = AppRules.cleanValues(entry.settings)

            if not values then
                return nil, 'invalid_app_settings', id
            end

            clean.settings = values

            if checkEntry then
                local checked, reason = checkEntry(id, clean)

                if not checked then
                    return nil, reason, id
                end

                clean = checked
            end

            entries[id] = clean

            if not seen[id] then
                seen[id] = true
                order[#order + 1] = id
            end
        end
    end

    local result = { order = order, entries = entries }

    if apps.watch == 'cover' then
        result.watch = 'cover'
    end

    if apps.only ~= nil and apps.only ~= false and apps.only ~= '' then
        if not AppRules.isId(apps.only) then
            return nil, 'invalid_only_app'
        end

        result.only = apps.only
    end

    return result
end

return AppRules
