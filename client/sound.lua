local Util = require 'shared.util'
local DeviceSound = require 'shared.sound'
local Nui = require 'client.nui'
local DeviceWorld = require 'client.world'
local DeviceScreens = require 'client.screens'
local DeviceIdle = require 'client.idle'
local DeviceUse = require 'client.use'

local DeviceSounds = {}

local OK = { ok = true }
local lastOs = {}

local function settings()
    return DeviceWorld.sound
end

local function paused()
    return Util.yes(IsPauseMenuActive())
end

local function play(sounds, gain, pan, spread)
    if not Nui.ready or gain <= 0 then return false end

    Nui.send({ type = 'deviceSound', sounds = sounds, gain = gain, pan = pan, spread = spread })

    return true
end

function DeviceSounds.forSession(kind)
    local DeviceOs = require 'client.os'

    local current = settings()

    return {
        on = current.enabled and DeviceSound.heard(kind),
        volume = DeviceSound.mix(DeviceSound.userGain(current), DeviceOs.volume()),
        click = DeviceSound.clickName(kind),
    }
end

function DeviceSounds.forTablet()
    return DeviceSounds.forSession('tablet')
end

function DeviceSounds.note(state, button)
    if not state.token or not DeviceSound.heard(state.kind) then return end

    local pending = state.sounds or { clicks = 0, rights = 0 }
    local field = DeviceSound.rightClick(state.kind, button) and 'rights' or 'clicks'

    pending[field] = math.min(DeviceSound.PER_BATCH, pending[field] + 1)
    state.sounds = pending
end

function DeviceSounds.flush(state, now)
    local pending = state.sounds

    if not pending or now < (state.soundAt or 0) then return false end

    state.sounds = nil

    local current = settings()

    if not current.enabled or current.nearby <= 0 or not state.token then return false end

    state.soundAt = now + DeviceSound.BATCH_MS
    TriggerServerEvent('evdev:device:sound', state.token, pending.clicks, pending.rights)

    return true
end

function DeviceSounds.osEvent(state, name, now)
    local DeviceOs = require 'client.os'

    if not DeviceSound.osSound(state.kind, name) or paused() then return false end

    local current = settings()

    if not current.enabled then return false end
    if now - (lastOs[name] or -math.huge) < DeviceSound.OS_GAP_MS then return false end

    lastOs[name] = now

    return play({ [name] = 1 }, DeviceSound.mix(DeviceSound.userGain(current), DeviceOs.volume()), 0.0, 0)
end

local function playAt(kind, batch, point, current)
    local DeviceOs = require 'client.os'

    local spot = Util.position(point)

    if not batch or not spot then return false end

    local distance = Util.distance(GetEntityCoords(cache.ped), spot)
    local gain = DeviceSound.mix(DeviceSound.nearbyGain(distance, current), DeviceOs.volume())

    if gain <= 0 then return false end

    local pan = DeviceSound.pan(GetFinalRenderedCamCoord(), GetFinalRenderedCamRot(2).z, spot)

    return play(DeviceSound.sounds(kind, batch), gain, pan, DeviceSound.BATCH_MS)
end

function DeviceSounds.nearby(id, kind, point, clicks, rights)
    local current = settings()

    if not current.enabled or current.nearby <= 0 or paused() then return false end

    local own = DeviceUse.session()

    if own and own.key == id then return false end

    local record = DeviceWorld.get(id)

    if not record or record.enabled == false or record.kind ~= kind then return false end
    if record.oos or DeviceIdle.asleep(id) then return false end

    return playAt(kind, DeviceSound.batch(kind, clicks, rights), point, current)
end

RegisterNUICallback('device:sound', function(data, respond)
    respond(OK)

    local state = DeviceUse.session()

    if not state or state.stage ~= 'using' or not DeviceScreens.ownPage(data) then return end

    DeviceSounds.osEvent(state, data.sound, GetGameTimer())
end)

RegisterNetEvent('evdev:client:deviceSound', function(id, kind, point, clicks, rights)
    DeviceSounds.nearby(id, kind, point, clicks, rights)
end)

return DeviceSounds
