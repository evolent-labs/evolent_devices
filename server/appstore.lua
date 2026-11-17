local Config = require 'config'
local Util = require 'shared.util'
local AppRules = require 'shared.apps'
local OsRules = require 'shared.os'
local Store = require 'server.store'
local Apps = require 'server.apps'
local AppHost = require 'server.hosting'
local DeviceOs = require 'server.os'

local AppStore = { rows = {} }

function AppStore.load()
    local ok, rows = pcall(Store.loadInstalls)

    if not ok then
        Util.log('could not read the installed apps: ' .. tostring(rows))
    end

    AppStore.rows = ok and type(rows) == 'table' and rows or {}
end

function AppStore.key(session, device)
    if device.kind == 'tablet' then
        return session.item and session.item.serial or 'cid:' .. tostring(session.cid)
    end

    return tostring(device.id)
end

local function preinstalled(device, id)
    local entries = type(device.apps) == 'table' and device.apps.entries or nil
    local entry = type(entries) == 'table' and entries[id] or nil

    if entry and entry.on == true then return true end

    if Apps.isBuiltin(id) then
        return Config.os.preinstalled[id] == true
    end

    return Apps.options(id).preinstalled[device.kind] == true
end

function AppStore.installed(session, device, id)
    if OsRules.FIXED[id] or not OsRules.enabled('store') then return true end

    local own = AppStore.rows[AppStore.key(session, device)]

    if own and own[id] ~= nil then
        return own[id]
    end

    return preinstalled(device, id)
end

function AppStore.shown(session, device, id)
    return AppHost.onlyApp(session) == id or AppStore.installed(session, device, id)
end

function AppStore.ids(session, device, visible)
    local only = AppHost.onlyApp(session)

    if only then
        return { only }
    end

    local list = {}

    for _, id in ipairs(OsRules.apps(device.kind)) do
        if AppStore.installed(session, device, id) then
            list[#list + 1] = id
        end
    end

    for _, view in ipairs(visible) do
        if AppStore.installed(session, device, view.id) then
            list[#list + 1] = view.id
        end
    end

    return list
end

function AppStore.set(session, device, id, on, by)
    local key = AppStore.key(session, device)

    if device.temporary ~= true then
        Store.saveInstall(key, id, on, by)
    end

    local own = AppStore.rows[key] or {}

    own[id] = on
    AppStore.rows[key] = own
end

function AppStore.forget(device)
    if not device.temporary then return end

    AppStore.rows[tostring(device.id)] = nil
end

function AppStore.reply(session, device, source, visible)
    visible = visible or AppHost.visible(session, device, source)

    local installed = AppStore.ids(session, device, visible)

    session.listSig = AppHost.signature(visible, installed)

    return { installed = installed }
end

local function hostDevice(device)
    return device.kind == 'tablet' and AppHost.tabletDevice() or device
end

local function offered(session, device, source, id)
    if not AppRules.isId(id) then return false end
    if Util.contains(OsRules.apps(device.kind), id) then return true end

    local visible = AppHost.visible(session, device, source)

    return AppHost.listed(visible, id), visible
end

DeviceOs.register('store:install', function(source, lock, record, id)
    local device = hostDevice(record)
    local known, visible = offered(lock, device, source, id)

    if not known then
        return Util.fail('unknown_app')
    end

    if AppHost.signal(lock, device) == 0 then
        return Util.fail('no_signal')
    end

    AppStore.set(lock, device, id, true, lock.cid)

    return Util.ok(AppStore.reply(lock, device, source, visible))
end, { app = 'store', rate = 2 })

DeviceOs.register('store:remove', function(source, lock, record, id)
    local device = hostDevice(record)
    local known, visible = offered(lock, device, source, id)

    if not known then
        return Util.fail('unknown_app')
    end

    if OsRules.FIXED[id] then
        return Util.fail('app_fixed')
    end

    if not DeviceOs.mayManage(lock, record) then
        return Util.fail('device_manage_only')
    end

    AppStore.set(lock, device, id, false, lock.cid)
    AppHost.drop(lock, id, 'app_closed', true, record.kind == 'tablet' and 'tablet' or lock.id)

    return Util.ok(AppStore.reply(lock, device, source, visible))
end, { app = 'store', rate = 2 })

return AppStore
