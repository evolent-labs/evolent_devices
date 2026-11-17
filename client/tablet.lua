local Config = require 'config'
local Bridge = require 'bridge'
local Util = require 'shared.util'
local ScreenRules = require 'shared.screen'
local TabletColours = require 'shared.tablet_colours'
local Client = require 'client.main'
local Nui = require 'client.nui'
local DeviceWorld = require 'client.world'
local DeviceSounds = require 'client.sound'
local DeviceApps = require 'client.apps'
local DeviceOs = require 'client.os'
local PlacementSync = require 'client.placement_sync'
local DeviceNotices = require 'client.notices'

local Tablet = {
    prop = nil,
    ped = nil,
    data = nil,
    tint = 0,
    phase = nil,
    clip = nil,
    playedAt = 0,
    useSince = 0,
    useUntil = 0,
    taking = false,
    run = 0,
    remote = {},
    lookers = {},
    lookAt = 0,
    asleep = false,
}

local STATE = 'evdev:tablet'
local PHASES = { off = true, lock = true, home = true }
local USE_END = 0.98
local USE_WAIT_MS = 8000
local TICK_MS = 100
local RELEASE_WAIT_MS = 250
local RELEASE_CHECKS = 8
local LOOK_PRIORITY = 3
local IK_HEAD, IK_BLEND_MS = 1, 250

Tablet.AWAY = {
    down = 'tablet_away_down',
    ragdoll = 'tablet_away_ragdoll',
    vehicle = 'tablet_away_vehicle',
    swimming = 'tablet_away_swimming',
    cuffed = 'tablet_away_cuffed',
    falling = 'tablet_away_falling',
    lost = 'tablet_away_lost',
}

local remoteDirty = false

local function configAttach()
    local attach = Config.tablet.attach

    return {
        bone = attach.bone,
        order = attach.order,
        x = attach.offset.x,
        y = attach.offset.y,
        z = attach.offset.z,
        rx = attach.rotation.x,
        ry = attach.rotation.y,
        rz = attach.rotation.z,
    }
end

local function attach(prop, ped, values)
    AttachEntityToEntity(
        prop,
        ped,
        GetPedBoneIndex(ped, values.bone),
        values.x,
        values.y,
        values.z,
        values.rx,
        values.ry,
        values.rz,
        false,
        false,
        false,
        true,
        values.order,
        true
    )
end

local function loadDict(dict)
    RequestAnimDict(dict)

    local deadline = GetGameTimer() + 5000

    while not HasAnimDictLoaded(dict) do
        if GetGameTimer() > deadline then return false end

        Wait(0)
    end

    return true
end

local function loadClips()
    for _, anim in pairs(Config.tablet.anims) do
        if not loadDict(anim.dict) then
            return false, anim.dict
        end
    end

    return true
end

local function paint(prop, value)
    if prop and DoesEntityExist(prop) then
        SetObjectTextureVariation(prop, TabletColours.index(value))
    end
end

local function spawn(ped, colour)
    local hash = PlacementSync.loadModel(Config.tablet.prop)

    if not hash then return nil end

    local coords = GetEntityCoords(ped)
    local prop = CreateObject(hash, coords.x, coords.y, coords.z + 0.5, false, false, false)

    SetModelAsNoLongerNeeded(hash)

    if not prop or prop == 0 then return nil end

    SetEntityCollision(prop, false, false)
    attach(prop, ped, configAttach())
    paint(prop, colour)

    return prop
end

local function remove(prop)
    if prop and DoesEntityExist(prop) then
        DetachEntity(prop, false, false)
        DeleteEntity(prop)
    end
end

local function play(name)
    local anim = Config.tablet.anims[name]

    TaskPlayAnim(
        Tablet.ped,
        anim.dict,
        anim.clip,
        Config.tablet.blendIn,
        Config.tablet.blendOut,
        -1,
        Config.tablet.flag,
        0.0,
        false,
        false,
        false
    )

    Tablet.clip, Tablet.playedAt, Tablet.usePhase = name, GetGameTimer(), nil
end

function Tablet.useEnding(ped, now)
    local anim = Config.tablet.anims.use

    if not Util.yes(IsEntityPlayingAnim(ped, anim.dict, anim.clip, 3)) then return true end
    if now >= Tablet.useUntil + USE_WAIT_MS then return true end

    local phase = GetEntityAnimCurrentTime(ped, anim.dict, anim.clip)
    local last = Tablet.usePhase

    Tablet.usePhase = phase

    return type(phase) == 'number' and (phase >= USE_END or (last ~= nil and phase < last))
