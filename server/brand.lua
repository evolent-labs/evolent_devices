local Config = require 'config'
local Util = require 'shared.util'
local BrandRules = require 'shared.brand'
local Store = require 'server.store'
local Audit = require 'server.audit'

local Brand = {}

Brand.OTHERS = {
    dealership = 'evd:brand',
    garage = 'evolentGarageBrand',
}

local function publish(brand)
    GlobalState[BrandRules.KEY] = brand or false
end

local function exists(file)
    local data = LoadResourceFile(GetCurrentResourceName(), file)

    return type(data) == 'string' and #data > 0
end

function Brand.loadWallpapers()
    local list, problems = BrandRules.cleanWallpapers(Config.wallpapers, exists)

    BrandRules.walls = list
    GlobalState[BrandRules.WALLS_KEY] = list

    return problems
end

local function goneIdle(saved, brand)
    local gone, kinds = {}, {}

    if type(saved.idle) ~= 'table' or not brand.idle then
        return gone, kinds
    end

    for _, kind in ipairs(BrandRules.IDLE_KINDS) do
        local id = saved.idle[kind]

        if id ~= nil and id ~= false and id ~= '' and brand.idle[kind] ~= id then
            id = tostring(id)

            if not kinds[id] then
                kinds[id] = {}
                gone[#gone + 1] = id
            end

            kinds[id][#kinds[id] + 1] = kind
        end
    end

    return gone, kinds
end

local function configIdle(problems)
    local idle = type(Config.brand) == 'table' and Config.brand.idle or nil

    if idle == nil then return end

    if type(idle) ~= 'table' then
        problems[#problems + 1] = "Config.brand.idle must be { laptop = '', pc = '', terminal = '' }, the evolent picture is used"

        return
    end

    for _, kind in ipairs(BrandRules.IDLE_KINDS) do
        local id = idle[kind]

        if id ~= nil and id ~= false and id ~= '' and not BrandRules.ownId(id) then
            problems[#problems + 1] = ('Config.brand.idle.%s: %s is not an id of Config.wallpapers, the evolent picture is used'):format(kind, tostring(id))
        end
    end
end

function Brand.load(stored)
    local problems = Brand.loadWallpapers()
    local saved = type(stored) == 'table' and stored.brand or nil

    configIdle(problems)

    if type(saved) ~= 'table' then
        publish(nil)

        return problems
    end

    local brand, reason = BrandRules.check(saved, true)

    if not brand then
        problems[#problems + 1] = ('the saved brand is ignored (%s), config.lua is used'):format(reason)
    else
        if brand.wallpaper ~= saved.wallpaper and not BrandRules.wallpaperId(saved.wallpaper) then
            problems[#problems + 1] = ('the saved wallpaper %s is gone, the evolent wallpaper is used'):format(tostring(saved.wallpaper))
        end

        local gone, kinds = goneIdle(saved, brand)

        for _, id in ipairs(gone) do
            problems[#problems + 1] = ('the saved own picture %s is gone, the evolent picture is used on idle screens (%s)'):format(id, table.concat(kinds[id], ', '))
        end
    end

    publish(brand)

    return problems
end

function Brand.saved()
    local saved = GlobalState[BrandRules.KEY]

    return type(saved) == 'table' and Util.copy(saved) or false
end

function Brand.others()
    local list = {}

    for name, key in pairs(Brand.OTHERS) do
        local value = GlobalState[key]
        local accent = type(value) == 'table' and BrandRules.colour(value.accent) or nil

        if accent then
            list[name] = { accent = accent }
        end
    end

    return list
end

function Brand.view()
    return {
        saved = Brand.saved(),
        defaults = BrandRules.defaults(),
        current = BrandRules.view(),
        limits = { picture = BrandRules.MAX_PICTURE, name = BrandRules.MAX_NAME },
        wallpapers = BrandRules.wallpaperIds(),
        others = Brand.others(),
    }
end

function Brand.save(actor, input)
    local brand, reason = BrandRules.check(input)

    if not brand then
        return Util.fail(reason)
    end

    Store.saveSetting('brand', brand)
    publish(brand)
    Audit.write(actor, 'brand', nil, { accent = brand.accent, logo = brand.logo ~= '', name = brand.name, wallpaper = brand.wallpaper, idle = brand.idle })
    Util.log(('brand %s saved by %s'):format(brand.accent, actor and actor.name or 'the console'))

    return Util.ok(Brand.view())
end

function Brand.reset(actor)
    Store.saveSetting('brand', false)
    publish(nil)
    Audit.write(actor, 'brand', nil, { reset = true })
    Util.log(('brand reset to config.lua by %s'):format(actor and actor.name or 'the console'))

    return Util.ok(Brand.view())
end

return Brand
