local Config = require 'config'
local Util = require 'shared.util'
local ScreenRules = require 'shared.screen'
local BrandRules = require 'shared.brand'
local OsRules = require 'shared.os'
local Store = require 'server.store'
local Guard = require 'server.guard'
local Audit = require 'server.audit'
local Registry = require 'server.registry'
local Access = require 'server.access'
local Sessions = require 'server.sessions'
local AppHost = require 'server.hosting'

local DeviceOs = { passwords = {}, tries = {}, notes = {}, photos = {} }

local function rules(name)
    return Config.os[name]
end

local function isOwner(lock, device)
    return device.ownerCid ~= nil and device.ownerCid == lock.cid
end

local function maySetPassword(lock, device)
    return isOwner(lock, device) or device.kind == 'tablet'
end

function DeviceOs.mayManage(lock, device)
    if device.kind == 'tablet' or isOwner(lock, device) then return true end
    if lock.source == nil then return false end
    if Guard.level(lock.source) then return true end

    return Access.decideManage(lock.source, device).allowed == true
end

function DeviceOs.mayWall(lock, device)
    if not ScreenRules.takesWall(device.kind) or device.temporary then return false end

    return DeviceOs.mayManage(lock, device)
end

function DeviceOs.load()
    local ok, passwords = pcall(Store.loadPasswords)

    if not ok then
        Util.log('could not read the device passwords: ' .. tostring(passwords))
    end

    DeviceOs.passwords = ok and type(passwords) == 'table' and passwords or {}
    DeviceOs.tries, DeviceOs.notes, DeviceOs.photos = {}, {}, {}
end

function DeviceOs.hasPassword(id)
    return DeviceOs.passwords[id] ~= nil
end

function DeviceOs.verify(password, hash)
    local ok, result = pcall(VerifyPasswordHash, password, hash)

    return ok and (result == true or result == 1)
end

