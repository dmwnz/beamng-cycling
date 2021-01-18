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


electrics.values.ant_power = 0
electrics.values.ant_cadence = 0
electrics.values.ant_heartrate = 0
electrics.values.throttleOverride = 0
electrics.values.brakeOverride = 0
electrics.values.hazard = 1

local function updateGFX(dt)
    electrics.values.throttle = max(electrics.values.throttleOverride, electrics.values.ant_power / 250)
    if ai.mode == 'disabled' then
        electrics.values.hazard_enabled = 1
        electrics.values.hazard = 1
        electrics.values.throttle = max(electrics.values.throttle, input.throttle)
    else
        electrics.values.hazard = 0
        electrics.values.hazard_enabled = 0
    end
    if electrics.values.throttleOverride > 0 then
        electrics.values.brake = 0
        electrics.values.abs = 1
    else
        if electrics.values.brakeOverride > 0 then
            input.brake = electrics.values.brakeOverride
        end
        electrics.values.brake = min(max(input.brake or 0, 0), 1)
        electrics.values.abs = 0
    end

    electrics.values.clutch = 0
    electrics.values.clutchRatio = 1
    electrics.values.gear = string.format("%dW", electrics.values.ant_power)
    electrics.values.gearIndex = 0
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

local function init(jbeamData)
    hubMotor = powertrain.getDevice("hubMotor")
    crankMotor = powertrain.getDevice("crankMotor")
    electrics.set_warn_signal(1)
    electrics.values.ant_cadence_factor = 1 / 150
    electrics.values.ant_power_factor = 1 / 250
end

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
-------------------------------

return M
