local Marker = {
    mode = 'poly',
    accent = { 195, 255, 0 },
    scale = 1.0,
    motion = true,
}

Marker.BOX = { margin = 0.08, least = 0.5, most = 12.0 }
Marker.STAND = 0.8
Marker.NEAR = { range = 12.0, most = 8, every = 250, moved = 1.0 }

local TONES = {
    warn = { 255, 176, 32 },
    bad = { 248, 40, 52 },
    neutral = { 161, 161, 170 },
    white = { 255, 255, 255 },
}

local FILES = {
    band = 'web/build/marker/evolent_band.png',
    soft = 'web/build/marker/evolent_band_soft.png',
    frame = 'web/build/marker/evolent_zone.png',
    frame_far = 'web/build/marker/evolent_zone_far.png',
    arrow = 'web/build/marker/evolent_box_arrow.png',
    person = 'web/build/marker/evolent_icon_person.png',
}

local STYLES = {
    box = { alpha = 0.95 },
    zone = { size = 1.8, alpha = 0.95, scaled = true },
    round = { alpha = 0.95 },
}

local FRAME, FRAME_MARGIN, FAR_RATIO, THIRD = 1.8, 0.155, 9.5, 1.0 / 3.0
local ARROW_SHAPE, ARROW_GAP, ARROW_STEP, ARROW_LEAST, ARROW_MOST = 0.6 / 1.04, 0.03, 0.8, 0.16, 0.6
local FILL_ALPHA, LINE_ALPHA, GLOW_ALPHA = 0.10, 0.55, 0.22
local ARC_AT, ARC_SPAN, FILL_MOST, CHUNK = 45.0, 50.0, 200.0, 8
local NEIGHBOUR_ALPHA, BLOCKER_ALPHA, LEVEL = 0.45, 0.8, 0.5
local FLOW_MS, LIFT, CULL_DEGREES, RETRY_MS = 1400, 0.03, 75.0, 1000

local LAYERS = {
    { name = 'fill', share = FILL_ALPHA },
    { name = 'line', share = LINE_ALPHA },
    { name = 'glow', share = GLOW_ALPHA },
    { name = 'band', share = 1.0 },
}

local txd = nil
local footprints = {}
local view = { now = -1, camera = nil, forward = nil }

local function rgb(value)
    if type(value) == 'table' and tonumber(value[1]) and tonumber(value[2]) and tonumber(value[3]) then
        return { math.floor(tonumber(value[1])), math.floor(tonumber(value[2])), math.floor(tonumber(value[3])) }
    end

    if type(value) == 'string' then
        local hex = value:match('^#?(%x%x%x%x%x%x)$')

        if hex then
            return { tonumber(hex:sub(1, 2), 16), tonumber(hex:sub(3, 4), 16), tonumber(hex:sub(5, 6), 16) }
        end

        local short = value:match('^#?(%x%x%x)$')

        if short then
            return {
                tonumber(short:sub(1, 1):rep(2), 16),
                tonumber(short:sub(2, 2):rep(2), 16),
                tonumber(short:sub(3, 3):rep(2), 16),
            }
        end
    end

    return nil
end

Marker.parse = rgb

function Marker.setup(options)
    if type(options) ~= 'table' then return end

    if options.draw == 'marker' or options.draw == 'poly' then
        Marker.mode = options.draw
    end

    local scale = tonumber(options.scale)

    if scale and scale > 0.1 and scale <= 4.0 then
        Marker.scale = scale
    end

    if options.motion ~= nil then
        Marker.motion = options.motion ~= false
    end

    Marker.setAccent(options.color)
end

function Marker.setAccent(value)
    local colour = rgb(value)

    if colour then
        Marker.accent = colour
    end

    return colour ~= nil
end

local function textures()
    if txd ~= nil then return txd or nil end

    txd = false

    local name = GetCurrentResourceName() .. '_marker'
    local dictionary = CreateRuntimeTxd(name)

    if not dictionary or dictionary == 0 then return nil end

    for texture, path in pairs(FILES) do
        local made = CreateRuntimeTextureFromImage(dictionary, texture, path)

        if not made or made == 0 then return nil end
    end

    txd = name

    return txd
end

