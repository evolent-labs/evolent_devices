local Integrations = require 'integrations'
local Bridge = require 'bridge'

local INVENTORY = 'qb-inventory'
local REASON = 'evolent_devices'
local adapter = { name = INVENTORY, resource = INVENTORY, metadata = true }

Integrations.inventories[INVENTORY] = adapter

function adapter.ready()
    return Bridge.uses('qbcore') and GetResourceState(INVENTORY) == 'started'
end

local function shape(item, slot)
    if type(item) ~= 'table' or type(item.name) ~= 'string' then return nil end

    return {
        name = item.name,
        slot = tonumber(item.slot) or slot,
        count = tonumber(item.amount) or tonumber(item.count) or 1,
        metadata = type(item.info) == 'table' and item.info or {},
    }
end

function adapter.itemDefined(name)
    local items = Bridge.items()

    return items ~= nil and items.defined(name) == true
end

function adapter.addItem(source, name, metadata)
    local ok, success = pcall(function()
        return exports[INVENTORY]:AddItem(source, name, 1, false, metadata or {}, REASON)
    end)

    return ok and success == true
end

function adapter.getSlot(source, slot)
    local ok, item = pcall(function() return exports[INVENTORY]:GetItemBySlot(source, slot) end)

    return ok and shape(item, slot) or nil
end

function adapter.removeItem(source, name, slot, serial)
    local item = adapter.getSlot(source, slot)

    if not item or item.name ~= name then return false end
    if type(serial) == 'string' and item.metadata.serial ~= serial then return false end

    local ok, success = pcall(function() return exports[INVENTORY]:RemoveItem(source, name, 1, slot, REASON) end)

    return ok and success == true
end

function adapter.setMetadata(source, slot, metadata)
    local item = adapter.getSlot(source, slot)

    if not item then return false end

    local ok, success = pcall(function()
        return exports[INVENTORY]:SetItemData(source, item.name, 'info', metadata, slot)
    end)

    return ok and success ~= false
end

function adapter.findItem(source, name, serial)
    local ok, list = pcall(function() return exports[INVENTORY]:GetItemsByName(source, name) end)

    if not ok or type(list) ~= 'table' then return nil end

    for _, entry in pairs(list) do
        local item = shape(entry)

        if item and item.name == name and item.metadata.serial == serial then
            return item
        end
    end

    return nil
end

function adapter.hasItem(source, name)
    local ok, has = pcall(function() return exports[INVENTORY]:HasItem(source, name, 1) end)

    return ok and has == true
end

function adapter.canCarry(source, name)
    local ok, can = pcall(function() return exports[INVENTORY]:CanAddItem(source, name, 1) end)

    return ok and can == true
end

function adapter.onItemUsed(names, handler)
    local items = Bridge.items()

    if not items then return false end

    local done = true

    for _, name in ipairs(names) do
        done = items.usable(name, function(source, item)
            handler(source, name, type(item) == 'table' and tonumber(item.slot) or nil)
        end) and done
    end

    return done
end
