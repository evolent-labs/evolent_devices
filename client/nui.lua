local Config = require 'config'
local Util = require 'shared.util'
local Client = require 'client.main'

local Nui = {
    visible = false,
    ready = false,
    view = nil,
    tabletToken = nil,
    adminToken = nil,
    key = Util.hex(32),
}

Nui.CALL_PATTERN = '^evdev:[%w:_]+$'
Nui.ADMIN_PREFIX = 'evdev:admin:'

local queue = {}

local function deliver(message)
    local stamped = {}

    for key, value in pairs(message) do
        stamped[key] = value
    end

    stamped.__h = Nui.key
    SendNUIMessage(stamped)
end

function Nui.send(message)
    if Nui.ready then
        deliver(message)

        return
    end

    if #queue >= 16 then
        table.remove(queue, 1)
    end

    queue[#queue + 1] = message
end

function Nui.initMessage()
    local DeviceBrand = require 'client.brand'

    return { type = 'init', locale = lib.getLocales(), command = Config.commands.admin, brand = DeviceBrand.current() }
end

function Nui.brand(view)
    local DeviceBrand = require 'client.brand'

    if not Nui.ready then return false end

    deliver({ type = 'brand', brand = view or DeviceBrand.current() })

    return true
end

function Nui.open(view, data)
    data = data or {}
    Nui.tabletToken = nil
    Nui.adminToken = view == 'admin' and type(data.token) == 'string' and data.token or nil

    if view == 'tablet' then
        local copy = {}

        for key, value in pairs(data) do
            copy[key] = value
        end

        copy.token = Util.hex(32)
        Nui.tabletToken = copy.token
        data = copy
    end

    Nui.visible, Nui.view = true, view
    SetNuiFocus(true, true)
    Nui.send({ type = 'open', view = view, data = data })
end

function Nui.close()
    if not Nui.visible then return end

    Nui.visible, Nui.view, Nui.tabletToken, Nui.adminToken = false, nil, nil, nil
    SetNuiFocus(false, false)
    Nui.send({ type = 'close' })
end

function Nui.adminOpen()
    return Nui.visible and Nui.view == 'admin'
end

function Nui.fromMain(data)
    return type(data) == 'table' and data.__os == nil and data.__device == nil
end

function Nui.tabletPost(data)
    return Nui.visible and Nui.view == 'tablet' and Nui.fromMain(data) and type(Nui.tabletToken) == 'string' and data.__t == Nui.tabletToken
end

function Nui.panelPost(data)
    return Nui.adminOpen() and Nui.fromMain(data) and type(Nui.adminToken) == 'string' and data.__t == Nui.adminToken
end

function Nui.forward(data)
    if type(data) ~= 'table' then
        return { ok = false, reason = 'unknown_action' }
    end

    local name = data.name

    if type(name) ~= 'string' or #name > 64 or not name:match(Nui.CALL_PATTERN) then
        return { ok = false, reason = 'unknown_action' }
    end

    if name:sub(1, #Nui.ADMIN_PREFIX) ~= Nui.ADMIN_PREFIX then
        return { ok = false, reason = 'unknown_action' }
    end

    if not Nui.adminOpen() or not Nui.fromMain(data) then
        return { ok = false, reason = 'panel_closed' }
    end

    local args = type(data.args) == 'table' and data.args or {}

    return Client.call(name, data.__t, table.unpack(args, 1, 8))
end

RegisterNUICallback('ready', function(data, respond)
    if not Nui.fromMain(data) then
        respond({ ok = false })

        return
    end

    Nui.ready = true
    deliver(Nui.initMessage())

    for _, message in ipairs(queue) do
        deliver(message)
    end

    queue = {}
    respond({ ok = true })
end)

RegisterNUICallback('close', function(data, respond)
    if not Nui.panelPost(data) then
        respond({ ok = false })

        return
    end

    local token = data.__t

    CreateThread(function() Client.call('evdev:admin:close', token) end)
    Nui.close()
    respond({ ok = true })
end)

RegisterNUICallback('call', function(data, respond)
    respond(Nui.forward(data))
end)

RegisterNUICallback('waypoint', function(data, respond)
    if not Nui.panelPost(data) then
        respond({ ok = false, reason = 'panel_closed' })

        return
    end

    local x, y = tonumber(data.x), tonumber(data.y)

    if not x or not y or x ~= x or y ~= y then
        respond({ ok = false, reason = 'invalid_position' })

        return
    end

    SetNewWaypoint(x + 0.0, y + 0.0)
    respond({ ok = true })
end)

RegisterNUICallback('places', function(data, respond)
    if not Nui.panelPost(data) or type(data.points) ~= 'table' then
        respond({ ok = false, reason = 'panel_closed' })

        return
    end

    local names = {}

    for index = 1, math.min(#data.points, 400) do
        local point = data.points[index]
        local x, y, z = type(point) == 'table' and tonumber(point.x), type(point) == 'table' and tonumber(point.y), type(point) == 'table' and tonumber(point.z)
        local name = ''

        if Util.isFinite(x) and Util.isFinite(y) and Util.isFinite(z) then
            local code = GetNameOfZone(x + 0.0, y + 0.0, z + 0.0)
            local label = type(code) == 'string' and code ~= '' and GetLabelText(code) or nil

            name = label and label ~= 'NULL' and label or code or ''
        end

        names[index] = name
    end

    respond({ ok = true, names = names })
end)

RegisterNUICallback('tablet', function(data, respond)
    local Tablet = require 'client.tablet'

    if not Nui.tabletPost(data) then
        respond({ ok = false, reason = 'tablet_closed' })

        return
    end

    data.__t = nil
    Tablet.nui(data, respond)
end)

RegisterNUICallback('placement', function(data, respond)
    local AdminPlacement = require 'client.placement_admin'

    if not Nui.panelPost(data) then
        respond({ ok = false, reason = 'panel_closed' })

        return
    end

    AdminPlacement.start(data, respond)
end)

return Nui
