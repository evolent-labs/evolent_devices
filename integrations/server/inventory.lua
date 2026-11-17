local Integrations = require 'integrations'

local ORDER = { 'ox_inventory', 'qb-inventory', 'esx' }
local created, used = nil, nil

local function active()
    for _, name in ipairs(ORDER) do
        local adapter = Integrations.inventories[name]

        if adapter and adapter.ready() then
            return adapter
        end
    end

    return nil
end

function Integrations.inventoryName()
    local adapter = active()

    return adapter and adapter.name or nil
end

function Integrations.inventoryReady()
    return active() ~= nil
end

function Integrations.keepsMetadata()
    local adapter = active()

    return adapter == nil or adapter.metadata == true
end

function Integrations.itemDefined(name)
    local adapter = active()

    if not adapter or type(name) ~= 'string' then return false end

    return adapter.itemDefined(name) == true
end

function Integrations.addItem(source, name, metadata)
    local adapter = active()

    return adapter ~= nil and adapter.addItem(source, name, metadata) == true
end

function Integrations.removeItem(source, name, slot, serial)
    local adapter = active()

    return adapter ~= nil and adapter.removeItem(source, name, slot, serial) == true
end

function Integrations.setMetadata(source, slot, metadata)
    local adapter = active()

    return adapter ~= nil and adapter.setMetadata(source, slot, metadata) == true
end

function Integrations.findItem(source, name, serial)
    local adapter = active()

    if not adapter or type(serial) ~= 'string' then return nil end

    local item = adapter.findItem(source, name, serial)

    return type(item) == 'table' and item or nil
end

function Integrations.getSlot(source, slot)
    local adapter = active()
    local item = adapter and adapter.getSlot(source, slot)

    return type(item) == 'table' and item or nil
end

function Integrations.hasItem(source, name)
    local adapter = active()

    if not adapter or type(name) ~= 'string' then return false end

    return adapter.hasItem(source, name) == true
end

function Integrations.canCarry(source, name)
    local adapter = active()

    return adapter ~= nil and adapter.canCarry(source, name) == true
end

local function hook()
    local adapter = active()

    if not created or not adapter or not adapter.onItemCreated then return false end

    return adapter.onItemCreated(created.names, created.handler) == true
end

local function listen()
    local adapter = active()

    if not used or not adapter or not adapter.onItemUsed then return false end

    return adapter.onItemUsed(used.names, used.handler) == true
end

function Integrations.onItemCreated(names, handler)
    created = { names = names, handler = handler }

    return hook()
end

function Integrations.onItemUsed(names, handler)
    used = { names = names, handler = handler }

    return listen()
end

AddEventHandler('onResourceStart', function(resource)
    for _, name in ipairs(ORDER) do
        local adapter = Integrations.inventories[name]

        if adapter and adapter.resource == resource then
            hook()
            listen()

            return
        end
    end
end)
