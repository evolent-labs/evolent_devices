local Config = require 'config'
local Bridge = require 'bridge'

if not Bridge.uses('esx') then return end

local CORE = 'es_extended'
local NOTIFY_KINDS = { inform = 'info', success = 'success', error = 'error', warning = 'error' }
local loaded, dead = nil, false

local function asked()
    local ok, object = pcall(function() return exports[CORE]:getSharedObject() end)

    if not ok or type(object) ~= 'table' then return false end

    local check = object.IsPlayerLoaded

    if check then
        local done, answer = pcall(check)

        if done then
            return answer ~= nil and answer ~= false and answer ~= 0
        end
    end

    return type(object.PlayerData) == 'table' and object.PlayerData.identifier ~= nil
end

function Bridge.isPlayerReady()
    if loaded == nil then
        loaded = asked()
    end

    return loaded == true
end

RegisterNetEvent('esx:playerLoaded', function()
    loaded, dead = true, false
end)

RegisterNetEvent('esx:onPlayerLogout', function()
    loaded, dead = false, false
end)

AddEventHandler('esx:onPlayerDeath', function()
    dead = true
end)

AddEventHandler('esx:onPlayerSpawn', function()
    dead = false
end)

function Bridge.onReady(callback)
    RegisterNetEvent('esx:playerLoaded', function()
        callback()
    end)
end

function Bridge.onLogout(callback)
    RegisterNetEvent('esx:onPlayerLogout', function()
        callback()
    end)
end

function Bridge.isDown()
    return dead or LocalPlayer.state.isDead == true
end

function Bridge.isRestrained()
    local cuffed = IsPedCuffed(cache.ped)

    return (cuffed ~= nil and cuffed ~= false and cuffed ~= 0) or LocalPlayer.state.handcuffed == true
end

function Bridge.notify(text, kind)
    if Config.notifyWith == 'framework' then
        TriggerEvent('esx:showNotification', text, NOTIFY_KINDS[kind] or 'info')

        return
    end

    lib.notify({ title = locale('brand'), description = text, type = kind or 'inform' })
end
