local OsApp = {}

local handlers = {}
local registered = {}

local function run(appId, name, data)
    if type(data) == 'table' then
        data.__os = nil
    end

    local ok, result = pcall(handlers[appId][name], data)

    if ok then return result end

    print(('[%s] %s: %s failed: %s'):format(GetCurrentResourceName(), appId, name, tostring(result)))

    return { ok = false, reason = 'app_error' }
end

local function listen(name)
    if registered[name] then return end

    registered[name] = true

    RegisterNUICallback(name, function(data, cb)
        for appId, list in pairs(handlers) do
            if list[name] and exports.evolent_devices:isAppPost(appId, data) then
                return cb(run(appId, name, data))
            end
        end

        cb({ ok = false })
    end)
end

AddEventHandler('evolent_devices:appPost', function(appId, name, data, replyId)
    local list = handlers[appId]

    if not list or not list[name] then return end

    exports.evolent_devices:answerAppPost(replyId, run(appId, name, data))
end)

function OsApp.handle(appId, name, fn)
    assert(type(appId) == 'string', 'OsApp.handle: appId must be a string')
    assert(type(name) == 'string', 'OsApp.handle: name must be a string')
    assert(type(fn) == 'function', 'OsApp.handle: fn must be a function')

    handlers[appId] = handlers[appId] or {}
    handlers[appId][name] = fn

    listen(name)
end

return OsApp
