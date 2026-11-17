local Config = require 'config'
local Util = require 'shared.util'

local AccessRules = {}

AccessRules.TYPES = { 'job', 'gang', 'citizen', 'keys', 'provider' }
AccessRules.MODES = { 'everyone', 'owner', 'rules' }

local known = {}

for _, name in ipairs(AccessRules.TYPES) do
    known[name] = true
end

local function maxRules()
    return Config.limits.rulesPerList or 24
end

local function setOf(list)
    local result = {}

    for _, value in ipairs(list or {}) do
        result[value] = true
    end

    return result
end

local function grade(value)
    if value == nil then
        return 0
    end

    return Util.integer(tonumber(value), 0, 100)
end

function AccessRules.normalizeRule(rule)
    if type(rule) ~= 'table' or not known[rule.type] then
        return nil, 'invalid_rule'
    end

    if rule.type == 'job' then
        local name, level = Util.name(rule.name), grade(rule.grade)

        if not name then
            return nil, 'unknown_job'
        end

        if not level then
            return nil, 'bad_grade'
        end

        return { type = 'job', name = name, grade = level, duty = rule.duty == true or nil }
    elseif rule.type == 'gang' then
        local name, level = Util.name(rule.name), grade(rule.grade)

        if not name then
            return nil, 'unknown_gang'
        end

        if not level then
            return nil, 'bad_grade'
        end

        if rule.duty == true then
            return nil, 'gang_duty'
        end

        return { type = 'gang', name = name, grade = level }
    elseif rule.type == 'citizen' then
        if not Util.isCid(rule.cid) then
            return nil, 'bad_citizen'
        end

        return { type = 'citizen', cid = rule.cid, label = Util.cleanText(rule.label, 64) or rule.cid }
    elseif rule.type == 'keys' then
        return { type = 'keys' }
    end

    local provider = Util.name(rule.provider)

    if not provider then
        return nil, 'unknown_provider'
    end

    if type(rule.value) ~= 'string' or #rule.value < 1 or #rule.value > 64 or not rule.value:match('^[%w_%-%.:]+$') then
        return nil, 'bad_provider_value'
    end

    if rule.level ~= nil and (type(rule.level) ~= 'string' or #rule.level > 32 or not rule.level:match('^[%w_%-]+$')) then
        return nil, 'bad_provider_level'
    end

    return { type = 'provider', provider = provider, value = rule.value, level = rule.level }
end

function AccessRules.ruleKey(rule)
    if rule.type == 'job' or rule.type == 'gang' then
        return ('%s:%s:%d:%s'):format(rule.type, rule.name, rule.grade, rule.duty and 'd' or '')
    elseif rule.type == 'citizen' then
        return 'citizen:' .. rule.cid
    elseif rule.type == 'provider' then
        return ('provider:%s:%s:%s'):format(rule.provider, rule.value, rule.level or '')
    end

    return rule.type
end

function AccessRules.normalize(access, options)
    options = options or {}

    if type(access) ~= 'table' then
        return nil, 'invalid_access'
    end

    local modes = setOf(options.modes or AccessRules.MODES)
    local types = setOf(options.types or AccessRules.TYPES)
    local mode = access.mode

    if not modes[mode] then
        return nil, 'invalid_access'
    end

    local rules = access.rules

    if rules == nil then
        rules = {}
    end

    if type(rules) ~= 'table' then
        return nil, 'invalid_access'
    end

    local count = #rules

    if count > (options.max or maxRules()) then
        return nil, 'too_many_rules'
    end

    for key in pairs(rules) do
        if math.type(key) ~= 'integer' or key < 1 or key > count then
            return nil, 'invalid_access'
        end
    end

    local clean, seen = {}, {}

    for index = 1, count do
        local rule, reason = AccessRules.normalizeRule(rules[index])

        if not rule then
            return nil, reason, index
        end

        if not types[rule.type] then
            return nil, 'invalid_rule', index
        end

        local key = AccessRules.ruleKey(rule)

        if not seen[key] then
            seen[key] = true
            clean[#clean + 1] = rule
        end
    end

    return { mode = mode, rules = clean }
end

function AccessRules.matchRule(rule, subject, context)
    if type(subject) ~= 'table' then return false end

    if rule.type == 'job' then
        local job = subject.job or {}

        if job.name == rule.name and (job.grade or -1) >= rule.grade and (not rule.duty or job.onduty == true) then return true end
        if rule.duty then return false end

        local jobs = subject.jobs or {}

        return (tonumber(jobs[rule.name]) or -1) >= rule.grade
    elseif rule.type == 'gang' then
        local gang = subject.gang or {}

        if gang.name == rule.name and (gang.grade or -1) >= rule.grade then return true end

        local gangs = subject.gangs or {}

        return (tonumber(gangs[rule.name]) or -1) >= rule.grade
    elseif rule.type == 'citizen' then
        return subject.cid ~= nil and subject.cid == rule.cid
    elseif rule.type == 'keys' then
        return context ~= nil and context.keys ~= nil and context.keys(subject) == true
    elseif rule.type == 'provider' then
        return context ~= nil and context.provider ~= nil and context.provider(rule, subject) == true
    end

    return false
end

local function groupWhy(rule, current, levels)
    local main = type(current) == 'table' and current or {}

    if main.name == rule.name then
        if (main.grade or -1) < rule.grade then
            return 'grade', main.grade or 0
        end

        return 'duty'
    end

    local level = tonumber((type(levels) == 'table' and levels or {})[rule.name])

    if level == nil then
        return 'not_in'
    end

    if level < rule.grade then
        return 'grade', level
    end

    return 'side_duty'
end

local OTHER_WHY = { citizen = 'person', keys = 'keys', provider = 'provider' }

function AccessRules.explain(rule, subject, context)
    if AccessRules.matchRule(rule, subject, context) then
        return true
    end

    local value = type(subject) == 'table' and subject or {}

    if rule.type == 'job' then
        return false, groupWhy(rule, value.job, value.jobs)
    end

    if rule.type == 'gang' then
        return false, groupWhy(rule, value.gang, value.gangs)
    end

    return false, OTHER_WHY[rule.type] or 'provider'
end

function AccessRules.passes(access, subject, context)
    if type(access) ~= 'table' then return false end
    if access.mode == 'everyone' then return true end
    if access.mode ~= 'rules' then return false end

    for index, rule in ipairs(access.rules or {}) do
        if AccessRules.matchRule(rule, subject, context) then
            return true, index
        end
    end

    return false
end

function AccessRules.decideUse(device, subject, context)
    context = context or {}

    if subject and subject.cid and device.ownerCid and device.ownerCid == subject.cid then
        return { allowed = true, via = 'owner' }
    end

    if context.admin then
        if not device.ownerCid then
            return { allowed = true, via = 'admin' }
        end

        if context.adminsOpenAny then
            return { allowed = true, via = 'admin_open' }
        end
    end

    local passed, index = AccessRules.passes(device.access, subject, context)

    if passed then
        return { allowed = true, via = index and 'rule' or 'everyone', rule = index }
    end

    return { allowed = false, refusal = AccessRules.refusal(device.access, subject, device) }
end

function AccessRules.decideManage(device, subject, context)
    context = context or {}

    if context.admin then
        return { allowed = true, via = 'admin' }
    end

    if subject and subject.cid and device.ownerCid and device.ownerCid == subject.cid then
        return { allowed = true, via = 'owner' }
    end

    local manage = device.manage

    if type(manage) == 'table' and manage.mode == 'rules' then
        local passed, index = AccessRules.passes(manage, subject, context)

        if passed then
            return { allowed = true, via = 'rule', rule = index }
        end
    end

    return { allowed = false }
end

function AccessRules.refusal(access, subject, device)
    local closed = { reason = device and not device.ownerCid and 'access_admins' or 'access_owner' }

    if type(access) ~= 'table' or access.mode == 'owner' then
        return closed
    end

    local rules = access.rules or {}

    if access.mode ~= 'rules' or #rules == 0 then
        return closed
    end

    if #rules > 1 then
        local kinds = {}

        for _, rule in ipairs(rules) do
            kinds[rule.type] = true
        end

        if Util.count(kinds) > 1 or not (kinds.job or kinds.gang) then
            return { reason = 'access_list' }
        end
    end

    local rule = rules[1]

    if rule.type == 'job' then
        local job = subject and subject.job or {}

        if #rules == 1 and rule.duty and job.name == rule.name and (job.grade or -1) >= rule.grade and job.onduty ~= true then
            return { reason = 'access_duty' }
        end

        local names = {}

        for index, entry in ipairs(rules) do
            names[index] = { type = 'job', name = entry.name, grade = entry.grade }
        end

        return { reason = 'access_job', groups = names }
    elseif rule.type == 'gang' then
        local names = {}

        for index, entry in ipairs(rules) do
            names[index] = { type = 'gang', name = entry.name, grade = entry.grade }
        end

        return { reason = 'access_gang', groups = names }
    elseif rule.type == 'citizen' then
        return { reason = 'access_players' }
    elseif rule.type == 'keys' then
        return { reason = 'access_keys' }
    end

    return { reason = 'access_provider', provider = rule.provider, value = rule.value, level = rule.level }
end

function AccessRules.usesProvider(access, providerId, value)
    if type(access) ~= 'table' then return false end

    for _, rule in ipairs(access.rules or {}) do
        if rule.type == 'provider' and rule.provider == providerId and (value == nil or rule.value == value) then return true end
    end

    return false
end

function AccessRules.usesType(access, ruleType)
    if type(access) ~= 'table' then return false end

    for _, rule in ipairs(access.rules or {}) do
        if rule.type == ruleType then return true end
    end

    return false
end

return AccessRules
