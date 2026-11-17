local PlacementSync = {}

local ROUND = { d = 10, h = 1, y = 100, r = 10, size = 100, table = 100 }
local NUMBER_MS = 50

local function same(a, b)
    if type(a) ~= 'table' or type(b) ~= 'table' then return a == b end
    if #a ~= #b then return false end

    for i = 1, #a do
        if a[i] ~= b[i] then return false end
    end

    return true
end

function PlacementSync.loadModel(name)
    local hash = type(name) == 'number' and name or joaat(name)

    if not IsModelInCdimage(hash) then return nil end

    RequestModel(hash)

    local deadline = GetGameTimer() + 5000

    while not HasModelLoaded(hash) and GetGameTimer() < deadline do
        Wait(0)
    end

    if not HasModelLoaded(hash) then return nil end

    return hash
end

function PlacementSync.start(session, send, message)
    session.sync = { send = send, sent = {}, at = 0 }
    message.state = 'start'
    send(message)
end

function PlacementSync.push(session, state)
    local sync = session.sync
    local now = GetGameTimer()
    local diff, urgent, any = {}, false, false

    for key, value in pairs(state) do
        local scale = ROUND[key]

        if scale then
            value = math.floor(value * scale + 0.5) / scale
        end

        if not same(sync.sent[key], value) then
            diff[key] = value
            any = true
            urgent = urgent or not scale
        end
    end

    if not any or (not urgent and now - sync.at < NUMBER_MS) then return end

    for key, value in pairs(diff) do
        sync.sent[key] = value
    end

    sync.at = now
    diff.state = 'tick'
    sync.send(diff)
end

return PlacementSync
