local Util = require 'shared.util'
local OsRules = require 'shared.os'
local Client = require 'client.main'
local Nui = require 'client.nui'
local DeviceScreens = require 'client.screens'
local DeviceUse = require 'client.use'
local DeviceSounds = require 'client.sound'

local DeviceOs = {}

local KVP = 'evdev:os_prefs'
local CALLS = {
    notes = true,
    ['note:save'] = true,
    ['note:delete'] = true,
    ['note:restore'] = true,
    ['note:purge'] = true,
    photos = true,
    ['photo:add'] = true,
    ['photo:remove'] = true,
    unlock = true,
    lock = true,
    password = true,
    forgot = true,
    wall = true,
    ['store:install'] = true,
    ['store:remove'] = true,
    notice = true,
}

local prefs = nil

local function stored()
    local text = GetResourceKvpString(KVP)

    if type(text) ~= 'string' or text == '' then return nil end

    local ok, value = pcall(json.decode, text)

    return ok and value or nil
end

function DeviceOs.prefs()
    if not prefs then
        prefs = OsRules.prefs(stored())
    end

    return Util.copy(prefs)
end

function DeviceOs.savePrefs(value)
    prefs = OsRules.prefs(value)
    SetResourceKvp(KVP, json.encode(prefs))

    return Util.copy(prefs)
end

function DeviceOs.volume()
    if not prefs then
        prefs = OsRules.prefs(stored())
    end

    return prefs.volume
end

function DeviceOs.call(token, name, a, b)
    if type(name) ~= 'string' or not CALLS[name] then
        return { ok = false, reason = 'unknown_action' }
    end

    return Client.call('evdev:os:' .. name, token, a, b)
end

RegisterNUICallback('os:call', function(data, respond)
    local state = DeviceUse.session()

    if not state or not state.token or not DeviceScreens.ownPage(data) then
        respond({ ok = false, reason = 'device_closed' })

        return
    end

    local token = state.token

    CreateThread(function()
        respond(DeviceOs.call(token, data.name, data.a, data.b))
    end)
end)

RegisterNUICallback('os:prefs', function(data, respond)
    if not DeviceScreens.ownPage(data) then
        respond({ ok = false, reason = 'device_closed' })

        return
    end

    local saved = DeviceOs.savePrefs(data.prefs)
    local state = DeviceUse.session()

    if state then
        Nui.send({ type = 'deviceVolume', sound = DeviceSounds.forSession(state.kind) })
    end

    respond({ ok = true, prefs = saved })
end)

return DeviceOs
