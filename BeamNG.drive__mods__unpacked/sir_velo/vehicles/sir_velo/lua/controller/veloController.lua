local M = {}
-- Mandatory controller parameters
M.type = "main"
M.relevantDevice = nil
M.engineInfo = {}
M.fireEngineTemperature = 0
M.throttle = 0
M.brake = 0
M.clutchRatio = 0

local min = math.min
local max = math.max
local abs = math.abs

local avToRPM = 9.549296596425384

local crankMotor = nil
local hubMotor = nil
local maxRPM = 13000

local socket = require('socket')
local host, port = '127.0.0.1', 20201
local client = assert(socket.tcp())
local slopeAge = 0
local recordAge = 0
local totalDistance = 0

electrics.values.ant_power = 0
electrics.values.ant_cadence = 0
electrics.values.ant_heartrate = 0
electrics.values.ant_slope = 0
local ant_is_recording = 0

local MAX_CADENCE = 0
local MIN_GRADE = 0
local MAX_GRADE = 0
local GRADE_DIFFICULTY = 0

local throttleOverride = 0
electrics.values.brakeOverride = 0

electrics.values.clutch = 0
electrics.values.clutchRatio = 1
electrics.values.gearIndex = 0

electrics.values.bike_cadence_normalized = 0

local MODEL_CDA = 0
local MODEL_CRR = 0
local MODEL_TOTALMASS = 0
local MODEL_DRIVETRAINEFFICIENCY = 0
local model_targetspeed = 0

local model_draftingcoefficient = 1

local function sendTorqueData()
    if not playerInfo.firstPlayerSeated then
        return
    end
    if hubMotor then
        hubMotor:sendTorqueData()
    end
    if crankMotor then
        crankMotor:sendTorqueData()
    end
end

local function toggleAI()
    if ai.mode == 'disabled' then
        ai.setMode('random')
        ai.driveInLane('on')
        electrics.set_warn_signal(0)
    else
        ai.setMode('disabled')
        electrics.set_warn_signal(1)
    end
end

local function toggleFitRecording()
    if ant_is_recording == 0 then
        client:send('START_RECORDING:0')
        electrics.setLightsState(1)
        totalDistance = 0
        ant_is_recording = 1
    else
        client:send('STOP_RECORDING:0')
        electrics.setLightsState(0)
        ant_is_recording = 0
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
         -- elseif k == 'SPD' then
         --     local speed = tonumber(v)
         --     electrics.values.ant_speed = speed * 3.6
            elseif k == 'CAD' then
                local cadence = tonumber(v)
                electrics.values.ant_cadence = cadence
            end
        end
    end
end

local function getCurrentLonLat()
    local x,y = obj:getPositionXYZ()  -- +x = E,  +y = N
    -- todo
    return 0, 0
end


local function sendCurrentSituation(dt)
    local _, pitch = obj:getRollPitchYaw()
    electrics.values.ant_slope = math.tan(pitch) * 100
    electrics.values.ant_slope = min(MAX_GRADE, electrics.values.ant_slope)
    electrics.values.ant_slope = max(MIN_GRADE, electrics.values.ant_slope)
    electrics.values.ant_slope = electrics.values.ant_slope * (GRADE_DIFFICULTY / 100)

    slopeAge = slopeAge + dt
    if slopeAge >= 1 then
        client:send('SLOPE:' .. electrics.values.ant_slope)
        slopeAge = 0
    end

    totalDistance = totalDistance + electrics.values.airspeed * dt
    local lon, lat = getCurrentLonLat()

    recordAge = recordAge + dt
    if ant_is_recording == 1 and recordAge >= 1 then
        client:send('WRITE_RECORD:' ..
            electrics.values.airspeed * 3.6 .. ',' ..
            electrics.values.ant_power .. ',' ..
            electrics.values.ant_cadence .. ',' ..
            electrics.values.ant_heartrate .. ',' ..
            lat .. ',' ..
            lon .. ',' ..
            electrics.values.altitude .. ',' ..
            totalDistance)
        recordAge = 0
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
    throttleOverride = math.max(0, 2 - electrics.values.airspeed)
    computeBikeSteering()
end

local function Resistance()
    return 0.5 * model_draftingcoefficient * obj:getAirDensity() * MODEL_CDA * electrics.values.airspeed * electrics.values.airspeed + MODEL_TOTALMASS * MODEL_CRR * -1 * obj:getGravity()
end

