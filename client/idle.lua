local Config = require 'config'
local Bridge = require 'bridge'
local Util = require 'shared.util'
local ScreenRules = require 'shared.screen'
local DeviceRules = require 'shared.rules'
local BrandRules = require 'shared.brand'
local LookRules = require 'shared.look'
local DeviceWorld = require 'client.world'
local DeviceScreens = require 'client.screens'
local DeviceBrand = require 'client.brand'

local DeviceIdle = {}

local PAGE = 'web/build/idle.html'
local TICK_MS = 250
local SOON_MS = 50
local HAND_BACK_MS = 6000
local READY_MS = 8000
local PAINT_MS = 4000
local DETAIL = 1.41
local STAMP = GetGameTimer()
local resource = GetCurrentResourceName()

local slots = {}
local darks = {}
local nearest = {}
local since, wasBusy, asleep = {}, {}, {}
local handed = {}
local serial = 0
local stopping = false
local soon = false

function DeviceIdle.handBack(model)
    if type(model) ~= 'string' then return end

    handed[model] = GetGameTimer()
    soon = true
end

local function handedBack(model, now)
    local at = handed[model]

    if at and now - at <= HAND_BACK_MS then return true end

    handed[model] = nil

    return false
end

local function config()
    local idle = type(Config.devices) == 'table' and Config.devices.idle or nil

    return type(idle) == 'table' and idle or {}
end

local function liveConfig()
    local live = config().live

    if type(live) ~= 'table' or live.enabled == false or not Util.integer(live.max, 1) then return nil end

    return live
end

local function darkConfig()
    local dark = config().dark

    if type(dark) ~= 'table' or dark.enabled == false or not Util.integer(dark.max, 1) then return nil end

    return dark
end

local yes = Util.yes

function DeviceIdle.settings(record)
    if record.screenFor ~= record.screen or record.displayFor ~= DeviceWorld.display or record.wallsFor ~= BrandRules.walls or not record.screenValue then
        record.screenFor, record.displayFor, record.wallsFor = record.screen, DeviceWorld.display, BrandRules.walls
        record.screenValue = ScreenRules.resolve(record.kind, record.screen, DeviceWorld.display)
    end

    return record.screenValue
end

local clockAt, clockMinute = nil, 0

local function minuteOfDay(now)
    if now ~= clockAt then
        clockAt, clockMinute = now, GetClockHours() * 60 + GetClockMinutes()
    end

    return clockMinute
end

local function idleMs(record, now)
    local key = record.key

    if DeviceWorld.busy(key) then
        wasBusy[key], since[key] = true, nil

        return 0
    end

    if wasBusy[key] then
        wasBusy[key], since[key] = nil, now
    end

    local from = math.max(
        since[key] or -math.huge,
        record.usedAt or -math.huge,
        DeviceWorld.lastUseEnded(key) or -math.huge
    )

    if from == -math.huge then
        since[key] = now
        from = now
    end

    return now - from
end

function DeviceIdle.state(record, now)
    if DeviceWorld.busy(record.key) then
        idleMs(record, now)

        return 'busy', DeviceIdle.settings(record)
    end

    local value = DeviceIdle.settings(record)

    if record.enabled == false or record.oos then
        return 'oos', value
    end

    now = now or GetGameTimer()

    local rest = ScreenRules.rest(value, idleMs(record, now), minuteOfDay(now))

    if rest then
        return rest, value
    end

    return 'idle', value
end

function DeviceIdle.wake(key, now)
    if key == nil then return end

    since[key] = now or GetGameTimer()
end

