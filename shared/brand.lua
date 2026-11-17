local Config = require 'config'
local Util = require 'shared.util'

local BrandRules = {
    KEY = 'evdev:brand',
    WALLS_KEY = 'evdev:walls',
    DEFAULT_ACCENT = '#C3FF00',
    DEFAULT_WALLPAPER = 'evolent',
    EVOLENT_FILE = 'web/build/wallpapers/evolent.webp',
    MAX_PICTURE = 98304,
    MAX_LINK = 512,
    MAX_NAME = 40,
    MAX_WALLS = 24,
    WALL_ID_LENGTH = 32,
    WALL_TYPES = { webp = true, jpg = true, jpeg = true, png = true },
    WALLPAPERS = { 'evolent' },
    IDLE_KINDS = { 'laptop', 'pc', 'terminal' },
    walls = nil,
}

function BrandRules.colour(value)
    value = type(value) == 'string' and value or ''

    if value:match('^#%x%x%x%x%x%x$') then
        return value:upper()
    end

    if value:match('^#%x%x%x$') then
        return ('#' .. value:sub(2):gsub('%x', '%0%0')):upper()
    end

    return nil
end

function BrandRules.picture(value)
    if value == nil or value == false or value == '' then
        return ''
    end

    if type(value) ~= 'string' then return nil end

    if #value <= BrandRules.MAX_LINK and value:match('^https://[^%s"\'<>\\]+$') then
        return value
    end

    if #value <= BrandRules.MAX_PICTURE and value:match('^data:image/[a-z]+;base64,[%w%+/=]+$') then
        return value
    end

    return nil
end

function BrandRules.name(value)
    if value == nil or value == false then
        return ''
    end

    if type(value) ~= 'string' or #value > BrandRules.MAX_NAME * 4 then return nil end

    local name = value:gsub('%s+', ' '):match('^ ?(.-) ?$')
    local length = utf8.len(name)

    if not length or length > BrandRules.MAX_NAME or name:find('[<>%z\1-\31\127]') then return nil end

    return name
end

function BrandRules.wallShape(value)
    if type(value) ~= 'string' or #value > BrandRules.WALL_ID_LENGTH or not value:find('^[a-z][a-z0-9_]*$') then return nil end

    return value
end

function BrandRules.wallFile(value)
    if type(value) ~= 'string' or #value > 160 then return nil end

    local extension = value:match('^web/build/wallpapers/[%w_%-]+%.(%a+)$')

    if not extension or not BrandRules.WALL_TYPES[extension:lower()] then return nil end

    return value
end

