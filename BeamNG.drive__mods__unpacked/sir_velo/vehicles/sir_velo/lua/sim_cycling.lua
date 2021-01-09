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
    -- http://paradise.caltech.edu/~cook/papers/TwoNeurons.pdf
    local _
    -- tuning
    local c1, c2 = 1, 1

    -- inputs
    local current_leaning,_,_ = obj:getRollPitchYaw() -- rad
    local desired_heading = (-math.pi / 6.0 * electrics.values.steering_input)

    -- first neuron
    local desired_leaning = c1 * desired_heading
    desired_leaning = math.max(desired_leaning, -math.pi / 4)
    desired_leaning = math.min(desired_leaning,  math.pi / 4)

    -- second neuron
    bike_steering = c2 * (desired_leaning - current_leaning)
end

local function updateGFX(dt)
    --readCompanionData()
    --cruiseControl(dt)
    computeBikeSteering(dt)
    electrics.values.bike_steering = bike_steering
    electrics.values.steering_input = bike_steering



end


M.onInit = onInit
M.updateGFX = updateGFX
M.onReset = onInit

return M
