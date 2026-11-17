local Config = require 'config'
local Bridge = require 'bridge'
local DeviceRules = require 'shared.rules'
local LookRules = require 'shared.look'
local DeviceIdle = require 'client.idle'
local DeviceBrand = require 'client.brand'

local DeviceNeon = {}

local TICK_MS = 500
local TEXTURE = 'neon'
local STAMP = GetGameTimer()
local ALPHABET = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
local resource = GetCurrentResourceName()

local strips = {}
local faces = {}
local stopping = false

local function hexOf(rgb)
    return ('%02X%02X%02X'):format(rgb[1], rgb[2], rgb[3])
end

local function base64(bytes)
    local out = {}

    for index = 1, #bytes, 3 do
        local a, b, c = bytes:byte(index, index + 2)
        local word = (a << 16) | ((b or 0) << 8) | (c or 0)
        local used = c and 4 or b and 3 or 2

        for slot = 1, 4 do
            if slot <= used then
                local value = (word >> (6 * (4 - slot))) & 63
                out[#out + 1] = ALPHABET:sub(value + 1, value + 1)
            else
                out[#out + 1] = '='
            end
        end
    end

    return table.concat(out)
end

function DeviceNeon.bitmap(rgb, size)
    local stride = (size * 3 + 3) // 4 * 4
    local row = string.char(rgb[3], rgb[2], rgb[1]):rep(size) .. ('\0'):rep(stride - size * 3)
    local pixels = row:rep(size)

    return string.pack('<c2I4I2I2I4I4i4i4I2I2I4I4i4i4I4I4', 'BM', 54 + #pixels, 0, 0, 54, 40, size, size, 1, 24, 0, #pixels, 2835, 2835, 0, 0) .. pixels
end

function DeviceNeon.picture(rgb, size)
    local encoded = base64(DeviceNeon.bitmap(rgb, size)):gsub('%+', '%%2B')

    return 'data:image/bmp;base64,' .. encoded
end

local function faceFor(model, rgb, size)
    local hex = hexOf(rgb)
    local key = ('%s|%s|%d'):format(model, hex, size)
    local face = faces[key]

    if face == nil then
        face = false

        local name = ('evdev_neon_%s_%s_%d'):format(model, hex, STAMP)
        local dict = CreateRuntimeTxd(name)
        local texture = dict and dict ~= 0 and CreateRuntimeTextureFromImage(dict, TEXTURE, DeviceNeon.picture(rgb, size)) or nil

        if texture and texture ~= 0 and GetRuntimeTextureWidth(texture) == size and GetRuntimeTextureHeight(texture) == size then
            face = name
        else
            print(('[evolent_devices] neon strip of %s: the #%s texture could not be made'):format(model, hex))
        end

        faces[key] = face
    end

    return face or nil, hex
end

local function release(entry)
    if entry.bound then
        RemoveReplaceTexture(entry.model, entry.target)
    end

    entry.bound, entry.face, entry.hex, entry.entity = false, nil, nil, nil
end

local function bind(entry, face, hex, entity)
    if entry.bound and entry.face == face and entry.entity == entity then return end

    if entry.bound and entry.face ~= face then
        RemoveReplaceTexture(entry.model, entry.target)
    end

    if Config.debug and entry.face ~= face then
        print(('[evolent_devices] neon strip of %s: #%s from %s'):format(entry.model, hex, face))
    end

    AddReplaceTexture(entry.model, entry.target, face, TEXTURE)
    entry.bound, entry.face, entry.hex, entry.entity = true, face, hex, entity
end

function DeviceNeon.tick()
    local brand = DeviceBrand.light()

    for _, kind in ipairs(DeviceRules.kinds()) do
        local strip = LookRules.strip(kind)

        for _, model in ipairs(strip and Config.kinds[kind].variants or {}) do
            local record = DeviceIdle.nearest(model)
            local entry = strips[model]

            if record then
                if not entry or entry.target ~= strip.texture or entry.size ~= strip.size then
                    if entry then
                        release(entry)
                    end

                    entry = { model = model, target = strip.texture, size = strip.size, bound = false }
                    strips[model] = entry
                end

                local rgb = LookRules.neon(record, brand)
                local face, hex = nil, nil

                if rgb then
                    face, hex = faceFor(model, rgb, entry.size)
                end

                if face then
                    bind(entry, face, hex, record.entity)
                elseif entry.bound then
                    release(entry)
                end
            elseif entry then
                release(entry)
            end
        end
    end
end

local function clear()
    for _, entry in pairs(strips) do
        release(entry)
    end
end

Bridge.onLogout(clear)

CreateThread(function()
    while not stopping do
        Wait(TICK_MS)

        if stopping then return end

        local ok, failure = pcall(DeviceNeon.tick)

        if not ok then
            print(('[evolent_devices] neon strips failed: %s'):format(tostring(failure)))
        end
    end
end)

AddEventHandler('onResourceStop', function(name)
    if name ~= resource then return end

    stopping = true
    clear()
end)

return DeviceNeon
