local Config = require 'config'
local Integrations = require 'integrations'
local Bridge = require 'bridge'
local Util = require 'shared.util'
local DeviceRules = require 'shared.rules'
local Client = require 'client.main'
local Nui = require 'client.nui'
local DeviceWorld = require 'client.world'
local DeviceScreens = require 'client.screens'
local DeviceStudio = require 'client.studio'
local PlacementCamera = require 'client.placement'

local DeviceUse = {}

local OPTION_USE, OPTION_BUSY, OPTION_MANAGE = 'evdev_use', 'evdev_busy', 'evdev_manage'
local OK = { ok = true }
local ICONS = { laptop = 'fa-solid fa-laptop', pc = 'fa-solid fa-desktop', terminal = 'fa-solid fa-display' }
local CONTROLS = { 1, 2, 21, 22, 23, 24, 25, 30, 31, 32, 33, 34, 35, 36, 37, 44, 45, 75, 140, 141, 142, 143 }
local PAUSE_CONTROLS = { 199, 200, 322 }
local PAUSE_GUARD_MS, PAUSE_GUARD_MAX_MS = 500, 10000
local MAPPING_MS = 100
local MEASURE_MS = 250
local FOCUS_HOLD_MS = 250
local PAGE_TIMEOUT_MS = 10000
local ANIM_LOAD_MS = 1500
local ARRIVE_DISTANCE, ARRIVE_HEADING, SNAP_DISTANCE = 0.15, 10.0, 0.65
local TASK_WALK = joaat('SCRIPT_TASK_GO_STRAIGHT_TO_COORD')
local TASK_GRACE_MS = 300
local ONE_SHOT_END = 0.95
local STAND_RADIUS, STAND_LOW, STAND_HIGH, STAND_CHECK_MS = 0.25, 0.30, 1.35, 1500
local FLOOR_ABOVE, FLOOR_BELOW = 0.5, 0.6
local FLOOR_DROP, DESK_BACK, EDGE_BELOW, BELLY = 2.2, 0.6, 0.03, 0.06
local WALK_SLIDE, ANIM_CHECK_MS = 0.3, 500
local VIEW_MARGIN, VIEW_MIN, VIEW_MAX_FOV = 0.1, 0.25, 110.0
local VIEW_FADE_MS, VIEW_CAMERA_MATCH = 150, 0.01
local PROMPT_LIFT = 0.12
local PROMPT_LOOK_MS = 100
local V = DeviceRules.vector

local session = nil
local targeted = {}
local stopping = false
local prompted = false
local pauseGuard = nil
local hooks = { open = {}, screen = {}, shown = {}, close = {} }

local function settings()
    return Config.devices
end

local function kindLabel(kind)
    return locale('kind_word_' .. kind)
end

local function horizontal(a, b)
    return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2)
end

local function headingError(a, b)
    return math.abs((a - b + 180.0) % 360.0 - 180.0)
end

local function emit(event, ...)
    for _, handler in ipairs(hooks[event]) do
        local ok, failure = pcall(handler, ...)

        if not ok then
            print(('[evolent_devices] device %s hook failed: %s'):format(event, tostring(failure)))
        end
    end
end

