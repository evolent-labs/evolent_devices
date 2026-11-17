local Config = require 'config'
local Bridge = require 'bridge'
local Prompt = require 'client.prompt'
local Marker = require 'client.marker'

local Client = { kinds = nil }

function Client.call(name, ...)
    local result = lib.callback.await(name, false, ...)

    if type(result) ~= 'table' then
        return { ok = false, reason = 'no_response' }
    end

    return result
end

function Client.reasonText(reason)
    local key = 'reason_' .. tostring(reason)

    if lib.getLocales()[key] then
        return locale(key)
    end

    return locale('reason_generic', tostring(reason))
end

function Client.notify(text, kind)
    Bridge.notify(text, kind or 'inform')
end

Prompt.send = function(message)
    local Nui = require 'client.nui'

    Nui.send(message)
end

Marker.setup(Config.marker)

CreateThread(function()
    TriggerEvent('chat:addSuggestion', '/' .. Config.commands.admin, locale('command_admin_help'), {
        { name = 'id', help = locale('command_admin_id_help') },
    })
end)

return Client
