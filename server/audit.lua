local Util = require 'shared.util'
local Store = require 'server.store'
local Guard = require 'server.guard'

local Audit = {}

Audit.ACTIONS = {
    'place',
    'move',
    'remove',
    'restore',
    'pickup',
    'return',
    'rename',
    'access',
    'manage',
    'apps',
    'page',
    'owner',
    'enable',
    'model',
    'space',
    'kick',
    'admin_open',
    'give',
    'settings',
    'zones',
    'app_status',
    'app_options',
    'signal',
    'screen',
    'password',
    'only_app',
    'brand',
}

local known = {}

for _, action in ipairs(Audit.ACTIONS) do
    known[action] = true
end

local MAX_DETAIL = 4096
local LISTED = 12

function Audit.write(actor, action, deviceId, detail)
    if not known[action] then return false end

    if detail ~= nil and (type(detail) ~= 'table' or #json.encode(detail) > MAX_DETAIL) then
        detail = { truncated = true }
    end

    local ok, id = pcall(Store.insertAudit, {
        actorCid = actor and actor.cid or nil,
        actorName = actor and actor.name and actor.name:sub(1, 64) or nil,
        action = action,
        deviceId = deviceId,
        detail = detail,
    })

    if not ok then
        print(('[evolent_devices] could not write the activity row %s for device %s: %s'):format(
            action,
            tostring(deviceId),
            tostring(id)
        ))

        return false
    end

    return id ~= nil
end

function Audit.listChanges(before, after, text)
    local old, new = {}, {}

    for _, entry in ipairs(before or {}) do
        old[entry.id] = entry
    end

    for _, entry in ipairs(after) do
        new[entry.id] = entry
    end

    local detail = { count = #after, added = {}, removed = {}, changed = {} }

    for _, entry in ipairs(after) do
        local was = old[entry.id]

        if not was then
            detail.added[#detail.added + 1] = text(entry)
        elseif not Util.same(was, entry) then
            detail.changed[#detail.changed + 1] = text(entry)
        end
    end

    for _, entry in ipairs(before or {}) do
        if not new[entry.id] then
            detail.removed[#detail.removed + 1] = text(entry)
        end
    end

    for _, key in ipairs({ 'added', 'removed', 'changed' }) do
        local list = detail[key]

        if #list > LISTED then
            detail[key .. 'More'] = #list - LISTED

            for index = #list, LISTED + 1, -1 do
                list[index] = nil
            end
        end
    end

    return detail
end

function Audit.list(filter)
    filter = type(filter) == 'table' and filter or {}

    local clean = { limit = Util.integer(tonumber(filter.limit), 1, 200) or 100 }

    if filter.action ~= nil then
        if not known[filter.action] then
            return nil, 'invalid_filter'
        end

        clean.action = filter.action
    end

    if filter.actions ~= nil then
        if type(filter.actions) ~= 'table' or #filter.actions < 1 or #filter.actions > #Audit.ACTIONS then
            return nil, 'invalid_filter'
        end

        clean.actions = {}

        for index, action in ipairs(filter.actions) do
            if not known[action] then
                return nil, 'invalid_filter'
            end

            clean.actions[index] = action
        end
    end

    if filter.deviceId ~= nil then
        clean.deviceId = Guard.idArg(filter.deviceId)

        if not clean.deviceId then
            return nil, 'invalid_filter'
        end
    end

    if filter.actor ~= nil then
        local actor = Util.cleanText(filter.actor, 64)

        if not actor then
            return nil, 'invalid_filter'
        end

        if actor ~= '' then
            clean.actor = actor
        end
    end

    if filter.before ~= nil then
        clean.before = Guard.idArg(filter.before)

        if not clean.before then
            return nil, 'invalid_filter'
        end
    end

    local rows = Store.listAudit({
        action = clean.action,
        actions = clean.actions,
        deviceId = clean.deviceId,
        actor = clean.actor,
        before = clean.before,
        limit = clean.limit + 1,
    })

    local more = #rows > clean.limit

    if more then
        rows[#rows] = nil
    end

    return { rows = rows, more = more, actions = Audit.ACTIONS }
end

return Audit
