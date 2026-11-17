local Util = require 'shared.util'

local Store = {}

Store.schema = 'sql/install.sql'

local DEVICE_COLUMNS = [[id, kind, variant, label, state, x, y, z, heading, surface, bucket, property_id, origin, serial,
    owner_cid, owner_name, enabled, access, manage, apps, page, legacy_key, created_by, updated_by, version,
    UNIX_TIMESTAMP(created_at) AS created_s, UNIX_TIMESTAMP(updated_at) AS updated_s,
    UNIX_TIMESTAMP(last_used_at) AS last_used_s, UNIX_TIMESTAMP(removed_at) AS removed_s,
    (SELECT s.settings FROM evdev_device_screens s WHERE s.device_id = evdev_devices.id) AS screen]]

local FIELDS = {
    kind = { column = 'kind' },
    variant = { column = 'variant', null = true },
    label = { column = 'label' },
    state = { column = 'state' },
    x = { column = 'x', null = true },
    y = { column = 'y', null = true },
    z = { column = 'z', null = true },
    heading = { column = 'heading', null = true },
    surface = { column = 'surface', flag = true },
    bucket = { column = 'bucket' },
    propertyId = { column = 'property_id', null = true },
    serial = { column = 'serial', null = true },
    ownerCid = { column = 'owner_cid', null = true },
    ownerName = { column = 'owner_name', null = true },
    enabled = { column = 'enabled', flag = true },
    access = { column = 'access', json = true },
    manage = { column = 'manage', json = true },
    apps = { column = 'apps', json = true },
    page = { column = 'page', json = true, null = true },
    updatedBy = { column = 'updated_by', null = true },
    lastUsedAt = { column = 'last_used_at', time = true, null = true },
    removedAt = { column = 'removed_at', time = true, null = true },
    screen = { own = true },
}

local function decode(text, fallback)
    if type(text) ~= 'string' or text == '' then
        return Util.copy(fallback)
    end

    local ok, value = pcall(json.decode, text)

    if ok and type(value) == 'table' then
        return value
    end

    return Util.copy(fallback)
end

local function flag(value)
    return value == 1 or value == true
end

local function affected(result)
    assert(type(result) == 'number' and result >= 0, 'Database update did not return an affected-row count.')

    return result
end

