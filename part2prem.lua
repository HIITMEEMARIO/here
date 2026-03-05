
getgenv()._VehHeliMod = getgenv()._VehHeliMod or {}

getgenv()._VehHeliMod.VehicleTuner = { Enabled = false }
getgenv()._VehHeliMod.HeliGodMode = { Enabled = false }
getgenv()._VehHeliMod.OriginalTune = {}
getgenv()._VehHeliMod.OriginalHeliTune = {}

-- Default configs (overridden by UI sliders)
getgenv()._VehHeliMod.VehicleConfig = {
    FrontGrip = 85,
    RearGrip = 85,
    FrontDriftGrip = 60,
    RearDriftGrip = 40,
    AccelerationFactor = 0.8,
    SteerSpeed = 8,
    MaxTurnAngle = 45,
    FrontFrequency = 3.5,
    RearFrequency = 3.0,
    FrontDamperComp = 0.7,
    FrontDamperExt = 0.6,
    RearDamperComp = 0.65,
    RearDamperExt = 0.55,
    FrontRollingFriction = 0.3,
    RearRollingFriction = 0.3,
}

getgenv()._VehHeliMod.HeliConfig = {
    StabilityMult = 1.8,
    PIDBoost = 1.6,
    DragMult = 0.6,
    ForceAutoHover = true,
    CollectiveBoost = 1.5,
    AngularDragMult = 2.0,
}

-- =====================================================
-- HELPER: Get active controller from ControllerService
-- =====================================================
getgenv()._VehHeliMod.GetActiveController = function()
    -- Use cached ControllerService from skriptk.lua if available
    local cs = getgenv()._CachedControllerService
    if cs and cs.Controller then
        return cs.Controller
    end

    -- Fallback: GC scan
    local ok, gc = pcall(function() return filtergc("table") end)
    if not ok then ok, gc = pcall(function() return getgc(true) end) end
    if not ok then return nil end

    for _, obj in pairs(gc) do
        if type(obj) == "table" and rawget(obj, "Controller") ~= nil then
            local s, v = pcall(function() return type(obj.Simulated) == "function" end)
            if s and v then
                getgenv()._CachedControllerService = obj
                gc = nil
                return obj.Controller
            end
        end
    end
    gc = nil
    return nil
end

-- =====================================================
-- VEHICLE TUNER FUNCTIONS
-- =====================================================

getgenv()._VehHeliMod.SaveVehicleTune = function(tune)
    if not tune or next(getgenv()._VehHeliMod.OriginalTune) ~= nil then return end

    local ot = {}
    ot.AccelerationFactor = tune.AccelerationFactor
    ot.SteerSpeed = tune.SteerSpeed
    ot.MaxSteerAngle = tune.MaxSteerAngle

    if tune.FrontWheels then
        ot.FrontWheels = {
            Grip = tune.FrontWheels.Grip,
            DriftGrip = tune.FrontWheels.DriftGrip,
            RollingFriction = tune.FrontWheels.RollingFriction,
            NaturalFrequency = tune.FrontWheels.NaturalFrequency,
            DamperRatioCompression = tune.FrontWheels.DamperRatioCompression,
            DamperRatioExtension = tune.FrontWheels.DamperRatioExtension,
        }
    end
    if tune.RearWheels then
        ot.RearWheels = {
            Grip = tune.RearWheels.Grip,
            DriftGrip = tune.RearWheels.DriftGrip,
            RollingFriction = tune.RearWheels.RollingFriction,
            NaturalFrequency = tune.RearWheels.NaturalFrequency,
            DamperRatioCompression = tune.RearWheels.DamperRatioCompression,
            DamperRatioExtension = tune.RearWheels.DamperRatioExtension,
        }
    end
    getgenv()._VehHeliMod.OriginalTune = ot
end

