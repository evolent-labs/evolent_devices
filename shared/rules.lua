local Config = require 'config'
local Util = require 'shared.util'
local ScreenRules = require 'shared.screen'

local DeviceRules = {
    KEEP_RANGE = 2.0,
    PAGE_OFFSET = 0.002,
}

local CORNERS = { 'TL', 'TR', 'BL', 'BR' }
local PLACES = { surface = true, floor = true }
local MODES = { poly = true, world = true }
local VIEWS = { hud = true, world = true }
local ASPECT_TOLERANCE = 0.015
local VIEW_EDGE_PX, VIEW_EDGE_SHARE = 2.0, 0.005
local PAGE_MIN, PAGE_MAX, PAGE_SNAP = 0.75, 2.0, 2

local function sub(a, b)
    return { x = a.x - b.x, y = a.y - b.y, z = a.z - b.z }
end

local function add(a, b)
    return { x = a.x + b.x, y = a.y + b.y, z = a.z + b.z }
end

local function scale(a, f)
    return { x = a.x * f, y = a.y * f, z = a.z * f }
end

local function dot(a, b)
    return a.x * b.x + a.y * b.y + a.z * b.z
end

local function cross(a, b)
    return { x = a.y * b.z - a.z * b.y, y = a.z * b.x - a.x * b.z, z = a.x * b.y - a.y * b.x }
end

local function length(a)
    return math.sqrt(dot(a, a))
end

local function unit(a)
    local size = length(a)

    if size == 0 then
        return { x = 0.0, y = 0.0, z = 0.0 }
    end

    return scale(a, 1.0 / size)
end

DeviceRules.vector = { sub = sub, add = add, scale = scale, dot = dot, cross = cross, length = length, unit = unit }

local function finite(value)
    return Util.isFinite(value)
end

local function whole(value)
    return finite(value) and value > 0 and value % 1 == 0
end

local function point(value)
    return type(value) == 'table' and finite(value.x) and finite(value.y) and finite(value.z)
end

function DeviceRules.spec(kind)
    local spec = type(kind) == 'string' and Config.kinds[kind] or nil

    if type(spec) ~= 'table' or type(spec.screen) ~= 'table' then return nil end

    return spec
end