local function walkers(centre, radius)
    local list = {}

    for _, player in ipairs(GetActivePlayers()) do
        local ped = GetPlayerPed(player)

        if ped and ped ~= 0 and DoesEntityExist(ped) then
            local at = GetEntityCoords(ped)

            if #(at - centre) <= radius then
                list[#list + 1] = at
            end
        end
    end

    if #list == 0 then
        list[1] = GetEntityCoords(cache.ped)
    end

    return list
end

local function reachOf(record)
    local use = record.spec and record.spec.use

    return type(use) == 'table' and tonumber(use.reach) or nil
end

local function reached(record, points)
    local reach = reachOf(record)

    if not reach then return false end

    local at = record.at

    for _, point in ipairs(points) do
        if #(point - at) <= reach and GetOffsetFromEntityGivenWorldCoords(record.entity, point.x, point.y, point.z).y < -0.05 then
            return true
        end
    end

    return false
end

function DeviceIdle.approached(record, points)
    return DoesEntityExist(record.entity) and reached(record, points)
end

function DeviceIdle.asleep(key)
    return asleep[key] == true
end

function DeviceIdle.light(record)
    local light = DeviceRules.light(record.spec)

    return ScreenRules.light(light, DeviceIdle.settings(record), LookRules.light(record))
end

local function words()
    return {
        oos = locale('idle_oos'),
        oosLine = locale('idle_oos_line'),
        unread = locale('idle_unread'),
        unreadOne = locale('idle_unread_one'),
    }
end

local send = DeviceWorld.tellPage

local function holderOf(model, kind)
    return { model = model, target = DeviceRules.screenTexture(model), idle = true, kind = kind }
end

local function own(holder)
    return holder ~= nil and DeviceScreens.holder(holder.model) == holder
end

local function create(kind, spec)
    serial = serial + 1

    local slot = { kind = kind, spec = spec, phase = 'free', freeSince = GetGameTimer() }

    DeviceWorld.startPage(slot, ('idle_%d_%d'):format(STAMP, serial), 'evdev_idle_', function(page)
        return ('https://cfx-nui-%s/%s?host=%s&kind=%s&width=%d&height=%d&browser=%s#s=%s'):format(
            resource,
            PAGE,
            resource,
            kind,
            spec.dui.width,
            spec.dui.height,
            page.browser,
            page.secret
        )
    end, spec.dui.width, spec.dui.height)

    slots[#slots + 1] = slot

    return slot
end

local function letGo(slot)
    if slot.holder then
        DeviceScreens.release(slot.holder)
    end

    slot.holder, slot.key, slot.record, slot.lookKey, slot.painted, slot.size = nil, nil, nil, nil, nil, nil
    slot.phase, slot.freeSince = 'free', GetGameTimer()
end

local function destroy(slot)
    if slot.destroyed then return end

    letGo(slot)
    slot.destroyed = true
    DeviceWorld.endPage(slot)

    for index = #slots, 1, -1 do
        if slots[index] == slot then
            table.remove(slots, index)
        end
    end
end

function DeviceIdle.shownSize(record)
    local corners = DeviceWorld.corners(record)
    local width, height = GetActiveScreenResolution()
    local points = {}

    for name, point in pairs(corners) do
        local onScreen, x, y = GetScreenCoordFromWorldCoord(point.x + 0.0, point.y + 0.0, point.z + 0.0)

        if not yes(onScreen) then
            points = nil
            break
        end

        points[name] = { x = x * width, y = y * height }
    end

    if points then
        local function gap(a, b)
            return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2)
        end

        return math.max(gap(points.TL, points.TR), gap(points.BL, points.BR)), math.max(
            gap(points.TL, points.BL),
            gap(points.TR, points.BR)
        )
    end

    local basis = DeviceRules.screenBasis(corners)

    local distance = math.max(
        0.05,
        #(GetFinalRenderedCamCoord() - vector3(basis.centre.x, basis.centre.y, basis.centre.z))
    )

    local scale = height / (2.0 * distance * math.tan(math.rad(GetFinalRenderedCamFov()) / 2.0))

    return basis.width * scale, basis.height * scale
end

function DeviceIdle.detail(holder, record, factor)
    local w, h = DeviceIdle.shownSize(record)
    local dui = holder.spec.dui
    local levels = holder.levels or {}

    factor = factor or DETAIL
    levels.w = ScreenRules.detailLevel(dui.width, w, factor, levels.w)
    levels.h = ScreenRules.detailLevel(dui.height, h, factor, levels.h)
    holder.levels = levels

    local width, height = ScreenRules.levelSize(dui.width, levels.w), ScreenRules.levelSize(dui.height, levels.h)
    local size = holder.size

    if size and size.w == width and size.h == height then return nil end

    holder.size = { w = width, h = height }

    return holder.size
end

local function detail(slot, live)
    local size = DeviceIdle.detail(slot, slot.record, live.detail)

    if size then
        send(slot, { type = 'detail', w = size.w, h = size.h })
    end
end

function DeviceIdle.unread(entry)
    local DeviceNotices = require 'client.notices'

    if not DeviceNotices or (entry.state ~= 'idle' and entry.state ~= 'sleep') then return nil end

    local count = DeviceNotices.count(entry.record.key)

    return count > 0 and count or nil
end

local function brandOf(record)
    return DeviceBrand.lightFor(record)
end

local function lookOf(entry)
    local brand = brandOf(entry.record)
    local look = ScreenRules.look(entry.record.kind, entry.value, (entry.state == 'oos' or entry.state == 'sleep') and entry.state or 'idle', brand)

    look.unread = DeviceIdle.unread(entry)

    return look, ScreenRules.lookKey(look) .. '\31' .. brand.accent .. '\31' .. brand.name, brand
end

local function draw(slot, entry, live, show, fadeMs)
    local look, key, brand = lookOf(entry)

    serial = serial + 1
    slot.serial, slot.lookKey, slot.painted, slot.paintSince = serial, key, false, GetGameTimer()
    detail(slot, live)

    send(slot, {
        type = 'look',
        serial = serial,
        show = show,
        fadeMs = fadeMs or live.fadeMs or 350,
        look = look,
        upscale = live.upscale or 'smooth',
        base = ScreenRules.look(entry.record.kind, ScreenRules.defaults(entry.record.kind, DeviceWorld.display), 'idle'),
        words = words(),
        brand = brand,
    })
end

local function assign(slot, entry, live)
    letGo(slot)
    slot.key, slot.record, slot.model = entry.key, entry.record, entry.record.model
    slot.holder = holderOf(entry.record.model, slot.kind)
    slot.phase = 'drawing'

    if handedBack(entry.record.model, GetGameTimer()) then
        slot.cut = true
        draw(slot, entry, live, true, 0)
    else
        slot.cut = nil
        draw(slot, entry, live, false)
    end
end

local function step(slot, entry, live, now)
    if slot.phase == 'leaving' then
        if now >= slot.leaveAt then
            letGo(slot)
        end

        return
    end

    if not slot.pageReady or not DeviceWorld.pageTexture(slot, now) then return end

    if slot.holder and slot.phase == 'shown' and not own(slot.holder) then
        letGo(slot)

        return
    end

    if not entry then return end

    if slot.key ~= entry.key or slot.record ~= entry.record then
        assign(slot, entry, live)

        return
    end

    detail(slot, live)

    if slot.phase == 'drawing' then
        if slot.painted then
            if DeviceScreens.claim(slot.holder, slot.txdName) then
                slot.phase = 'shown'
                send(slot, { type = 'show' })
            end
        elseif now - slot.paintSince > PAINT_MS then
            draw(slot, entry, live, slot.cut == true, slot.cut and 0 or nil)
        end

        return
    end

    local _, key = lookOf(entry)

    if key ~= slot.lookKey then
        draw(slot, entry, live, true)
    end
end

local function leave(slot, live, now)
    if slot.phase == 'shown' and own(slot.holder) then
        send(slot, { type = 'leave' })
        slot.phase, slot.leaveAt = 'leaving', now + (live and live.fadeMs or 0)
    elseif slot.phase ~= 'free' and slot.phase ~= 'leaving' then
        letGo(slot)
    end
end

local function rangeOf(live, kind)
    return type(live.range) == 'table' and Util.number(live.range[kind], 0) or 0
end

local function free(model, record)
    local holder = DeviceScreens.holder(model)

    return not (holder and not holder.idle and not holder.destroyed)
end

local function shown(record)
    return record.spec and record.model and DeviceRules.screenMode(record.spec) == 'world' and DoesEntityExist(record.entity)
end

local function nearestByModel(now, eye)
    local list = {}
    local seen = {}
    local visible = {}
    local here, range = nil, 0.0

    for key, record in pairs(DeviceWorld.spawned) do
        if shown(record) then
            here = here or GetEntityCoords(cache.ped)
            visible[key] = record
            range = math.max(range, #(record.at - here) + (reachOf(record) or 0.0))
        end
    end

    local points = here and walkers(here, range)

    for key, record in pairs(visible) do
        if reached(record, points) then
            DeviceIdle.wake(key, now)
        end

        local state, value = DeviceIdle.state(record, now)

        seen[key] = true
        asleep[key] = (state == 'off' or state == 'sleep') or nil

        local distance = #(eye - record.at)
        local best = list[record.model]

        if not best or distance < best.distance then
            list[record.model] = { key = key, record = record, state = state, value = value, distance = distance }
        end
    end

    for key in pairs(asleep) do
        if not seen[key] then
            asleep[key] = nil
        end
    end

    return list
end

local function slotFor(key)
    for _, slot in ipairs(slots) do
        if slot.key == key and slot.phase ~= 'leaving' then
            return slot
        end
    end

    return nil
end

local function wantsLive(entry)
    if entry.state == 'busy' then
        return entry.record.kind == 'terminal'
    end

    return entry.state == 'idle' or entry.state == 'oos' or entry.state == 'sleep'
end

local function pickLive(models, live, eye)
    local chosen = {}

    if not live then
        return chosen
    end

    local keep = Util.number(live.keep, 0) or 0

    for model, entry in pairs(models) do
        if wantsLive(entry) and free(model, entry.record) then
            local current = slotFor(entry.key)
            local limit = rangeOf(live, entry.record.kind) + (current and keep or 0)

            if entry.distance <= limit and (current or DeviceRules.facing(DeviceWorld.corners(entry.record), eye)) then
                entry.rank = entry.distance - (current and keep or 0)
                chosen[#chosen + 1] = entry
            end
        end
    end

    table.sort(chosen, function(a, b)
        if a.rank ~= b.rank then
            return a.rank < b.rank
        end

        return tostring(a.key) < tostring(b.key)
    end)

    for index = #chosen, live.max + 1, -1 do
        chosen[index] = nil
    end

    return chosen
end

local function placeLive(chosen, live, now)
    local wanted, taken = {}, {}

    for _, entry in ipairs(chosen) do
        wanted[entry.key] = entry
    end

    for _, slot in ipairs(slots) do
        if slot.key and wanted[slot.key] and slot.phase ~= 'leaving' then
            taken[slot.key] = slot
        elseif slot.key then
            leave(slot, live, now)
        end
    end

    for _, entry in ipairs(chosen) do
        if not taken[entry.key] then
            local pick

            for _, slot in ipairs(slots) do
                if not slot.key and not slot.pending and slot.phase == 'free' and slot.kind == entry.record.kind then
                    pick = slot
                    break
                end
            end

            if not pick and #slots >= live.max then
                for _, slot in ipairs(slots) do
                    if not slot.key and not slot.pending and slot.phase == 'free' then
                        destroy(slot)
                        break
                    end
                end
            end

            if not pick and #slots < live.max then
                pick = create(entry.record.kind, entry.record.spec)
            end

            if pick then
                pick.key, pick.record = nil, nil
                taken[entry.key] = pick
                pick.pending, pick.wantedAt = entry, now
            end
        end
    end

    for _, slot in ipairs(slots) do
        local entry = slot.pending or (slot.key and wanted[slot.key]) or nil

        slot.pending = nil
        step(slot, entry, live, now)
    end
end

local function neutralOf(record)
    local preset = ScreenRules.presets(record.kind)[1]

    return type(preset) == 'table' and preset.neutral == true and LookRules.neutral(record, DeviceBrand.light())
end

local function ownPicture(entry)
    local wall = ScreenRules.lookWall(entry.record.kind, entry.value, brandOf(entry.record))

    return wall ~= nil and wall.own == true
end

local function faceFor(entry)
    local size = entry.record.spec.textureSize

    if entry.state == 'off' then
        return DeviceScreens.blank(size)
    end

    if ownPicture(entry) then
        return entry.state == 'sleep' and DeviceScreens.blank(size) or nil
    end

    local neutral = neutralOf(entry.record)
    local face = DeviceScreens.stillFace(entry.record.kind, size, entry.state == 'sleep', neutral)

    if not face and entry.state == 'sleep' and neutral then
        face = DeviceScreens.stillFace(entry.record.kind, size, true, false)
    end

    if not face and entry.state == 'sleep' then
        face = DeviceScreens.blank(size)
    end

    return face
end

local function darkWanted(entry, live)
    if entry.state == 'off' then return true end
    if live[entry.key] then return false end
    if entry.state == 'sleep' then return true end

    return (entry.state == 'idle' or entry.state == 'oos' or entry.state == 'busy') and neutralOf(entry.record) and not ownPicture(entry)
end

local function placeDark(models, dark, live)
    local list = {}

    if dark then
        for model, entry in pairs(models) do
            if darkWanted(entry, live) and free(model, entry.record) then
                list[#list + 1] = entry
            end
        end

        table.sort(list, function(a, b) return a.distance < b.distance end)
    end

    local wanted = {}

    for index = 1, math.min(#list, dark and dark.max or 0) do
        wanted[list[index].record.model] = list[index]
    end

    for model, holder in pairs(darks) do
        if not wanted[model] then
            DeviceScreens.release(holder)
            darks[model] = nil
        end
    end

    for model, entry in pairs(wanted) do
        local face = faceFor(entry)

        if face then
            local holder = darks[model] or holderOf(model, entry.record.kind)

            darks[model] = holder

            if DeviceScreens.holder(model) ~= holder or holder.face ~= face then
                DeviceScreens.claim(holder, face)
            end
        elseif darks[model] then
            DeviceScreens.release(darks[model])
            darks[model] = nil
        end
    end
end

local function sweep(live, now)
    local linger = live and Util.integer(live.lingerMs, 0) or 0

    for index = #slots, 1, -1 do
        local slot = slots[index]

        if not slot.pageReady and now - slot.created > READY_MS then
            destroy(slot)
        elseif not slot.key and slot.phase == 'free' and slot.wantedAt ~= now and (not live or now - math.max(slot.freeSince or slot.created, slot.wantedAt or 0) >= linger) then
            destroy(slot)
        end
    end
end

function DeviceIdle.tick(now)
    now = now or GetGameTimer()

    local eye = GetFinalRenderedCamCoord()
    local models = nearestByModel(now, eye)
    local live, dark = liveConfig(), darkConfig()

    nearest = models
    local chosen = pickLive(models, live, eye)
    local lively = {}

    for _, slot in ipairs(slots) do
        if slot.key ~= nil and slot.phase == 'shown' and own(slot.holder) then
            lively[slot.key] = true
        end
    end

    placeDark(models, dark, lively)
    placeLive(chosen, live or { max = 0, fadeMs = 0 }, now)
    sweep(live, now)
end

function DeviceIdle.nearest(model)
    local entry = nearest[model]

    if not entry or DeviceWorld.spawned[entry.key] ~= entry.record or not DoesEntityExist(entry.record.entity) then return nil end

    return entry.record
end

function DeviceIdle.status()
    local list = { live = {}, dark = {} }

    for _, slot in ipairs(slots) do
        list.live[#list.live + 1] = {
            key = slot.key,
            kind = slot.kind,
            model = slot.holder and slot.holder.model or nil,
            phase = slot.phase,
            size = slot.size,
            browser = slot.browser,
            dui = slot.dui,
        }
    end

    for model in pairs(darks) do
        list.dark[#list.dark + 1] = model
    end

    table.sort(list.dark)

    return list
end

local function clear()
    for index = #slots, 1, -1 do
        destroy(slots[index])
    end

    for model, holder in pairs(darks) do
        DeviceScreens.release(holder)
        darks[model] = nil
    end

    since, wasBusy, asleep, handed, nearest = {}, {}, {}, {}, {}
end

RegisterNUICallback('device:painted', function(data, respond)
    respond({ ok = true })

    if type(data) ~= 'table' then return end

    for _, slot in ipairs(slots) do
        if slot.browser == tostring(data.browser) and data.s == slot.secret then
            if data.serial == slot.serial then
                slot.painted = true
            end

            return
        end
    end
end)

Bridge.onLogout(clear)

CreateThread(function()
    local nextAt = 0
    local quiet = false

    while not stopping do
        Wait(quiet and not soon and TICK_MS or SOON_MS)

        if stopping then return end

        local now = GetGameTimer()

        if soon or now >= nextAt then
            soon, nextAt = false, now + TICK_MS

            local ok, failure = pcall(DeviceIdle.tick, now)

            if not ok then
                print(('[evolent_devices] idle screens failed: %s'):format(tostring(failure)))
            end

            quiet = next(DeviceWorld.spawned) == nil and slots[1] == nil and next(darks) == nil
        end
    end
end)

AddEventHandler('onResourceStop', function(name)
    if name ~= resource then return end

    stopping = true
    clear()
end)

return DeviceIdle