local function look(now)
    if view.now == now then return view end

    local camera = GetFinalRenderedCamCoord()
    local rotation = GetFinalRenderedCamRot(2)
    local pitch, yaw = math.rad(rotation.x), math.rad(rotation.z)

    view.now = now
    view.camera = camera
    view.forward = { x = -math.sin(yaw) * math.cos(pitch), y = math.cos(yaw) * math.cos(pitch), z = math.sin(pitch) }

    return view
end

local function inView(x, y, z, radius)
    local camera, forward = view.camera, view.forward
    local dx, dy, dz = x - camera.x, y - camera.y, z - camera.z
    local distance = math.sqrt(dx * dx + dy * dy + dz * dz)

    if distance <= radius then return true end

    local spread = math.min(180.0, CULL_DEGREES + math.deg(math.asin(radius / distance)))

    return (dx * forward.x + dy * forward.y + dz * forward.z) / distance >= math.cos(math.rad(spread))
end

local function far(x, y, z, extent)
    local camera = view.camera
    local dx, dy, dz = camera.x - x, camera.y - y, camera.z - z
    local reach = extent * FAR_RATIO

    return dx * dx + dy * dy + dz * dz > reach * reach
end

local function facing(z)
    return view.camera.z >= z
end

local function colourOf(spec)
    if type(spec.color) == 'table' then return spec.color end

    return TONES[spec.tone] or (type(spec.accent) == 'table' and spec.accent) or Marker.accent
end

local function frame(x, y, z, heading)
    local turn = math.rad(heading)
    local c, s = math.cos(turn), math.sin(turn)

    return function(px, py)
        return { x = x + px * c - py * s, y = y + px * s + py * c, z = z }
    end
end

local function sheet(place, x0, y0, x1, y1, u0, v0, u1, v1)
    local a, b, c, d = place(x0, y0), place(x1, y0), place(x1, y1), place(x0, y1)

    a.u, a.v, b.u, b.v, c.u, c.v, d.u, d.v = u0, v0, u1, v0, u1, v1, u0, v1

    return { a, b, c, d }
end

local function texturedTri(a, b, c, colour, alpha, dictionary, texture)
    DrawTexturedPoly(
        a.x, a.y, a.z,
        b.x, b.y, b.z,
        c.x, c.y, c.z,
        colour[1], colour[2], colour[3], alpha,
        dictionary, texture,
        a.u, a.v, 1.0,
        b.u, b.v, 1.0,
        c.u, c.v, 1.0
    )
end

local function sheetDraw(points, up, colour, alpha, dictionary, texture)
    local a, b, c, d = points[1], points[2], points[3], points[4]

    if up then
        texturedTri(a, b, c, colour, alpha, dictionary, texture)
        texturedTri(a, c, d, colour, alpha, dictionary, texture)
    else
        texturedTri(c, b, a, colour, alpha, dictionary, texture)
        texturedTri(d, c, a, colour, alpha, dictionary, texture)
    end
end

local function plainRing(x, y, z, size, colour, alpha)
    DrawMarker(25, x, y, z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, size, size, 1.0, colour[1], colour[2], colour[3], alpha, false, false, 2, false, nil, nil, false)
end

