local Integrations = require 'integrations'

local hidden = false

function Integrations.hud(hide)
    hide = hide == true

    if hidden == hide then return end

    hidden = hide
    TriggerEvent('qbx_hud:client:setHidden', hide)
    TriggerEvent('evolent:client:hudHidden', hide)
end

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() and hidden then
        Integrations.hud(false)
    end
end)
