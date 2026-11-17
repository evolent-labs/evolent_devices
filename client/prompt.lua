local Prompt = {
    send = function(message)
        SendNUIMessage(message)
    end,
    range = 12.0,
    lift = 0.0,
}

local entries = {}
local order = 0
local shown = nil
local watching = false
local HOLD_MS, PIXEL, SIZE_MS = 50, 1.0, 1000
local size = { width = 1920, height = 1080, at = nil }

local function clean(value)
    if type(value) == 'string' then return value end
    if type(value) == 'number' then return tostring(value) end

    return nil
end

local function keysOf(option)
    local keys = option.keys or option.key

    if type(keys) == 'table' then
        local list = {}

        for _, key in ipairs(keys) do
            list[#list + 1] = clean(key)
        end

        return list
    end

    return { clean(keys) }
end

local function view(data)
    local options = {}

    for _, option in ipairs(data.options or {}) do
        if type(option) == 'table' and clean(option.label) then
            options[#options + 1] = {
                keys = keysOf(option),
                label = clean(option.label),
                main = option.main == true,
                off = option.off == true,
            }
        end
    end

    return {
        title = clean(data.title),
        context = clean(data.context),
        options = options,
        why = clean(data.why),
        icon = clean(data.icon),
        cue = clean(data.cue),
        note = clean(data.note),
        cueIcon = clean(data.cueIcon),
        hold = type(data.hold) == 'table' and 0 or nil,
    }
end

local function anchorOf(data)
    local anchor = data.anchor

    if anchor == nil then return nil end

    local lift = tonumber(data.lift) or Prompt.lift

    if type(anchor) == 'number' then
        if not DoesEntityExist(anchor) then return nil end

        local coords = GetEntityCoords(anchor)

        return coords.x, coords.y, coords.z + lift
    end

    if (type(anchor) == 'table' or type(anchor) == 'vector3' or type(anchor) == 'vector4') and anchor.x and anchor.y and anchor.z then
        return anchor.x + 0.0, anchor.y + 0.0, anchor.z + lift
    end

    return nil
end

local function project(data)
    local x, y, z = anchorOf(data)

    if not x then return nil end

    local camera = GetFinalRenderedCamCoord()
    local dx, dy, dz = camera.x - x, camera.y - y, camera.z - z

    if dx * dx + dy * dy + dz * dz > Prompt.range * Prompt.range then return nil end

    local visible, sx, sy = GetScreenCoordFromWorldCoord(x, y, z)

    if not visible or visible == 0 or sx < 0.0 or sx > 1.0 or sy < 0.0 or sy > 1.0 then return nil end

    return { x = math.floor(sx * 100000 + 0.5) / 100000, y = math.floor(sy * 100000 + 0.5) / 100000 }
end

local function screen(now)
    if not size.at or now - size.at >= SIZE_MS then
        local width, height = GetActiveScreenResolution()

        size.width = (tonumber(width) or 0) > 0 and width or size.width
        size.height = (tonumber(height) or 0) > 0 and height or size.height
        size.at = now
    end

    return size.width, size.height
end

local function top()
    local best = nil

    for _, entry in pairs(entries) do
        if not best or entry.priority > best.priority or (entry.priority == best.priority and entry.order > best.order) then
            best = entry
        end
    end

    return best
end

local function moved(a, b, now)
    if a == nil or b == nil then return a ~= b end

    local width, height = screen(now)

    return math.abs(a.x - b.x) * width > PIXEL or math.abs(a.y - b.y) * height > PIXEL
end

local function holdTick(state, now)
    local hold = state.entry.data.hold

    if type(hold) ~= 'table' or not hold.control then return end

    local down = IsControlPressed(0, hold.control) or IsDisabledControlPressed(0, hold.control)
    local ms = tonumber(hold.ms) or 800

    if down and not state.fired then
        state.since = state.since or now
    else
        state.since = nil
    end

    if not down then
        state.fired = false
    end

    local share = state.since and math.min(1.0, (now - state.since) / ms) or 0.0

    if share >= 1.0 and not state.fired then
        state.fired = true
        state.since = nil
        share = 0.0

        if type(hold.done) == 'function' then
            CreateThread(hold.done)
        end
    end

    if math.abs(share - (state.share or 0.0)) > 0.001 and (now - (state.holdAt or 0) >= HOLD_MS or share == 0.0) then
        state.share = share
        state.holdAt = now
        Prompt.send({ type = 'prompt', action = 'hold', id = state.id, hold = share })
    end
end

local function needsWatch(entry)
    return entry and (entry.data.anchor ~= nil or type(entry.data.hold) == 'table')
end

local function watch()
    if watching then return end

    watching = true

    CreateThread(function()
        while shown and needsWatch(shown.entry) do
            local now = GetGameTimer()
            local state = shown

            if state.entry.data.anchor ~= nil then
                local spot = project(state.entry.data)

                if moved(spot, state.spot, now) then
                    state.spot = spot
                    Prompt.send({ type = 'prompt', action = 'at', id = state.id, at = spot or false })
                end
            end

            holdTick(state, now)
            Wait(0)
        end

        watching = false
    end)
end

local function refresh()
    local entry = top()

    if not entry then
        if shown then
            Prompt.send({ type = 'prompt', action = 'hide', id = shown.id })
            shown = nil
        end

        return
    end

    if shown and shown.id == entry.id and shown.signature == entry.signature then
        shown.entry = entry

        return
    end

    local spot = entry.data.anchor ~= nil and project(entry.data) or nil

    shown = { id = entry.id, entry = entry, signature = entry.signature, spot = spot }
    Prompt.send({ type = 'prompt', action = 'show', id = entry.id, data = entry.view, at = spot or false })

    if needsWatch(entry) then
        watch()
    end
end

function Prompt.show(id, data, priority)
    if type(id) ~= 'string' or type(data) ~= 'table' then return end

    local sent = view(data)
    local signature = json.encode(sent)
    local entry = entries[id]

    if entry and entry.signature == signature and entry.priority == (priority or 0) then
        entry.data = data

        if shown and shown.id == id then
            shown.entry = entry

            if needsWatch(entry) then
                watch()
            end
        end

        return
    end

    order = order + 1
    entries[id] = { id = id, data = data, view = sent, signature = signature, priority = tonumber(priority) or 0, order = order }
    refresh()
end

Prompt.update = Prompt.show

function Prompt.hide(id)
    if id == nil then
        entries = {}
    elseif entries[id] then
        entries[id] = nil
    else
        return
    end

    refresh()
end

function Prompt.text(data)
    local lines = {}

    if type(data) ~= 'table' then return clean(data) or '' end

    if clean(data.title) then
        lines[#lines + 1] = clean(data.context) and ('%s, %s'):format(data.title, data.context) or data.title
    end

    for _, option in ipairs(data.options or {}) do
        local keys = table.concat(keysOf(option), ' ')
        local label = clean(option.label) or ''

        lines[#lines + 1] = keys ~= '' and ('[%s] %s'):format(keys, label) or label
    end

    if clean(data.why) then
        lines[#lines + 1] = data.why
    end

    if clean(data.cue) then
        lines[#lines + 1] = clean(data.note) and ('%s %s'):format(data.cue, data.note) or data.cue
    end

    return table.concat(lines, '  \n')
end

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end

    entries = {}
    shown = nil
end)

return Prompt