local function boxSheets(spec, x, y, z, heading, width, length)
    local cached = spec.sheets

    if cached and cached.x == x and cached.y == y and cached.z == z and cached.heading == heading and cached.width == width and cached.length == length then
        return cached
    end

    local place = frame(x, y, z, heading)
    local short = math.min(width, length)
    local margin = FRAME_MARGIN * short / FRAME
    local hw, hl = width * 0.5 + margin, length * 0.5 + margin
    local band = (short + margin * 2.0) * THIRD
    local parts

    if math.abs(width - length) < 0.01 then
        parts = { sheet(place, -hw, -hl, hw, hl, 0.0, 1.0, 1.0, 0.0) }
    elseif length > width then
        parts = {
            sheet(place, -hw, hl - band, hw, hl, 0.0, THIRD, 1.0, 0.0),
            sheet(place, -hw, band - hl, hw, hl - band, 0.0, THIRD * 2.0, 1.0, THIRD),
            sheet(place, -hw, -hl, hw, band - hl, 0.0, 1.0, 1.0, THIRD * 2.0),
        }
    else
        parts = {
            sheet(place, -hw, -hl, band - hw, hl, 0.0, 1.0, THIRD, 0.0),
            sheet(place, band - hw, -hl, hw - band, hl, THIRD, 1.0, THIRD * 2.0, 0.0),
            sheet(place, hw - band, -hl, hw, hl, THIRD * 2.0, 1.0, 1.0, 0.0),
        }
    end

    local wide = math.max(ARROW_LEAST, math.min(ARROW_MOST, width * 0.45))
    local tall = wide * ARROW_SHAPE
    local arrows = {}

    for index = 1, 2 do
        local inner = -(hl + ARROW_GAP + (index - 1) * tall * ARROW_STEP)

        arrows[index] = sheet(place, -wide * 0.5, inner - tall, wide * 0.5, inner, 0.0, 0.0, 1.0, 1.0)
    end

    local reach = hl + ARROW_GAP + tall * (1.0 + ARROW_STEP)

    cached = {
        x = x,
        y = y,
        z = z,
        heading = heading,
        width = width,
        length = length,
        parts = parts,
        arrows = arrows,
        extent = short + margin * 2.0,
        radius = math.sqrt(hw * hw + reach * reach),
    }
    spec.sheets = cached

    return cached
end

local function box(spec, x, y, z, colour, alpha, dictionary, now)
    local width = math.max(0.05, tonumber(spec.width) or Marker.BOX.least)
    local length = math.max(0.05, tonumber(spec.length) or Marker.BOX.least)
    local sheets = boxSheets(spec, x, y, z, tonumber(spec.heading) or 0.0, width, length)

    if not inView(x, y, z, sheets.radius) then return end

    local up = facing(z)
    local texture = far(x, y, z, sheets.extent) and 'frame_far' or 'frame'

    for _, part in ipairs(sheets.parts) do
        sheetDraw(part, up, colour, alpha, dictionary, texture)
    end

    if spec.arrows ~= true then return end

    local flow = Marker.motion and (now % FLOW_MS) / FLOW_MS or 0.0

    for index, points in ipairs(sheets.arrows) do
        local wave = index == 1 and 1.0 or 0.6

        if Marker.motion then
            wave = 0.55 + 0.45 * math.cos((flow + (index - 1) * 0.5) * math.pi * 2.0)
        end

        sheetDraw(points, up, colour, math.floor(alpha * 0.9 * wave + 0.5), dictionary, 'arrow')
    end
end

local function zoneSheet(spec, x, y, z, heading, size)
    local cached = spec.sheets

    if cached and cached.x == x and cached.y == y and cached.z == z and cached.heading == heading and cached.size == size then
        return cached
    end

    local half = (FRAME * 0.5 + FRAME_MARGIN) * size / FRAME

    cached = {
        x = x,
        y = y,
        z = z,
        heading = heading,
        size = size,
        frame = sheet(frame(x, y, z, heading), -half, -half, half, half, 0.0, 1.0, 1.0, 0.0),
        extent = half * 2.0,
        radius = half * 1.42,
    }
    spec.sheets = cached

    return cached
end

local function icon(x, y, z, size, heading, colour, alpha, dictionary, name)
    local half = size * 0.5
    local place = frame(x, y, z + 0.002, heading)

    sheetDraw(sheet(place, -half, -half, half, half, 0.0, 1.0, 1.0, 0.0), facing(z), colour, alpha, dictionary, name)
end

local function zone(spec, x, y, z, size, colour, alpha, dictionary)
    local sheets = zoneSheet(spec, x, y, z, tonumber(spec.heading) or 0.0, size)

    if not inView(x, y, z, sheets.radius) then return end

    sheetDraw(sheets.frame, facing(z), colour, alpha, dictionary, far(x, y, z, sheets.extent) and 'frame_far' or 'frame')

    if not spec.icon then return end

    local camera = view.camera

    icon(x, y, z, size * 0.4, math.deg(math.atan(camera.x - x, y - camera.y)), TONES.white, math.floor(alpha * 0.9 + 0.5), dictionary, spec.icon)
end