end

function Tablet.pace(now)
    if Tablet.clip == 'use' and now >= Tablet.useUntil then
        return 0
    end

    return TICK_MS
end

local function colourName(index)
    local entry = TabletColours[TabletColours.index(index) + 1]

    return locale('tablet_colour_' .. entry.id)
end

local function clockNow(answer)
    local clock = answer.clock

    if type(clock) ~= 'table' or type(clock.now) ~= 'number' then
        return clock
    end

    local passed = math.max(0, GetGameTimer() - (Tablet.takenAt or GetGameTimer()))

    return { now = clock.now + math.floor(passed / 1000), offset = clock.offset }
end

local function pageData(answer)
    local state = DeviceApps.current()
    local tablet = state and state.scope == 'tablet' and state or nil
    local system = type(answer.os) == 'table' and answer.os or {}
    local locked = system.password == true

    return {
        colour = Tablet.tint,
        recolour = answer.recolour == true,
        phase = locked and Tablet.phase == 'home' and 'lock' or Tablet.phase,
        pin = locked,
        serial = answer.serial,
        user = answer.user,
        clock = clockNow(answer),
        apps = answer.apps,
        installed = answer.installed,
        notices = answer.notices,
        signal = tablet and tablet.signal or answer.signal,
        windows = answer.windows,
        os = system,
        sound = DeviceSounds.forTablet(),
        sleep = Tablet.sleepSettings(),
        game = DeviceNotices.game(answer.alerts),
    }
end

function Tablet.sleepSettings()
    local display = ScreenRules.display(DeviceWorld.display)

    return { after = display.sleep, dim = ScreenRules.SLEEP_DIM }
end

function Tablet.dark()
    return Tablet.phase == 'off' or Tablet.asleep == true
end

function Tablet.setAsleep(on)
    on = on == true

    if Tablet.asleep == on then return false end

    local before = Tablet.dark()

    Tablet.asleep = on

    if Tablet.prop and before ~= Tablet.dark() then
        TriggerServerEvent('evdev:tablet:screen', not Tablet.dark())
    end

    return true
end

local function lookSettings()
    local look = Config.tablet.look

    return type(look) == 'table' and look.enabled ~= false and look or nil
end

function Tablet.keepLooking(ped, now)
    local look = lookSettings()

    if not look or now < Tablet.lookAt then return false end

    Tablet.lookAt = now + look.refreshMs
    TaskLookAtEntity(ped, Tablet.prop, -1, look.flags, LOOK_PRIORITY)

    return true
end

