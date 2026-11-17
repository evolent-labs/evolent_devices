local Config = require 'config'
local Util = require 'shared.util'
local DeviceRules = require 'shared.rules'
local DeviceWorld = require 'client.world'
local DeviceIdle = require 'client.idle'
local DeviceUse = require 'client.use'
local Tablet = require 'client.tablet'
local DeviceNotices = require 'client.notices'

local DeviceLight = {}

local SCAN_MS = 250
local STEP_MS = 100
local INNER_CONE, FALLOFF = 0.0, 1.0

local lights = {}
local held = {}

local yes = Util.yes

local function settings()
    local config = Config.devices

    if type(config) ~= 'table' then return nil end

    local light = config.light

    if type(light) ~= 'table' or light.enabled == false or not Util.isFinite(light.range) then return nil end
    if not Util.isFinite(light.max) or light.max < 1 then return nil end

    return light
end

local function ownKey()
    local stage = DeviceUse.stage()

    if stage == nil or stage == 'connecting' then return nil end

    return DeviceUse.key()
end

local function inView(at, range)
    return yes(IsSphereVisible(at.x + 0.0, at.y + 0.0, at.z + 0.0, range))
end

local function before(a, b)
    if a.rank ~= b.rank then
        return a.rank < b.rank
    end

    if a.distance ~= b.distance then
        return a.distance < b.distance
    end

    return a.key < b.key
end

local function flashing(key, now)
    return DeviceNotices ~= nil and DeviceNotices.flashing(key, now)
end

local function flash(key, now)
    return DeviceNotices ~= nil and DeviceNotices.flash(key, now) or 0.0
end

local function candidates(config)
    local list = {}

    if next(DeviceWorld.spawned) == nil then
        return list
    end

    local now = GetGameTimer()
    local eye = GetFinalRenderedCamCoord()
    local night = DeviceRules.night(GetClockHours(), config.night)
    local own = ownKey()

    for key, record in pairs(DeviceWorld.spawned) do
        local light = DeviceIdle.light(record)

        if light and DoesEntityExist(record.entity) and yes(IsEntityVisible(record.entity)) then
            local mine = key == own
            local distance = #(eye - record.at)
            local near = mine or distance <= config.range
            local inUse = near and (mine or DeviceWorld.busy(key))
            local dark = not inUse and DeviceIdle.asleep(key)
            local goal = (near and not dark) and DeviceRules.lightGoal(light, inUse, night) or 0.0
            local blinking = near and flashing(key, now)
            local current = lights[key]

            if current and current.entity ~= record.entity then
                current = nil
            end

            if goal > 0 or blinking or (current and current.level > 0) then
                list[#list + 1] = {
                    key = key,
                    record = record,
                    light = light,
                    goal = goal,
                    blinking = blinking,
                    mine = mine,
                    current = current,
                    distance = distance,
                    rank = DeviceRules.lightRank(mine, inUse, blinking and math.max(goal, light.intensity) or goal),
                }
            end
        end
    end

    table.sort(list, before)

    return list
end

local function scan()
    local config = settings()
    local list = config and candidates(config) or {}
    local max = config and math.floor(config.max) or 0
    local keep, slots = {}, 0

    for _, wanted in ipairs(list) do
        local record, current = wanted.record, wanted.current
        local slot = (wanted.goal > 0 or wanted.blinking) and slots < max

        if slot and not current then
            local at, direction = DeviceRules.lightSpot(DeviceWorld.corners(record), wanted.light)

            current = { entity = record.entity, level = 0.0, at = at, direction = direction }
        end

        if current then
            current.light, current.mine = wanted.light, wanted.mine

            if slot and (wanted.mine or inView(current.at, wanted.light.range)) then
                slots = slots + 1
                current.goal, current.hidden = wanted.goal, false
            elseif slot then
                current.goal, current.hidden = math.min(current.level, wanted.goal), true
            else
                if current.hidden then
                    current.level = 0.0
                end

                current.goal, current.hidden = 0.0, false
            end

            if current.goal > 0 or current.level > 0 or wanted.blinking then
                keep[wanted.key] = current
            end
        end
    end

    lights = keep
end

local function tabletLight()
    local light = Config.tablet.light

    if type(light) ~= 'table' or light.enabled == false then return nil end

    return light
end

