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

electrics.values.ant_power = -1
electrics.values.ant_cadence = -1
electrics.values.ant_heartrate = 0
electrics.values.ant_slope = 0
local slope_averaged = 0

electrics.values.ant_is_recording = 0 -- 0 = stopped, 1 = paused, 2 = recording

local FAKE_POWER = 0

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
electrics.values.bike_steering = 0

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
        ai.setScriptDebugMode('route')
        ai.debugMode = 'route'
        ai.driveInLane('on')
    else
        ai.setMode('disabled')
    end
end

local function startFitRecording()
    if electrics.values.ant_is_recording == 0 then
        client:send('START_RECORDING:0')
        totalDistance = 0
        electrics.values.ant_is_recording = 2
    elseif electrics.values.ant_is_recording == 1 then
        client:send('RESUME_RECORDING:0')
        electrics.values.ant_is_recording = 2
    end
end

local function pauseFitRecording()
    if electrics.values.ant_is_recording == 2 then
        client:send('PAUSE_RECORDING:0')
        electrics.values.ant_is_recording = 1
    end
end

local function stopFitRecording()
    if electrics.values.ant_is_recording == 1 then
        client:send('STOP_RECORDING:0')
        electrics.values.ant_is_recording = 0
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

    if M.currentLevel == 'italy' then
        local lon0 = 10.3083114
        local lat0 = 42.6105413

        local mPerDegree = 2 * math.pi * 6378137.0 / 360.0;

        local latitude = lat0 + y / mPerDegree;
        local longitude = lon0 + x / mPerDegree * math.cos(math.pi / 180 * latitude);

        return longitude, latitude;
    end

    return 0, 0
end


local function sendCurrentSituation(dt)
    local _, pitch = obj:getRollPitchYaw()

    local slope = math.tan(pitch) * 100
    slope = min(MAX_GRADE, slope)
    slope = max(MIN_GRADE, slope)
    slope = slope * (GRADE_DIFFICULTY / 100)

    slope_averaged = slope_averaged + slope * dt

    slopeAge = slopeAge + dt
    if slopeAge >= 1 then
        electrics.values.ant_slope = slope_averaged / slopeAge
        client:send('SLOPE:' .. electrics.values.ant_slope)
        slopeAge = 0
        slope_averaged = 0
    end

    totalDistance = totalDistance + electrics.values.airspeed * dt
    local lon, lat = getCurrentLonLat()

    recordAge = recordAge + dt
    if electrics.values.ant_is_recording == 2 and recordAge >= 1 then
        client:send('WRITE_RECORD:' ..
            electrics.values.airspeed * 3.6 .. ',' ..
            electrics.values.ant_power .. ',' ..
            electrics.values.ant_cadence .. ',' ..
            electrics.values.ant_heartrate .. ',' ..
            lon .. ',' ..
            lat .. ',' ..
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
    throttleOverride = math.min(math.max(0, 2 - electrics.values.airspeed), 1)
    computeBikeSteering()
end

local function GravityAcceleration()
    local _, pitch = obj:getRollPitchYaw()
    local slope = math.tan(pitch)

    return slope * abs(obj:getGravity())
end

local function AirResistanceForce()
    return 0.5 * model_draftingcoefficient * obj:getAirDensity() * MODEL_CDA * electrics.values.airspeed * electrics.values.airspeed
end

local function RollingResistanceForce()
    return MODEL_TOTALMASS * MODEL_CRR * abs(obj:getGravity())
end

local function deltaV(dt, power)

    local acceleration = (AirResistanceForce() + RollingResistanceForce()) / MODEL_TOTALMASS + GravityAcceleration()
    local a = 1
    local b = electrics.values.airspeed + acceleration * dt
    local p = power * MODEL_DRIVETRAINEFFICIENCY
    local c = - p * dt / MODEL_TOTALMASS + acceleration * electrics.values.airspeed * dt
    local delta = b * b - 4 * a * c
    if delta < 0 then
        return -1 * electrics.values.airspeed
    end
    return (-b + math.sqrt(delta)) / 2 / a;
end

local function updateSpeedModel(dt, power)
    local deltaV = deltaV(dt, power)
    model_targetspeed = min(15, electrics.values.airspeed + deltaV)
end


local function init(jbeamData)
    log('I', 'veloController', 'init')
    hubMotor = powertrain.getDevice('hubMotor')
    crankMotor = powertrain.getDevice('crankMotor')

    -- black magic to launch companion app
    obj:queueGameEngineLua('Engine.Platform.openFile(extensions.core_vehicle_manager.getPlayerVehicleData().vehicleDirectory .. "/companion/SimCompanion.exe")')

    -- black magic to get current level
    obj:queueGameEngineLua('be:getPlayerVehicle(0):queueLuaCommand(\'controller.mainController.currentLevel="\' .. getCurrentLevelIdentifier() .. \'"\')')

    MODEL_DRIVETRAINEFFICIENCY = jbeamData.drivetrainEfficiency
    MODEL_TOTALMASS = jbeamData.bikeWeight + jbeamData.riderWeight
    MODEL_CDA = jbeamData.cda
    MODEL_CRR = jbeamData.crr

    MAX_CADENCE = jbeamData.maxCadence
    MIN_GRADE = jbeamData.minGrade
    MAX_GRADE = jbeamData.maxGrade
    GRADE_DIFFICULTY = jbeamData.difficulty

    FAKE_POWER = jbeamData.fakePower

    pauseFitRecording()

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
    local power = electrics.values.ant_power
    local cadence =  electrics.values.ant_cadence
    if electrics.values.ant_power == -1 then
        power = input.throttle * FAKE_POWER
    end
    if electrics.values.ant_cadence == -1 then
        cadence = input.throttle * MAX_CADENCE
    end

    sendCurrentSituation(dt)
    readCompanionData()
    balanceBike()
    updateSpeedModel(dt, power)

    electrics.values.ant_speed = model_targetspeed * 3.6

    electrics.values.throttle = min(1, max(throttleOverride, max(0, model_targetspeed - electrics.values.airspeed) * 100))
    if throttleOverride > 0 then
        electrics.values.brake = 0
        electrics.values.abs = 1
    else
        if electrics.values.brakeOverride > 0 then
            input.brake = electrics.values.brakeOverride
        end
        electrics.values.brake = min(max(input.brake or 0, 0), 1)
        electrics.values.abs = 0

        if electrics.values.brake > 0 then
            electrics.values.throttle = 0
        end
    end

    electrics.setLightsState(electrics.values.ant_is_recording)

    electrics.values.bike_cadence_normalized = cadence / MAX_CADENCE

    electrics.values.gear = string.format("%dW", power)
    electrics.values.rpm = cadence * 100
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
M.startFitRecording = startFitRecording
M.pauseFitRecording = pauseFitRecording
M.stopFitRecording = stopFitRecording
M.currentLevel = nil

-------------------------------

return M
