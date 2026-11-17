local Config = require 'config'
local ScreenRules = require 'shared.screen'
local BrandRules = require 'shared.brand'
local LookRules = require 'shared.look'
local Marker = require 'client.marker'
local Nui = require 'client.nui'
local DeviceScreens = require 'client.screens'

local DeviceBrand = { applied = nil, short = nil, seen = nil }

local POLL_MS, POLLS = 250, 20
local stockName = nil

local function idleStamp(idle)
    if type(idle) ~= 'table' then
        return tostring(idle)
    end

    local parts = {}

    for index, kind in ipairs(BrandRules.IDLE_KINDS) do
        parts[index] = tostring(idle[kind])
    end

    return table.concat(parts, ',')
end

local function stamp(value)
    if type(value) ~= 'table' then
        return tostring(value)
    end

    return table.concat({ tostring(value.accent), tostring(value.name), tostring(value.wallpaper), type(value.logo) == 'string' and #value.logo or tostring(value.logo), idleStamp(value.idle) }, '')
end

local function wallStamp(list)
    if type(list) ~= 'table' then
        return tostring(list)
    end

    local parts = {}

    for index, entry in ipairs(list) do
        parts[index] = type(entry) == 'table' and table.concat({ tostring(entry.id), tostring(entry.name), tostring(entry.file) }, '|') or '?'
    end

    return table.concat(parts, ',')
end

local function markerColour()
    local colour = type(Config.marker) == 'table' and Config.marker.color or nil

    return type(colour) == 'string' and colour ~= '' and colour or nil
end

function DeviceBrand.tintMarkers(view)
    if markerColour() then return false end

    return Marker.setAccent((view or BrandRules.view()).accent)
end

function DeviceBrand.rename(view)
    local name = (view or BrandRules.view()).name
    local strings = lib.getLocales()

    stockName = stockName or strings.os_name
    strings.os_name = name ~= '' and name or stockName
end

function DeviceBrand.apply(value, quiet)
    local view = BrandRules.view(value == nil and false or value)

    DeviceBrand.applied = view
    DeviceBrand.short = { accent = view.accent, name = view.name, idle = view.idle }
    DeviceBrand.seen = stamp(value)
    DeviceBrand.rename(view)
    DeviceBrand.tintMarkers(view)

    if quiet then
        return view
    end

    for _, step in ipairs({
        function() Nui.brand(view) end,
        function() DeviceScreens.brand(view) end,
    }) do
        local ok, failure = pcall(step)

        if not ok then
            print(('[evolent_devices] brand update failed: %s'):format(tostring(failure)))
        end
    end

    return view
end

function DeviceBrand.current()
    return DeviceBrand.applied or BrandRules.view()
end

function DeviceBrand.light()
    return DeviceBrand.short or BrandRules.light()
end

function DeviceBrand.lightFor(record)
    local light = DeviceBrand.light()
    local accent = LookRules.accent(record, light)

    if accent == light.accent then
        return light
    end

    return { accent = accent, name = light.name, idle = light.idle }
end

function DeviceBrand.wallOf(record)
    if type(record) ~= 'table' or not ScreenRules.takesWall(record.kind) then return '' end

    return ScreenRules.wallOf(record.kind, type(record.screen) == 'table' and record.screen.wall or nil)
end

function DeviceBrand.viewFor(record, view)
    view = view or DeviceBrand.current()

    local accent = LookRules.accent(record, view)
    local wall = DeviceBrand.wallOf(record)

    if accent == view.accent and wall == '' then
        return view
    end

    local copy = {}

    for key, value in pairs(view) do
        copy[key] = value
    end

    copy.accent = accent
    copy.wall = wall ~= '' and wall or nil

    return copy
end

function DeviceBrand.useWalls(list)
    DeviceBrand.wallsSeen = wallStamp(list)
    BrandRules.useWallpapers(list)
end

AddStateBagChangeHandler(BrandRules.KEY, 'global', function(_, _, value)
    DeviceBrand.apply(value)
end)

AddStateBagChangeHandler(BrandRules.WALLS_KEY, 'global', function(_, _, value)
    DeviceBrand.useWalls(value)
    DeviceBrand.apply(GlobalState[BrandRules.KEY])
end)

DeviceBrand.useWalls(GlobalState[BrandRules.WALLS_KEY])
DeviceBrand.apply(GlobalState[BrandRules.KEY], true)

CreateThread(function()
    for _ = 1, POLLS do
        Wait(POLL_MS)

        local value = GlobalState[BrandRules.KEY]
        local walls = GlobalState[BrandRules.WALLS_KEY]

        if wallStamp(walls) ~= DeviceBrand.wallsSeen then
            DeviceBrand.useWalls(walls)
            DeviceBrand.apply(value)
        elseif stamp(value) ~= DeviceBrand.seen then
            DeviceBrand.apply(value)
        end
    end
end)

AddEventHandler('ox_lib:setLocale', function()
    stockName = nil
    DeviceBrand.rename(DeviceBrand.applied)
end)

return DeviceBrand