local function byDistance(a, b)
    if a.own ~= b.own then
        return a.own
    end

    return a.distance < b.distance
end

local function scanTablets()
    local light = tabletLight()
    local keep = {}
    local lit = light and Tablet.lit() or {}

    if lit[1] then
        local eye = GetFinalRenderedCamCoord()
        local list = {}

        for _, entry in ipairs(lit) do
            if DoesEntityExist(entry.prop) then
                entry.distance = #(eye - GetEntityCoords(entry.prop))

                if entry.own or entry.distance <= light.viewRange then
                    list[#list + 1] = entry
                end
            end
        end

        table.sort(list, byDistance)

        for index = 1, math.min(#list, light.max) do
            local entry = list[index]
            local current = held[entry.key]

            if not current or current.prop ~= entry.prop then
                current = { prop = entry.prop, level = 0.0 }
            end

            current.goal, current.own = light.intensity, entry.own
            keep[entry.key] = current
        end
    end

    for key, current in pairs(held) do
        if not keep[key] and current.level > 0 and DoesEntityExist(current.prop) then
            current.goal = 0.0
            keep[key] = current
        end
    end

    held = keep
end

local function drawTablets(elapsed)
    if next(held) == nil then return false end

    local light = tabletLight()
    local fade = light and tonumber(light.fadeMs) or 0

    for key, current in pairs(held) do
        current.level = DeviceRules.fadeTo(
            current.level,
            current.goal,
            light and fade > 0 and light.intensity * elapsed / fade or math.huge
        )

        if not DoesEntityExist(current.prop) or (current.level <= 0 and current.goal <= 0) then
            held[key] = nil
        elseif light and current.level > 0 then
            local at = GetOffsetFromEntityInWorldCoords(current.prop, 0.0, -light.offset, 0.0)

            if current.own or inView(at, light.range) then
                local aim = GetOffsetFromEntityInWorldCoords(current.prop, 0.0, -light.offset - 1.0, 0.0)

                DrawSpotLight(
                    at.x + 0.0,
                    at.y + 0.0,
                    at.z + 0.0,
                    aim.x - at.x + 0.0,
                    aim.y - at.y + 0.0,
                    aim.z - at.z + 0.0,
                    light.color[1],
                    light.color[2],
                    light.color[3],
                    light.range,
                    current.level + 0.0,
                    INNER_CONE,
                    light.cone,
                    FALLOFF
                )
            end
        end
    end

    return true
end

local function woke()
    for _, current in pairs(lights) do
        if current.hidden and inView(current.at, current.light.range) then return true end
    end

    return false
end

local function draw(elapsed)
    if next(lights) == nil then return false end

    local config = settings()
    local fade = config and tonumber(config.fadeMs) or 0
    local now = GetGameTimer()

    for key, current in pairs(lights) do
        local light = current.light

        current.level = DeviceRules.fadeTo(
            current.level,
            current.goal,
            fade > 0 and light.intensity * elapsed / fade or math.huge
        )

        local shown = math.max(current.level, light.intensity * flash(key, now))

        if current.level <= 0 and current.goal <= 0 and not flashing(key, now) then
            lights[key] = nil
        elseif shown > 0 and not current.hidden and (current.mine or inView(current.at, light.range)) then
            local at, direction = current.at, current.direction

            DrawSpotLight(
                at.x + 0.0,
                at.y + 0.0,
                at.z + 0.0,
                direction.x + 0.0,
                direction.y + 0.0,
                direction.z + 0.0,
                light.r,
                light.g,
                light.b,
                light.range,
                shown + 0.0,
                INNER_CONE,
                light.cone,
                FALLOFF
            )
        end
    end

    return true
end

DeviceWorld.on('despawn', function(record)
    lights[record.key] = nil
end)

CreateThread(function()
    local last, nextScan, active = GetGameTimer(), 0, false

    while not DeviceWorld.isStopping() do
        local now = GetGameTimer()

        if now >= nextScan or woke() then
            nextScan = now + SCAN_MS
            scan()
            scanTablets()
        end

        local elapsed = active and math.min(STEP_MS, math.max(0, now - last)) or 0
        local screens = draw(elapsed)
        local tablets = drawTablets(elapsed)

        active = screens or tablets
        last = now
        Wait(active and 0 or SCAN_MS)
    end
end)

return DeviceLight
