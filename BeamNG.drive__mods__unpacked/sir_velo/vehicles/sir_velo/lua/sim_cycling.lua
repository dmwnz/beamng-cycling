log('I', 'sim_cycling', 'Hello World !')

local M = {}

local socket = require('socket')
local host, port = '127.0.0.1', 20201
local client = assert(socket.tcp())

local targetSpeed= 0
local throttleSmooth = newTemporalSmoothing(200, 200)
local speedPID = newPIDStandard(0.3, 2, 0.0, 0, 1, 1, 1, 0, 2)

local situationAge = 0

local function onInit()

    electrics.values.ant_cadence_factor = 1/150
    electrics.values.ant_power_factor = 1/250

    local result, error = client:connect(host, port)
    if result == nil then
        log('E', 'sim_cycling', error)
    end
    client:settimeout(0);
end

local function cruiseControl(dt)
    local currentSpeed = electrics.values.wheelspeed or 0
    local output = speedPID:get(currentSpeed, targetSpeed, dt)
    electrics.values.throttleOverride = throttleSmooth:getUncapped(output, dt)
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

    situationAge = situationAge + dt
    if situationAge >= 1 then
        client:send('SLOPE:' .. electrics.values.ant_slope)
        situationAge = 0
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
    local throttleOverride = math.max(0, 2 - electrics.values.airspeed)
    local ant_power = electrics.values.ant_power or 0
    if throttleOverride > 0 then
        electrics.values.ant_power = ant_power + throttleOverride/electrics.values.ant_power_factor
        electrics.values.brake = 0
        electrics.values.parkingbrake = 0
    end
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
