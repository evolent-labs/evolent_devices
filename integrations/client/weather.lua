local Integrations = require 'integrations'

function Integrations.weatherPause(hold)
    TriggerEvent(hold and 'qb-weathersync:client:DisableSync' or 'qb-weathersync:client:EnableSync')
    TriggerEvent('cd_easytime:PauseSync', hold == true)
end