function DeviceRules.kinds()
    local list = {}

    for _, kind in ipairs(Config.kindOrder) do
        if DeviceRules.spec(kind) then
            list[#list + 1] = kind
        end
    end

    return list
end

function DeviceRules.variants(spec)
    return type(spec) == 'table' and type(spec.variants) == 'table' and spec.variants or {}
end

function DeviceRules.baseModel(spec)
    return DeviceRules.variants(spec)[1]
end

function DeviceRules.isVariant(spec, model)
    if type(model) ~= 'string' then return false end

    for _, name in ipairs(DeviceRules.variants(spec)) do
        if name == model then return true end
    end

    return false
end

function DeviceRules.variantOf(device)
    local spec = type(device) == 'table' and DeviceRules.spec(device.kind) or nil

    if not spec then return nil end

    if DeviceRules.isVariant(spec, device.variant) then
        return device.variant
    end

    if DeviceRules.isVariant(spec, device.model) then
        return device.model
    end

    return DeviceRules.baseModel(spec)
end

function DeviceRules.screenTexture(model)
    return model .. '_screen'
end

function DeviceRules.screenMode(spec, config)
    config = config or Config.devices

    local mode = type(spec) == 'table' and spec.screenMode or nil

    if mode == nil and type(config) == 'table' then
        mode = config.screenMode
    end

    return mode
end

function DeviceRules.userView(spec, config)
    config = config or Config.devices

    local view = type(spec) == 'table' and spec.userView or nil

    if view == nil and type(config) == 'table' then
        view = config.userView
    end

    return view or 'hud'
end

function DeviceRules.variantOrder(spec)
    local list, order = DeviceRules.variants(spec), {}

    for index = #list, 1, -1 do
        order[#order + 1] = list[index]
    end

    return order
end

function DeviceRules.spacingOk(list, position, kind, ignoreId)
    local own = DeviceRules.spec(kind)

    if not own then return false end

    for _, entry in ipairs(list or {}) do
        if entry.id == nil or entry.id ~= ignoreId then
            local other = Config.kinds[entry.kind]
            local needed = math.max(own.spacing or 0.0, other and other.spacing or 0.0)

            if length(sub(entry, position)) < needed then
                return false, entry
            end
        end
    end

    return true
end

function DeviceRules.toWorld(origin, heading, offset)
    local angle = math.rad(heading or 0.0)
    local c, s = math.cos(angle), math.sin(angle)

    return {
        x = origin.x + c * offset.x - s * offset.y,
        y = origin.y + s * offset.x + c * offset.y,
        z = origin.z + offset.z,
    }
end

function DeviceRules.screenCorners(spec)
    local screen = spec.screen

    if DeviceRules.screenMode(spec) ~= 'world' then
        return screen
    end

    local back = scale(DeviceRules.screenBasis(screen).normal, -DeviceRules.PAGE_OFFSET)
    local corners = {}

    for _, name in ipairs(CORNERS) do
        corners[name] = add(screen[name], back)
    end

    return corners
end

function DeviceRules.worldCorners(device, spec)
    local corners, screen = {}, DeviceRules.screenCorners(spec)

    for _, name in ipairs(CORNERS) do
        corners[name] = DeviceRules.toWorld(device, device.w, screen[name])
    end

    return corners
end

function DeviceRules.useSpot(device, spec)
    local spot = DeviceRules.toWorld(device, device.w, spec.use.offset)

    spot.w = device.w or 0.0

    return spot
end

function DeviceRules.animClips(anim)
    local list = {}

    if type(anim) ~= 'table' then
        return list
    end

    local function push(entry, role)
        local valid = type(entry) == 'table'

        list[#list + 1] = { dict = valid and entry.dict or nil, clip = valid and entry.clip or nil, role = role }
    end

    push(anim, 'base')

    if anim.tap ~= nil then
        push(anim.tap, 'tap')
    end

    if type(anim.idles) == 'table' then
        for _, entry in ipairs(anim.idles) do
            push(entry, 'idle')
        end
    end

    return list
end

function DeviceRules.animDicts(anim)
    local seen, list = {}, {}

    for _, entry in ipairs(DeviceRules.animClips(anim)) do
        if type(entry.dict) == 'string' and not seen[entry.dict] then
            seen[entry.dict] = true
            list[#list + 1] = entry.dict
        end
    end

    return list
end

function DeviceRules.typingPose(anim, surface, short)
    local best, cost = nil, math.huge

    for _, pose in ipairs(anim.poses) do
        local miss = math.abs(pose.height - surface) + math.max(0.0, short - pose.reach) * 2.0

        if miss < cost then
            best, cost = pose, miss
        end
    end

    return best
end

function DeviceRules.nextIdleAt(anim, now, roll)
    local every = type(anim) == 'table' and anim.idleEvery or nil

    if type(anim) ~= 'table' or type(anim.idles) ~= 'table' or #anim.idles == 0 or type(every) ~= 'table' then
        return nil
    end

    local low, high = tonumber(every[1]) or 0, tonumber(every[2]) or 0

    return now + low + math.floor((high - low) * (roll or 0.5))
end

function DeviceRules.checkAnim(anim)
    if type(anim) ~= 'table' then
        return 'anim needs dict and clip'
    end

    for _, entry in ipairs(DeviceRules.animClips(anim)) do
        if type(entry.dict) ~= 'string' or type(entry.clip) ~= 'string' then
            return entry.role == 'base' and 'anim needs dict and clip' or ('anim %s needs dict and clip'):format(entry.role)
        end

        if entry.dict ~= entry.dict:lower() or entry.clip ~= entry.clip:lower() then
            return 'anim names must be lower case'
        end
    end

    for _, pose in ipairs(type(anim.poses) == 'table' and anim.poses or {}) do
        if not finite(pose.height) or not finite(pose.reach) or not finite(pose.side) or not whole(pose.flag) then
            return 'anim poses need height, reach, side and flag'
        end
    end

    if (anim.flag ~= nil and not whole(anim.flag)) or (anim.oneShotFlag ~= nil and not whole(anim.oneShotFlag)) then
        return 'anim flag must be a whole number'
    end

    if anim.idles ~= nil then
        local every = anim.idleEvery

        if type(anim.idles) ~= 'table' or type(every) ~= 'table' or not finite(every[1]) or not finite(every[2]) or every[1] < 1000 or every[2] < every[1] then
            return 'anim idles need idleEvery { from, to } in ms, from 1000 up'
        end
    end

    if anim.tap ~= nil and anim.tapGap ~= nil and (not finite(anim.tapGap) or anim.tapGap < 0) then
        return 'anim tapGap must be 0 or more ms'
    end

    return nil
end

function DeviceRules.screenBasis(corners)
    local across, down = sub(corners.TR, corners.TL), sub(corners.BL, corners.TL)

    return {
        centre = add(corners.TL, scale(add(across, down), 0.5)),
        right = unit(across),
        up = unit(scale(down, -1.0)),
        normal = unit(cross(down, across)),
        width = length(across),
        height = length(down),
    }
end

function DeviceRules.cameraDistance(width, height, fov, aspect, fill)
    local half = math.tan(math.rad(fov) / 2.0)

    return math.max(height / (2.0 * half), width / (2.0 * half * aspect)) / (fill or 1.0)
end

function DeviceRules.cameraFov(width, height, distance, aspect, fill)
    return math.deg(2.0 * math.atan(math.max(height, width / aspect) / (2.0 * distance * (fill or 1.0))))
end

function DeviceRules.uvFromRay(origin, direction, corners)
    local basis = DeviceRules.screenBasis(corners)
    local facing = dot(direction, basis.normal)

    if facing >= 0 or dot(sub(origin, corners.TL), basis.normal) <= 0 then return nil end

    local distance = dot(sub(corners.TL, origin), basis.normal) / facing

    if distance < 0 then return nil end

    local hit = sub(add(origin, scale(direction, distance)), corners.TL)
    local across, down = sub(corners.TR, corners.TL), sub(corners.BL, corners.TL)

    return dot(hit, across) / dot(across, across), dot(hit, down) / dot(down, down)
end

function DeviceRules.slope(normal)
    if normal == nil or not finite(normal.x) or not finite(normal.y) or not finite(normal.z) then
        return 90.0
    end

    local size = length(normal)

    if size == 0 then
        return 90.0
    end

    return math.deg(math.acos(math.max(-1.0, math.min(1.0, normal.z / size))))
end

function DeviceRules.surface(normal, config)
    config = config or Config.devices

    local slope = DeviceRules.slope(normal)

    if slope > config.maxSlope then
        return 'steep', slope
    end

    if slope > config.flatSlope then
        return 'sloped', slope
    end

    return 'flat', slope
end

function DeviceRules.levelPoint(origin, direction, level, reach)
    if not finite(level) or math.abs(direction.z) < 0.0001 then return nil end

    local distance = (level - origin.z) / direction.z

    if distance <= 0 or distance > reach then return nil end

    return { x = origin.x + direction.x * distance, y = origin.y + direction.y * distance, z = level + 0.0 }
end

local CONTROL_KEYS = {
    Backspace = true,
    Delete = true,
    Enter = true,
    Tab = true,
    Escape = true,
    ArrowLeft = true,
    ArrowRight = true,
    ArrowUp = true,
    ArrowDown = true,
    Home = true,
    End = true,
}

local SHORTCUTS = { a = true, A = true, l = true, L = true }
local BUTTONS = { left = true, right = true }
local TEXT_BYTES = 256
local STATE_KEYS = 16
local STATE_KEY_BYTES = 24
local STATE_TEXT_BYTES = 512
local STATE_APPS = 4
local CLOCK_OFFSET = 14 * 3600

local function plain(text, limit)
    return type(text) == 'string' and #text <= limit and utf8.len(text) ~= nil and not text:find('[\0-\31\127]')
end

function DeviceRules.facing(corners, eye)
    local normal = cross(sub(corners.BL, corners.TL), sub(corners.TR, corners.TL))

    return dot(sub(eye, corners.TL), normal) > 0
end

function DeviceRules.pixel(px, py, size)
    if not finite(px) or not finite(py) or type(size) ~= 'table' then return nil end

    px, py = math.floor(px), math.floor(py)

    if px < 0 or py < 0 or px > size.width - 1 or py > size.height - 1 then return nil end

    return px, py
end

function DeviceRules.cleanPointer(u, v)
    if not finite(u) or not finite(v) or u < 0 or u > 1 or v < 0 or v > 1 then return nil end

    return math.floor(u * 1000 + 0.5) / 1000, math.floor(v * 1000 + 0.5) / 1000
end

function DeviceRules.cleanClock(clock)
    if type(clock) ~= 'table' or not finite(clock.now) or clock.now <= 0 then return nil end

    local offset = finite(clock.offset) and math.abs(clock.offset) <= CLOCK_OFFSET and math.floor(clock.offset + 0.5) or 0

    return { now = math.floor(clock.now), offset = offset }
end

function DeviceRules.pointerShare(px, py, size)
    return DeviceRules.cleanPointer(px / math.max(1, size.width - 1), py / math.max(1, size.height - 1))
end

function DeviceRules.screenMapping(projected, size)
    if type(projected) ~= 'table' or type(size) ~= 'table' then return nil end

    local values = {}

    for index, name in ipairs(CORNERS) do
        local corner = projected[name]

        if type(corner) ~= 'table' or not finite(corner.x) or not finite(corner.y) then return nil end

        values[index * 2 - 1], values[index * 2] = corner.x, corner.y
    end

    values[9], values[10] = size.width, size.height

    return values
end

function DeviceRules.mappingChanged(previous, values, tolerance)
    if type(previous) ~= 'table' or type(values) ~= 'table' then
        return type(previous) ~= type(values)
    end

    for index = 1, 10 do
        if math.abs(previous[index] - values[index]) > (tolerance or 0.0002) then return true end
    end

    return false
end

function DeviceRules.spriteRect(mapping, width, height)
    if type(mapping) ~= 'table' then return nil end

    for index = 1, 8 do
        if not finite(mapping[index]) then return nil end
    end

    local left, right = (mapping[1] + mapping[5]) / 2.0, (mapping[3] + mapping[7]) / 2.0
    local top, bottom = (mapping[2] + mapping[4]) / 2.0, (mapping[6] + mapping[8]) / 2.0

    if right <= left or bottom <= top or left < 0 or top < 0 or right > 1 or bottom > 1 then return nil end

    local dx = math.max(
        VIEW_EDGE_PX / ((finite(width) and width >= 1) and width or 1920),
        VIEW_EDGE_SHARE * (right - left)
    )

    local dy = math.max(
        VIEW_EDGE_PX / ((finite(height) and height >= 1) and height or 1080),
        VIEW_EDGE_SHARE * (bottom - top)
    )

    if math.abs(mapping[1] - left) > dx or math.abs(mapping[5] - left) > dx then return nil end
    if math.abs(mapping[3] - right) > dx or math.abs(mapping[7] - right) > dx then return nil end
    if math.abs(mapping[2] - top) > dy or math.abs(mapping[4] - top) > dy then return nil end
    if math.abs(mapping[6] - bottom) > dy or math.abs(mapping[8] - bottom) > dy then return nil end

    return {
        x = (left + right) / 2.0,
        y = (top + bottom) / 2.0,
        width = right - left,
        height = bottom - top,
        mapping = { left, top, right, top, left, bottom, right, bottom, mapping[9], mapping[10] },
    }
end

function DeviceRules.glassPixels(width, height, aspect, fill, screenWidth, screenHeight)
    if not finite(width) or not finite(height) or not finite(aspect) then return nil end
    if not finite(screenWidth) or not finite(screenHeight) then return nil end
    if width <= 0 or height <= 0 or aspect <= 0 or screenWidth < 1 or screenHeight < 1 then return nil end

    local share = ((finite(fill) and fill > 0) and fill or 1.0) / math.max(height, width / aspect)

    return width / aspect * share * screenWidth, height * share * screenHeight
end

local function pageRange(value, base)
    return value >= base * PAGE_MIN and value <= base * PAGE_MAX
end

function DeviceRules.pageSize(base, glassWidth, glassHeight)
    if not finite(glassWidth) or not finite(glassHeight) or glassWidth <= 0 or glassHeight <= 0 then
        return { width = base.width, height = base.height, exact = false }
    end

    local width, height = math.floor(glassWidth + 0.5), math.floor(glassHeight + 0.5)

    if pageRange(width, base.width) and pageRange(height, base.height) then
        return { width = width, height = height, exact = true }
    end

    local factor = math.max(PAGE_MIN, math.min(PAGE_MAX, glassWidth / base.width, glassHeight / base.height))

    return {
        width = math.floor(base.width * factor + 0.5),
        height = math.floor(base.height * factor + 0.5),
        exact = false,
    }
end

function DeviceRules.closeSize(a, b)
    if type(a) ~= 'table' or type(b) ~= 'table' then return false end

    return math.abs(a.width - b.width) <= PAGE_SNAP and math.abs(a.height - b.height) <= PAGE_SNAP
end

function DeviceRules.pixelBox(rect, screenWidth, screenHeight)
    if type(rect) ~= 'table' or type(rect.mapping) ~= 'table' then return nil end
    if not finite(screenWidth) or not finite(screenHeight) or screenWidth < 1 or screenHeight < 1 then return nil end

    local mapping = rect.mapping
    local left, top = math.floor(mapping[1] * screenWidth + 0.5), math.floor(mapping[2] * screenHeight + 0.5)
    local right, bottom = math.floor(mapping[3] * screenWidth + 0.5), math.floor(mapping[6] * screenHeight + 0.5)

    if right - left < 1 or bottom - top < 1 then return nil end

    return { x = left, y = top, width = right - left, height = bottom - top }
end

function DeviceRules.pageRect(box, size, screenWidth, screenHeight)
    if type(box) ~= 'table' or type(size) ~= 'table' then return nil end
    if not finite(screenWidth) or not finite(screenHeight) or screenWidth < 1 or screenHeight < 1 then return nil end

    local exact = DeviceRules.closeSize(box, size)
    local x, y, width, height = box.x, box.y, box.width, box.height

    if exact then
        x, y = x + math.floor((width - size.width) / 2), y + math.floor((height - size.height) / 2)
        width, height = size.width, size.height
    end

    local left, top = x / screenWidth, y / screenHeight
    local right, bottom = (x + width) / screenWidth, (y + height) / screenHeight

    return {
        x = (left + right) / 2.0,
        y = (top + bottom) / 2.0,
        width = right - left,
        height = bottom - top,
        exact = exact,
        mapping = { left, top, right, top, left, bottom, right, bottom, size.width, size.height },
    }
end

function DeviceRules.fadeShare(elapsed, ms)
    if not finite(ms) or ms <= 0 then
        return 1.0
    end

    if not finite(elapsed) or elapsed <= 0 then
        return 0.0
    end

    return math.min(1.0, elapsed / ms)
end

local STUDIO_LOOKS = { soft = { hour = 12, weather = 'OVERCAST' }, night = { hour = 21, weather = 'CLEAR' } }
local STUDIO_PARTS = { front = { 0, 1 }, rear = { 2, 3 }, bonnet = { 4 }, boot = { 5 } }
local STUDIO_FIT, STUDIO_NEAR, STUDIO_FLOOR_GAP = 1.12, 1.15, 0.25
local STUDIO_WINDOW_MIN = 64
local STUDIO_MAP = 8000.0

DeviceRules.STUDIO_PARTS = { 'front', 'rear', 'bonnet', 'boot' }

local function within(value, low, high, fallback)
    if not finite(value) then
        return fallback
    end

    return math.max(low, math.min(high, value)) + 0.0
end

function DeviceRules.angleTo(from, to)
    return (to - from + 180.0) % 360.0 - 180.0
end

function DeviceRules.easeShare(seconds, rate)
    if not finite(seconds) or seconds <= 0 then
        return 0.0
    end

    return 1.0 - math.exp(-math.min(seconds, 0.25) * rate)
end

function DeviceRules.studio(kind, config)
    config = config or Config.devices

    local studio = type(config) == 'table' and type(config.studio) == 'table' and config.studio or nil

    if not studio or studio.enabled == false or type(studio.kinds) ~= 'table' then return nil end
    if studio.kinds[kind] ~= true then return nil end

    local spec = DeviceRules.spec(kind)

    if not spec or DeviceRules.userView(spec, config) ~= 'hud' then return nil end

    local spot = studio.spot

    if not point(spot) then return nil end

    local look = type(studio.look) == 'table' and studio.look or {}
    local zoom = type(look.zoom) == 'table' and look.zoom or {}
    local name = STUDIO_LOOKS[look.look] and look.look or 'soft'
    local low, high = within(zoom.min, 0.5, 3.0, 0.8), within(zoom.max, 0.5, 3.0, 2.0)

    if low > high then
        low, high = 0.8, 2.0
    end

    return {
        spot = { x = spot.x + 0.0, y = spot.y + 0.0, z = spot.z + 0.0 },
        look = name,
        hour = STUDIO_LOOKS[name].hour,
        weather = STUDIO_LOOKS[name].weather,
        fov = within(look.fov, 20.0, 70.0, 35.0),
        yaw = (finite(look.yaw) and look.yaw or 35.0) % 360.0,
        pitch = within(look.pitch, 2.0, 65.0, 10.0),
        zoomMin = low,
        zoomMax = high,
        spin = within(look.spin, 0.0, 30.0, 6.0),
    }
end

function DeviceRules.studioPage(settings)
    if type(settings) ~= 'table' then return false end

    return {
        yaw = settings.yaw,
        pitch = settings.pitch,
        zoom = 1.0,
        zoomMin = settings.zoomMin,
        zoomMax = settings.zoomMax,
        spin = settings.spin,
    }
end

function DeviceRules.studioWindow(value, size)
    if type(value) ~= 'table' or type(size) ~= 'table' then return nil end

    for _, key in ipairs({ 'x', 'y', 'w', 'h' }) do
        if not finite(value[key]) then return nil end
    end

    local x, y, w, h = math.floor(value.x), math.floor(value.y), math.floor(value.w), math.floor(value.h)

    if x < 0 or y < 0 or w < STUDIO_WINDOW_MIN or h < STUDIO_WINDOW_MIN or x + w > size.width then return nil end
    if y + h > size.height then return nil end

    return { x = x, y = y, w = w, h = h }
end

function DeviceRules.studioScreen(rect, window, size)
    if type(rect) ~= 'table' or type(window) ~= 'table' or type(size) ~= 'table' then return nil end

    local sx, sy = rect.width / size.width, rect.height / size.height
    local w, h = window.w * sx, window.h * sy

    return {
        cx = rect.x - rect.width / 2.0 + window.x * sx + w / 2.0,
        cy = rect.y - rect.height / 2.0 + window.y * sy + h / 2.0,
        w = w,
        h = h,
    }
end

function DeviceRules.studioView(data, settings, current)
    current = current or {}

    local view = { yaw = current.yaw, pitch = current.pitch, zoom = current.zoom }

    if type(data) ~= 'table' or type(settings) ~= 'table' then
        return view
    end

    if finite(data.yaw) then
        view.yaw = data.yaw % 360.0
    end

    if finite(data.pitch) then
        view.pitch = within(data.pitch, 2.0, 65.0, settings.pitch)
    end

    if finite(data.zoom) then
        view.zoom = within(data.zoom, settings.zoomMin, settings.zoomMax, 1.0)
    end

    return view
end

function DeviceRules.studioFrame(box, view, fov, aspect, screen, far)
    local t = math.tan(math.rad(fov) / 2.0)

    screen = screen or { cx = 0.5, cy = 0.5, w = 1.0, h = 1.0 }

    local yaw, pitch = math.rad(view.yaw), math.rad(view.pitch)
    local toCamera = { x = -math.sin(yaw) * math.cos(pitch), y = math.cos(yaw) * math.cos(pitch), z = math.sin(pitch) }
    local forward = scale(toCamera, -1.0)
    local right = unit(cross(forward, { x = 0.0, y = 0.0, z = 1.0 }))
    local up = cross(right, forward)
    local wide = math.max(0.05, screen.w * aspect) * t / STUDIO_FIT
    local high = math.max(0.05, screen.h) * t / STUDIO_FIT
    local half = box.half or { x = box.radius, y = box.radius, z = box.radius }
    local distance = 0.0

    for _, sx in ipairs({ -1.0, 1.0 }) do
        for _, sy in ipairs({ -1.0, 1.0 }) do
            for _, sz in ipairs({ -1.0, 1.0 }) do
                local corner = { x = half.x * sx, y = half.y * sy, z = half.z * sz }
                local depth = dot(corner, toCamera)

                distance = math.max(
                    distance,
                    depth + math.abs(dot(corner, right)) / wide,
                    depth + math.abs(dot(corner, up)) / high
                )
            end
        end
    end

    distance = math.max(distance / math.max(0.1, view.zoom), box.radius * STUDIO_NEAR)

    if finite(far) then
        distance = math.min(distance, far)
    end

    local height = 2.0 * distance * t
    local width = height * aspect
    local target = add(sub(box.middle, scale(right, (screen.cx - 0.5) * width)), scale(up, (screen.cy - 0.5) * height))
    local from = add(target, scale(toCamera, distance))

    if finite(box.floor) and from.z < box.floor + STUDIO_FLOOR_GAP then
        local lift = box.floor + STUDIO_FLOOR_GAP - from.z

        from.z, target.z = from.z + lift, target.z + lift
    end

    return from, target, distance
end

function DeviceRules.studioBands(rect)
    local bands = {}

    if type(rect) ~= 'table' then
        return bands
    end

    local left, right = rect.x - rect.width / 2.0, rect.x + rect.width / 2.0
    local top, bottom = rect.y - rect.height / 2.0, rect.y + rect.height / 2.0

    local function band(x, y, w, h)
        if w > 0 and h > 0 then
            bands[#bands + 1] = { x = x, y = y, w = w, h = h }
        end
    end

    band(0.5, top / 2.0, 1.0, top)
    band(0.5, (bottom + 1.0) / 2.0, 1.0, 1.0 - bottom)
    band(left / 2.0, rect.y, left, rect.height)
    band((right + 1.0) / 2.0, rect.y, 1.0 - right, rect.height)

    return bands
end

function DeviceRules.freezeRect(rect)
    if type(rect) ~= 'table' or not finite(rect.x) or not finite(rect.y) or not finite(rect.width) or not finite(rect.height) then
        return nil
    end

    if rect.width <= 0 or rect.height <= 0 then return nil end

    return { x = rect.x, y = rect.y, w = rect.width, h = rect.height }
end

function DeviceRules.studioDoors(part)
    return STUDIO_PARTS[part]
end

function DeviceRules.studioModel(model)
    return type(model) == 'string' and #model > 0 and #model <= 32 and model:find('^[%w_]+$') ~= nil
end

function DeviceRules.studioPaints(wanted, paints)
    local known, list, seen = {}, {}, {}

    for _, paint in ipairs(type(paints) == 'table' and paints or {}) do
        if type(paint) == 'table' and type(paint.id) == 'string' then
            known[paint.id] = true
        end
    end

    for _, id in ipairs(type(wanted) == 'table' and wanted or {}) do
        if known[id] and not seen[id] then
            seen[id] = true
            list[#list + 1] = id
        end
    end

    if #list == 0 then
        for _, paint in ipairs(type(paints) == 'table' and paints or {}) do
            if type(paint) == 'table' and type(paint.id) == 'string' and not seen[paint.id] then
                seen[paint.id] = true
                list[#list + 1] = paint.id
            end
        end
    end

    return list
end

local function paletteOk(list)
    if type(list) ~= 'table' then return false end

    for _, paint in ipairs(list) do
        if type(paint) ~= 'table' or type(paint.id) ~= 'string' or not paint.id:find('^[%w_]+$') then return false end
        if not whole((paint.primary or -1) + 1) or not whole((paint.secondary or -1) + 1) then return false end
    end

    return true
end

DeviceRules.paletteOk = paletteOk

local function checkStudio(studio, fail)
    if studio == nil then return end

    if type(studio) ~= 'table' then
        fail('studio must be a table')

        return
    end

    if studio.enabled ~= nil and type(studio.enabled) ~= 'boolean' then
        fail('studio.enabled must be true or false')
    end

    if type(studio.kinds) ~= 'table' then
        fail('studio.kinds must list the device kinds that may ask for it')
    else
        for kind, on in pairs(studio.kinds) do
            if not DeviceRules.spec(kind) or type(on) ~= 'boolean' then
                fail('studio.kinds.' .. tostring(kind) .. ' must be a screen kind set to true or false')
            end
        end
    end

    local spot = studio.spot

    if not point(spot) then
        fail('studio.spot needs x, y and z')
    elseif math.abs(spot.x) > STUDIO_MAP or math.abs(spot.y) > STUDIO_MAP or spot.z < 50 or spot.z > 800 then
        fail('studio.spot must lie within 8000 m of the map centre at a height of 50 to 800 m')
    end

    if studio.paints ~= nil and not paletteOk(studio.paints) then
        fail('studio.paints needs id, primary and secondary colour numbers')
    end

    local look = studio.look

    if look == nil then return end

    if type(look) ~= 'table' then
        fail('studio.look must be a table')

        return
    end

    if look.look ~= nil and not STUDIO_LOOKS[look.look] then
        fail("studio.look.look must be 'soft' or 'night'")
    end

    if look.fov ~= nil and (not finite(look.fov) or look.fov < 20 or look.fov > 70) then
        fail('studio.look.fov must be degrees from 20 to 70')
    end

    if look.yaw ~= nil and not finite(look.yaw) then
        fail('studio.look.yaw must be degrees')
    end

    if look.pitch ~= nil and (not finite(look.pitch) or look.pitch < 2 or look.pitch > 65) then
        fail('studio.look.pitch must be degrees from 2 to 65')
    end

    if look.spin ~= nil and (not finite(look.spin) or look.spin < 0 or look.spin > 30) then
        fail('studio.look.spin must be degrees a second from 0 to 30')
    end

    local zoom = look.zoom

    if zoom ~= nil then
        if type(zoom) ~= 'table' or not finite(zoom.min) or not finite(zoom.max) or zoom.min < 0.5 or zoom.max > 3 or zoom.min >= zoom.max or zoom.min > 1 or zoom.max < 1 then
            fail('studio.look.zoom needs min 0.5 to 1 and max 1 to 3, min below max')
        end
    end
end

local LIGHT_COLOR, LIGHT_TINT = { 205, 220, 245 }, { 195, 255, 0 }
local LIGHT_CONE, LIGHT_OFFSET = 80.0, 0.12

local function channel(value, fallback)
    if not finite(value) then
        return fallback
    end

    return math.floor(math.max(0, math.min(255, value)) + 0.5)
end

local function share(value)
    if not finite(value) then
        return 0.0
    end

    return math.max(0.0, math.min(1.0, value)) + 0.0
end

local function rgb(value)
    if type(value) ~= 'table' then return false end

    for index = 1, 3 do
        local part = value[index]

        if not finite(part) or part < 0 or part > 255 or part % 1 ~= 0 then return false end
    end

    return value[4] == nil
end

function DeviceRules.light(spec, config)
    config = config or Config.devices

    local global = type(config) == 'table' and config.light or nil
    local own = type(spec) == 'table' and spec.light or nil

    if type(global) ~= 'table' or global.enabled == false or type(own) ~= 'table' then return nil end
    if not finite(own.range) or own.range <= 0 or not finite(own.intensity) or own.intensity <= 0 then return nil end

    local color = type(own.color) == 'table' and own.color or LIGHT_COLOR
    local tint = type(global.tintColor) == 'table' and global.tintColor or LIGHT_TINT
    local mix, out = share(own.tint), {}

    for index = 1, 3 do
        local base = channel(color[index], LIGHT_COLOR[index])

        out[index] = math.floor(base + (channel(tint[index], LIGHT_TINT[index]) - base) * mix + 0.5)
    end

    return {
        r = out[1],
        g = out[2],
        b = out[3],
        range = own.range + 0.0,
        intensity = own.intensity + 0.0,
        idle = share(own.idle),
        offset = (finite(own.offset) and own.offset or LIGHT_OFFSET) + 0.0,
        aim = (finite(own.aim) and own.aim or 0.0) + 0.0,
        cone = (finite(global.cone) and global.cone or LIGHT_CONE) + 0.0,
    }
end

function DeviceRules.night(hour, night)
    if type(night) ~= 'table' or not finite(hour) or not finite(night.from) then return false end
    if not finite(night.to) or night.from == night.to then return false end

    if night.from < night.to then
        return hour >= night.from and hour < night.to
    end

    return hour >= night.from or hour < night.to
end

function DeviceRules.lightGoal(light, inUse, night)
    if type(light) ~= 'table' then
        return 0.0
    end

    if inUse then
        return light.intensity
    end

    if night then
        return light.intensity * light.idle
    end

    return 0.0
end

function DeviceRules.lightRank(mine, inUse, goal)
    if mine then
        return 0
    end

    if not finite(goal) or goal <= 0 then
        return 3
    end

    return inUse and 1 or 2
end

function DeviceRules.lightSpot(corners, light)
    local basis = DeviceRules.screenBasis(corners)
    local angle = math.rad(light.aim or 0.0)
    local direction = unit(sub(scale(basis.normal, math.cos(angle)), scale(basis.up, math.sin(angle))))

    return add(basis.centre, scale(basis.normal, light.offset)), direction
end

function DeviceRules.blink(age, total, pulses)
    if not finite(age) or not finite(total) or total <= 0 or age < 0 or age >= total then
        return 0.0
    end

    local count = math.max(1, math.floor(tonumber(pulses) or 1))
    local phase = age / total * count

    return math.sin((phase - math.floor(phase)) * math.pi)
end

function DeviceRules.fadeTo(level, goal, step)
    if level < goal then
        return math.min(goal, level + step)
    end

    return math.max(goal, level - step)
end

function DeviceRules.cleanKey(data)
    if type(data) ~= 'table' then return nil end

    if data.kind == 'text' then
        local text = data.text

        if not plain(text, TEXT_BYTES) or #text == 0 then return nil end

        return { kind = 'text', text = text }
    end

    if data.kind ~= 'key' or type(data.key) ~= 'string' then return nil end

    local ctrl = data.ctrl == true

    if CONTROL_KEYS[data.key] or (ctrl and SHORTCUTS[data.key]) then
        return { kind = 'key', key = data.key, ctrl = ctrl, shift = data.shift == true }
    end

    return nil
end

function DeviceRules.cleanButton(button)
    if button == nil then
        return 'left'
    end

    return BUTTONS[button] and button or nil
end

function DeviceRules.cleanState(state, maxBytes)
    if type(state) ~= 'table' then return nil end

    local clean, keys, bytes = {}, 0, 2

    for key, value in pairs(state) do
        if type(key) ~= 'string' or #key > STATE_KEY_BYTES or not key:find('^%a[%w_]*$') then return nil end

        keys = keys + 1

        if keys > STATE_KEYS then return nil end

        local kind = type(value)

        if kind == 'number' then
            if not finite(value) then return nil end

            bytes = bytes + #key + 24
        elseif kind == 'boolean' then
            bytes = bytes + #key + 8
        elseif kind == 'string' then
            if not plain(value, STATE_TEXT_BYTES) then return nil end

            bytes = bytes + #key + #value + 6
        else
            return nil
        end

        clean[key] = value
    end

    if bytes > (maxBytes or 0) then return nil end

    return clean, bytes
end

function DeviceRules.cleanOsState(state, partBytes, maxBytes)
    if type(state) ~= 'table' then return nil end

    for key in pairs(state) do
        if key ~= 'shell' and key ~= 'apps' then return nil end
    end

    local shell, total = DeviceRules.cleanState(state.shell == nil and {} or state.shell, partBytes)

    if not shell then return nil end

    local apps, count = {}, 0

    if state.apps ~= nil then
        if type(state.apps) ~= 'table' then return nil end

        for id, part in pairs(state.apps) do
            if type(id) ~= 'string' or #id > 32 or not id:find('^[a-z][a-z0-9_]+$') then return nil end

            count = count + 1

            if count > STATE_APPS then return nil end

            local clean, bytes = DeviceRules.cleanState(part, partBytes)

            if not clean then return nil end

            apps[id] = clean
            total = total + bytes + #id + 4
        end
    end

    if total > (maxBytes or 0) then return nil end

    return { shell = shell, apps = apps }
end

function DeviceRules.cleanDeviceState(kind, state, mirror)
    mirror = mirror or Config.devices.mirror

    local spec = Config.kinds[kind]

    if spec and spec.os then
        return DeviceRules.cleanOsState(state, mirror.stateBytes, mirror.osStateBytes or mirror.stateBytes * 3)
    end

    return (DeviceRules.cleanState(state, mirror.stateBytes))
end

function DeviceRules.checkKind(kind, spec, mode)
    local problems = {}

    local function fail(text)
        problems[#problems + 1] = kind .. ': ' .. text
    end

    if type(spec) ~= 'table' then
        fail('not a table')

        return problems
    end

    local variants = spec.variants

    if type(variants) ~= 'table' or #variants == 0 then
        fail('variants must list at least one model')
    else
        local listed, count = {}, 0

        for _ in pairs(variants) do
            count = count + 1
        end

        if count ~= #variants then
            fail('variants must be a plain list')
        end

        for index, name in ipairs(variants) do
            if type(name) ~= 'string' or not name:find('^[a-z][a-z0-9_]*$') then
                fail(('variant %d must be a lower-case model name'):format(index))
            elseif listed[name] then
                fail('variant ' .. name .. ' is listed twice')
            end

            if type(name) == 'string' then
                listed[name] = true
            end
        end
    end

    if spec.screenMode ~= nil and not MODES[spec.screenMode] then
        fail('screenMode must be poly or world')
    end

    if spec.userView ~= nil and not VIEWS[spec.userView] then
        fail('userView must be hud or world')
    end

    if not PLACES[spec.placeOn] then
        fail('placeOn must be surface or floor')
    end

    if spec.os ~= nil and type(spec.os) ~= 'boolean' then
        fail('os must be true or false')
    end

    if spec.wireless ~= nil and type(spec.wireless) ~= 'boolean' then
        fail('wireless must be true or false')
    end

    if spec.page ~= nil and (type(spec.page) ~= 'string' or not spec.page:find('^[%w_/%-]+%.html$') or spec.page:find('..', 1, true)) then
        fail('page must be an .html file of this resource')
    end

    local dui = spec.dui

    if type(dui) ~= 'table' or not whole(dui.width) or not whole(dui.height) then
        fail('dui width and height must be whole numbers')
        dui = nil
    end

    local corners = type(spec.screen) == 'table' and spec.screen or {}
    local complete = true

    for _, name in ipairs(CORNERS) do
        if not point(corners[name]) then
            complete = false
        end
    end

    if not complete then
        fail('screen needs TL, TR, BL and BR')
    else
        local across, down = sub(corners.TR, corners.TL), sub(corners.BL, corners.TL)
        local width, height = length(across), length(down)

        if width <= 0 or height <= 0 then
            fail('screen has no area')
        else
            if length(sub(sub(corners.BR, corners.BL), across)) > 0.001 then
                fail('screen corners are not a flat rectangle')
            end

            if math.abs(dot(across, down)) / (width * height) > 0.01 then
                fail('screen corners are not square to each other')
            end

            if DeviceRules.screenBasis(corners).normal.y >= 0 then
                fail('the screen must face -Y')
            end

            if dui then
                local glass, page = width / height, dui.width / dui.height

                if math.abs(page / glass - 1.0) > ASPECT_TOLERANCE then
                    fail(('page %dx%d is %.3f wide per high, the glass %.3f'):format(
                        dui.width,
                        dui.height,
                        page,
                        glass
                    ))
                end
            end
        end
    end

    local size = spec.textureSize

    if type(size) ~= 'table' or not whole(size.width) or not whole(size.height) then
        fail('textureSize width and height must be whole numbers')
    elseif mode == 'world' and dui and (size.width ~= dui.width or size.height ~= dui.height) then
        fail(('in world mode the dui must equal textureSize (page %dx%d, texture %dx%d)'):format(
            dui.width,
            dui.height,
            size.width,
            size.height
        ))
    end

    local animProblem = DeviceRules.checkAnim(spec.anim)

    if animProblem then
        fail(animProblem)
    end

    local camera = spec.camera

    if type(camera) ~= 'table' or not finite(camera.fov) or camera.fov < 10 or camera.fov > 90 or not finite(camera.fill) or camera.fill <= 0 or camera.fill > 1 then
        fail('camera needs fov 10 to 90 and fill above 0 up to 1')
    end

    local use = spec.use

    if type(use) ~= 'table' or not point(use.offset) or not finite(use.reach) or use.reach <= 0 then
        fail('use needs offset and reach')
    end

    if not finite(spec.spacing) or spec.spacing <= 0 then
        fail('spacing must be above 0')
    end

    if spec.placeOn == 'floor' and (not finite(spec.clearFront) or spec.clearFront <= 0) then
        fail('a floor device needs clearFront')
    end

    local light = spec.light

    if light ~= nil and type(light) ~= 'table' then
        fail('light must be a table')
    elseif light ~= nil then
        if light.color ~= nil and not rgb(light.color) then
            fail('light.color must be red, green and blue, whole numbers from 0 to 255')
        end

        if light.tint ~= nil and (not finite(light.tint) or light.tint < 0 or light.tint > 1) then
            fail('light.tint must be a share from 0 to 1')
        end

        if not finite(light.range) or light.range <= 0 or light.range > 10 then
            fail('light.range must be metres above 0 up to 10')
        end

        if not finite(light.intensity) or light.intensity < 0 or light.intensity > 20 then
            fail('light.intensity must be from 0 to 20')
        end

        if light.idle ~= nil and (not finite(light.idle) or light.idle < 0 or light.idle > 1) then
            fail('light.idle must be a share from 0 to 1')
        end

        if light.offset ~= nil and (not finite(light.offset) or light.offset < 0 or light.offset > 1) then
            fail('light.offset must be metres from 0 to 1')
        end

        if light.aim ~= nil and (not finite(light.aim) or light.aim < -60 or light.aim > 60) then
            fail('light.aim must be degrees from -60 to 60')
        end
    end

    return problems
end

local function hour(value)
    return finite(value) and value >= 0 and value <= 24 and value % 1 == 0
end

local function checkLight(light, problems)
    if light == nil then return end

    if type(light) ~= 'table' then
        problems[#problems + 1] = 'light must be a table'

        return
    end

    local function fail(text)
        problems[#problems + 1] = 'light.' .. text
    end

    if light.enabled ~= nil and type(light.enabled) ~= 'boolean' then
        fail('enabled must be true or false')
    end

    if not finite(light.range) or light.range <= 0 or light.range > 100 then
        fail('range must be metres above 0 up to 100')
    end

    if not finite(light.max) or light.max < 0 or light.max > 8 or light.max % 1 ~= 0 then
        fail('max must be a whole number from 0 to 8')
    end

    if light.fadeMs ~= nil and (not finite(light.fadeMs) or light.fadeMs < 0 or light.fadeMs > 5000) then
        fail('fadeMs must be milliseconds from 0 to 5000')
    end

    if light.cone ~= nil and (not finite(light.cone) or light.cone <= 0 or light.cone >= 90) then
        fail('cone must be degrees above 0 and below 90')
    end

    if light.night ~= nil and (type(light.night) ~= 'table' or not hour(light.night.from) or not hour(light.night.to)) then
        fail('night needs from and to, whole hours from 0 to 24')
    end

    if light.tintColor ~= nil and not rgb(light.tintColor) then
        fail('tintColor must be red, green and blue, whole numbers from 0 to 255')
    end
end

function DeviceRules.checkConfig(config, kinds)
    config = config or Config.devices
    kinds = kinds or Config.kinds

    local problems = {}

    if type(config) ~= 'table' or type(kinds) ~= 'table' then
        return { 'Config.devices or Config.kinds is missing' }
    end

    if not MODES[config.screenMode] then
        problems[#problems + 1] = 'screenMode must be poly or world'
    end

    if config.userView ~= nil and not VIEWS[config.userView] then
        problems[#problems + 1] = 'userView must be hud or world'
    end

    local session = type(config.session) == 'table' and config.session or {}
    local fade = session.viewFadeMs

    if fade ~= nil and (not finite(fade) or fade < 0 or fade > 1000) then
        problems[#problems + 1] = 'session.viewFadeMs must be milliseconds from 0 to 1000'
    end

    if session.darkGlass ~= nil and type(session.darkGlass) ~= 'boolean' then
        problems[#problems + 1] = 'session.darkGlass must be true or false'
    end

    checkLight(config.light, problems)
    checkStudio(config.studio, function(text) problems[#problems + 1] = text end)

    for _, problem in ipairs(ScreenRules.checkConfig(config.idle, kinds)) do
        problems[#problems + 1] = problem
    end

    if not finite(config.streamDistance) or not finite(config.despawnDistance) or config.despawnDistance <= config.streamDistance then
        problems[#problems + 1] = 'despawnDistance must be larger than streamDistance'
    end

    if not finite(config.flatSlope) or not finite(config.maxSlope) or config.flatSlope < 0 or config.maxSlope < config.flatSlope or config.maxSlope >= 90 then
        problems[#problems + 1] = 'flatSlope and maxSlope must be degrees with 0 <= flatSlope <= maxSlope < 90'
    end

    local names = {}

    for kind, spec in pairs(kinds) do
        if type(spec) == 'table' and spec.placeOn ~= 'hand' then
            names[#names + 1] = kind
        end
    end

    table.sort(names)

    local owners = {}

    for _, kind in ipairs(names) do
        local spec = kinds[kind]

        for _, problem in ipairs(DeviceRules.checkKind(kind, spec, DeviceRules.screenMode(spec, config))) do
            problems[#problems + 1] = problem
        end

        for _, name in ipairs(type(spec.variants) == 'table' and spec.variants or {}) do
            if type(name) == 'string' then
                if owners[name] and owners[name] ~= kind then
                    problems[#problems + 1] = ('%s: variant %s is also a %s'):format(kind, name, owners[name])
                end

                owners[name] = owners[name] or kind
            end
        end
    end

    return problems
end

return DeviceRules
