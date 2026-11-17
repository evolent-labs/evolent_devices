local Config = require 'config'
local Integrations = require 'integrations'
local Bridge = require 'bridge'
local Util = require 'shared.util'
local Client = require 'client.main'
local Nui = require 'client.nui'
local DeviceWorld = require 'client.world'
local DeviceUse = require 'client.use'
local PlacementCamera = require 'client.placement'
local AdminPlacement = require 'client.placement_admin'
local Tablet = require 'client.tablet'
local ItemAim = require 'client.aim'

local DeviceItems = {}

local OPTION_PICKUP = 'evdev_pickup'
local PICKUP_REACH = 2.5
local targeted = {}
local stopping = false

local function slotOf(slot)
    if type(slot) ~= 'table' then return nil end

    return Util.integer(tonumber(slot.slot), 1, 10000)
end

local function refuse(reason)
    Client.notify(Client.reasonText(reason), 'error')
end

function DeviceItems.busy()
    local ped = cache.ped

    if IsEntityDead(ped) or Bridge.isDown() then
        return 'device_down'
    end

    if IsPedInAnyVehicle(ped, false) then
        return 'device_vehicle'
    end

    if DeviceUse.active() or PlacementCamera.busy() or ItemAim.busy() or Nui.visible or Tablet.prop then
        return 'item_busy'
    end

    return nil
end

local function kindWord(kind)
    return locale('kind_word_' .. tostring(kind))
end

function DeviceItems.place(slot)
    local number = slotOf(slot)

    if not number then return false end

    local reason = DeviceItems.busy()

    if reason then
        return refuse(reason)
    end

    local result = Client.call('evdev:item:begin', number)
    local data = type(result.data) == 'table' and result.data or nil

    if not result.ok or not data or type(data.ticket) ~= 'string' then
        return refuse(result.ok and 'no_response' or result.reason)
    end

    local started, why = ItemAim.start({ kind = data.kind, model = data.model, rules = data.rules, devices = AdminPlacement.others(), title = locale('kind_' .. data.kind) }, function(point)
        if not point then return false end

        local placed = Client.call('evdev:item:place', data.ticket, {
            x = point.x,
            y = point.y,
            z = point.z,
            h = point.w,
        })

        if not placed.ok then
            refuse(placed.reason)

            return false
        end

        Client.notify(locale('item_placed', locale('kind_' .. data.kind)), 'success')

        return true
    end)

    if not started then
        refuse(why)
    end

    return started
end

function DeviceItems.pickup(id)
    local reason = DeviceItems.busy()

    if reason then
        return refuse(reason)
    end

    local record = DeviceWorld.get(id)
    local result = Client.call('evdev:item:pickup', id)

    if not result.ok then
        return refuse(result.reason)
    end

    local other = type(result.data) == 'table' and result.data.held == 'other'

    Client.notify(
        locale(other and 'item_picked_up_other' or 'item_picked_up', kindWord(record and record.kind or 'laptop')),
        other and 'inform' or 'success'
    )
end

function DeviceItems.tablet(slot)
    local number = slotOf(slot)

    if not number then return false end

    if Tablet.prop then
        return Tablet.close('item')
    end

    return Tablet.take(number)
end

local function free()
    return not ItemAim.busy() and DeviceUse.free()
end

local function flags(record)
    local value = DeviceWorld.flags(record.id)

    return type(value) == 'table' and value or nil
end

local function options(record)
    return {
        {
            name = OPTION_PICKUP,
            icon = 'fa-solid fa-hand',
            label = locale('device_pickup'),
            distance = PICKUP_REACH,
            canInteract = function()
                local own = flags(record)

                return own ~= nil and own.pickup == true and free() and not DeviceWorld.busy(record.key)
            end,
            onSelect = function() CreateThread(function() DeviceItems.pickup(record.id) end) end,
        },
    }
end

local function attach(record)
    if stopping or not record.item or targeted[record.key] == record.entity then return end

    if Integrations.addEntityTarget(record.entity, options(record)) then
        targeted[record.key] = record.entity
    end
end

local function detach(record)
    local entity = targeted[record.key]

    if not entity then return end

    targeted[record.key] = nil
    Integrations.removeEntityTarget(entity, { OPTION_PICKUP })
end

DeviceWorld.on('spawn', attach)
DeviceWorld.on('despawn', detach)

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

RegisterNetEvent('evdev:client:tabletAway', function(reason)
    if Tablet.prop then
        Tablet.close(reason == 'lost' and 'lost' or 'item')
    end
end)

exports('placeItem', function(_, slot)
    CreateThread(function() DeviceItems.place(slot) end)
end)

RegisterNetEvent('evdev:client:useItem', function(kind, slot)
    if type(kind) ~= 'string' or not Config.items[kind] then return end

    CreateThread(function()
        if kind == 'tablet' then
            DeviceItems.tablet({ slot = slot })
        else
            DeviceItems.place({ slot = slot })
        end
    end)
end)

exports('useTablet', function(_, slot)
    CreateThread(function() DeviceItems.tablet(slot) end)
end)

Bridge.onLogout(function()
    ItemAim.cancel()
end)

AddEventHandler('onResourceStop', function(name)
    if name ~= GetCurrentResourceName() then return end

    stopping = true

    for key, entity in pairs(targeted) do
        targeted[key] = nil
        Integrations.removeEntityTarget(entity, { OPTION_PICKUP })
    end
end)

return DeviceItems