getgenv()._VehHeliMod.ApplyVehicleTune = function(tune)
    if not tune then return false end
    local cfg = getgenv()._VehHeliMod.VehicleConfig

    tune.AccelerationFactor = cfg.AccelerationFactor
    tune.SteerSpeed = cfg.SteerSpeed
    tune.MaxSteerAngle = cfg.MaxTurnAngle

    if tune.FrontWheels then
        tune.FrontWheels.Grip = cfg.FrontGrip
        tune.FrontWheels.DriftGrip = cfg.FrontDriftGrip
        tune.FrontWheels.RollingFriction = cfg.FrontRollingFriction
        tune.FrontWheels.NaturalFrequency = cfg.FrontFrequency
        tune.FrontWheels.DamperRatioCompression = cfg.FrontDamperComp
        tune.FrontWheels.DamperRatioExtension = cfg.FrontDamperExt
    end

    if tune.RearWheels then
        tune.RearWheels.Grip = cfg.RearGrip
        tune.RearWheels.DriftGrip = cfg.RearDriftGrip
        tune.RearWheels.RollingFriction = cfg.RearRollingFriction
        tune.RearWheels.NaturalFrequency = cfg.RearFrequency
        tune.RearWheels.DamperRatioCompression = cfg.RearDamperComp
        tune.RearWheels.DamperRatioExtension = cfg.RearDamperExt
    end

    -- Force solver recalc
    local ctrl = getgenv()._VehHeliMod.GetActiveController()
    if ctrl and ctrl._solver and ctrl._solver.NewTune then
        pcall(function() ctrl._solver:NewTune() end)
    end
    return true
end

getgenv()._VehHeliMod.RestoreVehicleTune = function(tune)
    local ot = getgenv()._VehHeliMod.OriginalTune
    if not tune or next(ot) == nil then return end

    tune.AccelerationFactor = ot.AccelerationFactor
    tune.SteerSpeed = ot.SteerSpeed
    tune.MaxSteerAngle = ot.MaxSteerAngle

    if tune.FrontWheels and ot.FrontWheels then
        for k, v in pairs(ot.FrontWheels) do tune.FrontWheels[k] = v end
    end
    if tune.RearWheels and ot.RearWheels then
        for k, v in pairs(ot.RearWheels) do tune.RearWheels[k] = v end
    end

    local ctrl = getgenv()._VehHeliMod.GetActiveController()
    if ctrl and ctrl._solver and ctrl._solver.NewTune then
        pcall(function() ctrl._solver:NewTune() end)
    end
    getgenv()._VehHeliMod.OriginalTune = {}
end

getgenv()._VehHeliMod.ToggleVehicleTuner = function(enabled)
    local mod = getgenv()._VehHeliMod
    mod.VehicleTuner.Enabled = enabled

    local ctrl = mod.GetActiveController()
    if not ctrl or not ctrl._tune or not ctrl._solver then
        mod.VehicleTuner.Enabled = false
        return false, "Wsiądź do pojazdu naziemnego!"
    end

    if enabled then
        mod.SaveVehicleTune(ctrl._tune)
        mod.ApplyVehicleTune(ctrl._tune)
        return true, "ON — Grip:" .. mod.VehicleConfig.FrontGrip .. " Accel:" .. mod.VehicleConfig.AccelerationFactor
    else
        mod.RestoreVehicleTune(ctrl._tune)
        return true, "OFF — Przywrócono oryginalne"
    end
end

-- =====================================================
-- HELICOPTER GOD MODE FUNCTIONS
-- =====================================================

getgenv()._VehHeliMod.SaveHeliTune = function(ctrl)
    if next(getgenv()._VehHeliMod.OriginalHeliTune) ~= nil then return end
    local tune = ctrl._tune or {}
    local oht = {
        SteadyStabilize = tune.SteadyStabilize,
        CollectiveInputSpeed = tune.CollectiveInputSpeed,
        PitchInputSpeed = tune.PitchInputSpeed,
        RollInputSpeed = tune.RollInputSpeed,
        YawInputSpeed = tune.YawInputSpeed,
    }

    if tune.AngularVelocityDragMultiplier then
        oht.AngularDrag = {}
        for k, v in pairs(tune.AngularVelocityDragMultiplier) do
            oht.AngularDrag[k] = v
        end
    end

    if tune.Blades then
        oht.Blades = {}
        for bn, bd in pairs(tune.Blades) do
            oht.Blades[bn] = {
                CounterTorque = bd.CounterTorque,
                AlignVertical = bd.AlignVertical,
            }
        end
    end
    getgenv()._VehHeliMod.OriginalHeliTune = oht
end