local function splitStatements(sql)
    local statements = {}

    for statement in sql:gmatch('([^;]+);') do
        local trimmed = statement:gsub('^%s+', ''):gsub('%s+$', '')

        if trimmed ~= '' then
            statements[#statements + 1] = trimmed
        end
    end

    return statements
end

local function schema()
    local sql = LoadResourceFile(GetCurrentResourceName(), Store.schema)

    assert(sql, Store.schema .. ' is missing from the resource.')

    return sql
end

function Store.tables()
    local list = {}

    for name in schema():gmatch('CREATE TABLE IF NOT EXISTS `([%w_]+)`') do
        list[#list + 1] = name
    end

    return list
end

function Store.install()
    for _, statement in ipairs(splitStatements(schema())) do
        MySQL.query.await(statement)
    end
end

function Store.missing()
    local rows = MySQL.query.await(
        'SELECT table_name AS name FROM information_schema.tables WHERE table_schema = DATABASE()'
    ) or {}
    local present = {}

    for _, row in ipairs(rows) do
        present[row.name] = true
    end

    local missing = {}

    for _, name in ipairs(Store.tables()) do
        if not present[name] then
            missing[#missing + 1] = name
        end
    end

    return missing
end

local function toDevice(row)
    return {
        id = row.id,
        kind = row.kind,
        variant = row.variant,
        label = row.label or '',
        state = row.state,
        x = row.x,
        y = row.y,
        z = row.z,
        heading = row.heading,
        surface = flag(row.surface),
        bucket = tonumber(row.bucket) or 0,
        propertyId = row.property_id,
        origin = row.origin,
        serial = row.serial,
        ownerCid = row.owner_cid,
        ownerName = row.owner_name,
        enabled = flag(row.enabled),
        access = decode(row.access, { mode = 'rules', rules = {} }),
        manage = decode(row.manage, { mode = 'owner', rules = {} }),
        apps = decode(row.apps, { order = {}, entries = {} }),
        page = decode(row.page, nil),
        screen = decode(row.screen, nil),
        legacyKey = row.legacy_key,
        createdBy = row.created_by,
        updatedBy = row.updated_by,
        createdAt = tonumber(row.created_s),
        updatedAt = tonumber(row.updated_s),
        lastUsedAt = tonumber(row.last_used_s),
        removedAt = tonumber(row.removed_s),
        version = tonumber(row.version) or 1,
    }
end

function Store.loadDevices()
    local rows = MySQL.query.await('SELECT ' .. DEVICE_COLUMNS .. ' FROM evdev_devices ORDER BY id') or {}
    local list = {}

    for index, row in ipairs(rows) do
        list[index] = toDevice(row)
    end

    return list
end

function Store.loadDevice(id)
    local row = MySQL.single.await('SELECT ' .. DEVICE_COLUMNS .. ' FROM evdev_devices WHERE id = ?', { id })

    return row and toDevice(row) or nil
end

function Store.insertDevice(device)
    return MySQL.insert.await([[INSERT INTO evdev_devices (kind, variant, label, state, x, y, z, heading, surface, bucket,
        property_id, origin, serial, owner_cid, owner_name, enabled, access, manage, apps, page, legacy_key, created_by, updated_by)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)]], {
        device.kind,
        device.variant,
        device.label or '',
        device.state or 'placed',
        device.x,
        device.y,
        device.z,
        device.heading,
        device.surface == false and 0 or 1,
        device.bucket or 0,
        device.propertyId,
        device.origin,
        device.serial,
        device.ownerCid,
        device.ownerName,
        device.enabled == false and 0 or 1,
        json.encode(device.access),
        json.encode(device.manage),
        json.encode(device.apps),
        device.page and json.encode(device.page) or nil,
        device.legacyKey,
        device.createdBy,
        device.createdBy,
        })
end

function Store.saveScreen(id, settings)
    if type(settings) ~= 'table' or next(settings) == nil then
        return affected(MySQL.update.await('DELETE FROM evdev_device_screens WHERE device_id = ?', { id }))
    end

    return affected(MySQL.update.await('INSERT INTO evdev_device_screens (device_id, settings) VALUES (?, ?) ON DUPLICATE KEY UPDATE settings = VALUES(settings)', {
        id,
        json.encode(settings),
    }))
end

function Store.updateDevice(id, version, fields)
    local sets, values = {}, {}

    for _, name in ipairs(Util.keys(fields)) do
        local spec = FIELDS[name]

        assert(spec, 'unknown device field ' .. tostring(name))

        local value = fields[name]

        if spec.own then
        elseif value == false and spec.null and not spec.flag then
            sets[#sets + 1] = spec.column .. ' = NULL'
        elseif spec.time then
            sets[#sets + 1] = spec.column .. ' = FROM_UNIXTIME(?)'
            values[#values + 1] = value
        else
            sets[#sets + 1] = spec.column .. ' = ?'

            if spec.json then
                value = json.encode(value)
            elseif spec.flag then
                value = value and 1 or 0
            end

            values[#values + 1] = value
        end
    end

    sets[#sets + 1] = 'version = version + 1'
    values[#values + 1] = id
    values[#values + 1] = version

    local changed = affected(MySQL.update.await(
        ('UPDATE evdev_devices SET %s WHERE id = ? AND version = ?'):format(table.concat(sets, ', ')),
        values
    ))

    if changed == 1 and fields.screen ~= nil then
        Store.saveScreen(id, fields.screen)
    end

    return changed
end

function Store.touchUsed(id, at)
    return affected(MySQL.update.await('UPDATE evdev_devices SET last_used_at = FROM_UNIXTIME(?) WHERE id = ?', {
        at,
        id,
    }))
end

function Store.serialTaken(serial)
    local count = MySQL.scalar.await('SELECT (SELECT COUNT(*) FROM evdev_devices WHERE serial = ?) + (SELECT COUNT(*) FROM evdev_serials WHERE serial = ?)', { serial, serial })

    return (tonumber(count) or 0) > 0
end

function Store.noteSerial(serial, kind)
    return affected(MySQL.update.await('INSERT IGNORE INTO evdev_serials (serial, kind) VALUES (?, ?)', {
        serial,
        kind,
    }))
end

function Store.loadSerials()
    local rows = MySQL.query.await('SELECT serial, dead FROM evdev_serials') or {}
    local list = {}

    for index, row in ipairs(rows) do
        list[index] = { serial = row.serial, dead = flag(row.dead) }
    end

    return list
end

function Store.purgeRemoved(days)
    affected(MySQL.update.await([[INSERT INTO evdev_serials (serial, kind, dead) SELECT serial, kind, 1 FROM evdev_devices
        WHERE state = 'removed' AND serial IS NOT NULL AND removed_at < (NOW() - INTERVAL ? DAY) ON DUPLICATE KEY UPDATE dead = 1]], { days }))

    affected(MySQL.update.await([[DELETE s FROM evdev_device_screens s JOIN evdev_devices d ON d.id = s.device_id
        WHERE d.state = 'removed' AND d.removed_at < (NOW() - INTERVAL ? DAY)]], { days }))

    return affected(MySQL.update.await(
        "DELETE FROM evdev_devices WHERE state = 'removed' AND removed_at < (NOW() - INTERVAL ? DAY)",
        { days }
    ))
end

function Store.loadPasswords()
    local rows = MySQL.query.await('SELECT device_id, hash FROM evdev_device_pins') or {}
    local passwords = {}

    for _, row in ipairs(rows) do
        local id = math.tointeger(tonumber(row.device_id))

        if id and type(row.hash) == 'string' and row.hash ~= '' then
            passwords[id] = row.hash
        end
    end

    return passwords
end

function Store.savePassword(deviceId, hash, by)
    return affected(MySQL.update.await([[INSERT INTO evdev_device_pins (device_id, hash, set_by) VALUES (?, ?, ?)
        ON DUPLICATE KEY UPDATE hash = VALUES(hash), set_by = VALUES(set_by)]], { deviceId, hash, by }))
end

function Store.clearPassword(deviceId)
    return affected(MySQL.update.await('DELETE FROM evdev_device_pins WHERE device_id = ?', { deviceId }))
end

function Store.listNotes(deviceId)
    local rows = MySQL.query.await([[SELECT id, title, body, author, UNIX_TIMESTAMP(updated_at) AS updated_s,
        UNIX_TIMESTAMP(deleted_at) AS deleted_s FROM evdev_notes WHERE device_id = ? ORDER BY updated_at DESC, id DESC]], {
        deviceId,
    }) or {}

    local list = {}

    for index, row in ipairs(rows) do
        list[index] = {
            id = math.tointeger(tonumber(row.id)),
            title = row.title or '',
            body = row.body or '',
            author = row.author,
            at = tonumber(row.updated_s),
            deletedAt = tonumber(row.deleted_s),
        }
    end

    return list
end

function Store.insertNote(deviceId, note, author)
    return MySQL.insert.await('INSERT INTO evdev_notes (device_id, title, body, author) VALUES (?, ?, ?, ?)', {
        deviceId,
        note.title,
        note.body,
        author,
    })
end

function Store.updateNote(deviceId, id, note, author)
    return affected(MySQL.update.await([[UPDATE evdev_notes SET title = ?, body = ?, author = ?, updated_at = CURRENT_TIMESTAMP
        WHERE id = ? AND device_id = ? AND deleted_at IS NULL]], { note.title, note.body, author, id, deviceId }))
end

function Store.trashNote(deviceId, id)
    return affected(MySQL.update.await([[UPDATE evdev_notes SET deleted_at = CURRENT_TIMESTAMP, updated_at = updated_at
        WHERE id = ? AND device_id = ? AND deleted_at IS NULL]], { id, deviceId }))
end

function Store.restoreNote(deviceId, id)
    return affected(MySQL.update.await([[UPDATE evdev_notes SET deleted_at = NULL, updated_at = updated_at
        WHERE id = ? AND device_id = ? AND deleted_at IS NOT NULL]], { id, deviceId }))
end

function Store.deleteNote(deviceId, id)
    return affected(MySQL.update.await('DELETE FROM evdev_notes WHERE id = ? AND device_id = ? AND deleted_at IS NOT NULL', {
        id,
        deviceId,
    }))
end

function Store.listPhotos(deviceId)
    local rows = MySQL.query.await([[SELECT id, url, name, author, UNIX_TIMESTAMP(created_at) AS created_s FROM evdev_photos
        WHERE device_id = ? ORDER BY id DESC]], { deviceId }) or {}

    local list = {}

    for index, row in ipairs(rows) do
        list[index] = {
            id = math.tointeger(tonumber(row.id)),
            url = row.url,
            name = row.name or '',
            author = row.author,
            at = tonumber(row.created_s),
        }
    end

    return list
end

function Store.insertPhoto(deviceId, photo, author)
    return MySQL.insert.await('INSERT INTO evdev_photos (device_id, url, name, author) VALUES (?, ?, ?, ?)', {
        deviceId,
        photo.url,
        photo.name,
        author,
    })
end

function Store.deletePhoto(deviceId, id)
    return affected(MySQL.update.await('DELETE FROM evdev_photos WHERE id = ? AND device_id = ?', { id, deviceId }))
end

function Store.purgeOs(trashDays)
    affected(MySQL.update.await('DELETE FROM evdev_notes WHERE deleted_at IS NOT NULL AND deleted_at < (NOW() - INTERVAL ? DAY)', {
        trashDays,
    }))

    local orphans = 'DELETE t FROM %s t LEFT JOIN evdev_devices d ON d.id = t.device_id WHERE d.id IS NULL'

    for _, name in ipairs({ 'evdev_notes', 'evdev_photos', 'evdev_device_pins' }) do
        affected(MySQL.update.await(orphans:format(name)))
    end

    affected(MySQL.update.await([[DELETE a FROM evdev_device_apps a LEFT JOIN evdev_devices d
        ON a.device_key = CONVERT(CAST(d.id AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci OR a.device_key = d.serial
        WHERE d.id IS NULL AND a.device_key NOT LIKE 'cid:%']]))
end

function Store.loadInstalls()
    local rows = MySQL.query.await('SELECT device_key, app, installed FROM evdev_device_apps') or {}
    local installs = {}

    for _, row in ipairs(rows) do
        local own = installs[row.device_key] or {}

        own[row.app] = flag(row.installed)
        installs[row.device_key] = own
    end

    return installs
end

function Store.saveInstall(key, app, installed, by)
    return affected(MySQL.update.await([[INSERT INTO evdev_device_apps (device_key, app, installed, changed_by) VALUES (?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE installed = VALUES(installed), changed_by = VALUES(changed_by)]], { key, app, installed and 1 or 0, by }))
end

function Store.loadApps()
    local rows = MySQL.query.await([[SELECT id, resource, status, enabled, options, label, version,
        UNIX_TIMESTAMP(first_seen) AS first_s, UNIX_TIMESTAMP(last_seen) AS last_s FROM evdev_apps]]) or {}

    local list = {}

    for index, row in ipairs(rows) do
        list[index] = {
            id = row.id,
            resource = row.resource,
            status = row.status,
            enabled = flag(row.enabled),
            options = decode(row.options, {}),
            label = row.label,
            version = row.version,
            firstSeen = tonumber(row.first_s),
            lastSeen = tonumber(row.last_s),
        }
    end

    return list
end

function Store.insertApp(app)
    MySQL.query.await([[INSERT INTO evdev_apps (id, resource, status, enabled, options, label, version, last_seen)
        VALUES (?, ?, ?, ?, ?, ?, ?, NOW())]], {
        app.id,
        app.resource,
        app.status,
        app.enabled == false and 0 or 1,
        json.encode(app.options or {}),
        app.label,
        app.version,
        })

    return true
end

function Store.seenApp(id, label, version)
    return affected(MySQL.update.await('UPDATE evdev_apps SET label = ?, version = ?, last_seen = NOW() WHERE id = ?', {
        label,
        version,
        id,
    }))
end

function Store.updateApp(id, fields)
    local sets, values = {}, {}

    if fields.status ~= nil then
        sets[#sets + 1] = 'status = ?'
        values[#values + 1] = fields.status
    end

    if fields.enabled ~= nil then
        sets[#sets + 1] = 'enabled = ?'
        values[#values + 1] = fields.enabled and 1 or 0
    end

    if fields.options ~= nil then
        sets[#sets + 1] = 'options = ?'
        values[#values + 1] = json.encode(fields.options)
    end

    if #sets == 0 then
        return 0
    end

    values[#values + 1] = id

    return affected(MySQL.update.await(
        ('UPDATE evdev_apps SET %s WHERE id = ?'):format(table.concat(sets, ', ')),
        values
    ))
end

function Store.loadSettings()
    local rows = MySQL.query.await('SELECT k, v FROM evdev_settings') or {}
    local settings = {}

    for _, row in ipairs(rows) do
        settings[row.k] = decode(row.v, nil)
    end

    return settings
end

function Store.saveSetting(key, value)
    MySQL.query.await('INSERT INTO evdev_settings (k, v) VALUES (?, ?) ON DUPLICATE KEY UPDATE v = VALUES(v)', {
        key,
        json.encode(value),
    })

    return true
end

function Store.insertAudit(entry)
    return MySQL.insert.await('INSERT INTO evdev_audit (actor_cid, actor_name, action, device_id, detail) VALUES (?, ?, ?, ?, ?)', {
        entry.actorCid,
        entry.actorName,
        entry.action,
        entry.deviceId,
        entry.detail and json.encode(entry.detail) or nil,
    })
end

local function likeText(text)
    return '%' .. text:gsub('[\\%%_]', '\\%0') .. '%'
end

function Store.listAudit(filter)
    local where, values = {}, {}

    if filter.action then
        where[#where + 1] = 'action = ?'
        values[#values + 1] = filter.action
    end

    if filter.actions then
        local marks = {}

        for index, action in ipairs(filter.actions) do
            marks[index] = '?'
            values[#values + 1] = action
        end

        where[#where + 1] = 'action IN (' .. table.concat(marks, ', ') .. ')'
    end

    if filter.deviceId then
        where[#where + 1] = 'device_id = ?'
        values[#values + 1] = filter.deviceId
    end

    if filter.actor then
        where[#where + 1] = '(actor_cid = ? OR actor_name LIKE ?)'
        values[#values + 1] = filter.actor
        values[#values + 1] = likeText(filter.actor)
    end

    if filter.before then
        where[#where + 1] = 'id < ?'
        values[#values + 1] = filter.before
    end

    values[#values + 1] = filter.limit

    local sql = 'SELECT id, UNIX_TIMESTAMP(`at`) AS at_s, actor_cid, actor_name, action, device_id, detail FROM evdev_audit'

    if #where > 0 then
        sql = sql .. ' WHERE ' .. table.concat(where, ' AND ')
    end

    local rows = MySQL.query.await(sql .. ' ORDER BY id DESC LIMIT ?', values) or {}
    local list = {}

    for index, row in ipairs(rows) do
        list[index] = {
            id = row.id,
            at = tonumber(row.at_s),
            actorCid = row.actor_cid,
            actorName = row.actor_name,
            action = row.action,
            deviceId = row.device_id,
            detail = decode(row.detail, nil),
        }
    end

    return list
end

function Store.purgeAudit(days)
    return affected(MySQL.update.await('DELETE FROM evdev_audit WHERE `at` < (NOW() - INTERVAL ? DAY)', { days }))
end

function Store.insertReturn(cid, item, metadata, reason)
    return MySQL.insert.await('INSERT INTO evdev_returns (cid, item, metadata, reason) VALUES (?, ?, ?, ?)', {
        cid,
        item,
        json.encode(metadata or {}),
        reason,
    })
end

function Store.loadReturns(cid)
    local rows = MySQL.query.await('SELECT id, item, metadata, reason FROM evdev_returns WHERE cid = ? ORDER BY id', { cid }) or {}
    local list = {}

    for index, row in ipairs(rows) do
        list[index] = { id = row.id, item = row.item, metadata = decode(row.metadata, {}), reason = row.reason }
    end

    return list
end

function Store.deleteReturn(id)
    return affected(MySQL.update.await('DELETE FROM evdev_returns WHERE id = ?', { id }))
end

local function idList(ids)
    local values = {}

    for _, id in ipairs(type(ids) == 'table' and ids or {}) do
        local clean = Util.integer(id, 1)

        if clean then
            values[#values + 1] = clean
        end
    end

    return values, ('?, '):rep(#values):sub(1, -3)
end

function Store.loadNotices()
    local rows = MySQL.query.await([[SELECT id, cid, device_id, app, notice_id, title, body, action, intent, seen,
        UNIX_TIMESTAMP(created_at) AS created_s FROM evdev_notices ORDER BY id]]) or {}
    local list = {}

    for index, row in ipairs(rows) do
        list[index] = {
            id = row.id,
            cid = row.cid,
            deviceId = row.device_id,
            app = row.app,
            noticeId = row.notice_id,
            title = row.title,
            body = row.body or '',
            action = row.action,
            intent = row.intent and decode(row.intent, nil) or nil,
            seen = flag(row.seen),
            at = tonumber(row.created_s) or 0,
        }
    end

    return list
end

function Store.insertNotice(target, notice)
    return MySQL.insert.await([[INSERT INTO evdev_notices (cid, device_id, app, notice_id, title, body, action, intent, seen, created_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, FROM_UNIXTIME(?))]], {
        target.cid,
        target.deviceId,
        notice.app,
        notice.id,
        notice.title,
        notice.body or '',
        notice.action,
        notice.intent and json.encode(notice.intent) or nil,
        notice.seen and 1 or 0,
        notice.at,
    })
end

function Store.seeNotices(ids)
    local values, marks = idList(ids)

    if #values == 0 then return 0 end

    return affected(MySQL.update.await('UPDATE evdev_notices SET seen = 1 WHERE id IN (' .. marks .. ')', values))
end

function Store.deleteNotices(ids)
    local values, marks = idList(ids)

    if #values == 0 then return 0 end

    return affected(MySQL.update.await('DELETE FROM evdev_notices WHERE id IN (' .. marks .. ')', values))
end

function Store.purgeNotices(days)
    local gone = affected(MySQL.update.await('DELETE FROM evdev_notices WHERE created_at < (NOW() - INTERVAL ? DAY)', { days }))

    return gone + affected(MySQL.update.await([[DELETE n FROM evdev_notices n LEFT JOIN evdev_devices d ON d.id = n.device_id
        WHERE n.device_id IS NOT NULL AND (d.id IS NULL OR d.state = 'removed')]]))
end

return Store