local function forgetTries(id)
    local prefix = tostring(id) .. ':'

    for key in pairs(DeviceOs.tries) do
        if key:sub(1, #prefix) == prefix then
            DeviceOs.tries[key] = nil
        end
    end
end

function DeviceOs.setPassword(id, password, actor)
    local hash = GetPasswordHash(password)

    if type(hash) ~= 'string' or #hash < 20 or hash == password then
        error('the server gave no password hash')
    end

    Store.savePassword(id, hash, actor and actor.cid or nil)
    DeviceOs.passwords[id] = hash
    forgetTries(id)
    Audit.write(actor, 'password', id, { set = true })
end

function DeviceOs.clearPassword(id, actor)
    local Tablets = require 'server.tablet'

    Store.clearPassword(id)
    DeviceOs.passwords[id] = nil
    forgetTries(id)

    local lock = Sessions.locks[id]

    if lock then
        lock.passwordLocked = false
    end

    local device = Registry.device(id)
    local holder = device and device.kind == 'tablet' and device.serial and Tablets.holderOf(device.serial)

    if holder then
        Tablets.open[holder].passwordLocked = false
    end

    Audit.write(actor, 'password', id, { cleared = true })
end

function DeviceOs.info(lock, device)
    local owner = isOwner(lock, device)
    local keeps = not device.temporary

    return {
        apps = AppHost.lentApp(lock) and {} or OsRules.apps(device.kind),
        password = DeviceOs.hasPassword(device.id),
        owner = owner,
        canPassword = maySetPassword(lock, device) and keeps,
        canWall = DeviceOs.mayWall(lock, device),
        canManage = DeviceOs.mayManage(lock, device),
        keeps = keeps,
        version = GetResourceMetadata(GetCurrentResourceName(), 'version', 0),
        serial = device.serial,
        ownerName = device.ownerName,
        limits = {
            notes = rules('notes').max,
            title = rules('notes').title,
            body = rules('notes').body,
            trash = rules('notes').trash,
            photos = rules('photos').max,
            photoName = rules('photos').name,
            links = OsRules.linksOn(),
            passwordMin = rules('password').min,
            passwordMax = rules('password').max,
        },
    }
end

local function session(source, token, whileLocked)
    local Tablets = require 'server.tablet'

    local lock, device = Tablets.owned(source, token)

    if not lock then
        lock = Sessions.owned(source, token)

        if not lock then
            return nil, nil, Util.fail('device_closed')
        end

        device = Registry.device(lock.id)
    end

    if not device or not OsRules.hasOs(device.kind) then
        return nil, nil, Util.fail('no_device')
    end

    if lock.passwordLocked and not whileLocked then
        return nil, nil, Util.fail('device_locked')
    end

    return lock, device
end

local SINGLE_READS = { files = { notes = true, photos = true } }

local function inScope(lock, app)
    local only = lock.only

    if not app or not only or only == app then return true end

    return SINGLE_READS[only] ~= nil and SINGLE_READS[only][app] == true
end

local function register(name, handler, options)
    Guard.register('evdev:os:' .. name, function(source, token, ...)
        local lock, device, failure = session(source, token, options.locked)

        if not lock then
            return failure
        end

        if options.app and not Util.contains(OsRules.apps(device.kind), options.app) then
            return Util.fail('app_off')
        end

        if not inScope(lock, options.app) then
            return Util.fail('single_app')
        end

        if options.keeps and device.temporary then
            return Util.fail('device_keeps_nothing')
        end

        return handler(source, lock, device, ...)
    end, { rate = options.rate, window = options.window })
end

DeviceOs.register = register

local function noteView(note)
    return {
        id = note.id,
        title = note.title,
        body = note.body,
        author = note.author,
        at = note.at,
        deletedAt = note.deletedAt,
    }
end

local function notesOf(device)
    local list = DeviceOs.notes[device.id]

    if not list then
        list = Store.listNotes(device.id)
        DeviceOs.notes[device.id] = list
    end

    return list
end

local function notesView(list)
    local notes, trash = {}, {}

    for _, note in ipairs(list) do
        if note.deletedAt then
            trash[#trash + 1] = noteView(note)
        else
            notes[#notes + 1] = noteView(note)
        end
    end

    table.sort(trash, function(a, b) return a.deletedAt > b.deletedAt end)

    return { notes = notes, trash = trash }
end

local function findNote(list, id)
    for index, note in ipairs(list) do
        if note.id == id then
            return index, note
        end
    end

    return nil
end

local function liveCount(list)
    local count = 0

    for _, note in ipairs(list) do
        if not note.deletedAt then
            count = count + 1
        end
    end

    return count
end

local function trimTrash(device, list)
    local trash = {}

    for _, note in ipairs(list) do
        if note.deletedAt then
            trash[#trash + 1] = note
        end
    end

    table.sort(trash, function(a, b) return a.deletedAt > b.deletedAt end)

    for index = rules('notes').trash + 1, #trash do
        local oldest = trash[index]

        Store.deleteNote(device.id, oldest.id)

        local at = findNote(list, oldest.id)

        if at then
            table.remove(list, at)
        end
    end
end

local function bringForward(list, index)
    local note = table.remove(list, index)

    table.insert(list, 1, note)

    return note
end

register('notes', function(_, _, device)
    return Util.ok(notesView(notesOf(device)))
end, { app = 'notes', keeps = true, rate = 2 })

register('note:save', function(_, lock, device, value)
    local note, reason = OsRules.note(value)

    if not note then
        return Util.fail(reason)
    end

    local list = notesOf(device)

    if note.id then
        local index, entry = findNote(list, note.id)

        if not entry or entry.deletedAt then
            return Util.fail('unknown_note')
        end

        Store.updateNote(device.id, entry.id, note, lock.name)
        entry.title, entry.body, entry.author, entry.at = note.title, note.body, lock.name, os.time()

        return Util.ok({ note = noteView(bringForward(list, index)) })
    end

    if liveCount(list) >= rules('notes').max then
        return Util.fail('notes_full', { max = rules('notes').max })
    end

    local id = math.tointeger(tonumber(Store.insertNote(device.id, note, lock.name)))

    if not id then
        return Util.fail('internal_error')
    end

    local entry = { id = id, title = note.title, body = note.body, author = lock.name, at = os.time() }

    table.insert(list, 1, entry)

    return Util.ok({ note = noteView(entry) })
end, { app = 'notes', keeps = true, rate = 4 })

register('note:delete', function(_, lock, device, id)
    if not DeviceOs.mayManage(lock, device) then
        return Util.fail('device_manage_only')
    end

    local list = notesOf(device)
    local _, entry = findNote(list, Guard.idArg(id))

    if not entry or entry.deletedAt then
        return Util.fail('unknown_note')
    end

    Store.trashNote(device.id, entry.id)
    entry.deletedAt = os.time()
    trimTrash(device, list)

    return Util.ok(notesView(list))
end, { app = 'notes', keeps = true, rate = 2 })

register('note:restore', function(_, _, device, id)
    local list = notesOf(device)
    local index, entry = findNote(list, Guard.idArg(id))

    if not entry or not entry.deletedAt then
        return Util.fail('unknown_note')
    end

    if liveCount(list) >= rules('notes').max then
        return Util.fail('notes_full', { max = rules('notes').max })
    end

    Store.restoreNote(device.id, entry.id)
    entry.deletedAt = nil
    bringForward(list, index)

    return Util.ok(notesView(list))
end, { app = 'notes', keeps = true, rate = 2 })

register('note:purge', function(_, lock, device, id)
    if not DeviceOs.mayManage(lock, device) then
        return Util.fail('device_manage_only')
    end

    local list = notesOf(device)
    local index, entry = findNote(list, Guard.idArg(id))

    if not entry or not entry.deletedAt then
        return Util.fail('unknown_note')
    end

    Store.deleteNote(device.id, entry.id)
    table.remove(list, index)

    return Util.ok(notesView(list))
end, { app = 'notes', keeps = true, rate = 2 })

local function photosOf(device)
    if device.temporary then
        return {}
    end

    local list = DeviceOs.photos[device.id]

    if not list then
        list = Store.listPhotos(device.id)
        DeviceOs.photos[device.id] = list
    end

    return list
end

local function shownPhotos(device)
    local list = {}

    for _, photo in ipairs(photosOf(device)) do
        if OsRules.linkAllowed(photo.url) then
            list[#list + 1] = photo
        end
    end

    return list
end

local function photosView(device)
    local own = {}

    for index, photo in ipairs(shownPhotos(device)) do
        own[index] = { id = photo.id, url = photo.url, name = photo.name, author = photo.author, at = photo.at }
    end

    return { photos = own, library = OsRules.library() }
end

register('photos', function(_, _, device)
    return Util.ok(photosView(device))
end, { app = 'photos', rate = 2 })

register('photo:add', function(_, lock, device, value)
    if not OsRules.linksOn() then
        return Util.fail('photo_links_off')
    end

    local photo, reason = OsRules.photo(value)

    if not photo then
        return Util.fail(reason)
    end

    if not OsRules.linkAllowed(photo.url) then
        return Util.fail('photo_host')
    end

    local list = photosOf(device)

    if #shownPhotos(device) >= rules('photos').max then
        return Util.fail('photos_full', { max = rules('photos').max })
    end

    local id = math.tointeger(tonumber(Store.insertPhoto(device.id, photo, lock.name)))

    if not id then
        return Util.fail('internal_error')
    end

    table.insert(list, 1, { id = id, url = photo.url, name = photo.name, author = lock.name, at = os.time() })

    return Util.ok(photosView(device))
end, { app = 'photos', keeps = true, rate = 1, window = 1500 })

register('photo:remove', function(_, lock, device, id)
    if not DeviceOs.mayManage(lock, device) then
        return Util.fail('device_manage_only')
    end

    local list = photosOf(device)
    local wanted = Guard.idArg(id)

    for index, photo in ipairs(list) do
        if photo.id == wanted and OsRules.linkAllowed(photo.url) then
            Store.deletePhoto(device.id, photo.id)
            table.remove(list, index)

            return Util.ok(photosView(device))
        end
    end

    return Util.fail('unknown_photo')
end, { app = 'photos', keeps = true, rate = 2 })

local function tryPassword(lock, device, password)
    local key = device.id .. ':' .. lock.cid
    local now = GetGameTimer()
    local wait = OsRules.blocked(DeviceOs.tries[key], now)

    if wait then
        return Util.fail('password_wait', { seconds = wait })
    end

    local hash = DeviceOs.passwords[device.id]
    local clean = OsRules.password(password)

    if hash and clean and DeviceOs.verify(clean, hash) then
        DeviceOs.tries[key] = nil

        return nil
    end

    local entry, left = OsRules.missed(DeviceOs.tries[key], now)

    DeviceOs.tries[key] = entry

    if left == 0 then
        return Util.fail('password_wait', { seconds = rules('password').waitSeconds })
    end

    return Util.fail('password_wrong', { left = left })
end

local function unlocked(lock, device)
    local Tablets = require 'server.tablet'
    local Notices = require 'server.notices'

    lock.passwordLocked = false

    return Util.ok({ notices = device.kind == 'tablet' and Tablets.notices(lock) or Notices.openFor(lock, device) })
end

register('unlock', function(_, lock, device, password)
    if not lock.passwordLocked or not DeviceOs.hasPassword(device.id) then
        return unlocked(lock, device)
    end

    local failure = tryPassword(lock, device, password)

    if failure then
        return failure
    end

    return unlocked(lock, device)
end, { locked = true, rate = 2 })

register('lock', function(_, lock, device)
    lock.passwordLocked = DeviceOs.hasPassword(device.id)

    return Util.ok({ password = lock.passwordLocked })
end, { locked = true, rate = 2 })

register('wall', function(source, lock, device, value)
    local Devices = require 'server.devices'

    if not DeviceOs.mayWall(lock, device) then
        return Util.fail('wall_owner_only')
    end

    local wall = (value == '' or value == false) and '' or BrandRules.wallpaperId(value)

    if not wall then
        return Util.fail('screen_wall')
    end

    local before = type(device.screen) == 'table' and device.screen or {}

    if (before.wall or '') == wall then
        return Util.ok({ wall = wall })
    end

    local screen = Util.copy(before)

    screen.wall = wall ~= '' and wall or nil

    local actor = Guard.actor(source)

    if not Devices.commit(actor, device, { screen = ScreenRules.compact(screen) or false }, device.version) then
        return Util.fail('device_changed')
    end

    Audit.write(actor, 'screen', device.id, { changed = { 'wall' } })

    return Util.ok({ wall = wall })
end, { app = 'settings', keeps = true, rate = 2 })

local function claimTablet(lock, device, actor)
    local Devices = require 'server.devices'

    if device.kind ~= 'tablet' or isOwner(lock, device) then return end

    if Devices.commit(actor, device, { ownerCid = lock.cid, ownerName = Util.cleanText(lock.name or '', 64) or lock.cid }, device.version) then
        Audit.write(actor, 'owner', device.id, { to = lock.cid, by = 'password' })
    end
end

register('password', function(source, lock, device, action, data)
    if not maySetPassword(lock, device) then
        return Util.fail('password_owner_only')
    end

    if action ~= 'set' and action ~= 'clear' then
        return Util.fail('invalid_password')
    end

    local fields = type(data) == 'table' and data or {}
    local clean = nil

    if action == 'set' then
        clean = OsRules.password(fields.password)

        if not clean then
            return Util.fail('invalid_password')
        end
    end

    if DeviceOs.hasPassword(device.id) then
        local failure = tryPassword(lock, device, fields.current)

        if failure then
            return failure
        end
    end

    local actor = Guard.actor(source)

    if action == 'clear' then
        if DeviceOs.hasPassword(device.id) then
            DeviceOs.clearPassword(device.id, actor)
        end

        return Util.ok({ password = false })
    end

    DeviceOs.setPassword(device.id, clean, actor)
    claimTablet(lock, device, actor)

    return Util.ok({ password = true, owner = isOwner(lock, device) })
end, { app = 'settings', keeps = true, rate = 1, window = 2000 })

register('forgot', function(source, lock, device)
    local Tablets = require 'server.tablet'
    local Notices = require 'server.notices'

    if not isOwner(lock, device) then
        return Util.fail('password_owner_only')
    end

    if DeviceOs.hasPassword(device.id) then
        DeviceOs.clearPassword(device.id, Guard.actor(source))
    end

    lock.passwordLocked = false

    local answer = { password = false }

    answer.notices = device.kind == 'tablet' and Tablets.notices(lock) or Notices.openFor(lock, device)

    return Util.ok(answer)
end, { locked = true, keeps = true, rate = 1, window = 2000 })

Sessions.on('open', function(lock, device, answer)
    if not OsRules.kind(device.kind) then return nil end

    lock.passwordLocked = DeviceOs.hasPassword(device.id)
    answer.os = DeviceOs.info(lock, device)

    return nil
end)

Sessions.on('close', function(lock)
    DeviceOs.notes[lock.id] = nil
    DeviceOs.photos[lock.id] = nil

    return nil
end)

return DeviceOs
