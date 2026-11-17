local Config = require 'config'
local Bridge = require 'bridge'
local Util = require 'shared.util'
local Registry = require 'server.registry'
local People = require 'server.people'

local Guard = { callbacks = {}, tokens = {}, hits = {}, locks = {} }

local LEVELS = { manage = 1, admin = 2 }

function Guard.level(source)
    if Bridge.isAdmin(source) then
        return 'admin'
    end

    if Bridge.canManage(source) then
        return 'manage'
    end

    return nil
end

function Guard.allows(level, needed)
    return level ~= nil and (LEVELS[level] or 0) >= (LEVELS[needed] or math.huge)
end

function Guard.actor(source)
    local subject = People.subject(source)

    if not subject or not subject.cid then return nil end

    return { source = source, cid = subject.cid, name = subject.name or subject.cid }
end

function Guard.issue(source)
    local token = Util.hex(32)

    Guard.tokens[source] = { token = token, last = GetGameTimer() }

    return token
end

function Guard.check(source, token)
    local entry = Guard.tokens[source]

    if not entry or type(token) ~= 'string' or #token ~= 32 then return false end

    local now = GetGameTimer()

    if now - entry.last > Config.admin.tokenIdleMinutes * 60000 then
        Guard.tokens[source] = nil

        return false
    end

    if entry.token ~= token then return false end

    entry.last = now

    return true
end

function Guard.drop(source)
    Guard.tokens[source] = nil
end

function Guard.sweep()
    local now = GetGameTimer()
    local limit = Config.admin.tokenIdleMinutes * 60000

    for source, entry in pairs(Guard.tokens) do
        if now - entry.last > limit then
            Guard.tokens[source] = nil
        end
    end
end

function Guard.rate(source, key, count, windowMs)
    local now = GetGameTimer()
    local perSource = Guard.hits[source]

    if not perSource then
        perSource = {}
        Guard.hits[source] = perSource
    end

    local entry = perSource[key]

    if not entry or now - entry.start >= (windowMs or 1000) then
        perSource[key] = { start = now, count = 1 }

        return true
    end

    if entry.count >= count then return false end

    entry.count = entry.count + 1

    return true
end

function Guard.forget(source)
    Guard.hits[source] = nil
    Guard.tokens[source] = nil
end

function Guard.exclusive(key, action)
    if Guard.locks[key] then
        return Util.fail('busy')
    end

    Guard.locks[key] = true

    local ok, result = pcall(action)

    Guard.locks[key] = nil

    if not ok then
        Util.log(('%s failed: %s'):format(key, result))

        return Util.fail('internal_error')
    end

    return result
end

function Guard.register(name, handler, options)
    options = options or {}
    Guard.callbacks[name] = options

    lib.callback.register(name, function(source, ...)
        if not Registry.ready then
            return Util.fail('server_not_ready')
        end

        local args = table.pack(...)
        local first, caller, level = 1, source, nil

        if options.level then
            level = Guard.level(source)

            if not Guard.allows(level, options.level) then
                return Util.fail('not_admin')
            end

            if not Guard.rate(source, '*panel', Config.admin.burst, 1000) then
                return Util.fail('slow_down')
            end
        end

        if not Guard.rate(source, name, options.rate or Config.admin.rate.read, options.window or 1000) then
            return Util.fail('slow_down')
        end

        if options.level then
            if not Guard.check(source, args[1]) then
                return Util.fail('bad_token')
            end

            first = 2
            caller = Guard.actor(source)

            if not caller then
                return Util.fail('not_ready')
            end

            caller.level = level
        end

        local ok, result = pcall(handler, caller, table.unpack(args, first, args.n))

        if not ok then
            Util.log(('%s failed: %s'):format(name, result))

            return Util.fail('internal_error')
        end

        if type(result) ~= 'table' then
            return Util.fail('internal_error')
        end

        return result
    end)
end

function Guard.stringArg(value, maxLength)
    return type(value) == 'string' and #value <= (maxLength or 64) and value or nil
end

function Guard.idArg(value)
    return Util.integer(tonumber(value), 1, 2 ^ 31)
end

function Guard.tableArg(value)
    return type(value) == 'table' and value or nil
end

return Guard