local function circle(radius, from, to, steps)
    local points = {}

    for step = 0, steps do
        local angle = math.rad(from + (to - from) * step / steps)
        points[#points + 1] = { radius * math.cos(angle), radius * math.sin(angle) }
    end

    return points
end

local function local2(px, py)
    return { x = px, y = py, z = 0.0 }
end

local function orient(a, b, c)
    return (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
end

local function addTri(list, a, b, c, texture)
    if orient(a, b, c) < 0 then
        a, c = c, a
    end

    list[#list + 1] = { a, b, c, texture }
end

local function normal(from, to)
    local dx, dy = to[1] - from[1], to[2] - from[2]
    local length = math.sqrt(dx * dx + dy * dy)

    if length < 0.0001 then return nil end

    return -dy / length, dx / length
end

local function stroke(points, width, closed, texture)
    local count = #points
    local half = width * 0.5
    local left, right, out = {}, {}, {}

    for index = 1, count do
        local point = points[index]
        local before = points[index - 1] or (closed and points[count]) or nil
        local after = points[index + 1] or (closed and points[1]) or nil
        local ax, ay, bx, by

        if before then ax, ay = normal(before, point) end
        if after then bx, by = normal(point, after) end

        ax, ay = ax or bx or 0.0, ay or by or 0.0
        bx, by = bx or ax, by or ay

        local nx, ny = ax + bx, ay + by
        local length = math.sqrt(nx * nx + ny * ny)

        if length < 0.0001 then
            nx, ny, length = ax, ay, 1.0
        end

        nx, ny = nx / length, ny / length

        local miter = half / math.max(0.5, nx * ax + ny * ay)
        local l, r = local2(point[1] + nx * miter, point[2] + ny * miter), local2(point[1] - nx * miter, point[2] - ny * miter)

        l.u, l.v, r.u, r.v = 1.0, 0.5, 0.0, 0.5
        left[index], right[index] = l, r
    end

    for index = 1, closed and count or count - 1 do
        local after = index % count + 1

        addTri(out, right[index], left[index], left[after], texture)
        addTri(out, right[index], left[after], right[after], texture)
    end

    return out
end

local function newChunk()
    return { fill = {}, line = {}, glow = {}, band = {} }
end

local function sphere(chunk)
    local sx, sy, count = 0.0, 0.0, 0

    for _, layer in ipairs(LAYERS) do
        for _, tri in ipairs(chunk[layer.name]) do
            for corner = 1, 3 do
                sx, sy, count = sx + tri[corner].x, sy + tri[corner].y, count + 1
            end
        end
    end

    local cx, cy, reach = sx / math.max(1, count), sy / math.max(1, count), 0.0

    for _, layer in ipairs(LAYERS) do
        for _, tri in ipairs(chunk[layer.name]) do
            for corner = 1, 3 do
                local dx, dy = tri[corner].x - cx, tri[corner].y - cy

                reach = math.max(reach, dx * dx + dy * dy)
            end
        end
    end

    chunk.x, chunk.y, chunk.radius = cx, cy, math.sqrt(reach) + 0.01
end

local function ringThickness(radius)
    return math.max(math.min(0.3, math.max(0.08, radius * 0.1)), radius * 0.004)
end

local function ringShape(spec, radius)
    local cached = spec.shape

    if cached and cached.radius == radius then return cached end

    local steps = math.max(32, math.min(64, math.ceil(radius * 2.5)))
    local thick = ringThickness(radius)
    local outline = circle(radius, 0.0, 360.0, steps)
    local chunks = {}

    outline[#outline] = nil

    local edge = stroke(outline, math.max(0.05, thick * 0.35), true, 'band')
    local centre = local2(0.0, 0.0)

    for segment = 1, steps do
        local index = math.ceil(segment / CHUNK)
        local chunk = chunks[index] or newChunk()

        chunks[index] = chunk

        if radius <= FILL_MOST then
            local a, b = outline[segment], outline[segment % steps + 1]

            addTri(chunk.fill, centre, local2(a[1], a[2]), local2(b[1], b[2]), false)
        end

        chunk.line[#chunk.line + 1] = edge[segment * 2 - 1]
        chunk.line[#chunk.line + 1] = edge[segment * 2]
    end

    local each = math.max(4, math.ceil(steps * ARC_SPAN / 360.0))

    for quarter = 0, 3 do
        local from = ARC_AT + quarter * 90.0 - ARC_SPAN * 0.5
        local bend = circle(radius - thick * 0.5, from, from + ARC_SPAN, each)
        local chunk = newChunk()

        chunk.glow = stroke(bend, thick * 3.0, false, 'soft')
        chunk.band = stroke(bend, thick, false, 'band')
        chunks[#chunks + 1] = chunk
    end

    for _, chunk in ipairs(chunks) do
        sphere(chunk)
    end

    cached = { radius = radius, thick = thick, chunks = chunks, seen = {} }
    spec.shape = cached

    return cached
end

local function round(spec, x, y, z, colour, alpha, dictionary)
    local radius = math.max(0.5, tonumber(spec.radius) or 1.0)
    local shape = ringShape(spec, radius)

    if not inView(x, y, z, radius + shape.thick * 2.0) then return end

    local up = facing(z)
    local seen = shape.seen

    for index, chunk in ipairs(shape.chunks) do
        seen[index] = inView(x + chunk.x, y + chunk.y, z, chunk.radius)
    end

    for _, layer in ipairs(LAYERS) do
        local name = layer.name
        local share = math.floor(alpha * layer.share + 0.5)

        for index, chunk in ipairs(shape.chunks) do
            if seen[index] then
                for _, tri in ipairs(chunk[name]) do
                    local a, b, c = tri[1], tri[2], tri[3]

                    if not up then
                        a, c = c, a
                    end

                    if tri[4] then
                        DrawTexturedPoly(
                            x + a.x, y + a.y, z,
                            x + b.x, y + b.y, z,
                            x + c.x, y + c.y, z,
                            colour[1], colour[2], colour[3], share,
                            dictionary, tri[4],
                            a.u, a.v, 1.0,
                            b.u, b.v, 1.0,
                            c.u, c.v, 1.0
                        )
                    else
                        DrawPoly(x + a.x, y + a.y, z, x + b.x, y + b.y, z, x + c.x, y + c.y, z, colour[1], colour[2], colour[3], share)
                    end
                end
            end
        end
    end
end

local function outer(spec, size)
    if spec.style == 'round' then return (tonumber(spec.radius) or 1.0) * 2.0 end
    if spec.style == 'zone' then return size end

    return math.max(tonumber(spec.width) or Marker.BOX.least, tonumber(spec.length) or Marker.BOX.least)
end

function Marker.draw(spec, now)
    now = now or GetGameTimer()
    look(now)

    local style = STYLES[spec.style] or STYLES.box
    local x, y, z = spec.x + 0.0, spec.y + 0.0, spec.z + LIFT
    local colour = colourOf(spec)
    local share = tonumber(spec.alpha) or style.alpha
    local alpha = math.floor(math.max(0.0, math.min(1.0, share)) * 255 + 0.5)
    local size = tonumber(spec.size) or style.size or 1.0

    if style.scaled then
        size = size * Marker.scale
    end

    local dictionary = Marker.mode == 'poly' and textures() or nil

    if not dictionary then
        plainRing(x, y, z, outer(spec, size), colour, alpha)

        return
    end

    if spec.style == 'zone' then
        zone(spec, x, y, z, size, colour, alpha, dictionary)
    elseif spec.style == 'round' then
        round(spec, x, y, z, colour, alpha, dictionary)
    else
        box(spec, x, y, z, colour, alpha, dictionary, now)
    end
end

function Marker.footprint(model)
    if type(model) ~= 'string' and type(model) ~= 'number' then return nil end

    local known = footprints[model]

    if known and known.width then return known end
    if known and GetGameTimer() < known.retry then return nil end

    local low, high = GetModelDimensions(type(model) == 'number' and model or joaat(model))

    if low and high and high.x - low.x > 0.01 and high.y - low.y > 0.01 then
        known = { width = high.x - low.x, length = high.y - low.y, x = (low.x + high.x) * 0.5, y = (low.y + high.y) * 0.5 }
    else
        known = { retry = GetGameTimer() + RETRY_MS }
    end

    footprints[model] = known

    return known.width and known or nil
end

function Marker.fit(mark, model, point)
    local size = Marker.footprint(model)
    local heading = (tonumber(point.w) or 0.0) + 0.0
    local turn = math.rad(heading)
    local c, s = math.cos(turn), math.sin(turn)
    local ox, oy = size and size.x or 0.0, size and size.y or 0.0
    local limits = Marker.BOX

    mark.style = 'box'
    mark.x = point.x + ox * c - oy * s
    mark.y = point.y + ox * s + oy * c
    mark.z = point.z
    mark.heading = heading
    mark.width = math.max(limits.least, math.min(limits.most, (size and size.width or 0.0) + limits.margin * 2.0))
    mark.length = math.max(limits.least, math.min(limits.most, (size and size.length or 0.0) + limits.margin * 2.0))

    return mark
end

local function nearby(marks, list, centre, now)
    local store = marks.near

    if not store then
        store = { list = {}, byEntry = {} }
        marks.near = store
    end

    local at, rule = store.at, Marker.NEAR

    if at and store.source == list and now - store.time < rule.every then
        local dx, dy, dz = centre.x - at.x, centre.y - at.y, centre.z - at.z

        if dx * dx + dy * dy + dz * dz <= rule.moved * rule.moved then
            return store.list
        end
    end

    store.time, store.source, store.at = now, list, { x = centre.x, y = centre.y, z = centre.z }

    local found, range = {}, rule.range * rule.range

    for _, entry in ipairs(list) do
        if type(entry) == 'table' and tonumber(entry.x) and tonumber(entry.y) and tonumber(entry.z) then
            local dx, dy, dz = entry.x - centre.x, entry.y - centre.y, entry.z - centre.z
            local distance = dx * dx + dy * dy + dz * dz

            if distance <= range then
                found[#found + 1] = { entry = entry, distance = distance }
            end
        end
    end

    table.sort(found, function(a, b) return a.distance < b.distance end)

    local chosen, byEntry = {}, {}

    for index = 1, math.min(#found, rule.most) do
        local entry = found[index].entry
        local mark = store.byEntry[entry] or {}

        Marker.fit(mark, entry.model, { x = entry.x, y = entry.y, z = entry.z, w = tonumber(entry.w) or tonumber(entry.h) or 0.0 })
        mark.entry = entry
        byEntry[entry] = mark
        chosen[#chosen + 1] = mark
    end

    store.list, store.byEntry = chosen, byEntry

    return chosen
end

function Marker.placement(marks, input, now)
    now = now or GetGameTimer()

    local camera = look(now).camera
    local point = input.point
    local others = input.others

    if type(others) == 'table' and #others > 0 then
        for _, mark in ipairs(nearby(marks, others, point or camera, now)) do
            local blocks = input.blocker ~= nil and mark.entry == input.blocker

            mark.tone = blocks and 'bad' or 'neutral'
            mark.alpha = blocks and BLOCKER_ALPHA or NEIGHBOUR_ALPHA
            Marker.draw(mark, now)
        end
    end

    if not point then return end

    local tone, accent = input.tone, input.accent
    local radius = tonumber(input.ring)

    if radius and radius > 0 then
        local ring = marks.ring or { style = 'round' }

        marks.ring = ring
        ring.x, ring.y, ring.z, ring.radius, ring.tone, ring.accent = point.x, point.y, point.z, radius, tone, accent
        Marker.draw(ring, now)
    end

    local stand = input.stand

    if input.model then
        local mark = Marker.fit(marks.box or {}, input.model, point)

        marks.box = mark
        mark.tone, mark.accent = tone, accent
        mark.arrows = input.front == true and not (stand and math.abs(stand.z - point.z) < LEVEL)
        Marker.draw(mark, now)
    end

    if stand then
        local mark = marks.stand or { style = 'zone', icon = 'person' }

        marks.stand = mark
        mark.x, mark.y, mark.z = stand.x, stand.y, stand.z
        mark.heading, mark.size = tonumber(stand.w) or tonumber(point.w) or 0.0, Marker.STAND
        mark.tone, mark.accent = tone, accent
        Marker.draw(mark, now)
    end
end

return Marker
