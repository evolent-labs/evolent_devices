local Integrations = require 'integrations'
local Bridge = require 'bridge'

local PROPERTIES = 'qbx_properties'
local CACHE_MS = 30000
local cache = {}

function Integrations.propertiesReady()
    return Bridge.uses('qbox') and GetResourceState(PROPERTIES) == 'started'
end

local function decodeHolders(text)
    local holders = {}

    if type(text) ~= 'string' or text == '' then
        return holders
    end

    local ok, list = pcall(json.decode, text)

    if ok and type(list) == 'table' then
        for _, cid in ipairs(list) do
            if type(cid) == 'string' then
                holders[cid] = true
            end
        end
    end

    return holders
end

function Integrations.propertyKeys(propertyId, fetch)
    if type(propertyId) ~= 'number' then return nil end

    local entry = cache[propertyId]
    local now = GetGameTimer()

    if entry and now - entry.at <= CACHE_MS then
        return entry
    end

    if not fetch or not Integrations.propertiesReady() then
        return entry
    end

    local ok, row = pcall(function()
        return MySQL.single.await('SELECT owner, keyholders, property_name FROM properties WHERE id = ?', {
            propertyId,
        })
    end)

    if not ok then
        return entry
    end

    entry = {
        at = now,
        owner = row and row.owner or nil,
        keyholders = decodeHolders(row and row.keyholders),
        name = row and row.property_name or nil,
    }

    cache[propertyId] = entry

    return entry
end

function Integrations.forgetProperty(propertyId)
    if propertyId == nil then
        cache = {}
    else
        cache[propertyId] = nil
    end
end
