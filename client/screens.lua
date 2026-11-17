local Config = require 'config'
local Bridge = require 'bridge'
local Util = require 'shared.util'
local ScreenRules = require 'shared.screen'
local DeviceRules = require 'shared.rules'
local OsRules = require 'shared.os'
local Client = require 'client.main'
local DeviceWorld = require 'client.world'

local DeviceScreens = { LOCALE_PREFIXES = { 'os_', 'kind_', 'brand', 'reason_' } }

local TEXTURE = DeviceWorld.PAGE_TEXTURE
local QUEUE = 16
local LOG = 64
local WATCH_RETRY_MS = 2000
local STATE_WAIT_MS = 500
local OUT_OF_SERVICE = 'web/build/out_of_service.html'
local STAMP = GetGameTimer()
local resource = GetCurrentResourceName()

local serial = 0
local own, spare, watch = nil, nil, nil
local bound = {}
local blanks = {}
local faces = {}
local osStrings = nil
local stopping = false

local function brandView(record, view)
    local DeviceBrand = require 'client.brand'

    return DeviceBrand.viewFor(record, view)
end

local function settings()
    return Config.devices
end

local function modelOf(record)
    return record.model or DeviceRules.baseModel(record.spec)
end

local function inWorld(screen)
    return DeviceRules.screenMode(screen.spec) == 'world'
end

local function cleanPage(page)
    if type(page) ~= 'table' or type(page.resource) ~= 'string' or type(page.path) ~= 'string' then return nil end
    if not page.resource:find('^[%w_%-]+$') or not page.path:find('^[%w_/%-%.]+%.html$') then return nil end
    if page.path:find('..', 1, true) then return nil end

    local app = type(page.app) == 'string' and page.app:find('^[a-z][a-z0-9_]*$') and page.app or nil
    local version = type(page.version) == 'string' and page.version:find('^[%w%.%-]+$') and page.version or nil

    return { resource = page.resource, path = page.path, app = app, version = version }
end

function DeviceScreens.pageFor(record, given)
    local page = cleanPage(given)

    if page then
        return page
    end

    if type(record.spec.page) == 'string' then
        return { resource = resource, path = record.spec.page }
    end

    return { resource = resource, path = OUT_OF_SERVICE }
end

local function samePage(a, b)
    return a ~= nil and b ~= nil and a.resource == b.resource and a.path == b.path and a.app == b.app and a.version == b.version
end

local function url(screen)
    local page = screen.page
    local extra = ''

    if page.app then
        extra = extra .. '&app=' .. page.app
    end

    if page.version then
        extra = extra .. '&v=' .. page.version
    end

    return ('https://cfx-nui-%s/%s?host=%s&kind=%s&device=%s&width=%d&height=%d&mode=%s&browser=%s%s#s=%s'):format(
        page.resource,
        page.path,
        resource,
        screen.kind,
        screen.kind,
        screen.width,
        screen.height,
        screen.mode,
        screen.browser,
        extra,
        screen.secret
    )
end

