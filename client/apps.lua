local Util = require 'shared.util'
local Client = require 'client.main'
local Nui = require 'client.nui'
local DeviceWorld = require 'client.world'
local DeviceScreens = require 'client.screens'
local DeviceUse = require 'client.use'

local DeviceApps = {}

local OK = { ok = true }
local REPLY_MS = 10000
local MESSAGE_BYTES = 32768
local NAME = '^[%w_:%-%.]+$'

local current = nil
local replies = {}
local serial = 0

local function bytes(value)
    local ok, text = pcall(json.encode, value)

    if not ok or text == nil then
        return math.huge
    end

    return #text
end

local function listOf(apps)
    local map = {}

    for _, view in ipairs(type(apps) == 'table' and apps or {}) do
        if type(view) == 'table' and type(view.id) == 'string' then
            map[view.id] = view
        end
    end

    return map
end

local TABLET_ACTIONS = {
    opened = 'appOpened',
    closed = 'appClosed',
    message = 'toApp',
    notice = 'notify',
    reply = 'appReply',
    intent = 'appIntent',
    refused = 'appRefused',
}

local function toPage(state, action, payload)
    if not state or current ~= state then return end

    if state.scope == 'tablet' then
        local message = { type = 'tablet', action = TABLET_ACTIONS[action] or action }

        for key, value in pairs(payload) do
            message[key] = value
        end

        Nui.send(message)

        return
    end

    if state.terminal then
        if action == 'message' then
            DeviceScreens.sendOwn(payload.message)
        end

        if action == 'reply' then
            DeviceScreens.sendOwn({ type = 'osReply', id = payload.id, data = payload.data })
        end

        return
    end

    local message = { type = 'app', action = action }

    for key, value in pairs(payload) do
        message[key] = value
    end

    DeviceScreens.sendOwn(message)
end

function DeviceApps.current()
    return current
end

function DeviceApps.begin(scope, session)
    DeviceApps.finish('device_closed')

    current = {
        scope = scope,
        token = session.token,
        kind = session.kind,
        key = session.key,
        device = session.device,
        apps = listOf(session.apps),
        open = {},
        signal = session.signal,
        terminal = session.kind == 'terminal',
    }

    local app = session.app

    if type(app) == 'table' and type(app.id) == 'string' and type(app.token) == 'string' then
        current.apps[app.id] = { id = app.id, label = app.label, resource = session.resource }
        current.open[app.id] = { token = app.token, context = app.context }
        current.pending = app.id

        if scope ~= 'device' then
            DeviceApps.announce()
        end
    end

    return current
end

function DeviceApps.announce()
    local state = current
    local id = state and state.pending

    if not id then return end

    state.pending = nil

    if state.open[id] then
        TriggerEvent('evolent_devices:appOpened', id, DeviceApps.session(id))
    end
end

function DeviceApps.finish(reason)
    local state = current

    if not state then return end

    current = nil

    for id in pairs(state.open) do
        TriggerEvent('evolent_devices:appClosed', id, reason or 'device_closed')
    end

    for key, entry in pairs(replies) do
        if entry.state == state then
            replies[key] = nil
        end
    end
end

function DeviceApps.session(appId)
    local state = current
    local open = state and state.open[appId]

    if not open then return nil end

    return {
        app = appId,
        kind = state.kind,
        device = state.device and Util.copy(state.device) or nil,
        token = open.token,
        context = Util.copy(open.context),
    }
end

local function cleanIntent(intent)
    if type(intent) ~= 'table' or bytes(intent) > 2048 then return nil end

    return intent
end

function DeviceApps.open(appId, intent)
    local state = current

    if not state or state.terminal or type(appId) ~= 'string' then
        return { ok = false, reason = 'device_closed' }
    end

    local open = state.open[appId]

    if open and open.reply then
        if cleanIntent(intent) then
            toPage(state, 'intent', { app = appId, intent = intent })
        end

        return open.reply
    end

    local result = Client.call('evdev:app:open', state.token, appId, cleanIntent(intent))

    if current ~= state then
        return { ok = false, reason = 'device_closed' }
    end

    local data = type(result.data) == 'table' and result.data or nil

    if not result.ok or not data or type(data.token) ~= 'string' or type(data.url) ~= 'string' then
        local reason = result.ok and 'no_response' or result.reason

        toPage(state, 'refused', { app = appId, reason = reason })

        return { ok = false, reason = reason }
    end

    local reply = {
        ok = true,
        app = appId,
        token = data.token,
        url = data.url,
        context = data.context,
        protocol = data.protocol,
        canvas = data.canvas,
        window = data.window,
        network = data.network,
        intent = data.intent,
    }

    state.open[appId] = { token = data.token, context = data.context, reply = reply }
    toPage(state, 'opened', reply)
    TriggerEvent('evolent_devices:appOpened', appId, DeviceApps.session(appId))

    return reply
end

