local Config = require 'config'
local Util = require 'shared.util'
local ScreenRules = require 'shared.screen'
local AppRules = require 'shared.apps'

local OsRules = {}

OsRules.APPS = { 'notes', 'files', 'photos', 'store', 'settings' }
OsRules.TABLET_APPS = { 'store', 'settings' }
OsRules.FIXED = { store = true, settings = true, files = true, photos = true }
OsRules.KINDS = { laptop = true, pc = true }
OsRules.QUIET_MAX = 32
OsRules.PREFS = {
    volume = 100,
    clock24 = true,
    dnd = false,
    sound = true,
    bright = 100,
    sleep = 0,
    lock = 0,
    seconds = false,
    dateFormat = 'dm',
    reduceMotion = false,
    gamePopup = true,
    gameSound = true,
}
OsRules.PREF_FLAGS = { 'clock24', 'dnd', 'sound', 'seconds', 'reduceMotion', 'gamePopup', 'gameSound' }
OsRules.PREF_RANGES = { volume = { 0, 100 }, bright = { 30, 100 } }
OsRules.PREF_CHOICES = {
    sleep = { 0, 1, 2, 5, 10 },
    lock = { 0, 1, 2, 5, 10, 30 },
    dateFormat = { 'dm', 'md' },
}

local function limits(name)
    return Config.os[name]
end

function OsRules.kind(kind)
    return OsRules.KINDS[kind] == true
end

function OsRules.hasOs(kind)
    return OsRules.kind(kind) or kind == 'tablet'
end

function OsRules.apps(kind)
    if not OsRules.hasOs(kind) then
        return {}
    end

    local list = {}

    for _, id in ipairs(kind == 'tablet' and OsRules.TABLET_APPS or OsRules.APPS) do
        if Config.os.apps[id] == true then
            list[#list + 1] = id
        end
    end

    return list
end

function OsRules.enabled(id)
    return Config.os.apps[id] == true
end

function OsRules.password(value)
    local rules = limits('password')

    if type(value) ~= 'string' or #value > rules.max * 4 then return nil end

    local length = utf8.len(value)

    if not length or length < rules.min or length > rules.max then return nil end
    if value:find('[%z\1-\31\127]') or value:find('\194[\128-\159]') then return nil end

    return value
end

function OsRules.blocked(entry, now)
    if type(entry) ~= 'table' or not entry.untilMs or now >= entry.untilMs then return nil end

    return math.max(1, math.ceil((entry.untilMs - now) / 1000))
end

function OsRules.missed(entry, now)
    local rules = limits('password')
    local count = type(entry) == 'table' and not entry.untilMs and entry.count or 0

    count = count + 1

    if count >= rules.tries then
        return { count = 0, untilMs = now + rules.waitSeconds * 1000 }, 0
    end

    return { count = count }, rules.tries - count
end

function OsRules.body(value, limit)
    if type(value) ~= 'string' or not utf8.len(value) then return nil end

    local text = value:gsub('\r\n', '\n'):gsub('\r', '\n'):gsub('\t', '    '):gsub('[%z\1-\9\11-\31\127]', '')

    if Util.textLength(text) > limit then return nil end

    return text
end

function OsRules.note(value)
    local rules = limits('notes')

    if type(value) ~= 'table' then
        return nil, 'invalid_note'
    end

    local title = value.title == nil and '' or Util.cleanText(value.title, rules.title)

    if not title then
        return nil, 'note_title_long'
    end

    local body = value.body == nil and '' or OsRules.body(value.body, rules.body)

    if not body then
        return nil, 'note_too_long'
    end

    if value.id ~= nil and not Util.integer(value.id, 1, 2 ^ 31) then
        return nil, 'invalid_note'
    end

    return { id = value.id, title = title, body = body }
end

function OsRules.photo(value)
    local rules = limits('photos')

    if type(value) ~= 'table' then
        return nil, 'invalid_photo'
    end

    local url = ScreenRules.url(value.url)

    if not url then
        return nil, 'photo_link'
    end

    local name = value.name == nil and '' or Util.cleanText(value.name, rules.name)

    if not name then
        return nil, 'photo_name'
    end

    return { url = url, name = name }
end

OsRules.HOSTS_MAX = 20

function OsRules.hosts(value)
    if type(value) ~= 'table' then return nil end

    local list, seen = {}, {}

    for index, host in pairs(value) do
        if math.type(index) ~= 'integer' or type(host) ~= 'string' then return nil end

        host = host:lower()

        if not ScreenRules.publicHost(host) then return nil end

        if not seen[host] then
            seen[host] = true
            list[#list + 1] = host
        end
    end

    if #list > OsRules.HOSTS_MAX then return nil end

    return list
end

function OsRules.linksOn()
    local rules = Config.os.photos

    return rules.links == true and type(rules.hosts) == 'table' and #rules.hosts > 0
end

function OsRules.linkAllowed(url)
    if not OsRules.linksOn() or not ScreenRules.url(url) then return false end

    local host = url:match('^https://([^/%?#:]+)'):lower()

    for _, entry in ipairs(Config.os.photos.hosts) do
        if type(entry) == 'string' then
            entry = entry:lower()

            if host == entry or host:sub(-(#entry + 1)) == '.' .. entry then return true end
        end
    end

    return false
end

function OsRules.library()
    local list = {}

    for index, entry in ipairs(Config.os.photos.library or {}) do
        local photo = type(entry) == 'table' and OsRules.photo(entry) or nil

        if photo then
            photo.id = 'l' .. index
            list[#list + 1] = photo
        end
    end

    return list
end

function OsRules.shownPhoto(url)
    if OsRules.linkAllowed(url) then return true end

    for _, photo in ipairs(OsRules.library()) do
        if photo.url == url then return true end
    end

    return false
end

function OsRules.prefs(value)
    local clean = Util.copy(OsRules.PREFS)

    clean.quiet = {}

    if type(value) ~= 'table' then
        return clean
    end

    for key, range in pairs(OsRules.PREF_RANGES) do
        local number = tonumber(value[key])

        if Util.isFinite(number) then
            clean[key] = math.floor(math.max(range[1], math.min(range[2], number)) + 0.5)
        end
    end

    for _, key in ipairs(OsRules.PREF_FLAGS) do
        if type(value[key]) == 'boolean' then
            clean[key] = value[key]
        end
    end

    for key, choices in pairs(OsRules.PREF_CHOICES) do
        if Util.contains(choices, value[key]) then
            clean[key] = value[key]
        end
    end

    if type(value.quiet) == 'table' then
        for _, id in ipairs(value.quiet) do
            if #clean.quiet >= OsRules.QUIET_MAX then break end

            if AppRules.isId(id) and not Util.contains(clean.quiet, id) then
                clean.quiet[#clean.quiet + 1] = id
            end
        end
    end

    return clean
end

return OsRules
