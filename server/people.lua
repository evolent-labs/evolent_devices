local Bridge = require 'bridge'
local Util = require 'shared.util'

local People = { subjects = {}, levels = {}, sources = {}, cids = {} }

local KEEP_MS = 1000

local function note(source, subject)
    local cid = subject and subject.cid or nil
    local was = People.cids[source]

    if was == cid then return end

    if was and People.sources[was] == source then
        People.sources[was] = nil
    end

    People.cids[source] = cid

    if cid then
        People.sources[cid] = source
    end
end

function People.fresh(source)
    local subject = Bridge.subject(source)

    People.subjects[source] = { at = GetGameTimer(), subject = subject }
    People.levels[source] = nil
    note(source, subject)

    return subject
end

function People.subject(source)
    local entry = People.subjects[source]

    if entry and GetGameTimer() - entry.at < KEEP_MS then
        return entry.subject
    end

    return People.fresh(source)
end

function People.forget(source)
    if source == nil then
        People.subjects, People.levels = {}, {}
    else
        People.subjects[source] = nil
        People.levels[source] = nil
    end
end

function People.gone(source)
    note(source, nil)
    People.forget(source)
end

function People.sourceOf(cid)
    local source = cid ~= nil and People.sources[cid] or nil
    local subject = source and People.subject(source) or nil

    if not subject or subject.cid ~= cid then return nil end

    return source, subject
end

local function standing(source)
    local entry = People.levels[source]
    local now = GetGameTimer()

    if not entry or now - entry.at >= KEEP_MS then
        entry = { at = now }
        People.levels[source] = entry
    end

    return entry
end

function People.admin(source)
    local entry = standing(source)

    if entry.admin == nil then
        entry.admin = Bridge.isAdmin(source) == true
    end

    return entry.admin
end

function People.level(source)
    local entry = standing(source)

    if entry.level == nil then
        entry.level = People.admin(source) and 'admin' or Bridge.canManage(source) and 'manage' or false
    end

    return entry.level or nil
end

function People.coords(source)
    local ped = GetPlayerPed(source)

    if not ped or ped == 0 then return nil end

    return GetEntityCoords(ped)
end

local function connected()
    local list = {}

    for _, id in ipairs(GetPlayers()) do
        local source = tonumber(id)

        if source then
            list[#list + 1] = source
        end
    end

    table.sort(list)

    return list
end

function People.online()
    local list = {}

    for _, source in ipairs(connected()) do
        if People.subject(source) then
            list[#list + 1] = source
        end
    end

    return list
end

function People.near(point, range, except)
    local list = {}

    for _, source in ipairs(connected()) do
        if source ~= except then
            local at = People.coords(source)

            if at and Util.distance(at, point) <= range and People.subject(source) then
                list[#list + 1] = source
            end
        end
    end

    return list
end

return People
