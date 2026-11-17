local Bridge = require 'bridge'

if not Bridge.uses('esx') then return end

local CORE = 'es_extended'
local NOTIFY_KINDS = { inform = 'info', success = 'success', error = 'error', warning = 'error' }
local common = require 'bridge.server.common'
local core = nil

local function esx(fresh)
    if fresh then
        core = nil
    end

    if not core then
        local ok, object = pcall(function() return exports[CORE]:getSharedObject() end)

        core = ok and type(object) == 'table' and object or nil
    end

    return core
end

local function call(name, ...)
    local object = esx()
    local fn = object and object[name]

    if not common.callable(fn) then return nil end

    local ok, result = pcall(fn, ...)

    return ok and result or nil
end

local function method(player, name, ...)
    local fn = type(player) == 'table' and player[name] or nil

    if not common.callable(fn) then return nil end

    local ok, result = pcall(fn, ...)

    return ok and result or nil
end

function Bridge.assertReady()
    assert(GetResourceState(CORE) == 'started', 'Start es_extended before evolent_devices.')
    assert(esx(), 'es_extended did not hand out its shared object.')
end

function Bridge.info()
    return { id = 'esx', label = 'ESX', gangs = false, multiJob = false, duty = true }
end

local function getPlayer(source)
    if not common.validSource(source) then return nil end

    local player = call('GetPlayerFromId', source)

    return type(player) == 'table' and type(player.identifier) == 'string' and player or nil
end

local function byIdentifier(identifier)
    if type(identifier) ~= 'string' then return nil end

    local player = call('GetPlayerFromIdentifier', identifier)

    return type(player) == 'table' and type(player.identifier) == 'string' and player or nil
end

local function nameOf(player)
    local named = common.trim(player.name)

    if named then
        return named
    end

    local variables = type(player.variables) == 'table' and player.variables or {}

    return common.fullName({ firstname = variables.firstName, lastname = variables.lastName }) or common.trim(method(player, 'getName'))
end

local function jobOf(player)
    local job = type(player.job) == 'table' and player.job or method(player, 'getJob')

    return type(job) == 'table' and job or {}
end

local function sourceOf(player)
    return tonumber(player.source) or tonumber(player.playerId)
end

function Bridge.getCharacterId(source)
    local player = getPlayer(source)

    return player and player.identifier or nil
end

function Bridge.getCharacterName(source)
    local player = getPlayer(source)

    return player and nameOf(player) or nil
end

function Bridge.getSourceByCharacterId(characterId)
    local player = byIdentifier(characterId)

    return player and sourceOf(player) or nil
end

function Bridge.subject(source)
    local player = getPlayer(source)

    if not player then return nil end

    local job = jobOf(player)
    local grade = tonumber(job.grade) or 0
    local state = Player(source).state

    return {
        source = source,
        cid = player.identifier,
        name = nameOf(player) or player.identifier,
        job = { name = job.name, grade = grade, onduty = job.onDuty ~= false },
        jobs = job.name and { [job.name] = grade } or {},
        gang = {},
        gangs = {},
        propertyId = nil,
        dead = state.isDead == true,
    }
end

function Bridge.lookupCitizen(characterId)
    if type(characterId) ~= 'string' then return nil end

    local function onlineEntry(identifier)
        local online = byIdentifier(identifier)

        if not online then return nil end

        return { cid = online.identifier, name = nameOf(online) or online.identifier, online = true, source = sourceOf(online) }
    end

    local found = onlineEntry(characterId)

    if found then
        return found
    end

    local ok, row = pcall(function()
        return MySQL.single.await('SELECT identifier, firstname, lastname FROM users WHERE identifier = ? LIMIT 1', { characterId })
    end)

    if not ok or type(row) ~= 'table' then return nil end

    local cid = type(row.identifier) == 'string' and row.identifier or characterId

    if cid ~= characterId then
        found = onlineEntry(cid)

        if found then
            return found
        end
    end

    return { cid = cid, name = common.fullName(row) or cid, online = false }
