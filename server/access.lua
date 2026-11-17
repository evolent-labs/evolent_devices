local Integrations = require 'integrations'
local Bridge = require 'bridge'
local Util = require 'shared.util'
local AccessRules = require 'shared.access'
local AppRules = require 'shared.apps'
local Registry = require 'server.registry'
local People = require 'server.people'
local Spaces = require 'server.spaces'

local Access = { DELAY_MS = 250, providers = {}, citizens = {}, pending = {}, cooling = false }

local CITIZEN_CACHE_MS = 300000

local function cleanLevels(levels)
    if levels == nil then
        return {}
    end

    if type(levels) ~= 'table' or #levels > 8 then return nil end

    local clean = {}

    for index, level in ipairs(levels) do
        if type(level) ~= 'table' or type(level.value) ~= 'string' or #level.value > 32 then return nil end
        if not level.value:match('^[%w_%-]+$') then return nil end

        local label = Util.label(level.label or level.value, 40)

        if not label then return nil end

        clean[index] = { value = level.value, label = label }
    end

    return clean
end

function Access.registerProvider(def, resource)
    if type(def) ~= 'table' or not AppRules.isId(def.id) then
        return false, 'invalid_id'
    end

    local label = Util.label(def.label, 40)

    if not label then
        return false, 'invalid_label'
    end

    if not AppRules.isCallable(def.options) or not AppRules.isCallable(def.check) then
        return false, 'invalid_hook'
    end

    local levels = cleanLevels(def.levels)

    if not levels then
        return false, 'invalid_levels'
    end

    local existing = Access.providers[def.id]

    if existing and existing.resource ~= resource and GetResourceState(existing.resource) == 'started' then
        return false, 'id_taken'
    end

    Access.providers[def.id] = {
        id = def.id,
        label = label,
        resource = resource,
        options = def.options,
        check = def.check,
        levels = levels,
    }

    Access.changed(def.id)

    return true
end

function Access.unregisterProvider(id, resource)
    local provider = Access.providers[id]

    if not provider or (resource and provider.resource ~= resource) then return false end

    Access.providers[id] = nil
    Access.changed(id)

    return true
end

function Access.dropResource(resource)
    for id, provider in pairs(Access.providers) do
        if provider.resource == resource then
            Access.unregisterProvider(id)
        end
    end
end

function Access.providerRunning(id)
    local provider = Access.providers[id]

    return provider ~= nil and GetResourceState(provider.resource) == 'started'
end

function Access.providerOptions(id, forSource)
    local provider = Access.providers[id]

    if not provider or not Access.providerRunning(id) then return nil end

    local ok, list = pcall(provider.options, forSource)

    if not ok then
        Util.log(('access provider %s: options failed: %s'):format(id, tostring(list)))

        return nil
    end

    local clean = {}

    for _, option in ipairs(type(list) == 'table' and list or {}) do
        if type(option) == 'table' and type(option.value) == 'string' and #option.value <= 64 then
            clean[#clean + 1] = {
                value = option.value,
                label = Util.cleanText(option.label or option.value, 64) or option.value,
            }
        end
    end

    return clean
end

function Access.providerCheck(rule, subject)
    local provider = Access.providers[rule.provider]

    if not provider or not subject or not Access.providerRunning(rule.provider) then return false end

    local ok, result = pcall(provider.check, subject.source, subject.cid, rule.value, rule.level)

    if not ok then
        Util.log(('access provider %s: check failed: %s'):format(rule.provider, tostring(result)))

        return false
    end

    return result == true
end

function Access.providersView()
    local list = {}

    for _, id in ipairs(Util.keys(Access.providers)) do
        local provider = Access.providers[id]

        list[#list + 1] = {
            id = id,
            label = provider.label,
            resource = provider.resource,
            running = Access.providerRunning(id),
            options = Access.providerOptions(id, nil) or {},
            levels = Util.copy(provider.levels),
        }
    end

    return list
end

function Access.context(device, source, fetch, admin)
    if admin == nil then
        admin = People.admin(source)
    end

    return {
        admin = admin,
        adminsOpenAny = Registry.settings.general.adminsOpenAny == true,
        keys = function(subject)
            if not device.propertyId or not subject.cid then return false end

            local keys = Integrations.propertyKeys(device.propertyId, fetch)

            return keys ~= nil and (keys.owner == subject.cid or keys.keyholders[subject.cid] == true)
        end,
        provider = function(rule, subject) return Access.providerCheck(rule, subject) end,
    }
end

function Access.decideUse(source, device, fetch)
    local subject = People.subject(source)

    if not subject then
        return { allowed = false, refusal = { reason = 'not_ready' } }, nil
    end

    return AccessRules.decideUse(device, subject, Access.context(device, source, fetch)), subject
end

