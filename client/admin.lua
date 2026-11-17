local Client = require 'client.main'
local Nui = require 'client.nui'
local Tablet = require 'client.tablet'

local AdminPanel = { level = nil }

local STAND = { laptop = 0.7, pc = 0.75, terminal = 0.9 }

RegisterNetEvent('evdev:client:openAdmin', function(payload)
    if type(payload) ~= 'table' or type(payload.token) ~= 'string' then return end

    AdminPanel.level = payload.level

    if Tablet.prop then
        Tablet.close('panel')
    end

    Nui.open('admin', { token = payload.token, level = payload.level, device = payload.device })
end)

RegisterNetEvent('evdev:client:kinds', function(list)
    if type(list) ~= 'table' then return end

    Client.kinds = list

    if Nui.adminOpen() then
        Nui.send({ type = 'kinds', kinds = list })
    end
end)

RegisterNetEvent('evdev:client:counts', function(data)
    if type(data) ~= 'table' or type(data.counts) ~= 'table' or not Nui.adminOpen() then return end

    Nui.send({ type = 'counts', counts = data.counts, waiting = tonumber(data.waiting) })
end)

RegisterNetEvent('evdev:client:goto', function(spot)
    if type(spot) ~= 'table' or type(spot.x) ~= 'number' then return end

    local heading = tonumber(spot.h) or 0.0
    local reach = STAND[spot.kind] or 0.8
    local radians = math.rad(heading)
    local x, y, z = spot.x + math.sin(radians) * reach, spot.y - math.cos(radians) * reach, spot.z + 1.0
    local ped = cache.ped

    RequestCollisionAtCoord(x, y, z)
    SetEntityCoords(ped, x, y, z, false, false, false, false)

    local found, ground = false, z

    for _ = 1, 20 do
        found, ground = GetGroundZFor_3dCoord(x, y, z + 1.0, false)

        if found then break end

        Wait(50)
    end

    if found then
        SetEntityCoords(ped, x, y, ground, false, false, false, false)
    end

    SetEntityHeading(ped, heading)
end)

return AdminPanel
