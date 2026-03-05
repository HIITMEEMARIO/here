-- =====================================================
-- BRM5 Vehicle Tuner & Helicopter God Mode Module v2
-- Loaded by skriptk.lua — all state in getgenv()
-- =====================================================

-- Cleanup old instance
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
    _cachedCS = nil,

    VehicleConfig = {
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
    },

    HeliConfig = {
        StabilityMult = 1.8,
        PIDBoost = 1.6,
        DragMult = 0.6,
        ForceAutoHover = true,
        CollectiveBoost = 1.5,
        AngularDragMult = 2.0,
    },
}

-- shortcut
local MOD = getgenv()._VehHeliMod

-- =====================================================
-- Get active controller (cached)
-- =====================================================
MOD.GetActiveController = function()
    local cs = MOD._cachedCS
    if cs and cs.Controller then
        return cs.Controller
    end

    local ok, gc = pcall(function() return filtergc("table") end)
    if not ok then ok, gc = pcall(function() return getgc(true) end) end
    if not ok then return nil end

    for _, obj in pairs(gc) do
        if type(obj) == "table" and rawget(obj, "Controller") ~= nil then
            local s, v = pcall(function() return type(obj.Simulated) == "function" end)
            if s and v then
                MOD._cachedCS = obj
                gc = nil
                return obj.Controller
            end
        end
    end
    gc = nil
    return nil
end

-- =====================================================
-- VEHICLE TUNER
-- =====================================================

MOD.SaveVehicleTune = function(tune)
    if not tune or next(MOD.OriginalTune) ~= nil then return end
    local ot = {
        AccelerationFactor = tune.AccelerationFactor,
        SteerSpeed = tune.SteerSpeed,
        MaxSteerAngle = tune.MaxSteerAngle,
    }
    if tune.FrontWheels then
        ot.FrontWheels = {}
        for k, v in pairs(tune.FrontWheels) do
            if type(v) == "number" then ot.FrontWheels[k] = v end
        end
    end
    if tune.RearWheels then
        ot.RearWheels = {}
        for k, v in pairs(tune.RearWheels) do
            if type(v) == "number" then ot.RearWheels[k] = v end
        end
    end
    MOD.OriginalTune = ot
end

MOD.ApplyVehicleTune = function(tune)
    if not tune then return false end
    local cfg = MOD.VehicleConfig

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

    local ctrl = MOD.GetActiveController()
    if ctrl and ctrl._solver and ctrl._solver.NewTune then
        pcall(function() ctrl._solver:NewTune() end)
    end
    return true
end

MOD.RestoreVehicleTune = function(tune)
    local ot = MOD.OriginalTune
    if not tune or not ot or next(ot) == nil then return end

    if ot.AccelerationFactor then tune.AccelerationFactor = ot.AccelerationFactor end
    if ot.SteerSpeed then tune.SteerSpeed = ot.SteerSpeed end
    if ot.MaxSteerAngle then tune.MaxSteerAngle = ot.MaxSteerAngle end

    if tune.FrontWheels and ot.FrontWheels then
        for k, v in pairs(ot.FrontWheels) do tune.FrontWheels[k] = v end
    end
    if tune.RearWheels and ot.RearWheels then
        for k, v in pairs(ot.RearWheels) do tune.RearWheels[k] = v end
    end

    local ctrl = MOD.GetActiveController()
    if ctrl and ctrl._solver and ctrl._solver.NewTune then
        pcall(function() ctrl._solver:NewTune() end)
    end
    MOD.OriginalTune = {}
end

-- Called by UI toggle
MOD.ToggleVehicleTuner = function(enabled)
    MOD.VehicleTuner.Enabled = enabled

    local ctrl = MOD.GetActiveController()
    if not ctrl or not ctrl._tune then
        MOD.VehicleTuner.Enabled = false
        return false, "Wsiądź do pojazdu!"
    end

    if enabled then
        MOD.SaveVehicleTune(ctrl._tune)
        MOD.ApplyVehicleTune(ctrl._tune)
        return true, "ON — Grip:" .. MOD.VehicleConfig.FrontGrip .. " Accel:" .. MOD.VehicleConfig.AccelerationFactor
    else
        MOD.RestoreVehicleTune(ctrl._tune)
        return true, "OFF — Przywrócono"
    end
end

-- Called by sliders when value changes (instant re-apply)
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
        PitchInputSpeed = tune.PitchInputSpeed,
        RollInputSpeed = tune.RollInputSpeed,
        YawInputSpeed = tune.YawInputSpeed,
    }
    if tune.AngularVelocityDragMultiplier then
        oht.AngularDrag = {}
        for k, v in pairs(tune.AngularVelocityDragMultiplier) do oht.AngularDrag[k] = v end
    end
    if tune.Blades then
        oht.Blades = {}
        for bn, bd in pairs(tune.Blades) do
            oht.Blades[bn] = { CounterTorque = bd.CounterTorque, AlignVertical = bd.AlignVertical }
        end
    end
    MOD.OriginalHeliTune = oht