function Access.decideManage(source, device)
    local subject = Bridge.subject(source)

    if not subject then
        return { allowed = false }
    end

    return AccessRules.decideManage(device, subject, Access.context(device, source, false, false))
end

function Access.flags(source, device, subject, level)
    local Items = require 'server.items'

    if device.state ~= 'placed' or device.kind == 'tablet' then return nil end

    local context = Access.context(device, source, false, level == 'admin')
    local flags, any = {}, false

    if subject.cid and device.ownerCid == subject.cid then
        flags.own, any = true, true
    end

    if AccessRules.decideUse(device, subject, context).allowed then
        flags.use, any = true, true
    end

    context.admin = false

    if not flags.own and AccessRules.decideManage(device, subject, context).allowed then
        flags.manage, any = true, true
    end

    if level then
        flags.admin, any = true, true
    end

    if Items.pickable(device) and (flags.own or level or (flags.manage and Items.pickupBy(device) == 'manage')) then
        flags.pickup = true
    end

    return any and flags or nil
end

function Access.mapFor(source)
    local subject = People.subject(source)

    if not subject then
        return {}
    end

    local level = People.level(source)
    local map = {}

    for _, device in pairs(Registry.devices) do
        local flags = Access.flags(source, device, subject, level)

        if flags then
            map[device.id] = flags
        end
    end

    return map
end

function Access.push(source)
    TriggerClientEvent('evdev:client:access', source, Access.mapFor(source), true)
end

function Access.pushDevices(devices)
    for _, source in ipairs(People.online()) do
        local subject, level = People.subject(source), People.level(source)
        local map = {}

        for _, device in ipairs(devices) do
            map[device.id] = Access.flags(source, device, subject, level) or false
        end

        TriggerClientEvent('evdev:client:access', source, map, false)
    end
end

function Access.pushDevice(device)
    Access.pushDevices({ device })
end

function Access.pushAll()
    for _, source in ipairs(People.online()) do
        Access.push(source)
    end
end

local function usesProvider(device, providerId, value)
    if AccessRules.usesProvider(device.access, providerId, value) then return true end
    if AccessRules.usesProvider(device.manage, providerId, value) then return true end

    for _, entry in pairs(type(device.apps) == 'table' and device.apps.entries or {}) do
        if AccessRules.usesProvider(entry.access, providerId, value) then return true end
    end

    return false
end

