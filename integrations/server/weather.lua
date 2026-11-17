local Integrations = require 'integrations'

function Integrations.weatherHold(source, weather)
    if not GetPlayerName(source) then return end

    local state = Player(source).state

    if type(weather) == 'string' then
        state:set('playerWeather', weather, true)
    end

    state:set('syncWeather', false, true)
end

function Integrations.weatherRelease(source)
    if not GetPlayerName(source) then return end

    local state = Player(source).state

    state:set('playerWeather', nil, true)
    state:set('syncWeather', true, true)
end
