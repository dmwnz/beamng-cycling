log('I', 'sim_cycling', 'Hello World !')

local M = {}

local socket = require("socket")
local host, port = "127.0.0.1", 20201
local client = assert(socket.tcp())

local targetSpeed= 0
local throttleSmooth = newTemporalSmoothing(200, 200)
local speedPID = newPIDStandard(0.3, 2, 0.0, 0, 1, 1, 1, 0, 2)

local bike_steering = 0

local function setSpeed(speed)
    targetSpeed = speed/3.6
    rampedTargetSpeed = electrics.values.wheelspeed or 0
end

local function onInit()
    -- local result, error = client:connect(host, port);
    -- if result == nil then
    --     log('E', 'sim_cycling', error)
    -- end
    -- client:settimeout(0);
    -- client:send("hello world\n");
end

local function cruiseControl(dt)
    local currentSpeed = electrics.values.wheelspeed or 0
    local output = speedPID:get(currentSpeed, targetSpeed, dt)
    electrics.values.throttleOverride = throttleSmooth:getUncapped(output, dt)
end

local function readCompanionData()
    local res, status = client:receive()
    if res ~= nil then
        for k,v in string.gmatch(res, "(%w+):(%w+)") do
            if k == 'HR' then
                local lastHr = tonumber(v)
                setSpeed(lastHr)
                log('I', 'sim_cycling', 'found hr : ' .. lastHr)
            end
        end
        client:send("hello world\n");
    end
end

local function computeBikeSteering(dt)
    local _
    -- tuning
    local c1, c2 = math.min(10/(electrics.values.airspeed + 0.01), 10) , math.min(electrics.values.airspeed/3, 2)

    -- inputs
    local current_leaning,_,_ = -1 * obj:getRollPitchYaw() -- rad
    --                           ^
    -- giving it the same sign as input_steering (negative = left, positive = right)

    local max_leaning = math.pi/4 -- could be improved

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
    if throttleOverride > 0 then
        electrics.values.throttle = electrics.values.throttle + throttleOverride
        electrics.values.brake = 0
        electrics.values.parkingbrake = 0
    end
    computeBikeSteering()
end

local function updateGFX(dt)
    --readCompanionData()
    --cruiseControl(dt)
    balanceBike()

end


M.onInit = onInit
M.updateGFX = updateGFX
M.onReset = onInit

return M
