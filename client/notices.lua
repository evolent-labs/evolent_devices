local Config = require 'config'
local Util = require 'shared.util'
local DeviceRules = require 'shared.rules'
local AppRules = require 'shared.apps'
local DeviceSound = require 'shared.sound'
local Nui = require 'client.nui'
local DeviceWorld = require 'client.world'
local DeviceOs = require 'client.os'

local DeviceNotices = { counts = {}, stamps = {}, blinks = {}, primed = false }

DeviceNotices.STATE = 'evdev:unread'
DeviceNotices.BLINK_MS = 1800
DeviceNotices.PULSES = 3
DeviceNotices.POCKET_GAIN = 0.6
DeviceNotices.LATE_MS = 4000
DeviceNotices.SHOWN = 4

function DeviceNotices.settings()
    local value = type(Config.notifications) == 'table' and Config.notifications or {}
    local popup = type(value.popup) == 'table' and value.popup or {}
    local tablet = type(value.tablet) == 'table' and value.tablet or {}
    local screen = type(value.screen) == 'table' and value.screen or {}

    return {
        popup = popup.enabled ~= false,
        tablet = tablet.enabled ~= false,
        position = type(popup.position) == 'string' and popup.position or 'top_right',
        seconds = Util.integer(popup.seconds, 3, 20) or 6,
        screen = screen.enabled ~= false,
        blink = screen.enabled ~= false and screen.blink ~= false,
        sound = value.sound ~= false,
    }
end

function DeviceNotices.game(alerts)
    local prefs = DeviceOs.prefs()
    local settings = DeviceNotices.settings()
    local allowed = type(alerts) == 'table' and alerts or { popup = settings.popup or settings.tablet, sound = settings.sound }

    return {
        popup = prefs.gamePopup ~= false,
        sound = prefs.gameSound ~= false,
        canPopup = allowed.popup ~= false,
        canSound = allowed.sound ~= false,
    }
end

function DeviceNotices.setGame(data)
    local prefs = DeviceOs.prefs()

    if type(data) == 'table' then
        if type(data.popup) == 'boolean' then
            prefs.gamePopup = data.popup
        end

        if type(data.sound) == 'boolean' then
            prefs.gameSound = data.sound
        end
    end

    local saved = DeviceOs.savePrefs(prefs)

    return { ok = true, popup = saved.gamePopup, sound = saved.gameSound }
end

function DeviceNotices.gain(payload, prefs, pocket)
    if payload.sound ~= true or prefs.gameSound == false then return 0.0 end

    local gain = DeviceSound.mix(DeviceSound.userGain(DeviceSound.settings(DeviceWorld.sound)), DeviceOs.volume())

    if pocket then
        gain = Util.round(gain * DeviceNotices.POCKET_GAIN, 3)
    end

    return gain
end

local function wanted(notice, prefs)
    if type(notice) ~= 'table' or not AppRules.isId(notice.app) then return false end
    if type(notice.title) ~= 'string' or notice.title == '' then return false end

    return not Util.contains(prefs.quiet or {}, notice.app)
end

function DeviceNotices.show(payload)
    if type(payload) ~= 'table' or type(payload.list) ~= 'table' then return false end

    local prefs = DeviceOs.prefs()

    if prefs.gamePopup == false or prefs.dnd == true then return false end

    local list = {}

    for _, notice in ipairs(payload.list) do
        if #list < DeviceNotices.SHOWN and wanted(notice, prefs) then
            list[#list + 1] = notice
        end
    end

    if #list == 0 then return false end

    local settings = DeviceNotices.settings()
    local pocket = payload.mode == 'pocket'

    Nui.send({
        type = 'notice',
        mode = pocket and 'pocket' or 'popup',
        notices = list,
        more = Util.integer(payload.more, 0, 999) or 0,
        position = settings.position,
        seconds = settings.seconds,
        gain = DeviceNotices.gain(payload, prefs, pocket),
    })

    return true
end

function DeviceNotices.apply(value, now)
    local counts = {}
    local blink = DeviceNotices.settings().blink

    for key, entry in pairs(type(value) == 'table' and value or {}) do
        local id = Util.integer(tonumber(key), 1)
        local count = type(entry) == 'table' and Util.integer(entry.n, 1, 99) or nil

        if id and count then
            local mark = Util.integer(entry.b, 0) or 0

            counts[id] = count

            if DeviceNotices.primed and blink and mark > (DeviceNotices.stamps[id] or 0) then
                DeviceNotices.blinks[id] = now or GetGameTimer()
            end

            DeviceNotices.stamps[id] = math.max(mark, DeviceNotices.stamps[id] or 0)
        end
    end

    DeviceNotices.counts = counts
    DeviceNotices.primed = true

    return counts
end

function DeviceNotices.count(key)
    if not DeviceNotices.settings().screen then return 0 end

    return DeviceNotices.counts[key] or 0
end

function DeviceNotices.flashing(key, now)
    local start = DeviceNotices.blinks[key]

    if not start then return false end

    if (now or GetGameTimer()) - start >= DeviceNotices.BLINK_MS then
        DeviceNotices.blinks[key] = nil

        return false
    end

    return true
end

function DeviceNotices.flash(key, now)
    now = now or GetGameTimer()

    if not DeviceNotices.flashing(key, now) then return 0.0 end

    return DeviceRules.blink(now - DeviceNotices.blinks[key], DeviceNotices.BLINK_MS, DeviceNotices.PULSES)
end

RegisterNetEvent('evdev:client:notices', function(payload)
    if type(payload) ~= 'table' then return end

    if payload.late then
        CreateThread(function()
            Wait(DeviceNotices.LATE_MS)
            DeviceNotices.show(payload)
        end)

        return
    end

    DeviceNotices.show(payload)
end)

AddStateBagChangeHandler(DeviceNotices.STATE, 'global', function(_, _, value)
    DeviceNotices.apply(value)
end)

DeviceNotices.apply(GlobalState[DeviceNotices.STATE])

return DeviceNotices
