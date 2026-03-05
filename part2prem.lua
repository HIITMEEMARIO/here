-- =====================================================
-- BRM5 Vehicle Tuner & Helicopter God Mode Module v4
-- Relies entirely on skriptk.lua's ControllerService
-- =====================================================

if getgenv()._VehHeliMod and getgenv()._VehHeliMod._loopRunning then
    getgenv()._VehHeliMod._loopRunning = false
    task.wait(0.2)
end

getgenv()._VehHeliMod = {
    VehicleTuner = { Enabled = false },
    HeliGodMode = { Enabled = false },
    OriginalTune = {},
    OriginalHeliTune = {},
    _loopRunning = true,

    VehicleConfig = {
        FrontGrip = 85,
        RearGrip = 85,
        FrontDriftGrip = 60,
        RearDriftGrip = 40,
        AccelerationFactor = 0.8,
        SteerSpeed = 8,
        MaxTurnAngle = 45,
    },
    HeliConfig = {
        StabilityMult = 1.8,
        PIDBoost = 1.6,
        CollectiveBoost = 1.5,
        AngularDragMult = 2.0,
        ForceAutoHover = true,
    },
}

local MOD = getgenv()._VehHeliMod

MOD.GetActiveController = function()
    -- ALWAYS use the exact ControllerService from skriptk.lua
    local cs = getgenv()._CachedControllerService
    if cs and cs.Controller then
        return cs.Controller
    end
    return nil
end

-- =====================================================
-- VEHICLE TUNER
-- =====================================================

MOD.SaveVehicleTune = function(tune)
    if not tune or next(MOD.OriginalTune) ~= nil then return end
    MOD.OriginalTune = {
        AccelerationFactor = tune.AccelerationFactor,
        SteerSpeed = tune.SteerSpeed,
        MaxSteerAngle = tune.MaxSteerAngle,
        FrontWheels = tune.FrontWheels and {
            Grip = tune.FrontWheels.Grip,
            DriftGrip = tune.FrontWheels.DriftGrip,
        } or nil,
        RearWheels = tune.RearWheels and {
            Grip = tune.RearWheels.Grip,
            DriftGrip = tune.RearWheels.DriftGrip,
        } or nil,
    }
end

MOD.ApplyVehicleTune = function(tune)
    if not tune then return end
    local cfg = MOD.VehicleConfig

    if tune.AccelerationFactor ~= nil then tune.AccelerationFactor = cfg.AccelerationFactor end
    if tune.SteerSpeed ~= nil then tune.SteerSpeed = cfg.SteerSpeed end
    if tune.MaxSteerAngle ~= nil then tune.MaxSteerAngle = cfg.MaxTurnAngle end
    if tune.MaxTurnAngleConstant ~= nil then tune.MaxTurnAngleConstant = cfg.MaxTurnAngle end

    if tune.FrontWheels then
        if tune.FrontWheels.Grip ~= nil then tune.FrontWheels.Grip = cfg.FrontGrip end
        if tune.FrontWheels.DriftGrip ~= nil then tune.FrontWheels.DriftGrip = cfg.FrontDriftGrip end
    end
    if tune.RearWheels then
        if tune.RearWheels.Grip ~= nil then tune.RearWheels.Grip = cfg.RearGrip end
        if tune.RearWheels.DriftGrip ~= nil then tune.RearWheels.DriftGrip = cfg.RearDriftGrip end
    end

    local ctrl = MOD.GetActiveController()
    if ctrl and ctrl._solver and ctrl._solver.NewTune then
        pcall(function() ctrl._solver:NewTune() end)
    end
end

