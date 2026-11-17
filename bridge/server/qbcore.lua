local Bridge = require 'bridge'

if not Bridge.uses('qbcore') then return end

local CORE = 'qb-core'
local NOTIFY_KINDS = { inform = 'primary', success = 'success', error = 'error', warning = 'error' }
local common = require 'bridge.server.common'
local core = nil

local function qb(fresh)
    if fresh then
        core = nil
    end

    if not core then
        local ok, object = pcall(function() return exports[CORE]:GetCoreObject() end)

        core = ok and type(object) == 'table' and object or nil
    end

    return core
end

local function functions()
    local object = qb()

    return object and type(object.Functions) == 'table' and object.Functions or nil
end

local function shared(key)
    local object = qb()
    local data = object and object.Shared

    return type(data) == 'table' and data[key] or nil
end

function Bridge.assertReady()
    assert(GetResourceState(CORE) == 'started', 'Start qb-core before evolent_devices.')
    assert(qb(), 'qb-core did not hand out its core object.')
end

function Bridge.info()
    return { id = 'qbcore', label = 'QBCore', gangs = true, multiJob = false, duty = true }
end

local function getPlayer(source)
    if not common.validSource(source) then return nil end

    local calls = functions()

    if not calls then return nil end

    local ok, player = pcall(calls.GetPlayer, source)

    return ok and type(player) == 'table' and type(player.PlayerData) == 'table' and player or nil
end

local function byCitizenId(cid)
    local calls = functions()

    if not calls or type(cid) ~= 'string' then return nil end

    local ok, player = pcall(calls.GetPlayerByCitizenId, cid)

    return ok and type(player) == 'table' and type(player.PlayerData) == 'table' and player or nil
end

local function fullName(data)
    return data and common.fullName(common.decode(data.charinfo)) or nil
end

local function level(grade)
    return type(grade) == 'table' and tonumber(grade.level) or tonumber(grade) or 0
end

function Bridge.getCharacterId(source)
    local player = getPlayer(source)

    return player and player.PlayerData.citizenid or nil
end

function Bridge.getCharacterName(source)
    local player = getPlayer(source)

    return player and fullName(player.PlayerData) or nil
end

function Bridge.getSourceByCharacterId(characterId)
    local player = byCitizenId(characterId)

    return player and player.PlayerData.source or nil
end

function Bridge.subject(source)
    local player = getPlayer(source)

    if not player then return nil end

    local data = player.PlayerData
    local job, gang, metadata = data.job or {}, data.gang or {}, data.metadata or {}
    local jobGrade, gangGrade = level(job.grade), level(gang.grade)

    return {
        source = source,
        cid = data.citizenid,
        name = fullName(data) or data.citizenid,
        job = { name = job.name, grade = jobGrade, onduty = job.onduty == true },
        jobs = job.name and { [job.name] = jobGrade } or {},
        gang = { name = gang.name, grade = gangGrade },
        gangs = gang.name and { [gang.name] = gangGrade } or {},
        propertyId = nil,
        dead = metadata.isdead == true or metadata.inlaststand == true,
    }
end

function Bridge.lookupCitizen(characterId)
    if type(characterId) ~= 'string' then return nil end

    local function onlineEntry(cid)
        local online = byCitizenId(cid)

        if not online then return nil end

        local data = online.PlayerData

        return { cid = data.citizenid or cid, name = fullName(data) or cid, online = true, source = data.source }
    end

    local found = onlineEntry(characterId)

    if found then
        return found
    end

    local ok, row = pcall(function()
        return MySQL.single.await('SELECT citizenid, charinfo FROM players WHERE citizenid = ? LIMIT 1', { characterId })
    end)

    if not ok or type(row) ~= 'table' then return nil end

    local cid = type(row.citizenid) == 'string' and row.citizenid or characterId

    if cid ~= characterId then
        found = onlineEntry(cid)

        if found then
            return found
        end
    end

    return { cid = cid, name = fullName(row) or cid, online = false }
end

local groups, forgetGroups = common.groupCache(function(kind, fresh)
    if fresh then
        qb(true)
    end

    return shared(kind == 'jobs' and 'Jobs' or 'Gangs')
end)

Bridge.groups = groups

local function hasPermission(source, group)
    local calls = functions()

    if not calls or not common.callable(calls.HasPermission) then return false end

    local ok, answer = pcall(calls.HasPermission, source, group)

    return ok and answer ~= nil and answer ~= false and answer ~= 0
end

function Bridge.isAdmin(source)
    return common.isAdmin(source, hasPermission)
end

function Bridge.canManage(source)
    return common.canManage(source, hasPermission)
end

function Bridge.isPlayerReady(source, subject)
    if subject == nil then
        subject = Bridge.subject(source)
    end

    return subject ~= nil and not subject.dead
end

function Bridge.onlinePlayers()
    local list = {}
    local calls = functions()
    local ok, players = false, nil

    if calls then
        ok, players = pcall(calls.GetPlayers)
    end

    if ok and type(players) == 'table' then
        for _, source in pairs(players) do
            local number = tonumber(source)

            if number then
                list[#list + 1] = number
            end
        end
    end

    table.sort(list)

    return list
end

function Bridge.notify(source, text, kind)
    if common.framework() then
        TriggerClientEvent('QBCore:Notify', source, text, NOTIFY_KINDS[kind] or 'primary')

        return
    end

    common.notifyOx(source, text, kind)
end

function Bridge.onCharacterLoaded(callback)
    AddEventHandler('QBCore:Server:PlayerLoaded', function(player)
        if type(player) == 'table' and type(player.PlayerData) == 'table' and common.trusted(player.PlayerData.source) then
            callback(player.PlayerData.source)
        end
    end)
end

function Bridge.onCharacterUnloaded(callback)
    AddEventHandler('QBCore:Server:OnPlayerUnload', function(playerSource)
        if common.trusted(playerSource) then
            callback(playerSource)
        end
    end)
end

function Bridge.onGroupsChanged(callback)
    for _, name in ipairs({ 'QBCore:Server:OnJobUpdate', 'QBCore:Server:OnGangUpdate', 'QBCore:Server:SetDuty' }) do
        AddEventHandler(name, function(playerSource)
            if type(playerSource) == 'number' and common.trusted(playerSource) then
                callback(playerSource)
            end
        end)
    end

    AddEventHandler('QBCore:Server:UpdateObject', function()
        if not common.trusted() then return end

        core = nil
        forgetGroups()
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
    local calls = functions()

    if not calls then return nil end

    return {
        defined = function(name)
            local list = shared('Items')

            if type(list) ~= 'table' or not list[name] then
                list = qb(true) and shared('Items')
            end

            return type(list) == 'table' and list[name] ~= nil
        end,
        usable = function(name, handler)
            local ok = pcall(calls.CreateUseableItem, name, function(source, item)
                handler(tonumber(source), item)
            end)

            return ok
        end,
    }
end
