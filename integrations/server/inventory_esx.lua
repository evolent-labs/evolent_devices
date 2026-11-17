local Config = require 'config'
local Integrations = require 'integrations'
local Bridge = require 'bridge'
local Util = require 'shared.util'

local adapter = { name = 'esx', resource = 'es_extended', metadata = false }
local held, cached = {}, nil

Integrations.inventories.esx = adapter

local function core()
    if cached == nil and Bridge.uses('esx') then
        local items = Bridge.items()

        cached = items and items.inventory and items or nil
    end

    return cached
end

function adapter.ready()
    return GetResourceState(adapter.resource) == 'started' and core() ~= nil
end

local function names()
    local list = {}

    for _, kind in ipairs(Config.kindOrder) do
        local entry = Config.items[kind]

        if entry and type(entry.item) == 'string' then
            list[#list + 1] = entry.item
        end
    end

    return list
end

local function slotOf(name)
    for index, entry in ipairs(names()) do
        if entry == name then
            return index
        end
    end

    return nil
end

local function count(source, name)
    local items = core()

    return items and items.inventory.count(source, name) or 0
end

local function stack(source, name)
    local cid = Bridge.getCharacterId(source)

    if not cid then return nil end

    held[cid] = held[cid] or {}
    held[cid][name] = held[cid][name] or {}

    local list = held[cid][name]
    local have = count(source, name)

    while #list > have do
        table.remove(list)
    end

    return list
end

function adapter.itemDefined(name)
    local items = core()

    return items ~= nil and items.defined(name) == true
end

function adapter.addItem(source, name, metadata)
    local items = core()

    if not items or not items.inventory.add(source, name) then return false end

    local list = stack(source, name)

    if list and type(metadata) == 'table' and metadata.serial then
        list[#list + 1] = Util.copy(metadata)
    end

    return true
end

function adapter.getSlot(source, slot)
    local name = names()[tonumber(slot) or 0]
    local have = name and count(source, name) or 0

    if have < 1 then return nil end

    local list = stack(source, name) or {}

    return { name = name, slot = slot, count = have, metadata = Util.copy(list[1] or {}) }
end

function adapter.setMetadata(source, slot, metadata)
    local name = names()[tonumber(slot) or 0]
    local list = name and stack(source, name)

    if not list or count(source, name) < 1 then return false end

    list[1] = Util.copy(metadata)

    return true
end

function adapter.removeItem(source, name, _, serial)
    local items = core()
    local list = stack(source, name)

    if not items or not list or not items.inventory.remove(source, name) then return false end

    for index, entry in ipairs(list) do
        if serial == nil or entry.serial == serial then
            table.remove(list, index)

            break
        end
    end

    return true
end

function adapter.findItem(source, name, serial)
    for _, entry in ipairs(stack(source, name) or {}) do
        if entry.serial == serial then
            return { name = name, slot = slotOf(name), count = 1, metadata = Util.copy(entry) }
        end
    end

    return nil
end

function adapter.hasItem(source, name)
    return count(source, name) > 0
end

function adapter.canCarry(source, name)
    local items = core()

    return items ~= nil and items.inventory.canCarry(source, name) == true
end

function adapter.onItemUsed(list, handler)
    local items = core()

    if not items then return false end

    local done = true

    for _, name in ipairs(list) do
        done = items.usable(name, function(source)
            handler(source, name, slotOf(name))
        end) and done
    end

    return done
end

function adapter.forget(cid)
    if cid == nil then
        held = {}
    else
        held[cid] = nil
    end
end
