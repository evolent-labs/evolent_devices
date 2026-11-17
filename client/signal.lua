local Config = require 'config'
local Bridge = require 'bridge'
local Util = require 'shared.util'
local SignalRules = require 'shared.signal'
local DeviceWorld = require 'client.world'
local PlacementCamera = require 'client.placement'
local AdminPlacement = require 'client.placement_admin'

local SignalMasts = { spawned = {}, list = {} }

local SCAN_MS = 1000
local KEEP = 30.0
local stopping = false
local hidden = {}

local function cleanList(value)
    local list = {}

    for _, mast in ipairs(type(value) == 'table' and value or {}) do
        if type(mast) == 'table' and Util.integer(mast.id, 1) and SignalRules.isMast(mast.model)
            and Util.isFinite(mast.x) and Util.isFinite(mast.y) and Util.isFinite(mast.z) then
            list[mast.id] = {
                id = mast.id,
                model = mast.model,
                x = mast.x + 0.0,
                y = mast.y + 0.0,
                z = mast.z + 0.0,
                h = (Util.isFinite(mast.h) and mast.h or 0.0) + 0.0,
            }
        end
    end

    return list
end

local function signature(mast)
    return ('%s|%.2f|%.2f|%.2f|%.1f'):format(mast.model, mast.x, mast.y, mast.z, mast.h)
end

local function despawn(id)
    local entry = SignalMasts.spawned[id]

    if not entry then return end

    SignalMasts.spawned[id] = nil

    if DoesEntityExist(entry.entity) then
        DeleteEntity(entry.entity)
    end
end

local function spawn(mast)
    local hash = joaat(mast.model)

    if not IsModelInCdimage(hash) then return end

    RequestModel(hash)

    local deadline = GetGameTimer() + 5000

    while not HasModelLoaded(hash) and GetGameTimer() < deadline do
        Wait(0)
    end

    if not HasModelLoaded(hash) or stopping then return end

    local entity = CreateObjectNoOffset(hash, mast.x, mast.y, mast.z, false, false, false)

    SetModelAsNoLongerNeeded(hash)

    if not entity or entity == 0 then return end

    SetEntityHeading(entity, mast.h)
    FreezeEntityPosition(entity, true)
    SetEntityAsMissionEntity(entity, true, true)

    if hidden[mast.id] then
        SetEntityVisible(entity, false, false)
        SetEntityCollision(entity, false, false)
    end

    SignalMasts.spawned[mast.id] = { entity = entity, signature = signature(mast) }
end

local function stream()
    local coords = GetEntityCoords(cache.ped)
    local range = Config.signal.streamDistance
    local world = (DeviceWorld.space or 'b0') == 'b0'

    for id, mast in pairs(SignalMasts.list) do
        local current = SignalMasts.spawned[id]
        local distance = #(coords - vector3(mast.x, mast.y, mast.z))

        if current and current.signature ~= signature(mast) then
            despawn(id)
            current = nil
        end

        if world and not current and distance <= range then
            spawn(mast)
        elseif current and (not world or distance > range + KEEP) then
            despawn(id)
        end
    end

    for id in pairs(SignalMasts.spawned) do
        if not SignalMasts.list[id] then
            despawn(id)
        end
    end
end

function SignalMasts.entity(id)
    local entry = SignalMasts.spawned[id]

    return entry and entry.entity or nil
end

function SignalMasts.hide(id, on)
    hidden[id] = on and true or nil

    local entity = SignalMasts.entity(id)

    if entity and DoesEntityExist(entity) then
        SetEntityVisible(entity, not on, false)
        SetEntityCollision(entity, not on, not on)
    end
end

AddStateBagChangeHandler('evdev:masts', 'global', function(_, _, value)
    SignalMasts.list = cleanList(value)
end)

AdminPlacement.register('antenna', function(data)
    local model = SignalRules.isMast(data.model) and data.model or Config.signal.masts[1]
    local id = Util.integer(tonumber(data.antennaId), 1)
    local radius = tonumber(data.radius)

    local request = {
        kind = 'prop',
        model = model,
        title = locale('ui_placement_mast_title'),
        reach = Util.isFinite(radius) and radius > 0 and radius or Config.signal.radius,
    }

    local mast = id and SignalMasts.list[id]
    local placed = false

    if mast then
        request.start = { x = mast.x, y = mast.y, z = mast.z, w = mast.h }
        SignalMasts.hide(id, true)

        CreateThread(function()
            Wait(250)

            while PlacementCamera.busy() do
                Wait(250)
            end

            Wait(400)

            if placed then
                Wait(5000)
            end

            SignalMasts.hide(id, false)
        end)
    end

    return request, function(point)
        placed = true

        return {
            ok = true,
            position = { x = point.x, y = point.y, z = point.z, h = point.w },
            space = DeviceWorld.space or 'b0',
        }
    end
end)

CreateThread(function()
    SignalMasts.list = cleanList(GlobalState['evdev:masts'])

    while not stopping do
        if Bridge.isPlayerReady() then
            stream()
        end

        Wait(SCAN_MS)
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end

    stopping = true

    for id in pairs(SignalMasts.spawned) do
        despawn(id)
    end
end)

return SignalMasts
