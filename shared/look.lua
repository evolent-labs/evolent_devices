local Config = require 'config'
local Util = require 'shared.util'
local BrandRules = require 'shared.brand'

local LookRules = {
    DARKEST = 8,
    FLOOR = 242,
    STRIPS = { terminal = { texture = 'evd_terminal_strip', size = 4 } },
}

function LookRules.clean(value)
    if type(value) ~= 'table' then return nil end

    local accent = BrandRules.colour(value.accent)

    if not accent then return nil end

    return { accent = accent, neon = BrandRules.colour(value.neon), light = BrandRules.colour(value.light) }
end

function LookRules.stamp(look)
    if type(look) ~= 'table' then return '' end

    return table.concat({ look.accent or '', look.neon or '', look.light or '' }, '|')
end

function LookRules.lit(hex)
    local colour = BrandRules.colour(hex)

    if not colour then return nil end

    local r, g, b = tonumber(colour:sub(2, 3), 16), tonumber(colour:sub(4, 5), 16), tonumber(colour:sub(6, 7), 16)
    local peak = math.max(r, g, b)

    if peak < LookRules.DARKEST then
        return { LookRules.FLOOR, LookRules.FLOOR, LookRules.FLOOR }
    end

    local scale = 255 / peak

    return { math.floor(r * scale), math.floor(g * scale), math.floor(b * scale) }
end

local function lookOf(record)
    return type(record) == 'table' and type(record.look) == 'table' and record.look or nil
end

function LookRules.accent(record, brand)
    local look = lookOf(record)

    if look and BrandRules.colour(look.accent) then
        return BrandRules.colour(look.accent)
    end

    return type(brand) == 'table' and BrandRules.colour(brand.accent) or BrandRules.DEFAULT_ACCENT
end

function LookRules.neon(record, brand)
    local look = lookOf(record)

    return LookRules.lit(look and look.neon or LookRules.accent(record, brand))
end

function LookRules.light(record)
    local look = lookOf(record)

    return look and LookRules.lit(look.light) or nil
end

function LookRules.neutral(record, brand)
    return LookRules.accent(record, brand) ~= BrandRules.DEFAULT_ACCENT
end

function LookRules.strip(kind)
    local spec = type(kind) == 'string' and Config.kinds[kind] or nil

    if type(spec) ~= 'table' or spec.neon == false then return nil end

    local strip = type(spec.neon) == 'table' and spec.neon or LookRules.STRIPS[kind]

    if type(strip) ~= 'table' or type(strip.texture) ~= 'string' or not strip.texture:find('^[%w_]+$') then return nil end

    return { texture = strip.texture, size = Util.integer(strip.size, 1, 64) or 4 }
end

return LookRules
