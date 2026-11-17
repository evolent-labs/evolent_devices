local Config = require 'config'
local Util = require 'shared.util'
local ConfigRules = require 'shared.config_rules'
local Marker = require 'client.marker'
local DeviceBrand = require 'client.brand'

local DeviceConfig = { applied = nil }

local POLL_MS, POLLS = 250, 20

local function markers()
    Marker.setup(Config.marker)

    if DeviceBrand then
        DeviceBrand.tintMarkers()
    end
end

DeviceConfig.HOOKS = {
    marker = markers,
}

local function clean(value)
    return type(value) == 'table' and value or {}
end

function DeviceConfig.apply(value)
    local diff = clean(value)

    if DeviceConfig.applied == nil and next(diff) == nil then
        DeviceConfig.applied = {}

        return {}
    end

    local changed = ConfigRules.apply(diff)
    local touched = {}

    DeviceConfig.applied = Util.copy(diff)

    for _, path in ipairs(changed) do
        local root = path:match('^([^%.]+)')

        if DeviceConfig.HOOKS[root] and not touched[root] then
            touched[root] = true

            local ok, failure = pcall(DeviceConfig.HOOKS[root])

            if not ok then
                print(('[evolent_devices] settings update failed: %s'):format(tostring(failure)))
            end
        end
    end

    return changed
end

AddStateBagChangeHandler(ConfigRules.KEY, 'global', function(_, _, value)
    DeviceConfig.apply(value)
end)

DeviceConfig.apply(GlobalState[ConfigRules.KEY])

CreateThread(function()
    for _ = 1, POLLS do
        Wait(POLL_MS)

        local value = clean(GlobalState[ConfigRules.KEY])

        if not Util.same(value, DeviceConfig.applied) then
            DeviceConfig.apply(value)
        end
    end
end)

return DeviceConfig
