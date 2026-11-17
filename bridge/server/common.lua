local Config = require 'config'

local common = {}

function common.validSource(source)
    return type(source) == 'number' and source > 0
end

function common.trusted(playerSource)
    local from = tonumber(source)

    return not from or from <= 0 or from == tonumber(playerSource)
end

function common.callable(value)
    if type(value) == 'function' then return true end

    local meta = type(value) == 'table' and getmetatable(value) or nil

    return type(meta) == 'table' and meta.__call ~= nil
end

function common.ace(source, ace)
    local answer = IsPlayerAceAllowed(source, ace)

    return answer ~= nil and answer ~= false and answer ~= 0
end

local function inGroups(source, level, check)
    if not check then return false end

    local groups = type(Config.adminGroups) == 'table' and Config.adminGroups[level] or nil

    for _, name in ipairs(type(groups) == 'table' and groups or {}) do
        if type(name) == 'string' and name ~= '' and check(source, name) then
            return true
        end
    end

    return false
end

function common.isAdmin(source, check)
    if not common.validSource(source) then return false end

    return common.ace(source, Config.aces.admin) or inGroups(source, 'admin', check)
end

function common.canManage(source, check)
    if not common.validSource(source) then return false end

    return common.isAdmin(source, check) or common.ace(source, Config.aces.manage) or inGroups(source, 'manage', check)
end

function common.trim(text)
    if type(text) ~= 'string' then return nil end

    local clean = text:match('^%s*(.-)%s*$')

    return clean ~= '' and clean or nil
end

function common.fullName(info)
    if type(info) ~= 'table' then return nil end

    return common.trim(('%s %s'):format(info.firstname or '', info.lastname or ''))
end

function common.decode(text)
    if type(text) == 'table' then return text end
    if type(text) ~= 'string' or text == '' then return nil end

    local ok, value = pcall(json.decode, text)

    return ok and type(value) == 'table' and value or nil
end

function common.sortedGroups(raw)
    local list, byName = {}, {}

    for name, group in pairs(type(raw) == 'table' and raw or {}) do
        if type(name) == 'string' and type(group) == 'table' then
            local grades, names = {}, {}

            for level, grade in pairs(type(group.grades) == 'table' and group.grades or {}) do
                local number = tonumber(level)

                if number then
                    local label = type(grade) == 'table' and (grade.label or grade.name) or tostring(number)

                    grades[#grades + 1] = { level = number, name = tostring(label) }
                    names[number] = tostring(label)
                end
            end

            table.sort(grades, function(a, b) return a.level < b.level end)

            local entry = { name = name, label = group.label or name, grades = grades }

            list[#list + 1] = entry
            byName[name] = { label = entry.label, grades = names }
        end
    end

    table.sort(list, function(a, b)
        if a.label == b.label then
            return a.name < b.name
        end

        return a.label < b.label
    end)

    return list, byName
end

function common.groupCache(read)
    local cache, at = nil, 0

    return function(fresh)
        local now = GetGameTimer()

        if fresh or not cache or now - at > 60000 then
            local jobs, byJob = common.sortedGroups(read('jobs', fresh))
            local gangs, byGang = common.sortedGroups(read('gangs', fresh))

            cache = { jobs = jobs, gangs = gangs, byJob = byJob, byGang = byGang }
            at = now
        end

        return cache
    end, function()
        cache = nil
    end
end

local OX_KINDS = { inform = 'inform', success = 'success', error = 'error', warning = 'warning' }

function common.notifyOx(source, text, kind)
    TriggerClientEvent('ox_lib:notify', source, { title = locale('brand'), description = text, type = OX_KINDS[kind] or 'inform' })
end

function common.framework()
    return Config.notifyWith == 'framework'
end

return common