function BrandRules.cleanWallpapers(list, exists)
    local clean, problems, seen = {}, {}, { [BrandRules.DEFAULT_WALLPAPER] = true }

    if list == nil or list == false then
        return clean, problems
    end

    if type(list) ~= 'table' then
        return clean, { 'Config.wallpapers must be a list of { id, name, file }' }
    end

    for index, entry in ipairs(list) do
        local where = ('Config.wallpapers[%d]'):format(index)
        local id = type(entry) == 'table' and BrandRules.wallShape(entry.id) or nil
        local file = type(entry) == 'table' and BrandRules.wallFile(entry.file) or nil
        local name = type(entry) == 'table' and BrandRules.name(entry.name) or nil

        if #clean >= BrandRules.MAX_WALLS then
            problems[#problems + 1] = ('%s and the rest are left out: at most %d own pictures'):format(where, BrandRules.MAX_WALLS)
            break
        elseif type(entry) ~= 'table' then
            problems[#problems + 1] = where .. ' must be { id = ..., name = ..., file = ... }'
        elseif not id then
            problems[#problems + 1] = ('%s needs an id of lower-case letters, digits and _ (at most %d)'):format(where, BrandRules.WALL_ID_LENGTH)
        elseif seen[id] then
            problems[#problems + 1] = id == BrandRules.DEFAULT_WALLPAPER and (where .. ': evolent is the built-in wallpaper, pick another id') or (where .. ' repeats the id ' .. id)
        elseif not file then
            problems[#problems + 1] = where .. '.file must be a .webp, .jpg, .jpeg or .png file under web/build/wallpapers/'
        elseif exists and not exists(file) then
            problems[#problems + 1] = ('%s: %s is not in the resource, the evolent wallpaper shows instead'):format(where, file)
        else
            seen[id] = true
            clean[#clean + 1] = { id = id, name = (name and name ~= '') and name or id, file = file }
        end
    end

    return clean, problems
end

function BrandRules.useWallpapers(list)
    BrandRules.walls = (BrandRules.cleanWallpapers(list))

    return BrandRules.walls
end

function BrandRules.ownWallpapers()
    if BrandRules.walls == nil then
        return BrandRules.useWallpapers(GlobalState[BrandRules.WALLS_KEY])
    end

    return BrandRules.walls
end

local function own(id)
    for _, entry in ipairs(BrandRules.ownWallpapers()) do
        if entry.id == id then
            return entry
        end
    end

    return nil
end

function BrandRules.ownId(value)
    return type(value) == 'string' and own(value) ~= nil and value or nil
end

function BrandRules.wallpaperId(value)
    if type(value) ~= 'string' then return nil end

    return (own(value) or Util.contains(BrandRules.WALLPAPERS, value)) and value or nil
end

function BrandRules.wallpaperOr(value)
    return BrandRules.wallpaperId(value) or (BrandRules.wallShape(value) and BrandRules.DEFAULT_WALLPAPER) or nil
end

function BrandRules.wallpaperOf(value)
    local entry = type(value) == 'string' and own(value) or nil

    if entry then
        return { id = entry.id, name = entry.name, file = entry.file, own = true }
    end

    return { id = BrandRules.DEFAULT_WALLPAPER, file = BrandRules.EVOLENT_FILE, own = false }
end

function BrandRules.wallpaperIds()
    local list = Util.copy(BrandRules.WALLPAPERS)

    for _, entry in ipairs(BrandRules.ownWallpapers()) do
        list[#list + 1] = entry.id
    end

    return list
end

function BrandRules.wallpaperList()
    local list = {}

    for index, entry in ipairs(BrandRules.ownWallpapers()) do
        list[index] = { id = entry.id, name = entry.name, file = entry.file }
    end

    return list
end

function BrandRules.wallpaper(value)
    if value == nil or value == '' then
        return BrandRules.DEFAULT_WALLPAPER
    end

    return BrandRules.wallpaperId(value)
end

function BrandRules.idle(value, lenient)
    local out = {}

    for _, kind in ipairs(BrandRules.IDLE_KINDS) do
        out[kind] = ''
    end

    if type(value) ~= 'table' then
        return (lenient or value == nil or value == false) and out or nil
    end

    for _, kind in ipairs(BrandRules.IDLE_KINDS) do
        local id = value[kind]

        if id ~= nil and id ~= false and id ~= '' then
            if BrandRules.ownId(id) then
                out[kind] = id
            elseif not lenient then
                return nil
            end
        end
    end

    return out
end

function BrandRules.idleOf(kind, brand)
    local idle = type(brand) == 'table' and type(brand.idle) == 'table' and brand.idle[kind] or nil
    local entry = type(idle) == 'string' and idle ~= '' and own(idle) or nil

    if not entry then return nil end

    return { id = entry.id, name = entry.name, file = entry.file, own = true }
end

function BrandRules.check(input, lenient)
    if type(input) ~= 'table' then
        return nil, 'invalid_brand_colour'
    end

    local accent = BrandRules.colour(input.accent)

    if not accent then
        return nil, 'invalid_brand_colour'
    end

    local logo = BrandRules.picture(input.logo)

    if not logo then
        return nil, 'invalid_brand_logo'
    end

    local name = BrandRules.name(input.name)

    if not name then
        return nil, 'invalid_brand_name'
    end

    local wallpaper = BrandRules.wallpaper(input.wallpaper) or (lenient and BrandRules.wallpaperOr(input.wallpaper)) or nil

    if not wallpaper then
        return nil, 'invalid_brand_wallpaper'
    end

    local idle = nil

    if input.idle ~= nil and input.idle ~= false then
        idle = BrandRules.idle(input.idle, lenient)

        if not idle then
            return nil, 'invalid_brand_idle'
        end
    end

    return { accent = accent, logo = logo, name = name, wallpaper = wallpaper, idle = idle }
end

local function source(value)
    if type(value) ~= 'string' or value == '' then
        return ''
    end

    if value:sub(1, 8) == 'https://' or value:sub(1, 11) == 'data:image/' then
        return BrandRules.picture(value) or ''
    end

    if not value:find('^[%w_/%-%.]+$') or value:find('..', 1, true) then
        return ''
    end

    return ('https://cfx-nui-%s/%s'):format(GetCurrentResourceName(), (value:gsub('^/+', '')))
end

function BrandRules.defaults()
    local config = type(Config.brand) == 'table' and Config.brand or {}

    return {
        accent = BrandRules.colour(config.accent) or BrandRules.DEFAULT_ACCENT,
        logo = source(config.logo),
        name = BrandRules.name(config.name) or '',
        wallpaper = BrandRules.wallpaper(config.wallpaper) or BrandRules.DEFAULT_WALLPAPER,
        idle = BrandRules.idle(config.idle, true),
    }
end

function BrandRules.saved(value)
    if value == nil then
        value = GlobalState[BrandRules.KEY]
    end

    return type(value) == 'table' and BrandRules.check(value, true) or nil
end

function BrandRules.current(value)
    local brand = BrandRules.defaults()
    local saved = BrandRules.saved(value)

    brand.custom = saved ~= nil

    if saved then
        brand.accent, brand.wallpaper = saved.accent, saved.wallpaper

        if saved.logo ~= '' then
            brand.logo = saved.logo
        end

        if saved.name ~= '' then
            brand.name = saved.name
        end

        if saved.idle then
            brand.idle = saved.idle
        end
    end

    return brand
end

function BrandRules.view(value)
    local brand = BrandRules.current(value)

    return { accent = brand.accent, logo = brand.logo, name = brand.name, wallpaper = brand.wallpaper, idle = brand.idle, walls = BrandRules.wallpaperList() }
end

function BrandRules.light(value)
    local brand = BrandRules.current(value)

    return { accent = brand.accent, name = brand.name, idle = brand.idle }
end

return BrandRules
