local Config = require 'config'
local Util = require 'shared.util'
local AccessRules = require 'shared.access'
local AppRules = require 'shared.apps'
local OsRules = require 'shared.os'
local Store = require 'server.store'
local Audit = require 'server.audit'
local Access = require 'server.access'

local Apps = { registered = {}, rows = {}, refused = {}, claims = {}, loaded = false }

local function trusted(resource)
    return Util.contains(Config.trustedResources, resource)
end

local function claimed(id, claim, owner)
    Apps.refused[id] = { resource = claim.resource, reason = 'id_taken', version = claim.def.version }
    Util.log(('app %s from %s is refused: the id belongs to %s'):format(id, claim.resource, owner))
end

local function dropClaim(id, resource)
    local list = Apps.claims[id]

    if not list then return end

    for index = #list, 1, -1 do
        if list[index].resource == resource then
            table.remove(list, index)
        end
    end

    local entry = Apps.registered[id]

    if entry and entry.resource == resource and list[1] then
        Apps.registered[id] = { def = list[1].def, resource = list[1].resource }
    end

    if #list == 0 then
        Apps.claims[id] = nil
    end
end

function Apps.settle()
    local Sessions = require 'server.sessions'

    local claims = Apps.claims

    Apps.claims = {}

    for _, id in ipairs(Util.keys(Apps.registered)) do
        local entry, row = Apps.registered[id], Apps.rows[id]
        local list = claims[id] or { { resource = entry.resource, def = entry.def } }
        local winner = list[1]

        if row then
            winner = nil

            for _, claim in ipairs(list) do
                if claim.resource == row.resource then
                    winner = claim
                end
            end
        end

        if winner then
            Apps.registered[id] = { def = winner.def, resource = winner.resource }
        else
            Apps.registered[id] = nil

            if Sessions.closeApp then
                Sessions.closeApp(id, 'app_stopped')
            end
        end

        for _, claim in ipairs(list) do
            if claim ~= winner then
                claimed(id, claim, row and row.resource or winner.resource)
            end
        end
    end
end

function Apps.load()
    Apps.rows = {}

    for _, row in ipairs(Store.loadApps()) do
        Apps.rows[row.id] = row
    end

    Apps.loaded = true
    Apps.settle()

    for _, id in ipairs(Util.keys(Apps.registered)) do
        Apps.sync(id)
    end
end

function Apps.sync(id)
    local Admin = require 'server.admin'

    local entry = Apps.registered[id]

    if not entry then return end

    local def, row = entry.def, Apps.rows[id]

    if not row then
        row = {
            id = id,
            resource = entry.resource,
            status = trusted(entry.resource) and 'allowed' or 'pending',
            enabled = true,
            options = {},
            label = def.label,
            version = def.version,
        }

        local ok, failure = pcall(Store.insertApp, row)

        if not ok then
            Util.log(('could not store app %s: %s'):format(id, tostring(failure)))
        end

        Apps.rows[id] = row

        if row.status == 'pending' then
            Util.log(('app %s from %s waits for approval: /%s, Apps and integrations'):format(
                id,
                entry.resource,
                Config.commands.admin
            ))

            Admin.pushCounts()
        end
    else
        row.label, row.version = def.label, def.version
        pcall(Store.seenApp, id, def.label, def.version)
    end
end

local function mediaRule(kind)
    local rule = AppRules.MEDIA[kind]

    return ('a %s is %d to %d px wide, %d to %d px tall and %g:1 to %g:1'):format(
        kind, rule.minWidth, rule.maxWidth, rule.minHeight, rule.maxHeight, rule.minRatio, rule.maxRatio
    )
end