function DeviceApps.close(appId, tell)
    local state = current

    if not state or not state.open[appId] then return false end

    state.open[appId] = nil

    local token = state.token

    CreateThread(function() Client.call('evdev:app:close', token, appId) end)
    if tell then
        toPage(state, 'closed', { app = appId, reason = 'app_closed' })
    end

    TriggerEvent('evolent_devices:appClosed', appId, 'app_closed')

    return true
end

function DeviceApps.relay(appId, name, payload, id)
    local state = current

    if not state or not state.open[appId] or type(name) ~= 'string' or #name > 64 then return false end
    if not name:find(NAME) then return false end
    if type(id) ~= 'string' and type(id) ~= 'number' then return false end

    serial = serial + 1

    local key = ('r%d_%s'):format(serial, Util.hex(8))

    replies[key] = { state = state, app = appId, id = id }
    TriggerEvent('evolent_devices:appPost', appId, name, type(payload) == 'table' and payload or {}, key)

    CreateThread(function()
        Wait(REPLY_MS)

        local entry = replies[key]

        if not entry then return end

        replies[key] = nil
        toPage(entry.state, 'reply', { app = entry.app, id = entry.id, data = { ok = false, reason = 'no_response' } })
    end)

    return true
end

function DeviceApps.answer(key, result, invoker)
    local entry = replies[key]

    if not entry then return false end

    local view = entry.state.apps[entry.app]

    if invoker and view and view.resource and invoker ~= view.resource then return false end

    replies[key] = nil

    if bytes(result) > MESSAGE_BYTES then
        result = { ok = false, reason = 'message_too_big' }
    end

    toPage(entry.state, 'reply', { app = entry.app, id = entry.id, data = result })

    return true
end

function DeviceApps.deliver(appId, message)
    local state = current

    if not state or not state.open[appId] or type(message) ~= 'table' then return false end

    toPage(state, 'message', { app = appId, message = message })

    return true
end

function DeviceApps.isPost(appId, data)
    local open = current and current.open[appId]

    return open ~= nil and type(data) == 'table' and type(data.__os) == 'string' and data.__os == open.token
end

local function ownerOf(appId)
    local view = current and current.apps[appId]

    return view and view.resource or nil
end

local function mine(appId)
    local invoker = GetInvokingResource()
    local owner = ownerOf(appId)

    return invoker == nil or invoker == GetCurrentResourceName() or owner == nil or invoker == owner
end

function DeviceApps.watched(key, kind, extra)
    if type(extra) ~= 'table' then return end

    local list = type(extra.apps) == 'table' and extra.apps or {}

    if type(extra.app) == 'table' then
        list = { { id = extra.app.id, view = 'state', data = extra.app.data } }
    end

    for _, app in ipairs(list) do
        if type(app) == 'table' and type(app.id) == 'string' and app.view == 'state' then
            TriggerEvent('evolent_devices:appWatch', app.id, key, app.data)
        end
    end
end

DeviceUse.on('open', function(state, answer)
    if type(answer) ~= 'table' or type(answer.token) ~= 'string' then return end

    DeviceApps.begin('device', {
        token = answer.token,
        kind = state.kind,
        key = state.key,
        device = answer.device,
        apps = answer.apps,
        signal = answer.signal,
        app = answer.app,
        resource = type(answer.page) == 'table' and answer.page.resource or nil,
    })
end)

DeviceUse.on('screen', function()
    if current and current.scope == 'device' then
        DeviceApps.announce()
    end
end)

DeviceUse.on('shown', function(state)
    local id = current and current.scope == 'device' and type(state.opened) == 'table' and state.opened.openApp or nil

    if type(id) ~= 'string' or not current.apps[id] or current.open[id] then return end

    CreateThread(function() DeviceApps.open(id) end)
end)

DeviceUse.on('close', function(_, reason)
    if current and current.scope == 'device' then
        DeviceApps.finish(reason)
    end
end)

RegisterNUICallback('os:app', function(data, respond)
    respond(OK)

    local state = current

    if not state or state.scope ~= 'device' or not DeviceScreens.ownPage(data) then return end
    if type(data.app) ~= 'string' then return end

    if data.act == 'open' then
        CreateThread(function() DeviceApps.open(data.app, data.intent) end)
    elseif data.act == 'close' then
        DeviceApps.close(data.app, false)
    elseif data.act == 'visible' and state.open[data.app] then
        TriggerEvent('evolent_devices:appVisible', data.app, data.visible == true)
    end
end)

RegisterNUICallback('os:post', function(data, respond)
    respond(OK)

    local state = current

    if not state or state.scope ~= 'device' or not DeviceScreens.ownPage(data) then return end

    DeviceApps.relay(data.app, data.name, data.data, data.id)
end)