function Tablet.lit()
    local list = {}

    if Tablet.prop and not Tablet.dark() then
        list[1] = { key = 'own', prop = Tablet.prop, own = true }
    end

    for serverId, entry in pairs(Tablet.remote) do
        if entry.lit then
            list[#list + 1] = { key = serverId, prop = entry.prop, own = false }
        end
    end

    return list
end

function Tablet.blocked(ped)
    if IsEntityDead(ped) or IsPedDeadOrDying(ped, true) or Bridge.isDown() then
        return 'down'
    end

    if IsPedRagdoll(ped) then
        return 'ragdoll'
    end

    if IsPedInAnyVehicle(ped, true) then
        return 'vehicle'
    end

    if IsPedSwimming(ped) or IsPedSwimmingUnderWater(ped) then
        return 'swimming'
    end

    if IsPedCuffed(ped) or Bridge.isRestrained() then
        return 'cuffed'
    end

    if IsPedFalling(ped) or IsPedInParachuteFreeFall(ped) then
        return 'falling'
    end

    return nil
end

function Tablet.setTint(value)
    Tablet.tint = TabletColours.index(value)
    paint(Tablet.prop, Tablet.tint)
end

function Tablet.take(slot)
    if Tablet.taking or Tablet.prop then return false end

    local ped = cache.ped
    local blocked = Tablet.blocked(ped)
    local refusal = blocked and 'tablet_' .. blocked or Nui.visible and 'tablet_busy' or nil

    if refusal then
        Client.notify(Client.reasonText(refusal), 'error')

        return false
    end

    Tablet.taking = true

    local result = slot and Client.call('evdev:tablet:open', slot) or Client.call('evdev:tablet:open')
    local answeredAt = GetGameTimer()

    if not result.ok then
        Tablet.taking = false
        Client.notify(Client.reasonText(result.reason), 'error')

        return false
    end

    local answer = type(result.data) == 'table' and result.data or {}
    local loaded, missing = loadClips()
    local prop = loaded and spawn(ped, answer.tint) or nil

    blocked = Tablet.blocked(ped)

    if not prop or blocked or Nui.visible then
        remove(prop)
        Tablet.taking = false
        TriggerServerEvent('evdev:tablet:close')

        if not loaded then
            print(('[evolent_devices] clip dictionary %s did not load'):format(missing))
        end

        local reason = not loaded and 'tablet_anim_missing' or not prop and 'tablet_model_missing' or blocked and 'tablet_' .. blocked or 'tablet_busy'

        Client.notify(Client.reasonText(reason), 'error')

        return false
    end

    Tablet.prop, Tablet.ped, Tablet.data, Tablet.takenAt = prop, ped, answer, answeredAt

    if type(answer.token) == 'string' then
        DeviceApps.begin('tablet', {
            token = answer.token,
            kind = 'tablet',
            apps = answer.apps,
            signal = answer.signal,
        })
    end

    Tablet.tint = TabletColours.index(answer.tint)
    Tablet.useSince, Tablet.useUntil = 0, 0
    Tablet.run = Tablet.run + 1
    Tablet.taking = false
    Tablet.lookAt = 0
    Tablet.asleep = false
    play('hold')
    Tablet.keepLooking(ped, GetGameTimer())

    if Tablet.phase == 'off' then
        TriggerServerEvent('evdev:tablet:screen', false)
    end

    Nui.open('tablet', pageData(answer))

    local run = Tablet.run

    CreateThread(function()
        while Tablet.prop and Tablet.run == run do
            Tablet.tick()
            Wait(Tablet.pace(GetGameTimer()))
        end
    end)

    return true
end

local function stillHolding(ped)
    for _, anim in pairs(Config.tablet.anims) do
        if Util.yes(IsEntityPlayingAnim(ped, anim.dict, anim.clip, 3)) then return true end
    end

    return false
end

local function release(ped)
    for _, anim in pairs(Config.tablet.anims) do
        StopAnimTask(ped, anim.dict, anim.clip, 1.0)
    end

    CreateThread(function()
        for _ = 1, RELEASE_CHECKS do
            Wait(RELEASE_WAIT_MS)

            if Tablet.prop or Tablet.taking or not DoesEntityExist(ped) then return end

            if stillHolding(ped) then
                ClearPedSecondaryTask(ped)

                return
            end
        end
    end)
end

function Tablet.close(reason)
    local prop, ped = Tablet.prop, Tablet.ped

    if not prop then return false end

    Tablet.prop, Tablet.ped, Tablet.clip = nil, nil, nil
    Tablet.asleep = false
    Tablet.run = Tablet.run + 1

    if ped and DoesEntityExist(ped) then
        release(ped)

        if lookSettings() then
            TaskClearLookAt(ped)
        end
    end

    remove(prop)

    local apps = DeviceApps.current()

    if apps and apps.scope == 'tablet' then
        DeviceApps.finish('tablet_closed')
    end

    if Nui.view == 'tablet' then
        Nui.close()
    end

    TriggerServerEvent('evdev:tablet:close')

    if Tablet.AWAY[reason] then
        Client.notify(locale(Tablet.AWAY[reason]), 'inform')
    end

    return true
end

function Tablet.activity()
    if not Tablet.prop then return end

    local now = GetGameTimer()

    if now >= Tablet.useUntil then
        Tablet.useSince = now
    end

    Tablet.useUntil = math.max(now + Config.tablet.activityHoldMs, Tablet.useSince + Config.tablet.useMinimumMs)

    if Tablet.clip ~= 'use' then
        play('use')
    end
end

function Tablet.tick()
    if not Tablet.prop then return end

    local ped = cache.ped
    local reason = (ped ~= Tablet.ped or not DoesEntityExist(Tablet.prop)) and 'lost' or Tablet.blocked(ped)

    if reason then
        return Tablet.close(reason)
    end

    if Nui.view ~= 'tablet' then
        return Tablet.close('replaced')
    end

    local now = GetGameTimer()
    local wanted = now < Tablet.useUntil and 'use' or 'hold'

    if wanted == 'hold' and Tablet.clip == 'use' and not Tablet.useEnding(ped, now) then
        wanted = 'use'
    end

    local anim = Config.tablet.anims[wanted]

    if Tablet.clip ~= wanted or (now - Tablet.playedAt > 1000 and not Util.yes(IsEntityPlayingAnim(ped, anim.dict, anim.clip, 3))) then
        play(wanted)
    end

    Tablet.keepLooking(ped, now)
end

local actions = {}

function actions.activity(_, respond)
    Tablet.activity()
    respond({ ok = true })
end

function actions.phase(data, respond)
    if PHASES[data.phase] then
        local wasDark = Tablet.dark()

        Tablet.phase = data.phase

        if data.phase == 'off' then
            Tablet.asleep = false
        end

        if wasDark ~= Tablet.dark() then
            TriggerServerEvent('evdev:tablet:screen', not Tablet.dark())
        end
    end

    respond({ ok = true })
end

function actions.os(data, respond)
    local token = type(Tablet.data) == 'table' and Tablet.data.token or nil

    if type(token) ~= 'string' then
        respond({ ok = false, reason = 'tablet_closed' })

        return
    end

    respond(DeviceOs.call(token, data.name, data.a, data.b))
end

function actions.sleep(data, respond)
    Tablet.setAsleep(data.asleep == true)
    respond({ ok = true })
end

function actions.colour(data, respond)
    local result = Client.call('evdev:tablet:colour', data.colour)
    local answer = type(result.data) == 'table' and result.data or {}
    local colour = answer.colour ~= nil and TabletColours.index(answer.colour) or nil

    if result.ok and colour then
        Tablet.setTint(colour)
    end

    respond({ ok = result.ok == true, reason = result.reason, colour = colour })
end

function actions.openApp(data, respond)
    if type(data.app) ~= 'string' then
        respond({ ok = false, reason = 'unknown_app' })

        return
    end

    respond(DeviceApps.open(data.app, type(data.intent) == 'table' and data.intent or nil))
end

function actions.closeApp(data, respond)
    respond({ ok = DeviceApps.close(data.app, false) })
end

function actions.appPost(data, respond)
    respond({ ok = DeviceApps.relay(data.app, data.name, data.data, data.id) })
end

function actions.appVisible(data, respond)
    respond({ ok = true })

    local state = DeviceApps.current()

    if state and state.scope == 'tablet' and type(data.app) == 'string' and state.open[data.app] then
        TriggerEvent('evolent_devices:appVisible', data.app, data.visible == true)
    end
end

function actions.close(_, respond)
    respond({ ok = true })
    Tablet.close('page')
end

function actions.game(data, respond)
    respond(DeviceNotices.setGame(data))
end

function Tablet.nui(data, respond)
    local action = Tablet.prop and type(data.action) == 'string' and actions[data.action] or nil

    if not action then
        respond({ ok = false, reason = Tablet.prop and 'unknown_action' or 'tablet_closed' })

        return
    end

    action(data, respond)
end

function Tablet.setColour(value)
    local result = Client.call('evdev:tablet:colour', value)

    if not result.ok then
        Client.notify(Client.reasonText(result.reason), 'error')

        return false
    end

    Tablet.setTint(result.data.colour)

    if Tablet.prop and Nui.view == 'tablet' then
        Nui.send({ type = 'tablet', action = 'colour', colour = Tablet.tint })
    end

    Client.notify(locale('tablet_colour_set', colourName(Tablet.tint)), 'success')

    return true
end

local function holder(serverId)
    local value = Player(serverId).state[STATE]

    if type(value) == 'table' and value.holding == true then
        return value
    end

    return nil
end

local function dropRemote(serverId)
    local entry = Tablet.remote[serverId]

    if not entry then return end

    Tablet.remote[serverId] = nil
    remove(entry.prop)
end

local function showRemote(serverId, ped, value)
    local colour = TabletColours.index(value.tint)
    local entry = Tablet.remote[serverId]

    if entry and entry.ped == ped and DoesEntityExist(entry.prop) and IsEntityAttachedToEntity(entry.prop, ped) then
        entry.lit = value.lit ~= false

        if entry.tint ~= colour then
            entry.tint = colour
            paint(entry.prop, colour)
        end

        return
    end

    dropRemote(serverId)

    for _, anim in pairs(Config.tablet.anims) do
        RequestAnimDict(anim.dict)
    end

    local prop = spawn(ped, colour)

    if prop then
        Tablet.remote[serverId] = { prop = prop, ped = ped, tint = colour, lit = value.lit ~= false }
    end
end

local function chooseLookers(here)
    local look = lookSettings()
    local list = {}

    if look and look.others ~= false then
        for _, entry in pairs(Tablet.remote) do
            if Util.distance(GetEntityCoords(entry.ped), here) <= look.range then
                list[#list + 1] = entry
            end
        end
    end

    Tablet.lookers = list
end

function Tablet.headsFrame()
    for _, entry in ipairs(Tablet.lookers) do
        if DoesEntityExist(entry.ped) and DoesEntityExist(entry.prop) then
            local at = GetEntityCoords(entry.prop)

            SetIkTarget(entry.ped, IK_HEAD, 0, 0, at.x + 0.0, at.y + 0.0, at.z + 0.0, 0, IK_BLEND_MS, IK_BLEND_MS)
        end
    end
end

function Tablet.remoteTick()
    local me = cache.playerId
    local here = GetEntityCoords(cache.ped)
    local seen = {}

    for _, player in ipairs(GetActivePlayers()) do
        if player ~= me then
            local ped = GetPlayerPed(player)

            if ped ~= 0 and DoesEntityExist(ped) then
                local serverId = GetPlayerServerId(player)
                local limit = Config.tablet.range + (Tablet.remote[serverId] and 10.0 or 0.0)
                local value = Util.distance(GetEntityCoords(ped), here) <= limit and holder(serverId) or nil

                if value then
                    seen[serverId] = true
                    showRemote(serverId, ped, value)
                end
            end
        end
    end

    for serverId in pairs(Tablet.remote) do
        if not seen[serverId] then
            dropRemote(serverId)
        end
    end

    chooseLookers(here)
end

function Tablet.onState(bagName, value)
    local serverId = tonumber(tostring(bagName):match('^player:(%d+)$'))

    if not serverId then return end

    if serverId == cache.serverId then
        if Tablet.prop and type(value) == 'table' then
            Tablet.setTint(value.tint)
        end

        return
    end

    local entry = Tablet.remote[serverId]

    if type(value) ~= 'table' or value.holding ~= true then
        dropRemote(serverId)
    elseif entry then
        entry.tint = TabletColours.index(value.tint)
        entry.lit = value.lit ~= false
        paint(entry.prop, entry.tint)
    else
        remoteDirty = true
    end
end

function Tablet.dropAllRemote()
    for serverId in pairs(Tablet.remote) do
        dropRemote(serverId)
    end
end

local commands = {}

function commands.close()
    Tablet.close('command')
end

commands.off = commands.close

function commands.colour(args)
    local value = tonumber(args[2])

    if not value then
        Client.notify(locale('tablet_colour_usage', Config.commands.tablet, #TabletColours - 1), 'error')

        return
    end

    Tablet.setColour(value)
end

commands.color = commands.colour

function Tablet.command(args)
    local action = type(args[1]) == 'string' and args[1]:lower() or ''

    if action == '' then
        if not Tablet.prop then
            return Tablet.take()
        end

        return Tablet.close('command')
    end

    local handler = commands[action]

    if not handler then
        Client.notify(locale('tablet_usage', Config.commands.tablet, #TabletColours - 1), 'error')

        return
    end

    handler(args)
end

RegisterCommand(Config.commands.tablet, function(_, args)
    CreateThread(function() Tablet.command(args or {}) end)
end, false)

AddStateBagChangeHandler(STATE, nil, function(bagName, _, value)
    Tablet.onState(bagName, value)
end)

Bridge.onLogout(function()
    Tablet.close('logout')
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end

    Tablet.close('stop')
    Tablet.dropAllRemote()
end)

TriggerEvent('chat:addSuggestion', '/' .. Config.commands.tablet, locale('command_tablet_help'), {
    { name = 'action', help = locale('command_tablet_action_help') },
})

CreateThread(function()
    while true do
        if Tablet.lookers[1] then
            Tablet.headsFrame()
            Wait(0)
        else
            Wait(500)
        end
    end
end)

CreateThread(function()
    while true do
        Tablet.remoteTick()

        for _ = 1, next(Tablet.remote) and 5 or 10 do
            if remoteDirty then break end

            Wait(100)
        end

        remoteDirty = false
    end
end)

return Tablet