function DeviceUse.on(event, handler)
    if hooks[event] and type(handler) == 'function' then
        hooks[event][#hooks[event] + 1] = handler
    end
end

function DeviceUse.active()
    return session ~= nil
end

function DeviceUse.session()
    return session
end

function DeviceUse.key()
    return session and session.key or nil
end

function DeviceUse.stage()
    return session and session.stage or nil
end

function DeviceUse.closedText(reason)
    local key = 'closed_' .. tostring(reason)

    if lib.getLocales()[key] then
        return locale(key)
    end

    return Client.reasonText(reason)
end

function DeviceUse.allowed(record)
    if record.enabled == false then return false end

    local kinds = Client.kinds

    if type(kinds) == 'table' then
        for _, entry in ipairs(kinds) do
            if entry.kind == record.kind and entry.enabled == false then return false end
        end
    end

    return true
end

function DeviceUse.free()
    local ped = cache.ped

    return session == nil and not Nui.visible and not PlacementCamera.busy()
        and not IsPedInAnyVehicle(ped, false) and not IsEntityDead(ped) and not IsPedRagdoll(ped) and not IsEntityPositionFrozen(ped)
end

function DeviceUse.near(record)
    if not record or DeviceWorld.get(record.key) ~= record or not DoesEntityExist(record.entity) then return false end

    local coords = GetEntityCoords(cache.ped)

    if #(coords - record.at) > record.spec.use.reach then return false end

    return GetOffsetFromEntityGivenWorldCoords(record.entity, coords.x, coords.y, coords.z).y < -0.05
end

function DeviceUse.canInteract(record)
    return DeviceUse.allowed(record) and DeviceUse.free() and DeviceUse.near(record)
end

function DeviceUse.canManage(record)
    if not record then return false end

    local flags = DeviceWorld.flags(record.id)

    return type(flags) == 'table' and flags.admin == true and DeviceUse.free() and DeviceUse.near(record)
end

local function closeToken(token)
    CreateThread(function() Client.call('evdev:device:close', token) end)
end

local function quietTimecycle(state)
    if settings().session.clearTimecycle == false then return end

    local index = GetTimecycleModifierIndex()

    if type(index) ~= 'number' or index < 0 then return end

    local name = GetTimecycleModifierNameByIndex(index)

    if type(name) ~= 'string' or name == '' or GetTimecycleModifierIndexByName(name) ~= index then return end

    state.timecycle = { name = name, strength = GetTimecycleModifierStrength() }
    ClearTimecycleModifier()
end

local function restoreTimecycle(state)
    local saved = state.timecycle

    state.timecycle = nil

    if not saved or GetTimecycleModifierIndex() ~= -1 then return end

    SetTimecycleModifier(saved.name)
    SetTimecycleModifierStrength((tonumber(saved.strength) or 1.0) + 0.0)
end

local function pauseHeld()
    for _, control in ipairs(PAUSE_CONTROLS) do
        if Util.yes(IsDisabledControlPressed(0, control)) then return true end
    end

    return false
end

local function guardPause()
    local now = GetGameTimer()

    if Util.yes(IsPauseMenuActive()) then return end

    if pauseGuard then
        pauseGuard.heldAt = now

        return
    end

    local guard = { since = now, heldAt = now }

    pauseGuard = guard

    CreateThread(function()
        while pauseGuard == guard do
            local at = GetGameTimer()

            for _, control in ipairs(PAUSE_CONTROLS) do
                DisableControlAction(0, control, true)
            end

            if Util.yes(IsPauseMenuActive()) then
                SetPauseMenuActive(false)
            end

            if pauseHeld() then
                guard.heldAt = at
            end

            if at - guard.heldAt > PAUSE_GUARD_MS or at - guard.since > PAUSE_GUARD_MAX_MS then
                pauseGuard = nil

                return
            end

            Wait(0)
        end
    end)
end

function DeviceUse.close(reason)
    local state = session

    if not state then return end

    session = nil
    guardPause()
    Integrations.hud(false)

    local quick = stopping or DeviceWorld.isStopping()
    local cut = DeviceStudio.stop(state, quick)
    local ped = state.ped

    if state.token then
        closeToken(state.token)
        DeviceWorld.released(state.key)
    end

    if state.screen then
        DeviceScreens.close()
    end

    restoreTimecycle(state)
    Nui.send({ type = 'device', state = 'end' })

    if Nui.view == 'device' then
        Nui.visible, Nui.view = false, nil
        SetNuiFocus(false, false)
    end

    if state.camera then
        local camera, ease = state.camera, settings().session.cameraEaseMs

        if quick or cut then
            RenderScriptCams(false, false, 0, true, true)
            DestroyCam(camera, false)
        else
            RenderScriptCams(false, true, ease, true, true)

            CreateThread(function()
                Wait(ease + 50)
                DestroyCam(camera, false)
            end)
        end
    end

    if DoesEntityExist(ped) then
        if state.walking and GetScriptTaskStatus(ped, TASK_WALK) ~= 7 then
            ClearPedTasks(ped)
        end

        if state.anim then
            StopAnimTask(ped, state.anim.dict, state.anim.clip, 2.0)
        end

        if state.looking then
            TaskClearLookAt(ped)
        end

        if state.frozen then
            FreezeEntityPosition(ped, false)
        end

        if state.hidden then
            SetEntityLocallyVisible(ped)
        end
    end

    emit('close', state, reason)

    if reason then
        Client.notify(DeviceUse.closedText(reason), 'error')
    end
end

function DeviceUse.leave()
    local state = session

    if not state then return end
    if DeviceStudio.leave(state) then return end

    if state.stage ~= 'using' or (state.viewAlpha or 0) <= 0 then
        DeviceUse.close()

        return
    end

    state.stage, state.leaveSince, state.leaveAlpha = 'leaving', GetGameTimer(), state.viewAlpha
    guardPause()
end

local function cancelReason(state)
    local ped = state.ped

    if cache.ped ~= ped or not DoesEntityExist(ped) then
        return 'ped'
    end

    local record = state.record

    if DeviceWorld.get(state.key) ~= record or not DoesEntityExist(record.entity) then
        return 'device'
    end

    if IsEntityDead(ped) then
        return 'dead'
    end

    if IsPedRagdoll(ped) then
        return 'ragdoll'
    end

    if IsPedInAnyVehicle(ped, false) then
        return 'vehicle'
    end

    if IsPauseMenuActive() then
        return 'pause'
    end

    if IsEntityPositionFrozen(ped) and not state.frozen then
        return 'frozen'
    end

    local health, armour = GetEntityHealth(ped), GetPedArmour(ped)
    local lost = (state.health - health) + (state.armour - armour)

    state.health, state.armour = health, armour

    if lost >= settings().session.damage then
        return 'damage'
    end

    if #(GetEntityCoords(ped) - record.at) > state.spec.use.reach + settings().session.cancelReach then
        return 'distance'
    end

    if Nui.view ~= 'device' or PlacementCamera.busy() then
        return 'ui'
    end

    return nil
end

local function pageSize(state)
    return DeviceScreens.size() or state.spec.dui
end

local function project(point)
    local onScreen, x, y = GetScreenCoordFromWorldCoord(point.x + 0.0, point.y + 0.0, point.z + 0.0)

    if not Util.yes(onScreen) then return nil end

    return { x = x, y = y }
end

local function sendMapping(state, now, exact)
    local projected = {}

    for name, point in pairs(DeviceWorld.corners(state.record)) do
        projected[name] = project(point)
    end

    local values = DeviceRules.screenMapping(projected, pageSize(state)) or false

    state.mappedAt = now

    if DeviceRules.mappingChanged(state.mapping, values, exact and 0 or nil) then
        state.mapping = values
    end
end

local function overlay(state, rect)
    local values = rect and rect.mapping or state.mapping

    if values == nil or values == state.overlay then return end

    state.overlay = values
    Nui.send({ type = 'deviceScreen', screen = values })
end

local function ownCamera(state)
    if not state.camera or GetRenderingCam() ~= state.camera then return false end

    local coord = GetFinalRenderedCamCoord()

    return coord ~= nil and V.length(V.sub(coord, state.cameraAt)) <= VIEW_CAMERA_MATCH
end

local function measure(state, now)
    if now < (state.measureAt or 0) then return end

    state.measureAt = now + MEASURE_MS

    local width, height = GetActiveScreenResolution()
    local box = DeviceRules.pixelBox(DeviceRules.spriteRect(state.mapping, width, height), width, height)

    if not box then
        state.candidate = nil

        return
    end

    local key = ('%dx%d@%dx%d'):format(box.width, box.height, width, height)

    if key == state.boxKey then
        if box.x ~= state.box.x or box.y ~= state.box.y then
            state.box = box
        end

        return
    end

    if key == state.candidate or (not state.boxKey and DeviceRules.closeSize(box, pageSize(state))) then
        state.box, state.boxKey, state.candidate = box, key, nil
        state.boxScreen = { width = width, height = height }

        return
    end

    state.candidate = key
end

local function viewRect(state, now)
    local held = DeviceStudio.rect(state)

    if held then
        return held
    end

    if not state.hud or now < state.settledAt or not ownCamera(state) then return nil end

    if (state.mappedAt or -1) < state.settledAt then
        sendMapping(state, now, true)
    end

    measure(state, now)

    local box, size = state.box, pageSize(state)

    if not box then return nil end

    if state.sized and not state.viewSince then
        local wanted = DeviceRules.pageSize(state.spec.dui, box.width, box.height)

        if not DeviceRules.closeSize(wanted, size) and DeviceScreens.rebuild(wanted) then return nil end
    end

    if state.rectFor ~= box or state.rectWidth ~= size.width or state.rectHeight ~= size.height then
        state.rectFor, state.rectWidth, state.rectHeight = box, size.width, size.height
        state.rect = DeviceRules.pageRect(box, size, state.boxScreen.width, state.boxScreen.height)
    end

    return state.rect
end

local function drawView(state, now)
    local rect = viewRect(state, now)
    local txd, txn

    if rect then
        txd, txn = DeviceScreens.sprite()
    end

    overlay(state, txd and rect)

    if not txd then
        state.viewSince, state.viewAlpha, state.darkened = nil, 0.0, false
        DeviceScreens.dark(false)

        return
    end

    local fade = settings().session.viewFadeMs or VIEW_FADE_MS
    local alpha

    if state.stage == 'leaving' then
        alpha = state.leaveAlpha * (1.0 - DeviceRules.fadeShare(now - state.leaveSince, fade))
    else
        if not state.viewSince then
            state.viewSince = now
            DeviceScreens.seen()
        end

        alpha = DeviceRules.fadeShare(now - state.viewSince, fade)
    end

    state.viewAlpha = alpha

    if state.stage == 'using' then
        state.darkened = alpha >= 1.0 and settings().session.darkGlass ~= false
    end

    DeviceScreens.dark(state.darkened == true)

    local value = math.floor(alpha * 255 + 0.5)
    local tint = state.tint or 255

    if value > 0 then
        DrawSprite(txd, txn, rect.x, rect.y, rect.width, rect.height, 0.0, tint, tint, tint, value)
    end
end

local function share(state, now)
    local mirror = settings().mirror

    if mirror.enabled == false or not state.token then return end

    if not state.watched then return end

    local pointer = state.pendingPointer

    if pointer and state.privatePointer then
        state.pendingPointer, pointer = nil, nil
    end

    if pointer and now >= (state.pointerAt or 0) then
        state.pendingPointer = nil
        state.pointerAt = now + math.ceil(1000 / mirror.pointerHz)
        TriggerServerEvent('evdev:device:pointer', state.token, pointer.u, pointer.v)
    end

    local page = state.pendingState

    if page and now >= (state.stateAt or 0) then
        state.pendingState = nil
        state.stateAt = now + mirror.intervalMs
        TriggerServerEvent('evdev:device:state', state.token, page)
    end
end

local function beat(state)
    local token = state.token

    CreateThread(function()
        local result = Client.call('evdev:device:beat', token)

        if session == state and not result.ok and result.reason == 'device_closed' then
            DeviceUse.close('device_closed')
        end
    end)
end

local function monitor(state)
    local DeviceSounds = require 'client.sound'

    while session == state do
        if cancelReason(state) then
            DeviceUse.close()

            return
        end

        local now = GetGameTimer()

        for _, control in ipairs(CONTROLS) do
            DisableControlAction(0, control, true)
        end

        DisablePlayerFiring(cache.playerId, true)

        if state.hidden then
            SetEntityLocallyInvisible(state.ped)
            HideHudAndRadarThisFrame()
        end

        Integrations.hud(state.hidden == true)

        if state.stage == 'using' then
            if now < state.focusUntil then
                SetNuiFocus(true, true)
            end

            if not DeviceStudio.holds(state) and now >= (state.mappingAt or 0) then
                state.mappingAt = now + MAPPING_MS
                sendMapping(state, now)
            end

            share(state, now)
            DeviceSounds.flush(state, now)

            if not DeviceScreens.ready() and now - state.usingSince > PAGE_TIMEOUT_MS then
                DeviceUse.close('device_page_failed')

                return
            end

            if state.idleMs and now - state.inputAt > state.idleMs then
                DeviceUse.close('device_idle')

                return
            end
        end

        if state.stage == 'using' or state.stage == 'leaving' then
            drawView(state, now)
        end

        if state.stage == 'using' then
            DeviceStudio.frame(state, now)
            DeviceUse.animate(state, now)
        end

        if session ~= state then return end

        if state.stage == 'leaving' and state.viewAlpha <= 0 then
            DeviceUse.close()

            return
        end

        if state.token and now >= state.beatAt then
            state.beatAt = now + state.heartbeatMs
            beat(state)
        end

        Wait(0)
    end
end

local function loaded(dicts)
    for _, dict in ipairs(dicts) do
        if not HasAnimDictLoaded(dict) then return false end
    end

    return true
end

local function playBase(state, now)
    local anim = state.spec.anim
    local flag = state.pose and state.pose.flag or anim.flag or 49

    TaskPlayAnim(state.ped, anim.dict, anim.clip, 4.0, 4.0, -1, flag, 0.0, false, false, false)
    state.anim, state.oneShot = { dict = anim.dict, clip = anim.clip }, nil
    state.idleAt = DeviceRules.nextIdleAt(anim, now, math.random())
    state.animCheckAt = now + ANIM_CHECK_MS
end

local function playOnce(state, entry, now)
    local anim = state.spec.anim

    TaskPlayAnim(state.ped, entry.dict, entry.clip, 4.0, 4.0, -1, anim.oneShotFlag or 1048578, 0.0, false, false, false)
    state.anim, state.oneShot = { dict = entry.dict, clip = entry.clip }, { startedAt = now }
end

local function onceDone(state, now)
    local current = state.anim

    if now - state.oneShot.startedAt < TASK_GRACE_MS then return false end
    if not Util.yes(IsEntityPlayingAnim(state.ped, current.dict, current.clip, 3)) then return true end

    return GetEntityAnimCurrentTime(state.ped, current.dict, current.clip) >= ONE_SHOT_END
end

function DeviceUse.animate(state, now)
    local anim = state.spec.anim

    if not state.anim or type(anim) ~= 'table' then return end

    if not state.oneShot and now >= (state.animCheckAt or 0) then
        state.animCheckAt = now + ANIM_CHECK_MS

        if not Util.yes(IsEntityPlayingAnim(state.ped, state.anim.dict, state.anim.clip, 3)) then
            playBase(state, now)

            return
        end
    end

    local tap = anim.tap
    local tapReady = tap ~= nil and state.tapWanted == true and now - (state.tappedAt or -math.huge) >= (anim.tapGap or 0)

    if state.oneShot and not (tapReady and not state.oneShot.tap) then
        if onceDone(state, now) then
            state.tappedAt = state.oneShot.tap and now or state.tappedAt
            playBase(state, now)
        end

        return
    end

    if tapReady then
        state.tapWanted = false
        playOnce(state, tap, now)
        state.oneShot.tap = true

        return
    end

    if state.idleAt and now >= state.idleAt then
        playOnce(state, anim.idles[math.random(#anim.idles)], now)
    end
end

function DeviceUse.tapped(state)
    if state and state.anim and type(state.spec.anim) == 'table' and state.spec.anim.tap then
        state.tapWanted = true
    end
end

local function lookAtGlass(state)
    if not state.spec.anim.look then return end

    local basis = DeviceRules.screenBasis(DeviceWorld.corners(state.record))
    local centre = basis.centre

    TaskLookAtCoord(state.ped, centre.x + 0.0, centre.y + 0.0, centre.z + 0.0, -1, 2048, 3)
    state.looking = true
end

local function playAnim(state)
    local anim = state.spec.anim

    if not anim then return end

    local dicts = DeviceRules.animDicts(anim)

    for _, dict in ipairs(dicts) do
        RequestAnimDict(dict)
    end

    local deadline = GetGameTimer() + ANIM_LOAD_MS

    while session == state and not loaded(dicts) and GetGameTimer() < deadline do
        Wait(0)
    end

    if session ~= state or not HasAnimDictLoaded(anim.dict) then return end

    playBase(state, GetGameTimer())
    lookAtGlass(state)
end

local function lineHit(from, to, flags, ignore)
    local handle = StartExpensiveSynchronousShapeTestLosProbe(
        from.x,
        from.y,
        from.z,
        to.x,
        to.y,
        to.z,
        flags,
        ignore,
        7
    )

    local _, hit, at, _, entity = GetShapeTestResult(handle)

    if Util.yes(hit) and at then
        return at, entity
    end

    return nil
end

local function viewRoom(state, from, to)
    local flags, device = 1 + 2 + 16, state.record.entity
    local wall, entity = lineHit(from, to, flags, device)

    if wall and entity and entity ~= 0 and GetEntityAttachedTo(entity) == state.ped then
        wall = lineHit(V.add(wall, V.scale(V.unit(V.sub(to, from)), 0.05)), to, flags, device)
    end

    return wall and V.length(V.sub(wall, from)) or nil
end

local function standPlan(state)
    local spec = state.spec
    local keys, anim = spec.use.keyboard, spec.anim

    if type(keys) ~= 'table' or type(anim) ~= 'table' or type(anim.poses) ~= 'table' then return nil end

    local entity = state.record.entity
    local desk, feet = GetEntityCoords(entity), GetEntityCoords(state.ped)
    local here = GetOffsetFromEntityGivenWorldCoords(entity, feet.x, feet.y, feet.z)
    local front = GetOffsetFromEntityInWorldCoords(entity, keys.x + 0.0, math.min(here.y, keys.y - DESK_BACK), 0.0)
    local over = GetOffsetFromEntityInWorldCoords(entity, keys.x + 0.0, keys.y + 0.0, 0.0)
    local floor = lineHit(feet, { x = feet.x, y = feet.y, z = feet.z - FLOOR_DROP }, 1 + 16, state.ped)

    local edge = lineHit(
        { x = front.x, y = front.y, z = desk.z - EDGE_BELOW },
        { x = over.x, y = over.y, z = desk.z - EDGE_BELOW },
        1 + 16,
        entity
    )

    local short = 0.0

    if edge then
        short = math.max(0.0, keys.y - (GetOffsetFromEntityGivenWorldCoords(entity, edge.x, edge.y, edge.z).y - BELLY))
    end

    local ground = floor and floor.z or feet.z - 1.0
    local pose = DeviceRules.typingPose(anim, desk.z + keys.z - ground, short)
    local x, y = keys.x - pose.side, keys.y - math.max(pose.reach, short)

    return {
        pose = pose,
        spot = GetOffsetFromEntityInWorldCoords(entity, x + 0.0, y + 0.0, 0.0),
        clear = GetOffsetFromEntityInWorldCoords(entity, x + 0.0, y - STAND_RADIUS + BELLY, 0.0),
    }
end

local function standClear(state, target, plan)
    local feet = target.z - 1.0

    local floor = lineHit(
        { x = target.x, y = target.y, z = feet + FLOOR_ABOVE },
        { x = target.x, y = target.y, z = feet - FLOOR_BELOW },
        1 + 16,
        state.ped
    )

    if not floor then return false end

    local ground = floor.z

    local room = plan and plan.clear or target

    local test = StartShapeTestCapsule(
        room.x,
        room.y,
        ground + STAND_LOW,
        room.x,
        room.y,
        ground + STAND_HIGH,
        STAND_RADIUS,
        plan and 1 + 2 or 1 + 2 + 4 + 16,
        state.ped,
        7
    )

    local deadline = GetGameTimer() + STAND_CHECK_MS

    while session == state do
        local status, hit, _, _, entity = GetShapeTestResult(test)

        if status == 2 then
            return not Util.yes(hit) or (entity ~= 0 and entity == state.record.entity)
        end

        if status == 0 or GetGameTimer() >= deadline then return false end

        Wait(0)
    end

    return false
end

local function approach(state)
    state.stage = 'walking'

    local ped = state.ped
    local spot, heading = DeviceWorld.useSpot(state.record)
    local plan = standPlan(state)

    if plan then
        state.pose, spot = plan.pose, plan.spot
    end

    local coords = GetEntityCoords(ped)
    local target = vector3(spot.x, spot.y, coords.z)
    local clear = standClear(state, target, plan)

    if session ~= state then return end

    if clear and (horizontal(coords, target) > ARRIVE_DISTANCE or headingError(GetEntityHeading(ped), heading) > ARRIVE_HEADING) then
        TaskGoStraightToCoord(ped, target.x, target.y, target.z, 1.0, -1, heading, WALK_SLIDE)
        state.walking = true

        local started = GetGameTimer()
        local deadline = started + settings().session.walkMs

        while session == state and GetGameTimer() < deadline do
            if horizontal(GetEntityCoords(ped), target) <= ARRIVE_DISTANCE and headingError(GetEntityHeading(ped), heading) <= ARRIVE_HEADING then break end
            if GetGameTimer() - started > TASK_GRACE_MS and GetScriptTaskStatus(ped, TASK_WALK) == 7 then break end

            Wait(0)
        end

        if session ~= state then return end

        if GetScriptTaskStatus(ped, TASK_WALK) ~= 7 then
            ClearPedTasks(ped)
        end

        state.walking = false
    end

    local position = GetEntityCoords(ped)

    if clear and horizontal(position, target) <= SNAP_DISTANCE then
        SetEntityCoordsNoOffset(ped, target.x, target.y, position.z, false, false, false)
        SetEntityHeading(ped, heading + 0.0)
        FreezeEntityPosition(ped, true)
        state.frozen = true
    end

    playAnim(state)
end

local function startCamera(state)
    local spec = state.spec
    local basis = DeviceRules.screenBasis(DeviceWorld.corners(state.record))
    local aspect, fill, fov = GetAspectRatio(false), spec.camera.fill, spec.camera.fov + 0.0
    local distance = DeviceRules.cameraDistance(basis.width, basis.height, fov, aspect, fill)
    local reach = viewRoom(state, basis.centre, V.add(basis.centre, V.scale(basis.normal, distance)))
    local room = reach and reach - VIEW_MARGIN

    if room and room < distance then
        local closest = math.max(
            VIEW_MIN,
            DeviceRules.cameraDistance(basis.width, basis.height, VIEW_MAX_FOV, aspect, fill)
        )

        if room < closest then
            return false, 'device_view_blocked'
        end

        distance, fov = room, DeviceRules.cameraFov(basis.width, basis.height, room, aspect, fill)
    end

    local position = V.add(basis.centre, V.scale(basis.normal, distance))
    local camera = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)

    if not camera or camera == 0 then return false end

    SetCamCoord(camera, position.x, position.y, position.z)
    PointCamAtCoord(camera, basis.centre.x, basis.centre.y, basis.centre.z)
    SetCamFov(camera, fov)
    SetCamUseShallowDofMode(camera, false)
    SetCamDofStrength(camera, 0.0)
    SetCamMotionBlurStrength(camera, 0.0)

    local ease = settings().session.cameraEaseMs

    RenderScriptCams(true, true, ease, true, true)
    state.camera, state.cameraAt = camera, position
    state.settledAt = GetGameTimer() + ease
    quietTimecycle(state)

    return true
end

local function focus(state)
    local DeviceSounds = require 'client.sound'

    local started, reason = startCamera(state)

    if not started then
        DeviceUse.close(reason or 'device_camera')

        return
    end

    state.hidden = true
    state.hud, state.viewAlpha = DeviceRules.userView(state.spec) == 'hud', 0.0
    SetEntityLocallyInvisible(state.ped)
    DeviceScreens.show()

    local size = pageSize(state)

    SetNuiFocus(true, true)
    state.overlayToken = Util.hex(32)

    Nui.send({
        type = 'device',
        state = 'start',
        kind = state.kind,
        width = size.width,
        height = size.height,
        os = state.spec.os == true,
        token = state.overlayToken,
        sound = DeviceSounds.forSession(state.kind),
    })

    local now = GetGameTimer()

    state.focusUntil, state.usingSince, state.inputAt, state.stage = now + FOCUS_HOLD_MS, now, now, 'using'
    emit('shown', state)
end

local function sizedView(spec)
    if DeviceRules.userView(spec) ~= 'hud' or type(spec.camera) ~= 'table' then return false end

    return DeviceRules.screenMode(spec) ~= 'world' or settings().session.darkGlass ~= false
end

local function plannedSize(state)
    if not state.sized then return nil end

    local basis = DeviceRules.screenBasis(DeviceWorld.corners(state.record))
    local width, height = GetActiveScreenResolution()

    local glassWidth, glassHeight = DeviceRules.glassPixels(
        basis.width,
        basis.height,
        GetAspectRatio(false),
        state.spec.camera.fill,
        width,
        height
    )

    return DeviceRules.pageSize(state.spec.dui, glassWidth, glassHeight)
end

local function refusal(result)
    local data = type(result.data) == 'table' and result.data or {}

    if type(data.text) == 'string' and data.text ~= '' then
        return data.text
    end

    return Client.reasonText(result.reason or 'no_response')
end

function DeviceUse.open(record)
    if session or not DeviceUse.canInteract(record) then return end

    if DeviceWorld.busy(record.key) then
        Client.notify(Client.reasonText('device_in_use'), 'error')

        return
    end

    local ped = cache.ped

    local state = {
        record = record,
        key = record.key,
        kind = record.kind,
        spec = record.spec,
        ped = ped,
        stage = 'connecting',
        health = GetEntityHealth(ped),
        armour = GetPedArmour(ped),
        heartbeatMs = Config.general.session.heartbeatSeconds * 1000,
        studioSettings = DeviceStudio.settingsFor(record),
        sized = sizedView(record.spec),
    }

    session = state
    Nui.visible, Nui.view = true, 'device'
    DeviceUse.hidePrompt()
    CreateThread(function() monitor(state) end)
    local result = Client.call('evdev:device:open', record.id)
    local data = type(result.data) == 'table' and result.data or {}

    if session ~= state then
        if result.ok and type(data.token) == 'string' then
            closeToken(data.token)
            DeviceWorld.released(record.key)
        end

        return
    end

    if not result.ok or type(data.token) ~= 'string' then
        DeviceUse.close()
        Client.notify(result.ok and Client.reasonText('no_response') or refusal(result), 'error')

        return
    end

    state.token = data.token

    if Util.integer(data.heartbeat, 2, 30) then
        state.heartbeatMs = data.heartbeat * 1000
    end

    if Util.integer(data.idleMinutes, 1, 240) then
        state.idleMs = data.idleMinutes * 60000
    end

    local bright = type(data.screen) == 'table' and Util.integer(data.screen.brightness, 20, 100) or nil

    if bright and not record.spec.os then
        state.tint = math.floor(255 * bright / 100 + 0.5)
    end

    state.beatAt = GetGameTimer() + state.heartbeatMs
    state.opened = data
    emit('open', state, data)

    if session ~= state then return end

    state.screen = DeviceScreens.open(record, data, plannedSize(state))
    emit('screen', state)

    if session ~= state then return end

    approach(state)

    if session ~= state then return end

    focus(state)
end

local function rayPixel(state, x, y)
    if not Util.isFinite(x) or not Util.isFinite(y) or x < 0 or x > 1 or y < 0 or y > 1 then return nil end

    local origin, direction = GetWorldCoordFromScreenCoord(x + 0.0, y + 0.0)
    local u, v = DeviceRules.uvFromRay(origin, direction, DeviceWorld.corners(state.record))

    if not u or u < 0 or u > 1 or v < 0 or v > 1 then return nil end

    local size = pageSize(state)

    return DeviceRules.pixel(math.min(size.width - 1, u * size.width), math.min(size.height - 1, v * size.height), size)
end

local function fromOverlay(data)
    local state = session

    return state ~= nil and type(data) == 'table' and type(state.overlayToken) == 'string' and data.__d == state.overlayToken
end

RegisterNUICallback('device:close', function(data, respond)
    respond(OK)

    if not fromOverlay(data) and not DeviceScreens.ownPage(data) then return end

    DeviceUse.leave()
end)

RegisterNUICallback('device:pointer', function(data, respond)
    local DeviceSounds = require 'client.sound'

    respond(OK)

    local state = session

    if not state or state.stage ~= 'using' or not fromOverlay(data) then return end

    local button = DeviceRules.cleanButton(data.button)

    if not button then return end

    local size = pageSize(state)
    local px, py

    if data.px ~= nil or data.py ~= nil then
        px, py = DeviceRules.pixel(data.px, data.py, size)
    else
        px, py = rayPixel(state, data.x, data.y)
    end

    state.inputAt = GetGameTimer()

    if data.type == 'up' then
        DeviceScreens.mouse('up', px, py, 0, button)

        return
    end

    if not px then return end

    if data.type == 'dblclick' then
        DeviceScreens.sendOwn({ type = 'deviceDblClick', x = px, y = py })

        return
    end

    if data.type ~= 'move' and data.type ~= 'down' and data.type ~= 'wheel' then return end

    DeviceScreens.mouse(data.type, px, py, tonumber(data.delta) or 0, button)

    if data.type == 'down' then
        DeviceUse.tapped(state)
        DeviceSounds.note(state, button)
    end

    if data.type ~= 'wheel' then
        local u, v = DeviceRules.pointerShare(px, py, size)

        if u then
            state.pendingPointer = { u = u, v = v }
        end
    end
end)

RegisterNUICallback('device:key', function(data, respond)
    respond(OK)

    local state = session

    if not state or state.stage ~= 'using' or not fromOverlay(data) then return end

    local key = DeviceRules.cleanKey(data)

    if not key then return end

    state.inputAt = GetGameTimer()
    key.type = 'deviceKey'
    DeviceScreens.sendOwn(key)
end)

RegisterNUICallback('device:state', function(data, respond)
    respond(OK)

    local state = session

    if not state or not DeviceScreens.ownPage(data) then return end

    if data.privatePointer ~= nil then
        state.privatePointer = data.privatePointer == true
    end

    if data.editing ~= nil and state.editing ~= (data.editing == true) then
        state.editing = data.editing == true
        Nui.send({ type = 'deviceEditing', editing = state.editing })
    end

    if data.state ~= nil then
        local clean = DeviceRules.cleanDeviceState(state.kind, data.state, settings().mirror)

        if clean then
            state.lastState = clean

            if state.watched then
                state.pendingState = clean
            end
        end
    end
end)

RegisterNetEvent('evdev:client:deviceWatched', function(id, on)
    local state = session

    if not state or state.record.id ~= id then return end

    state.watched = on == true

    if state.watched then
        state.pendingState, state.stateAt = state.lastState, 0
    else
        state.pendingState, state.pendingPointer = nil, nil
    end
end)

RegisterNUICallback('device:frozen', function(data, respond)
    respond(OK)

    if not fromOverlay(data) then return end

    DeviceStudio.frozen(session, data.ok == true)
end)

RegisterNUICallback('device:studio', function(data, respond)
    respond(OK)

    local state = session

    if not state or not DeviceScreens.ownPage(data) then return end
    if state.stage ~= 'using' and data.act ~= 'window' and data.act ~= 'car' then return end

    DeviceStudio.action(state, data)
end)

RegisterNetEvent('evdev:client:sessionClosed', function(id, reason)
    if not session or session.key ~= id then return end

    DeviceUse.close(type(reason) == 'string' and reason or 'device_closed')
end)

local function targetOptions(record)
    local reach = record.spec.use.reach

    return {
        {
            name = OPTION_USE,
            icon = ICONS[record.kind] or 'fa-solid fa-display',
            label = locale('device_use'),
            distance = reach,
            canInteract = function()
        return DeviceUse.canInteract(record) and not DeviceWorld.busy(record.key)
    end,
            onSelect = function() CreateThread(function() DeviceUse.open(record) end) end,
        },
        {
            name = OPTION_BUSY,
            icon = 'fa-solid fa-lock',
            label = locale('device_in_use'),
            distance = reach,
            canInteract = function()
        return DeviceUse.canInteract(record) and DeviceWorld.busy(record.key)
    end,
            onSelect = function() Client.notify(Client.reasonText('device_in_use'), 'error') end,
        },
        {
            name = OPTION_MANAGE,
            icon = 'fa-solid fa-sliders',
            label = locale('device_manage'),
            distance = reach,
            canInteract = function() return DeviceUse.canManage(record) end,
            onSelect = function() TriggerServerEvent('evdev:server:openAdmin', record.id) end,
        },
    }
end

local function attach(record)
    if stopping or targeted[record.key] == record.entity or not Integrations.targetAvailable() then return end

    if Integrations.addEntityTarget(record.entity, targetOptions(record)) then
        targeted[record.key] = record.entity
    end
end

local function detach(record)
    local entity = targeted[record.key]

    if not entity then return end

    targeted[record.key] = nil
    Integrations.removeEntityTarget(entity, { OPTION_USE, OPTION_BUSY, OPTION_MANAGE })
end

function DeviceUse.hidePrompt()
    if not prompted then return end

    prompted = false
    Integrations.hidePrompt()
end

local function promptAnchor(record)
    if not record.promptAt and record.point and record.spec then
        local corners = DeviceRules.worldCorners(record.point, record.spec)

        record.promptAt = vector3(
            (corners.TL.x + corners.TR.x) * 0.5,
            (corners.TL.y + corners.TR.y) * 0.5,
            math.max(corners.TL.z, corners.TR.z) + PROMPT_LIFT
        )
    end

    return record.promptAt
end

local function promptFor(record, busy)
    local option = { key = settings().interaction.keyLabel, label = locale('device_prompt_use', kindLabel(record.kind)), main = not busy, off = busy }

    return {
        options = { option },
        why = busy and locale('device_prompt_busy') or nil,
        icon = 'user',
        anchor = promptAnchor(record),
    }
end

local function showPrompt(key, record, busy)
    if prompted == key then return end

    prompted = key
    Integrations.showPrompt(promptFor(record, busy))
end

DeviceWorld.on('spawn', attach)

DeviceWorld.on('despawn', function(record)
    detach(record)

    if session and session.key == record.key then
        DeviceUse.close()
    end
end)

AddEventHandler('onClientResourceStart', function(name)
    if name ~= 'ox_target' then return end

    CreateThread(function()
        Wait(500)
        targeted = {}

        for _, record in pairs(DeviceWorld.spawned) do
            attach(record)
        end
    end)
end)

AddEventHandler('onClientResourceStop', function(name)
    if name == 'ox_target' then
        targeted = {}
    end
end)

Bridge.onLogout(function()
    DeviceUse.close()
end)

CreateThread(function()
    local reach = 0.0

    for _, kind in ipairs(DeviceRules.kinds()) do
        reach = math.max(reach, Config.kinds[kind].use.reach)
    end

    local key = settings().interaction.key
    local lookAt, found, offered = 0, nil, false

    while not stopping do
        local wait, shown = 500, false

        if not session and next(DeviceWorld.spawned) and not Integrations.targetAvailable() then
            local now = GetGameTimer()

            if now >= lookAt then
                lookAt = now + PROMPT_LOOK_MS
                found = DeviceWorld.nearest(GetEntityCoords(cache.ped), reach + 4.0)
                offered = found ~= nil and DeviceUse.canInteract(found)
            end

            local record = found

            if record and DeviceWorld.get(record.key) == record then
                wait = PROMPT_LOOK_MS

                if offered then
                    shown = true

                    if DeviceWorld.busy(record.key) then
                        showPrompt('busy:' .. record.key, record, true)
                    else
                        wait = 0
                        showPrompt('use:' .. record.key, record, false)

                        if IsControlJustReleased(0, key) then
                            lookAt = 0

                            CreateThread(function() DeviceUse.open(record) end)
                        end
                    end
                end
            end
        else
            found, offered, lookAt = nil, false, 0
        end

        if not shown then
            DeviceUse.hidePrompt()
        end

        Wait(wait)
    end
end)

AddEventHandler('onResourceStop', function(name)
    if name ~= GetCurrentResourceName() then return end

    stopping = true
    DeviceUse.close()
    DeviceUse.hidePrompt()

    for key, entity in pairs(targeted) do
        targeted[key] = nil
        Integrations.removeEntityTarget(entity, { OPTION_USE, OPTION_BUSY, OPTION_MANAGE })
    end
end)

return DeviceUse
