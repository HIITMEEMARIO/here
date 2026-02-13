local Compkiller = loadstring(game:HttpGet("https://raw.githubusercontent.com/4lpaca-pin/CompKiller/refs/heads/main/src/source.luau"))();
-- [[ SINGLETON / KILL OLD INSTANCE ]]
if getgenv().Blackhawk_Running then
    getgenv().Blackhawk_Running = false -- Signal old instance to stop
    task.wait(0.1)
end
getgenv().Blackhawk_Running = true
local scriptId = tick()
getgenv().Blackhawk_CurrentId = scriptId

-- [[ UI CLEANUP - DESTROY OLD GUI ]]
-- Try to find existing Compkiller UI in CoreGui (default name is usually 'CompKiller | UI' or similar)
local CoreGui = game:GetService("CoreGui")
for _, child in pairs(CoreGui:GetChildren()) do
    if child.Name == "CompKiller | UI" or child.Name == "CompKiller" then
        child:Destroy()
    end
end
-- Also check if we stored it in getgenv previously
if getgenv().Blackhawk_GUI and getgenv().Blackhawk_GUI.Parent then
    getgenv().Blackhawk_GUI:Destroy()
end

-- Cleanup previous connections
if getgenv().BlackhawkESP_Connections then
    for _, conn in pairs(getgenv().BlackhawkESP_Connections) do
        if conn then pcall(function() conn:Disconnect() end) end
    end
end
getgenv().BlackhawkESP_Connections = {}

-- [[ AUTO RE-EXECUTE ON TELEPORT ]]
local function QueueTeleport()
    local queue = (syn and syn.queue_on_teleport) or queue_on_teleport
    if queue then
        queue('if not shared.BRM_Executed then shared.BRM_Executed = true; task.wait(3); loadstring(game:HttpGet("https://raw.githubusercontent.com/HIITMEEMARIO/here/refs/heads/main/v2.lua"))() end')
    end
end

-- Disconnect old teleport connection if it exists
if getgenv().TeleportConn then getgenv().TeleportConn:Disconnect() end
getgenv().TeleportConn = game:GetService("Players").LocalPlayer.OnTeleport:Connect(QueueTeleport)
table.insert(getgenv().BlackhawkESP_Connections, getgenv().TeleportConn)
-- [[ SECURITY SYSTEM (DRM / Anti-Leak) ]] 
-- HWID-Based Protection powered by Google Apps Script
local SECURITY_URL = "https://script.google.com/macros/s/AKfycbyzXuryAKcxZxEPICMFcX9NT7pBH4UuOk8R6f03KSn_QifteveKvkx1fdNM-50o0-OD/exec" -- <<< WKLEJ TU SWÓJ LINK


-- [[ STAFF / ANTI-CHEAT SYSTEM ]]
local function CreateTag()
    local tag = Instance.new("StringValue")
    tag.Name = "Blackhawk_ActiveUser"
    tag.Value = "V5_Premium"
    tag.Parent = game.Players.LocalPlayer
end
CreateTag()

getgenv().DetectedUsers = {}

local function RemoteBan(targetUserId)
    local req_func = (syn and syn.request) or (http and http.request) or request or http_request
    if req_func then
        req_func({
            Url = SECURITY_URL,
            Method = "POST",
            Headers = {["Content-Type"] = "application/json"},
            Body = game:GetService("HttpService"):JSONEncode({
                action = "ban",
                targetUserId = targetUserId,
                username = game.Players.LocalPlayer.Name
            })
        })
    end
end


-- Localize Globals and Methods for Performance
local Vector3_new = Vector3.new
local Vector2_new = Vector2.new
local CFrame_new = CFrame.new
local Color3_new = Color3.new
local Color3_fromHSV = Color3.fromHSV
local RaycastParams_new = RaycastParams.new
local math_floor = math.floor
local math_clamp = math.clamp
local math_abs = math.abs
local pairs = pairs
local ipairs = ipairs
local type = type
local tick = tick
local os_clock = os.clock
local string_format = string.format
local rawget = rawget
local pcall = pcall
local tostring = tostring
local getgenv = getgenv
local getgc = getgc
local filtergc = filtergc
local Drawing = Drawing
local Drawing_new = Drawing and Drawing.new