local function flush(ids)
    local Sessions = require 'server.sessions'

    local devices = {}

    for _, id in ipairs(Util.keys(ids)) do
        local device = Registry.device(id)

        if device then
            devices[#devices + 1] = device
        end
    end

    if #devices == 0 then return end

    Access.pushDevices(devices)

    if Sessions.recheck then
        Sessions.recheck()
    end
end

local function cool()
    Access.cooling = true

    CreateThread(function()
        Wait(Access.DELAY_MS)

        local ids = Access.pending

        Access.pending, Access.cooling = {}, false

        if next(ids) ~= nil then
            cool()
            flush(ids)
        end
    end)
end

function Access.changed(providerId, value)
    if not Registry.ready then
        return 0
    end

    local ids, count = {}, 0

    for _, device in pairs(Registry.devices) do
        if device.state == 'placed' and usesProvider(device, providerId, value) then
            ids[device.id] = true
            count = count + 1
        end
    end

    if count == 0 then
        return 0
    end

    if Access.cooling then
        for id in pairs(ids) do
            Access.pending[id] = true
        end

        return count
    end

    cool()
    flush(ids)

    return count
end

function Access.withoutKeys(access)
    local copy = Util.copy(access)
    local kept = {}

    for _, rule in ipairs(copy.rules or {}) do
        if rule.type ~= 'keys' then
            kept[#kept + 1] = rule
        end
    end

    copy.rules = kept

    return copy
end

function Access.lookupCitizen(cid)
    if not Util.isCid(cid) then return nil end

    local cached = Access.citizens[cid]
    local now = GetGameTimer()

    if cached and now - cached.at <= CITIZEN_CACHE_MS then
        return cached.found
    end

    local found = Bridge.lookupCitizen(cid)

    Access.citizens[cid] = { at = now, found = found }

    return found
end

local function keyed(access)
    local set = {}

    for _, rule in ipairs(type(access) == 'table' and access.rules or {}) do
        if type(rule) == 'table' and rule.type then
            local clean = AccessRules.normalizeRule(rule)

            if clean then
                set[AccessRules.ruleKey(clean)] = rule
            end
        end
    end

    return set
end

function Access.validate(access, device, options)
    options = options or {}

    local clean, reason, index = AccessRules.normalize(access, options)

    if not clean then
        return nil, reason, index
    end

    local groups = Bridge.groups()
    local before = keyed(options.current)

    for position, rule in ipairs(clean.rules) do
        local kept = before[AccessRules.ruleKey(rule)]

        if rule.type == 'gang' and not kept and not Bridge.info().gangs then
            return nil, 'no_gangs', position
        end

        if rule.type == 'job' or rule.type == 'gang' then
            local group = (rule.type == 'job' and groups.byJob or groups.byGang)[rule.name]

            if not group and not kept then
                return nil, rule.type == 'job' and 'unknown_job' or 'unknown_gang', position
            end

            if group and group.grades[rule.grade] == nil and not kept then
                return nil, 'bad_grade', position
            end
        elseif rule.type == 'citizen' then
            if kept and kept.label then
                rule.label = Util.cleanText(kept.label, 64) or rule.cid
            else
                local found = Access.lookupCitizen(rule.cid)

                if not found then
                    return nil, 'unknown_citizen', position
                end

                rule.cid = found.cid
                rule.label = Util.cleanText(found.name, 64) or rule.cid
            end
        elseif rule.type == 'keys' then
            if not options.template and (not device or not device.propertyId) then
                return nil, 'keys_not_home', position
            end
        elseif rule.type == 'provider' and not kept then
            local provider = Access.providers[rule.provider]

            if not provider then
                return nil, 'unknown_provider', position
            end

            if not Access.providerRunning(rule.provider) then
                return nil, 'provider_stopped', position
            end

            local found = false

            for _, option in ipairs(Access.providerOptions(rule.provider, nil) or {}) do
                if option.value == rule.value then
                    found = true
                    break
                end
            end

            if not found then
                return nil, 'bad_provider_value', position
            end

            if #provider.levels > 0 then
                local level = false

                for _, entry in ipairs(provider.levels) do
                    if entry.value == rule.level then
                        level = true
                        break
                    end
                end

                if not level then
                    return nil, 'bad_provider_level', position
                end
            elseif rule.level ~= nil then
                return nil, 'bad_provider_level', position
            end
        end
    end

    local seen, unique = {}, {}

    for _, rule in ipairs(clean.rules) do
        local key = AccessRules.ruleKey(rule)

        if not seen[key] then
            seen[key] = true
            unique[#unique + 1] = rule
        end
    end

    clean.rules = unique

    return clean
end

function Access.memo()
    return { options = {} }
end

local function optionLabel(memo, providerId, value)
    memo = memo or Access.memo()

    if memo.options[providerId] == nil then
        memo.options[providerId] = Access.providerOptions(providerId, nil) or false
    end

    for _, option in ipairs(memo.options[providerId] or {}) do
        if option.value == value then
            return option.label
        end
    end

    return value
end

local function groupText(rule)
    local groups = Bridge.groups()
    local group = (rule.type == 'job' and groups.byJob or groups.byGang)[rule.name]
    local label = group and group.label or rule.name

    if rule.grade > 0 then
        return locale('chip_group_grade', label, rule.grade), group ~= nil
    end

    return label, group ~= nil
end

function Access.ruleText(rule, memo)
    if rule.type == 'job' or rule.type == 'gang' then
        local text, known = groupText(rule)

        if rule.duty then
            text = locale('chip_on_duty', text)
        end

        return text, known
    elseif rule.type == 'citizen' then
        return rule.label or rule.cid, true
    elseif rule.type == 'keys' then
        return locale('chip_keys'), true
    end

    local provider = Access.providers[rule.provider]

    local text = locale(
        'chip_provider',
        optionLabel(memo, rule.provider, rule.value),
        provider and provider.label or rule.provider
    )

    if provider and rule.level then
        for _, level in ipairs(provider.levels) do
            if level.value == rule.level then
                text = locale('chip_provider_level', text, level.label)
                break
            end
        end
    end

    return text, Access.providerRunning(rule.provider)
end

local AUDIT_RULES = 12

local function noteList(rules, memo)
    local list = {}

    for index = 1, math.min(#rules, AUDIT_RULES) do
        local rule = rules[index]
        local text = Access.ruleText(rule, memo)

        if rule.type == 'citizen' and text ~= rule.cid then
            text = ('%s (%s)'):format(text, rule.cid)
        end

        list[index] = Util.clip(text, 60)
    end

    return list, math.max(0, #rules - AUDIT_RULES)
end

function Access.changes(before, after, memo)
    local old, new = keyed(before), keyed(after)
    local added, removed = {}, {}

    for _, rule in ipairs(after.rules) do
        if not old[AccessRules.ruleKey(rule)] then
            added[#added + 1] = rule
        end
    end

    for key, rule in pairs(old) do
        if not new[key] then
            removed[#removed + 1] = AccessRules.normalizeRule(rule)
        end
    end

    table.sort(removed, function(a, b) return AccessRules.ruleKey(a) < AccessRules.ruleKey(b) end)

    local detail = { from = type(before) == 'table' and before.mode or nil, mode = after.mode, rules = #after.rules }
    local more

    detail.added, more = noteList(added, memo)

    if more > 0 then
        detail.addedMore = more
    end

    detail.removed, more = noteList(removed, memo)

    if more > 0 then
        detail.removedMore = more
    end

    return detail
end

function Access.describe(access, memo)
    local rules = {}

    for index, rule in ipairs(type(access) == 'table' and access.rules or {}) do
        local entry = Util.copy(rule)
        local text, known = Access.ruleText(rule, memo)

        entry.text = text
        entry.missing = not known or nil
        rules[index] = entry
    end

    return { mode = type(access) == 'table' and access.mode or 'owner', rules = rules }
end

function Access.summary(device, memo)
    local access = type(device.access) == 'table' and device.access or {}

    if access.mode == 'everyone' then
        return { mode = 'everyone', chips = { { type = 'everyone', text = locale('chip_everyone') } } }
    end

    local rules = access.mode == 'rules' and access.rules or {}

    if #rules == 0 then
        local closed = device.ownerCid and 'owner' or 'admins'

        return { mode = access.mode or 'owner', chips = { { type = closed, text = locale('chip_' .. closed) } } }
    end

    local chips = {}

    for index = 1, math.min(#rules, 3) do
        chips[index] = { type = rules[index].type, text = (Access.ruleText(rules[index], memo)) }
    end

    if #rules > 3 then
        chips[#chips + 1] = { type = 'more', text = locale('chip_more', #rules - 3) }
    end

    return { mode = 'rules', chips = chips, count = #rules }
end

local function groupsText(groups)
    local names = {}
    local known = Bridge.groups()

    for index, entry in ipairs(groups or {}) do
        local group = (entry.type == 'job' and known.byJob or known.byGang)[entry.name]
        local label = group and group.label or entry.name

        names[index] = entry.grade > 0 and locale('access_group_grade', label, entry.grade) or label
    end

    return table.concat(names, locale('word_or'))
end

function Access.refusalText(device, refusal)
    local word = locale('kind_word_' .. tostring(device.kind))
    local reason = refusal and refusal.reason or 'access_owner'

    if reason == 'access_job' or reason == 'access_gang' then
        return locale(reason, groupsText(refusal.groups), word)
    end

    if reason == 'access_provider' then
        local provider = Access.providers[refusal.provider]

        local text = locale(
            'chip_provider',
            optionLabel(nil, refusal.provider, refusal.value),
            provider and provider.label or refusal.provider
        )

        return locale('access_provider', text, word)
    end

    if lib.getLocales()[reason] then
        return locale(reason, word)
    end

    return locale('access_list', word)
end

function Access.test(device, target)
    local Apps = require 'server.apps'

    local subject = Bridge.subject(target)

    if not subject then
        return nil, 'target_not_ready'
    end

    local context = Access.context(device, target, true)
    local use = AccessRules.decideUse(device, subject, context)
    local managed = Access.decideManage(target, device)
    local ped = GetPlayerPed(target)

    local checks = {
        enabled = device.enabled == true,
        space = device.state == 'placed' and Spaces.of(target) == Spaces.ofDevice(device),
        alive = not subject.dead,
        onFoot = not ped or ped == 0 or GetVehiclePedIsIn(ped, false) == 0,
    }

    local result = {
        player = { id = target, name = subject.name, cid = subject.cid },
        use = { allowed = use.allowed, via = use.via, rule = use.rule },
        manage = { allowed = managed.allowed, via = managed.via, rule = managed.rule },
        checks = checks,
    }

    if use.rule then
        result.use.ruleText = Access.ruleText(device.access.rules[use.rule])
    end

    if not use.allowed then
        result.use.reasonText = Access.refusalText(device, use.refusal)
    end

    result.openNow = use.allowed and checks.enabled and checks.space and checks.alive and checks.onFoot
    result.apps = Apps.testFor(device, subject, target)

    return result
end

function Access.check(device, target, access)
    local probe = device

    if access then
        probe = Util.copy(device)
        probe.access = access
    end

    local result, reason = Access.test(probe, target)

    if not result then
        return nil, reason
    end

    local subject = Bridge.subject(target)
    local context = Access.context(probe, target, true, false)
    local lines = {}

    if probe.access.mode == 'rules' then
        for index, rule in ipairs(probe.access.rules or {}) do
            local matched, why, grade = AccessRules.explain(rule, subject, context)

            lines[index] = {
                type = rule.type,
                text = Access.ruleText(rule),
                match = matched == true,
                why = why,
                grade = grade,
                need = rule.grade,
            }
        end
    end

    result.mode = probe.access.mode
    result.lines = lines
    result.owned = device.ownerCid ~= nil

    return result
end

return Access