end

MOD.ApplyHeliGodMode = function(ctrl)
    local tune = ctrl._tune
    if not tune then return false end
    local cfg = MOD.HeliConfig

    local stabMult = math.clamp(cfg.StabilityMult, 1.0, 2.0)
    local pidMult = math.clamp(cfg.PIDBoost, 1.0, 2.5)
    local dragMult = math.clamp(cfg.AngularDragMult, 1.0, 3.0)
    local collectMult = math.clamp(cfg.CollectiveBoost, 1.0, 2.0)

    -- Need to restore originals first before re-applying multipliers
    -- to avoid stacking multipliers on each re-apply
    local oht = MOD.OriginalHeliTune
    if oht and next(oht) ~= nil then
        if oht.SteadyStabilize and tune.SteadyStabilize ~= nil then
            tune.SteadyStabilize = math.clamp(oht.SteadyStabilize * stabMult, 0, 0.95)
        end
        if oht.CollectiveInputSpeed and tune.CollectiveInputSpeed then
            tune.CollectiveInputSpeed = math.clamp(oht.CollectiveInputSpeed * collectMult, 1, 60)
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
    else
        -- First apply without originals
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
    end

    -- PID gain boost (always from originals to avoid stacking)
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
    return true
end

MOD.RestoreHeliTune = function(ctrl)
    local oht = MOD.OriginalHeliTune
    if not oht or next(oht) == nil then return end
    local tune = ctrl._tune
    if not tune then return end

    if oht.SteadyStabilize then tune.SteadyStabilize = oht.SteadyStabilize end
    if oht.CollectiveInputSpeed then tune.CollectiveInputSpeed = oht.CollectiveInputSpeed end
    if oht.PitchInputSpeed then tune.PitchInputSpeed = oht.PitchInputSpeed end
    if oht.RollInputSpeed then tune.RollInputSpeed = oht.RollInputSpeed end
    if oht.YawInputSpeed then tune.YawInputSpeed = oht.YawInputSpeed end

    if oht.AngularDrag and tune.AngularVelocityDragMultiplier then
        for k, v in pairs(oht.AngularDrag) do tune.AngularVelocityDragMultiplier[k] = v end
    end
    if oht.Blades and tune.Blades then
        for bn, od in pairs(oht.Blades) do
            if tune.Blades[bn] then
                if od.CounterTorque then tune.Blades[bn].CounterTorque = od.CounterTorque end
                if od.AlignVertical then tune.Blades[bn].AlignVertical = od.AlignVertical end
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
    MOD.OriginalHeliTune = {}
end

MOD.ToggleHeliGodMode = function(enabled)
    MOD.HeliGodMode.Enabled = enabled

    local ctrl = MOD.GetActiveController()
    if not ctrl then
        MOD.HeliGodMode.Enabled = false
        return false, "Wsiądź do helikoptera!"
    end
    if not ctrl._PIDs and ctrl._autoHover == nil then
        MOD.HeliGodMode.Enabled = false
        return false, "Nie w helikopterze!"
    end

    if enabled then
        MOD.SaveHeliTune(ctrl)
        MOD.ApplyHeliGodMode(ctrl)
        return true, "ON — Stab x" .. MOD.HeliConfig.StabilityMult
    else
        MOD.RestoreHeliTune(ctrl)
        return true, "OFF — Przywrócono"
    end
end

-- Called by sliders (instant re-apply)
MOD.ReapplyHeli = function()
    if not MOD.HeliGodMode.Enabled then return end
    local ctrl = MOD.GetActiveController()
    if ctrl and ctrl._tune then
        MOD.ApplyHeliGodMode(ctrl)
    end
end

-- =====================================================
-- Auto-reapply loop (ONLY when enabled, STOPS on disable)
-- =====================================================
task.spawn(function()
    while getgenv()._VehHeliMod and getgenv()._VehHeliMod._loopRunning do
        task.wait(2)
        if getgenv()._VehHeliMod then
            if getgenv()._VehHeliMod.VehicleTuner.Enabled then
                pcall(function()
                    local ctrl = getgenv()._VehHeliMod.GetActiveController()
                    if ctrl and ctrl._tune then
                        getgenv()._VehHeliMod.ApplyVehicleTune(ctrl._tune)
                    end
                end)
            end
        end
    end
end)

print("[VehHeliMod] Module v2 loaded!")
