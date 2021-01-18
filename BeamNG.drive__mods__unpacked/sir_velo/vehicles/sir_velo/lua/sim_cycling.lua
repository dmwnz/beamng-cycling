log('I', 'sim_cycling', 'Hello World !')

local M = {}

local socket = require('socket')
local host, port = '127.0.0.1', 20201
local client = assert(socket.tcp())

local slopeAge = 0

local function onInit()
    client:settimeout(0);
    local result, error = client:connect(host, port)
    if result == nil then
        log('E', 'sim_cycling', error)
    end
end

local function readCompanionData()
    local res, status = client:receive()
    if res ~= nil then
        for k,v in string.gmatch(res, '(%w+):(%w+)') do
            if k == 'HR' then
                local hr = tonumber(v)
                electrics.values.ant_heartrate = hr
            elseif k == 'POW' then
                local power = tonumber(v)
                electrics.values.ant_power = power
            elseif k == 'SPD' then
                local speed = tonumber(v)
                electrics.values.ant_speed = speed * 3.6
            elseif k == 'CAD' then
                local cadence = tonumber(v)
                electrics.values.ant_cadence = cadence
            end
        end
    end
end

local function sendCurrentSituation(dt)

    local _, pitch = obj:getRollPitchYaw()

    electrics.values.ant_slope = math.tan(pitch)

    slopeAge = slopeAge + dt
    if slopeAge >= 1 then
        client:send('SLOPE:' .. electrics.values.ant_slope)
        slopeAge = 0
    end
end

local function computeBikeSteering(dt)
    -- tuning
    local c1, c2 = math.min(10/(electrics.values.airspeed + 0.01), 10) , math.min(electrics.values.airspeed/3, 2)

    -- inputs
    local current_leaning,_,_ = obj:getRollPitchYaw() -- rad
    current_leaning = current_leaning * -1
    --                                   ^
    -- giving it the same sign as input_steering (negative = left, positive = right)

    local max_leaning = math.pi/5 -- could be improved

    local additional_leaning = electrics.values.steering_input * max_leaning
    -- to go right (steering_input > 0), we want to lean right

    if current_leaning + additional_leaning < -max_leaning then
        additional_leaning = -max_leaning - current_leaning
    elseif current_leaning + additional_leaning > max_leaning then
        additional_leaning = max_leaning - current_leaning
    end

    electrics.values.bike_steering = c1 * current_leaning  + c2 * -additional_leaning
end

local function balanceBike()
    electrics.values.throttleOverride = math.max(0, 2 - electrics.values.airspeed)
    computeBikeSteering()
end

local function updateGFX(dt)
    sendCurrentSituation(dt)
    readCompanionData()
    --cruiseControl(dt)
    balanceBike()

end


M.onInit = onInit
M.updateGFX = updateGFX
M.onReset = onInit

return M
