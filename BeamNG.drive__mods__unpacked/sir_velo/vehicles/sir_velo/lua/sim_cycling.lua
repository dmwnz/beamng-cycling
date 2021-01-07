log('I', 'sim_cycling', 'Hello World !')

local M = {}

local socket = require("socket")
local host, port = "127.0.0.1", 20201
local client = assert(socket.tcp())

local targetSpeed= 0
local throttleSmooth = newTemporalSmoothing(200, 200)
local speedPID = newPIDStandard(0.3, 2, 0.0, 0, 1, 1, 1, 0, 2)
local crank_rotation = 0  -- degrees

local bike_steering = 0

local previous_leaning = 0
local current_leaning, current_heading = 0, 0

local bs_dt = 0


local function setSpeed(speed)
    targetSpeed = speed/3.6
    rampedTargetSpeed = electrics.values.wheelspeed or 0
end

local function onInit()
    electrics.values.throttle = 0
    electrics.values.crank_rotation = crank_rotation
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
    
    -- tuning
    local c1, c2, c3 = 1, 1, 0

    -- inputs
    current_leaning,_,current_heading = obj:getRollPitchYaw() -- rad
    local leaning_d = (current_leaning - previous_leaning) / dt -- rad/sec
    local desired_heading = current_heading + (-math.pi / 6.0 * electrics.values.steering_input)

    -- first neuron
    local desired_leaning = c1 * (desired_heading - current_heading)
    desired_leaning = math.max(desired_leaning, -math.pi / 4)
    desired_leaning = math.min(desired_leaning,  math.pi / 4)

    -- second neuron
    bike_steering = c2 * (desired_leaning - current_leaning) - c3 * leaning_d

    previous_leaning = current_leaning
end

local function updateGFX(dt)
    --readCompanionData()
    --cruiseControl(dt)
    computeBikeSteering(dt)
    electrics.values.bike_steering = bike_steering
    electrics.values.steering_input = bike_steering


    local crankset_rpm = electrics.values.rpm / 3   -- assuming wheel speed = 3 x crank speed
    crank_rotation = (crank_rotation + crankset_rpm * 360/60 * dt) % 360
    electrics.values.crank_rotation = crank_rotation

end


M.onInit = onInit
M.updateGFX = updateGFX
M.onReset = onInit

return M
