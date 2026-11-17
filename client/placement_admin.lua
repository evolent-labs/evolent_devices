local Util = require 'shared.util'
local DeviceRules = require 'shared.rules'
local Marker = require 'client.marker'
local Nui = require 'client.nui'
local DeviceWorld = require 'client.world'
local DeviceUse = require 'client.use'
local PlacementCamera = require 'client.placement'
local ItemAim = require 'client.aim'

local AdminPlacement = { kinds = {} }

local RESTORE_MS = 5000

local function others(exceptId)
    local list = {}
    local space = DeviceWorld.space or 'b0'

    for id, view in pairs(DeviceWorld.devices) do
        if id ~= exceptId and view.space == space then
            list[#list + 1] = {
                id = id,
                kind = view.kind,
                model = view.model,
                x = view.x,
                y = view.y,
                z = view.z,
                w = view.h,
            }
        end
    end

    return list
end

AdminPlacement.others = others

function AdminPlacement.register(kind, builder)
    if type(kind) ~= 'string' or type(builder) ~= 'function' or DeviceRules.spec(kind) then return false end

    AdminPlacement.kinds[kind] = builder

    return true
end

AdminPlacement.register('zone', function(data)
    local radius = Util.isFinite(tonumber(data.radius)) and tonumber(data.radius) or 15.0

    return {
        kind = 'zone',
        ring = { radius = radius, min = PlacementCamera.ZONE.min, max = PlacementCamera.ZONE.max },
        title = locale('ui_placement_zone_title'),
    }, function(point)
        return {
            ok = true,
            position = { x = point.x, y = point.y, z = point.z, h = point.w },
            radius = point.radius,
            space = DeviceWorld.space or 'b0',
        }
    end
end)

function AdminPlacement.request(data)
    if type(data) ~= 'table' or type(data.kind) ~= 'string' then
        return nil, 'invalid_kind'
    end

    local builder = AdminPlacement.kinds[data.kind]

    if builder then
        return builder(data)
    end

    local spec = DeviceRules.spec(data.kind)

    if not spec then
        return nil, 'invalid_kind'
    end

    local id = Util.integer(tonumber(data.deviceId), 1)

    local request = {
        kind = 'device',
        device = data.kind,
        model = data.variant,
        devices = others(id),
        title = locale('kind_' .. data.kind),
    }

    if id then
        local view = DeviceWorld.devices[id]

        if not view then
            return nil, 'unknown_device'
        end

        local record = DeviceWorld.get(id)

        request.start = { x = view.x, y = view.y, z = view.z, w = view.h }
        request.moving = record and record.entity or nil
        request.model = request.model or view.model
        request.accent = type(view.look) == 'table' and view.look.accent or nil
    end

    return request, function(point)
        return {
            ok = true,
            position = { x = point.x, y = point.y, z = point.z, h = point.w },
            surface = spec.placeOn == 'surface' and point.snap ~= false,
        }
    end
end

local function focusPanel()
    if Nui.adminOpen() then
        SetNuiFocus(true, true)
    end
end

function AdminPlacement.start(data, respond)
    if PlacementCamera.busy() or DeviceUse.active() then
        respond({ ok = false, reason = 'busy' })

        return
    end

    local request, finish = AdminPlacement.request(data)

    if not request then
        respond({ ok = false, reason = finish or 'invalid_kind' })

        return
    end

    request.slots = PlacementCamera.slots(data.slots)

    SetNuiFocus(false, false)

    local started, reason = PlacementCamera.start(request, function(point, outcome, moving)
        focusPanel()

        if outcome ~= 'confirm' or not point then
            respond({ ok = false, reason = 'cancelled' })

            return
        end

        respond(finish(point))

        if moving then
            CreateThread(function()
                local deadline = GetGameTimer() + RESTORE_MS

                while GetGameTimer() < deadline do
                    Wait(250)
                end

                if DoesEntityExist(moving) then
                    PlacementCamera.restore(moving)
                end
            end)
        end
    end)

    if not started then
        focusPanel()
        respond({ ok = false, reason = reason or 'busy' })
    end
end

function AdminPlacement.forScript(data, done)
    if type(done) ~= 'function' and type(done) ~= 'table' then
        return false, 'invalid_definition'
    end

    if type(data) ~= 'table' or not DeviceRules.spec(data.kind) or data.kind == 'tablet' then
        return false, 'invalid_kind'
    end

    if PlacementCamera.busy() or DeviceUse.active() or ItemAim.busy() then
        return false, 'busy'
    end

    local request, finish = AdminPlacement.request({ kind = data.kind, deviceId = data.deviceId })

    if not request then
        return false, finish or 'invalid_kind'
    end

    if type(data.title) == 'string' and data.title ~= '' then
        request.title = data.title:sub(1, 48)
    end

    if Marker.parse(data.accent) then
        request.accent = data.accent
    end

    local started, reason = PlacementCamera.start(request, function(point, outcome, moving)
        if outcome ~= 'confirm' or not point then
            pcall(done, nil, 'cancelled')

            return
        end

        local position = finish(point).position

        pcall(done, {
            x = position.x,
            y = position.y,
            z = position.z,
            h = position.h,
            surface = point.snap ~= false,
        })

        if moving then
            Wait(RESTORE_MS)

            if DoesEntityExist(moving) then
                PlacementCamera.restore(moving)
            end
        end
    end)

    if not started then
        return false, reason or 'busy'
    end

    return true
end

exports('placeDevice', function(data, done)
    return AdminPlacement.forScript(data, done)
end)

return AdminPlacement
