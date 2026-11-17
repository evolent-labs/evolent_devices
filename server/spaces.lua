local Registry = require 'server.registry'
local People = require 'server.people'

local Spaces = { known = {} }

local BUCKET_EVERY, FULL_EVERY = 2, 10

function Spaces.ofDevice(device)
    if device.propertyId then
        return 'p' .. tostring(device.propertyId)
    end

    return 'b' .. tostring(device.bucket or 0)
end

local function spaceOf(source, subject)
    if subject and subject.propertyId then
        return 'p' .. tostring(subject.propertyId), subject.propertyId
    end

    return 'b' .. tostring(GetPlayerRoutingBucket(source) or 0), nil
end

function Spaces.of(source)
    return spaceOf(source, People.fresh(source))
end

function Spaces.recent(source)
    return spaceOf(source, People.subject(source))
end

function Spaces.last(source)
    return Spaces.known[source] or Spaces.recent(source)
end

function Spaces.describe(space)
    local kind, number = tostring(space):match('^([bp])(%d+)$')

    number = tonumber(number)

    if kind == 'p' then
        return { kind = 'home', number = number, text = locale('space_home', number) }
    end

    if number == 0 then
        return { kind = 'world', number = 0, text = locale('space_world') }
    end

    return { kind = 'bucket', number = number, text = locale('space_bucket', number or 0) }
end

function Spaces.refresh(source)
    local space = Spaces.recent(source)

    if Spaces.known[source] == space then return false end

    Spaces.known[source] = space
    TriggerClientEvent('evdev:client:space', source, space, Registry.ready and Registry.snapshot(space) or nil)

    return true
end

function Spaces.forget(source)
    Spaces.known[source] = nil
end

function Spaces.poll(cycle)
    if cycle % FULL_EVERY == 0 then
        for _, source in ipairs(People.online()) do
            Spaces.refresh(source)
        end

        return
    end

    if cycle % BUCKET_EVERY ~= 0 then return end

    for source, known in pairs(Spaces.known) do
        if known:sub(1, 1) == 'b' and known ~= 'b' .. tostring(GetPlayerRoutingBucket(source) or 0) then
            Spaces.refresh(source)
        end
    end
end

return Spaces
