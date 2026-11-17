local Config = {}

Config.debug = false

Config.framework = 'auto'

Config.notifyWith = 'ox_lib'

Config.aces = {
    admin = 'evolent_devices.admin',
    manage = 'evolent_devices.manage',
}

Config.adminGroups = {
    admin = { 'god', 'superadmin', 'admin' },
    manage = {},
}

Config.commands = {
    admin = 'evdevices',
    tablet = 'evdtablet',
}

Config.database = {
    autoMigrate = true,
}

Config.admin = {
    tokenIdleMinutes = 30,
    placeRange = 60.0,
    placeTolerance = 8.0,
    rate = { read = 10, write = 4, lookup = 1 },
    burst = 30,
}

Config.general = {
    adminsOpenAny = false,
    auditDays = 90,
    removedDays = 30,
    twinRadius = 25.0,
    watchRange = 12.0,
    forceCover = false,
    session = {
        idleMinutes = 15,
        lockMinutes = 5,
        leaseSeconds = 15,
        heartbeatSeconds = 5,
    },
    sound = {
        enabled = true,
        volume = 70,
        nearby = 40,
        range = 8.0,
    },
    display = {
        brightness = 100,
        light = 100,
        color = '',
        sleep = 3,
        night = false,
        nightFrom = 1320,
        nightTo = 420,
    },
}

Config.brand = {
    accent = '#C3FF00',
    logo = '',
    name = '',
    wallpaper = 'evolent',
    idle = { laptop = '', pc = '', terminal = '' },
}

Config.wallpapers = {}

Config.trustedResources = { 'evolent_dealership', 'evolent_boosting', 'evolent_garage' }

Config.limits = {
    rulesPerList = 24,
    appsPerDevice = 16,
    zones = 100,
    labelLength = 40,
    blockedSerials = 200,
    antennas = 200,
    appWindows = 4,
}

Config.marker = {
    color = '',
    scale = 1.0,
    motion = true,
    draw = 'poly',
}

Config.os = {
    apps = { notes = true, files = true, photos = true, store = true, settings = true },
    preinstalled = {},
    notes = { max = 40, title = 60, body = 3000, trash = 20, trashDays = 30 },
    photos = { links = false, hosts = { 'fivemanage.com', 'imgur.com' }, max = 24, name = 40, library = {} },
    password = { min = 4, max = 32, tries = 5, waitSeconds = 60 },
}

Config.notifications = {
    popup = { enabled = true, position = 'top_right', seconds = 6 },
    tablet = { enabled = true },
    screen = { enabled = true, blink = true },
    sound = true,
    keepDays = 7,
    keep = 30,
}

return Config
