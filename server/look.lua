local Util = require 'shared.util'
local AppRules = require 'shared.apps'
local LookRules = require 'shared.look'
local Registry = require 'server.registry'
local Apps = require 'server.apps'
local AppHost = require 'server.hosting'

local DeviceLook = { DELAY_MS = 250, cache = {}, waiting = {}, failed = {}, timer = false }

local function call(appId, hook, ctx)
    local ok, result = pcall(hook, ctx)

    if ok then
        return result
    end

    if not DeviceLook.failed[appId] then
        DeviceLook.failed[appId] = true
        Util.log(('app %s: its look hook failed: %s'):format(appId, tostring(result)))
    end

    return nil
end

function DeviceLook.appOf(device)
    if type(device) ~= 'table' or device.kind ~= 'terminal' then return nil end

    local appId = AppHost.pageApp(device)
    local entry = appId and Apps.registered[appId] or nil

    if not entry or not AppRules.isCallable(entry.def.look) then return nil end

    return appId, entry
end

function DeviceLook.compute(device)
    local appId, entry = DeviceLook.appOf(device)

    if not appId then return nil, nil end

    local ctx = {
        app = appId,
        kind = device.kind,
        device = { id = device.id, label = device.label ~= '' and device.label or nil, owner = device.ownerCid },
        settings = AppHost.settingsFor(device, appId),
    }

    return LookRules.clean(call(appId, entry.def.look, ctx)), entry.resource
end

local function placed(device)
    return device.state == 'placed' and device.kind == 'terminal'
end

function DeviceLook.fresh(device)
    if type(device) ~= 'table' or device.id == nil then return nil end

    if not placed(device) then
        DeviceLook.cache[device.id] = nil
        return nil
    end

    local look, resource = DeviceLook.compute(device)

    DeviceLook.cache[device.id] = { look = look or false, stamp = LookRules.stamp(look), resource = resource }

    return look
end

function DeviceLook.get(device)
    if type(device) ~= 'table' or device.id == nil then return nil end

    local known = DeviceLook.cache[device.id]

    if not known then
        return DeviceLook.fresh(device)
    end

    return known.look or nil
end

function DeviceLook.refresh(resource)
    return Registry.batch(function()
        local changed = 0

        for _, device in ipairs(Registry.list(placed)) do
            local known = DeviceLook.cache[device.id]
            local _, entry = DeviceLook.appOf(device)
            local mine = resource == nil or (entry and entry.resource == resource) or (known and known.resource == resource)

            if mine then
                local look, owner = DeviceLook.compute(device)
                local stamp = LookRules.stamp(look)

                if (known and known.stamp or '') ~= stamp then
                    Registry.publish(device)
                    changed = changed + 1
                else
                    DeviceLook.cache[device.id] = { look = look or false, stamp = stamp, resource = owner }
                end
            end
        end

        return changed
    end)
end

function DeviceLook.changed(resource)
    if not Registry.ready or type(resource) ~= 'string' then return false end

    DeviceLook.waiting[resource] = true

    if DeviceLook.timer then return true end

    DeviceLook.timer = true

    CreateThread(function()
        Wait(DeviceLook.DELAY_MS)

        local list = DeviceLook.waiting

        DeviceLook.waiting, DeviceLook.timer = {}, false

        for name in pairs(list) do
            local ok, failure = pcall(DeviceLook.refresh, name)

            if not ok then
                Util.log(('device looks of %s were not refreshed: %s'):format(name, tostring(failure)))
            end
        end
    end)

    return true
end

return DeviceLook