function Apps.shippedMedia(kind, path, resource)
    local data = LoadResourceFile(resource, path)
    local reason, width, height = AppRules.mediaFault(kind, path, data)

    if not reason then return true end

    local why = 'the file is not in the script'

    if reason == 'bytes' then
        why = ('the file is %.1f MB, at most %g MB'):format(#data / 1048576, AppRules.MEDIA[kind].bytes / 1048576)
    elseif reason == 'format' then
        why = 'it is not a PNG, JPG or WebP picture of the type its name says'
    elseif reason == 'size' or reason == 'shape' then
        why = ('it is %d x %d px, %s'):format(width, height, mediaRule(kind))
    end

    Util.log(('the Store leaves out the %s %s of %s: %s'):format(kind, path, resource, why))

    return false
end

function Apps.shippedPictures(list, resource)
    local kept = {}

    for _, path in ipairs(list or {}) do
        if AppRules.isLink(path) or Apps.shippedMedia('picture', path, resource) then
            kept[#kept + 1] = path
        end
    end

    return kept
end

function Apps.register(def, resource)
    local DeviceLook = require 'server.look'

    local clean, reason = AppRules.validate(def)
    local id = type(def) == 'table' and AppRules.isId(def.id) and def.id or nil

    if id and OsRules.FIXED[id] then
        clean, reason = nil, 'id_taken'
    end

    if clean and LoadResourceFile(resource, clean.page) == nil then
        clean, reason = nil, 'page_missing'
    end

    if clean then
        clean.pictures = Apps.shippedPictures(clean.pictures, resource)

        if clean.cover and not Apps.shippedMedia('cover', clean.cover, resource) then
            clean.cover = nil
        end
    end

    if not clean then
        if id then
            Apps.refused[id] = {
                resource = resource,
                reason = reason,
                version = type(def.version) == 'string' and def.version:sub(1, 32) or nil,
            }
        end

        return false, reason
    end

    local row, current = Apps.rows[clean.id], Apps.registered[clean.id]

    if not Apps.loaded then
        Apps.refused[clean.id] = nil

        local list = Apps.claims[clean.id] or {}

        if current and #list == 0 then
            list[1] = { resource = current.resource, def = current.def }
        end

        local mine = false

        for _, claim in ipairs(list) do
            if claim.resource == resource then
                claim.def, mine = clean, true
            end
        end

        if not mine then
            list[#list + 1] = { resource = resource, def = clean }
        end

        Apps.claims[clean.id] = list

        if not current or current.resource == resource then
            Apps.registered[clean.id] = { def = clean, resource = resource }
        end

        DeviceLook.changed(resource)

        return true
    end

    if (row and row.resource ~= resource) or (current and current.resource ~= resource) then
        return false, 'id_taken'
    end

    Apps.refused[clean.id] = nil
    Apps.registered[clean.id] = { def = clean, resource = resource }
    Apps.sync(clean.id)
    DeviceLook.changed(resource)

    return true
end

function Apps.unregister(id, resource)
    local Sessions = require 'server.sessions'
    local DeviceLook = require 'server.look'

    if not Apps.loaded and resource then
        dropClaim(id, resource)
    end

    local entry = Apps.registered[id]

    if not entry or (resource and entry.resource ~= resource) then return false end

    Apps.registered[id] = nil

    if Sessions.closeApp then
        Sessions.closeApp(id, 'app_stopped')
    end

    DeviceLook.changed(entry.resource)

    return true
end

function Apps.dropResource(resource)
    local DeviceLook = require 'server.look'

    for _, id in ipairs(Util.keys(Apps.claims)) do
        dropClaim(id, resource)
    end

    for _, id in ipairs(Util.keys(Apps.registered)) do
        if Apps.registered[id].resource == resource then
            Apps.unregister(id)
        end
    end

    for id, refused in pairs(Apps.refused) do
        if refused.resource == resource then
            Apps.refused[id] = nil
        end
    end

    DeviceLook.changed(resource)
end

function Apps.running(id)
    local entry = Apps.registered[id]

    return entry ~= nil and GetResourceState(entry.resource) == 'started'
end

function Apps.status(id)
    local row, refused = Apps.rows[id], Apps.refused[id]

    if row and row.status == 'blocked' then
        return 'blocked'
    end

    if refused and refused.reason == 'unsupported_api' then
        return 'needs_update'
    end

    if row and row.status == 'pending' then
        return 'pending'
    end

    if not Apps.running(id) then
        return 'stopped'
    end

    if row and not row.enabled then
        return 'off'
    end

    return 'running'
end

function Apps.options(id)
    local entry, row = Apps.registered[id], Apps.rows[id]
    local defaults = entry and entry.def.defaults or { kinds = {}, playerDevices = false }
    local saved = row and type(row.options) == 'table' and row.options or {}
    local kinds = Util.copy(defaults.kinds or {})

    for kind, on in pairs(type(saved.kinds) == 'table' and saved.kinds or {}) do
        kinds[kind] = on == true
    end

    local access = defaults.access

    if saved.access == false then
        access = nil
    elseif type(saved.access) == 'table' then
        access = saved.access
    end

    local playerDevices = defaults.playerDevices == true

    if type(saved.playerDevices) == 'boolean' then
        playerDevices = saved.playerDevices
    end

    local preinstalled = Util.copy(defaults.preinstalled or {})

    for kind, on in pairs(type(saved.preinstalled) == 'table' and saved.preinstalled or {}) do
        preinstalled[kind] = on == true
    end

    return {
        kinds = kinds,
        preinstalled = preinstalled,
        playerDevices = playerDevices,
        access = access,
        watch = saved.watch == 'cover' and 'cover' or 'app',
    }
end

local function fieldOptions(field, source)
    if type(field.options) == 'table' and not field.options.__cfx_functionReference then
        return field.options
    end

    local ok, list = pcall(field.options, source)

    if not ok or type(list) ~= 'table' then
        return {}
    end

    local clean = {}

    for _, option in ipairs(list) do
        if type(option) == 'table' and (type(option.value) == 'string' or Util.isFinite(option.value)) then
            clean[#clean + 1] = {
                value = option.value,
                label = Util.cleanText(option.label or tostring(option.value), 64) or tostring(option.value),
            }
        end
    end

    return clean
end

function Apps.fieldsView(def)
    local list = {}

    for index, field in ipairs(def and def.settings or {}) do
        list[index] = {
            key = field.key,
            type = field.type,
            label = field.label,
            default = field.default,
            min = field.min,
            max = field.max,
            maxLength = field.maxLength,
            options = field.type == 'select' and fieldOptions(field) or nil,
        }
    end

    return list
end

function Apps.view(id, memo)
    local entry, row, refused = Apps.registered[id], Apps.rows[id], Apps.refused[id]
    local def = entry and entry.def
    local options = Apps.options(id)

    return {
        id = id,
        label = def and def.label or row and row.label or id,
        resource = entry and entry.resource or row and row.resource or refused and refused.resource,
        version = def and def.version or row and row.version or refused and refused.version,
        description = def and def.description or nil,
        api = def and def.api or nil,
        status = Apps.status(id),
        approval = row and row.status or nil,
        enabled = row == nil or row.enabled == true,
        running = Apps.running(id),
        kinds = def and Util.copy(def.kinds) or {},
        terminal = def and def.terminal or false,
        icon = def and Util.copy(def.icon) or nil,
        canvas = def and Util.copy(def.canvas) or nil,
        watch = def and def.watch or 'cover',
        network = def and def.network,
        settings = Apps.fieldsView(def),
        options = {
            kinds = options.kinds,
            preinstalled = options.preinstalled,
            playerDevices = options.playerDevices,
            watch = options.watch,
            access = options.access and Access.describe(options.access, memo) or nil,
        },
        refused = refused and refused.reason or nil,
        firstSeen = row and row.firstSeen or nil,
        lastSeen = row and row.lastSeen or nil,
    }
end

function Apps.ids()
    local set = {}

    for id in pairs(Apps.rows) do
        set[id] = true
    end

    for id in pairs(Apps.registered) do
        set[id] = true
    end

    for id in pairs(Apps.refused) do
        set[id] = true
    end

    return Util.keys(set)
end

function Apps.list(memo)
    local list = {}

    for _, id in ipairs(Apps.ids()) do
        list[#list + 1] = Apps.view(id, memo)
    end

    table.sort(list, function(a, b)
        if a.label == b.label then
            return a.id < b.id
        end

        return a.label < b.label
    end)

    return list
end

function Apps.supports(id, kind)
    local entry = Apps.registered[id]

    return entry ~= nil and Util.contains(entry.def.kinds, kind)
end

function Apps.forKind(kind, memo)
    local list = {}

    for _, view in ipairs(Apps.list(memo)) do
        if Util.contains(view.kinds, kind) then
            list[#list + 1] = view
        end
    end

    return list
end

local function kindSwitches(id, value, osOnly)
    if type(value) ~= 'table' then
        return nil, 'invalid_app_patch'
    end

    local kinds = {}

    for kind, on in pairs(value) do
        if not Config.kinds[kind] or (osOnly and kind == 'terminal') or type(on) ~= 'boolean' then
            return nil, 'invalid_app_patch'
        end

        if Apps.registered[id] and not Apps.supports(id, kind) then
            return nil, 'app_wrong_kind'
        end

        kinds[kind] = on
    end

    return kinds
end

function Apps.save(actor, id, patch)
    local Sessions = require 'server.sessions'
    local DeviceLook = require 'server.look'

    local row = Apps.rows[id]

    if not row then
        return nil, 'unknown_app'
    end

    if type(patch) ~= 'table' then
        return nil, 'invalid_app_patch'
    end

    local fields, statusChange, optionChange = {}, {}, {}
    local options = Util.copy(type(row.options) == 'table' and row.options or {})

    for key, value in pairs(patch) do
        if key == 'approval' then
            if value ~= 'allowed' and value ~= 'blocked' then
                return nil, 'invalid_app_patch'
            end

            if value ~= row.status then
                fields.status, statusChange.approval = value, value
            end
        elseif key == 'enabled' then
            if type(value) ~= 'boolean' then
                return nil, 'invalid_app_patch'
            end

            if value ~= row.enabled then
                fields.enabled, statusChange.enabled = value, value
            end
        elseif key == 'kinds' or key == 'preinstalled' then
            local kinds, reason = kindSwitches(id, value, key == 'preinstalled')

            if not kinds then
                return nil, reason
            end

            options[key], optionChange[key] = kinds, kinds
        elseif key == 'playerDevices' then
            if type(value) ~= 'boolean' then
                return nil, 'invalid_app_patch'
            end

            options.playerDevices, optionChange.playerDevices = value, value
        elseif key == 'watch' then
            if value ~= 'app' and value ~= 'cover' then
                return nil, 'invalid_app_patch'
            end

            options.watch, optionChange.watch = value, value
        elseif key == 'access' then
            if value == false then
                options.access = false
            else
                local access, reason = Access.validate(value, nil, {
                    modes = { 'rules' },
                    types = { 'job', 'gang', 'citizen', 'provider' },
                    current = type(options.access) == 'table' and options.access or nil,
                })

                if not access then
                    return nil, reason
                end

                options.access = access
            end

            optionChange.access = options.access and #options.access.rules or false
        else
            return nil, 'invalid_app_patch'
        end
    end

    if next(optionChange) then
        fields.options = options
    end

    if next(fields) == nil then
        return Apps.view(id)
    end

    Store.updateApp(id, fields)

    if fields.status then
        row.status = fields.status
    end

    if fields.enabled ~= nil then
        row.enabled = fields.enabled
    end

    if fields.options then
        row.options = fields.options
    end

    if next(statusChange) then
        Audit.write(actor, 'app_status', nil, { app = id, change = statusChange })
    end

    if next(optionChange) then
        Audit.write(actor, 'app_options', nil, { app = id, change = optionChange })
    end

    if (fields.status == 'blocked' or fields.enabled == false) and Sessions.closeApp then
        Sessions.closeApp(id, 'app_blocked')
    end

    if (fields.status or fields.enabled ~= nil) and Apps.registered[id] then
        DeviceLook.changed(Apps.registered[id].resource)
    end

    return Apps.view(id)
end

function Apps.isBuiltin(id)
    return Util.contains(OsRules.APPS, id)
end

function Apps.checkOnly(id, device)
    if not device or not OsRules.kind(device.kind) or id == 'store' then
        return 'only_app_kind'
    end

    if Apps.isBuiltin(id) then
        if not OsRules.enabled(id) then
            return 'app_off'
        end

        return nil
    end

    local registered = Apps.registered[id]

    if not registered then
        return Apps.rows[id] and 'app_stopped' or 'unknown_app'
    end

    if not Util.contains(registered.def.kinds, device.kind) then
        return 'app_wrong_kind'
    end

    if Apps.isPlayerDevice(device) and not Apps.options(id).playerDevices then
        return 'app_not_player_devices'
    end

    return nil
end

local function keepOnly(apps, current, device)
    local id = apps.only

    if not id then
        return apps
    end

    local kept = type(current) == 'table' and current.only == id

    if not kept then
        local reason = Apps.checkOnly(id, device)

        if reason then
            return nil, reason, id
        end
    end

    if Apps.isBuiltin(id) then
        return apps
    end

    local entry = apps.entries[id] or { settings = {} }

    entry.on = true
    apps.entries[id] = entry

    if not Util.contains(apps.order, id) then
        apps.order[#apps.order + 1] = id
    end

    return apps
end

function Apps.normalizeDeviceApps(value, current, device)
    local apps, reason, id = Apps.checkDeviceApps(value, current, device)

    if not apps then
        return nil, reason, id
    end

    return keepOnly(apps, current, device)
end

function Apps.checkDeviceApps(value, current, device)
    local before = type(current) == 'table' and type(current.entries) == 'table' and current.entries or {}

    return AppRules.normalizeDeviceApps(value, function(id, entry)
        local registered = Apps.registered[id]
        local old = before[id]

        if registered then
            if device and not Util.contains(registered.def.kinds, device.kind) then
                return nil, 'app_wrong_kind'
            end

            local values = AppRules.checkValues(entry.settings, registered.def.settings, fieldOptions)

            if not values then
                return nil, 'invalid_app_settings'
            end

            entry.settings = values
        elseif not old and not Apps.rows[id] then
            return nil, 'unknown_app'
        end

        if entry.access then
            local access, reason = Access.validate(entry.access, device, {
                modes = { 'rules' },
                current = old and old.access or nil,
            })

            if not access then
                return nil, reason
            end

            entry.access = access
        end

        return entry
    end)
end

function Apps.normalizePage(value, current)
    if value == nil or value == false then return false end

    if type(value) ~= 'table' or not AppRules.isId(value.app) then
        return nil, 'invalid_page'
    end

    local registered = Apps.registered[value.app]
    local kept = type(current) == 'table' and current.app == value.app
    local values = AppRules.cleanValues(value.settings)

    if not values then
        return nil, 'invalid_app_settings'
    end

    if registered then
        if not registered.def.terminal then
            return nil, 'app_not_terminal'
        end

        if not kept and (Apps.rows[value.app] == nil or Apps.rows[value.app].status ~= 'allowed') then
            return nil, 'app_not_allowed'
        end

        values = AppRules.checkValues(values, registered.def.settings, fieldOptions)

        if not values then
            return nil, 'invalid_app_settings'
        end
    elseif not kept then
        return nil, 'unknown_app'
    end

    return { app = value.app, settings = values }
end

function Apps.isPlayerDevice(device)
    return device.origin == 'item' or device.ownerCid ~= nil
end

function Apps.decide(device, id, subject, context)
    local row = Apps.rows[id]

    if not row or row.status == 'pending' then
        return false, 'app_pending'
    end

    if row.status == 'blocked' then
        return false, 'app_blocked'
    end

    if not Apps.running(id) then
        return false, 'app_stopped'
    end

    if not row.enabled then
        return false, 'app_off'
    end

    if not Apps.supports(id, device.kind) then
        return false, 'app_wrong_kind'
    end

    local options = Apps.options(id)
    local entry = type(device.apps) == 'table' and type(device.apps.entries) == 'table' and device.apps.entries[id] or nil
    local on

    if entry then
        on = entry.on == true
    elseif Apps.isPlayerDevice(device) then
        on = options.kinds[device.kind] ~= false
    else
        on = options.kinds[device.kind] == true
    end

    if not on then
        return false, 'app_switched_off'
    end

    if Apps.isPlayerDevice(device) and not options.playerDevices then
        return false, 'app_not_player_devices'
    end

    local access = entry and entry.access or options.access

    if access and not AccessRules.passes(access, subject, context) then
        return false, 'app_access'
    end

    return true
end

function Apps.testFor(device, subject, source)
    local list = {}

    if not OsRules.hasOs(device.kind) then
        local page = type(device.page) == 'table' and device.page.app or nil

        if page then
            local row = Apps.rows[page]
            local ok = Apps.running(page) and row ~= nil and row.status == 'allowed' and row.enabled == true
            local status = Apps.status(page)

            list[1] = {
                id = page,
                label = Apps.view(page).label,
                visible = ok,
                reason = not ok and (status == 'running' and 'app_pending' or 'app_' .. status) or nil,
            }
        end

        return list
    end

    local context = Access.context(device, source, true, false)
    local ids = {}

    for id, entry in pairs(Apps.registered) do
        if Util.contains(entry.def.kinds, device.kind) then
            ids[#ids + 1] = id
        end
    end

    table.sort(ids)

    for _, id in ipairs(ids) do
        local visible, reason = Apps.decide(device, id, subject, context)

        list[#list + 1] = { id = id, label = Apps.registered[id].def.label, visible = visible, reason = reason }
    end

    return list
end

return Apps
