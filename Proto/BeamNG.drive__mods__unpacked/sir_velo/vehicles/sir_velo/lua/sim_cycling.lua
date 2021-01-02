log('I', 'sim_cycling', 'Hello World !')

local M = {}

local socket = require("socket")
local host, port = "127.0.0.1", 20201
local client = assert(socket.tcp())

local targetSpeed= 0
local throttleSmooth = newTemporalSmoothing(200, 200)
local speedPID = newPIDStandard(0.3, 2, 0.0, 0, 1, 1, 1, 0, 2)
local crank_rotation = 0  -- degrees
local wheel_rotation = 0  -- degrees
local fake_steering = 0


local function setSpeed(speed)
    targetSpeed = speed/3.6
    rampedTargetSpeed = electrics.values.wheelspeed or 0
end

local function onInit()
    electrics.values.fake_steering = 0
    electrics.values.throttle = 0
    electrics.values.crank_rotation = crank_rotation
    electrics.values.wheel_rotation = wheel_rotation
    local result, error = client:connect(host, port);
    if result == nil then
        log('E', 'sim_cycling', error)
    end
    client:settimeout(0);
    client:send("hello world\n");
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

local function updateGFX(dt)
    readCompanionData()
    cruiseControl(dt)
    crank_rotation = (crank_rotation + electrics.values.throttle_input) % 360
    wheel_rotation = (wheel_rotation + electrics.values.throttle_input * 2.5) % 360
    
    electrics.values.crank_rotation = crank_rotation
    electrics.values.wheel_rotation = wheel_rotation
    electrics.values.fake_steering = electrics.values.steering_input
    -- log('I', 'sim_cycling', electrics.values['crank_rotation'])
end


M.onInit = onInit
M.updateGFX = updateGFX
M.onReset = onInit

return M
