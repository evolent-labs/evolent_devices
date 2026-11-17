local Util = {}

local FORBIDDEN = { '\194\183', '\226\128\147', '\226\128\148' }

function Util.copy(value)
    if type(value) ~= 'table' then
        return value
    end

    local result = {}

    for key, item in pairs(value) do
        result[key] = Util.copy(item)
    end

    return result
end

function Util.count(list)
    local total = 0

    for _ in pairs(list) do
        total = total + 1
    end

    return total
end

function Util.contains(list, value)
    for index = 1, #list do
        if list[index] == value then return true end
    end

    return false
end

function Util.keys(map)
    local list = {}

    for key in pairs(map) do
        list[#list + 1] = key
    end

    table.sort(list, function(a, b) return tostring(a) < tostring(b) end)

    return list
end

function Util.yes(value)
    return value == true or value == 1
end

function Util.isFinite(value)
    return type(value) == 'number' and value == value and value > -math.huge and value < math.huge
end

function Util.integer(value, low, high)
    if not Util.isFinite(value) or value % 1 ~= 0 then return nil end
    if (low and value < low) or (high and value > high) then return nil end

    return math.tointeger(value) or value
end

function Util.number(value, low, high)
    if not Util.isFinite(value) then return nil end
    if (low and value < low) or (high and value > high) then return nil end

    return value + 0.0
end

function Util.round(value, decimals)
    local scale = 10 ^ (decimals or 0)

    return math.floor(value * scale + 0.5) / scale
end

function Util.hasForbidden(text)
    if type(text) ~= 'string' then return false end

    for _, sequence in ipairs(FORBIDDEN) do
        if text:find(sequence, 1, true) then return true end
    end

    return false
end

function Util.textLength(text)
    return utf8.len(text) or #text
end

function Util.cleanText(value, maxLength)
    if type(value) ~= 'string' then return nil end
    if not utf8.len(value) then return nil end

    local text = value:gsub('[%c]', ' '):gsub('%s+', ' '):match('^%s*(.-)%s*$')

    if Util.textLength(text) > (maxLength or 64) then return nil end

    return text
end

function Util.label(value, maxLength)
    local text = Util.cleanText(value, maxLength)

    if not text or text == '' or Util.hasForbidden(text) then return nil end

    return text
end

function Util.name(value)
    if type(value) ~= 'string' then return nil end

    local text = value:lower():match('^%s*(.-)%s*$')

    if #text < 1 or #text > 40 or not text:match('^[a-z0-9_]+$') then return nil end

    return text
end

function Util.isCid(value)
    return type(value) == 'string' and #value >= 1 and #value <= 60 and value:match('^[%w:]+$') ~= nil
end

function Util.position(value)
    if type(value) ~= 'table' and type(value) ~= 'vector3' and type(value) ~= 'vector4' then return nil end

    local x, y, z = tonumber(value.x), tonumber(value.y), tonumber(value.z)
    local h = tonumber(value.h or value.w or value.heading or 0.0)

    if not (Util.isFinite(x) and Util.isFinite(y) and Util.isFinite(z) and Util.isFinite(h)) then return nil end
    if math.abs(x) > 12000 or math.abs(y) > 12000 or z < -500 or z > 3000 then return nil end

    return { x = Util.round(x, 3), y = Util.round(y, 3), z = Util.round(z, 3), h = Util.round(h % 360, 2) }
end

function Util.distance(a, b)
    local dx, dy, dz = a.x - b.x, a.y - b.y, (a.z or 0.0) - (b.z or 0.0)

    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

function Util.hex(length)
    local parts = {}

    for index = 1, length do
        parts[index] = ('%x'):format(math.random(0, 15))
    end

    return table.concat(parts)
end

function Util.merge(base, over)
    if type(base) ~= 'table' or type(over) ~= 'table' then
        if over == nil then
            return Util.copy(base)
        end

        return Util.copy(over)
    end

    local result = Util.copy(base)

    for key, value in pairs(over) do
        if type(value) == 'table' and type(result[key]) == 'table' and #value == 0 and next(value) ~= nil then
            result[key] = Util.merge(result[key], value)
        else
            result[key] = Util.copy(value)
        end
    end

    return result
end

function Util.same(a, b)
    if type(a) ~= 'table' or type(b) ~= 'table' then
        return a == b
    end

    for key, value in pairs(a) do
        if not Util.same(value, b[key]) then return false end
    end

    for key in pairs(b) do
        if a[key] == nil then return false end
    end

    return true
end

function Util.clip(text, maxLength)
    text = tostring(text or '')

    local length = utf8.len(text)

    if not length then
        return text:sub(1, maxLength)
    end

    if length <= maxLength then
        return text
    end

    return text:sub(1, utf8.offset(text, maxLength + 1) - 1) .. '...'
end

function Util.ok(data)
    return { ok = true, data = data }
end

function Util.fail(reason, data)
    return { ok = false, reason = reason, data = data }
end

function Util.log(message)
    print(('[evolent_devices] %s'):format(message))
end

return Util