local function osLocale()
    if osStrings then
        return osStrings
    end

    local list = {}

    for key, text in pairs(lib.getLocales()) do
        if type(key) == 'string' and type(text) == 'string' then
            for _, prefix in ipairs(DeviceScreens.LOCALE_PREFIXES) do
                if key:sub(1, #prefix) == prefix then
                    list[key] = text
                    break
                end
            end
        end
    end

    osStrings = list

    return list
end

local deliver = DeviceWorld.tellPage

local function flush(screen)
    if not screen or screen.destroyed or not screen.pageReady then return end

    local lead, queue = screen.lead, screen.queue

    screen.lead, screen.queue = {}, {}

    for _, message in ipairs(lead) do
        deliver(screen, message)
    end

    for _, message in ipairs(queue) do
        deliver(screen, message)
    end
end

local function create(record, mode, page, size)
    local spec = record.spec

    size = size or spec.dui
    serial = serial + 1

    local screen = {
        kind = record.kind,
        spec = spec,
        page = page,
        mode = mode,
        record = record,
        key = record.key,
        width = size.width,
        height = size.height,
        queue = {},
        lead = {},
    }

    screen.model = modelOf(record)
    screen.target = DeviceRules.screenTexture(screen.model)

    return DeviceWorld.startPage(screen, ('%s_%d_%d'):format(mode, STAMP, serial), 'evdev_dui_', url, screen.width, screen.height, function()
        flush(screen)
    end)
end

local function unbind(screen)
    local DeviceIdle = require 'client.idle'

    if bound[screen.model] == screen then
        bound[screen.model], screen.face = nil, nil
        RemoveReplaceTexture(screen.model, screen.target)
        DeviceIdle.handBack(screen.model)
    end
end

function DeviceScreens.refresh(model)
    if type(model) ~= 'string' then return end

    local holder = bound[model]

    RemoveReplaceTexture(model, DeviceRules.screenTexture(model))

    if holder and holder.face then
        AddReplaceTexture(model, holder.target, holder.face, TEXTURE)
    end
end

function DeviceScreens.blank(size)
    if type(size) ~= 'table' or not Util.integer(size.width, 1) or not Util.integer(size.height, 1) then return nil end

    local key = ('%dx%d'):format(size.width, size.height)
    local blank = blanks[key]

    if blank == nil then
        blank = false

        local name = ('evdev_dark_%s_%d'):format(key, STAMP)
        local texture = CreateRuntimeTexture(CreateRuntimeTxd(name), TEXTURE, size.width, size.height)

        if texture and texture ~= 0 and GetRuntimeTextureWidth(texture) == size.width and GetRuntimeTextureHeight(texture) == size.height then
            CommitRuntimeTexture(texture)
            blank = name
        end

        blanks[key] = blank
    end

    return blank or nil
end

local function faceName(kind, sleep, neutral)
    if sleep then
        return neutral and ('evdev_sleep_%s_neutral_%d'):format(kind, STAMP) or ('evdev_sleep_%s_%d'):format(kind, STAMP)
    end

    return ('evdev_still_%s_%d'):format(kind, STAMP)
end

function DeviceScreens.stillFace(kind, size, sleep, neutral)
    if type(size) ~= 'table' or not Util.integer(size.width, 1) or not Util.integer(size.height, 1) then return nil end

    sleep, neutral = sleep == true, neutral == true

    local key = ('%s|%s|%s'):format(kind, tostring(sleep), tostring(neutral))
    local face = faces[key]

    if face == nil then
        face = false

        local preset = ScreenRules.presets(kind)[1]
        local path = type(preset) == 'table' and (not neutral or preset.neutral == true) and ScreenRules.stillPicture(preset.picture, sleep, neutral) or nil

        if path then
            local name = faceName(kind, sleep, neutral)
            local texture = CreateRuntimeTextureFromImage(CreateRuntimeTxd(name), TEXTURE, path)

            if texture and texture ~= 0 and GetRuntimeTextureWidth(texture) == size.width and GetRuntimeTextureHeight(texture) == size.height then
                face = name
            end
        end

        faces[key] = face
    end

    return face or nil
end

local function ownPage(screen)
    return screen ~= nil and type(screen.page) == 'table' and screen.page.resource == resource
end

local function blankOf(screen)
    return DeviceScreens.blank(screen.spec.textureSize)
end

local function faceOf(screen)
    local blank = (screen.dark or screen.sized) and blankOf(screen)

    if blank then
        return blank
    end

    local size = screen.spec.textureSize

    if screen.sized or screen.width ~= size.width or screen.height ~= size.height then return nil end

    return screen.txdName
end

local function place(screen)
    local holder = bound[screen.model]
    local face = faceOf(screen)

    if holder and (holder ~= screen or screen.face ~= face) then
        RemoveReplaceTexture(screen.model, screen.target)
    end

    if holder and holder ~= screen then
        holder.face = nil
    end

    bound[screen.model], screen.face = screen, face
    AddReplaceTexture(screen.model, screen.target, face, TEXTURE)
end

local function destroy(screen)
    if not screen or screen.destroyed then return end

    screen.destroyed, screen.showing = true, false
    unbind(screen)
    DeviceWorld.endPage(screen)
end

local function remember(screen, message)
    if not screen.log then return end

    if #screen.log >= LOG then
        screen.log = nil

        return
    end

    screen.log[#screen.log + 1] = message
end

local function send(screen, message)
    if not screen or screen.destroyed then return end

    remember(screen, message)

    if screen.pageReady and #screen.lead == 0 and #screen.queue == 0 then
        deliver(screen, message)

        return
    end

    if #screen.queue >= QUEUE then
        table.remove(screen.queue, 1)
    end

    screen.queue[#screen.queue + 1] = message
end

local function lead(screen, messages)
    if not screen or screen.destroyed then return end

    for _, message in ipairs(messages) do
        remember(screen, message)
        screen.lead[#screen.lead + 1] = message
    end

    flush(screen)
end

local function mayBind(screen)
    local holder = bound[screen.model]

    if holder and holder ~= screen and not holder.destroyed and holder.showing and holder == own then return false end

    local record = screen.record

    return record ~= nil and DoesEntityExist(record.entity)
end

local function mayShow(screen)
    if not screen.showing or not inWorld(screen) then return false end
    if not screen.texture and not screen.sized then return false end

    return mayBind(screen) and faceOf(screen) ~= nil
end

local function bind(screen, now)
    if not screen or screen.destroyed then return end

    if #screen.lead > 0 or #screen.queue > 0 then
        flush(screen)
    end

    DeviceWorld.pageTexture(screen, now)

    if mayShow(screen) then
        place(screen)
    elseif bound[screen.model] == screen then
        unbind(screen)
    end
end

function DeviceScreens.holder(model)
    return bound[model]
end

function DeviceScreens.claim(holder, face)
    local current = bound[holder.model]

    if current and current ~= holder and not current.destroyed and not current.idle then return false end
    if current == holder and holder.face == face then return true end

    if current then
        RemoveReplaceTexture(holder.model, holder.target)
        current.face = nil
    end

    bound[holder.model], holder.face = holder, face
    AddReplaceTexture(holder.model, holder.target, face, TEXTURE)

    return true
end

function DeviceScreens.release(holder)
    if bound[holder.model] ~= holder then
        holder.face = nil

        return
    end

    bound[holder.model], holder.face = nil, nil
    RemoveReplaceTexture(holder.model, holder.target)
end

local function cornersOf(screen)
    local record = screen.record

    if not record or not DoesEntityExist(record.entity) then return nil end

    if screen.cornersFor ~= record.entity then
        screen.corners, screen.cornersFor = DeviceWorld.screen(record.entity, screen.spec), record.entity
    end

    return screen.corners
end

local function draw(screen)
    if not screen or screen.destroyed or not screen.showing or not screen.texture then return false end
    if inWorld(screen) or screen.sized then return false end

    local corners = cornersOf(screen)

    if not corners or not DeviceRules.facing(corners, GetFinalRenderedCamCoord()) then return true end

    local tl, tr, bl, br = corners.TL, corners.TR, corners.BL, corners.BR

    local du, dv = ScreenRules.uvInset(screen.width, screen.height)

    DrawTexturedPoly(
        tl.x,
        tl.y,
        tl.z,
        bl.x,
        bl.y,
        bl.z,
        tr.x,
        tr.y,
        tr.z,
        255,
        255,
        255,
        255,
        screen.txdName,
        TEXTURE,
        du,
        dv,
        1.0,
        du,
        1.0 - dv,
        1.0,
        1.0 - du,
        dv,
        1.0
    )

    DrawTexturedPoly(
        tr.x,
        tr.y,
        tr.z,
        bl.x,
        bl.y,
        bl.z,
        br.x,
        br.y,
        br.z,
        255,
        255,
        255,
        255,
        screen.txdName,
        TEXTURE,
        1.0 - du,
        dv,
        1.0,
        du,
        1.0 - dv,
        1.0,
        1.0 - du,
        1.0 - dv,
        1.0
    )

    return true
end

function DeviceScreens.openMessage(record, opened)
    local DeviceOs = require 'client.os'

    local message = {}

    for key, value in pairs(type(opened) == 'table' and opened or {}) do
        if key ~= 'token' and key ~= 'page' then
            message[key] = value
        end
    end

    message.type, message.kind = 'open', record.kind
    message.clock = DeviceRules.cleanClock(message.clock)

    if not record.spec.os then
        message.studio = DeviceRules.studioPage(DeviceRules.studio(record.kind)) or nil
    elseif OsRules.kind(record.kind) then
        message.prefs = DeviceOs.prefs()
    end

    return message
end

local function reusable(screen, record, page, size)
    if not screen or screen.destroyed then return false end
    if screen.kind ~= record.kind or screen.model ~= modelOf(record) then return false end
    if not samePage(screen.page, page) then return false end

    local wanted = size or record.spec.dui

    return screen.sized == (size ~= nil) and screen.width == wanted.width and screen.height == wanted.height
end

function DeviceScreens.open(record, opened, size)
    local page = DeviceScreens.pageFor(record, type(opened) == 'table' and opened.page or nil)
    local screen

    if reusable(spare, record, page, size) then
        screen, spare = spare, nil
    else
        destroy(spare)
        spare = nil
        screen = create(record, 'use', page, size)
    end

    screen.record, screen.key, screen.cornersFor = record, record.key, nil
    screen.showing, screen.releaseAt, screen.discard, screen.dark = false, nil, nil, false
    screen.sized, screen.log = size ~= nil, {}
    own = screen

    local messages = {}

    if record.spec.os then
        messages[#messages + 1] = { type = 'init', locale = osLocale(), brand = brandView(record) }
    end

    local message = DeviceScreens.openMessage(record, opened)

    if ownPage(screen) then
        message.brand = brandView(record)
    end

    messages[#messages + 1] = message
    lead(screen, messages)

    return screen
end

function DeviceScreens.show()
    if not own then return end

    own.showing = true
    send(own, { type = 'shown' })
end

function DeviceScreens.close()
    local screen = own

    own = nil

    if not screen then return end

    screen.showing = false
    unbind(screen)

    if not screen.pageReady or not screen.texture or screen.discard then
        destroy(screen)

        return
    end

    send(screen, { type = 'close' })
    destroy(spare)
    spare = screen
    screen.releaseAt = GetGameTimer() + settings().mirror.idleMs
end

function DeviceScreens.ready()
    return own ~= nil and own.texture ~= nil
end

function DeviceScreens.size()
    if not own or own.destroyed then return nil end

    return { width = own.width, height = own.height }
end

function DeviceScreens.rebuild(size)
    local old = own

    if not old or old.destroyed or not old.log or not old.sized then return false end
    if old.width == size.width and old.height == size.height then return false end

    local screen = create(old.record, 'use', old.page, size)

    screen.sized, screen.showing, screen.dark, screen.log = true, old.showing, old.dark, {}
    lead(screen, old.log)

    if bound[old.model] == old then
        bound[old.model], screen.face, old.face = screen, old.face, nil
    end

    own = screen
    destroy(old)

    return true
end

function DeviceScreens.seen()
    if own then
        own.log = nil
    end
end

function DeviceScreens.ownPage(data)
    return own ~= nil and not own.destroyed and type(data) == 'table' and data.browser ~= nil and tostring(data.browser) == own.browser and data.s == own.secret
end

function DeviceScreens.ownResource()
    return own and not own.destroyed and own.page.resource or nil
end

function DeviceScreens.sprite()
    local screen = own

    if not screen or screen.destroyed or not screen.showing or not screen.texture then return nil end

    return screen.txdName, TEXTURE
end

function DeviceScreens.dark(on)
    local screen = own

    on = on == true

    if not screen or screen.destroyed or screen.dark == on then return end

    screen.dark = on

    if bound[screen.model] == screen and faceOf(screen) ~= screen.face then
        place(screen)
    end
end

function DeviceScreens.sendOwn(message)
    send(own, message)
end

function DeviceScreens.sendWatch(message)
    if watch and watch.watching == true then
        send(watch.screen, message)
    end
end

function DeviceScreens.brand(view)
    local count = 0

    for _, screen in pairs({ own = own, watch = watch and watch.screen or nil }) do
        if not screen.destroyed and ownPage(screen) then
            send(screen, { type = 'brand', brand = brandView(screen.record, view) })
            count = count + 1
        end
    end

    return count
end

function DeviceScreens.lookChanged(key)
    local count = 0

    for _, screen in pairs({ own = own, watch = watch and watch.screen or nil }) do
        if not screen.destroyed and screen.key == key and ownPage(screen) then
            send(screen, { type = 'brand', brand = brandView(screen.record) })
            count = count + 1
        end
    end

    return count
end

function DeviceScreens.mouse(kind, px, py, delta, button)
    local screen = own

    if not screen or not screen.pageReady or screen.destroyed then return end

    delta = tonumber(delta) or 0
    button = button == 'right' and 'right' or 'left'

    if kind == 'wheel' and delta == 0 then return end

    if kind == 'up' then
        if px then
            SendDuiMouseMove(screen.dui, px, py)
        end

        SendDuiMouseUp(screen.dui, button)

        return
    end

    SendDuiMouseMove(screen.dui, px, py)

    if kind == 'down' then
        SendDuiMouseDown(screen.dui, button)
    elseif kind == 'wheel' then
        SendDuiMouseWheel(screen.dui, delta > 0 and -100 or 100, 0)
    end
end

function DeviceScreens.watching()
    return watch and not watch.destroyed and watch.watching == true and watch.key or nil
end

local function stopWatch(entry)
    if entry.screen then
        entry.screen.showing = false
        unbind(entry.screen)
    end

    if not entry.watching then return end

    entry.watching = false

    local id = entry.key

    CreateThread(function() Client.call('evdev:device:watch', id, false) end)
end

local function startWatch(entry)
    local DeviceApps = require 'client.apps'

    entry.watching = 'pending'

    local id = entry.key
    local result = Client.call('evdev:device:watch', id, true)

    if watch ~= entry or entry.destroyed then
        if result.ok then
            CreateThread(function() Client.call('evdev:device:watch', id, false) end)
        end

        return
    end

    if not result.ok then
        entry.watching = false
        entry.retryAt = GetGameTimer() + WATCH_RETRY_MS

        return
    end

    local data = type(result.data) == 'table' and result.data or {}
    local page = DeviceScreens.pageFor(entry.record, data.page)
    local screen = entry.screen

    if screen and not samePage(screen.page, page) then
        destroy(screen)
        screen = nil
    end

    if not screen then
        screen = create(entry.record, 'watch', page)

        if entry.record.spec.os then
            lead(screen, { { type = 'init', locale = osLocale(), brand = brandView(entry.record) } })
        end

        entry.screen = screen
    end

    local state = DeviceRules.cleanDeviceState(entry.record.kind, data.state, settings().mirror)

    entry.watching, entry.idleAt = true, nil
    entry.showAt = not state and GetGameTimer() + STATE_WAIT_MS or nil
    screen.showing = state ~= nil
    send(screen, { type = 'watch', kind = entry.record.kind, extra = data.extra, brand = ownPage(screen) and brandView(entry.record) or nil })
    DeviceApps.watched(entry.key, entry.record.kind, data.extra)

    local time = DeviceRules.cleanClock(data.clock)

    if time then
        send(screen, { type = 'clock', clock = time })
    end

    if state then
        send(screen, { type = 'state', state = state })
    end

    local pointer = type(data.pointer) == 'table' and data.pointer or {}
    local u, v = DeviceRules.cleanPointer(pointer.u, pointer.v)

    if u then
        send(screen, { type = 'pointer', u = u, v = v })
    end
end

local function dropWatch(entry)
    if not entry then return end

    entry.destroyed = true
    destroy(entry.screen)
end

local function wanted()
    local mirror = settings().mirror

    if own or mirror.enabled == false or (mirror.maxScreens or 0) < 1 then return nil end

    local coords = GetEntityCoords(cache.ped)
    local range = DeviceWorld.watchRange

    if watch and not watch.destroyed then
        local record = DeviceWorld.get(watch.key)

        if record == watch.record and DeviceWorld.busy(watch.key) and DoesEntityExist(record.entity)
            and #(coords - record.at) <= range + DeviceRules.KEEP_RANGE then
            return record
        end
    end

    local eye = GetFinalRenderedCamCoord()
    local best, bestDistance = nil, range

    for key, record in pairs(DeviceWorld.spawned) do
        if DeviceWorld.busy(key) and DoesEntityExist(record.entity) then
            local distance = #(coords - record.at)

            if distance <= bestDistance and DeviceRules.facing(DeviceWorld.corners(record), eye) then
                best, bestDistance = record, distance
            end
        end
    end

    return best
end

local function maintainWatch(now)
    local record = wanted()
    local current = watch

    if current and record ~= current.record then
        stopWatch(current)

        if record or DeviceWorld.get(current.key) ~= current.record then
            dropWatch(current)
            watch = nil
        else
            current.idleAt = current.idleAt or now + settings().mirror.idleMs

            if now >= current.idleAt then
                dropWatch(current)
                watch = nil
            end
        end
    end

    if record and not watch then
        watch = { key = record.key, record = record, watching = false }
    end

    if watch and watch.record == record and not watch.watching and now >= (watch.retryAt or 0) then
        startWatch(watch)
    end

    if watch and watch.showAt and now >= watch.showAt then
        watch.showAt = nil

        if watch.screen and watch.watching == true then
            watch.screen.showing = true
        end
    end
end

local function watchDetail(entry)
    local DeviceIdle = require 'client.idle'

    local screen, record = entry.screen, entry.record

    if not screen or not screen.pageReady or entry.watching ~= true or not DoesEntityExist(record.entity) then return end

    local live = type(Config.devices.idle) == 'table' and type(Config.devices.idle.live) == 'table' and Config.devices.idle.live or {}
    local size = DeviceIdle.detail(screen, record, live.detail)

    if size then
        send(screen, { type = 'detail', w = size.w, h = size.h })
    end
end

local function watched(id)
    return watch ~= nil and not watch.destroyed and watch.key == id and watch.watching == true and watch.screen ~= nil
end

RegisterNetEvent('evdev:client:deviceState', function(id, state)
    if not watched(id) then return end

    local clean = DeviceRules.cleanDeviceState(watch.record.kind, state, settings().mirror)

    if clean then
        send(watch.screen, { type = 'state', state = clean })
    end

    if watch.showAt then
        watch.showAt = nil
        watch.screen.showing = true
    end
end)

RegisterNetEvent('evdev:client:devicePointer', function(id, u, v)
    if not watched(id) then return end

    local cu, cv = DeviceRules.cleanPointer(u, v)

    if cu then
        send(watch.screen, { type = 'pointer', u = cu, v = cv })
    end
end)

RegisterNetEvent('evdev:client:deviceIdle', function(id)
    if not watch or watch.destroyed or watch.key ~= id then return end

    watch.watching, watch.showAt = false, nil

    if watch.screen then
        watch.screen.showing = false
        unbind(watch.screen)
        send(watch.screen, { type = 'idle' })
    end

    watch.idleAt = GetGameTimer() + settings().mirror.idleMs
end)

RegisterNetEvent('evdev:client:deviceUnwatched', function(id)
    if not watch or watch.destroyed or watch.key ~= id then return end

    watch.watching, watch.retryAt, watch.showAt = false, nil, nil

    if watch.screen then
        watch.screen.showing = false
        unbind(watch.screen)
    end
end)

DeviceWorld.on('spawn', function(record)
    if record.model and DeviceRules.screenMode(record.spec) == 'world' then
        DeviceScreens.refresh(record.model)
    end
end)

Bridge.onLogout(function()
    dropWatch(watch)
    destroy(spare)
    watch, spare = nil, nil

    if own then
        own.discard = true
    end
end)

CreateThread(function()
    while not stopping do
        Wait((own and not own.texture) and 100 or 250)

        if stopping then return end

        local now = GetGameTimer()

        bind(own, now)

        if spare and now >= (spare.releaseAt or 0) then
            destroy(spare)
            spare = nil
        end

        maintainWatch(now)

        if watch then
            bind(watch.screen, now)
            watchDetail(watch)
        end
    end
end)

CreateThread(function()
    while not stopping do
        Wait(0)

        local drawn = draw(own)

        drawn = (watch and draw(watch.screen)) or drawn

        if not drawn then
            Wait((own or watch) and 100 or 500)
        end
    end
end)

AddEventHandler('onResourceStop', function(name)
    if name ~= resource then return end

    stopping = true
    destroy(own)
    destroy(spare)
    dropWatch(watch)
    own, spare, watch = nil, nil, nil
end)

AddEventHandler('ox_lib:setLocale', function()
    osStrings = nil
end)

return DeviceScreens
