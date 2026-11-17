local Config = require 'config'
local Integrations = require 'integrations'
local Prompt = require 'client.prompt'
local PlacementCamera = require 'client.placement'

local TARGET = 'ox_target'

local function guarded(options)
    for _, option in ipairs(options) do
        local original = option.canInteract

        option.canInteract = function(...)
            if PlacementCamera.busy() then return false end

            return original == nil or original(...)
        end
    end

    return options
end

function Integrations.targetAvailable()
    if Config.devices.interaction.useTarget == false then return false end

    return GetResourceState(TARGET) == 'started'
end

function Integrations.addEntityTarget(entity, options)
    if not Integrations.targetAvailable() then return false end

    exports.ox_target:addLocalEntity(entity, guarded(options))

    return true
end

function Integrations.removeEntityTarget(entity, names)
    if GetResourceState(TARGET) ~= 'started' then return false end

    exports.ox_target:removeLocalEntity(entity, names)

    return true
end

local PROMPT_ID = 'device'

local function textPrompt()
    return Config.devices.interaction.prompt == 'ox'
end

local shownAs = nil

local function hideAs(text)
    if text then
        lib.hideTextUI()

        return
    end

    Prompt.hide(PROMPT_ID)
end

function Integrations.showPrompt(data)
    local text = textPrompt()

    if shownAs ~= nil and shownAs ~= text then
        hideAs(shownAs)
    end

    shownAs = text

    if text then
        lib.showTextUI(Prompt.text(data))

        return
    end

    Prompt.show(PROMPT_ID, data)
end

function Integrations.hidePrompt()
    local text = shownAs

    if text == nil then
        text = textPrompt()
    end

    shownAs = nil
    hideAs(text)
end