-- Services
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local CoreGui = game:GetService("CoreGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Camera = Workspace.CurrentCamera
local LocalPlayer = Players.LocalPlayer
local Mouse = LocalPlayer:GetMouse()

-- SolveLead defined later at line 746
-- Removed duplicate definition


-- Optimized Weapon Management
local WeaponManager = {
    Equipped = nil,
    Logic = {},
    Visuals = {},
    LastScan = 0,
    -- ScanCooldown unused
    Connection = nil
}

local ESPElements = {}
local CurrentFrameId = 0
local ESPEnabled = false
local ActorManager = {
    Enemies = {},
    Teammates = {},
    Vehicles = {},
    _lastMapUpdate = 0,
    _lastListUpdate = 0,
    _lastTargetUpdate = 0,
    Initialized = false,
    SelectedTarget = nil,
    SelectedActor = nil,
    _rageShots = {},
    _rageShotsNeeded = {},
    _rageLast = {},
    _ignoredTargets = {}
}

-- Forward Declarations
local SetupHooks
local EnableSpeedController
local GetSecureContainer
local DetectMapType 
local SecureESPContainer = nil
local ShouldShowEntity -- Forward declaration
local RefreshFirearmControllers

-- Core Service Globals (Found via GC)
local InventoryService, ReplicatorService, ClientService, WorldService, BulletService, Network
local CharacterController, ControllerService, FirearmInventoryClass, ActorClass, Recoiler, EffectsService
local CalibersTable, VehicleService, FirearmInventory

-- Configuration
local Config = {
    -- Entity Filters
    ShowPlayers = true,
    ShowZombies = true,
    ShowNPCs = true,
    ShowSquadMembers = false,
    ShowVehicles = false,
    VehicleColor = Color3_new(0, 1, 1),
    VehicleHealthColor = Color3_new(0, 1, 0),
    IgnoreLocalVehicle = true,
    
    -- Visual Options
    UseBoxESP = true,
    SimpleESP = false,
    UseHighlight = false,
    UseTracers = false,
    ShowNames = true,
    ShowDistance = true,
    ShowHealth = true,
    ShowWeaponInfo = true,
    BoxStyle = "Full",
    
    -- Vehicle Visuals
    ShowVehicleBox = true,
    VehicleBoxStyle = "Full",
    ShowVehicleName = true,
    ShowVehicleHealth = true,
    VehicleHealthBarSide = "Bottom",

    TextScale = 1.20,
    DynamicTextScaling = true,
    
    -- Distance Settings
    MaxDistance = 2000,

    -- Combat Settings
    NoRecoil = false,
    NoSpread = false,
    UnlockFiremodes = false,
    RPMValue = 800,
    AutoReload = true,

    -- Silent Aim
    SilentAim = false,
    SilentAimFOV = 100,
    SilentAimHitChance = 100,
    SilentAimTargetPart = "Head",
    
    -- Ragebot
    RageMode = false,
    Rage_BurstSize = 1,
    Rage_LookAt = false,
    Rage_FOV = 360,
    Rage_Range = 500,
    Rage_TargetPart = "Head",
    
    ShowFOV = false,
    Prediction = false,
    BulletDrop = false,
    ShowPrediction = false,
    PredictionColor = Color3.fromRGB(255, 0, 0),
    HitboxExpander = false,
    HitboxSize = 4,
    SmartTargetSwitch = false, -- Auto-switch to next target when current will die
    
    -- Character Movement
    Character_Fly = false,
    Character_FlySpeed = 50,
    Character_WalkSpeedEnabled = false,
    Character_WalkSpeed = 16,
    Character_SprintSpeedEnabled = false,
    Character_SprintSpeed = 25,
    
    -- Vehicle Turret Settings
    TurretUnlockFiremodes = false,
    TurretNoRecoil = false,
    TurretNoSpread = false,
    AlwaysDay = false,
    NoFog = false,
    ThermalVision = false,
    NightVision = false,

    -- Colors
    BoxColor = nil, -- Default to Entity Color
    HealthBarColor = nil, -- Default to Green/Gradient
    PlayerColor = Color3_new(1, 0.65, 0),
    TeammateColor = Color3_new(0, 1, 0),
    ZombieColor = Color3_new(1, 0, 0),
    NPCColor = Color3_new(1, 1, 0),
    SquadColor = Color3_new(0, 1, 0),
    TracerColor = Color3_new(1, 1, 1),
    
    -- Zombie Type Colors
    ZombieColors = {
        [1] = Color3_new(0.58, 0.29, 0),
        [2] = Color3_new(1, 1, 0),
        [3] = Color3_new(1, 0, 0),
        [4] = Color3_new(0.58, 0, 1)
    },
    
    -- Layout Settings
    BoxScale = 1.0,

    
    HealthBarSide = "Left",
    UseHealthGradient = true,
    
    -- Map-specific
    AutoDetectMap = true,
    CurrentMapType = "Unknown",
    CurrentMapName = "Unknown",
    
    -- FPS Optimization
    FPS_NoRain = false,
    FPS_NoEffects = false,
    FPS_NoShells = false,
    FPS_NoLensFlare = false,
    FPS_LowQuality = false,
    
    -- Vehicle Fly
    VehicleFly_Enabled = false,
    VehicleFly_Speed = 100,
    VehicleFly_ToggleKey = Enum.KeyCode.X,
    VehicleFly_UpKey = Enum.KeyCode.E,
    VehicleFly_DownKey = Enum.KeyCode.Q,

    -- Vehicle Teleport
    VehicleWaypoints = {}
}

-- ==========================================
-- VEHICLE FLY SYSTEM (After Config for scope access)
-- ==========================================

local VehicleFly = {
    HooksApplied = false
}

-- Apply Vehicle Fly Movement (hooks into VehicleClass.Update)
local function ApplyVehicleFly(vehicle, dt, originalUpdate)
    if not Config.VehicleFly_Enabled or not vehicle.Controlling then
        return originalUpdate(vehicle, dt)
    end
    
    if not Camera then return originalUpdate(vehicle, dt) end
    
    -- Calculate movement direction based on camera
    local moveDir = Vector3_new()
    if UserInputService:IsKeyDown(Enum.KeyCode.W) then moveDir = moveDir + Camera.CFrame.LookVector end
    if UserInputService:IsKeyDown(Enum.KeyCode.S) then moveDir = moveDir - Camera.CFrame.LookVector end
    if UserInputService:IsKeyDown(Enum.KeyCode.A) then moveDir = moveDir - Camera.CFrame.RightVector end
    if UserInputService:IsKeyDown(Enum.KeyCode.D) then moveDir = moveDir + Camera.CFrame.RightVector end
    if UserInputService:IsKeyDown(Config.VehicleFly_UpKey) then moveDir = moveDir + Vector3_new(0,1,0) end
    if UserInputService:IsKeyDown(Config.VehicleFly_DownKey) then moveDir = moveDir - Vector3_new(0,1,0) end
    
    if moveDir.Magnitude > 0 then moveDir = moveDir.Unit end
    
    -- Calculate new position
    local currentCF = vehicle.CFrame or (vehicle.Hitbox and vehicle.Hitbox.CFrame) or CFrame_new()
    local newPos = currentCF.Position + (moveDir * Config.VehicleFly_Speed * dt)
    local newCF = CFrame.lookAt(newPos, newPos + Camera.CFrame.LookVector)
    
    -- Update vehicle
    vehicle.CFrame = newCF
    if vehicle.Hitbox then vehicle.Hitbox.CFrame = newCF end
    
    -- Update controller solver if available
    pcall(function()
        if ControllerService and ControllerService.Controller then
            local ctrl = ControllerService.Controller
            if ctrl._vehicle == vehicle and ctrl._solver and ctrl._solver.SetState then
                ctrl._solver:SetState(newCF, Vector3_new(), Vector3_new(), vehicle.ComponentReplicates)
            end
        end
    end)
    
    -- Update actor position
    pcall(function()
        if ReplicatorService and ReplicatorService.LocalActor then
            ReplicatorService.LocalActor.SimulatedPosition = newCF.Position
        end
    end)
    
    return newCF, vehicle.Hitbox, {}
end

-- Hook VehicleClass Update (called during service initialization)
function VehicleFly.HookVehicles()
    if VehicleFly.HooksApplied then return end
    
    for _, tbl in pairs(getgc(true)) do
        if type(tbl) == "table" and rawget(tbl, "Update") and not tbl._FlyHooked then
            -- Detect VehicleClass by checking for vehicle-specific methods
            if rawget(tbl, "SetRPM") or rawget(tbl, "_updateLightModes") then
                local old = tbl.Update
                tbl.Update = function(self, dt) return ApplyVehicleFly(self, dt, old) end
                tbl._FlyHooked = true
            end
        end
    end
    
    VehicleFly.HooksApplied = true
end

-- Toggle Vehicle Fly
function VehicleFly.Toggle()
    Config.VehicleFly_Enabled = not Config.VehicleFly_Enabled
    print("[Vehicle Fly]", Config.VehicleFly_Enabled and "ENABLED" or "DISABLED")
end


-- BRM5 Place IDs (Dumped from PlaceService)
local Places = {
    ["Menu"] = {16173503753, 2916899287},
    ["CM_Mission1"] = {83829699029749, 4843465225},
    ["OW_Ronograd"] = {95595459346841, 3701546109},
    ["OW_Blank"] = {0, 5899968224},
    ["HQ_Seychelles"] = {139188553486454, 14014688944},
    ["PVP_Coast"] = {99240342190508, 5480112241},
    ["PVP_Favela"] = {123576346999506, 5468388011},
    ["PVP_NYC"] = {71499109870653, 3826587512},
    ["PVP_Tokyo"] = {125537938344868, 4524359706},
    ["PVP_Office"] = {113296614204646, 5289429734},
    ["PVP_Blank"] = {0, 10938546013},
    ["ZMP_NYC"] = {84460047957624, 4747446334},
    ["ZME_NYC"] = {84460047957624, 4747446334}
}

local lastCollections = nil

local function BulkScan(retry) -- High performance scanning engine
    -- Prevent scanning in Menu (optimization), but return proper structure
    if game.PlaceId == 16173503753 or game.PlaceId == 2916899287 then
        return {}, {
            FirearmInventoryClass = {},
            FirearmInventoryReplicator = {},
            FirearmInventory = {},
            TurretController = {}
        }
    end

    local now = tick()
    -- Only scan if we don't have a cache OR it's been a long time (10s cooldown)
    if not retry and gcCache and (now - lastScan) < 10 then 
        return {
            ReplicatorService = ReplicatorService,
            BulletService = BulletService,
        }, lastCollections
    end

    local startTime = os_clock()
    
    -- Optimized Scanner: Use filtergc with 'table' filter for 10x faster iteration
    local success, res = pcall(function() return filtergc("table") end)
    if not success then success, res = pcall(function() return getgc(true) end) end
    if not success or type(res) ~= "table" then return end
    
    gcCache = res
    lastScan = now
    
    -- Local results table to avoid frequent global access
    local found = {}
    local collections = {
         FirearmInventoryClass = {},
         FirearmInventoryReplicator = {},
         FirearmInventory = {},
         TurretController = {}
    }

    local count = 0
    for _, obj in pairs(res) do
        count = count + 1
        -- if count % 8000 == 0 then task.wait() end -- Anti-Lag REMOVED
        
        if type(obj) == "table" then
            -- 1. IDENTIFY UNIQUE SERVICES (Fingerprinting via rawget) - ONLY IF MISSING
            
            -- ReplicatorService
            if not ReplicatorService and not found.ReplicatorService and rawget(obj, "Actors") and rawget(obj, "LocalActor") then
                found.ReplicatorService = obj
            
            -- BulletService
            elseif not BulletService and not found.BulletService and rawget(obj, "_multithreadSend") then
                found.BulletService = obj
            
            -- WorldService
            elseif not WorldService and not found.WorldService and rawget(obj, "InactiveWorld") then
                found.WorldService = obj
            
            -- ClientService
            elseif not ClientService and not found.ClientService and rawget(obj, "Clients") and rawget(obj, "LocalClient") then
                found.ClientService = obj
            
            -- VehicleService
            elseif not VehicleService and not found.VehicleService and rawget(obj, "Vehicles") and rawget(obj, "Changed") then
                found.VehicleService = obj
            
            -- EnvironmentService
            elseif not EnvironmentService and not found.EnvironmentService and rawget(obj, "RainDensity") and (rawget(obj, "_lights") or rawget(obj, "_clouds")) then
                found.EnvironmentService = obj
            
            -- InventoryService
            elseif not InventoryService and not found.InventoryService and rawget(obj, "Inventories") and (rawget(obj, "_hasRadio") or rawget(obj, "_droppedItems")) then
                found.InventoryService = obj
            
            -- CalibersTable
            elseif not CalibersTable and not found.CalibersTable and rawget(obj, "shotgun_12gauge_00buck") then
                found.CalibersTable = obj
            
            -- EffectsService
            elseif not EffectsService and not found.EffectsService and rawget(obj, "BulletLand") and rawget(obj, "BulletFired") then
                found.EffectsService = obj
            
            -- Network
            elseif not Network and not found.Network and rawget(obj, "FireServer") and rawget(obj, "_events") then
                found.Network = obj
            
            -- ControllerService
            elseif not ControllerService and not found.ControllerService and rawget(obj, "Controller") and type(obj.Controller) == "table" and rawget(obj.Controller, "Update") then
                found.ControllerService = obj
                
            -- 2. IDENTIFY CLASSES AND PROTOTYPES (Only scan if needed)
            elseif not CharacterController and not found.CharacterController and rawget(obj, "SetCFrame") and rawget(obj, "SetVehicleGoal") then
                if rawget(obj, "__index") == obj or not rawget(obj, "Parent") then 
                    found.CharacterController = obj 
                end
            elseif not FirearmInventoryClass and not found.FirearmInventoryClass and rawget(obj, "Equip") and rawget(obj, "Unequip") and rawget(obj, "Discharge") then
                found.FirearmInventoryClass = obj
            elseif not Recoiler and not found.Recoiler and rawget(obj, "Impulse") and rawget(obj, "TimeSkip") and rawget(obj, "GetCameraAdjustment") then
                found.Recoiler = obj
            elseif not ActorClass and not found.ActorClass and rawget(obj, "Update") and rawget(obj, "_updateLOD") then
                found.ActorClass = obj
            elseif not CharacterCamera and not found.CharacterCamera and rawget(obj, "Update") and rawget(obj, "Render") and rawget(obj, "Watch") then
                found.CharacterCamera = obj
            elseif not TurretController and not found.TurretController and rawget(obj, "_discharge") and rawget(obj, "Discharge") then
                found.TurretController = obj
            
            -- 3. COLLECT INSTANCES (ALWAYS SCAN to update lists)
            elseif rawget(obj, "_firearm") and rawget(obj, "_actor") then
                table.insert(collections.FirearmInventoryReplicator, obj)
            elseif rawget(obj, "_firearm") and rawget(obj, "_bulletsShot") then
                table.insert(collections.FirearmInventory, obj)
            elseif rawget(obj, "_turret") and rawget(obj, "_config") then
                table.insert(collections.TurretController, obj)
            end
        end
    end

    -- Update Globals & Log Found Services
    local function logService(name, obj)
        if obj then
            print(string_format("[BulkScan] Found %s", name))
            return obj
        end
    end

    ReplicatorService = logService("ReplicatorService", found.ReplicatorService) or ReplicatorService
    BulletService = logService("BulletService", found.BulletService) or BulletService
    WorldService = logService("WorldService", found.WorldService) or WorldService
    ClientService = logService("ClientService", found.ClientService) or ClientService
    VehicleService = logService("VehicleService", found.VehicleService) or VehicleService
    EnvironmentService = logService("EnvironmentService", found.EnvironmentService) or EnvironmentService
    InventoryService = logService("InventoryService", found.InventoryService) or InventoryService
    CalibersTable = logService("CalibersTable", found.CalibersTable) or CalibersTable
    EffectsService = logService("EffectsService", found.EffectsService) or EffectsService
    CharacterController = logService("CharacterController", found.CharacterController) or CharacterController
    ControllerService = logService("ControllerService", found.ControllerService) or ControllerService
    FirearmInventoryClass = logService("FirearmInventoryClass", found.FirearmInventoryClass) or FirearmInventoryClass
    Recoiler = logService("Recoiler", found.Recoiler) or Recoiler
    ActorClass = logService("ActorClass", found.ActorClass) or ActorClass
    TurretController = logService("TurretController", found.TurretController) or TurretController
    CharacterCamera = logService("CharacterCamera", found.CharacterCamera) or (shared.Engine and shared.Engine.CharacterCamera)
    Network = logService("Network", found.Network) or Network
    
    FirearmInventory = collections.FirearmInventory
    lastCollections = collections
    
    print(string_format("[BulkScan] Memory scan took: %.1fms ", (os_clock() - startTime) * 1000))
    
    -- RETRY MECHANISM IF CRITICAL SERVICES MISSING
    if not found.ReplicatorService or not found.BulletService or not found.CharacterController then
        -- Clean up local references to big table
        res = nil 
        found = nil
        collections = nil
        
        if not retry then
            task.spawn(function()
                while not (ReplicatorService and BulletService and CharacterController) do
                    -- IMMEDIATE MEMORY CLEANUP
                    gcCache = nil -- Drop the huge table from cache
                    pcall(function() collectgarbage("count"); collectgarbage("collect") end) -- Force Aggressive GC
                    
                    print("[BulkScan] Critical services missing. FORCE GC executed. Retrying in 2s...")
                    task.wait(2)
                    
                    -- Force retry scan
                    BulkScan(true)
                end
                
                print("[BulkScan] All critical services found!")
            end)
        end
    end

    return found, collections
end

-- Helper to find Services via ModuleScript (getnilinstances)
-- Helper to find Services via ModuleScript (getnilinstances)
local function FindService_Module(name)
    -- Disabled 'require' based scan as per request
    -- Using BulkScan as primary method
    return nil
end

-- Kept for compatibility
local function FindService(serviceName, manualCache)
    if not ReplicatorService then BulkScan() end
    if serviceName == "ReplicatorService" then return ReplicatorService
    elseif serviceName == "BulletService" then return BulletService
    elseif serviceName == "CharacterController" then return CharacterController
    elseif serviceName == "InventoryService" then return InventoryService
    end
    return nil
end

--[[
    FORWARD DECLARATIONS
]]

-- Moved GetMuzzlePosition here for visibility
function GetMuzzlePosition()
    -- Priority 0: Active Equipped Controller from Cached WeaponManager
    -- This avoids scanning the huge FirearmInventory table every frame
    if WeaponManager.Equipped then
        local handler = WeaponManager.Equipped
        if handler._originalMuzzle then
            local success, cf = pcall(handler._originalMuzzle, handler)
            if success and cf then return cf.Position end
        elseif handler.GetMuzzleCFrame then
            local success, cf = pcall(handler.GetMuzzleCFrame, handler)
            if success and cf then return cf.Position end
        end
    end

    -- Fallback: Start with Camera Position to avoid nil errors if logic fails
    return Camera.CFrame.Position
end

function GetSecureContainer()
    if SecureESPContainer and SecureESPContainer.Parent then 
        return SecureESPContainer 
    end

    local function TryCreate(parent)
        local success, result = pcall(function()
            local f = parent:FindFirstChild("ESP_Cache")
            if not f then
                f = Instance.new("ScreenGui")
                f.Name = "ESP_Cache"
                f.ResetOnSpawn = false
                -- Safe syn.protect_gui call
                if (parent.Name == "CoreGui" or parent.Name == "RobloxGui") and type(syn) == "table" and syn.protect_gui then 
                    pcall(function() syn.protect_gui(f) end) 
                end
                f.Parent = parent
            end
            return f
        end)
        if success and result then return result end
        return nil
    end

    -- Prio 1: specific executor gui container (gethui)
    local success, hui = pcall(function() return gethui() end)
    if success and hui then
        local folder = TryCreate(hui)
        if folder then 
            SecureESPContainer = folder
            return folder 
        end
    end

    -- Prio 2: CoreGui (if accessible)
    local success2, core = pcall(function() return game:GetService("CoreGui") end)
    if success2 and core then
        local folder = TryCreate(core)
        if folder then
            SecureESPContainer = folder
            return folder
        end
    end

    -- Prio 3: PlayerGui (Fallback)
    if LocalPlayer then
        local pGui = LocalPlayer:FindFirstChild("PlayerGui")
        if pGui then
            local folder = TryCreate(pGui)
            if folder then
                SecureESPContainer = folder
                return folder
            end
        end
    end

    return nil
end

local function InitializeServices()
    -- Optimized Bulk Memory Scan
    local found, collections = BulkScan()
    if not found then return false end
    
    -- Sync with legacy globals
    CalibersTable = found.CalibersTable
    
    -- Fallback: Find Critical Services via ModuleScript if missed by GC
    if not ControllerService then
        ControllerService = FindService_Module("ControllerService")
        if ControllerService then print("[Init] Found ControllerService via ModuleScript") end
    end
    
    if not Network then
         -- Network is sometimes named differently or is a child of something
         local net = FindService_Module("network")
         if not net then net = FindService_Module("Network") end
         if net then 
            Network = net 
            print("[Init] Found Network via ModuleScript")
         end
    end
    
    RefreshFirearmControllers(true)
    SetupHooks() 

    -- 4. Hook BulletService (Global Silent Aim) - Initialize ONCE
    if BulletService then
         -- Only save original if it doesn't exist (prevents recursion on re-execution)
         if not BulletService._originalDischarge then
             BulletService._originalDischarge = BulletService.Discharge
         end
        
         local lastUsedCaliber, lastUsedVelocity = nil, 2000
         BulletService.Discharge = function(self, originCF, p49, p50, p51, p52, p53, p54, p55, p56, p57)
            local muzzlePos 
            
            if (p51) and (Config.SilentAim or Config.RageMode) and (math.random(1, 100) <= Config.SilentAimHitChance) then
                p57 = false 
                
                local targetHead = ActorManager.SelectedTarget_RB or ActorManager.SelectedTarget_SA
                local targetActor = ActorManager.SelectedActor_RB or ActorManager.SelectedActor_SA
                
                if targetHead then 
                     local targetPos = targetHead.Position
                     local muzzle_velocity = 2000
                     
                     -- Caching for high RPM/High Pellet count performance
                     if p49 == lastUsedCaliber then
                         muzzle_velocity = lastUsedVelocity
                     elseif p49 and BulletService.GetInfo then
                          local vel = BulletService:GetInfo(p49, p50)
                          if vel and vel > 0 then 
                              muzzle_velocity = vel 
                              lastUsedCaliber = p49
                              lastUsedVelocity = vel
                          end
                     end
                     
                     local targetVelocity = getgenv()._lastPredVel or Vector3_new(0,0,0)
                     local gravity = 32.2 
                      
                     if originCF then muzzlePos = originCF.Position end
                     if not muzzlePos and GetMuzzlePosition then 
                         muzzlePos = GetMuzzlePosition() 
                     end
                     
                     if muzzlePos and targetPos then
                         local aimPos, _ = SolveLead(muzzlePos, targetPos, targetVelocity, muzzle_velocity, gravity)
                         getgenv().LastSilentAimUpdate = tick()
                         originCF = CFrame_new(muzzlePos, aimPos)

                         -- Target Acquisition Visual
                         if not ActorManager._lastRBLog or (tick() - ActorManager._lastRBLog > 5) then
                             print(string_format("[Ragebot] TARGET ACQUIRED: %s", targetActor.OwnerName or "NPC"))
                             ActorManager._lastRBLog = tick()
                         end
                     end
                end
            end
            return BulletService._originalDischarge(self, originCF, p49, p50, p51, p52, p53, p54, p55, p56, p57)
        end
        getgenv()._BulletServiceHooked = true
    end
    
    -- Recoiler hooks moved to SetupAggressiveHooks() to avoid duplication
    
    return true
end



-- Controller Cache
local AllControllersCache = {
    Visuals = {},
    Logic = {}
}

RefreshFirearmControllers = function(silent)
    -- Throttling
    if tick() - WeaponManager.LastScan < 0.2 then return end
    WeaponManager.LastScan = tick()

    -- Optimized: Use BulkScan and its collections
    local _, collections = BulkScan()
    if not collections then return end
    
    -- Sync Caches
    WeaponManager.Visuals = collections.FirearmInventoryReplicator
    WeaponManager.Logic = collections.FirearmInventory
    
    -- Include Turrets in Visuals
    for _, t in ipairs(collections.TurretController) do
        table.insert(WeaponManager.Visuals, t)
    end
    
    -- Include Active Turret from LocalActor
    if ReplicatorService and ReplicatorService.LocalActor then
        local myActor = ReplicatorService.LocalActor
        if myActor.Turret and type(myActor.Turret) == "table" and myActor.Turret._config then
            table.insert(WeaponManager.Visuals, myActor.Turret)
        end
    end
    
    -- Sync with legacy globals
    AllControllersCache.Visuals = WeaponManager.Visuals
    AllControllersCache.Logic = WeaponManager.Logic
    FirearmInventory = WeaponManager.Logic
    
    -- Update Equipped reference
    if InventoryService and InventoryService.Equipped then
        WeaponManager.Equipped = InventoryService.Equipped.Handler
    end
end



-- Projectile lead and bullet drop calculation
local function SolveLead(sourcePos, targetPos, targetVelocity, bulletSpeed, gravity)
    local distance = (targetPos - sourcePos).Magnitude
    local time = distance / bulletSpeed
    
    local predictedPos = targetPos
    if targetVelocity and targetVelocity.Magnitude > 0.1 then
        predictedPos = targetPos + (targetVelocity * time)
    end
    
    distance = (predictedPos - sourcePos).Magnitude
    time = distance / bulletSpeed
    if targetVelocity and targetVelocity.Magnitude > 0.1 then
        predictedPos = targetPos + (targetVelocity * time)
    end
    
    local dropCompensation = 0.5 * gravity * (time * time)
    predictedPos = predictedPos + Vector3_new(0, dropCompensation, 0)
    
    return predictedPos, time
end

-- Calculate expected damage based on caliber dropoff
-- GetBulletDamage was unused and removed

-- Calculate damage based on caliber, distance, and body part
-- Mirrors BulletService.GetDamageGraph logic from game

--[[
    ENTITY CLASSIFICATION
]]
local function GetEntityType(actor)
    -- Check if zombie
    if actor.Zombie == true then
        return "Zombie"
    end
    
    -- Check if player (has valid Player owner in game)
    if actor.Owner and Players:GetPlayerByUserId(actor.Owner.UserId) then
        return "Player"
    end
    
    -- Check if NPC (has owner but not a real player, or AI-controlled)
    if actor.Owner or actor.OwnerName then
        return "NPC"
    end
    
    return "Unknown"
end

local function IsTeammate(actor, cachedLocalSquad)
    -- Rule 0: Zombies are NEVER teammates
    if actor.Zombie == true then return false end

    -- Detect if it's a real player
    local ownerPlayer = actor.Owner and Players:GetPlayerByUserId(actor.Owner.UserId)
    local isRealPlayer = ownerPlayer ~= nil

    -- Rule 1: Friendly Maps (Only real PLAYERS are teammates)
    if isRealPlayer and (Config.CurrentMapName == "OW_Ronograd" or Config.CurrentMapName == "ZME_NYC") then
        return true
    end

    -- Rule 2: Team Check (PVP)
    if isRealPlayer and ownerPlayer.Team and LocalPlayer.Team and ownerPlayer.Team == LocalPlayer.Team then
        return true
    end

    -- Rule 3: ClientService Squad Check
    if isRealPlayer and cachedLocalSquad and cachedLocalSquad ~= "" then
        if ClientService.Clients and ClientService.Clients[ownerPlayer] then
             local targetClient = ClientService.Clients[ownerPlayer]
             return targetClient.Squad == cachedLocalSquad
        end
    end
    
    return false
end

--[[
    SPATIAL PARTITIONING HELPERS
]]  
local function GetSectorKey(position, sectorSize)
    local x = math.floor(position.X / sectorSize)
    local z = math.floor(position.Z / sectorSize)
    return x * 65536 + z -- Numeric key: faster hash than string concat
end

local function DecodeSectorKey(key)
    -- Decode numeric key back to x, z
    local x = math.floor(key / 65536)
    local z = key - x * 65536
    -- Handle negative z (two's complement style)
    if z > 32767 then z = z - 65536 end
    return x, z
end

--[[
    ACTOR MANAGER (Entity Caching System)
    Decouples heavy entity iteration from RenderStepped
]]
function ActorManager:Update(dt)
    if not ReplicatorService or not ReplicatorService.Actors then return end
    
    local now = tick()
    
    -- Initialize spatial partitioning fields (once)
    if not self._sectors then
        self._sectors = {}           -- Sector grid
        self._sectorSize = 512       -- Sector size (studs)
        self._playerSector = nil     -- Current player sector
        self._targetQueue = {}       -- Top 3 pre-cached targets
        self._lastSectorUpdate = 0
    end
    
    -- Optimize Map Detection (Every 10s)
    if not self._lastMapUpdate or (now - self._lastMapUpdate > 10) then
        Config.CurrentMapType = DetectMapType()
        self._lastMapUpdate = now
    end

    -- 1. Refresh Entity Lists (Every 0.5s)
    if not self._lastListUpdate or (now - self._lastListUpdate > 0.5) then
        table.clear(self.Enemies)
        table.clear(self.Teammates)
        table.clear(self.Vehicles)
        
        -- SPATIAL PARTITIONING: Clear and rebuild sectors
        table.clear(self._sectors)
        
        local localSquad = nil
        if ClientService and ClientService.LocalClient then
            localSquad = ClientService.LocalClient.Squad
        end
        
        local localPlayer = LocalPlayer
        
        for _, actor in pairs(ReplicatorService.Actors) do
            if not actor or not actor.Alive or not actor.Character then continue end
            if actor.Owner == localPlayer then continue end
            
            actor._entityType = GetEntityType(actor)
            actor._isTeammate = IsTeammate(actor, localSquad)
            
            -- OPTIMIZATION: Cache visibility check (runs every 0.5s)
            if ShouldShowEntity then
                actor._cachedShow = ShouldShowEntity(actor, actor._entityType, localSquad)
            else
                actor._cachedShow = true
            end
            
            if actor._isTeammate then
                table.insert(self.Teammates, actor)
            else
                table.insert(self.Enemies, actor)
                
                -- SPATIAL PARTITIONING: Bucket enemy into sector
                -- OPTIMIZATION: actor.Position is engine-interpolated; actor.RootPart is direct ref (no FindFirstChild)
                local actorPos = actor.Position or (actor.RootPart and actor.RootPart.Position)
                if actorPos then
                    local sectorKey = GetSectorKey(actorPos, self._sectorSize)
                    if not self._sectors[sectorKey] then
                        self._sectors[sectorKey] = {}
                    end
                    table.insert(self._sectors[sectorKey], actor)
                end
            end
        end
        
        if VehicleService and VehicleService.Vehicles then
            for _, veh in pairs(VehicleService.Vehicles) do
                table.insert(self.Vehicles, veh)
            end
        end
        
        -- SPATIAL PARTITIONING: Update player sector
        local playerPos = Camera.CFrame.Position
        self._playerSector = GetSectorKey(playerPos, self._sectorSize)
        
        self._lastListUpdate = now
        self.Initialized = true
    end

    -- 2. Update Combat Targets (OPTIMIZED)
    -- Silent Aim: Balanced refresh (0.05s = 20Hz)
    if self.Initialized and (not self._lastTargetUpdate or (now - self._lastTargetUpdate > 0.05)) then
        if GetCombatTarget then
            if Config.SilentAim or Config.ShowPrediction then
                local target, actor = GetCombatTarget("SilentAim")
                self.SelectedTarget_SA = target
                self.SelectedActor_SA = actor
            else
                self.SelectedTarget_SA = nil
                self.SelectedActor_SA = nil
            end
        end
        self._lastTargetUpdate = now
    end
    
    -- Ragebot: Ultra-High-Speed Target Acquisition (60Hz = 0.016s)
    -- Ragebot: Direct scan (persistence handled inside GetCombatTarget)
    if self.Initialized and Config.RageMode and GetCombatTarget then
        local updateInterval = 0.016 -- 60Hz update rate (was 30Hz)
        
        if not self._lastRageUpdate or (now - self._lastRageUpdate > updateInterval) then
            local target, actor = GetCombatTarget("Rage")
            self.SelectedTarget_RB = target
            self.SelectedActor_RB = actor
            self._lastRageUpdate = now
        end
    elseif not Config.RageMode then
        self.SelectedTarget_RB = nil
        self.SelectedActor_RB = nil
    end
end

--[[
    WALLCHECK LOGIC (Optimized with Penetration)
]]
local CollectionService = game:GetService("CollectionService")

local function IsIgnored(part)
    if not part then return false end
    -- CharacterCast collision group handles most filtering (debris, vehicles, particles).
    -- Only check transparency and glass name as edge cases.
    if part.Transparency > 0.9 then return true end
    if part.Name == "Glass" or part.Name == "Window" then return true end
    return false
end

local VisCache = {}
local VisRayParams = RaycastParams.new()
VisRayParams.FilterType = Enum.RaycastFilterType.Exclude
VisRayParams.CollisionGroup = "CharacterCast" -- Match game's own raycast group (ActorClass.lua:1114)
VisRayParams.IgnoreWater = true

-- Cache Cleanup (Prevent Memory Bloat)
local LastVisCacheCleanup = 0

-- Pre-allocate filter table to reduce garbage collection
local VisFilterTable = table.create(16) 

local function IsVisible(targetActor, targetPart, origin, isPriority)
    if not targetPart or not targetPart.Parent then return false end
    
    local now = tick()
    local uid = targetActor.UID
    
    -- CACHE CLEANUP: Prevent memory bloat (every 2 seconds)
    if now - LastVisCacheCleanup > 2 then
        for k, v in pairs(VisCache) do
            if now - v.last > 5 then -- Remove entries older than 5s
                VisCache[k] = nil
            end
        end
        LastVisCacheCleanup = now
    end
    
    -- PRIORITY MODE: Active target gets fresh raycast, skips cache
    if not isPriority then
        -- Non-priority: Use cache (for search candidates)
        if VisCache[uid] and (now - VisCache[uid].last < 0.05) then
            return VisCache[uid].result
        end
    end

    -- RAYCAST BUDGET CHECK (priority targets don't consume budget)
    if not isPriority then
        if getgenv().RaycastBudget <= 0 then
            return false -- Skip visibility check if budget exhausted
        end
        getgenv().RaycastBudget = getgenv().RaycastBudget - 1
    end

    local character = targetPart.Parent
    local originPos = origin or Camera.CFrame.Position
    local direction = (targetPart.Position - originPos)
    -- OPTIMIZATION: Use engine's LOD_Distance as fast pre-check (avoids Magnitude calc for far targets)
    local dist = targetActor.LOD_Distance or direction.Magnitude
    
    -- Engine Optimization: Use game's own visibility check first
    if not targetActor.ViewportOnScreen and (dist > 100) and not Config.RageMode then
         VisCache[uid] = { result = false, last = now }
         return false
    end

    -- Fast Check: Reset filter table without creating new one
    table.clear(VisFilterTable)
    table.insert(VisFilterTable, Camera)
    if LocalPlayer.Character then table.insert(VisFilterTable, LocalPlayer.Character) end
    table.insert(VisFilterTable, character) -- Ignore target char to hit parts behind accessories
    
    if ReplicatorService and ReplicatorService.LocalActor then
        local myActor = ReplicatorService.LocalActor
        if myActor.Seat and myActor.Seat.Model then
             table.insert(VisFilterTable, myActor.Seat.Model)
        end
    end

    VisRayParams.FilterDescendantsInstances = VisFilterTable

    local currentPos = originPos
    local isVisible = false
    
    -- Optimization: Single Raycast first (most common case)
    local result = Workspace:Raycast(currentPos, direction, VisRayParams)
    
    if not result then 
        isVisible = true 
    elseif result.Instance:IsDescendantOf(character) then
        isVisible = true
    else
        -- Wallbang/Penetration Logic (Only if initial check fails)
        -- Limit to 2 penetrations for performance
        local penetrations = 0
        local dirUnit = direction.Unit
        local remainingDist = dist
        
        while penetrations < 2 do
            if not result then 
                isVisible = true; break 
            end
            
            local hitPart = result.Instance
            if hitPart:IsDescendantOf(character) then
                isVisible = true; break
            end
            
            if IsIgnored(hitPart) then
                table.insert(VisFilterTable, hitPart)
                VisRayParams.FilterDescendantsInstances = VisFilterTable
                penetrations = penetrations + 1
                
                -- Raycast again from hit position slightly forward
                result = Workspace:Raycast(result.Position + (dirUnit * 0.1), direction - (result.Position - currentPos), VisRayParams)
            else
                isVisible = false; break
            end
        end
    end
    
    VisCache[uid] = { result = isVisible, last = now }
    return isVisible
end

--[[
    COMBAT TARGETING (OPTIMIZED)
    High-performance target acquisition with pre-filtering and engine-calculated distances
]]
GetCombatTarget = function(mode)
    -- Reset Raycast Budget (Max 20 per frame for ragebot responsiveness)
    getgenv().RaycastBudget = (mode == "Rage") and 20 or 12

    local cfg = Config
    local targetPartName = (mode == "Rage") and cfg.Rage_TargetPart or cfg.SilentAimTargetPart or "Head"
    
    local useFOV = (mode == "SilentAim")
    local fovLimit = cfg.SilentAimFOV
    local fovLimitSq = fovLimit * fovLimit 
    local maxDistance = (mode == "Rage") and cfg.Rage_Range or cfg.MaxDistance or 2000
    local maxDistSq = maxDistance * maxDistance -- Pre-calculate for faster comparison
    
    local checkOrigin = Camera.CFrame.Position
    local muzzle = GetMuzzlePosition()
    if muzzle then checkOrigin = muzzle end

    if not ActorManager.Enemies or #ActorManager.Enemies == 0 then return nil, nil end
    
    -- OPTIMIZATION: Validate Active Target First (1 Priority Raycast)
    -- If current target still valid, return immediately (saves 10-19 raycasts!)
    if mode == "Rage" and ActorManager.SelectedActor_RB then
        local activeActor = ActorManager.SelectedActor_RB
        
        -- Check if this target was marked for ignore (e.g. single-shot switching)
        if ignoredTargets and ignoredTargets[activeActor.UID] and tick() < ignoredTargets[activeActor.UID] then
            ActorManager.SelectedActor_RB = nil
            ActorManager.SelectedTarget_RB = nil
        -- Quick validation checks
        elseif activeActor.Alive and activeActor.Character then
            local dist = activeActor.LOD_Distance
            if not dist or dist <= 0 then
                dist = (activeActor.Position - checkOrigin).Magnitude
            end
            
            -- Still in range?
            if dist <= maxDistance then
                local targetPart = activeActor.Parts[targetPartName]
                
                -- PRIORITY VISIBILITY CHECK (doesn't consume budget)
                if targetPart and IsVisible(activeActor, targetPart, checkOrigin, true) then
                    -- Active target still valid! Return early
                    return targetPart, activeActor
                end
            end
            
            -- Active target invalid, clear it and search for new one
            ActorManager.SelectedActor_RB = nil
            ActorManager.SelectedTarget_RB = nil
        else
            -- Active target invalid, clear it and search for new one
            ActorManager.SelectedActor_RB = nil
            ActorManager.SelectedTarget_RB = nil
        end
    end
    
    -- PRE-ALLOCATE: Reuse candidates table to reduce GC pressure

    local candidates = getgenv()._targetCandidates or table.create(64)
    table.clear(candidates)
    getgenv()._targetCandidates = candidates
    
    local now = tick()
    local ignoredTargets = ActorManager._ignoredTargets
    local mouse, mouseX, mouseY
    
    if useFOV then
        mouse = UserInputService:GetMouseLocation()
        mouseX, mouseY = mouse.X, mouse.Y
    end
    
    
    -- SPATIAL PARTITIONING: Get enemies from nearby sectors only

    local enemyList
    if mode == "Rage" and ActorManager._sectors and ActorManager._playerSector then
        -- Reuse cached table to avoid GC
        enemyList = getgenv()._cachedEnemyList or table.create(100)
        table.clear(enemyList)
        getgenv()._cachedEnemyList = enemyList
        
        local px, pz = DecodeSectorKey(ActorManager._playerSector)
        for dx = -1, 1 do
            for dz = -1, 1 do
                 local key = (px + dx) * 65536 + (pz + dz)
                 local sectorEnemies = ActorManager._sectors[key]
                 if sectorEnemies then
                    for _, actor in ipairs(sectorEnemies) do
                        table.insert(enemyList, actor)
                    end
                 end
            end
        end
        
        -- Fallback: If no enemies in nearby sectors, use full list
        if #enemyList == 0 then
            enemyList = ActorManager.Enemies
        end
    else
        -- Silent Aim or no sectors: use full list
        enemyList = ActorManager.Enemies
    end
    
    -- FAST PATH: Single enemy in Rage mode = skip candidate table entirely
    if mode == "Rage" and #enemyList == 1 then
        local actor = enemyList[1]
        if actor.Alive and actor.Character and actor._cachedShow ~= false then
            local dist = actor.LOD_Distance or 9999
            if dist <= maxDistance then
                local part = actor.Parts and actor.Parts[targetPartName]
                if not part then part = actor.Parts and (actor.Parts.Head or actor.Parts.UpperTorso) end
                if part and part.Parent and IsVisible(actor, part, checkOrigin) then
                    return part, actor
                end
            end
        end
    end
    
    -- 1. FAST PRE-FILTER & SCORE (Single pass, minimal allocations)
    for _, actor in pairs(enemyList) do
         -- Quick alive check
         if not actor.Alive then continue end
         
         -- Ignored targets check (with expiry cleanup)
         if ignoredTargets then
             local ignoreUntil = ignoredTargets[actor.UID]
             if ignoreUntil then
                 if now < ignoreUntil then
                     continue
                 else
                     ignoredTargets[actor.UID] = nil -- Expired - cleanup
                     -- Also reset damage tracking for this target
                     if ActorManager._rageDmg then ActorManager._rageDmg[actor.UID] = nil end
                     if ActorManager._rageShots then ActorManager._rageShots[actor.UID] = nil end
                     if ActorManager._rageLast then ActorManager._rageLast[actor.UID] = nil end
                 end
             end
         end
         
         local char = actor.Character
         if not char then continue end
         
         -- OPTIMIZATION: Use engine-calculated LOD_Distance if available (saves magnitude calc!)
         local dist = actor.LOD_Distance
         if not dist or dist <= 0 then
             -- Fallback: Calculate manually only if engine value missing
              -- OPTIMIZATION: Use actor.Position or actor.RootPart (direct engine ref, no FindFirstChild)
              local actorPos = actor.Position
              if not actorPos then
                  local root = actor.RootPart or (actor.Parts and actor.Parts.Head)
                  if not root then continue end
                  actorPos = root.Position
              end
              local delta = actorPos - checkOrigin
              dist = math.sqrt(delta.X*delta.X + delta.Y*delta.Y + delta.Z*delta.Z)
         end
         
         -- Distance pre-filter (using squared distance when possible)
         if dist > maxDistance then continue end
         
         -- RAGEBOT: 360° TARGET ACQUISITION (No FOV/Viewport restrictions!)
         -- For Ragebot (mode == "Rage"), useFOV = false, so targets in ALL directions
         -- are valid. Only limited by Rage_Range distance, not screen position.
         local score = dist -- Default: closest first (Ragebot)
         
         -- FOV filtering for Silent Aim
         if useFOV then
              -- Early viewport check using engine data
              if not actor.ViewportOnScreen and dist > 50 then continue end
              
              -- OPTIMIZATION: Use engine-interpolated Position instead of PrimaryPart lookup
              local rootPos = actor.Position
              if not rootPos then
                  local root = char.PrimaryPart or char:FindFirstChild("Head")
                  if not root then continue end
                  rootPos = root.Position
              end
              
              local pos, onScreen = Camera:WorldToViewportPoint(rootPos)
              if not onScreen then continue end
              
              -- Screen distance (squared for performance)
              local dx = pos.X - mouseX
              local dy = pos.Y - mouseY
              local screenDistSq = (dx*dx) + (dy*dy)
              
              if screenDistSq > fovLimitSq then continue end
              score = screenDistSq -- Silent Aim: closest to crosshair
         end
         
         -- Store candidate with pre-calculated score
         table.insert(candidates, { 
             actor = actor, 
             score = score, 
             char = char,
             dist = dist -- Cache for later use
         })
    end
    
    -- Early exit if no candidates
    if #candidates == 0 then return nil, nil end
    
    -- 2. OPTIMIZED SORT: Use ascending score (best target = lowest score)
    -- OPTIMIZATION: Linear min-scan instead of O(n log n) sort
    -- Ragebot only needs the best target, not a sorted list
    local bestIdx = 1
    local bestScore = candidates[1].score
    for ci = 2, #candidates do
        if candidates[ci].score < bestScore then
            bestScore = candidates[ci].score
            bestIdx = ci
        end
    end
    -- Swap best to front
    if bestIdx ~= 1 then
        candidates[1], candidates[bestIdx] = candidates[bestIdx], candidates[1]
    end
    
    -- 3. VISIBILITY CHECK (Budget-aware, prioritized order)
    for i = 1, #candidates do
         local candle = candidates[i]
         local actor = candle.actor
         local char = candle.char
         
         -- Find target part (direct table lookup — no hierarchy search)
          local part = actor.Parts and actor.Parts[targetPartName]
          if not part then
              -- Fallback chain via Parts table
              part = (actor.Parts and (actor.Parts["Head"] or actor.Parts["UpperTorso"])) or char:FindFirstChild("Head")
         end
         
         if part and part.Parent then
             -- Perform visibility check (uses raycast budget)
             if IsVisible(actor, part, checkOrigin) then
                 return part, actor -- SUCCESS: Return first visible target
             end
             
             -- Budget exhausted - stop checking
             if getgenv().RaycastBudget <= 0 then break end
         end
    end

    return nil, nil -- No valid target found
end

-- Hook Weapon Controller (GetMuzzleCFrame) - Server Leniency Method
local function HookController(controller)
    if type(controller) ~= "table" then return end
    if controller._hookedMuzzle then return end
    
    -- Safety: Skip turrets (they have their own class hook)
    if rawget(controller, "_turret") or rawget(controller, "_config") then 
        return 
    end
    if controller.GetMuzzleCFrame then
        controller._originalMuzzle = controller.GetMuzzleCFrame
        
        controller.GetMuzzleCFrame = function(self, ...)
            local muzzleCF, v2, v3 = controller._originalMuzzle(self, ...)
            if not muzzleCF then return muzzleCF, v2, v3 end
            -- Determine if this controller is a vehicle weapon
            if self._actor and not self._actor.IsLocalPlayer and ReplicatorService.LocalActor.Character then
                  local hum = ReplicatorService.LocalActor.Character:FindFirstChild("male")
                  if hum and hum.SeatPart and hum.SeatPart.Parent == self._actor then
                      isVehicleWeapon = true
                  end
            end

            local isYours = false
            if self._actor and self._actor.IsLocalPlayer then 
                isYours = true 
            end
            
            -- 2. Check if it's a vehicle we are driving/gunning
            if not isYours and isVehicleWeapon then
                isYours = true
            end
            
            -- Combat Targeting (Ragebot priority, then Silent Aim)
            local combatTarget = ActorManager.SelectedTarget_RB or ActorManager.SelectedTarget_SA
            local targetActor = ActorManager.SelectedActor_RB or ActorManager.SelectedActor_SA
            
            -- Return muzzle CFrame unmodified to prevent "Auto Shoot" visual snapping
            -- Silent Aim Logic moved to BulletService.Discharge
            -- UPDATE: We MUST modify this for the Server to accept the hit (OriginCFrame validation)
             if (Config.SilentAim or Config.RageMode) and combatTarget and targetActor then
                 local targetHead = combatTarget
                 
                 -- Calculate Aim Position with Prediction
                 local targetPos = targetHead.Position
                 local gravity = 32.2 -- Hardcoded engine gravity
                 local muzzle_velocity = 2000
                 
                 if self._firearm and self._firearm.Tune then
                     local caliberName = self._firearm.Tune.Caliber
                     local barrelLen = self._firearm.Tune.Barrel
                     
                     if BulletService and BulletService.GetInfo then
                         local success, vel = pcall(function() return BulletService:GetInfo(caliberName, barrelLen) end)
                          if success and vel then muzzle_velocity = vel end
                     end
                 end
                 
                 local targetVelocity = Vector3_new(0,0,0)
                 if targetActor._oldDirection then
                      targetVelocity = targetActor._oldDirection * 60
                 elseif targetHead.Parent and targetHead.Parent.PrimaryPart then
                      targetVelocity = targetHead.Parent.PrimaryPart.AssemblyLinearVelocity or Vector3_new(0,0,0)
                 end
                 
                 if not muzzleCF then return end -- Safety check
                 
                 local aimPos, travelTime = SolveLead(muzzleCF.Position, targetPos, targetVelocity, muzzle_velocity, gravity)
                 
                 -- Manual compensation removed to avoid double-application. 
                 -- SolveLead handles Config.BulletDrop internally.


                 -- Calculate Zeroing Angle to subtract (ONLY IF ADS IS TRUE)
                 local zeroAngle = 0
                 local actor = self._actor
                 
                 -- Game only applies zeroing when ADS is true
                 if actor and actor.ADS and actor.ViewModel and actor.ViewModel.Zero then
                     local zeroData = actor.ViewModel.Zero
                     local zeroDist = zeroData
                     if type(zeroData) == "table" then zeroDist = zeroData[4] end
                     
                     if zeroDist then
                        local v177 = zeroDist * gravity / (muzzle_velocity ^ 2)
                        zeroAngle = math.asin(math.clamp(v177, -1, 1)) * 0.5
                     end
                 end
                 
                 muzzleCF = CFrame_new(muzzleCF.Position, aimPos) * CFrame.Angles(-zeroAngle, 0, 0)
            end

            return muzzleCF, v2, v3
        end
        controller._hookedMuzzle = true
    elseif controller._discharge then
         -- Hooking _discharge logic
         controller._originalDischarge = controller._discharge
         
         controller._discharge = function(self, active)
             self._firing = active -- Set firing flag
             local r = controller._originalDischarge(self, active)
             
             -- Trigger Combat Logic on discharge
             if active and (Config.SilentAim or Config.RageMode) and (math.random(1, 100) <= Config.SilentAimHitChance) then
                  local targetHead = ActorManager.SelectedTarget_RB or ActorManager.SelectedTarget_SA
                  local targetActor = ActorManager.SelectedActor_RB or ActorManager.SelectedActor_SA
                  
                  if targetHead and targetHead.Parent then
                       -- Calculate Direction to Target
                       local muzzlePos = Camera.CFrame.Position -- Fallback if no Muzzle
                       -- Try to find Muzzle
                       if self._actor and self._actor.Character then
                           -- OPTIMIZATION: actor.RootPart is direct engine ref (no FindFirstChild)
                           local tool = self._actor.RootPart or self._actor.Character.PrimaryPart
                           if tool then muzzlePos = tool.Position end
                       end
                       
                       local targetPos = targetHead.Position
                       local direction = (targetPos - muzzlePos).Unit
                       
                       -- Force Character Rotation (Client Side Visual)
                       if self._actor and self._actor.IsLocalPlayer and ReplicatorService.LocalActor.Character then
                           local root = ReplicatorService.LocalActor.Character.PrimaryPart
                           if root then
                               local yaw = math.atan2(direction.X, direction.Z)
                               ReplicatorService.LocalActor.Orientation = yaw
                               ReplicatorService.LocalActor.GoalOrientation = yaw
                               root.CFrame = CFrame.new(root.Position, root.Position + direction)
                           end
                       end
                  end
             end
             
             return r
         end
    end
end

-- FOV Circle
local FOVCircle = Drawing.new("Circle")
FOVCircle.Thickness = 1
FOVCircle.NumSides = 60
FOVCircle.Radius = Config.SilentAimFOV
FOVCircle.Filled = false
FOVCircle.Visible = false
FOVCircle.Color = Color3.fromRGB(255, 255, 255)

-- Velocity Cache
getgenv().VelocityCache = {}

-- Prediction Visualizer (Global)
getgenv().PredictionDot = Drawing.new("Circle")
getgenv().PredictionDot.Thickness = 1
getgenv().PredictionDot.NumSides = 10
getgenv().PredictionDot.Radius = 2
getgenv().PredictionDot.Filled = true
getgenv().PredictionDot.Visible = false
getgenv().PredictionDot.Color = Config.PredictionColor

-- Weapon Info Overlay
local WeaponInfoText = Drawing.new("Text")
WeaponInfoText.Size = 18
WeaponInfoText.Center = false
WeaponInfoText.Outline = true
WeaponInfoText.Color = Color3.fromRGB(0, 255, 255)
WeaponInfoText.Position = Vector2.new(50, Camera.ViewportSize.Y - 100)
WeaponInfoText.Visible = false
WeaponInfoText.Font = 2

--[[
    ENGINE HOOKS - Character Controller (Fly & Noclip)
    Hooks into the game's update loop instead of running an external loop.
]]

-- Speed Controller (SpeedPenalty Method - More Compatible)
local SpeedControllerConnection = nil

function EnableSpeedController()
    if SpeedControllerConnection then return end
    
    SpeedControllerConnection = RunService.Heartbeat:Connect(function()
        -- Find local actor
        local actor = nil
        if ReplicatorService and ReplicatorService.LocalActor then
            actor = ReplicatorService.LocalActor
        elseif ControllerService and ControllerService.Controller and ControllerService.Controller._localActor then
            actor = ControllerService.Controller._localActor
        end
        
        if not actor then return end
        
        local walkEnabled = Config.Character_WalkSpeedEnabled
        local sprintEnabled = Config.Character_SprintSpeedEnabled
        
        if not walkEnabled and not sprintEnabled then
            -- Reset to normal
            if actor.SpeedPenalty then
                actor.SpeedPenalty = nil
            end
            return
        end
        
        -- Detect if sprinting (from CharacterController: IsSprinting property)
        local controller = ControllerService and ControllerService.Controller
        local isSprinting = controller and controller.IsSprinting
        
        local multiplier = 1
        
        if sprintEnabled and isSprinting then
            -- Sprint speed hack: User wants X studs/s, base is 16.8
            multiplier = (Config.Character_SprintSpeed or 25) / 16.8
        elseif walkEnabled and not isSprinting then
            -- Walk speed hack: User wants X studs/s, base is 12
            multiplier = (Config.Character_WalkSpeed or 16) / 12
        end
        
        -- Apply as SpeedPenalty (>1 = faster, <1 = slower)
        actor.SpeedPenalty = multiplier
    end)
    
    table.insert(getgenv().BlackhawkESP_Connections, SpeedControllerConnection)
    -- print removed
end

--[[
    AGGRESSIVE GUN MODS & HOOKS
    Implementation based on reference script for maximum reliability
]]
local function ApplyGunMods(firearm, force)
    if not firearm or not firearm._firearm or not firearm._firearm.Tune then return end
    
    -- Force update logic
    firearm._LastTuneTime = tick()

    local tune = firearm._firearm.Tune
    local caliber = firearm._caliber
    local override = firearm._firearm.OverrideTune

    -- Initialize Backups (Tune)
    if not tune._Originals then
        tune._Originals = {
            Recoil_X = tune.Recoil_X, Recoil_Z = tune.Recoil_Z, Recoil_Camera = tune.Recoil_Camera,
            RecoilForce_Tap = tune.RecoilForce_Tap, RecoilForce_Impulse = tune.RecoilForce_Impulse,
            Recoil_Range = tune.Recoil_Range, Recoil_KickBack = tune.Recoil_KickBack,
            Barrel_Spread = tune.Barrel_Spread, Spread = tune.Spread,
            RPM = tune.RPM, Firemodes = tune.Firemodes,
            Bolt = tune.Bolt, Bolt_Action_Pause = tune.Bolt_Action_Pause,
            -- Add potential movement spread keys if they exist
            Hipfire_Spread = tune.Hipfire_Spread,
            Move_Spread = tune.Move_Spread,
            Jump_Spread = tune.Jump_Spread
        }
    end
    
    -- Initialize Backups (Caliber)
    if caliber and not caliber._Originals then
         caliber._Originals = {
             Spread = caliber.Spread,
             RecoilForce = caliber.RecoilForce
         }
    end
    
    if override and not override._Originals then
         override._Originals = {
            Recoil_X = override.Recoil_X, Recoil_Z = override.Recoil_Z, Recoil_Camera = override.Recoil_Camera,
            RecoilForce_Tap = override.RecoilForce_Tap, RecoilForce_Impulse = override.RecoilForce_Impulse,
            Spread = override.Spread, RPM = override.RPM, Firemodes = override.Firemodes
         }
    end

    -- Apply Modifications
    if Config.NoRecoil or Config.SilentAim then
        tune.Recoil_X = 0; tune.Recoil_Y = 0; tune.Recoil_Z = 0; tune.Recoil_Camera = 0
        tune.RecoilForce_Tap = 0; tune.RecoilForce_Impulse = 0
        tune.Recoil_Range = Vector2_new(0, 0); tune.Recoil_KickBack = 0
        tune.FocusRecoil_X = 0; tune.FocusRecoil_Z = 0; tune.FocusRecoil_Camera = 0
        tune.Sway = 0; tune.Sway_ADS = 0
        
        if tune.Bolt then tune.Bolt = 0 end
        if tune.Bolt_Action_Pause then tune.Bolt_Action_Pause = 0 end
        
        if override then
             override.Recoil_X = 0; override.Recoil_Y = 0; override.Recoil_Z = 0; override.Recoil_Camera = 0
             override.RecoilForce_Tap = 0; override.RecoilForce_Impulse = 0
             override.Sway = 0; override.Sway_ADS = 0
        end
        
        if caliber then
             caliber.RecoilForce = 0
        end
    else
        -- Restore Recoil
        for k,v in pairs(tune._Originals) do if tune[k] ~= nil then tune[k] = v end end
        if override and override._Originals then
             for k,v in pairs(override._Originals) do if override[k] ~= nil then override[k] = v end end
        end
        if caliber and caliber._Originals then
             caliber.RecoilForce = caliber._Originals.RecoilForce
        end
    end

    if Config.NoSpread then
        tune.Barrel_Spread = 0
        tune.Spread = 0
        tune.MinSpread = 0
        tune.MaxSpread = 0
        tune.Hipfire_Spread = 0
        tune.Move_Spread = 0
        tune.Jump_Spread = 0
        
        if caliber then
            caliber.Spread = 0
        end
        if override then override.Spread = 0; override.MinSpread = 0; override.MaxSpread = 0 end
    else
        tune.Barrel_Spread = tune._Originals.Barrel_Spread
        tune.Spread = tune._Originals.Spread
        tune.MinSpread = tune._Originals.MinSpread or 0
        tune.MaxSpread = tune._Originals.MaxSpread or 0
        tune.Hipfire_Spread = tune._Originals.Hipfire_Spread
        tune.Move_Spread = tune._Originals.Move_Spread
        tune.Jump_Spread = tune._Originals.Jump_Spread
        
        if caliber and caliber._Originals then
            caliber.Spread = caliber._Originals.Spread
        end
        if override and override._Originals then
            override.Spread = override._Originals.Spread
        end
    end

    if Config.CustomRPM and Config.RPMValue then
        tune.RPM = Config.RPMValue
        if override then override.RPM = Config.RPMValue end
    else
        tune.RPM = tune._Originals.RPM
        if override and override._Originals then override.RPM = override._Originals.RPM end
    end

    if Config.UnlockFiremodes then
        local hasAuto = false
        if tune.Firemodes then
            for _, m in pairs(tune.Firemodes) do if m == 2 then hasAuto = true end end
            if not hasAuto then table.insert(tune.Firemodes, 2) end
        end
        
        if override and override.Firemodes then
            local hasAutoOverride = false
            for _, m in pairs(override.Firemodes) do if m == 2 then hasAutoOverride = true end end
            if not hasAutoOverride then table.insert(override.Firemodes, 2) end
        end
    end
end

local function SetupAggressiveHooks()
    -- 1. Hook FirearmInventoryClass (Permanent Instance Capture)
    local fc = FirearmInventoryClass 
    if fc and type(fc) == "table" then
        if not fc._OriginalEquip then fc._OriginalEquip = fc.Equip end
        if fc._OriginalEquip then
            fc.Equip = function(self, ...)
                ApplyGunMods(self, true) -- Sets recoil to 0 whenever weapon is held
                return fc._OriginalEquip(self, ...)
            end
        end
    end
    
    -- 2. Hook Recoiler (Permanent Visual Recoil Override)
    local rc = Recoiler
    if rc and type(rc) == "table" then
        if not rc._OriginalImpulse then rc._OriginalImpulse = rc.Impulse end
        if rc._OriginalImpulse then
            rc.Impulse = function(self, ...)
                if Config.NoRecoil then return end
                return rc._OriginalImpulse(self, ...)
            end
        end
        
        if rc.GetViewmodelAdjustment and not rc._OriginalVMAdjust then
             rc._OriginalVMAdjust = rc.GetViewmodelAdjustment
             rc.GetViewmodelAdjustment = function(self, ...)
                 if Config.NoRecoil then return CFrame_new() end
                 return rc._OriginalVMAdjust(self, ...)
             end
        end

        if rc.GetCameraAdjustment and not rc._OriginalCamAdjust then
             rc._OriginalCamAdjust = rc.GetCameraAdjustment
             rc.GetCameraAdjustment = function(self, ...)
                 if Config.NoRecoil then return CFrame_new(), 0 end
                 return rc._OriginalCamAdjust(self, ...)
             end
        end
    end

    -- 3. Hook CharacterCamera (Ragebot Orientation Layer)
    local cc = CharacterCamera or (shared.Engine and shared.Engine.CharacterCamera) or getgenv().CharacterCamera
    if not cc then
        -- Fallback: Scan if not found
        for _, obj in pairs(getgc(true)) do
            if type(obj) == "table" and rawget(obj, "Update") and rawget(obj, "Render") and rawget(obj, "Watch") then
                cc = obj; break
            end
        end
    end

    if cc and cc.Update and not cc._originalUpdate then
        cc._originalUpdate = cc.Update
        cc.Update = function(self, ...)
            local res = cc._originalUpdate(self, ...)
            
            local localActor = (ReplicatorService and ReplicatorService.LocalActor) or (self and self._localActor)
            
            -- Spinbot Logic (Client-Side Visual & Replication)
            if Config.Spinbot and localActor and localActor.Alive then
                local speed = (Config.SpinbotSpeed or 10)
                local yaw = (tick() * speed) % (math.pi * 2)
                localActor.Orientation = yaw
                localActor.GoalOrientation = yaw
                localActor.CameraX = yaw
            -- Ragebot Orientation Lock (Camera Layer)
            elseif Config.RageMode and Config.Rage_LookAt and ActorManager.SelectedTarget_RB then
                local targetPos = ActorManager.SelectedTarget_RB.Position
                local myPos = localActor.Position or Vector3_new()
                local lookDir = (Vector3_new(targetPos.X, myPos.Y, targetPos.Z) - myPos).Unit
                
                -- Calculate Yaw and Pitch according to game logic (ActorClass.lua)
                local yaw = math.atan2(lookDir.X, lookDir.Z)
                local pitch = math.atan2(targetPos.Y - myPos.Y, Vector2_new(lookDir.X, lookDir.Z).Magnitude)
                
                localActor.Orientation = yaw
                localActor.GoalOrientation = yaw
                localActor.CameraX = yaw
                localActor.CameraY = pitch
            end
            
            return res
        end
    end
end

local function SetupActorHooks()
    -- Hook ActorClass.Update (Crash Protection for Climbing Bug)
    local ac = ActorClass
    
    -- Fallback: If not found, check Replicator
    if not ac and ReplicatorService and ReplicatorService.Actors then
        for _, actor in pairs(ReplicatorService.Actors) do
            local mt = getmetatable(actor)
            if mt and mt.__index then
                ac = mt.__index
                ActorClass = ac -- Set Global
                break
            end
        end
    end

    if ac and ac.Update then
        if not ac._originalUpdate then
            ac._originalUpdate = ac.Update
            
            ac.Update = function(self, ...)
                local args = {pcall(ac._originalUpdate, self, ...)}
                local success = args[1]
                
                if not success then return end
                return unpack(args, 2)
            end
        end
    end
end

local function SetupEnvironmentHooks()
    -- Hook EnvironmentService:Update for No Fog and Always Day
    local es = EnvironmentService or FindService("EnvironmentService", true)
    
    if es then
        local mt = getmetatable(es)
        if mt and mt.Update then 
            -- Hook the Metatable (Class) function
            if not mt._originalUpdate then
                setreadonly(mt, false)
                mt._originalUpdate = mt.Update
                local lighting = Lighting -- Cache once at hook creation time
                
                mt.Update = function(self, dt, ...)
                    -- 1. Call Original First (let game calculate effects)
                    local result = mt._originalUpdate(self, dt, ...)
                    
                    -- 2. Force Overrides AFTER game logic
                    
                    if Config.AlwaysDay then
                        lighting.ClockTime = 12
                    end
                    
                    if Config.NoFog then
                        -- Override Lighting Fog
                        lighting.FogEnd = 100000
                        lighting.FogStart = 0
                        
                        -- Override Atmosphere if it exists (EnvironmentService controls this)
                        local atmosphere = self._atmosphere 
                        -- fallback to finding in Lighting if self._atmosphere isn't accessible
                        if not atmosphere then atmosphere = lighting:FindFirstChildOfClass("Atmosphere") end
                        
                        if atmosphere then
                            atmosphere.Density = 0
                            atmosphere.Haze = 0
                            atmosphere.Glare = 0
                            atmosphere.Offset = 0
                        end
                        
                        -- Override Clouds
                        local clouds = self._clouds or lighting:FindFirstChildOfClass("Clouds")
                        if clouds then
                            clouds.Cover = 0
                            clouds.Density = 0
                        end
                    end
                    
                    return result
                end
                setreadonly(mt, true)
            end
        else
            -- Fallback if no metatable (unlikely but possible if found table IS the class)
            if es.Update and not es._originalUpdate then
                  es._originalUpdate = es.Update
                  local lighting = Lighting -- Cache once at hook creation time
                  es.Update = function(self, dt, ...)
                    local result = es._originalUpdate(self, dt, ...)
                    
                    -- Direct Force Fallback
                    if Config.AlwaysDay then lighting.ClockTime = 12 end
                    if Config.NoFog then
                        lighting.FogEnd = 100000
                        local atm = lighting:FindFirstChildOfClass("Atmosphere")
                        if atm then atm.Density = 0; atm.Haze = 0 end
                        local clouds = lighting:FindFirstChildOfClass("Clouds")
                        if clouds then clouds.Cover = 0 end
                    end
                    return result
                 end
            end
        end
    end
end

-- Removed 'local' to use forward declaration
function SetupHooks()
    SetupAggressiveHooks()  
    SetupActorHooks()
    SetupEnvironmentHooks()

    -- 4. Hook CharacterController Loop (Fly, Noclip, Speed)
    local TargetController = nil
    
    -- Try CharacterController directly or metatable
    if CharacterController then
        if CharacterController.Update then
            TargetController = CharacterController
        else
            local meta = getmetatable(CharacterController)
            local index = meta and meta.__index
            if type(index) == "table" and index.Update then
                TargetController = index
            end
        end
    end
    
    -- Try ControllerService fallback
    if not TargetController and ControllerService and ControllerService.Controller then
        local ctrl = ControllerService.Controller
        if ctrl.Update then
            TargetController = ctrl
        else
            local meta = getmetatable(ctrl)
            local index = (meta and meta.__index) or meta
            if type(index) == "table" and index.Update then
                TargetController = index
            end
        end
    end

    if TargetController and TargetController.Update then
        --print("[ESP] Hooking CharacterController:", (TargetController.SetCFrame and "Method/Index") or "Instance/Metatable")
        EnableSpeedController()
        
        -- Hook Update Function with persistence check
        if not TargetController._originalUpdate then
             TargetController._originalUpdate = TargetController.Update
        end
        
        local OldUpdate = TargetController._originalUpdate

        TargetController.Update = function(self, viewInput, dt, ...)
            if Config.Character_Fly then
                -- FRESH LocalActor reference
                local localActor = (ReplicatorService and ReplicatorService.LocalActor) or (self and self._localActor)
                if not localActor or not localActor.Alive then
                    return OldUpdate(self, viewInput, dt, ...)
                end
                
                -- Ragebot Orientation Lock
                if Config.RageMode and Config.Rage_LookAt and ActorManager.SelectedTarget_RB then
                    local targetPos = ActorManager.SelectedTarget_RB.Position
                    local myPos = self._position or Vector3_new()
                    local lookDir = (Vector3_new(targetPos.X, myPos.Y, targetPos.Z) - myPos).Unit
                    local yaw = math.atan2(lookDir.X, lookDir.Z)
                    local pitch = math.atan2(targetPos.Y - myPos.Y, Vector2_new(lookDir.X, lookDir.Z).Magnitude)
                    
                    localActor.Orientation = yaw
                    localActor.GoalOrientation = yaw
                    localActor.CameraX = yaw
                    localActor.CameraY = pitch
                    self.Orientation = yaw
                end

                self.VelocityGravity = 0
                self.HeightState = 0 -- Standing
                self.IsGrounded = true

                local camCF = Camera.CFrame
                local dir = Vector3_new(0, 0, 0)

                if viewInput and viewInput.Magnitude > 0 then
                    dir = dir + (camCF.LookVector * -viewInput.Y) + (camCF.RightVector * viewInput.X)
                end

                if UserInputService:IsKeyDown(Enum.KeyCode.Space) then dir = dir + Vector3_new(0, 1, 0) end
                if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then
                    dir = dir - Vector3_new(0, 1, 0)
                end

                if dir.Magnitude > 0 then
                    local flySpeedVal = tonumber(Config.Character_FlySpeed) or 50
                    local flySprint = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) and 2.5 or 1
                    local deltaTime = type(dt) == "number" and dt or 0.016
                    
                    local nextPos = self._position + (dir.Unit * flySpeedVal * flySprint * deltaTime)

                    self._position = nextPos
                    self._lastSafePosition = nextPos
                    localActor.SimulatedPosition = nextPos
                    localActor.Grounded = true
                    localActor.Sprinting = false
                    local _, yRot = Camera.CFrame:ToOrientation()
                    localActor.CFrame = CFrame.new(nextPos) * CFrame.Angles(0, yRot, 0)
                    localActor.Orientation = yRot
                end
                
                return
            else
                -- RESET STATE
                if self._localActor then
                     if self._localActor.Rappelling then self._localActor.Rappelling = false end
                     if self.HeightState == nil then
                         self.HeightState = 0 
                         self._localActor.HeightState = 0
                     end
                end
                
                return OldUpdate(self, viewInput, dt, ...)
            end
        end
    else
        warn("[ESP] ⚠ Could not find d.Update to hook!")
    end
end

--[[
    COMBAT LOGIC
]]
local function UpdateCombat(frameId)
    -- OPTIMIZATION: Cache mouse state once per frame (avoid repeated UserInputService calls)
    local mousePressed = UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
    
    local cfg = Config
    local activeVelocity = 2000 -- Already local, keep initial value
    local showWeaponInfo = cfg.ShowWeaponInfo
    local showPred = cfg.ShowPrediction or (cfg.SilentAim and cfg.Prediction)
    local activeTune -- Declare activeTune as local here

    
    -- BACKGROUND LOOPS COMPLETELY REMOVED.
    -- Modifications are handled permanently by class hooks.

    -- Update via signals if possible
    if InventoryService and not WeaponManager.Connection then
        if InventoryService.OnInterfaceStateChanged then
            WeaponManager.Connection = InventoryService.OnInterfaceStateChanged:Connect(function()
                WeaponManager.Equipped = InventoryService.Equipped and InventoryService.Equipped.Handler
            end)
            table.insert(getgenv().BlackhawkESP_Connections, WeaponManager.Connection)
        end
        -- Initial Sync
        WeaponManager.Equipped = InventoryService.Equipped and InventoryService.Equipped.Handler
    end
    
    -- JIT Cache & Immediate Modification
    local equippedController = WeaponManager.Equipped or (InventoryService and InventoryService.Equipped and InventoryService.Equipped.Handler)
    
    -- Auto Reload Logic
    if equippedController and Config.AutoReload and not equippedController._reloading then
        local mag = equippedController._mag
        local meta = equippedController._item and equippedController._item.MetaData
        if meta and ((not mag or mag.Capacity <= 0) and not meta.Chamber) then
            -- AMMO CHECK: Only reload if we actually have magazines with ammo
            local hasMags = false
            pcall(function()
                local mags = equippedController:_getMags()
                if mags and #mags > 0 then hasMags = true end
            end)
            
            if hasMags then
                pcall(function() 
                    local vim = game:GetService("VirtualInputManager")
                    vim:SendKeyEvent(true, Enum.KeyCode.R, false, game)
                    vim:SendKeyEvent(false, Enum.KeyCode.R, false, game)
                end)
            end
        end
    end
    
    -- Cache Combat Targets for this frame
    local targetPart_RB = ActorManager.SelectedTarget_RB
    local targetPart_SA = ActorManager.SelectedTarget_SA
    
    if equippedController then
         ApplyGunMods(equippedController, false) 

         -- IMMEDIATE HOOK: Ensure Silent Aim works instantly
         if (Config.SilentAim or Config.RageMode) and not equippedController._isHookedESP then
             HookController(equippedController)
             equippedController._isHookedESP = true
         end

         -- Ragebot Combat Logic (OPTIMIZED - Cached Stats & Smart Shooting)
         local rageDidShoot = false -- Track if we fired this frame
         
         if Config.RageMode and ActorManager.SelectedTarget_RB then
              local targetActor = ActorManager.SelectedActor_RB
              if not targetActor or not targetActor.Alive then return end
              
              local uid = targetActor.UID
              
               -- CACHE: Weapon stats + damage (cached per weapon change, not per frame)
               local weaponRPM = 600
               local weaponCaliber = equippedController._caliber
               
               -- Use cached weapon data if same weapon as last frame
               local cachedWeapon = ActorManager._cachedRageWeapon
               if cachedWeapon and cachedWeapon.controller == equippedController then
                   weaponRPM = cachedWeapon.rpm
                   -- estDamage from cache
               else
                   -- Recalculate weapon stats (only on weapon change)
                   if equippedController._firearm and equippedController._firearm.Tune then
                       weaponRPM = equippedController._firearm.Tune.RPM or 600
                   end
                   
                   local estDmg = 80
                   local tgtPartName = Config.Rage_TargetPart or "Head"
                   local calConfig = CalibersTable and weaponCaliber and CalibersTable[weaponCaliber]
                   if calConfig and calConfig.Damage and calConfig.Dropoff and BulletService then
                       local ok, dmg = pcall(function()
                           local _, rangeOff = BulletService:GetInfo(weaponCaliber, 10)
                           return BulletService:GetDamageGraph(0, rangeOff or 0, calConfig.Damage, calConfig.Dropoff, calConfig.Damp or 1, tgtPartName)
                       end)
                       if ok and dmg and dmg > 0 then
                           local bullets = calConfig.Bullets or 1
                           estDmg = dmg * bullets
                       end
                   end
                   
                   ActorManager._cachedRageWeapon = {
                       controller = equippedController,
                       rpm = weaponRPM,
                       estDamage = estDmg
                   }
               end
               
               local estDamage = ActorManager._cachedRageWeapon and ActorManager._cachedRageWeapon.estDamage or 80
             
             -- Calculate shots needed based on map type
             local shotsNeeded
             local ignoreTime -- How long to ignore after done
             if isPVP then
                 -- PVP: Full kill — fire until target HP is gone
                 shotsNeeded = ActorManager._rageShotsNeeded[uid]
                 if not shotsNeeded then
                     shotsNeeded = math.ceil(targetHP / estDamage)
                     if shotsNeeded < 1 then shotsNeeded = 1 end
                     ActorManager._rageShotsNeeded[uid] = shotsNeeded
                 end
                 ignoreTime = 0.5
             else
                 -- Zombie/OW: Burst shot then switch
                 shotsNeeded = Config.Rage_BurstSize or 1
                 ignoreTime = 0.5
             end
             
             local shotsFired = ActorManager._rageShots[uid] or 0
             local now = tick()
             local lastShot = ActorManager._rageLast[uid] or 0
             local fireDelay = 60 / weaponRPM
             
             if shotsFired >= shotsNeeded then
                 -- All needed shots fired — switch to next target
                 ActorManager._ignoredTargets[uid] = now + ignoreTime
                 ActorManager.SelectedTarget_RB = nil
                 ActorManager.SelectedActor_RB = nil
                 -- Force stop weapon immediately
                 local method = equippedController.Discharge
                 -- Stop call removed (single shot logic)
             elseif (Config.Rage_AutoFire or mousePressed) and (now - lastShot >= fireDelay) then
                 -- Autofire Safety Check (ALWAYS ACTIVE)
                 local hasAmmo = (equippedController._mag and equippedController._mag.Capacity > 0) or (equippedController._item and equippedController._item.MetaData and equippedController._item.MetaData.Chamber)
                 if not hasAmmo then
                     return
                 end
                 
                 -- Fire 1 shot
                 ActorManager._rageLast[uid] = now
                 ActorManager._rageShots[uid] = shotsFired + 1
                 rageDidShoot = true
                 
                 -- Fire weapon: discharge(true) then IMMEDIATE stop
                 local dischargeMethod = equippedController.Discharge
                 if dischargeMethod then
                     dischargeMethod(equippedController)
                     -- Immediate synchronous stop (not deferred!)
                     -- Stop call removed (single shot logic)
                 end
                 
                 -- Check if that was the last needed shot
                 if (shotsFired + 1) >= shotsNeeded then
                     -- Done with this target — ignore and switch NOW
                     ActorManager._ignoredTargets[uid] = now + ignoreTime
                     ActorManager.SelectedTarget_RB = nil
                     ActorManager.SelectedActor_RB = nil
                 end
             end
         end
         
         -- SAFETY: Force stop weapon when ragebot is active but NOT shooting this frame
         if Config.RageMode and not rageDidShoot and equippedController._firing 
            and not mousePressed then
             local method = equippedController.Discharge
             -- Stop call removed (single shot logic)
         end

    -- TRIGGERBOT LOGIC (Legit / Silent Aim)
    if Config.Triggerbot and not Config.RageMode then
        local targetActor = ActorManager.SelectedActor_SA
        local validTarget = false
        
        if targetActor and targetActor.Alive then
             -- Silent Aim Target Check
             validTarget = true
        else
             -- Fallback: Raycast forward if no Silent Aim target selected (Legit Triggerbot)
             local mouse = UserInputService:GetMouseLocation()
             local ray = Camera:ViewportPointToRay(mouse.X, mouse.Y)
             local params = RaycastParams.new()
             params.FilterType = Enum.RaycastFilterType.Exclude
             params.FilterDescendantsInstances = {Camera, LocalPlayer.Character}
             local result = Workspace:Raycast(ray.Origin, ray.Direction * 1000, params)
             
             if result and result.Instance then
                 local model = result.Instance:FindFirstAncestorOfClass("Model")
                 if model then
                     -- Check if this model is a known enemy
                     for _, enemy in ipairs(ActorManager.Enemies) do
                         if enemy.Character == model and enemy.Alive then
                             validTarget = true
                             break
                         end
                     end
                 end
             end
        end
        
        if validTarget then
             -- Check RPM
             local weaponRPM = 600
             if equippedController._firearm and equippedController._firearm.Tune then
                 weaponRPM = equippedController._firearm.Tune.RPM or 600
             end
             
             local fireDelay = 60 / weaponRPM
             local lastShot = equippedController._lastTriggerShot or 0
             local now = tick()
             
             if now - lastShot >= fireDelay then
                 -- Autofire Safety Check (ALWAYS ACTIVE)
                 local hasAmmo = (equippedController._mag and equippedController._mag.Capacity > 0) or (equippedController._item and equippedController._item.MetaData and equippedController._item.MetaData.Chamber)
                 if not hasAmmo then
                     return
                 end

                 equippedController._lastTriggerShot = now
                 
                 -- Fire Weapon directly via Discharge
                 if equippedController.Discharge then
                     equippedController:Discharge()
                 end
             end
        end
    end
    
    
    -- IMMEDIATE HOOK: Vehicle Turret (Manual Fetch)
    -- This ensures we hook the turret even if it's not in the main cache yet
    if ReplicatorService and ReplicatorService.LocalActor then
        local myActor = ReplicatorService.LocalActor
        if myActor.Turret and type(myActor.Turret) == "table" then
            local turretController = myActor.Turret
             -- Apply Turret Mods (Directly)
             local tConfig = turretController._config
             if tConfig then
                 -- Unlock config table efficiently
                 if setreadonly then pcall(setreadonly, tConfig, false) end
                 if make_writeable then pcall(make_writeable, tConfig) end
                 
                 if cfg.TurretNoRecoil then 
                     tConfig.Recoil = 0
                     tConfig.Recoil_Base = Vector2.new(0,0)
                     tConfig.Recoil_Range = Vector2.new(0,0)
                     tConfig.Recoil_Camera = 0
                     tConfig.Recoil_Kick = 0
                     tConfig.Recoil_Smooth = 0
                     tConfig.RPM_RecoilScale = 0
                     tConfig.CameraShake = nil -- Disable visual shake
                 end
                 if cfg.TurretNoSpread then 
                    tConfig.Spread = 0
                    tConfig.Barrel_Spread = 0
                    tConfig.MinSpread = 0
                    tConfig.MaxSpread = 0
                    tConfig.Recoil_Spread = 0
                    
                    if CalibersTable and tConfig.Caliber then
                        local cal = CalibersTable[tConfig.Caliber]
                        if cal then cal.Spread = 0 end
                    end
                 end
                 if cfg.TurretUnlockFiremodes and tConfig.Firemodes then
                        -- Check for all auto-related modes (0, 2)
                        local hasAuto = false
                        for _, m in pairs(tConfig.Firemodes) do if m == 0 or m == 2 then hasAuto = true end end
                        if not hasAuto then table.insert(tConfig.Firemodes, 0) end
                 end
             end
        end
    end


    -- 1. Gun Mods (Standard Cache Loop - Keep for Turrets ONLY)
    -- THROTTLED: Run every 10 frames (approx 0.16s) to save CPU
    if (frameId % 10 == 0) and (cfg.TurretNoRecoil or cfg.TurretNoSpread or cfg.TurretUnlockFiremodes) then
        -- VISUALS: Turrets
        if AllControllersCache.Visuals then
            for _, controller in ipairs(AllControllersCache.Visuals) do
                 if type(controller) ~= "table" or controller == equippedController then continue end -- Skip active/invalid
                 
                 local isTurret = rawget(controller, "_turret") ~= nil
                 
                 if isTurret then
                     local tConfig = controller._config
                     if tConfig then
                         -- Unlock config table if readonly
                         if setreadonly then pcall(setreadonly, tConfig, false) end
                         
                         if cfg.TurretNoRecoil then 
                             tConfig.Recoil = 0
                             tConfig.Recoil_Base = Vector2.new(0,0)
                             tConfig.Recoil_Camera = 0
                             tConfig.Recoil_Kick = 0
                         end
                         if cfg.TurretNoSpread then 
                            tConfig.Spread = 0
                            tConfig.Barrel_Spread = 0
                         end
                         if cfg.TurretUnlockFiremodes and tConfig.Firemodes then
                                local hasAuto = false
                                for _, m in pairs(tConfig.Firemodes) do if m == 0 then hasAuto = true end end
                                if not hasAuto then table.insert(tConfig.Firemodes, 0) end
                         end
                      end
                 end
            end
        end
    end

    -- Weapon Info & Prediction (using equippedController located above)
    -- THROTTLED: Run every 5 frames (approx 0.08s) - UI updates are expensive
    if (showWeaponInfo or showPred) and (frameId % 5 == 0) then
        if type(equippedController) == "table" and equippedController._firearm then
            local firearm = equippedController._firearm
            activeTune = firearm.Tune
            
            if activeTune then
                local velocity = 0
                if BulletService and activeTune.Caliber then
                    local success, v = pcall(function() 
                        return BulletService:GetInfo(activeTune.Caliber, activeTune.Barrel or 1)
                    end)
                    if success and v and v > 0 then velocity = v end
                end

                if velocity == 0 then
                    velocity = activeTune.Velocity or (activeTune.MuzzleVelocity and activeTune.MuzzleVelocity.Value) or 2000
                end
                
                activeVelocity = velocity

                if showWeaponInfo then
                    local weaponName = firearm.Name or activeTune.Name or "Unknown"


                    local caliberName = ""
                    if CalibersTable and activeTune.Caliber and CalibersTable[activeTune.Caliber] then
                        local cal = CalibersTable[activeTune.Caliber]
                        if cal and cal.FamilyName then
                            caliberName = cal.FamilyName
                            if cal.VariantName and cal.VariantName ~= "" then caliberName = caliberName .. " " .. cal.VariantName end
                        end
                    end

                    local velocityMS = math_floor(velocity * 0.3048 + 0.5)
                    local infoText = string_format("Weapon: %s\nCaliber: %s\nVelocity: %d m/s", weaponName, caliberName ~= "" and caliberName or "N/A", velocityMS)

                    -- Optimization: Only update if text changed
                    if WeaponInfoText.Text ~= infoText then
                        WeaponInfoText.Text = infoText
                    end
                    WeaponInfoText.Position = Vector2_new(50, Camera.ViewportSize.Y - 120)
                    WeaponInfoText.Visible = true
                else
                    WeaponInfoText.Visible = false
                end
            else
                WeaponInfoText.Visible = false
            end
        else
            WeaponInfoText.Visible = false
        end
    end
    
    -- 2. Apply Silent Aim Hooks -> uses cached FirearmInventory
    if Config.SilentAim and FirearmInventory and type(FirearmInventory) == "table" then
        for _, controller in pairs(FirearmInventory) do
            if type(controller) == "table" and controller._firearm and not controller._isHookedESP then
                HookController(controller)
                controller._isHookedESP = true
            end
        end
    end
    
    -- Spinbot / Ragebot: High-Priority Orientation & CFrame Lock (Triple-Lock System)
    if (cfg.RageMode or cfg.Spinbot) and ReplicatorService and ReplicatorService.LocalActor then
        local myActor = ReplicatorService.LocalActor
        if myActor.Alive and myActor.Character then
            -- OPTIMIZATION: actor.RootPart is direct engine ref (no FindFirstChild)
            local root = myActor.RootPart or myActor.Character.PrimaryPart
            if root then
                local muzzlePos = GetMuzzlePosition() or Camera.CFrame.Position
                local targetPos = targetPart_RB and targetPart_RB.Position
                
                local yaw, pitch
                
                if cfg.RageMode and cfg.Rage_LookAt and targetPart_RB then
                    -- RAGE TARGET ROTATION
                    local direction = (targetPos - muzzlePos).Unit
                    yaw = math.atan2(direction.X, direction.Z)
                    pitch = math.atan2(targetPos.Y - muzzlePos.Y, Vector2_new(direction.X, direction.Z).Magnitude)
                    
                    root.CFrame = CFrame.new(root.Position, root.Position + Vector3_new(math.sin(yaw), 0, math.cos(yaw)))
                elseif cfg.Spinbot then
                    -- SPINBOT ROTATION
                    local speed = (Config.SpinbotSpeed or 20)
                    yaw = (tick() * speed) % (math.pi * 2)
                    pitch = 0
                    
                    root.CFrame = CFrame.new(root.Position) * CFrame.Angles(0, yaw, 0)
                end
                
                if yaw then
                    -- Update Actor Properties for engine visibility and server replication
                    myActor.Orientation = yaw
                    myActor.GoalOrientation = yaw
                    myActor.CameraX = yaw
                    myActor.CameraY = pitch
                    
                    local controller = ControllerService and ControllerService.Controller
                    if controller then
                        controller.Orientation = yaw
                    end
                end
            end
        end
    end

    -- 4. Update Combat Visuals (FOV, Prediction)
    -- OPTIMIZATION: Only get mouse location when FOV circle is actually needed
    if Config.SilentAim and Config.ShowFOV and FOVCircle then
        local mouse = UserInputService:GetMouseLocation()
        FOVCircle.Visible = true
        FOVCircle.Position = mouse
        FOVCircle.Radius = Config.SilentAimFOV
    elseif FOVCircle then
        FOVCircle.Visible = false
    end
    
    -- Optimized Prediction Logic (Using Silent Aim target for visualization)
    local targetPart = targetPart_SA
    local targetActor = ActorManager.SelectedActor_SA

    if targetPart then
        local rawVel = Vector3_new(0,0,0)
        if targetActor and targetActor._oldDirection then
            rawVel = targetActor._oldDirection * 60
        elseif targetPart.Parent and targetPart.Parent.PrimaryPart then
            rawVel = targetPart.Parent.PrimaryPart.AssemblyLinearVelocity or Vector3_new(0,0,0)
        end
        
        -- Initialize or Lerp
        if not getgenv()._lastPredVel then 
            getgenv()._lastPredVel = rawVel 
        else
            -- LERP Smoothing: 0.15 seems to be the sweet spot for stability
            getgenv()._lastPredVel = getgenv()._lastPredVel:Lerp(rawVel, 0.15) 
        end
    end

    if getgenv().PredictionDot then
        local dot = getgenv().PredictionDot
        
        if Config.ShowPrediction and targetPart then
             local muzzlePos = GetMuzzlePosition() or Camera.CFrame.Position
             local targetPos = targetPart.Position
             local targetVel = getgenv()._lastPredVel or Vector3_new(0,0,0)
             local gravity = 32.2 -- Restored to game value (was 25) 
             
             local aimPos, _ = SolveLead(muzzlePos, targetPos, targetVel, activeVelocity, gravity)
             local screenPos, onScreen = Camera:WorldToViewportPoint(aimPos)
             
             if onScreen then
                 dot.Position = Vector2_new(screenPos.X, screenPos.Y)
                 dot.Color = cfg.PredictionColor or Color3_fromHSV(0.33, 1, 1)
                 dot.Visible = true
             else
                 dot.Visible = false
             end
        else
            dot.Visible = false
        end
    end
end
end

local function GetEntityColor(actor, entityType, cachedLocalSquad)
    if entityType == "Player" then
        if IsTeammate(actor, cachedLocalSquad) then
            return Config.SquadColor or Config.TeammateColor or Color3_new(0, 1, 0) -- Green
        end
        return Config.PlayerColor or Color3_new(1, 0.65, 0) -- Orange/Red
    elseif entityType == "Zombie" then
        -- Check zombie ability level for color
        if actor.Health and type(actor.Health) == "table" and actor.Health.Ability then
            return Config.ZombieColors[actor.Health.Ability] or Config.ZombieColor or Color3_new(1, 0, 0)
        end
        return Config.ZombieColor or Color3_new(1, 0, 0)
    elseif entityType == "NPC" then
        return Config.NPCColor or Color3_new(1, 1, 0) -- Yellow
    end
    
    return Color3_new(1, 1, 1)  -- White for unknown
end

--[[
    MAP DETECTION
]]
--[[
    VEHICLE TELEPORT LOGIC
]]

local function GetNetwork()
    if Network then return Network end
    
    -- Robust Logic from VehicleTeleport.lua
    -- 1. Check Executor Global Cache
    if getgenv().network and type(getgenv().network._key) == "table" then 
        Network = getgenv().network
        return Network 
    end
    
    -- 2. Try getnilinstances
    for _, obj in pairs(getnilinstances()) do
        if obj:IsA("ModuleScript") and obj.Name:lower():find("network") then
            local s, v = pcall(require, obj)
            if s and type(v) == "table" and v.FireServer then
                Network = v
                return Network
            end
        end
    end
    
    -- 3. Deep GC Scan
    for _, v in pairs(getgc(true)) do
        if type(v) == "table" then
            if rawget(v, "_key") and type(rawget(v, "_key")) == "table" and rawget(v, "_code") then
                Network = v
                return Network
            end
             -- Fallback fingerprint
            if rawget(v, "FireServer") and rawget(v, "_events") then
                Network = v
                return Network
            end
        end
    end
    return nil
end

local ActiveControllerCache = nil
local function GetActiveVehicleController()
    -- 0. Check Cache validity against current seat
    local player = LocalPlayer
    local char = player.Character
    local hum = char and char:FindFirstChild("Humanoid")
    local seat = hum and hum.SeatPart
    
    
    -- 0. Check Cache validity against current seat
    -- If SeatPart is nil, we might still be in a vehicle (e.g. custom seating or early initialization)
    -- So we don't return nil immediately, but we proceed with caution.
    
    if seat then
        -- Strict Mode: If we have a seat, validating against it is the best way.
        if ActiveControllerCache and ActiveControllerCache._vehicle and ActiveControllerCache._vehicle.Model then
            if seat:IsDescendantOf(ActiveControllerCache._vehicle.Model) then
                 return ActiveControllerCache
            else
                 ActiveControllerCache = nil
            end
        end
    else
        -- Relaxed Mode: No seat detected by Humanoid. 
        -- This happens in BRM5 for some vehicles or turrets.
        -- We will validate using position/distance or just ControllerService trust.
    end



    -- 1. Try global cache first
    if ControllerService and ControllerService.Controller and ControllerService.Controller._vehicle then
        local candidate = ControllerService.Controller
        local vehModel = candidate._vehicle.Model
        
        -- Validation
        if seat and vehModel then
             if seat:IsDescendantOf(vehModel) then
                ActiveControllerCache = candidate
                return ActiveControllerCache
             end
        elseif vehModel then
             -- Fallback: Check if character is physically near or parented
             if char and char.Parent == vehModel then
                 ActiveControllerCache = candidate
                 return ActiveControllerCache
             end
             -- Ultimate Fallback: Just trust ControllerService if we have no other info
             -- (This returns the vehicle the game THINKs we are controlling)
             ActiveControllerCache = candidate
             return ActiveControllerCache
        end
    end


    -- 2. Deep GC Scan for active controller (Most reliable for injected scripts)
    -- OPTIMIZED: Check for _localActor match first (Best method)
    local myActor = ReplicatorService and ReplicatorService.LocalActor
    
    for _, v in pairs(getgc(true)) do
        if type(v) == "table" then
            -- Check for signature properties of the VehicleController
            if rawget(v, "_vehicle") and rawget(v, "Update") and rawget(v, "_solver") then
                
                -- BEST CHECK: Compare controller's actor with our local actor
                if myActor and rawget(v, "_localActor") == myActor then
                    ActiveControllerCache = v
                    return ActiveControllerCache
                end
                
                -- Fallback Checks (if ReplicatorService is missing or _localActor not set)
                local veh = rawget(v, "_vehicle")
                if veh and veh.Model then
                     if seat then
                        if seat:IsDescendantOf(veh.Model) then
                            ActiveControllerCache = v
                            return ActiveControllerCache
                        end
                     else
                        -- Fallback if no seat detected: check distance
                        if char and char.PrimaryPart and veh.Model.PrimaryPart then
                            if (char.PrimaryPart.Position - veh.Model.PrimaryPart.Position).Magnitude < 20 then
                                ActiveControllerCache = v
                                return ActiveControllerCache
                            end
                        end
                     end
                end
            end
        end
    end
    
    return nil
end

local function TeleportVehicle(targetPos, targetRotY)
    local net = GetNetwork()
    if not net then 
         if Notifier and Notifier.new then
             Notifier.new({Title = "Error", Content = "Network Service not found!", Duration = 3})
         else
             warn("[Teleport] Network Service not found!")
         end
         return 
    end
    
    local controller = GetActiveVehicleController()
    
    if not controller or not controller._vehicle then
         if Notifier and Notifier.new then
             Notifier.new({Title = "Error", Content = "Get in a vehicle first!", Duration = 3})
         else
             warn("[Teleport] Get in a vehicle first!")
         end
         return 
    end
    
    local vehicle = controller._vehicle
    
    -- Teleport Logic from VehicleTeleport.lua
    local newCF = CFrame.new(targetPos)
    if targetRotY then
        newCF = newCF * CFrame.Angles(0, math.rad(targetRotY), 0)
    end

    -- 1. Update Local Physics
    if vehicle.Hitbox then vehicle.Hitbox.CFrame = newCF end
    vehicle.CFrame = newCF

    -- 2. Update Solver
    local solver = controller._solver
    if solver and solver.SetState then
        -- SetState(CFrame, Velocity, AngularVelocity, ComponentState)
        solver:SetState(newCF, Vector3.new(0,0,0), Vector3.new(0,0,0), vehicle.ComponentReplicates)
    end

    -- 3. Replicate to Server
    -- "ReplicateVehicle", UID, x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22, Steering, Components
    local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = newCF:GetComponents()
    local steering = vehicle.Steering or 0
    local components = vehicle.ComponentReplicates
    
    net:FireServer("ReplicateVehicle", vehicle.UID, x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22, steering, components)
    
    if Notifier and Notifier.new then
        Notifier.new({Title = "Teleport", Content = "Vehicle Teleported!", Duration = 3})
    else
        -- Fallback if Notifier is missing
        print("[Teleport] Vehicle Teleported!")
    end
end

DetectMapType = function()
    -- 1. Check PlaceId (Most Reliable)
    local currentId = game.PlaceId
    for name, data in pairs(Places) do
        if data[1] == currentId or data[2] == currentId then
            Config.CurrentMapName = name -- Store exact name (e.g. ZMP_NYC)
            
            if name:find("PVP_") then return "PVP" end
            if name:find("ZM") then return "Zombie" end
            if name:find("OW_") then return "OpenWorld" end
            if name:find("HQ_") or name:find("CM_") then return "Headquarters" end
            if name == "Menu" then return "Menu" end
        end
    end
    
    -- 2. Fallback: WorldService
    if not WorldService then
        return "Unknown"
    end
    
    -- WorldService has _world property (string name of current world)
    local placeName = WorldService._world or ""
    Config.CurrentMapName = placeName -- Fallback name
    
    if placeName:find("PVP_") then
        return "PVP"
    elseif placeName:find("ZM") then
        return "Zombie"
    elseif placeName:find("OW_") or placeName == "Default" then
        return "OpenWorld"
    elseif placeName:find("HQ_") or placeName:find("CM_") then
        return "Headquarters"
    elseif placeName == "Menu" then
        return "Menu"
    end
    
    return "Unknown"
end

ShouldShowEntity = function(actor, entityType, cachedLocalSquad)
    -- Map-specific filtering
    if Config.AutoDetectMap then
        local mapType = Config.CurrentMapType
        
        -- In PVP, don't show zombies
        if mapType == "PVP" and entityType == "Zombie" then
            return false
        end
    end
    
    -- User filter settings
    if entityType == "Player" then
        if IsTeammate(actor, cachedLocalSquad) and not Config.ShowSquadMembers then
            return false
        end
        return Config.ShowPlayers
    elseif entityType == "Zombie" then
        return Config.ShowZombies
    elseif entityType == "NPC" then
        return Config.ShowNPCs
    end
    
    return false
end

--[[
    ESP RENDERING (HYBRID: Highlight + Drawing API)
]]
local function CreateHighlight(actor, color)
    if not actor.Character then return nil end
    
    local highlight = Instance.new("Highlight")
    highlight.FillColor = color
    highlight.FillTransparency = 0.9
    highlight.OutlineColor = color
    highlight.OutlineTransparency = 0
    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    highlight.Parent = actor.Character
    
    return highlight
end

local function CreateDrawingESP()
    local esp = {
        BoxOutline = Drawing_new("Square"),
        Box = Drawing_new("Square"),
        HealthBarOutline = Drawing_new("Square"),
        HealthBar = Drawing_new("Square"),
        Name = Drawing_new("Text"),
        Distance = Drawing_new("Text")
    }
    
    -- Setup Defaults
    esp.BoxOutline.Visible = false
    esp.BoxOutline.Color = Color3.new(0, 0, 0)
    esp.BoxOutline.Thickness = 3
    esp.BoxOutline.Transparency = 1
    esp.BoxOutline.Filled = false
    esp.BoxOutline.ZIndex = 1

    esp.Box.Visible = false
    esp.Box.Color = Color3.new(1, 1, 1)
    esp.Box.Thickness = 1
    esp.Box.Transparency = 1
    esp.Box.Filled = false
    esp.Box.ZIndex = 2
    
    esp.HealthBarOutline.Visible = false
    esp.HealthBarOutline.Color = Color3.new(0, 0, 0)
    esp.HealthBarOutline.Thickness = 1
    esp.HealthBarOutline.Filled = true
    esp.HealthBarOutline.Transparency = 1
    esp.HealthBarOutline.ZIndex = 1

    esp.HealthBar.Visible = false
    esp.HealthBar.Color = Color3.new(0, 1, 0)
    esp.HealthBar.Thickness = 1
    esp.HealthBar.Filled = true
    esp.HealthBar.ZIndex = 2
    
    esp.Name.Visible = false
    esp.Name.Color = Color3.new(1, 1, 1)
    esp.Name.Size = 13
    esp.Name.Center = true
    esp.Name.Outline = true
    esp.Name.Font = 2 -- UI
    esp.Name.ZIndex = 3
    
    esp.Distance.Visible = false
    esp.Distance.Color = Color3.new(1, 1, 1)
    esp.Distance.Size = 12
    esp.Distance.Center = true
    esp.Distance.Outline = true
    esp.Distance.Font = 2
    esp.Distance.ZIndex = 3
    
    esp.Tracer = Drawing.new("Line")
    esp.Tracer.Visible = false
    esp.Tracer.Color = Color3.new(1, 1, 1)
    esp.Tracer.Thickness = 1
    esp.Tracer.Transparency = 1
    
    -- Corner Box Lines (8 lines)
    esp.Corners = {}
    for i = 1, 8 do
        local line = Drawing.new("Line")
        line.Visible = false
        line.Thickness = 1
        line.Color = Color3.new(1, 1, 1)
        table.insert(esp.Corners, line)
    end
    
    return esp
end

local function CreateSimpleESP(espData)
    local box = Instance.new("BoxHandleAdornment")
    box.Name = "ESPBox"
    box.AlwaysOnTop = true
    box.ZIndex = 5
    box.Transparency = 0.6
    box.Color3 = espData.Color

    -- Secure GUI Logic (Global Cached Container)
    local container = GetSecureContainer()
    if not container then return end 

    box.Parent = container
    espData.SimpleESP = { Box = box, Container = container }
end



local function CreateESPForActor(actor, cachedLocalSquad)
    local entityType = GetEntityType(actor)
    
    if not ShouldShowEntity(actor, entityType, cachedLocalSquad) then
        return
    end
    
    local color = GetEntityColor(actor, entityType, cachedLocalSquad)
    local espData = {
        Actor = actor,
        EntityType = entityType,
        Color = color
    }
    
    -- Create visual elements
    if Config.UseHighlight then
        espData.Highlight = CreateHighlight(actor, color)
    end
    
    -- Always create Drawing ESP elements (managed visibility)
    espData.Drawing = CreateDrawingESP()
    
    -- Create Simple ESP elements (used if Config.SimpleESP is enabled)
    CreateSimpleESP(espData)
    
    ESPElements[actor.UID] = espData
end

-- Helper function to efficiently toggle all drawing visibility (with Caching)
local function SetAllVisible(drawings, espData, visible)
    if espData._visible == visible then return end
    espData._visible = visible
    
    local boxOn = visible and Config.UseBoxESP
    drawings.Box.Visible = boxOn
    drawings.BoxOutline.Visible = boxOn
    
    drawings.Name.Visible = visible and Config.ShowNames
    drawings.Distance.Visible = visible and Config.ShowDistance
    
    local healthOn = visible and Config.ShowHealth
    drawings.HealthBar.Visible = healthOn
    drawings.HealthBarOutline.Visible = healthOn
    
    drawings.Tracer.Visible = visible and Config.UseTracers
    
    -- Only update highlight if defined
    if espData.Highlight then espData.Highlight.Enabled = visible and Config.UseHighlight end
    
    -- Hide corner lines if not visible
    if not visible then
        for _, line in ipairs(drawings.Corners) do line.Visible = false end
    end
end

-- Hitbox Expander Helper
local OriginalSizes = setmetatable({}, { __mode = "k" })
local function ApplyHitboxExpander(actor, espData, cfg)
    local head = espData.CachedHead
    local enabled = cfg.HitboxExpander
    
    if not head or not head.Parent then
        local char = actor.Character
        -- OPTIMIZATION: actor.Parts.Head is direct engine ref (no FindFirstChild)
        head = (actor.Parts and actor.Parts.Head) or (char and char:FindFirstChild("Head"))
        espData.CachedHead = head
    end
    
    if not head then return end
    
    if enabled and actor.Alive then
        if not OriginalSizes[head] then OriginalSizes[head] = head.Size end
        local sz = cfg.HitboxSize or 4
        head.Size = Vector3_new(sz, sz, sz)
        head.Transparency = 0.5
        head.CanCollide = false
    elseif OriginalSizes[head] then
        head.Size = OriginalSizes[head]
        head.Transparency = 0
        head.CanCollide = true
        OriginalSizes[head] = nil
    end
end

local function RemoveESP(uid)
    local espData = ESPElements[uid]
    if not espData then return end
    
    -- Clean up Highlight
    if espData.Highlight then pcall(function() espData.Highlight:Destroy() end) end
    
    -- Clean up Simple ESP
    if espData.SimpleESP then
        pcall(function() espData.SimpleESP.Box:Destroy() end)
    end

    -- Clean up Drawings
    if espData.Drawing then
        local drawings = espData.Drawing
        if drawings.Box then pcall(function() drawings.Box:Remove() end) end
        if drawings.BoxOutline then pcall(function() drawings.BoxOutline:Remove() end) end
        if drawings.Name then pcall(function() drawings.Name:Remove() end) end
        if drawings.Distance then pcall(function() drawings.Distance:Remove() end) end
        if drawings.HealthBar then pcall(function() drawings.HealthBar:Remove() end) end
        if drawings.HealthBarOutline then pcall(function() drawings.HealthBarOutline:Remove() end) end
        if drawings.Tracer then pcall(function() drawings.Tracer:Remove() end) end
        if drawings.Corners then
            for _, line in ipairs(drawings.Corners) do
                pcall(function() line:Remove() end)
            end
        end
    end
    
    ESPElements[uid] = nil
end

local function UpdateESPForActor(uid, espData, frameId, cachedCfg, localSquad)
    local actor = espData.Actor
    local entityType = actor._entityType or "Unknown"
    
    -- Mark as updated
    espData.LastUpdate = frameId
    
    -- Check if actor is still valid and Alive (Engine Check)
    if not actor or not actor.Alive then
        RemoveESP(uid)
        return
    end

    -- Hitbox Expander Integration
    ApplyHitboxExpander(actor, espData, cachedCfg)

    -- Bug Fix: Re-check filters for existing elements
    if not ShouldShowEntity(actor, entityType, localSquad) then
        SetAllVisible(espData.Drawing, espData, false)
        return
    end
    
    local distance = actor.LOD_Distance or 9999
    
    -- PERFORMANCE: Throttling & Culling
    if distance > cachedCfg.MaxDistance then
        SetAllVisible(espData.Drawing, espData, false)
        if espData.SimpleESP and espData.SimpleESP.Box then pcall(function() espData.SimpleESP.Box.Visible = false end) end
        return
    end
    
    -- DISTANCE THROTTLING: Far actors update less frequently
    if distance > 1500 and (frameId % 4) ~= 0 then return end
    if distance > 500 and (frameId % 2) ~= 0 then return end
    
    -- MODE: Simple ESP (BoxHandleAdornment)
    if cachedCfg.SimpleESP then
        SetAllVisible(espData.Drawing, espData, false)
        local sESP = espData.SimpleESP
        local isVisible = actor.OnScreen or actor.ViewportOnScreen or actor.LOD_OnScreen
        if distance < 50 then isVisible = true end

        if isVisible then
             local char = actor.Character
             -- OPTIMIZATION: actor.Parts.Head is direct engine ref (no FindFirstChild)
             local target = (actor.Parts and actor.Parts.Head) or (char and char:FindFirstChild("Head"))
             if target then
                local box = sESP.Box
                pcall(function() 
                    box.Visible = true; box.Adornee = target; 
                    box.Size = target.Size; box.Color3 = espData.Color 
                end)
             end
        else
            if sESP and sESP.Box then pcall(function() sESP.Box.Visible = false end) end
        end
        return
    end
    
    local drawings = espData.Drawing
    -- OPTIMIZATION: Use engine's ViewportOnScreen + LOD_OnScreen to skip rendering
    -- Engine pre-calculates ViewportOnScreen via WorldToViewportPoint in Stepped
    -- and LOD_OnScreen = ViewportOnScreen when LOD > 2 (distance > 256)
    local engineVisible = actor.LOD_OnScreen or (distance < 128 and actor.ViewportOnScreen)
    
    if not engineVisible then
        SetAllVisible(drawings, espData, false)
        return
    end
    
    -- OPTIMIZATION: Use engine-interpolated Position (updated every frame in ActorClass.Update)
    local worldPos = actor.Position or (actor.RootPart and actor.RootPart.Position)
    if not worldPos then return end
    
    -- Still need WorldToViewportPoint for precise screen coordinates, but engine already 
    -- confirmed it's on screen via ViewportOnScreen check above
    local screen_point, onScreen = Camera:WorldToViewportPoint(worldPos)
    if not onScreen then
        SetAllVisible(drawings, espData, false)
        return
    end
    
    local screenPos = Vector2_new(screen_point.X, screen_point.Y)
    SetAllVisible(drawings, espData, true)

    -- Update Highlight
    if espData.Highlight then 
        espData.Highlight.FillColor = espData.Color
        espData.Highlight.OutlineColor = espData.Color
    end
    
    -- Calculate Box Dimensions
    local height = 6.5 -- Standing
    local hState = actor.HeightState
    if hState == 1 then height = 4.5 end -- Crouch
    if hState == 2 then height = 2.5 end -- Prone
    
    local top_point = Camera:WorldToViewportPoint(worldPos + Vector3_new(0, height*0.5, 0))
    local bottom_point = Camera:WorldToViewportPoint(worldPos - Vector3_new(0, height*0.5, 0))
    local scale = cachedCfg.BoxScale or 1
    local boxHeight = math_abs(bottom_point.Y - top_point.Y) * scale
    local boxWidth = boxHeight * 0.6
    
    local boxPosition = Vector2_new(screenPos.X - boxWidth * 0.5, screenPos.Y - boxHeight * 0.5)
    
    -- Update Drawings
    
    -- Determine box color (override or entity-based)
    local boxColor = cachedCfg.BoxColor or espData.Color
    
    -- Box
    if cachedCfg.UseBoxESP then
        if cachedCfg.BoxStyle == "Corner" then
            -- Corner box style - hide full box, show corner lines
            drawings.Box.Visible = false
            drawings.BoxOutline.Visible = false
            
            local cornerLength = (boxWidth < boxHeight and boxWidth or boxHeight) * 0.25
            local corners = drawings.Corners
            
            -- OPTIMIZATION: Cache intermediate coordinates
            local bpX, bpY = boxPosition.X, boxPosition.Y
            local rightX = bpX + boxWidth
            local bottomY = bpY + boxHeight
            local topLeft = boxPosition -- Reuse existing Vector2
            local topRight = Vector2_new(rightX, bpY)
            local bottomLeft = Vector2_new(bpX, bottomY)
            local bottomRight = Vector2_new(rightX, bottomY)
            
            -- Top-left corner
            corners[1].From = topLeft
            corners[1].To = Vector2_new(bpX + cornerLength, bpY)
            corners[1].Color = boxColor
            corners[1].Visible = true
            
            corners[2].From = topLeft
            corners[2].To = Vector2_new(bpX, bpY + cornerLength)
            corners[2].Color = boxColor
            corners[2].Visible = true
            
            -- Top-right corner
            corners[3].From = topRight
            corners[3].To = Vector2_new(rightX - cornerLength, bpY)
            corners[3].Color = boxColor
            corners[3].Visible = true
            
            corners[4].From = topRight
            corners[4].To = Vector2_new(rightX, bpY + cornerLength)
            corners[4].Color = boxColor
            corners[4].Visible = true
            
            -- Bottom-left corner
            corners[5].From = bottomLeft
            corners[5].To = Vector2_new(bpX + cornerLength, bottomY)
            corners[5].Color = boxColor
            corners[5].Visible = true
            
            corners[6].From = bottomLeft
            corners[6].To = Vector2_new(bpX, bottomY - cornerLength)
            corners[6].Color = boxColor
            corners[6].Visible = true
            
            -- Bottom-right corner
            corners[7].From = bottomRight
            corners[7].To = Vector2_new(rightX - cornerLength, bottomY)
            corners[7].Color = boxColor
            corners[7].Visible = true
            
            corners[8].From = bottomRight
            corners[8].To = Vector2_new(rightX, bottomY - cornerLength)
            corners[8].Color = boxColor
            corners[8].Visible = true
        else
            -- Full box style
            -- Hide corner lines
            local corners = drawings.Corners
            if corners[1].Visible then
                for _, line in ipairs(corners) do
                    line.Visible = false
                end
            end
            
            drawings.BoxOutline.Size = Vector2_new(boxWidth, boxHeight)
            drawings.BoxOutline.Position = boxPosition
            drawings.BoxOutline.Visible = true
            
            drawings.Box.Size = Vector2_new(boxWidth, boxHeight)
            drawings.Box.Position = boxPosition
            drawings.Box.Color = boxColor
            drawings.Box.Visible = true
        end
    else
        drawings.Box.Visible = false
        drawings.BoxOutline.Visible = false
        local corners = drawings.Corners
        if corners[1].Visible then
            for _, line in ipairs(corners) do
                line.Visible = false
            end
        end
    end
    
    -- Name
    if cachedCfg.ShowNames then
        local displayName = actor.OwnerName
        if entityType == "Zombie" then
             local h = actor.Health
             if h and type(h) == "table" and h.Ability then
                local abilityNames = {"Crippled", "Slow", "Normal", "Sprinter"}
                displayName = abilityNames[h.Ability] or "Zombie"
            else
                displayName = "Zombie"
            end
        elseif not displayName or displayName == "???" then
            displayName = "AI"
        end
        
        local dynamicScale = cachedCfg.DynamicTextScaling and math_clamp(boxHeight * 0.016, 0.5, 1.0) or 1.0
        local nameSize = 13 * cachedCfg.TextScale * dynamicScale
        
        drawings.Name.Text = displayName
        drawings.Name.Position = Vector2_new(screenPos.X, boxPosition.Y - (nameSize + 3))
        drawings.Name.Color = espData.Color
        drawings.Name.Size = nameSize
        drawings.Name.Visible = true
    else
        drawings.Name.Visible = false
    end
    
    -- Distance (Meters)
    if cachedCfg.ShowDistance then
        local dynamicScale = cachedCfg.DynamicTextScaling and math_clamp(boxHeight * 0.016, 0.5, 1.0) or 1.0
        local distSize = 12 * cachedCfg.TextScale * dynamicScale
        
        drawings.Distance.Text = string_format("[%dm]", math_floor(distance * 0.28))
        drawings.Distance.Size = distSize
        
        -- Adjust position based on Health Bar if at Bottom
        local distY = boxPosition.Y + boxHeight + 2
        if cachedCfg.HealthBarSide == "Bottom" then
             distY = distY + 6 -- Make room for bar
        end
        
        drawings.Distance.Position = Vector2_new(screenPos.X, distY)
        drawings.Distance.Visible = true
    else
        drawings.Distance.Visible = false
    end
    
    -- Health Bar
    if cachedCfg.ShowHealth and actor.Health then
        local healthPercent = 1
        local hp = actor.Health
        if type(hp) == "number" then
            healthPercent = math_clamp(hp * 0.01, 0, 1)
        end
        
        local barColor = cachedCfg.HealthBarColor or Color3_new(0, 1, 0)
        if cachedCfg.UseHealthGradient then
            barColor = Color3_fromHSV(healthPercent * 0.3, 1, 1) -- Green to Red
        end

        local barSize, barPos, outlineSize, outlinePos
        local hbSide = cachedCfg.HealthBarSide

        if hbSide == "Bottom" then
             local barW = boxWidth * healthPercent
             barSize = Vector2_new(barW, 4)
             barPos = Vector2_new(boxPosition.X, boxPosition.Y + boxHeight + 2)
             outlineSize = Vector2_new(boxWidth + 2, 6)
             outlinePos = Vector2_new(boxPosition.X - 1, boxPosition.Y + boxHeight + 1)
        elseif hbSide == "Right" then
             local barH = boxHeight * healthPercent
             barSize = Vector2_new(2, barH)
             barPos = Vector2_new(boxPosition.X + boxWidth + 3, boxPosition.Y + (boxHeight - barH))
             outlineSize = Vector2_new(4, boxHeight + 2)
             outlinePos = Vector2_new(boxPosition.X + boxWidth + 2, boxPosition.Y - 1)
        else
             local barH = boxHeight * healthPercent
             barSize = Vector2_new(2, barH)
             barPos = Vector2_new(boxPosition.X - 5, boxPosition.Y + (boxHeight - barH))
             outlineSize = Vector2_new(4, boxHeight + 2)
             outlinePos = Vector2_new(boxPosition.X - 6, boxPosition.Y - 1)
        end
        
        drawings.HealthBarOutline.Size = outlineSize
        drawings.HealthBarOutline.Position = outlinePos
        drawings.HealthBarOutline.Visible = true
        
        drawings.HealthBar.Size = barSize
        drawings.HealthBar.Position = barPos
        drawings.HealthBar.Color = barColor
        drawings.HealthBar.Visible = true
    else
        drawings.HealthBar.Visible = false
        drawings.HealthBarOutline.Visible = false
    end
    
    -- Tracers
    if cachedCfg.UseTracers then
        local viewport = Camera.ViewportSize
        drawings.Tracer.From = Vector2_new(viewport.X * 0.5, viewport.Y)
        drawings.Tracer.To = Vector2_new(screenPos.X, boxPosition.Y + boxHeight)
        drawings.Tracer.Color = espData.Color
        drawings.Tracer.Visible = true
    else
        drawings.Tracer.Visible = false
    end
end

--[[
    VEHICLE UPDATE LOOP
    Iterates over VehicleService.Vehicles (Engine Table)
]]
local function HideVehicleESP(espData)
    local drawings = espData.Drawing
    drawings.Box.Visible = false
    drawings.BoxOutline.Visible = false
    drawings.Name.Visible = false
    drawings.Distance.Visible = false
    drawings.HealthBar.Visible = false
    drawings.HealthBarOutline.Visible = false
    if drawings.Corners then for _, l in ipairs(drawings.Corners) do l.Visible = false end end
end

local function UpdateESPForVehicle(uid, espData, vehicle, currentFrameId)
    local pos = nil
    -- OPTIMIZATION: vehicle.CFrame.Position is engine-maintained; avoid PrimaryPart lookup
    pos = (vehicle.Model.PrimaryPart and vehicle.Model.PrimaryPart.Position) or vehicle.CFrame.Position
    
    -- OPTIMIZATION: Cache camera position for vehicle ESP distance calc
    local camPos = Camera.CFrame.Position
    local dv = camPos - pos
    local dist = math.sqrt(dv.X*dv.X + dv.Y*dv.Y + dv.Z*dv.Z) -- Faster than .Magnitude
    
    if dist > Config.MaxDistance then
        HideVehicleESP(espData)
        return
    end

    local screenPos, onScreen = Camera:WorldToViewportPoint(pos)
    
    if not onScreen then
        HideVehicleESP(espData)
        return
    end
    
    espData.LastUpdate = currentFrameId
    
    -- OPTIMIZATION: Cache vehicle extents size (expensive call)
    if not espData._cachedSize or (currentFrameId % 60 == 0) then
        espData._cachedSize = vehicle.Model:GetExtentsSize()
    end
    local size = espData._cachedSize
    local height = size.Y
    local width = math.max(size.X, size.Z)
    local boxSize = Vector2.new(1000/dist * width, 1000/dist * height) * (Config.BoxScale or 1.0)
    local boxPos = Vector2.new(screenPos.X - boxSize.X/2, screenPos.Y - boxSize.Y/2)
    local boxHeight = boxSize.Y
    local boxWidth = boxSize.X
    
    local drawings = espData.Drawing
    local boxColor = Config.VehicleColor or Color3.new(0, 1, 1)

    -- BOX
    if Config.ShowVehicleBox then
        -- Update Outline First (Background) - Size offset to prevent occlusion
        drawings.BoxOutline.Color = Color3.new(0,0,0)
        drawings.BoxOutline.Transparency = 1
        drawings.BoxOutline.Thickness = 1 -- Back to 1px
        drawings.BoxOutline.Size = boxSize + Vector2.new(2, 2)
        drawings.BoxOutline.Position = boxPos - Vector2.new(1, 1)
        drawings.BoxOutline.ZIndex = 0
        
        -- Update Main Box Second (Foreground)
        drawings.Box.Color = boxColor
        drawings.Box.Transparency = 1
        drawings.Box.Thickness = 1 -- Back to 1px
        drawings.Box.Size = boxSize
        drawings.Box.Position = boxPos
        drawings.Box.ZIndex = 5
        
        if Config.VehicleBoxStyle == "Corner" then
             drawings.Box.Visible = false
             drawings.BoxOutline.Visible = false
             
             if drawings.Corners then
                 local cornerLength = math.min(boxWidth, boxHeight) * 0.25
                 local c = drawings.Corners
                 
                 -- TL
                 c[1].From = Vector2.new(boxPos.X, boxPos.Y); c[1].To = Vector2.new(boxPos.X + cornerLength, boxPos.Y)
                 c[2].From = Vector2.new(boxPos.X, boxPos.Y); c[2].To = Vector2.new(boxPos.X, boxPos.Y + cornerLength)
                 -- TR
                 c[3].From = Vector2.new(boxPos.X + boxWidth, boxPos.Y); c[3].To = Vector2.new(boxPos.X + boxWidth - cornerLength, boxPos.Y)
                 c[4].From = Vector2.new(boxPos.X + boxWidth, boxPos.Y); c[4].To = Vector2.new(boxPos.X + boxWidth, boxPos.Y + cornerLength)
                 -- BL
                 c[5].From = Vector2.new(boxPos.X, boxPos.Y + boxHeight); c[5].To = Vector2.new(boxPos.X + cornerLength, boxPos.Y + boxHeight)
                 c[6].From = Vector2.new(boxPos.X, boxPos.Y + boxHeight); c[6].To = Vector2.new(boxPos.X, boxPos.Y + boxHeight - cornerLength)
                 -- BR
                 c[7].From = Vector2.new(boxPos.X + boxWidth, boxPos.Y + boxHeight); c[7].To = Vector2.new(boxPos.X + boxWidth - cornerLength, boxPos.Y + boxHeight)
                 c[8].From = Vector2.new(boxPos.X + boxWidth, boxPos.Y + boxHeight); c[8].To = Vector2.new(boxPos.X + boxWidth, boxPos.Y + boxHeight - cornerLength)
                 
                 for _, l in ipairs(c) do
                     l.Color = boxColor
                     l.Transparency = 1
                     l.Thickness = 1
                     l.ZIndex = 5
                     l.Visible = true
                 end
             end
        else
            if drawings.Corners then for _,l in pairs(drawings.Corners) do l.Visible = false end end
            
            drawings.BoxOutline.Visible = true
            drawings.Box.Visible = true
        end
    else
        drawings.Box.Visible = false
        drawings.BoxOutline.Visible = false
        if drawings.Corners then for _,l in pairs(drawings.Corners) do l.Visible = false end end
    end
    
    -- NAME
    if Config.ShowVehicleName then
        local dynamicScale = Config.DynamicTextScaling and math.clamp(boxHeight / 60, 0.5, 1.0) or 1.0
        local nameSize = 13 * (Config.TextScale or 1) * dynamicScale
        
        local name = vehicle._vehicleName or (vehicle.Model and vehicle.Model.Name) or "Vehicle"
        drawings.Name.Text = name
        drawings.Name.Size = nameSize
        drawings.Name.Position = Vector2.new(screenPos.X, boxPos.Y - (nameSize + 3))
        drawings.Name.Color = boxColor
        drawings.Name.ZIndex = 3
        drawings.Name.Outline = true
        drawings.Name.Visible = true
    else
        drawings.Name.Visible = false
    end
    
    -- DISTANCE
    if Config.ShowDistance then
        local dynamicScale = Config.DynamicTextScaling and math.clamp(boxHeight / 60, 0.5, 1.0) or 1.0
        local distSize = 12 * (Config.TextScale or 1) * dynamicScale
        
        local meters = math.floor(dist * 0.28) -- Convert studs to meters approx
        drawings.Distance.Text = string.format("[%dm]", meters)
        drawings.Distance.Size = distSize
        drawings.Distance.Color = boxColor
        drawings.Distance.ZIndex = 3
        drawings.Distance.Outline = true
        
        -- Position at bottom, adjusting for health bar if needed
        local distY = boxPos.Y + boxHeight + 2
        if Config.ShowVehicleHealth and Config.VehicleHealthBarSide == "Bottom" then
             distY = distY + 6
        end
        drawings.Distance.Position = Vector2.new(screenPos.X, distY)
        drawings.Distance.Visible = true
    else
        drawings.Distance.Visible = false
    end
    
    -- HEALTH
    if Config.ShowVehicleHealth and vehicle.Healths then
         local currentHp = 0
         local maxHp = 0
         for _, v in pairs(vehicle.Healths) do 
             if type(v) == "number" then currentHp = currentHp + v; maxHp = maxHp + 100 end
         end
         if maxHp == 0 then maxHp = 100 end
         local hpPercent = math.clamp(currentHp / maxHp, 0, 1)
         
         local barColor = Config.VehicleHealthColor or Color3.new(0,1,0)
         if Config.UseHealthGradient then
             barColor = Color3.fromHSV(hpPercent * 0.3, 1, 1) -- Red-Green gradient
         end
         
         local barSize, barPos, outlineSize, outlinePos
         
         if Config.VehicleHealthBarSide == "Bottom" then
             local barW = boxWidth * hpPercent
             barSize = Vector2.new(barW, 4)
             barPos = Vector2.new(boxPos.X, boxPos.Y + boxHeight + 2)
             outlineSize = Vector2.new(boxWidth + 2, 6)
             outlinePos = Vector2.new(boxPos.X - 1, boxPos.Y + boxHeight + 1)
         elseif Config.VehicleHealthBarSide == "Right" then
             local barW = 2
             local barH = boxHeight * hpPercent
             barSize = Vector2.new(barW, barH)
             barPos = Vector2.new(boxPos.X + boxWidth + 3, boxPos.Y + (boxHeight - barH))
             outlineSize = Vector2.new(barW + 2, boxHeight + 2)
             outlinePos = Vector2.new(boxPos.X + boxWidth + 2, boxPos.Y - 1)
         else -- Left
             local barW = 2
             local barH = boxHeight * hpPercent
             barSize = Vector2.new(barW, barH)
             barPos = Vector2.new(boxPos.X - 5, boxPos.Y + (boxHeight - barH))
             outlineSize = Vector2.new(barW + 2, boxHeight + 2)
             outlinePos = Vector2.new(boxPos.X - 6, boxPos.Y - 1)
         end
         
         -- Draw Outline First (Background) - Size offset
         drawings.HealthBarOutline.Size = outlineSize + Vector2.new(2, 2)
         drawings.HealthBarOutline.Position = outlinePos - Vector2.new(1, 1)
         drawings.HealthBarOutline.Color = Color3.new(0,0,0)
         drawings.HealthBarOutline.Transparency = 1
         drawings.HealthBarOutline.Thickness = 1
         drawings.HealthBarOutline.ZIndex = 0
         drawings.HealthBarOutline.Visible = true

         -- Draw Bar Second (Foreground)
         drawings.HealthBar.Size = barSize
         drawings.HealthBar.Position = barPos
         drawings.HealthBar.Color = barColor
         drawings.HealthBar.Transparency = 1
         drawings.HealthBar.ZIndex = 5
         drawings.HealthBar.Visible = true
    else
         drawings.HealthBar.Visible = false
         drawings.HealthBarOutline.Visible = false
    end
end

local function UpdateVehicles(frameId, cachedCfg)
    if not Config.ShowVehicles then return end
    if not ActorManager.Initialized then return end
    
    local localActor = ReplicatorService and ReplicatorService.LocalActor
    local myVehUID = nil
    if localActor then
        -- Correct UID detection from Seat/Turret
        if localActor.Seat then 
            myVehUID = localActor.Seat.UID or (localActor.Seat.Model and localActor.Seat.Model.Name)
        end
        if not myVehUID and localActor.Turret and localActor.Turret._uid then 
            -- Turret Controller UID is often vehicleUID_TurretIndex, but we check _vehicle ref
            if localActor.Turret._vehicle then 
                myVehUID = localActor.Turret._vehicle.UID
            else
                myVehUID = localActor.Turret._uid:split("_")[1]
            end
        end
    end
    
    for _, actor in ipairs(ActorManager.Vehicles) do
        local uid = "Veh_" .. tostring(actor.UID)
        local espData = ESPElements[uid]
        
        -- Ignore Local Vehicle Logic
        local isLocal = (myVehUID == actor.UID)
        if Config.IgnoreLocalVehicle and isLocal then
            if espData and espData._visible ~= false then
                HideVehicleESP(espData)
                if espData.Highlight then espData.Highlight.Enabled = false end
                espData._visible = false
            end
            continue
        end
        
        -- Create if missing
        if not espData then
            espData = {
                Drawing = CreateDrawingESP(),
                Type = "Vehicle",
                LastUpdate = frameId,
                _visible = true
            }
            ESPElements[uid] = espData
        end
        
        espData._visible = true
        UpdateESPForVehicle(actor.UID, espData, actor, frameId)
    end
end

-- IsEnemy helper for Hitbox Expander
local function IsEnemyForExpander(player)
    if not player or not LocalPlayer then return false end
    -- If using team system
    if player.Team and LocalPlayer.Team and player.Team == LocalPlayer.Team then return false end
    -- Fallback/Safety: consider everyone else enemy if not same team
    return true
end

-- Hitbox expander merged into ESP loop

-- Server Hide Hook (Spoof Size property)
task.spawn(function()
    if not getrawmetatable then return end
    local mt = getrawmetatable(game)
    setreadonly(mt, false)
    local oldIndex = mt.__index
    
    mt.__index = newcclosure(function(self, key)
        if key == "Size" and Config.HitboxExpander and OriginalSizes[self] then
            return OriginalSizes[self]
        end
        
        if type(oldIndex) == "function" then
            local success, result = pcall(oldIndex, self, key)
            if success then return result end
        elseif type(oldIndex) == "table" then
             local success, result = pcall(function() return oldIndex[key] end)
             if success then return result end
        end
        return nil 
    end)
    setreadonly(mt, true)
end)

-- OPTIMIZATION: Module-level cached config (avoid per-frame table allocation)
local _cachedCfg = {}
local _cachedCfgFrame = -30

local function RefreshCachedCfg()
    _cachedCfg.MaxDistance = Config.MaxDistance or 1000
    _cachedCfg.UseBoxESP = Config.UseBoxESP
    _cachedCfg.BoxStyle = Config.BoxStyle
    _cachedCfg.BoxScale = Config.BoxScale or 1
    _cachedCfg.BoxColor = Config.BoxColor
    _cachedCfg.ShowNames = Config.ShowNames
    _cachedCfg.ShowDistance = Config.ShowDistance
    _cachedCfg.ShowHealth = Config.ShowHealth
    _cachedCfg.HealthBarSide = Config.HealthBarSide
    _cachedCfg.HealthBarColor = Config.HealthBarColor
    _cachedCfg.UseHealthGradient = Config.UseHealthGradient
    _cachedCfg.UseTracers = Config.UseTracers
    _cachedCfg.UseHighlight = Config.UseHighlight
    _cachedCfg.SimpleESP = Config.SimpleESP
    _cachedCfg.TextScale = (Config.TextScale or 1.2)
    _cachedCfg.DynamicTextScaling = true
    _cachedCfg.HitboxExpander = Config.HitboxExpander
    _cachedCfg.HitboxSize = Config.HitboxSize
end

local function UpdateESP()
    if not ESPEnabled and not Config.HitboxExpander then return end
    if not ReplicatorService then return end
    
    CurrentFrameId = CurrentFrameId + 1
    local localSquad = ClientService and ClientService.LocalClient and ClientService.LocalClient.Squad
    
    -- OPTIMIZATION: Refresh config cache every 30 frames instead of every frame
    if CurrentFrameId - _cachedCfgFrame >= 30 then
        RefreshCachedCfg()
        _cachedCfgFrame = CurrentFrameId
    end
    local cachedCfg = _cachedCfg
    
    -- Process Actor Lists
    local function Process(list)
        for _, actor in ipairs(list) do
            -- Early exit if hidden (Pre-calculated in ActorManager)
            if actor._cachedShow == false then
                 if ESPElements[actor.UID] then RemoveESP(actor.UID) end
                 continue 
            end

            local uid = actor.UID
            if not uid then continue end
            if not ESPElements[uid] then CreateESPForActor(actor, localSquad) end
            local espData = ESPElements[uid]
            if espData then
                -- Throttle Color Updates
                if (CurrentFrameId % 30) == 0 then
                    espData.Color = GetEntityColor(actor, actor._entityType, localSquad)
                end
                UpdateESPForActor(uid, espData, CurrentFrameId, cachedCfg, localSquad)
            end
        end
    end
    
    if ActorManager.Initialized then
        Process(ActorManager.Enemies)
        Process(ActorManager.Teammates)
    end
    
    -- OPTIMIZATION: Cleanup stale ESP elements every 10 frames (not every frame)
    if CurrentFrameId % 10 == 0 then
        for uid, espData in pairs(ESPElements) do
            if espData.Type ~= "Vehicle" and espData.LastUpdate < CurrentFrameId - 5 then
                RemoveESP(uid)
            end
        end
    end
end

--[[
    INITIALIZATION
]]
-- Initialize Comp Notifier
local Notifier = Compkiller.newNotify();

-- ══════════════════════════════════════════════════════
-- PREMIUM THEME: Override default colors for a unique look
-- ══════════════════════════════════════════════════════
Compkiller.Colors.Highlight = Color3.fromRGB(160, 120, 255)       -- Purple accent
Compkiller.Colors.Toggle = Color3.fromRGB(140, 100, 235)          -- Toggle active
Compkiller.Colors.Risky = Color3.fromRGB(255, 200, 60)            -- Gold risky warning
Compkiller.Colors.BGDBColor = Color3.fromRGB(18, 18, 24)          -- Darker background
Compkiller.Colors.BlockColor = Color3.fromRGB(24, 24, 32)         -- Section blocks
Compkiller.Colors.StrokeColor = Color3.fromRGB(40, 38, 50)        -- Borders
Compkiller.Colors.DropColor = Color3.fromRGB(30, 28, 38)          -- Dropdowns
Compkiller.Colors.MouseEnter = Color3.fromRGB(50, 45, 65)         -- Hover highlight
Compkiller.Colors.BlockBackground = Color3.fromRGB(34, 32, 44)    -- Inner blocks
Compkiller.Colors.LineColor = Color3.fromRGB(55, 50, 70)          -- Separator lines
Compkiller.Colors.HighStrokeColor = Color3.fromRGB(60, 55, 75)    -- Highlight borders

-- Enable Premium Features
Compkiller:CustomIconHighlight() -- Auto-colorize ALL icons to match purple theme

-- Loader (Beautification)
Compkiller:Loader("rbxassetid://120245531583106" , 2).yield();

-- Progress Notification (step-by-step loading feedback)
local loadNotify = Notifier.new({
    Title = "BRM5 PRO",
    Content = "Initializing...",
    Duration = math.huge,
    Icon = "rbxassetid://120245531583106"
})
pcall(function() loadNotify:SetProgress(0.1, 0.3) end)
task.wait(0.15)

-- Create Window
local Window = Compkiller.new({
    Name = "BRM5 | Lubiebf4",
    Keybind = "LeftAlt",
    Logo = "rbxassetid://120245531583106",
    Scale = Compkiller.Scale.Window,
    TextSize = 15,
});

-- Store GUI reference for Singleton cleanup
if Window and Window.Screen then
    getgenv().Blackhawk_GUI = Window.Screen
end

-- Initialize Config Manager
local _ConfigManager = Compkiller:ConfigManager({ 
    Directory = "BlackhawkESP", 
    Config = "BRM5" 
})
_ConfigManager.EnableNotify = true

-- Update Window Header (Username + Avatar)
Window:Update({
    Username = LocalPlayer.DisplayName,
    ExpireDate = "PREMIUM",
    WindowName = "BRM5",
    Logo = "rbxassetid://120245531583106"
})

-- Watermark HUD (Top-Right Corner)
local WM = Window:Watermark()
WM:AddText({ Icon = "zap", Text = "BRM5" })
WM:AddText({ Icon = "user", Text = LocalPlayer.DisplayName })
local wmFPS = WM:AddText({ Icon = "activity", Text = "0 FPS" })
local wmPing = WM:AddText({ Icon = "wifi", Text = "0ms" })

-- Update FPS + Ping in Watermark
-- OPTIMIZATION: FPS watermark without blocking RenderStepped:Wait()
local _wmFrameCount = 0
local _wmLastUpdate = 0
RunService.RenderStepped:Connect(function()
    _wmFrameCount = _wmFrameCount + 1
    local now = tick()
    if now - _wmLastUpdate >= 1 then
        pcall(function()
            local fps = math.floor(_wmFrameCount / (now - _wmLastUpdate))
            if wmFPS and wmFPS.SetText then
                wmFPS:SetText(tostring(fps) .. " FPS")
            end
            local ping = math.floor(game:GetService("Stats").Network.ServerStatsItem["Data Ping"]:GetValue())
            if wmPing and wmPing.SetText then
                wmPing:SetText(tostring(ping) .. "ms")
            end
        end)
        _wmFrameCount = 0
        _wmLastUpdate = now
    end
end)

-- ══════════════════════════════════════════════════════
-- HOME TAB (Welcome & Info) — Premium Layout
-- ══════════════════════════════════════════════════════
local HomeTab = Window:DrawTab({ Name = "Home", Icon = "home", Type = "Double" })

-- ── LEFT COLUMN: Welcome + Features ──
local S_Welcome = HomeTab:DrawSection({ Name = "Welcome", Position = "left" })

S_Welcome:AddParagraph({
    Title = '<font color="rgb(160,120,255)">⚡</font>  BRM5 PREM  <font color="rgb(100,100,120)">v2.1</font>',
    Content = 'Welcome, <font color="rgb(160,120,255)"><b>' .. LocalPlayer.DisplayName .. '</b></font>!\nYou are running the <font color="rgb(255,200,60)">Premium</font> edition.'
})

S_Welcome:AddParagraph({
    Title = '<font color="rgb(160,120,255)">♦</font>  Credits',
    Content = 'Developer: <font color="rgb(160,120,255)">Lubiebf4</font>\nUI Framework: <font color="rgb(140,100,235)">Compkiller</font> by 4lpaca'
})

local S_Features = HomeTab:DrawSection({ Name = "Features", Position = "left" })

S_Features:AddParagraph({
    Title = '<font color="rgb(160,120,255)">🎯</font>  Combat',
    Content = '<font color="rgb(200,200,220)">Silent Aim  ·  Ragebot  ·  No Recoil\nNo Spread  ·  Custom RPM  ·  Spinbot</font>'
})

S_Features:AddParagraph({
    Title = '<font color="rgb(160,120,255)">👁</font>  Visuals',
    Content = '<font color="rgb(200,200,220)">Box ESP  ·  Corner ESP  ·  Highlight\nHealth Bars  ·  Tracers  ·  Name Tags</font>'
})

S_Features:AddParagraph({
    Title = '<font color="rgb(160,120,255)">🚀</font>  Movement',
    Content = '<font color="rgb(200,200,220)">Vehicle Fly  ·  Speed Hack  ·  Noclip\nHitbox Expander  ·  Vehicle Teleport</font>'
})

-- ── RIGHT COLUMN: Changelog + Server ──
local S_Changelog = HomeTab:DrawSection({ Name = "Changelog", Position = "right" })

S_Changelog:AddParagraph({
    Title = '<font color="rgb(255,200,60)">★</font>  v3.0 — Security Update',
    Content = '<font color="rgb(130,255,130)">+</font> Improved Ragebot Logic\n' ..
              '<font color="rgb(130,255,130)">+</font> Added Auto Reload System\n' ..
              '<font color="rgb(130,255,130)">+</font> Added Queue on Teleport\n' ..
              '<font color="rgb(130,255,130)">+</font> Optimized Loading Speed\n' ..
              '<font color="rgb(130,255,130)">+</font> Enhanced Security\n' ..
              '<font color="rgb(130,255,130)">+</font> Menu Execute Handler\n' ..
              '<font color="rgb(130,255,130)">+</font> Added Free User Detection (Kick)'
})

local S_Server = HomeTab:DrawSection({ Name = "Info", Position = "right" })

-- Dynamic Keybinds Paragraph (updates when keybinds change)
local KeybindsInfo = S_Server:AddParagraph({
    Title = '<font color="rgb(160,120,255)">⌨</font>  Keybinds',
    Content = '<font color="rgb(255,200,60)">LeftAlt</font> — Toggle Menu\n<font color="rgb(255,200,60)">V</font> — Character Fly\n<font color="rgb(255,200,60)">X</font> — Vehicle Fly'
})

-- Global update function for keybinds display
getgenv()._KeybindDisplayKeys = { Menu = "LeftAlt", CharFly = "V", VehFly = "X" }
getgenv()._UpdateKeybindDisplay = function()
    pcall(function()
        local k = getgenv()._KeybindDisplayKeys
        local text = '<font color="rgb(255,200,60)">' .. tostring(k.Menu) .. '</font> — Toggle Menu'
            .. '\n<font color="rgb(255,200,60)">' .. tostring(k.CharFly) .. '</font> — Character Fly'
            .. '\n<font color="rgb(255,200,60)">' .. tostring(k.VehFly) .. '</font> — Vehicle Fly'
        if KeybindsInfo and KeybindsInfo.SetContent then
            KeybindsInfo:SetContent(text)
        end
    end)
end

S_Server:AddParagraph({
    Title = '<font color="rgb(160,120,255)">💡</font>  Tip',
    Content = '<font color="rgb(200,200,220)">Right-click any toggle to assign\na custom keybind to it.</font>'
})

S_Server:AddParagraph({
    Title = '<font color="rgb(160,120,255)">🌐</font>  Server',
    Content = 'Place: <font color="rgb(160,120,255)">' .. tostring(game.PlaceId) .. '</font>\nJob: <font color="rgb(100,100,120)">' .. string.sub(tostring(game.JobId), 1, 12) .. '...</font>'
})

S_Server:AddButton({
    Name = "📋  Copy Server Link",
    Callback = function()
        pcall(function()
            setclipboard("roblox://experiences/start?placeId=" .. tostring(game.PlaceId) .. "&gameInstanceId=" .. tostring(game.JobId))
        end)
        if Notifier and Notifier.new then
            Notifier.new({ Title = "Copied!", Content = "Server join link copied to clipboard.", Duration = 3, Icon = "rbxassetid://120245531583106" })
        end
    end
})

pcall(function() loadNotify:Content("Building Combat tab...") end)
pcall(function() loadNotify:SetProgress(0.3, 0.3) end)
task.wait(0.1)

-- Combat Tab
local CombatTab = Window:DrawTab({ Name = "Combat", Icon = "swords", Type = "Double" })

-- Rage Section
local S_Rage = CombatTab:DrawSection({ Name = "Ragebot", Position = "right" })

S_Rage:AddToggle({ 
    Name = "Enabled", 
    Flag = "Rage_Enabled", 
    Default = false,
    Callback = function(v) 
        Config.RageMode = v
    end 
})


S_Rage:AddToggle({ 
    Name = "Look At Target", 
    Flag = "Rage_LookAt", 
    Default = false,
    Callback = function(v) 
        Config.Rage_LookAt = v
    end 
})

S_Rage:AddSlider({
    Name = "Rage Range",
    Flag = "Rage_Range",
    Min = 50,
    Max = 2000,
    Default = 500,
    Callback = function(v)
        Config.Rage_Range = v
    end
})

S_Rage:AddDropdown({
    Name = "Target Part",
    Flag = "Rage_TargetPart",
    Default = "Head",
    Values = { "Head", "UpperTorso" },
    Callback = function(v)
        Config.Rage_TargetPart = v
    end
})

S_Rage:AddToggle({ 
    Name = "Auto Fire", 
    Flag = "Rage_AutoFire", 
    Default = false,
    Callback = function(v) 
        Config.Rage_AutoFire = v
    end 
})

S_Rage:AddSlider({ 
    Name = "Burst Size", 
    Flag = "Rage_BurstSize", 
    Min = 1, 
    Max = 10, 
    Default = 1, 
    Callback = function(v) 
        Config.Rage_BurstSize = v 
    end 
})


-- Gun Mods Section
local S_GunMods = CombatTab:DrawSection({ Name = "Gun Mods", Position = "right" })

-- Silent Aim Section
local S_SilentAim = CombatTab:DrawSection({ Name = "Silent Aim", Position = "left" })

S_SilentAim:AddToggle({ 
    Name = "Enabled", 
    Flag = "Combat_SilentAim", 
    Default = false,
    Callback = function(v) 
        Config.SilentAim = v
    end 
})


S_SilentAim:AddToggle({ 
    Name = "Show FOV", 
    Flag = "Combat_ShowFOV", 
    Default = false,
    Callback = function(v) 
        Config.ShowFOV = v
    end 
})

S_SilentAim:AddToggle({ 
    Name = "Show Weapon Info", 
    Flag = "Combat_ShowWeaponInfo", 
    Default = true,
    Callback = function(v) 
        Config.ShowWeaponInfo = v
    end 
})

S_SilentAim:AddSlider({ 
    Name = "FOV Radius", 
    Min = 10, 
    Max = 500, 
    Default = 100, 
    Flag = "Combat_SilentAimFOV", 
    Callback = function(v) 
        Config.SilentAimFOV = v
    end 
})

S_SilentAim:AddSlider({ 
    Name = "Hit Chance", 
    Min = 0, 
    Max = 100, 
    Default = 100, 
    Flag = "Combat_SilentAimChance", 
    Callback = function(v) 
        Config.SilentAimHitChance = v
    end 
})

S_SilentAim:AddDropdown({
    Name = "Target Part",
    Default = "Head",
    Values = {
        "Head", "UpperTorso", "LowerTorso",
        "LeftUpperArm", "LeftLowerArm", "LeftHand",
        "RightUpperArm", "RightLowerArm", "RightHand",
        "LeftUpperLeg", "LeftLowerLeg", "LeftFoot",
        "RightUpperLeg", "RightLowerLeg", "RightFoot"
    },
    Flag = "Combat_SilentAimPart",
    Callback = function(v)
        Config.SilentAimTargetPart = v
    end
})

S_SilentAim:AddToggle({ 
    Name = "Prediction", 
    Flag = "Combat_Prediction", 
    Default = false,
    Callback = function(v) 
        Config.Prediction = v
    end 
})


S_SilentAim:AddToggle({ 
    Name = "Bullet Drop", 
    Flag = "ESP_BulletDrop", 
    Default = false,
    Callback = function(v) 
        Config.BulletDrop = v
    end 
})

S_SilentAim:AddToggle({ 
    Name = "Triggerbot", 
    Flag = "Combat_Triggerbot", 
    Default = false,
    Callback = function(v) 
        Config.Triggerbot = v
    end 
})

-- Hitbox Expander
S_SilentAim:AddToggle({ 
    Name = "Hitbox Expander", 
    Flag = "Comb_HitboxExpander", 
    Default = false,
    Callback = function(v) 
        Config.HitboxExpander = v
        if not v then
            -- Reset hitboxes when disabled
            -- This requires a function reference, waiting for implementation
        end
    end 
})


S_SilentAim:AddSlider({ 
    Name = "Hitbox Size", 
    Min = 2, 
    Max = 15, 
    Default = 4, 
    Flag = "Comb_HitboxSize", 
    Callback = function(v) 
        Config.HitboxSize = v
    end 
})



S_GunMods:AddToggle({ 
    Name = "No Recoil", 
    Flag = "Combat_NoRecoil", 
    Default = false,
    Callback = function(v) 
        Config.NoRecoil = v
    end 
})


S_GunMods:AddToggle({ 
    Name = "No Spread", 
    Flag = "Combat_NoSpread", 
    Default = false,
    Callback = function(v) 
        Config.NoSpread = v
    end 
})

S_GunMods:AddToggle({ 
    Name = "Auto Reload", 
    Flag = "Combat_AutoReload", 
    Default = true,
    Callback = function(v) 
        Config.AutoReload = v
    end 
})

S_GunMods:AddToggle({ 
    Name = "Unlock Firemodes", 
    Flag = "Combat_Firemodes", 
    Default = false,
    Callback = function(v) 
        Config.UnlockFiremodes = v
    end 
})

S_GunMods:AddToggle({ 
    Name = "Custom RPM", 
    Flag = "Combat_CustomRPM", 
    Default = false,
    Callback = function(v) 
        Config.CustomRPM = v
    end 
})

S_GunMods:AddSlider({ 
    Name = "RPM Value", 
    Min = 100, 
    Max = 3000, 
    Default = 800, 
    Flag = "Combat_RPMValue", 
    Callback = function(v) 
        Config.RPMValue = v
    end 
})

pcall(function() loadNotify:Content("Building ESP tab...") end)
pcall(function() loadNotify:SetProgress(0.5, 0.3) end)
task.wait(0.1)

-- Visuals Tab
local VisualsTab = Window:DrawTab({ Name = "ESP", Icon = "eye", Type = "Double" })

-- ESP Settings Section
local S_ESP = VisualsTab:DrawSection({ Name = "ESP Settings", Position = "left" })

S_ESP:AddToggle({ 
    Name = "Enable ESP", 
    Flag = "ESP_Enabled", 
    Default = false,
    Callback = function(v) 
        ESPEnabled = v
        if not v then
            for uid in pairs(ESPElements) do
                RemoveESP(uid)
            end
        end
    end 
})


S_ESP:AddToggle({ 
    Name = "Simple ESP (Optimized)", 
    Flag = "ESP_Simple", 
    Default = false,
    Callback = function(v) 
        Config.SimpleESP = v
        -- Clear ESP to refresh with new mode
        for uid in pairs(ESPElements) do
            RemoveESP(uid)
        end
    end 
})

S_ESP:AddToggle({ 
    Name = "Box ESP", 
    Flag = "ESP_Box", 
    Default = true,
    Callback = function(v) 
        Config.UseBoxESP = v
        -- Clear ESP to refresh with new settings
        for uid in pairs(ESPElements) do
            RemoveESP(uid)
        end
    end 
})

S_ESP:AddToggle({ 
    Name = "Highlight ESP", 
    Flag = "ESP_Highlight", 
    Default = false,
    Callback = function(v) 
        Config.UseHighlight = v
        -- Clear ESP to refresh with new settings
        for uid in pairs(ESPElements) do
            RemoveESP(uid)
        end
    end 
})

S_ESP:AddToggle({ 
    Name = "Tracers", 
    Flag = "ESP_Tracers", 
    Default = false,
    Callback = function(v) 
        Config.UseTracers = v
        -- Clear ESP to refresh with new settings
        for uid in pairs(ESPElements) do
            RemoveESP(uid)
        end
    end 
})

S_ESP:AddToggle({ 
    Name = "Show Names", 
    Flag = "ESP_Names", 
    Default = true,
    Callback = function(v) 
        Config.ShowNames = v
    end 
})

S_ESP:AddToggle({ 
    Name = "Show Distance", 
    Flag = "ESP_Distance", 
    Default = true,
    Callback = function(v) 
        Config.ShowDistance = v
    end 
})

S_ESP:AddToggle({ 
    Name = "Show Health", 
    Flag = "ESP_Health", 
    Default = true,
    Callback = function(v) 
        Config.ShowHealth = v
    end 
})

S_ESP:AddToggle({ 
    Name = "Show Prediction", 
    Flag = "ESP_ShowPred", 
    Default = false,
    Callback = function(v) 
        Config.ShowPrediction = v
    end 
})


S_ESP:AddColorPicker({ 
    Name = "Prediction Color", 
    Default = Config.PredictionColor,
    Flag = "ESP_PredColor", 
    Callback = function(v) 
        Config.PredictionColor = v
        local dot = getgenv().PredictionDot
        if dot then
            dot.Color = v
        end
    end 
})


Config.TextScale = 1.2


S_ESP:AddSlider({ 
    Name = "Max Distance (m)", 
    Min = 25, 
    Max = 3000, 
    Default = 1000, -- ~1000 studs
    Flag = "ESP_MaxDist", 
    Callback = function(v) 
        -- Convert meters to studs for internal use (1m ≈ 3.57 studs)
        Config.MaxDistance = math.floor(v * 3.57)
    end 
})

-- Entity Filters Section
local S_Filters = VisualsTab:DrawSection({ Name = "Entity Filters", Position = "right" })

S_Filters:AddToggle({ 
    Name = "Show Players", 
    Flag = "ESP_Players", 
    Default = true,
    Callback = function(v) 
        Config.ShowPlayers = v
        -- Clear ESP to refresh with new filters
        for uid in pairs(ESPElements) do
            RemoveESP(uid)
        end
    end 
})

S_Filters:AddToggle({ 
    Name = "Show Zombies", 
    Flag = "ESP_Zombies", 
    Default = true,
    Callback = function(v) 
        Config.ShowZombies = v
        -- Clear ESP to refresh with new filters
        for uid in pairs(ESPElements) do
            RemoveESP(uid)
        end
    end 
})

S_Filters:AddToggle({ 
    Name = "Show NPCs", 
    Flag = "ESP_NPCs", 
    Default = true,
    Callback = function(v) 
        Config.ShowNPCs = v
        -- Clear ESP to refresh with new filters
        for uid in pairs(ESPElements) do
            RemoveESP(uid)
        end
    end 
})



S_Filters:AddToggle({ 
    Name = "Show teammates", 
    Flag = "ESP_Squad", 
    Default = false,
    Callback = function(v) 
        Config.ShowSquadMembers = v
        -- Clear ESP to refresh with new filters
        for uid in pairs(ESPElements) do
            RemoveESP(uid)
        end
    end 
})

S_Filters:AddButton({ 
    Name = "Clear All ESP", 
    Callback = function() 
        for uid in pairs(ESPElements) do
            RemoveESP(uid)
        end
    end 
})

-- Colors Section
local S_Colors = VisualsTab:DrawSection({ Name = "Entity Colors", Position = "right" })

S_Colors:AddColorPicker({
    Name = "Player (Enemy)",
    Flag = "Color_Player",
    Default = Config.PlayerColor,
    Callback = function(v)
        Config.PlayerColor = v
    end
})

S_Colors:AddColorPicker({
    Name = "Teammate (Squad)",
    Flag = "Color_Squad",
    Default = Config.SquadColor,
    Callback = function(v)
        Config.SquadColor = v
    end
})

S_Colors:AddColorPicker({
    Name = "NPC",
    Flag = "Color_NPC",
    Default = Config.NPCColor,
    Callback = function(v)
        Config.NPCColor = v
    end
})

S_Colors:AddColorPicker({
    Name = "Zombie: Crippled",
    Flag = "Color_Z_Crippled",
    Default = Config.ZombieColors[1],
    Callback = function(v)
        Config.ZombieColors[1] = v
    end
})

S_Colors:AddColorPicker({
    Name = "Zombie: Slow",
    Flag = "Color_Z_Slow",
    Default = Config.ZombieColors[2],
    Callback = function(v)
        Config.ZombieColors[2] = v
    end
})

S_Colors:AddColorPicker({
    Name = "Zombie: Normal",
    Flag = "Color_Z_Normal",
    Default = Config.ZombieColors[3],
    Callback = function(v)
        Config.ZombieColors[3] = v
    end
})

S_Colors:AddColorPicker({
    Name = "Zombie: Sprinter",
    Flag = "Color_Z_Sprinter",
    Default = Config.ZombieColors[4],
    Callback = function(v)
        Config.ZombieColors[4] = v
    end
})

-- Character Tab
local CharacterTab = Window:DrawTab({ Name = "Character", Icon = "user", Type = "Double" })
local S_Movement = CharacterTab:DrawSection({ Name = "Movement", Position = "left" })

local FlyToggle = S_Movement:AddToggle({ 
    Name = "Fly", 
    Flag = "Char_Fly", 
    Default = false,
    Callback = function(v) 
        Config.Character_Fly = v
        
        -- Reset Fly State when disabling
        if not v and ControllerService and ControllerService.Controller then
            -- Restore physics by un-forcing CFrame
            if ControllerService.Controller.SetCFrame then
                ControllerService.Controller:SetCFrame(nil)
            end
        end
    end 
})

local FlyKey = "V"
FlyToggle.Link:AddKeybind({
    Name = "Fly Key", 
    Flag = "Char_FlyKey", 
    Default = FlyKey,
    Callback = function(v) 
        FlyKey = v
        if getgenv()._KeybindDisplayKeys then getgenv()._KeybindDisplayKeys.CharFly = v end
        if getgenv()._UpdateKeybindDisplay then getgenv()._UpdateKeybindDisplay() end
    end
})

game:GetService("UserInputService").InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    
    -- Fly Toggle
    if FlyKey and FlyKey ~= "None" and (input.KeyCode.Name == FlyKey or input.KeyCode == FlyKey) then
        FlyToggle:SetValue(not FlyToggle:GetValue())
    end
    if Window.Keybind and Window.Keybind ~= "None" and (input.KeyCode.Name == Window.Keybind or input.KeyCode == Window.Keybind) then
    end
end)

S_Movement:AddSlider({ 
    Name = "Fly Speed", 
    Min = 10, 
    Max = 1000, 
    Default = 50, 
    Flag = "Char_FlySpeed", 
    Callback = function(v) 
        Config.Character_FlySpeed = v
    end 

 
})

S_Movement:AddToggle({ 
    Name = "Spinbot", 
    Flag = "Char_Spinbot", 
    Default = false,
    Callback = function(v) 
        Config.Spinbot = v
    end 
})

S_Movement:AddSlider({ 
    Name = "Spin Speed", 
    Min = 1, 
    Max = 100, 
    Default = 20, 
    Flag = "Char_SpinSpeed", 
    Callback = function(v) 
        Config.SpinbotSpeed = v
    end 
})
 
S_Movement:AddToggle({ 
    Name = "Walk Speed", 
    Flag = "Char_WalkSpeedEnabled", 
    Default = false,
    Callback = function(v) 
        Config.Character_WalkSpeedEnabled = v
    end 
})

S_Movement:AddSlider({ 
    Name = "Walk Speed Value", 
    Min = 16, 
    Max = 100, 
    Default = 16, 
    Flag = "Char_WalkSpeed", 
    Callback = function(v) 
        Config.Character_WalkSpeed = v
    end 
})

S_Movement:AddToggle({ 
    Name = "Sprint Speed", 
    Flag = "Char_SprintSpeedEnabled", 
    Default = false,
    Callback = function(v) 
        Config.Character_SprintSpeedEnabled = v
    end 
})

S_Movement:AddSlider({ 
    Name = "Sprint Speed Value", 
    Min = 25, 
    Max = 100, 
    Default = 25, 
    Flag = "Char_SprintSpeed", 
    Callback = function(v) 
        Config.Character_SprintSpeed = v
    end 
})

-- World Section (based on EnvironmentService analysis)
local S_World = CharacterTab:DrawSection({ Name = "World", Position = "right" })

S_World:AddToggle({ 
    Name = "Thermal Vision", 
    Flag = "World_ThermalVision", 
    Default = false,
    Callback = function(v) 
        Config.ThermalVision = v
        -- Use EnvironmentService.FLIR property discovered in service analysis
        if EnvironmentService then
            EnvironmentService.FLIR = v
        end
    end 
})

local NVGColorCorrection = nil

local NVGColors = {
    ["Green"] = Color3.fromRGB(112, 245, 65),  -- Green Phosphor (original)
    ["Blue"] = Color3.fromRGB(165, 233, 255)   -- White Phosphor (blue-ish)
}
local CurrentNVGColor = "Green"

local function ApplyNVGEffect()
    if Config.NightVision and NVGColorCorrection then
        NVGColorCorrection.TintColor = NVGColors[CurrentNVGColor] or NVGColors["Green"]
        -- Exact game values from Tubes.lua
        NVGColorCorrection.Brightness = 0.15
        NVGColorCorrection.Contrast = 0.5
        NVGColorCorrection.Saturation = -1
        NVGColorCorrection.Enabled = true
    end
end

S_World:AddToggle({ 
    Name = "Night Vision", 
    Flag = "World_NightVision", 
    Default = false,
    Callback = function(v) 
        Config.NightVision = v
        
        if v then
            -- Create NVG effect using Lighting ColorCorrectionEffect
            if not NVGColorCorrection then
                NVGColorCorrection = Instance.new("ColorCorrectionEffect")
                NVGColorCorrection.Name = "ESP_NightVision"
                NVGColorCorrection.Parent = game:GetService("Lighting")
            end
            ApplyNVGEffect()
        else
            -- Disable NVG effect
            if NVGColorCorrection then
                NVGColorCorrection.Enabled = false
            end
        end
    end 
})

S_World:AddDropdown({
    Name = "NVG Color",
    Flag = "World_NVGColor",
    Values = {"Green", "Blue"},
    Default = "Green",
    Callback = function(v)
        CurrentNVGColor = v
        ApplyNVGEffect()
    end
})

-- Layout Section
local S_Layout = VisualsTab:DrawSection({ Name = "Layout Settings", Position = "left" })


Config.BoxScale = 1.4 -- Locked default

S_Layout:AddDropdown({
    Name = "Box Style",
    Values = {"Full", "Corner"},
    Default = "Full",
    Flag = "ESP_BoxStyle",
    Callback = function(v)
        Config.BoxStyle = v
    end
})

S_Layout:AddColorPicker({
    Name = "Box Color",
    Flag = "ESP_BoxColorOverride",
    Default = Color3.fromRGB(255, 255, 255),
    Callback = function(v)
        Config.BoxColor = v
    end
})

S_Layout:AddDropdown({
    Name = "Health Bar Position",
    Values = {"Left", "Right", "Bottom"},
    Default = "Left",
    Flag = "ESP_BarPos",
    Callback = function(v)
        Config.HealthBarSide = v
    end
})

S_Layout:AddToggle({
    Name = "Health Gradient",
    Flag = "ESP_BarGrad",
    Default = true,
    Callback = function(v)
        Config.UseHealthGradient = v
    end
})

S_Layout:AddColorPicker({
    Name = "Health Color",
    Flag = "ESP_BarColor",
    Default = Color3.fromRGB(0, 255, 0),
    Callback = function(v)
        Config.HealthBarColor = v
    end
})

-- Vehicle Tab
local VehicleTab = Window:DrawTab({ Name = "Vehicles", Icon = "car", Type = "Double" })
-- local S_Vehicles = VehicleTab:DrawSection({ Name = "Vehicle List", Position = "left" }) -- Removed as empty
local S_VehVisuals = VehicleTab:DrawSection({ Name = "Visuals", Position = "right" })

-- Add Turret Mods Section (Left)
-- Vehicle Fly Section
local S_VehFly = VehicleTab:DrawSection({ Name = "Vehicle Fly", Position = "left" })

local VehFlyToggle = S_VehFly:AddToggle({ 
    Name = "Enable Fly", 
    Flag = "Veh_Fly", 
    Default = Config.VehicleFly_Enabled,
    Callback = function(v) 
        Config.VehicleFly_Enabled = v
    end 
})

local VehFlyKey = Config.VehicleFly_ToggleKey
VehFlyToggle.Link:AddKeybind({
    Name = "Fly Key", 
    Flag = "Veh_FlyKey", 
    Default = VehFlyKey,
    Callback = function(v) 
        VehFlyKey = v
        Config.VehicleFly_ToggleKey = v
        if getgenv()._KeybindDisplayKeys then getgenv()._KeybindDisplayKeys.VehFly = v end
        if getgenv()._UpdateKeybindDisplay then getgenv()._UpdateKeybindDisplay() end
    end
})

S_VehFly:AddSlider({
    Name = "Fly Speed",
    Flag = "Veh_FlySpeed",
    Default = Config.VehicleFly_Speed,
    Min = 10,
    Max = 500,
    Callback = function(v)
        Config.VehicleFly_Speed = v
    end
})

-- Add Turret Mods Section (Left)
local S_VehTurret = VehicleTab:DrawSection({ Name = "Turret Mods", Position = "left" })

S_VehTurret:AddToggle({ 
    Name = "Unlock Firemodes", 
    Flag = "Veh_UnlockFiremodes", 
    Default = false,
    Callback = function(v) 
        Config.TurretUnlockFiremodes = v
    end 
})

S_VehTurret:AddToggle({ 
    Name = "No Recoil", 
    Flag = "Veh_NoRecoil", 
    Default = false,
    Callback = function(v) 
        Config.TurretNoRecoil = v
    end 
})

S_VehTurret:AddToggle({ 
    Name = "No Spread", 
    Flag = "Veh_NoSpread", 
    Default = false,
    Callback = function(v) 
        Config.TurretNoSpread = v
    end 
})

-- Vehicle Teleport Section
local S_VehTeleport = VehicleTab:DrawSection({ Name = "Teleport", Position = "left" })

local NewWaypointName = "Base"
local SelectedWaypoint = nil

S_VehTeleport:AddTextBox({
    Name = "Waypoint Name",
    Flag = "Veh_WayptName",
    Default = "Base",
    Placeholder = "Enter name...",
    Callback = function(v)
        NewWaypointName = v
    end
})

-- Helper to get sorted names
local function GetWaypointNames()
    local names = {}
    for name, _ in pairs(Config.VehicleWaypoints or {}) do
        table.insert(names, name)
    end
    table.sort(names)
    return names
end

local WaypointDropdown = S_VehTeleport:AddDropdown({
    Name = "Select Waypoint",
    Values = GetWaypointNames(),
    Default = "",
    Flag = "Veh_SelectWaypt",
    Callback = function(v)
        SelectedWaypoint = v
    end
})

S_VehTeleport:AddButton({
    Name = "Save Current Params",
    Callback = function()
        local controller = GetActiveVehicleController()

        if not controller or not controller._vehicle then
             Notifier.new({Title = "Error", Content = "Get in a vehicle first!", Duration = 3})
             return
        end
        
        local veh = controller._vehicle
        local pos = veh.Model and veh.Model.PrimaryPart and veh.Model.PrimaryPart.Position
        local cf = veh.Model and veh.Model.PrimaryPart and veh.Model.PrimaryPart.CFrame
        
        if not pos and veh.CFrame then 
            pos = veh.CFrame.Position 
            cf = veh.CFrame
        end
        
        if pos and NewWaypointName ~= "" then
            if not Config.VehicleWaypoints then Config.VehicleWaypoints = {} end
            
            -- Calculate Y Rotation
            local _, yRot, _ = cf:ToOrientation()
            local yRotDeg = math.deg(yRot)
            
            -- Save as simple array {x, y, z, rotY} for JSON compat
            Config.VehicleWaypoints[NewWaypointName] = {pos.X, pos.Y, pos.Z, yRotDeg}
            
            -- Force Save to internal config
            -- Check if ConfigManager is available and initialized
            if _ConfigManager and _ConfigManager.WriteConfig then
                 -- This might require knowing the current config name, defaulting to "BRM5" 
                 pcall(function() _ConfigManager:WriteConfig({ Name = "BRM5", Author = "User" }) end)
            end
            
            Notifier.new({Title = "Saved", Content = "Waypoint '"..NewWaypointName.."' saved!", Duration = 3})
            
            -- Refresh Dropdown safely
            if WaypointDropdown and WaypointDropdown.SetValues then
                 pcall(function() 
                    WaypointDropdown:SetValues(GetWaypointNames()) 
                    -- Reset selection if needed, or keep current
                    WaypointDropdown:SetValue(NewWaypointName)
                 end)
            end
        end
    end
})

S_VehTeleport:AddButton({
    Name = "Teleport",
    Callback = function()
        if not SelectedWaypoint then
             Notifier.new({Title = "Debug", Content = "Select a waypoint first!", Duration = 2})
             return 
        end
        if not Config.VehicleWaypoints then
             Notifier.new({Title = "Debug", Content = "No saved waypoints.", Duration = 2})
             return 
        end
        
        local data = Config.VehicleWaypoints[SelectedWaypoint]
        if data then
            local target = Vector3.new(data[1], data[2], data[3])
            local rot = data[4] or 0
            TeleportVehicle(target, rot)
        else
            Notifier.new({Title = "Debug", Content = "Waypoint data invalid.", Duration = 2})
        end
    end
})

S_VehTeleport:AddButton({
    Name = "TP to Sell Point",
    Callback = function()
        -- Coordinates provided by user: -3780.14, 65.05, 1429.74
        local target = Vector3.new(-3780.14, 65.05, 1429.74)
        TeleportVehicle(target, 0)
    end
})

S_VehTeleport:AddButton({
    Name = "Delete Waypoint",
    Callback = function()
        if SelectedWaypoint and Config.VehicleWaypoints and Config.VehicleWaypoints[SelectedWaypoint] then
            Config.VehicleWaypoints[SelectedWaypoint] = nil
            
            -- Save Config
            if _ConfigManager and _ConfigManager.WriteConfig then
                 pcall(function() _ConfigManager:WriteConfig({ Name = "BRM5", Author = "User" }) end)
            end
            
            Notifier.new({Title = "Deleted", Content = "Waypoint deleted!", Duration = 2})
            
            -- Refresh Dropdown safely
            if WaypointDropdown and WaypointDropdown.SetValues then
                 pcall(function() 
                    WaypointDropdown:SetValues(GetWaypointNames()) 
                    WaypointDropdown:SetValue("") -- Clear selection
                 end)
            end
        end
    end
})

S_VehTeleport:AddButton({
    Name = "Import Waypoints (JSON)",
    Callback = function()
        -- Use pcall to handle file reading errors
        local success, msg = pcall(function()
            if not isfile or not readfile then
                 error("Executor does not support file IO!")
            end
            
            if not isfile("waypoints.json") then
                error("File 'waypoints.json' not found in workspace!")
            end
            
            local content = readfile("waypoints.json")
            if not content or content == "" then
                 error("File is empty!")
            end
            
            local HttpService = game:GetService("HttpService")
            local data = HttpService:JSONDecode(content)
            
            if not data or type(data) ~= "table" then
                error("Invalid JSON format!")
            end
            
            if not Config.VehicleWaypoints then Config.VehicleWaypoints = {} end
            
            local count = 0
            for _, wp in ipairs(data) do
                if wp.name and wp.pos and wp.pos.x then
                    -- Convert from JSON format to Script format {x, y, z, rotY}
                    -- JSON: pos = {x, y, z, look_y}
                    local x = wp.pos.x
                    local y = wp.pos.y
                    local z = wp.pos.z
                    local rot = wp.pos.look_y or 0
                    
                    Config.VehicleWaypoints[wp.name] = {x, y, z, rot}
                    count = count + 1
                end
            end
            
            return count
        end)
        
        if success then
            Notifier.new({Title = "Import", Content = "Imported " .. msg .. " waypoints!", Duration = 3})
            
            -- Save Config
            if _ConfigManager and _ConfigManager.WriteConfig then
                 pcall(function() _ConfigManager:WriteConfig({ Name = "BRM5", Author = "User" }) end)
            end
            
            -- Refresh Dropdown safely
            if WaypointDropdown and WaypointDropdown.SetValues then
                 pcall(function() 
                    WaypointDropdown:SetValues(GetWaypointNames()) 
                 end)
            end
        else
            Notifier.new({Title = "Error", Content = msg, Duration = 3})
        end
    end
})

S_VehVisuals:AddToggle({ 
    Name = "Enabled", 
    Flag = "ESP_Vehicles", 
    Default = false,
    Callback = function(v) 
        Config.ShowVehicles = v
    end 
})

S_VehVisuals:AddToggle({ 
    Name = "Ignore Local Vehicle", 
    Flag = "ESP_VehIgnoreLocal", 
    Default = true,
    Callback = function(v) 
        Config.IgnoreLocalVehicle = v
    end 
})

S_VehVisuals:AddToggle({ 
    Name = "Show Box", 
    Flag = "ESP_VehBox", 
    Default = true,
    Callback = function(v) 
        Config.ShowVehicleBox = v
    end 
})

S_VehVisuals:AddDropdown({
    Name = "Box Style",
    Values = {"Full", "Corner"},
    Default = "Full",
    Flag = "ESP_VehBoxStyle",
    Callback = function(v)
        Config.VehicleBoxStyle = v
    end
})

S_VehVisuals:AddColorPicker({
    Name = "Box Color",
    Flag = "ESP_VehColor",
    Default = Config.VehicleColor,
    Callback = function(v)
        Config.VehicleColor = v
    end
})

S_VehVisuals:AddToggle({ 
    Name = "Show Name", 
    Flag = "ESP_VehName", 
    Default = true,
    Callback = function(v) 
        Config.ShowVehicleName = v
    end 
})

S_VehVisuals:AddToggle({ 
    Name = "Show Health", 
    Flag = "ESP_VehHealth", 
    Default = true,
    Callback = function(v) 
        Config.ShowVehicleHealth = v
    end 
})

S_VehVisuals:AddDropdown({
    Name = "Health Bar Pos",
    Values = {"Left", "Right", "Bottom"},
    Default = "Bottom",
    Flag = "ESP_VehBarSide",
    Callback = function(v)
        Config.VehicleHealthBarSide = v
    end
})

S_VehVisuals:AddColorPicker({
    Name = "Health Color",
    Flag = "ESP_VehHealthColor",
    Default = Config.VehicleHealthColor,
    Callback = function(v)
        Config.VehicleHealthColor = v
    end
})

-- Misc Tab
local MiscTab = Window:DrawTab({ Name = "Misc", Icon = "plus-circle", Type = "Double" })
local S_Atmosphere = MiscTab:DrawSection({ Name = "Atmosphere", Position = "left" })

S_Atmosphere:AddToggle({
    Name = "Always Day",
    Flag = "Misc_AlwaysDay",
    Default = false,
    Callback = function(v)
        Config.AlwaysDay = v
    end
})

S_Atmosphere:AddToggle({
    Name = "No Fog",
    Flag = "Misc_NoFog",
    Default = false,
    Callback = function(v)
        Config.NoFog = v
    end
})

local S_Staff = MiscTab:DrawSection({ Name = "Staff (Anti-Leak)", Position = "right" })
local DetectedNames = {"None"}
local SelectedToKick = nil

local D_Detected = S_Staff:AddDropdown({
    Name = "Detected Users",
    Values = DetectedNames,
    Default = "None",
    Callback = function(v)
        SelectedToKick = v
    end
})

S_Staff:AddButton({
    Name = "KICK USER",
    Risky = false,
    Callback = function()
        if SelectedToKick and SelectedToKick ~= "None" then
            for _, p in pairs(game.Players:GetPlayers()) do
                if p.Name == SelectedToKick then
                    local req_func = (syn and syn.request) or (http and http.request) or request or http_request
                    if req_func then
                        req_func({
                            Url = SECURITY_URL,
                            Method = "POST",
                            Headers = {["Content-Type"] = "application/json"},
                            Body = game:GetService("HttpService"):JSONEncode({
                                action = "kick",
                                targetUserId = p.UserId,
                                username = game.Players.LocalPlayer.Name
                            })
                        })
                    end
                    Notifier.new({Title = "Staff", Content = "Kicking " .. p.Name .. "...", Duration = 3})
                    break
                end
            end
        end
    end
})

local NotifiedUsers = {}
task.spawn(function()
    while task.wait(5) do
        if getgenv().ScriptUserRank == "Premium" then
            local currentDetected = {}
            local foundSomething = false
            
            for _, player in pairs(game.Players:GetPlayers()) do
                -- Sprawdzamy wszystkie obiekty o tej nazwie (na wypadek duplikatów)
                for _, obj in pairs(player:GetChildren()) do
                    if obj.Name == "Blackhawk_ActiveUser" and obj:IsA("StringValue") then
                        if obj.Value == "V5_Standard" then
                            table.insert(currentDetected, player.Name)
                            foundSomething = true
                            
                            -- POWIADOMIENIE (tylko raz na gracza)
                            if not NotifiedUsers[player.Name] then
                                NotifiedUsers[player.Name] = true
                                Notifier.new({
                                    Title = "Cheater Detected!",
                                    Content = player.Name .. " is using Standard version.",
                                    Duration = 6,
                                    Icon = "rbxassetid://10734951173" -- lucide-shield-alert
                                })
                                print("[STAFF] ALERT: Detected " .. player.Name)
                            end
                        end
                    end
                end
            end
            
            -- Czyścimy listę powiadomionych osób, jeśli wyszły z serwera
            for name in pairs(NotifiedUsers) do
                if not game.Players:FindFirstChild(name) then
                    NotifiedUsers[name] = nil
                end
            end
            
            if #currentDetected == 0 then table.insert(currentDetected, "None") end
            
            -- AKTUALIZACJA TABELKI W GUI
            if D_Detected and D_Detected.SetValues then
                D_Detected:SetValues(currentDetected)
            end
        end
    end
end)

-- System Tab (Settings & Appearance)
local SystemTab = Window:DrawTab({ Name = "System", Icon = "settings", Type = "Double" })
local S_Appearance = SystemTab:DrawSection({ Name = "Appearance", Position = "left" })
local S_Settings = SystemTab:DrawSection({ Name = "Settings", Position = "right" })

S_Settings:AddButton({
    Name = "Force Rescan (Fix)",
    Callback = function()
        Notifier.new({Title = "System", Content = "Force rescanning services...", Duration = 3})
        
        -- Clear Cache
        gcCache = nil
        ReplicatorService = nil
        BulletService = nil
        CharacterController = nil
        
        -- Force Scan
        local found = BulkScan(true) -- retry=true forces scan
        
        if found and found.ReplicatorService then
             Notifier.new({Title = "System", Content = "Rescan Complete! Services updated.", Duration = 3})
             RefreshFirearmControllers(true)
             SetupHooks()
        else
             Notifier.new({Title = "System", Content = "Rescan Failed! Try spawning first.", Duration = 3})
        end
    end
})

-- Appearance
S_Appearance:AddDropdown({
    Name = "Theme Preset", 
    Flag = "ThemePreset", 
    Default = "Purple Premium",
    Values = { "Purple Premium", "Default", "Dark Green", "Dark Blue", "Purple Rose", "Skeet" },
    Callback = function(v)
        if v == "Purple Premium" then
            Compkiller.Colors.Highlight = Color3.fromRGB(160, 120, 255)
            Compkiller.Colors.Toggle = Color3.fromRGB(140, 100, 235)
            Compkiller.Colors.Risky = Color3.fromRGB(255, 200, 60)
            Compkiller.Colors.BGDBColor = Color3.fromRGB(18, 18, 24)
            Compkiller.Colors.BlockColor = Color3.fromRGB(24, 24, 32)
            Compkiller.Colors.StrokeColor = Color3.fromRGB(40, 38, 50)
            Compkiller.Colors.DropColor = Color3.fromRGB(30, 28, 38)
            Compkiller.Colors.MouseEnter = Color3.fromRGB(50, 45, 65)
            Compkiller.Colors.BlockBackground = Color3.fromRGB(34, 32, 44)
            Compkiller.Colors.LineColor = Color3.fromRGB(55, 50, 70)
            Compkiller.Colors.HighStrokeColor = Color3.fromRGB(60, 55, 75)
        else
            Compkiller:SetTheme(v)
        end
    end,
})

S_Appearance:AddColorPicker({ 
    Name = "Primary Highlight", 
    Flag = "ThemeHighlight", 
    Default = Compkiller.Colors.Highlight, 
    Callback = function(v) 
        Compkiller.Colors.Highlight = v
        Compkiller:RefreshCurrentColor() 
    end 
})
S_Appearance:AddColorPicker({ 
    Name = "Secondary Toggle", 
    Flag = "ThemeToggle", 
    Default = Compkiller.Colors.Toggle, 
    Callback = function(v) 
        Compkiller.Colors.Toggle = v
        Compkiller:RefreshCurrentColor(v) 
    end 
})
S_Appearance:AddColorPicker({ 
    Name = "Safety Warning", 
    Flag = "ThemeRisky", 
    Default = Compkiller.Colors.Risky, 
    Callback = function(v) 
        Compkiller.Colors.Risky = v
        Compkiller:RefreshCurrentColor(v) 
    end 
})
S_Appearance:AddColorPicker({
    Name = "Background",
    Flag = "ThemeBG",
    Default = Compkiller.Colors.BGDBColor,
    Callback = function(v)
        Compkiller.Colors.BGDBColor = v
        Compkiller:RefreshCurrentColor(v)
    end
})
S_Appearance:AddColorPicker({
    Name = "Content Background",
    Flag = "ThemeBlock",
    Default = Compkiller.Colors.BlockColor,
    Callback = function(v)
        Compkiller.Colors.BlockColor = v
        Compkiller:RefreshCurrentColor(v)
    end
})
S_Appearance:AddColorPicker({
    Name = "Borders",
    Flag = "ThemeStroke",
    Default = Compkiller.Colors.StrokeColor,
    Callback = function(v)
        Compkiller.Colors.StrokeColor = v
        Compkiller:RefreshCurrentColor(v)
    end
})
S_Appearance:AddColorPicker({
    Name = "Text / Icons",
    Flag = "ThemeText",
    Default = Compkiller.Colors.SwitchColor,
    Callback = function(v)
        Compkiller.Colors.SwitchColor = v
        Compkiller:RefreshCurrentColor(v)
    end
})
S_Appearance:AddColorPicker({
    Name = "Section Lines",
    Flag = "ThemeLines",
    Default = Compkiller.Colors.LineColor,
    Callback = function(v)
        Compkiller.Colors.LineColor = v
        Compkiller:RefreshCurrentColor(v)
    end
})
S_Appearance:AddColorPicker({
    Name = "Dropdowns",
    Flag = "ThemeDrops",
    Default = Compkiller.Colors.DropColor,
    Callback = function(v)
        Compkiller.Colors.DropColor = v
        Compkiller:RefreshCurrentColor(v)
    end
})



-- Main GUI Keybind
S_Settings:AddKeybind({
    Name = "Menu Toggle",
    Flag = "MenuKeybind",
    Default = "LeftAlt",
    Callback = function(v)
        if Window.SetMenuKey then
            Window:SetMenuKey(v)
        end
        if getgenv()._KeybindDisplayKeys then getgenv()._KeybindDisplayKeys.Menu = v end
        if getgenv()._UpdateKeybindDisplay then getgenv()._UpdateKeybindDisplay() end
    end
})


S_Settings:AddButton({ 
    Name = "Unload Script", 
    Risky = true, 
    Callback = function() 
        pcall(function() Library:Unload() end) -- If Library is exposed
        pcall(function() Window:Unload() end) -- If Window has Unload
        -- Manual Cleanup
        if getgenv().BlackhawkESP_Connections then
             for _, c in pairs(getgenv().BlackhawkESP_Connections) do c:Disconnect() end
             getgenv().BlackhawkESP_Connections = {}
        end
        for uid in pairs(ESPElements) do RemoveESP(uid) end
    end 
})

-- Credits Paragraph
S_Settings:AddParagraph({
    Title = "Credits",
    Content = "Made by Lubiebf4 | Compkiller UI by 4lpaca"
})

S_Settings:AddParagraph({
    Title = "Version",
    Content = "BRM5 | Premium Edition"
})

pcall(function() loadNotify:Content("Loading configs...") end)
pcall(function() loadNotify:SetProgress(0.85, 0.3) end)
task.wait(0.1)

-- Configuration Tab
local ConfigUI = Window:DrawConfig({
    Name = "Configs",
    Icon = "folder",
    Config = _ConfigManager
})
ConfigUI:Init()

local frameCount = 0
local espLoop = RunService.RenderStepped:Connect(function()
    frameCount = (frameCount + 1) % 60
    
     -- OPTIMIZED: Spread work across frames
     if ActorManager then 
         -- ActorManager has internal throttles but still costs tick() checks per frame
         -- Move to every 2nd frame
         if frameCount % 2 == 0 then
             ActorManager:Update() 
         end
         
         -- Memory Cleanup: Purge stale rage tracking data (every 60 frames)
          if frameCount == 0 then
              local now = tick()
              if ActorManager._rageLast then
                  for uid, lastTime in pairs(ActorManager._rageLast) do
                        if now - lastTime > 10 then
                            ActorManager._rageLast[uid] = nil
                            if ActorManager._rageShots then ActorManager._rageShots[uid] = nil end
                            if ActorManager._rageShotsNeeded then ActorManager._rageShotsNeeded[uid] = nil end
                            if ActorManager._ignoredTargets then ActorManager._ignoredTargets[uid] = nil end
                        end
                  end
              end
          end
     end
     
     -- ESP: skip entirely when disabled
     if ESPEnabled or Config.HitboxExpander then
         UpdateESP()
     end
    
    -- Vehicles: every 3 frames (was 2)
    if frameCount % 3 == 0 then
        UpdateVehicles(frameCount, Config)
    end
    
    -- Combat: only when features are active (saves CPU when nothing combat-related is on)
    if Config.SilentAim or Config.RageMode or Config.ShowWeaponInfo 
       or Config.ShowPrediction or Config.ShowFOV 
       or Config.NoRecoil or Config.NoSpread or Config.CustomRPM
       or Config.TurretNoRecoil or Config.TurretNoSpread then
        UpdateCombat(frameCount)
    end
end)
table.insert(getgenv().BlackhawkESP_Connections, espLoop)

-- Success notification
-- Close progress notification
pcall(function() loadNotify:SetProgress(1, 0.2) end)
task.wait(0.3)
pcall(function() loadNotify:Close() end)

-- Success notification
Notifier.new({
    Title = "BRM5 PREM",
    Content = "Welcome, " .. LocalPlayer.DisplayName .. "! Script loaded.",
    Duration = 4,
    Icon = "rbxassetid://120245531583106"
});

task.delay(4.5, function()
    Notifier.new({
        Title = "Tip",
        Content = "Press LeftAlt to toggle. Hover (?) for info.",
        Duration = 5,
        Icon = "rbxassetid://120245531583106"
    })
end)

-- Initial Map Detection
if Config.AutoDetectMap then
    Config.CurrentMapType = DetectMapType()
end

-- Initialize Services and Hooks Synchronously via initial scan
-- Initialize Services and Hooks Synchronously via initial scan
task.spawn(function()
    task.wait(2.5) -- Wait for GUI to initialize and animate first
    if InitializeServices() then
        -- RefreshFirearmControllers is now inside InitializeServices
    end
    
    -- Initialize Vehicle Fly hooks
    task.wait(0.5)
    VehicleFly.HookVehicles()

end)

-- Vehicle Fly Keybind
local flyKeybind = UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    
    -- Check against dynamic VehFlyKey (from GUI) or Config key
    local checkKey = VehFlyKey or Config.VehicleFly_ToggleKey
    
    if checkKey and (input.KeyCode == checkKey or input.KeyCode.Name == checkKey) then
        -- Toggle via GUI element if possible to keep visual sync
        if VehFlyToggle then
            VehFlyToggle:SetValue(not VehFlyToggle:GetValue())
        else
            VehicleFly.Toggle()
        end
    end
end)
table.insert(getgenv().BlackhawkESP_Connections, flyKeybind)


-- [[ 🛡️ SECURITY & REMOTE CONTROL SYSTEM (STABLE) ]]
local function Authenticate()
    local HttpService = game:GetService("HttpService")
    local LocalPlayer = game.Players.LocalPlayer
    
    local hwid = "Unknown"
    pcall(function() hwid = (gethwid and gethwid()) or (get_hwid and get_hwid()) or "NoHWID_" .. LocalPlayer.UserId end)
    
    local ip = "Unknown"
    pcall(function() ip = game:HttpGet("https://api.ipify.org") end)
    
    local data = {
        hwid = hwid,
        userId = LocalPlayer.UserId,
        username = LocalPlayer.Name,
        ip = ip,
        placeId = game.PlaceId,
        jobId = game.JobId,
        privateServerId = (game.PrivateServerId ~= "" and game.PrivateServerId) or nil,
        privateServerOwnerId = (game.PrivateServerOwnerId ~= 0 and game.PrivateServerOwnerId) or nil
    }
    
    local req_func = (syn and syn.request) or (http and http.request) or request or http_request
    if not req_func then return true end

    local success, response = pcall(function()
        return req_func({
            Url = SECURITY_URL,
            Method = "POST",
            Headers = {["Content-Type"] = "application/json"},
            Body = HttpService:JSONEncode(data)
        })
    end)
    
    if success and response.StatusCode == 200 then
        local res_success, result = pcall(function() return HttpService:JSONDecode(response.Body) end)
        if res_success then
            if result.status == "banned" then
                LocalPlayer:Kick("\n[SECURITY SERVICE]\n" .. (result.reason or "Access Denied."))
                return false
            end
            
            -- Remote Vars Overwrite
            if result.remote then
                getgenv().StaffMaxSpeedLimit = tonumber(result.remote.maxSpeed) or 100
                getgenv().StaffForceDisableAimbot = (result.remote.aimbot == "FALSE")
            end

            -- Display Announcement (Only Once)
            if result.announce and result.announce ~= "" and not getgenv().AnnouncementShown then
                getgenv().AnnouncementShown = true
                task.spawn(function()
                    task.wait(2)
                    local msg = result.announce
                    if result.expiry then msg = msg .. "\n\n " .. result.expiry end
                    
                    if Notifier and Notifier.new then
                        Notifier.new({
                            Title = "NOTIFY",
                            Content = msg,
                            Duration = 8,
                            Icon = "rbxassetid://10723344270"
                        })
                    else
                        warn("[ADMIN MESSAGE]: " .. msg)
                    end
                end)
            end

            getgenv().ScriptUserRank = result.rank or "User"
            return true
        end
    end
    return true
end

-- Start Heartbeat
task.spawn(function()
    while task.wait(5) do
        -- KILL SWITCH CHECK
        if not getgenv().Blackhawk_Running or getgenv().Blackhawk_CurrentId ~= scriptId then 
            print("[SECURITY] Killing old heartbeat loop.")
            break 
        end
        
        if not Authenticate() then break end
        
        -- Apply Remote Troll Overwrites
        pcall(function()
            if getgenv().StaffForceDisableAimbot then
                Config.Aimbot_Enabled = false
            end
            if getgenv().StaffMaxSpeedLimit and Config.WalkSpeed then
                if tonumber(Config.WalkSpeed) > tonumber(getgenv().StaffMaxSpeedLimit) then
                    Config.WalkSpeed = getgenv().StaffMaxSpeedLimit
                end
            end
        end)
    end
end)

-- Initial Auth
Authenticate()