getgenv()._VehHeliMod.ApplyHeliGodMode = function(ctrl)
    local tune = ctrl._tune
    if not tune then return false end
    local cfg = getgenv()._VehHeliMod.HeliConfig

    -- SAFETY: Clamp to prevent NaN/Infinity
    local stabMult = math.clamp(cfg.StabilityMult, 1.0, 2.0)
    local pidMult = math.clamp(cfg.PIDBoost, 1.0, 2.5)
    local dragMult = math.clamp(cfg.AngularDragMult, 1.0, 3.0)
    local collectMult = math.clamp(cfg.CollectiveBoost, 1.0, 2.0)

    if tune.SteadyStabilize ~= nil then
        tune.SteadyStabilize = math.clamp(tune.SteadyStabilize * stabMult, 0, 0.95)
    end
    if tune.CollectiveInputSpeed then
        tune.CollectiveInputSpeed = math.clamp(tune.CollectiveInputSpeed * collectMult, 1, 60)
    end

    if tune.AngularVelocityDragMultiplier then
        for k, v in pairs(tune.AngularVelocityDragMultiplier) do
            tune.AngularVelocityDragMultiplier[k] = math.clamp(v * dragMult, 0.1, 10)
        end
    end

    if tune.Blades then
        for _, bd in pairs(tune.Blades) do
            if bd.AlignVertical then
                bd.AlignVertical = math.clamp(bd.AlignVertical * stabMult, 0, 0.95)
            end
        end
    end

    -- PID gain boost (clamped)
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

    -- Force auto-hover
    if cfg.ForceAutoHover and ctrl._autoHover ~= nil then
        ctrl._autoHover = true
    end

    if ctrl._solver and ctrl._solver.NewTune then
        pcall(function() ctrl._solver:NewTune() end)
    end
    return true
end

getgenv()._VehHeliMod.RestoreHeliTune = function(ctrl)
    local oht = getgenv()._VehHeliMod.OriginalHeliTune
    if next(oht) == nil then return end
    local tune = ctrl._tune
    if not tune then return end

    tune.SteadyStabilize = oht.SteadyStabilize
    tune.CollectiveInputSpeed = oht.CollectiveInputSpeed
    tune.PitchInputSpeed = oht.PitchInputSpeed
    tune.RollInputSpeed = oht.RollInputSpeed
    tune.YawInputSpeed = oht.YawInputSpeed

    if oht.AngularDrag and tune.AngularVelocityDragMultiplier then
        for k, v in pairs(oht.AngularDrag) do
            tune.AngularVelocityDragMultiplier[k] = v
        end
    end
    if oht.Blades and tune.Blades then
        for bn, od in pairs(oht.Blades) do
            if tune.Blades[bn] then
                tune.Blades[bn].CounterTorque = od.CounterTorque
                tune.Blades[bn].AlignVertical = od.AlignVertical
            end
        end
    end

    -- Restore PID gains
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
    getgenv()._VehHeliMod.OriginalHeliTune = {}
end

getgenv()._VehHeliMod.ToggleHeliGodMode = function(enabled)
    local mod = getgenv()._VehHeliMod
    mod.HeliGodMode.Enabled = enabled

    local ctrl = mod.GetActiveController()
    if not ctrl then
        mod.HeliGodMode.Enabled = false
        return false, "Wsiądź do helikoptera!"
    end

    -- Check it's a HelicopterController
    if not ctrl._PIDs and ctrl._autoHover == nil then
        mod.HeliGodMode.Enabled = false
        return false, "Nie jesteś w helikopterze!"
    end

    if enabled then
        mod.SaveHeliTune(ctrl)
        mod.ApplyHeliGodMode(ctrl)
        return true, "ON — Stability x" .. mod.HeliConfig.StabilityMult .. " PID x" .. mod.HeliConfig.PIDBoost
    else
        mod.RestoreHeliTune(ctrl)
        return true, "OFF — Przywrócono oryginalne"
    end
end

-- Auto-reapply loop for vehicle tuner (survives vehicle changes)
task.spawn(function()
    while true do
        task.wait(1.5)
        if getgenv()._VehHeliMod.VehicleTuner.Enabled then
            local ctrl = getgenv()._VehHeliMod.GetActiveController()
            if ctrl and ctrl._tune and ctrl._solver then
                getgenv()._VehHeliMod.ApplyVehicleTune(ctrl._tune)
            end
        end
    end
end)

print("[VehHeliMod] Module loaded!")
