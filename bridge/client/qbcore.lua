local Config = require 'config'
local Bridge = require 'bridge'

if not Bridge.uses('qbcore') then return end

local CORE = 'qb-core'
local NOTIFY_KINDS = { inform = 'primary', success = 'success', error = 'error', warning = 'error' }
local metadata = nil
local core = nil

local function playerData()
    if not core then
        local ok, object = pcall(function() return exports[CORE]:GetCoreObject() end)

        core = ok and type(object) == 'table' and object or nil
    end

    local calls = core and core.Functions

    if type(calls) ~= 'table' or not calls.GetPlayerData then return nil end

    local ok, data = pcall(calls.GetPlayerData)

    return ok and type(data) == 'table' and data or nil
end

local function current()
    if not metadata then
        local data = playerData()

        metadata = data and type(data.metadata) == 'table' and data.metadata or nil
    end

    return metadata or {}
end

function Bridge.isPlayerReady()
    return LocalPlayer.state.isLoggedIn == true
end

function Bridge.onReady(callback)
    RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
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

AddEventHandler('onClientResourceStart', function(resource)
    if resource == CORE then
        core = nil
    end
end)

function Bridge.isDown()
    local data = current()

    return LocalPlayer.state.isDead == true or data.isdead == true or data.inlaststand == true
end

function Bridge.isRestrained()
    return current().ishandcuffed == true
end

function Bridge.notify(text, kind)
    if Config.notifyWith == 'framework' then
        TriggerEvent('QBCore:Notify', text, NOTIFY_KINDS[kind] or 'primary')

        return
    end

    lib.notify({ title = locale('brand'), description = text, type = kind or 'inform' })
end