RegisterNetEvent('evdev:client:appClosed', function(key, appId, reason)
    local state = current

    if not state or type(appId) ~= 'string' or not state.open[appId] then return end
    if (key == 'tablet') ~= (state.scope == 'tablet') or (key ~= 'tablet' and key ~= state.key) then return end

    state.open[appId] = nil
    toPage(state, 'closed', { app = appId, reason = type(reason) == 'string' and reason or 'app_closed' })
    TriggerEvent('evolent_devices:appClosed', appId, reason)
end)

RegisterNetEvent('evdev:client:appMessage', function(appId, message)
    DeviceApps.deliver(appId, message)
end)

RegisterNetEvent('evdev:client:appNotice', function(appId, notice)
    local state = current

    if not state or state.terminal or type(notice) ~= 'table' or type(appId) ~= 'string' then return end
    if not state.apps[appId] and type(notice.label) ~= 'string' then return end

    toPage(state, 'notice', { app = appId, notice = notice })
end)

RegisterNetEvent('evdev:client:apps', function(list, installed)
    local state = current

    if not state or state.terminal or type(list) ~= 'table' then return end

    state.apps = listOf(list)

    if state.scope == 'tablet' then
        Nui.send({ type = 'tablet', action = 'apps', apps = list, installed = installed })
    else
        DeviceScreens.sendOwn({ type = 'apps', apps = list, installed = installed })
    end
end)

RegisterNetEvent('evdev:client:signal', function(reading)
    local state = current

    if not state or type(reading) ~= 'table' then return end

    local bars = Util.integer(reading.bars, 0, 4)

    if not bars then return end

    state.signal = { bars = bars, wired = reading.wired == true }

    if state.scope == 'tablet' then
        Nui.send({ type = 'tablet', action = 'signal', signal = state.signal })
    elseif not state.terminal then
        DeviceScreens.sendOwn({ type = 'signal', bars = bars, wired = state.signal.wired })
    end
end)

exports('sendAppMessage', function(appId, message)
    if type(appId) ~= 'string' or type(message) ~= 'table' or not mine(appId) then return false end
    if bytes(message) > MESSAGE_BYTES then return false end

    return DeviceApps.deliver(appId, message)
end)

exports('sendWatchMessage', function(key, appId, message)
    if type(appId) ~= 'string' or type(message) ~= 'table' or bytes(message) > MESSAGE_BYTES then return false end
    if DeviceScreens.watching() ~= key then return false end

    local record = DeviceWorld.get(key)

    if record and record.spec.os then
        DeviceScreens.sendWatch({ type = 'app', action = 'message', app = appId, message = message })
    else
        DeviceScreens.sendWatch(message)
    end

    return true
end)

exports('isAppOpen', function(appId)
    return current ~= nil and current.open[appId] ~= nil
end)

exports('appSession', function(appId)
    return DeviceApps.session(appId)
end)

exports('isAppPost', function(appId, data)
    return DeviceApps.isPost(appId, data)
end)

exports('answerAppPost', function(key, result)
    return DeviceApps.answer(key, result, GetInvokingResource())
end)

exports('openApp', function(appId, intent)
    local state = current

    if not state or state.terminal or type(appId) ~= 'string' or not state.apps[appId] then return false end

    if state.open[appId] then
        toPage(state, 'intent', { app = appId, intent = cleanIntent(intent) or {} })

        return true
    end

    if state.scope == 'tablet' then
        Nui.send({ type = 'tablet', action = 'openApp', app = appId, intent = cleanIntent(intent) })
    else
        CreateThread(function() DeviceApps.open(appId, intent) end)
    end

    return true
end)

exports('closeApp', function(appId)
    if type(appId) ~= 'string' or not mine(appId) then return false end

    return DeviceApps.close(appId, true)
end)

exports('leaveDevice', function()
    local Tablet = require 'client.tablet'

    local state = current

    if not state then return false end

    if state.scope == 'tablet' then
        return Tablet.close('app')
    end

    DeviceUse.leave()

    return true
end)

exports('isUsingDevice', function()
    return current ~= nil
end)

RegisterNetEvent('evdev:client:openTablet', function(appId, intent)
    local Tablet = require 'client.tablet'

    if type(appId) ~= 'string' then return end

    local clean = cleanIntent(intent)

    if Tablet.prop then
        if current and current.scope == 'tablet' then
            Nui.send({ type = 'tablet', action = 'openApp', app = appId, intent = clean })
        end

        return
    end

    CreateThread(function()
        if Tablet.take() then
            Nui.send({ type = 'tablet', action = 'openApp', app = appId, intent = clean })
        end
    end)
end)

exports('openTablet', function(options)
    local Tablet = require 'client.tablet'

    if Tablet.prop then return true end

    CreateThread(function()
        if Tablet.take() and type(options) == 'table' and type(options.app) == 'string' then
            Nui.send({ type = 'tablet', action = 'openApp', app = options.app, intent = cleanIntent(options.intent) })
        end
    end)

    return true
end)

return DeviceApps