MOD.RestoreVehicleTune = function(tune)
    local ot = MOD.OriginalTune
    if not tune or not ot or next(ot) == nil then return end

    if ot.AccelerationFactor then tune.AccelerationFactor = ot.AccelerationFactor end
    if ot.SteerSpeed then tune.SteerSpeed = ot.SteerSpeed end
    if ot.MaxSteerAngle then tune.MaxSteerAngle = ot.MaxSteerAngle end

    if tune.FrontWheels and ot.FrontWheels then
        if ot.FrontWheels.Grip then tune.FrontWheels.Grip = ot.FrontWheels.Grip end
        if ot.FrontWheels.DriftGrip then tune.FrontWheels.DriftGrip = ot.FrontWheels.DriftGrip end
    end
    if tune.RearWheels and ot.RearWheels then
        if ot.RearWheels.Grip then tune.RearWheels.Grip = ot.RearWheels.Grip end
        if ot.RearWheels.DriftGrip then tune.RearWheels.DriftGrip = ot.RearWheels.DriftGrip end
    end

    MOD.OriginalTune = {}
    local ctrl = MOD.GetActiveController()
    if ctrl and ctrl._solver and ctrl._solver.NewTune then
        pcall(function() ctrl._solver:NewTune() end)
    end
end

MOD.ToggleVehicleTuner = function(enabled)
    MOD.VehicleTuner.Enabled = enabled
    local ctrl = MOD.GetActiveController()
    
    if not ctrl or not ctrl._tune then
        MOD.VehicleTuner.Enabled = false
        return false, "No Vehicle!"
    end

    if enabled then
        MOD.SaveVehicleTune(ctrl._tune)
        MOD.ApplyVehicleTune(ctrl._tune)
        return true, "ON!"
    else
        MOD.RestoreVehicleTune(ctrl._tune)
        return true, "OFF!"
    end
end

MOD.ReapplyVehicle = function()
    if not MOD.VehicleTuner.Enabled then return end
    local ctrl = MOD.GetActiveController()
    if ctrl and ctrl._tune then
        MOD.ApplyVehicleTune(ctrl._tune)
    end
end

-- =====================================================
-- HELICOPTER GOD MODE
-- =====================================================

MOD.SaveHeliTune = function(ctrl)
    if next(MOD.OriginalHeliTune) ~= nil then return end
    local tune = ctrl._tune or {}
    local oht = {
        SteadyStabilize = tune.SteadyStabilize,
        CollectiveInputSpeed = tune.CollectiveInputSpeed,
    }

    if tune.AngularVelocityDragMultiplier then
        oht.AngularDrag = {}
        for k, v in pairs(tune.AngularVelocityDragMultiplier) do oht.AngularDrag[k] = v end
    end
    if tune.Blades then
        oht.Blades = {}
        for bn, bd in pairs(tune.Blades) do
            oht.Blades[bn] = { AlignVertical = bd.AlignVertical }
        end
    end
    MOD.OriginalHeliTune = oht
end

MOD.ApplyHeliGodMode = function(ctrl)
    local tune = ctrl._tune
    if not tune then return end
    local cfg = MOD.HeliConfig
    local oht = MOD.OriginalHeliTune

    local stabMult = math.clamp(cfg.StabilityMult, 1.0, 2.0)
    local pidMult = math.clamp(cfg.PIDBoost, 1.0, 2.5)
    local dragMult = math.clamp(cfg.AngularDragMult, 1.0, 3.0)
    local collectMult = math.clamp(cfg.CollectiveBoost, 1.0, 2.0)

    -- Scale relative to original values to prevent stacking
    local base = (oht and next(oht) ~= nil) and oht or tune

    if base.SteadyStabilize and tune.SteadyStabilize ~= nil then
        tune.SteadyStabilize = math.clamp(base.SteadyStabilize * stabMult, 0, 0.95)
    end
    if base.CollectiveInputSpeed and tune.CollectiveInputSpeed then
        tune.CollectiveInputSpeed = math.clamp(base.CollectiveInputSpeed * collectMult, 1, 60)
    end

    if oht.AngularDrag and tune.AngularVelocityDragMultiplier then
        for k, v in pairs(oht.AngularDrag) do
            tune.AngularVelocityDragMultiplier[k] = math.clamp(v * dragMult, 0.1, 10)
        end
    end

    if oht.Blades and tune.Blades then
        for bn, od in pairs(oht.Blades) do
            if tune.Blades[bn] and od.AlignVertical then
                tune.Blades[bn].AlignVertical = math.clamp(od.AlignVertical * stabMult, 0, 0.95)
            end
        end
    end

    -- PID boost (always from originals to avoid stacking)
    if ctrl._PIDs then
        for _, modes in pairs(ctrl._PIDs) do
            for _, axes in pairs(modes) do
                for _, pid in pairs(axes) do
                    if pid.Kp then
                        pid._origKp = pid._origKp or pid.Kp
                        pid.Kp = math.clamp(pid._origKp * pidMult, -20, 20)
                    end
                end
            end
        end
    end

    if cfg.ForceAutoHover and ctrl._autoHover ~= nil then
        ctrl._autoHover = true
    end

    if ctrl._solver and ctrl._solver.NewTune then
        pcall(function() ctrl._solver:NewTune() end)
    end
