local Integrations = require 'integrations'

local INVENTORY = 'ox_inventory'
local adapter = { name = INVENTORY, resource = INVENTORY, metadata = true }

Integrations.inventories[INVENTORY] = adapter

function adapter.ready()
    return GetResourceState(INVENTORY) == 'started'
end

function adapter.itemDefined(name)
    local ok, item = pcall(function() return exports.ox_inventory:Items(name) end)

    return ok and item ~= nil
end

function adapter.addItem(source, name, metadata)
    local ok, success = pcall(function() return exports.ox_inventory:AddItem(source, name, 1, metadata) end)

    return ok and success == true
end

function adapter.removeItem(source, name, slot, serial)
    local metadata = type(serial) == 'string' and { serial = serial } or nil

    local ok, success = pcall(function()
        return exports.ox_inventory:RemoveItem(source, name, 1, metadata, slot, false, false)
    end)

    return ok and success == true
end

function adapter.setMetadata(source, slot, metadata)
    local ok = pcall(function() exports.ox_inventory:SetMetadata(source, slot, metadata) end)

    return ok
end

function adapter.findItem(source, name, serial)
    local ok, item = pcall(function()
        return exports.ox_inventory:GetSlotWithItem(source, name, { serial = serial }, false)
    end)

    return ok and type(item) == 'table' and item or nil
end

function adapter.getSlot(source, slot)
    local ok, item = pcall(function() return exports.ox_inventory:GetSlot(source, slot) end)

    return ok and type(item) == 'table' and item or nil
end

function adapter.hasItem(source, name)
    local ok, count = pcall(function() return exports.ox_inventory:GetItemCount(source, name) end)

    return ok and (tonumber(count) or 0) > 0
end

function adapter.canCarry(source, name)
    local ok, result = pcall(function() return exports.ox_inventory:CanCarryItem(source, name, 1) end)

    return ok and result == true
end

function adapter.onItemCreated(names, handler)
    local filter = {}

    for _, name in ipairs(names) do
        filter[name] = true
    end

    local ok, id = pcall(function()
        return exports.ox_inventory:registerHook('createItem', function(payload)
            if type(payload) ~= 'table' then return end

            local item = payload.item
            local result = handler(type(item) == 'table' and item.name or nil, payload.metadata)

            if type(result) == 'table' then
                return result
            end
        end, { itemFilter = filter })
    end)

    return ok and id ~= nil
end
