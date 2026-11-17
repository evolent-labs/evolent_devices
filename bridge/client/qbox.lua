local Bridge = require 'bridge'

if not Bridge.uses('qbox') then return end

local metadata = nil

function Bridge.isPlayerReady()
    return LocalPlayer.state.isLoggedIn == true
end

function Bridge.onReady(callback)
    AddEventHandler('QBCore:Client:OnPlayerLoaded', function()
        callback()
    end)
end

function Bridge.onLogout(callback)
    RegisterNetEvent('QBCore:Client:OnPlayerUnload', function()
        metadata = nil
        callback()
    end)
end

RegisterNetEvent('QBCore:Player:SetPlayerData', function(data)
    metadata = type(data) == 'table' and type(data.metadata) == 'table' and data.metadata or nil
end)

function Bridge.isDown()
    return LocalPlayer.state.isDead == true
end

function Bridge.isRestrained()
    if not metadata then
        local ok, data = pcall(function() return exports.qbx_core:GetPlayerData() end)

        metadata = ok and type(data) == 'table' and type(data.metadata) == 'table' and data.metadata or nil
    end

    return metadata ~= nil and metadata.ishandcuffed == true
end

function Bridge.notify(text, kind)
    lib.notify({ title = locale('brand'), description = text, type = kind or 'inform' })
end