end

MOD.RestoreHeliTune = function(ctrl)
    local oht = MOD.OriginalHeliTune
    if not oht or next(oht) == nil then return end
    local tune = ctrl._tune
    if not tune then return end

    if oht.SteadyStabilize then tune.SteadyStabilize = oht.SteadyStabilize end
    if oht.CollectiveInputSpeed then tune.CollectiveInputSpeed = oht.CollectiveInputSpeed end

    if oht.AngularDrag and tune.AngularVelocityDragMultiplier then
        for k, v in pairs(oht.AngularDrag) do tune.AngularVelocityDragMultiplier[k] = v end
    end
    if oht.Blades and tune.Blades then
        for bn, od in pairs(oht.Blades) do
            if tune.Blades[bn] and od.AlignVertical then
                tune.Blades[bn].AlignVertical = od.AlignVertical
            end
        end
    end

    if ctrl._PIDs then
        for _, modes in pairs(ctrl._PIDs) do
            for _, axes in pairs(modes) do
                for _, pid in pairs(axes) do
                    if pid._origKp then
                        pid.Kp = pid._origKp
                        pid._origKp = nil
                    end
                end
            end
        end
    end

    if ctrl._solver and ctrl._solver.NewTune then
        pcall(function() ctrl._solver:NewTune() end)
    end
    MOD.OriginalHeliTune = {}
end

MOD.ToggleHeliGodMode = function(enabled)
    MOD.HeliGodMode.Enabled = enabled
    local ctrl = MOD.GetActiveController()
    
    if not ctrl or (not ctrl._PIDs and ctrl._autoHover == nil) then
        MOD.HeliGodMode.Enabled = false
        return false, "No Heli!"
    end

    if enabled then
        MOD.SaveHeliTune(ctrl)
        MOD.ApplyHeliGodMode(ctrl)
        return true, "ON!"
    else
        MOD.RestoreHeliTune(ctrl)
        return true, "OFF!"
    end
end

MOD.ReapplyHeli = function()
    if not MOD.HeliGodMode.Enabled then return end
    local ctrl = MOD.GetActiveController()
    if ctrl and ctrl._tune then
        MOD.ApplyHeliGodMode(ctrl)
    end
end

-- =====================================================
-- Auto-Apply Loop
-- =====================================================
task.spawn(function()
    while getgenv()._VehHeliMod and getgenv()._VehHeliMod._loopRunning do
        task.wait(1.5)
        if getgenv()._VehHeliMod then
            local ctrl = getgenv()._VehHeliMod.GetActiveController()
            if ctrl and ctrl._tune then
                if getgenv()._VehHeliMod.VehicleTuner.Enabled and (ctrl._throttle ~= nil) then
                    pcall(function() getgenv()._VehHeliMod.ApplyVehicleTune(ctrl._tune) end)
                end
                if getgenv()._VehHeliMod.HeliGodMode.Enabled and (ctrl._PIDs ~= nil or ctrl._autoHover ~= nil) then
                    pcall(function() getgenv()._VehHeliMod.ApplyHeliGodMode(ctrl) end)
                end
            end
        end
    end
end)