end

local groups, forgetGroups = common.groupCache(function(kind, fresh)
    if kind ~= 'jobs' then return {} end

    if fresh then
        esx(true)
    end

    local jobs = call('GetJobs')

    if type(jobs) ~= 'table' then
        local object = esx()

        jobs = object and object.Jobs
    end

    return jobs
end)

Bridge.groups = groups

local function groupCheck()
    local known, current = false, nil

    return function(source, group)
        if not known then
            local player = getPlayer(source)

            known = true
            current = player and player.group or nil

            if player and type(current) ~= 'string' then
                current = method(player, 'getGroup')
            end
        end

        return current ~= nil and current == group
    end
end

function Bridge.isAdmin(source)
    return common.isAdmin(source, groupCheck())
end

function Bridge.canManage(source)
    return common.canManage(source, groupCheck())
end

function Bridge.isPlayerReady(source, subject)
    if subject == nil then
        subject = Bridge.subject(source)
    end

    return subject ~= nil and not subject.dead
end

function Bridge.onlinePlayers()
    local list = {}
    local players = call('GetExtendedPlayers')

    for _, player in pairs(type(players) == 'table' and players or {}) do
        local number = type(player) == 'table' and sourceOf(player) or tonumber(player)

        if number then
            list[#list + 1] = number
        end
    end

    table.sort(list)

    return list
end

function Bridge.notify(source, text, kind)
    if common.framework() then
        TriggerClientEvent('esx:showNotification', source, text, NOTIFY_KINDS[kind] or 'info')

        return
    end

    common.notifyOx(source, text, kind)
end

function Bridge.onCharacterLoaded(callback)
    AddEventHandler('esx:playerLoaded', function(playerSource)
        local number = tonumber(playerSource)

        if number and common.trusted(number) then
            callback(number)
        end
    end)
end

function Bridge.onCharacterUnloaded(callback)
    AddEventHandler('esx:playerLogout', function(playerSource)
        local number = tonumber(playerSource)

        if number and common.trusted(number) then
            callback(number)
        end
    end)
end

function Bridge.onGroupsChanged(callback)
    AddEventHandler('esx:setJob', function(playerSource)
        local number = tonumber(playerSource)

        if number and common.trusted(number) then
            callback(number)
        end
    end)
end

function Bridge.onPropertyChanged()
end

AddEventHandler('onResourceStart', function(resource)
    if resource == CORE then
        core = nil
        forgetGroups()
    end
end)

function Bridge.items()
    if not esx() then return nil end

    local function count(source, name)
        local player = getPlayer(source)
        local item = player and method(player, 'getInventoryItem', name)

        return type(item) == 'table' and math.max(0, math.floor(tonumber(item.count) or 0)) or 0
    end

    return {
        defined = function(name)
            local object = esx(true)
            local list = object and object.Items

            return type(name) == 'string' and type(list) == 'table' and list[name] ~= nil
        end,
        usable = function(name, handler)
            local object = esx()

            if not object or not common.callable(object.RegisterUsableItem) then return false end

            local ok = pcall(object.RegisterUsableItem, name, function(source)
                handler(tonumber(source), nil)
            end)

            return ok
        end,
        inventory = {
            count = count,
            add = function(source, name)
                local player = getPlayer(source)

                if not player then return false end

                local before = count(source, name)

                method(player, 'addInventoryItem', name, 1)

                return count(source, name) > before
            end,
            remove = function(source, name)
                local player = getPlayer(source)
                local before = count(source, name)

                if not player or before < 1 then return false end

                method(player, 'removeInventoryItem', name, 1)

                return count(source, name) < before
            end,
            canCarry = function(source, name)
                local player = getPlayer(source)

                return player ~= nil and method(player, 'canCarryItem', name, 1) == true
            end,
        },
    }
end
