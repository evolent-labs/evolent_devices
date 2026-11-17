local Bridge = require 'bridge'

if not Bridge.uses('qbox') then return end

local CORE = 'qbx_core'
local common = require 'bridge.server.common'

function Bridge.assertReady()
    assert(GetResourceState(CORE) == 'started', 'Start qbx_core before evolent_devices.')
end

function Bridge.info()
    return { id = 'qbox', label = 'Qbox', gangs = true, multiJob = true, duty = true }
end

local function getPlayer(source)
    if not common.validSource(source) then return nil end

    return exports.qbx_core:GetPlayer(source)
end

local function fullName(data)
    return data and common.fullName(data.charinfo) or nil
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
    if type(characterId) ~= 'string' then return nil end

    local player = exports.qbx_core:GetPlayerByCitizenId(characterId)

    return player and player.PlayerData.source or nil
end

function Bridge.subject(source)
    local player = getPlayer(source)

    if not player then return nil end

    local data = player.PlayerData
    local job, gang, metadata = data.job or {}, data.gang or {}, data.metadata or {}

    return {
        source = source,
        cid = data.citizenid,
        name = fullName(data) or data.citizenid,
        job = {
            name = job.name,
            grade = type(job.grade) == 'table' and tonumber(job.grade.level) or 0,
            onduty = job.onduty == true,
        },
        jobs = type(data.jobs) == 'table' and data.jobs or {},
        gang = { name = gang.name, grade = type(gang.grade) == 'table' and tonumber(gang.grade.level) or 0 },
        gangs = type(data.gangs) == 'table' and data.gangs or {},
        propertyId = tonumber(metadata.currentPropertyId),
        dead = metadata.isdead == true or metadata.inlaststand == true,
    }
end

function Bridge.lookupCitizen(characterId)
    if type(characterId) ~= 'string' then return nil end

    local function onlineEntry(cid)
        local online = exports.qbx_core:GetPlayerByCitizenId(cid)

        if not online then return nil end

        local data = online.PlayerData

        return { cid = data.citizenid or cid, name = fullName(data) or cid, online = true, source = data.source }
    end

    local found = onlineEntry(characterId)

    if found then
        return found
    end

    local ok, offline = pcall(function() return exports.qbx_core:GetOfflinePlayer(characterId) end)

    if not ok or type(offline) ~= 'table' or not offline.PlayerData then return nil end

    local cid = type(offline.PlayerData.citizenid) == 'string' and offline.PlayerData.citizenid or characterId

    if cid ~= characterId then
        found = onlineEntry(cid)

        if found then
            return found
        end
    end

    return { cid = cid, name = fullName(offline.PlayerData) or cid, online = false }
end

local groups, forgetGroups = common.groupCache(function(kind)
    if kind == 'jobs' then
        return exports.qbx_core:GetJobs()
    end

    return exports.qbx_core:GetGangs()
end)

Bridge.groups = groups

function Bridge.isAdmin(source)
    return common.isAdmin(source)
end

function Bridge.canManage(source)
    return common.canManage(source)
end

function Bridge.isPlayerReady(source, subject)
    if subject == nil then
        subject = Bridge.subject(source)
    end

    return subject ~= nil and not subject.dead
end

function Bridge.onlinePlayers()
    local list = {}
    local ok, players = pcall(function() return exports.qbx_core:GetQBPlayers() end)

    if ok and type(players) == 'table' then
        for source in pairs(players) do
            if type(source) == 'number' then
                list[#list + 1] = source
            end
        end
    end

    table.sort(list)

    return list
end

function Bridge.notify(source, text, kind)
    common.notifyOx(source, text, kind)
end

function Bridge.onCharacterLoaded(callback)
    AddEventHandler('QBCore:Server:PlayerLoaded', function(player)
        if type(player) == 'table' and player.PlayerData and common.trusted(player.PlayerData.source) then
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
    for _, name in ipairs({ 'QBCore:Server:OnJobUpdate', 'QBCore:Server:OnGangUpdate', 'qbx_core:server:onGroupUpdate', 'QBCore:Server:SetDuty' }) do
        AddEventHandler(name, function(playerSource)
            if type(playerSource) == 'number' and common.trusted(playerSource) then
                callback(playerSource)
            end
        end)
    end

    for _, name in ipairs({ 'qbx_core:server:onJobUpdate', 'qbx_core:server:onGangUpdate' }) do
        AddEventHandler(name, function()
            if common.trusted() then
                forgetGroups()
            end
        end)
    end
end

function Bridge.onPropertyChanged(callback)
    AddEventHandler('qbx_core:server:onSetMetaData', function(key, _, value, playerSource)
        if key == 'currentPropertyId' and type(playerSource) == 'number' and common.trusted(playerSource) then
            callback(playerSource, tonumber(value))
        end
    end)
end

function Bridge.items()
    return nil
end
