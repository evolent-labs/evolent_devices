local Config = require 'config'
local Integrations = require 'integrations'

local Bridge = {}

Bridge.FRAMEWORKS = {
    { id = 'qbox', resource = 'qbx_core', label = 'Qbox' },
    { id = 'qbcore', resource = 'qb-core', label = 'QBCore' },
    { id = 'esx', resource = 'es_extended', label = 'ESX' },
}

local chosen = nil

local function running(resource)
    local state = GetResourceState(resource)

    return state == 'started' or state == 'starting'
end

local function detect()
    local wanted = Config.framework or 'auto'

    for _, entry in ipairs(Bridge.FRAMEWORKS) do
        if entry.id == wanted then
            return entry
        end
    end

    if wanted ~= 'auto' or type(GetResourceState) ~= 'function' then return nil end

    for _, entry in ipairs(Bridge.FRAMEWORKS) do
        if running(entry.resource) then
            return entry
        end
    end

    return nil
end

function Bridge.active()
    if chosen == nil then
        chosen = detect() or false
        Bridge.framework = chosen and chosen.id or nil
    end

    return chosen or nil
end

function Bridge.uses(id)
    local entry = Bridge.active()

    return entry ~= nil and entry.id == id
end

function Bridge.missingText()
    local wanted = Config.framework or 'auto'

    if wanted ~= 'auto' then
        local known = false

        for _, entry in ipairs(Bridge.FRAMEWORKS) do
            known = known or entry.id == wanted
        end

        if not known then
            return ("Config.framework is '%s'. Use 'auto', 'qbox', 'qbcore' or 'esx'."):format(tostring(wanted))
        end
    end

    return 'No framework is running. Start qbx_core, qb-core or es_extended before evolent_devices, or set Config.framework.'
end

Bridge.contract = {
    server = {
        'assertReady',
        'info',
        'getCharacterId',
        'getCharacterName',
        'getSourceByCharacterId',
        'subject',
        'lookupCitizen',
        'groups',
        'isAdmin',
        'canManage',
        'isPlayerReady',
        'onlinePlayers',
        'notify',
        'onCharacterLoaded',
        'onCharacterUnloaded',
        'onGroupsChanged',
        'onPropertyChanged',
        'items',
    },
    client = { 'isPlayerReady', 'onReady', 'onLogout', 'isDown', 'isRestrained', 'notify' },
}

function Bridge.validate(side)
    assert(Bridge.active(), Bridge.missingText())

    for _, name in ipairs(Bridge.contract[side]) do
        assert(type(Bridge[name]) == 'function', ('Bridge.%s is missing from the %s bridge of %s'):format(name, side, Bridge.framework))
    end

    for _, name in ipairs(Integrations.contract[side]) do
        assert(
            type(Integrations[name]) == 'function',
            ('Integrations.%s is missing from the %s integrations'):format(name, side)
        )
    end
end

return Bridge