local function deltaV(dt)
    local _, pitch = obj:getRollPitchYaw()
    local slope = math.tan(pitch)
    local acceleration = Resistance() / MODEL_TOTALMASS - slope * obj:getGravity()
    local a = 1
    local b = electrics.values.airspeed - acceleration * dt
    local p = electrics.values.ant_power * MODEL_DRIVETRAINEFFICIENCY
    local c = - p * dt / MODEL_TOTALMASS + acceleration * electrics.values.airspeed * dt
    local delta = b * b - 4 * a * c
    if delta < 0 then
        return -1 * electrics.values.airspeed
    end
    return (-b + math.sqrt(delta)) / 2 / a;
end

local function updateSpeedModel(dt)
    local deltaV = deltaV(dt)
    model_targetspeed = electrics.values.airspeed + deltaV
end


local function init(jbeamData)
    hubMotor = powertrain.getDevice('hubMotor')
    crankMotor = powertrain.getDevice('crankMotor')

    MODEL_DRIVETRAINEFFICIENCY = jbeamData.drivetrainEfficiency
    MODEL_TOTALMASS = jbeamData.bikeWeight + jbeamData.riderWeight
    MODEL_CDA = jbeamData.cda
    MODEL_CRR = jbeamData.crr

    MAX_CADENCE = jbeamData.maxCadence
    MIN_GRADE = jbeamData.minGrade
    MAX_GRADE = jbeamData.maxGrade
    GRADE_DIFFICULTY = jbeamData.difficulty

    if ant_is_recording == 1 then
        toggleFitRecording()
    end

    if ai.mode ~= 'disabled' then
        toggleAI()
    end

    client:settimeout(0);
    local result, error = client:connect(host, port)
    if result == nil then
        log('E', 'sim_cycling', error)
    else
        log('I', 'sim_cycling', client:getpeername())
    end
end

local function updateGFX(dt)
    sendCurrentSituation(dt)
    readCompanionData()
    balanceBike()
    updateSpeedModel(dt)

    electrics.values.throttle = max(throttleOverride, deltaV(dt) * 50)
    if ai.mode == 'disabled' then
        electrics.values.throttle = max(electrics.values.throttle, input.throttle)
    end
    if throttleOverride > 0 then
        electrics.values.brake = 0
        electrics.values.abs = 1
    else
        if electrics.values.brakeOverride > 0 then
            input.brake = electrics.values.brakeOverride
        end
        electrics.values.brake = min(max(input.brake or 0, 0), 1)
        electrics.values.abs = 0
    end

    electrics.values.bike_cadence_normalized = electrics.values.ant_cadence / MAX_CADENCE

    electrics.values.gear = string.format("%dW", electrics.values.ant_power)
    electrics.values.rpm = electrics.values.ant_cadence * 100
    electrics.values.watertemp = electrics.values.ant_heartrate / 200 * 130 -- on dial; min: 50, max: 130

    electrics.values.fuelCapacity = 1 -- w'bal ?
    electrics.values.fuelVolume = 0.75 -- w'bal ?

    M.engineInfo = {0 -- 1. idle rpm
    , maxRPM -- 2. max rpm
    , 0 -- 3. ??
    , 0 -- 4. ??
    , electrics.values.rpm -- 5. current rpm
    , electrics.values.gear -- 6. gear name
    , 0 -- 7. max gear index
    , 0 -- 8. min gear index
    , 0 -- 9. engine torque
    , 0 -- 10. gearbox torque
    , obj:getGroundSpeed() -- 11. airspeed
    , electrics.values.fuelVolume -- 12. fuel volume
    , electrics.values.fuelCapacity -- 13. fuel capacity
    , "manual" -- 14. gearbox mode
    , obj:getID() -- 15. object id
    , 0 -- 16. ??
    , 0 -- 17. gear index
    , 1 -- 18. is engine running
    , 0 -- 19. engine load
    , 0 -- 20. wheel torque
    , 0 -- 21. wheel power
    }

end


M.init = init
M.updateGFX = updateGFX

-- Mandatory main controller API
M.shiftUp = nop
M.shiftDown = nop
M.shiftToGearIndex = nop
M.cycleGearboxModes = nop
M.setGearboxMode = nop
M.setStarter = nop
M.setFreeze = nop
M.sendTorqueData = sendTorqueData
M.toggleAI = toggleAI
M.toggleFitRecording = toggleFitRecording
-------------------------------

return M
