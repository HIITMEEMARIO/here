if not game:IsLoaded() then game.Loaded:Wait() end
local LibraryLoaded, Compkiller = pcall(function()
    local function notify(msg)
        pcall(function()
            game:GetService("StarterGui"):SetCore("SendNotification", {
                Title = "VoidSens",
                Text = msg,
                Duration = 5
            })
        end)
    end
    return loadstring(game:HttpGet(
        "https://raw.githubusercontent.com/HIITMEEMARIO/here/refs/heads/main/gui.lua"))()
end)

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
        queue(
            'if not shared.BRM_Executed then shared.BRM_Executed = true; task.wait(3); loadstring(game:HttpGet("https://raw.githubusercontent.com/HIITMEEMARIO/here/refs/heads/main/iv2.lua"))() end')
    end
end

-- Disconnect old teleport connection if it exists
if getgenv().TeleportConn then getgenv().TeleportConn:Disconnect() end
getgenv().TeleportConn = game:GetService("Players").LocalPlayer.OnTeleport:Connect(QueueTeleport)
table.insert(getgenv().BlackhawkESP_Connections, getgenv().TeleportConn)

-- Localize Globals and Methods for Performance
local Vector3_new = Vector3.new
local VECTOR3_ZERO = Vector3_new(0, 0, 0)
local Vector2_new = Vector2.new
local CFrame_new = CFrame.new
local Color3_new = Color3.new
local Color3_fromHSV = Color3.fromHSV
local RaycastParams_new = RaycastParams.new
local math_floor = math.floor
local math_ceil = math.ceil
local math_clamp = math.clamp
-- local math_abs = math.abs -- removed to reduce local count; use math.abs() directly
local pairs = pairs
local ipairs = ipairs
local type = type
local tick = tick
-- local os.clock = os.clock -- removed to reduce local count; use os.clock() directly
local string_format = string.format
-- local rawget = rawget -- removed to reduce local count; rawget is already a fast global
local pcall = pcall
local tostring = tostring
local getgenv = getgenv
-- local getgc = getgc -- removed to reduce local count; getgc is executor global
-- local filtergc = filtergc -- removed to reduce local count; filtergc is executor global

-- Safe Drawing Constructor (Resilient against lazy-loading & missing APIs)
local DrawingAPI_Available = type(Drawing) == "table" or type(getgenv().Drawing) == "table"
local function SafeDrawing(className)
    if not DrawingAPI_Available then return nil end
    local success, obj = pcall(function()
        local lib = Drawing or getgenv().Drawing
        return lib.new(className)
    end)
    return success and obj or nil
end

-- P6: Cache getgenv() reference globally (used throughout combat/prediction)
local _genv = getgenv()

-- Services
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
-- CoreGui already declared above -- removed duplicate to reduce local count
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Camera = Workspace.CurrentCamera
local LocalPlayer = Players.LocalPlayer
local Mouse = LocalPlayer:GetMouse()

-- SolveLead defined later at line 746

-- Local cache variables for BulkScan
local gcCache, lastScan = nil, 0
-- Merged with gcCache above to reduce local count


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
-- O3: Cache Players:GetPlayerByUserId results (players don't change UserId)
local _playerByUserId = {}
Players.PlayerRemoving:Connect(function(player)
    _playerByUserId[player.UserId] = nil
end)
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
local InventoryService, ReplicatorService, ClientService, WorldService, BulletService, Network, InputService
local CharacterController, ControllerService, FirearmInventoryClass, ActorClass, Recoiler, EffectsService
local CalibersTable, VehicleService, FirearmInventory
local MenuInterface -- MenuInterface singleton (holds PrivateServerData, MatchmakingQueueData)

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
    BoxColor = nil,       -- Default to Entity Color
    HealthBarColor = nil, -- Default to Green/Gradient
    PlayerColor = Color3_new(1, 0.65, 0),
    TeammateColor = Color3_new(0, 1, 0),
    ZombieColor = Color3_new(1, 0, 0),
    NPCColor = Color3_new(1, 1, 0),
    SquadColor = Color3_new(0, 1, 0),
    TracerColor = Color3_new(1, 1, 1),
    WeaponColor = Color3_new(1, 1, 1),

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
    if UserInputService:IsKeyDown(Config.VehicleFly_UpKey) then moveDir = moveDir + Vector3_new(0, 1, 0) end
    if UserInputService:IsKeyDown(Config.VehicleFly_DownKey) then moveDir = moveDir - Vector3_new(0, 1, 0) end

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
    ["Menu"] = { 16173503753, 2916899287 },
    ["DEV_Grav"] = { 17271259902, 0 },
    ["DEV_Mb"] = { 18127391367, 0 },
    ["DEV_Kit"] = { 110308858728653, 0 },
    ["DEV_Gnar"] = { 79821195747721, 0 },
    ["CM_Mission1"] = { 83829699029749, 4843465225 },
    ["OW_Ronograd"] = { 95595459346841, 3701546109 },
    ["OW_Blank"] = { 0, 5899968224 },
    ["HQ_Seychelles"] = { 139188553486454, 14014688944 },
    ["PVP_Coast"] = { 99240342190508, 5480112241 },
    ["PVP_Favela"] = { 123576346999506, 5468388011 },
    ["PVP_NYC"] = { 71499109870653, 3826587512 },
    ["PVP_Tokyo"] = { 125537938344868, 4524359706 },
    ["PVP_Office"] = { 113296614204646, 5289429734 },
    ["PVP_Blank"] = { 0, 10938546013 },
    ["ZMP_NYC"] = { 84460047957624, 4747446334 },
    ["ZME_NYC"] = { 84460047957624, 4747446334 }
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

    local startTime = os.clock()

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

            -- 1. IDENTIFY UNIQUE SERVICES (Fingerprinting via rawget)
            -- Use independent IFs to ensure one object can be identified as multiple services (e.g. ControllerService vs CharacterController)

            -- ReplicatorService
            if not ReplicatorService and not found.ReplicatorService and rawget(obj, "Actors") and rawget(obj, "LocalActor") then
                found.ReplicatorService = obj
            end

            -- BulletService
            if not BulletService and not found.BulletService and rawget(obj, "_multithreadSend") then
                found.BulletService = obj
            end

            -- WorldService
            if not WorldService and not found.WorldService and rawget(obj, "InactiveWorld") then
                found.WorldService = obj
            end

            -- ClientService
            if not ClientService and not found.ClientService and rawget(obj, "Clients") and rawget(obj, "LocalClient") then
                found.ClientService = obj
            end

            -- VehicleService
            if not VehicleService and not found.VehicleService and rawget(obj, "Vehicles") and rawget(obj, "Changed") then
                found.VehicleService = obj
            end

            -- EnvironmentService
            if not EnvironmentService and not found.EnvironmentService and rawget(obj, "RainDensity") and (rawget(obj, "_lights") or rawget(obj, "_clouds")) then
                found.EnvironmentService = obj
            end

            -- InventoryService
            if not InventoryService and not found.InventoryService and rawget(obj, "Inventories") and (rawget(obj, "_hasRadio") or rawget(obj, "_droppedItems")) then
                found.InventoryService = obj
            end

            -- CalibersTable
            if not CalibersTable and not found.CalibersTable and rawget(obj, "shotgun_12gauge_00buck") then
                found.CalibersTable = obj
            end

            -- EffectsService
            if not EffectsService and not found.EffectsService and rawget(obj, "BulletLand") and rawget(obj, "BulletFired") then
                found.EffectsService = obj
            end

            -- Network
            if not Network and not found.Network then
                if rawget(obj, "FireServer") and rawget(obj, "_events") then
                    found.Network = obj
                elseif rawget(obj, "_key") and type(rawget(obj, "_key")) == "table" and rawget(obj, "_code") then
                    found.Network = obj
                end
            end

            -- InputService
            if not InputService and not found.InputService and rawget(obj, "_inputMovement") and rawget(obj, "_mouseMovement") then
                found.InputService = obj
            end

            -- ControllerService
            if not ControllerService and not found.ControllerService then
                if rawget(obj, "Controller") ~= nil then -- Key exists
                    local success, hasSimulated = pcall(function() return type(obj.Simulated) == "function" end)
                    if success and hasSimulated then
                        found.ControllerService = obj
                    elseif type(obj.Controller) == "table" and rawget(obj.Controller, "Update") then
                        found.ControllerService = obj -- Fallback to active controller check
                    end
                end
            end

            -- 2. IDENTIFY CLASSES AND PROTOTYPES
            if not CharacterController and not found.CharacterController and rawget(obj, "SetCFrame") and rawget(obj, "SetVehicleGoal") then
                if rawget(obj, "__index") == obj or not rawget(obj, "Parent") then
                    found.CharacterController = obj
                end
            end

            if not FirearmInventoryClass and not found.FirearmInventoryClass and rawget(obj, "Equip") and rawget(obj, "Unequip") and rawget(obj, "Discharge") then
                found.FirearmInventoryClass = obj
            end

            if not Recoiler and not found.Recoiler and rawget(obj, "Impulse") and rawget(obj, "TimeSkip") and rawget(obj, "GetCameraAdjustment") then
                found.Recoiler = obj
            end

            if not ActorClass and not found.ActorClass and rawget(obj, "Update") and rawget(obj, "Vault") and rawget(obj, "Slide") then
                found.ActorClass = obj
            end

            if not CharacterCamera and not found.CharacterCamera and rawget(obj, "Update") and rawget(obj, "Render") and rawget(obj, "Watch") then
                found.CharacterCamera = obj
            end

            if not TurretController and not found.TurretController and rawget(obj, "_discharge") and rawget(obj, "Discharge") then
                found.TurretController = obj
            end

            -- MenuInterface (singleton with PrivateServerData & MatchmakingQueueData)
            if not MenuInterface and not found.MenuInterface and rawget(obj, "_privateServerData") and rawget(obj, "_matchmakingQueueData") then
                found.MenuInterface = obj
            end

            -- 3. COLLECT INSTANCES
            if rawget(obj, "_firearm") and rawget(obj, "_actor") then
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
    CharacterCamera = logService("CharacterCamera", found.CharacterCamera) or
        (shared.Engine and shared.Engine.CharacterCamera)
    Network = logService("Network", found.Network) or Network
    -- Print encryption key and auth code when Network is found
    if Network and Network._key then
        print("[BulkScan] ===== ENCRYPTION KEY FOUND =====")
        print("[BulkScan] Key: [" .. table.concat(Network._key, ", ") .. "]")
        print("[BulkScan] Code: " .. tostring(Network._code))
        print("[BulkScan] ===================================")
    end
    InputService = logService("InputService", found.InputService) or InputService
    MenuInterface = logService("MenuInterface", found.MenuInterface) or MenuInterface

    FirearmInventory = collections.FirearmInventory
    lastCollections = collections

    print(string_format("[BulkScan] Memory scan took: %.1fms ", (os.clock() - startTime) * 1000))

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
                    pcall(function()
                        collectgarbage("count"); collectgarbage("collect")
                    end) -- Force Aggressive GC

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

-- Kept for compatibility
local function FindService(serviceName, manualCache)
    if not ReplicatorService then BulkScan() end
    if serviceName == "ReplicatorService" then
        return ReplicatorService
    elseif serviceName == "BulletService" then
        return BulletService
    elseif serviceName == "CharacterController" then
        return CharacterController
    elseif serviceName == "InventoryService" then
        return InventoryService
    end
    return nil
end

--[[
    FORWARD DECLARATIONS
]]

local _cachedMuzzle, _cachedMuzzleFrame = nil, -1
-- Merged with _cachedMuzzle above to reduce local count

-- Moved GetMuzzlePosition here for visibility
function GetMuzzlePosition()
    -- P19: C-Boundary Cache (75% call reduction)
    if _cachedMuzzleFrame == CurrentFrameId then return _cachedMuzzle end

    local returnPos
    -- Priority 0: Active Equipped Controller from Cached WeaponManager
    -- This avoids scanning the huge FirearmInventory table every frame
    if WeaponManager.Equipped then
        local handler = WeaponManager.Equipped
        if handler._originalMuzzle then
            local success, cf = pcall(handler._originalMuzzle, handler)
            if success and cf then returnPos = cf.Position end
        elseif handler.GetMuzzleCFrame then
            local success, cf = pcall(handler.GetMuzzleCFrame, handler)
            if success and cf then returnPos = cf.Position end
        end
    end

    -- Fallback: Start with Camera Position to avoid nil errors if logic fails
    if not returnPos then returnPos = Camera.CFrame.Position end

    _cachedMuzzle = returnPos
    _cachedMuzzleFrame = CurrentFrameId
    return returnPos
end

function GetSecureContainer()
    if SecureESPContainer then
        local success, parent = pcall(function() return SecureESPContainer.Parent end)
        if success and parent then
            return SecureESPContainer
        end
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

-- (GetEntityType and IsTeammate defined below at lines ~1022/1041 — removed duplicate here)

local function InitializeServices()
    -- Optimized Bulk Memory Scan
    local found, collections = BulkScan()
    if not found then return false end

    -- Sync with legacy globals
    CalibersTable = found.CalibersTable

    -- Fallback: Find Critical Services via ModuleScript if missed by GC
    -- (Handled by BulkScan now)

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
                -- Guard: Only modify aim when a firearm is actually equipped
                local eqCtrl = WeaponManager.Equipped or
                    (InventoryService and InventoryService.Equipped and InventoryService.Equipped.Handler)
                if not eqCtrl or not eqCtrl._firearm then
                    return BulletService._originalDischarge(self, originCF, p49, p50, p51, p52, p53, p54, p55, p56, p57)
                end
                p57 = false

                local targetHead = ActorManager.SelectedTarget_RB or ActorManager.SelectedTarget_SA
                local targetActor = ActorManager.SelectedActor_RB or ActorManager.SelectedActor_SA

                if targetHead then
                    local targetPos = targetActor._visiblePoint or targetHead.Position
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

                    local targetVelocity = getgenv()._lastPredVel or Vector3_new(0, 0, 0)
                    local gravity = 32.2

                    if originCF then muzzlePos = originCF.Position end
                    if not muzzlePos and GetMuzzlePosition then
                        muzzlePos = GetMuzzlePosition()
                    end

                    if muzzlePos and targetPos then
                        local aimPos, _ = SolveLead(muzzlePos, targetPos, targetVelocity, muzzle_velocity, gravity)
                        getgenv().LastSilentAimUpdate = tick()
                        originCF = CFrame_new(muzzlePos, aimPos)
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



-- Projectile lead and bullet drop calculation (O7: Optimized — single velocity magnitude check)
-- NOTE: Drop compensation uses HORIZONTAL (XZ) distance for travel time.
-- The game's BulletClassMultithread uses v17 = cosA*v*t (horizontal distance),
-- so using 3D distance would overestimate time and over-compensate drop when muzzle != target height.
local function SolveLead(sourcePos, targetPos, targetVelocity, bulletSpeed, gravity)
    -- Lead: initial time from 3D distance (correct for movement prediction)
    local distance = (targetPos - sourcePos).Magnitude
    local time = distance / bulletSpeed

    local predictedPos = targetPos
    local velMag = targetVelocity and targetVelocity.Magnitude or 0
    if velMag > 0.1 then
        predictedPos = targetPos + (targetVelocity * time)
        -- Second iteration refinement
        time = (predictedPos - sourcePos).Magnitude / bulletSpeed
        predictedPos = targetPos + (targetVelocity * time)
    end

    if Config.BulletDrop then
        -- Use HORIZONTAL distance for drop time (matches game's ballistic formula)
        -- 3D distance would inflate time when muzzle is above/below target → dot too high
        local hDist = Vector3_new(predictedPos.X - sourcePos.X, 0, predictedPos.Z - sourcePos.Z).Magnitude
        local dropTime = hDist / bulletSpeed
        local dropCompensation = 0.5 * gravity * (dropTime * dropTime)
        predictedPos = predictedPos + Vector3_new(0, dropCompensation, 0)
    end

    return predictedPos, time
end

-- Velocity tracking cache: actor UID -> { pos, time, vel }
local VelTrackCache = {}

-- Resolve world-space velocity for a target actor (handles vehicle-seated targets)
-- Uses position-delta tracking for framerate-independent velocity
local function GetTargetVelocity(actor)
    if not actor then return VECTOR3_ZERO end

    -- Check if actor is seated in a vehicle — use vehicle velocity
    local seat = actor.Seat
    if seat and seat.UID and VehicleService then
        local ok, vehicle = pcall(function()
            return VehicleService.Vehicles and VehicleService.Vehicles[seat.UID]
        end)
        if ok and vehicle then
            if vehicle._derivedVelocity and vehicle._derivedVelocity.Magnitude > 0.1 then
                return vehicle._derivedVelocity
            end
            if vehicle.Hitbox then
                local hOk, vel = pcall(function() return vehicle.Hitbox.AssemblyLinearVelocity end)
                if hOk and vel and vel.Magnitude > 0.1 then
                    return vel
                end
            end
        end
    end

    -- Walking targets: compute velocity from position deltas (framerate-independent)
    local uid = actor.UID
    local pos = actor.Position
    if not pos or not uid then return VECTOR3_ZERO end

    local now = tick()
    local entry = VelTrackCache[uid]
    if not entry then
        VelTrackCache[uid] = { pos = pos, time = now, vel = VECTOR3_ZERO }
        return VECTOR3_ZERO
    end

    local dt = now - entry.time
    if dt > 0.016 then -- Only update at ~60Hz to avoid micro-jitter
        local delta = pos - entry.pos
        local rawVel = delta / dt

        -- Clamp Y component to avoid extreme vertical vel from teleports/ladders
        rawVel = Vector3_new(rawVel.X, math_clamp(rawVel.Y, -50, 50), rawVel.Z)

        -- Reject teleport spikes (> 100 studs/sec = ~70 mph, unrealistic running speed)
        if rawVel.Magnitude > 100 then
            rawVel = VECTOR3_ZERO
        end

        -- Smooth velocity with EMA (exponential moving average)
        local alpha = math_clamp(dt * 8, 0.05, 0.5)
        entry.vel = entry.vel:Lerp(rawVel, alpha)
        entry.pos = pos
        entry.time = now
    end

    return entry.vel
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

    -- P10: Use cached player reference (set in ActorManager:Update)
    if actor._ownerPlayer then
        return "Player"
    end

    -- Check if NPC (has owner but not a real player, or AI-controlled)
    if actor.Owner or actor.OwnerName then
        return "NPC"
    end

    return "Unknown"
end

local function IsTeammate(actor, cachedLocalSquad)
    -- Rule 0: Zombies themselves are NEVER teammates
    if actor.Zombie == true then return false end

    -- P10: Use cached player reference
    local ownerPlayer = actor._ownerPlayer
    local isRealPlayer = ownerPlayer ~= nil

    local mapType = Config.CurrentMapType or "Unknown"

    -- Rule 1: Friendly Maps
    -- W BRM5 domyslnie wszystkie mapy poza stricte PVP to mapy kooperacyjne (PvE).
    -- Jesli to prawdziwy gracz i NIE JESTESMY na mapie PVP -> JEST Z NAMI.
    if isRealPlayer then
        -- Zombie PvE (ZME) ma mapType = "Zombie". Wszyscy inni ludzie tam to nasi bracia.
        if mapType == "Zombie" or mapType == "OpenWorld" or mapType == "Headquarters" or mapType == "Menu" or mapType == "Unknown" then
            return true
        end
    end

    -- Rule 2: PvP Maps -> Omijamy sprawdzanie druzyn Roblox bo sa zbugowane w BRM5.
    -- W trybach PVP (w tym ZMP Survival) na wroga zmieniani sa wszyscy, KTO NIE JEST W TWOIM SQUADZIE.

    -- Rule 3: ClientService Squad Check (Niezawodne sprawdzenie party z menu glownego)
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
        self._sectors = {}       -- Sector grid
        self._sectorSize = 512   -- Sector size (studs)
        self._playerSector = nil -- Current player sector
        self._targetQueue = {}   -- Top 3 pre-cached targets
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
        if ClientService and type(ClientService.LocalClient) == "table" then
            localSquad = ClientService.LocalClient.Squad
        end

        local localPlayer = LocalPlayer
        -- P7: Use counted indices instead of table.insert (avoids internal resize checks)
        local enemyN, teamN, vehN = 0, 0, 0

        for _, actor in pairs(ReplicatorService.Actors) do
            if not actor or not actor.Alive or not actor.Character then continue end
            if actor.Owner == localPlayer then continue end

            -- O3: Use cached player lookup (avoid repeated GetPlayerByUserId API calls)
            if actor.Owner then
                local uid = actor.Owner.UserId
                local cached = _playerByUserId[uid]
                if cached == nil then
                    cached = Players:GetPlayerByUserId(uid) or false
                    _playerByUserId[uid] = cached
                end
                actor._ownerPlayer = cached or nil
            else
                actor._ownerPlayer = nil
            end

            actor._entityType = GetEntityType(actor)
            actor._isTeammate = IsTeammate(actor, localSquad)

            -- Cache visibility check (runs every 0.5s)
            if ShouldShowEntity then
                actor._cachedShow = ShouldShowEntity(actor, actor._entityType, localSquad)
            else
                actor._cachedShow = true
            end

            if actor._isTeammate then
                teamN = teamN + 1
                self.Teammates[teamN] = actor
            else
                enemyN = enemyN + 1
                self.Enemies[enemyN] = actor

                -- SPATIAL PARTITIONING: Bucket enemy into sector
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
                vehN = vehN + 1
                self.Vehicles[vehN] = veh
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
local VisFilterTable = table.create(64) -- Sized for all actor characters as exclude filter

-- OPTIMIZATION: Cache actor character list for visibility filter (rebuilt every 0.5s by ActorManager)
-- This avoids iterating ALL actors on every raycast call (up to 40x/frame!)
local _cachedActorCharacters = {}
local _cachedActorCharsFrame = -1

-- Pre-calculate hitbox offsets to avoid per-raycast allocations
local HitboxOffsets = {
    -- Axial points (6) - unit length
    Vector3_new(1, 0, 0), Vector3_new(-1, 0, 0),
    Vector3_new(0, 1, 0), Vector3_new(0, -1, 0),
    Vector3_new(0, 0, 1), Vector3_new(0, 0, -1),
    -- Diagonal Octants (8) - NORMALIZED to unit length (was 1.73x too far!)
    Vector3_new(1, 1, 1).Unit, Vector3_new(1, 1, -1).Unit,
    Vector3_new(1, -1, 1).Unit, Vector3_new(1, -1, -1).Unit,
    Vector3_new(-1, 1, 1).Unit, Vector3_new(-1, 1, -1).Unit,
    Vector3_new(-1, -1, 1).Unit, Vector3_new(-1, -1, -1).Unit
}

-- P9: Pre-allocate penetration raycast params (reused per call, no per-raycast alloc)
local PenRayParams = RaycastParams_new()
PenRayParams.FilterType = Enum.RaycastFilterType.Exclude
PenRayParams.CollisionGroup = "CharacterCast"
PenRayParams.IgnoreWater = true
local PenFilterTable = table.create(20)

-- R2: Pre-allocated Triggerbot RaycastParams
local TriggerbotRayParams = RaycastParams_new()
TriggerbotRayParams.FilterType = Enum.RaycastFilterType.Exclude

-- R6: Zombie ability names (hoisted from ESP render loop)
local ZombieAbilityNames = { "Crippled", "Slow", "Normal", "Sprinter" }

-- O1: Module-level CheckPoint (eliminates per-IsVisible closure allocation)
local function CheckPointVisible(point, originPos, character, fIdx)
    local dir = (point - originPos)
    local result = Workspace:Raycast(originPos, dir, VisRayParams)
    if not result then return true end
    if result.Instance:IsDescendantOf(character) then return true end

    -- Penetration check with pre-allocated params
    local penetrations = 0
    local dirUnit = dir.Unit
    table.clear(PenFilterTable)
    for i = 1, fIdx do PenFilterTable[i] = VisFilterTable[i] end
    local penIdx = fIdx
    PenRayParams.FilterDescendantsInstances = PenFilterTable

    local curRes = result
    while penetrations < 2 do
        local hitPart = curRes.Instance
        if hitPart:IsDescendantOf(character) then return true end
        if IsIgnored(hitPart) then
            penIdx = penIdx + 1
            PenFilterTable[penIdx] = hitPart
            PenRayParams.FilterDescendantsInstances = PenFilterTable
            penetrations = penetrations + 1
            curRes = Workspace:Raycast(curRes.Position + (dirUnit * 0.1), dir - (curRes.Position - originPos),
                PenRayParams)
            if not curRes then return true end
        else
            return false
        end
    end
    return false
end

local function IsVisible(targetActor, targetPart, origin, isPriority)
    if not targetPart or not targetPart.Parent then return false end

    local now = _genv and _genv.LastTime or tick()
    local uid = targetActor.UID

    -- CACHE CLEANUP: Prevent memory bloat (every 2 seconds)
    if now - LastVisCacheCleanup > 2 then
        for k, v in pairs(VisCache) do
            if now - v.last > 5 then
                VisCache[k] = nil
            end
        end
        LastVisCacheCleanup = now
    end

    -- PRIORITY MODE: Active target gets fresh raycast, skips cache
    if not isPriority then
        local cacheTTL = Config.RageMode and 0.016 or 0.05
        if VisCache[uid] and (now - VisCache[uid].last < cacheTTL) then
            return VisCache[uid].result
        end
    end

    -- RAYCAST BUDGET CHECK
    if not isPriority then
        local budget = _genv and _genv.RaycastBudget or 0
        if budget <= 0 then
            return false
        end
        if _genv then _genv.RaycastBudget = budget - 1 end
    end

    local character = targetPart.Parent
    local cam = Workspace.CurrentCamera
    local originPos = origin or (_genv and _genv.LastCamCF and _genv.LastCamCF.Position) or (cam and cam.CFrame.Position)
    if not originPos then return false end
    local dist = targetActor.LOD_Distance or (targetPart.Position - originPos).Magnitude

    -- Engine Optimization: Use game's own visibility check first
    if not targetActor.ViewportOnScreen and (dist > 100) and not Config.RageMode then
        local entry = VisCache[uid]
        if not entry then
            entry = {}; VisCache[uid] = entry
        end
        entry.result = false; entry.last = now; entry.point = nil
        return false
    end

    -- Build filter table (reuse pre-allocated)
    -- OPTIMIZATION: Use cached actor character list instead of iterating all actors per raycast
    table.clear(VisFilterTable)
    local fIdx = 0
    fIdx = fIdx + 1; VisFilterTable[fIdx] = Camera
    if LocalPlayer.Character then
        fIdx = fIdx + 1; VisFilterTable[fIdx] = LocalPlayer.Character
    end
    fIdx = fIdx + 1; VisFilterTable[fIdx] = character

    -- Rebuild actor chars cache when ActorManager updates (every 0.5s)
    local amFrame = ActorManager._lastListUpdate or 0
    if amFrame ~= _cachedActorCharsFrame then
        _cachedActorCharsFrame = amFrame
        table.clear(_cachedActorCharacters)
        if ReplicatorService and ReplicatorService.Actors then
            local ci = 0
            for _, actor in pairs(ReplicatorService.Actors) do
                if actor.Character then
                    ci = ci + 1
                    _cachedActorCharacters[ci] = actor.Character
                end
            end
        end
    end

    -- Add cached actor characters (fast array copy, no pairs() iteration)
    for i = 1, #_cachedActorCharacters do
        local c = _cachedActorCharacters[i]
        if c ~= character then
            fIdx = fIdx + 1; VisFilterTable[fIdx] = c
        end
    end

    if ReplicatorService and ReplicatorService.LocalActor then
        local myActor = ReplicatorService.LocalActor
        if myActor.Seat and myActor.Seat.Model then
            fIdx = fIdx + 1; VisFilterTable[fIdx] = myActor.Seat.Model
        end
    end

    VisRayParams.FilterDescendantsInstances = VisFilterTable

    local isVisible = false
    local visiblePoint = targetPart.Position

    if CheckPointVisible(visiblePoint, originPos, character, fIdx) then
        isVisible = true
    elseif Config.HitboxExpander then
        -- Hitbox Expander: if center is behind wall, check offset points
        -- When offset is visible, aim THERE (it's the only part peeking out)
        local sz = (Config.HitboxSize or 4) * 0.42
        for i = 1, #HitboxOffsets do
            local p = visiblePoint + (HitboxOffsets[i] * sz)
            if CheckPointVisible(p, originPos, character, fIdx) then
                isVisible = true
                visiblePoint = p -- Aim at the visible offset (center is blocked)
                break
            end
        end

        if not isVisible then
            for i = 1, 6 do
                local offset = HitboxOffsets[i] * (sz * 0.6)
                local p = visiblePoint + offset
                if CheckPointVisible(p, originPos, character, fIdx) then
                    isVisible = true
                    visiblePoint = p
                    break
                end
            end
        end
    end

    -- O4: Reuse VisCache entry tables
    local entry = VisCache[uid]
    if not entry then
        entry = {}; VisCache[uid] = entry
    end
    entry.result = isVisible; entry.last = now; entry.point = visiblePoint
    if isVisible then
        -- Only store _visiblePoint if hitbox expander found an offset
        -- When center is visible, clear it so hooks use targetHead.Position directly
        if visiblePoint ~= targetPart.Position then
            targetActor._visiblePoint = visiblePoint -- Hitbox offset aim point
        else
            targetActor._visiblePoint = nil          -- Center visible, aim naturally
        end
    end
    return isVisible
end

--[[
    COMBAT TARGETING (OPTIMIZED)
    High-performance target acquisition with pre-filtering and engine-calculated distances
]]
GetCombatTarget = function(mode)
    -- Reset Raycast Budget (Max 20 per frame for ragebot responsiveness)
    _genv.RaycastBudget = (mode == "Rage") and 50 or 12

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

    local candidates = _genv._targetCandidates or table.create(64)
    local candScores = _genv._targetCandScores or table.create(64)
    local candChars = _genv._targetCandChars or table.create(64)
    table.clear(candidates)
    table.clear(candScores)
    table.clear(candChars)
    _genv._targetCandidates = candidates
    _genv._targetCandScores = candScores
    _genv._targetCandChars = candChars

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
        enemyList = _genv._cachedEnemyList or table.create(100)
        table.clear(enemyList)
        _genv._cachedEnemyList = enemyList

        local px, pz = DecodeSectorKey(ActorManager._playerSector)
        for dx = -1, 1 do
            for dz = -1, 1 do
                local key = (px + dx) * 65536 + (pz + dz)
                local sectorEnemies = ActorManager._sectors[key]
                if sectorEnemies then
                    for _, actor in ipairs(sectorEnemies) do
                        enemyList[#enemyList + 1] = actor
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
        if actor.Downed then continue end -- F3: Skip incapacitated targets

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
            dist = math.sqrt(delta.X * delta.X + delta.Y * delta.Y + delta.Z * delta.Z)
        end

        -- Distance pre-filter (using squared distance when possible)
        if dist > maxDistance then continue end

        -- RAGEBOT: 360° TARGET ACQUISITION (No FOV/Viewport restrictions!)
        -- For Ragebot (mode == "Rage"), useFOV = false, so targets in ALL directions
        -- are valid. Only limited by Rage_Range distance, not screen position.
        local score = dist -- Default: closest first (Ragebot)

        -- FOV filtering for Silent Aim
        if useFOV then
            -- OPT: Use engine-cached ViewportOnScreen FIRST (free, already computed by game)
            -- Only fallback to WorldToViewportPoint if engine value is missing
            if not actor.ViewportOnScreen then continue end

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
            local screenDistSq = (dx * dx) + (dy * dy)

            if screenDistSq > fovLimitSq then continue end
            score = screenDistSq -- Silent Aim: closest to crosshair
        end

        -- P12: Store candidate in parallel arrays (eliminates per-actor table alloc)
        local n = #candidates + 1
        candidates[n] = actor
        candScores[n] = score
        candChars[n] = char
    end

    -- Early exit if no candidates
    local numCand = #candidates
    if numCand == 0 then return nil, nil end

    -- 2. Linear min-scan: find best score index
    local bestIdx = 1
    local bestScore = candScores[1]
    for ci = 2, numCand do
        if candScores[ci] < bestScore then
            bestScore = candScores[ci]
            bestIdx = ci
        end
    end
    -- Swap best to front
    if bestIdx ~= 1 then
        candidates[1], candidates[bestIdx] = candidates[bestIdx], candidates[1]
        candScores[1], candScores[bestIdx] = candScores[bestIdx], candScores[1]
        candChars[1], candChars[bestIdx] = candChars[bestIdx], candChars[1]
    end

    -- 3. VISIBILITY CHECK (Budget-aware, prioritized order)
    for i = 1, numCand do
        local actor = candidates[i]
        local char = candChars[i]

        -- Find target part (direct table lookup)
        local part = actor.Parts and actor.Parts[targetPartName]
        if not part then
            part = (actor.Parts and (actor.Parts["Head"] or actor.Parts["UpperTorso"])) or char:FindFirstChild("Head")
        end

        if part and part.Parent then
            if IsVisible(actor, part, checkOrigin) then
                return part, actor
            end

            -- Budget exhausted - stop checking
            if _genv.RaycastBudget <= 0 then break end
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

            -- P18: Fallback to Camera CFrame if original failed (prevents "invalid argument #1" crash in BulletService)
            if not muzzleCF then
                muzzleCF = Workspace.CurrentCamera.CFrame
            end
            -- Determine if this controller is a vehicle weapon
            local isVehicleWeapon = false
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
                local targetPos = targetActor._visiblePoint or targetHead.Position
                local gravity = 32.2 -- Hardcoded engine gravity
                local muzzle_velocity = 2000

                if self._firearm and self._firearm.Tune then
                    local caliberName = self._firearm.Tune.Caliber
                    local barrelLen = self._firearm.Tune.Barrel

                    -- OPT: Cache velocity per-weapon (key = caliber+barrel) to avoid pcall every shot
                    local cacheKey = (caliberName or "") .. (barrelLen or "1")
                    local cachedVel = controller._cachedVelocity
                    if cachedVel and controller._cachedVelKey == cacheKey then
                        muzzle_velocity = cachedVel
                    elseif BulletService and BulletService.GetInfo then
                        local success, vel = pcall(BulletService.GetInfo, BulletService, caliberName, barrelLen)
                        if success and vel then
                            muzzle_velocity = vel
                            controller._cachedVelocity = vel
                            controller._cachedVelKey = cacheKey
                        end
                    end
                end

                local targetVelocity = GetTargetVelocity(targetActor)

                -- Safety check removed (handled by top-level fallback)

                local aimPos, travelTime = SolveLead(muzzleCF.Position, targetPos, targetVelocity, muzzle_velocity,
                    gravity)

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
                    local muzzlePos = GetMuzzlePosition() -- Use shared function
                    if not muzzlePos then muzzlePos = Camera.CFrame.Position end

                    local targetPos = targetHead.Position
                    local direction = (targetPos - muzzlePos).Unit

                    -- Force Character Orientation (Consistent with ActorClass Yaw calculation)
                    if self._actor and self._actor.IsLocalPlayer and ReplicatorService.LocalActor.Character then
                        local root = ReplicatorService.LocalActor.Character.PrimaryPart
                        local myActor = ReplicatorService.LocalActor
                        if root then
                            local yaw = math.atan2(direction.X, direction.Z)
                            myActor.Orientation = yaw
                            myActor.GoalOrientation = yaw
                            myActor.CameraX = yaw
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

        -- OPT: Early exit before any service lookups when both disabled
        if not walkEnabled and not sprintEnabled then
            -- Only reset SpeedPenalty if we previously set it
            if _genv._speedHackActive then
                local actor = ReplicatorService and ReplicatorService.LocalActor
                if actor and actor.SpeedPenalty then actor.SpeedPenalty = nil end
                _genv._speedHackActive = false
            end
            return
        end

        local actor = nil
        if ReplicatorService and ReplicatorService.LocalActor then
            actor = ReplicatorService.LocalActor
        elseif ControllerService and ControllerService.Controller and ControllerService.Controller._localActor then
            actor = ControllerService.Controller._localActor
        end

        if not actor then return end

        -- Detect if sprinting (from CharacterController: IsSprinting property)
        local controller = ControllerService and ControllerService.Controller
        local isSprinting = controller and controller.IsSprinting

        local multiplier = 1

        if sprintEnabled and isSprinting then
            multiplier = (Config.Character_SprintSpeed or 25) / 16.8
        elseif walkEnabled and not isSprinting then
            multiplier = (Config.Character_WalkSpeed or 16) / 12
        end

        actor.SpeedPenalty = multiplier
        _genv._speedHackActive = true
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
    -- OPTIMIZATION: Use cached time and increase throttle to 2 seconds
    local now = getgenv().LastTime or tick()
    if firearm._LastTuneTime and (now - firearm._LastTuneTime < 2) and not force then return end
    firearm._LastTuneTime = now

    local tune = firearm._firearm.Tune
    local caliber = firearm._caliber
    local override = firearm._firearm.OverrideTune

    -- Initialize Backups (Tune)
    if not tune._Originals then
        tune._Originals = {
            Recoil_X = tune.Recoil_X,
            Recoil_Z = tune.Recoil_Z,
            Recoil_Camera = tune.Recoil_Camera,
            RecoilForce_Tap = tune.RecoilForce_Tap,
            RecoilForce_Impulse = tune.RecoilForce_Impulse,
            Recoil_Range = tune.Recoil_Range,
            Recoil_KickBack = tune.Recoil_KickBack,
            Barrel_Spread = tune.Barrel_Spread,
            Spread = tune.Spread,
            RPM = tune.RPM,
            Firemodes = tune.Firemodes,
            Bolt = tune.Bolt,
            Bolt_Action_Pause = tune.Bolt_Action_Pause,
            -- Add potential movement spread keys if they exist
            Hipfire_Spread = tune.Hipfire_Spread,
            Move_Spread = tune.Move_Spread,
            Jump_Spread = tune.Jump_Spread,
            MinSpread = tune.MinSpread,
            MaxSpread = tune.MaxSpread
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
            Recoil_X = override.Recoil_X,
            Recoil_Z = override.Recoil_Z,
            Recoil_Camera = override.Recoil_Camera,
            RecoilForce_Tap = override.RecoilForce_Tap,
            RecoilForce_Impulse = override.RecoilForce_Impulse,
            Spread = override.Spread,
            RPM = override.RPM,
            Firemodes = override.Firemodes
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
        for k, v in pairs(tune._Originals) do if tune[k] ~= nil then tune[k] = v end end
        if override and override._Originals then
            for k, v in pairs(override._Originals) do if override[k] ~= nil then override[k] = v end end
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
        if override then
            override.Spread = 0; override.MinSpread = 0; override.MaxSpread = 0
        end
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
                -- R1: Direct multi-return instead of table packing (saves ~30 allocs/frame)
                local ok, r1, r2 = pcall(ac._originalUpdate, self, ...)
                if ok then
                    return r1, r2
                end

                -- CRASH MITIGATION (V4): Return authoritative state if engine failed
                if self.Alive and self.Character and self.CFrame then
                    return self.CFrame,
                        self.RootPart or self.Character.PrimaryPart or self.Character:FindFirstChild("LowerTorso")
                end
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
                local lighting = Lighting
                -- R4: Cache Atmosphere and Clouds lookups
                local cachedAtmosphere, cachedClouds

                mt.Update = function(self, dt, ...)
                    local result = mt._originalUpdate(self, dt, ...)

                    if Config.AlwaysDay then
                        lighting.ClockTime = 12

                        local isInterior = false
                        pcall(function()
                            if self._room and self._room.IsInterior then
                                isInterior = true
                            end
                        end)

                        if isInterior then
                            lighting.GlobalShadows = false
                            lighting.Ambient = Color3_new(1, 1, 1)
                            lighting.OutdoorAmbient = Color3_new(1, 1, 1)
                        else
                            lighting.GlobalShadows = true
                        end
                    end

                    if Config.NoFog then
                        lighting.FogEnd = 100000
                        lighting.FogStart = 0

                        local atmosphere = cachedAtmosphere or self._atmosphere or
                        lighting:FindFirstChildOfClass("Atmosphere")
                        if atmosphere then
                            cachedAtmosphere = atmosphere
                            atmosphere.Density = 0
                            atmosphere.Haze = 0
                            atmosphere.Glare = 0
                            atmosphere.Offset = 0
                        end

                        local clouds = cachedClouds or self._clouds or lighting:FindFirstChildOfClass("Clouds")
                        if clouds then
                            cachedClouds = clouds
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
                    if Config.AlwaysDay then
                        lighting.ClockTime = 12

                        local isInterior = false
                        pcall(function()
                            if self._room and self._room.IsInterior then
                                isInterior = true
                            end
                        end)

                        if isInterior then
                            lighting.Brightness = 2
                            lighting.GlobalShadows = false
                            lighting.Ambient = Color3_new(1, 1, 1)
                            lighting.OutdoorAmbient = Color3_new(1, 1, 1)
                        else
                            lighting.GlobalShadows = true
                        end
                    end
                    if Config.NoFog then
                        lighting.FogEnd = 100000
                        local atm = lighting:FindFirstChildOfClass("Atmosphere")
                        if atm then
                            atm.Density = 0; atm.Haze = 0
                        end
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

                -- FORCE REPLICATOR SYNC: Ensure the actor is always active for rendering/movement
                localActor.UseClient = true
                localActor._lod = false
                localActor._isInactive = false

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

                -- CLEANUP PHYSICS: Ensure we aren't in a state that locks movement
                if localActor.Rappelling then localActor.Rappelling = nil end

                -- VISIBILITY ENFORCEMENT: Fixes character disappearing when switching FP/TP
                if localActor.Character and localActor.Character.Parent ~= workspace then
                    localActor.Character.Parent = workspace
                end

                -- Force visibility of all character parts (Head, Torso, etc.)
                if localActor.Parts then
                    for _, part in pairs(localActor.Parts) do
                        if part:IsA("BasePart") then
                            part.LocalTransparencyModifier = 0
                        end
                    end
                end

                local camCF = Camera.CFrame
                local dir = Vector3_new(0, 0, 0)

                -- AGGRESSIVE INPUT CAPTURE: Direct UserInputService check to bypass engine suppression
                if UserInputService:IsKeyDown(Enum.KeyCode.W) then dir = dir + camCF.LookVector end
                if UserInputService:IsKeyDown(Enum.KeyCode.S) then dir = dir - camCF.LookVector end
                if UserInputService:IsKeyDown(Enum.KeyCode.D) then dir = dir + camCF.RightVector end
                if UserInputService:IsKeyDown(Enum.KeyCode.A) then dir = dir - camCF.RightVector end
                if UserInputService:IsKeyDown(Enum.KeyCode.Space) then dir = dir + Vector3_new(0, 1, 0) end
                if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then dir = dir - Vector3_new(0, 1, 0) end

                local flySpeedVal = tonumber(Config.Character_FlySpeed) or 50
                local flySprint = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) and 2.5 or 1
                local deltaTime = type(dt) == "number" and dt or 0.016

                local nextPos = self._position + (dir * flySpeedVal * flySprint * deltaTime)

                -- SYNC ALL PROPERTIES: Force ReplicatorService and Engine to see new position
                self._position = nextPos
                self._lastSafePosition = nextPos

                localActor.Position = nextPos
                localActor.SimulatedPosition = nextPos

                local _, yRot = camCF:ToOrientation()
                localActor.CFrame = CFrame.new(nextPos) * CFrame.Angles(0, yRot, 0)
                localActor.Orientation = yRot

                -- Return position for ReplicatorService's internal tracking
                return
            else
                -- RESET STATE
                if self._localActor then
                    if self._localActor.Rappelling then self._localActor.Rappelling = nil end
                end

                return OldUpdate(self, viewInput, dt, ...)
            end
        end
    else

    end
end

--[[
    COMBAT LOGIC
]]
-- Persistent velocity/tune cache stored in _genv to avoid module-level locals
-- (module-level locals count as upvalues in ALL closures, risking the 200-upvalue limit)
-- _genv is already an existing upvalue, so storing sub-fields costs nothing extra.
if not _genv._activeVelocity then _genv._activeVelocity = 2000 end

local function UpdateCombat(frameId)
    local now = _genv.LastTime or tick()
    -- OPTIMIZATION: Cache mouse state once per frame (avoid repeated UserInputService calls)
    local mousePressed = UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)

    local cfg = Config
    -- activeVelocity/activeTune live in _genv (persistent across frames, no extra upvalue cost)
    local activeVelocity = _genv._activeVelocity or 2000
    local showWeaponInfo = cfg.ShowWeaponInfo
    local showPred = cfg.ShowPrediction or (cfg.SilentAim and cfg.Prediction)
    local activeTune = _genv._activeTune


    -- BACKGROUND LOOPS COMPLETELY REMOVED.
    -- Modifications are handled permanently by class hooks.

    -- Update via signals if possible
    if InventoryService and not WeaponManager.Connection then
        if InventoryService.OnInterfaceStateChanged then
            WeaponManager.Connection = InventoryService.OnInterfaceStateChanged:Connect(function()
                WeaponManager.Equipped = InventoryService.Equipped and InventoryService.Equipped.Handler
            end)
            table.insert(_genv.BlackhawkESP_Connections, WeaponManager.Connection)
        end
        -- Initial Sync
        WeaponManager.Equipped = InventoryService.Equipped and InventoryService.Equipped.Handler
    end

    -- JIT Cache & Immediate Modification
    -- LIVE CHECK: Always verify weapon is currently equipped (prevents stale reference firing)
    local liveEquipped = InventoryService and InventoryService.Equipped and InventoryService.Equipped.Handler
    if liveEquipped then
        WeaponManager.Equipped = liveEquipped
    else
        WeaponManager.Equipped = nil
    end
    local equippedController = WeaponManager.Equipped

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

        if Config.RageMode and ActorManager.SelectedTarget_RB and equippedController._firearm
            and equippedController._item then -- Extra guard: _item exists only when weapon is in hand
            local targetActor = ActorManager.SelectedActor_RB
            -- F1: Don't use bare return — it exits entire UpdateCombat
            if not targetActor or not targetActor.Alive or targetActor.Downed then
                ActorManager.SelectedTarget_RB = nil
                ActorManager.SelectedActor_RB = nil
            else
                local uid = targetActor.UID

                -- CACHE: Weapon stats + damage (cached per weapon change, not per frame)
                local weaponRPM = 600
                local weaponCaliber = equippedController._caliber

                local cachedWeapon = ActorManager._cachedRageWeapon
                if cachedWeapon and cachedWeapon.controller == equippedController then
                    weaponRPM = cachedWeapon.rpm
                else
                    if equippedController._firearm and equippedController._firearm.Tune then
                        weaponRPM = equippedController._firearm.Tune.RPM or 600
                    end

                    local estDmg = 80
                    local tgtPartName = Config.Rage_TargetPart or "Head"
                    local calConfig = CalibersTable and weaponCaliber and CalibersTable[weaponCaliber]
                    if calConfig and calConfig.Damage and calConfig.Dropoff and BulletService then
                        -- F2: Direct pcall without closure
                        local ok1, _, rangeOff = pcall(BulletService.GetInfo, BulletService, weaponCaliber, 10)
                        if ok1 then
                            local ok2, dmg = pcall(BulletService.GetDamageGraph, BulletService, 0, rangeOff or 0,
                                calConfig.Damage, calConfig.Dropoff, calConfig.Damp or 1, tgtPartName)
                            if ok2 and dmg and dmg > 0 then
                                estDmg = dmg * (calConfig.Bullets or 1)
                            end
                        end
                    end

                    ActorManager._cachedRageWeapon = {
                        controller = equippedController,
                        rpm = weaponRPM,
                        estDamage = estDmg
                    }
                end

                local estDamage = ActorManager._cachedRageWeapon and ActorManager._cachedRageWeapon.estDamage or 80

                local shotsNeeded
                local ignoreTime
                local isPVP = Config.CurrentMapType == "PVP"
                local targetHP = 100
                if targetActor.Health then
                    if type(targetActor.Health) == "number" then
                        targetHP = targetActor.Health
                    elseif type(targetActor.Health) == "table" then
                        targetHP = targetActor.Health.Value or 100
                    end
                end

                if isPVP then
                    -- F4: Always recalculate from live HP (target may have taken damage from others)
                    shotsNeeded = math_ceil(targetHP / estDamage)
                    if shotsNeeded < 1 then shotsNeeded = 1 end
                    ignoreTime = 0.5
                else
                    shotsNeeded = Config.Rage_BurstSize or 1
                    ignoreTime = 0.5
                end

                local shotsFired = ActorManager._rageShots[uid] or 0
                local lastShot = ActorManager._rageLast[uid] or 0
                local fireDelay = 60 / weaponRPM

                if shotsFired >= shotsNeeded then
                    ActorManager._ignoredTargets[uid] = now + ignoreTime
                    ActorManager.SelectedTarget_RB = nil
                    ActorManager.SelectedActor_RB = nil
                elseif (Config.Rage_AutoFire or mousePressed) and (now - lastShot >= fireDelay) then
                    local hasAmmo = (equippedController._mag and equippedController._mag.Capacity > 0) or
                        (equippedController._item and equippedController._item.MetaData and equippedController._item.MetaData.Chamber)
                    -- F1: Don't return on no ammo — just skip shooting
                    if hasAmmo then
                        ActorManager._rageLast[uid] = now
                        ActorManager._rageShots[uid] = shotsFired + 1
                        rageDidShoot = true

                        local dischargeMethod = equippedController.Discharge
                        if dischargeMethod then
                            local currentCam = Workspace.CurrentCamera
                            if currentCam then
                                equippedController:Discharge()
                            end
                        end

                        if (shotsFired + 1) >= shotsNeeded then
                            ActorManager._ignoredTargets[uid] = now + ignoreTime
                            ActorManager.SelectedTarget_RB = nil
                            ActorManager.SelectedActor_RB = nil
                        end
                    end
                end
            end -- end else (valid target)
        end

        -- (Dead safety block removed — was no-op)

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
                -- R2: Use pre-allocated triggerbot raycast params
                TriggerbotRayParams.FilterDescendantsInstances = { Camera, LocalPlayer.Character }
                local result = Workspace:Raycast(ray.Origin, ray.Direction * 1000, TriggerbotRayParams)

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
                    local hasAmmo = (equippedController._mag and equippedController._mag.Capacity > 0) or
                        (equippedController._item and equippedController._item.MetaData and equippedController._item.MetaData.Chamber)
                    if not hasAmmo then
                        -- Skip firing only (don't exit UpdateCombat)
                    else
                        equippedController._lastTriggerShot = now

                        -- Fire Weapon directly via Discharge
                        local dischargeMethod = equippedController.Discharge
                        if dischargeMethod then
                            local currentCam = Workspace.CurrentCamera
                            if currentCam then
                                equippedController:Discharge()
                            end
                        end
                    end -- hasAmmo
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
                        tConfig.Recoil_Base = Vector2.new(0, 0)
                        tConfig.Recoil_Range = Vector2.new(0, 0)
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
                                tConfig.Recoil_Base = Vector2.new(0, 0)
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
                        -- R3: Direct pcall without closure
                        local success, v = pcall(BulletService.GetInfo, BulletService, activeTune.Caliber,
                            activeTune.Barrel or 1)
                        if success and v and v > 0 then velocity = v end
                    end

                    if velocity == 0 then
                        velocity = activeTune.Velocity or (activeTune.MuzzleVelocity and activeTune.MuzzleVelocity.Value) or
                            2000
                    end

                    activeVelocity = velocity
                    _genv._activeVelocity = velocity -- persist for next frame

                    if showWeaponInfo then
                        local weaponName = firearm.Name or activeTune.Name or "Unknown"


                        local caliberName = ""
                        if CalibersTable and activeTune.Caliber and CalibersTable[activeTune.Caliber] then
                            local cal = CalibersTable[activeTune.Caliber]
                            if cal and cal.FamilyName then
                                caliberName = cal.FamilyName
                                if cal.VariantName and cal.VariantName ~= "" then
                                    caliberName = caliberName ..
                                        " " .. cal.VariantName
                                end
                            end
                        end

                        local velocityMS = math_floor(velocity * 0.3048 + 0.5)
                        local infoText = string_format("Weapon: %s\nCaliber: %s\nVelocity: %d m/s", weaponName,
                            caliberName ~= "" and caliberName or "N/A", velocityMS)

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

                        root.CFrame = CFrame.new(root.Position,
                            root.Position + Vector3_new(math.sin(yaw), 0, math.cos(yaw)))
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
            local rawVel = GetTargetVelocity(targetActor)

            -- P11: Initialize or Lerp (using cached _genv)
            if not _genv._lastPredVel then
                _genv._lastPredVel = rawVel
            else
                _genv._lastPredVel = _genv._lastPredVel:Lerp(rawVel, 0.15)
            end
        end

        if _genv.PredictionDot then
            local dot = _genv.PredictionDot

            if Config.ShowPrediction and targetPart then
                local muzzlePos = GetMuzzlePosition() or Camera.CFrame.Position
                local targetPos = targetPart.Position
                local targetVel = _genv._lastPredVel or VECTOR3_ZERO
                local gravity = 32.2

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
        return Config.PlayerColor or Color3_new(1, 0.65, 0)                         -- Orange/Red
    elseif entityType == "Zombie" then
        -- Check zombie ability level for color
        if actor.Health and type(actor.Health) == "table" and actor.Health.Ability then
            return Config.ZombieColors[actor.Health.Ability] or Config.ZombieColor or Color3_new(1, 0, 0)
        end
        return Config.ZombieColor or Color3_new(1, 0, 0)
    elseif entityType == "NPC" then
        return Config.NPCColor or Color3_new(1, 1, 0) -- Yellow
    end

    return Color3_new(1, 1, 1) -- White for unknown
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
    -- 1. Trust ControllerService (Should be found by BulkScan/FindService_Module now)
    if ControllerService and ControllerService.Controller and ControllerService.Controller._vehicle then
        return ControllerService.Controller
    end

    -- 2. Fallback: Find Vehicle via VehicleService (No GC Scan)
    -- This handles cases where ControllerService might be desynced or missing
    if VehicleService and VehicleService.Vehicles then
        local player = LocalPlayer
        local char = player.Character
        local root = char and (char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart)
        local hum = char and char:FindFirstChild("Humanoid")
        local seat = hum and hum.SeatPart

        for _, veh in pairs(VehicleService.Vehicles) do
            if veh and veh.Model then
                -- Check Seat
                if seat and seat:IsDescendantOf(veh.Model) then
                    -- Return vehicle itself or mock controller.
                    -- Note: Without ControllerService, we can't guarantee _solver,
                    -- but we return the vehicle object which often acts as the controller structure in this game.
                    return { _vehicle = veh, _solver = veh._solver or {} }
                end

                -- Check Owner/Distance
                if veh.Owner == player then
                    local targetPart = veh.Model.PrimaryPart or veh.Model:FindFirstChildOfClass("BasePart")
                    local dist = (targetPart and root) and (root.Position - targetPart.Position).Magnitude or 9999

                    if dist < 80 or dist == 9999 then
                        return { _vehicle = veh, _solver = veh._solver or {} }
                    end
                end
            end
        end
    end

    if Notifier and Notifier.new then
        Notifier.new({ Title = "Vehicle Error", Content = "No active vehicle found!", Duration = 3 })
    end
    print("[Teleport] No active vehicle found.")
    return nil
end

local function TeleportVehicle(targetPos, targetRotY)
    local net = GetNetwork()
    if not net then
        if Notifier and Notifier.new then
            Notifier.new({ Title = "Error", Content = "Network Service not found!", Duration = 3 })
        else
            warn("[Teleport] Network Service not found!")
        end
        return
    end

    local controller = GetActiveVehicleController()

    if not controller or not controller._vehicle then
        if Notifier and Notifier.new then
            Notifier.new({ Title = "Error", Content = "Get in a vehicle first!", Duration = 3 })
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
        solver:SetState(newCF, Vector3.new(0, 0, 0), Vector3.new(0, 0, 0), vehicle.ComponentReplicates)
    end

    -- 3. Replicate to Server
    -- "ReplicateVehicle", UID, x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22, Steering, Throttle, Components
    local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = newCF:GetComponents()
    local steering = vehicle.Steering or 0
    local components = vehicle.ComponentReplicates

    net:FireServer("ReplicateVehicle", vehicle.UID, x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22, steering,
        components)

    if Notifier and Notifier.new then
        Notifier.new({ Title = "Teleport", Content = "Vehicle Teleported!", Duration = 3 })
    else
        -- Fallback if Notifier is missing
        print("[Teleport] Vehicle Teleported!")
    end
end

DetectMapType = function()
    -- 1. Check PlaceId (Most Reliable)
    local currentId = game.PlaceId

    -- Specjalny przypadek na zbugowane ID trybu Zombie (ZMP / ZME wspoldziela 4747446334)
    if currentId == 4747446334 or currentId == 84460047957624 then
        -- NOWA, NIEZAWODNA METODA DLA MAP ZOMBIE:
        -- Limit MaxPlayers okazal sie kompletnie zbugowany poniewaz obie mapy stawiaja serwery 30 slotow.
        -- Sprawdzamy wiec czy w Workspace znajduje sie wyrazny folder PvE czy PvP wygenerowany przez silnik.
        if workspace:FindFirstChild("PvE") then
            Config.CurrentMapName = "ZME_NYC"
            return "Zombie" -- ZME_NYC to Player vs Zombies (PvE)
        elseif workspace:FindFirstChild("PvP") then
            Config.CurrentMapName = "ZMP_NYC"
            return "PVP" -- ZMP_NYC to Player vs Player (PvP)
        end

        -- Fallback tylko w razie jakiegos bledu ładowana przestrzeni (rzadkie)
        local maxPlayers = game:GetService("Players").MaxPlayers
        if maxPlayers > 20 then
            Config.CurrentMapName = "ZMP_NYC"
            return "PVP"
        else
            Config.CurrentMapName = "ZME_NYC"
            return "Zombie"
        end
    end

    local foundName = nil
    for name, data in pairs(Places) do
        if data[1] == currentId or data[2] == currentId then
            foundName = name
            Config.CurrentMapName = name -- Store exact name

            if name:find("PVP_") then return "PVP" end
            if name:find("ZM") then return "Zombie" end
            if name:find("OW_") then return "OpenWorld" end
            if name:find("DEV_") then return "OpenWorld" end
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

    -- Jesli _worldService nam pomoze rozeznac:
    if placeName == "ZME_NYC" then
        Config.CurrentMapName = "ZME_NYC"
        return "Zombie" -- Zwiadczenie z folderu PvE/PvP bylo glowne, tu WorldService wkracza jako pewnik
    elseif placeName == "ZMP_NYC" then
        Config.CurrentMapName = "ZMP_NYC"
        return "PVP"
    end

    -- Zachowaj tylko gdy na pewno udalo sie cos znalezc (inaczej zostawi poprzednia nazwe)
    if placeName ~= "" and placeName ~= "Unknown" and not foundName then
        Config.CurrentMapName = placeName
    end

    if placeName:find("PVP_") then
        return "PVP"
    elseif placeName:find("ZM") then
        return "Zombie"
    elseif placeName:find("OW_") or placeName:find("DEV_") or placeName == "Default" then
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

    -- pcall: Highlight Instance may fail in executor security context
    local ok, highlight = pcall(function()
        local h = Instance.new("Highlight")
        h.FillColor = color
        h.FillTransparency = 0.9
        h.OutlineColor = color
        h.OutlineTransparency = 0
        h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        h.Parent = actor.Character
        return h
    end)
    return ok and highlight or nil
end

local function CreateDrawingESP()
    -- If Drawing API is completely missing, return an empty drawing table and force SimpleESP
    if not DrawingAPI_Available then return nil end

    local esp = {
        BoxOutline = SafeDrawing("Square"),
        Box = SafeDrawing("Square"),
        HealthBarOutline = SafeDrawing("Square"),
        HealthBar = SafeDrawing("Square"),
        Name = SafeDrawing("Text"),
        Distance = SafeDrawing("Text"),
        Weapon = SafeDrawing("Text"),
        Tracer = SafeDrawing("Line"),
        Corners = {}
    }

    -- If the executor failed to create the basic drawing, abort ESP creation to avoid crashes
    if not esp.BoxOutline then return nil end

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
    esp.Name.Font = ((Drawing and Drawing.Fonts) and Drawing.Fonts.UI) or 2
    esp.Name.ZIndex = 3

    esp.Distance.Visible = false
    esp.Distance.Color = Color3.new(1, 1, 1)
    esp.Distance.Size = 12
    esp.Distance.Center = true
    esp.Distance.Outline = true
    esp.Distance.Font = ((Drawing and Drawing.Fonts) and Drawing.Fonts.UI) or 2
    esp.Distance.ZIndex = 3

    esp.Weapon.Visible = false
    esp.Weapon.Color = Color3.new(1, 1, 1)
    esp.Weapon.Size = 12
    esp.Weapon.Center = true
    esp.Weapon.Outline = true
    esp.Weapon.Font = ((Drawing and Drawing.Fonts) and Drawing.Fonts.UI) or 2
    esp.Weapon.ZIndex = 3

    esp.Tracer.Visible = false
    esp.Tracer.Color = Color3.new(1, 1, 1)
    esp.Tracer.Thickness = 1
    esp.Tracer.Transparency = 1

    -- Corner Box Lines (8 lines)
    for i = 1, 8 do
        local line = SafeDrawing("Line")
        if line then
            line.Visible = false
            line.Thickness = 1
            line.Color = Color3.new(1, 1, 1)
            line.Transparency = 1
            table.insert(esp.Corners, line)
        end
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

    -- Always create Drawing ESP elements (managed visibility). Fallback logic inside safely prevents errors.
    espData.Drawing = CreateDrawingESP()

    -- If Drawing library is fully unsupported, silently force SimpleESP so player still has ESP
    if not espData.Drawing then
        Config.SimpleESP = true
    end

    -- Create Simple ESP elements (used if Config.SimpleESP is enabled)
    CreateSimpleESP(espData)

    ESPElements[actor.UID] = espData
end

-- Helper function to efficiently toggle all drawing visibility (with Caching)
-- NOTE: Per-feature visibility (boxes, names, health, tracers) is handled in UpdateESPForActor.
-- This function just toggles the entire group ON/OFF.
local function SetAllVisible(drawings, espData, visible)
    if espData._visible == visible then return end
    espData._visible = visible

    drawings.Box.Visible = visible
    drawings.BoxOutline.Visible = visible
    drawings.Name.Visible = visible
    drawings.Distance.Visible = visible
    drawings.Weapon.Visible = visible
    drawings.HealthBar.Visible = visible
    drawings.HealthBarOutline.Visible = visible
    drawings.Tracer.Visible = visible

    -- Highlight is a Roblox Instance — needs pcall (Plugin security context)
    if espData.Highlight then pcall(function() espData.Highlight.Enabled = visible end) end

    -- Hide corner lines when going invisible
    if not visible and espData._cornersVisible then
        local corners = drawings.Corners
        corners[1].Visible = false; corners[2].Visible = false
        corners[3].Visible = false; corners[4].Visible = false
        corners[5].Visible = false; corners[6].Visible = false
        corners[7].Visible = false; corners[8].Visible = false
        espData._cornersVisible = false
    end
end

-- Hitbox Expander Helper
local OriginalSizes = setmetatable({}, { __mode = "k" })
local function ApplyHitboxExpander(actor, espData, cfg, localSquad)
    local head = espData.CachedHead
    local enabled = Config.HitboxExpander -- P10: Bypass delayed cache for strict frame-perfect toggle reading

    if not head or not head.Parent then
        local char = actor.Character
        -- OPTIMIZATION: actor.Parts.Head is direct engine ref (no FindFirstChild)
        head = (actor.Parts and actor.Parts.Head) or (char and char:FindFirstChild("Head"))
        espData.CachedHead = head
    end

    if not head then
        -- Cleanup: if old head was tracked, remove it from OriginalSizes
        -- (head was destroyed by engine, e.g. actor died)
        if espData._lastTrackedHead and OriginalSizes[espData._lastTrackedHead] then
            OriginalSizes[espData._lastTrackedHead] = nil
        end
        espData._lastTrackedHead = nil
        return
    end
    espData._lastTrackedHead = head

    if enabled and actor.Alive and not IsTeammate(actor, localSquad) then
        if not OriginalSizes[head] then OriginalSizes[head] = head.Size end
        local sz = cfg.HitboxSize or 4

        -- P16: Only update properties if they actually need changing
        if head.Size.X ~= sz then
            head.Size = Vector3_new(sz, sz, sz)
            head.Transparency = 0.5
            head.CanCollide = false
        end
    elseif OriginalSizes[head] then
        if head.Size ~= OriginalSizes[head] then
            head.Size = OriginalSizes[head]
            head.Transparency = 0
            head.CanCollide = true
        end
        OriginalSizes[head] = nil
    end
end

getgenv().ResetAllHitboxes = function()
    for head, origSize in pairs(OriginalSizes) do
        if head and head.Parent then
            head.Size = origSize
            head.Transparency = 0
            head.CanCollide = true
        end
    end
    table.clear(OriginalSizes)
end

local function RemoveESP(uid)
    local espData = ESPElements[uid]
    if not espData then return end

    if espData.Highlight then 
        pcall(function() espData.Highlight:Destroy() end) 
    end

    if espData.SimpleESP and espData.SimpleESP.Box then
        pcall(function() espData.SimpleESP.Box:Destroy() end)
    end

    if espData.Drawing then
        local drawings = espData.Drawing
        if drawings.Box then pcall(function() drawings.Box:Remove() end) end
        if drawings.BoxOutline then pcall(function() drawings.BoxOutline:Remove() end) end
        if drawings.Name then pcall(function() drawings.Name:Remove() end) end
        if drawings.Distance then pcall(function() drawings.Distance:Remove() end) end
        if drawings.HealthBar then pcall(function() drawings.HealthBar:Remove() end) end
        if drawings.HealthBarOutline then pcall(function() drawings.HealthBarOutline:Remove() end) end
        if drawings.Tracer then pcall(function() drawings.Tracer:Remove() end) end
        if drawings.Weapon then pcall(function() drawings.Weapon:Remove() end) end
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
    local drawings = espData.Drawing
    if not drawings then return end -- Safety Guard

    local entityType = actor._entityType or "Unknown"

    -- Mark as updated
    espData.LastUpdate = frameId

    -- If ESP was toggled OFF while HitboxExpander keeps loop alive -> Hide ALL visuals immediately
    if not ESPEnabled then
        SetAllVisible(drawings, espData, false)
        if espData.SimpleESP and espData.SimpleESP.Box then
            pcall(function() espData.SimpleESP.Box.Visible = false end)
        end
        if espData.Highlight then
            pcall(function() espData.Highlight.Enabled = false end)
        end

        -- We DO NOT return here! We must let the HitboxExpander logic run below.
    end

    -- Check if actor is still valid and Alive (Engine Check)
    if not actor or not actor.Alive then
        if actor then
            -- P2: Direct head reset without pcall closure
            local head = espData.CachedHead
            if head and OriginalSizes[head] then
                local ok, _ = pcall(function()
                    head.Size = OriginalSizes[head]
                    head.Transparency = 0
                    head.CanCollide = true
                end)
                OriginalSizes[head] = nil
            end
            -- R7: Use direct call with HitboxExpander=false (no metatable alloc)
            ApplyHitboxExpander(actor, espData, { HitboxExpander = false }, localSquad)
        end
        RemoveESP(uid)
        return
    end

    -- Hitbox Expander Integration
    ApplyHitboxExpander(actor, espData, cachedCfg, localSquad)

    -- Bug Fix: Re-check filters for existing elements (REMOVED: Already checked in loop)
    -- if not ShouldShowEntity(actor, entityType, localSquad) then
    --    SetAllVisible(drawings, espData, false)
    --    return
    -- end

    local distance = actor.LOD_Distance or 9999

    -- P5: MERGED VISIBILITY CHECK (combines ViewportOnScreen + OnScreen + LOD_OnScreen)
    local isVisible = actor.ViewportOnScreen or actor.OnScreen or actor.LOD_OnScreen

    if actor._isInactive or (distance > cachedCfg.MaxDistance) or (not isVisible) then
        SetAllVisible(drawings, espData, false)
        if espData.SimpleESP and espData.SimpleESP.Box then
            pcall(function() espData.SimpleESP.Box.Visible = false end)
        end
        return
    end

    -- DISTANCE THROTTLING: Removed per user request to maintain 60 FPS for distant targets.

    -- MODE: Simple ESP (BoxHandleAdornment) — P2: removed pcall closures
    if cachedCfg.SimpleESP then
        SetAllVisible(drawings, espData, false)
        local sESP = espData.SimpleESP
        if distance < 50 then isVisible = true end

        if isVisible then
            local target = (actor.Parts and actor.Parts.Head) or
            (actor.Character and actor.Character:FindFirstChild("Head"))
            if target and sESP then
                local box = sESP.Box
                local ok = pcall(function()
                    box.Visible = true
                    box.Adornee = target
                    box.Size = Vector3_new(1.2, 1.2, 1.2)
                    box.Color3 = espData.Color
                end)
            end
        elseif sESP and sESP.Box then
            sESP.Box.Visible = false
        end
        return
    else
        -- Awaryjne gaszenie gdy gracz uzywa tradycyjnego ESP 2D, a pętla ma nadal wyrenderowany Simple ESP Box z poprzedniej klatki:
        -- Fallback: hide SimpleESP box when using 2D ESP mode
        if espData.SimpleESP and espData.SimpleESP.Box then
            pcall(function() espData.SimpleESP.Box.Visible = false end)
        end
    end

    -- Still need WorldToViewportPoint for precise screen coordinates
    local worldPos = actor.Position or (actor.RootPart and actor.RootPart.Position)
    if not worldPos then return end

    local cam = getgenv().LastCamCF or Camera.CFrame -- Use cached Camera CFrame
    local screen_point, onScreen = Camera:WorldToViewportPoint(worldPos)
    if not onScreen then
        SetAllVisible(drawings, espData, false)
        return
    end

    local screenX, screenY = screen_point.X, screen_point.Y
    SetAllVisible(drawings, espData, true)

    -- Update Highlight (pcall required — Roblox Instance security context)
    if espData.Highlight then
        pcall(function()
            espData.Highlight.FillColor = espData.Color
            espData.Highlight.OutlineColor = espData.Color
        end)
    end

    -- Calculate Box Dimensions (Using Fast 3D Math instead of engine calls)
    local height = 6.0                   -- Height multiplier for engine world
    local hState = actor.HeightState
    if hState == 1 then
        height = 4.0                     -- Crouching (Enum 1)
    elseif hState == 2 then
        height = 2.0                     -- Proning (Enum 2)
    elseif hState == 4 then
        height = 3.0                     -- Swimming (Enum 4)
    end

    -- P17: 66% reduction in engine boundary crossings!
    -- Use depth (screen_point.Z), FOV, and AspectRatio to calculate 2D height
    local scale = cachedCfg.BoxScale or 1
    -- OPT: aspectHeight is pre-computed once per frame (passed as argument), not per-actor
    local aspectH = cachedCfg._cachedAspectHeight or (Camera.ViewportSize.Y / (2 * math.tan(Camera.FieldOfView * 0.00872664625)))

    local depthZ = screen_point.Z
    if depthZ < 0.1 then depthZ = 0.1 end -- Prevent divide by zero

    local boxHeight = (height / depthZ) * aspectH * scale
    local boxWidth = boxHeight * 0.6

    local bpX, bpY = screenX - boxWidth * 0.5, screenY - boxHeight * 0.5

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
            local rightX = bpX + boxWidth
            local bottomY = bpY + boxHeight
            local topLeft = Vector2_new(bpX, bpY)
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

            espData._cornersVisible = true
        else
            -- Full box style — hide corner lines using cached flag
            if espData._cornersVisible then
                local corners = drawings.Corners
                corners[1].Visible = false; corners[2].Visible = false
                corners[3].Visible = false; corners[4].Visible = false
                corners[5].Visible = false; corners[6].Visible = false
                corners[7].Visible = false; corners[8].Visible = false
                espData._cornersVisible = false
            end

            drawings.BoxOutline.Size = Vector2_new(boxWidth, boxHeight)
            drawings.BoxOutline.Position = Vector2_new(bpX, bpY)
            drawings.BoxOutline.Visible = true

            drawings.Box.Size = Vector2_new(boxWidth, boxHeight)
            drawings.Box.Position = Vector2_new(bpX, bpY)
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
                displayName = ZombieAbilityNames[h.Ability] or "Zombie"
            else
                displayName = "Zombie"
            end
        elseif not displayName or displayName == "???" then
            displayName = "AI"
        end

        local dynamicScale = cachedCfg.DynamicTextScaling and math_clamp(boxHeight * 0.016, 0.5, 1.0) or 1.0
        local nameSize = 13 * cachedCfg.TextScale * dynamicScale

        -- Adjust Y if Health Bar is at Top
        local nameY = bpY - (nameSize + 3)
        if cachedCfg.HealthBarSide == "Top" then
            nameY = nameY - 8
        end

        drawings.Name.Text = displayName
        drawings.Name.Position = Vector2_new(screenX, nameY)
        drawings.Name.Color = espData.Color
        drawings.Name.Size = nameSize
        drawings.Name.Visible = true
    else
        drawings.Name.Visible = false
    end

    -- Weapon holding ESP
    local weaponShown = false
    if Config.ShowWeapon then
        local weaponName = nil
        if actor._equipped and actor._inventory and actor._inventory[actor._equipped] then
            local rep = actor._inventory[actor._equipped]
            local rawName = nil
            if rep._item then
                rawName = rep._item.Name or (rep._item.Layout and rep._item.Layout.Name)
            elseif rep._firearm then
                rawName = rep._firearm.Name
            end
            
            if rawName and rawName ~= "" then
                -- Clean technical prefixes (e.g. FirearmPrimaryM110 -> M110)
                weaponName = rawName:gsub("^FirearmPrimary", ""):gsub("^FirearmSecondary", ""):gsub("^Firearm", ""):gsub("^Melee", ""):gsub("^Throwable", ""):gsub("^Tool", ""):gsub("^Item", "")
                if weaponName == "" then weaponName = rawName end
            end
        end

        if weaponName and weaponName ~= "None" and weaponName ~= "Unknown" then
            local dynamicScale = cachedCfg.DynamicTextScaling and math_clamp(boxHeight * 0.016, 0.5, 1.0) or 1.0
            local weaponSize = 12 * cachedCfg.TextScale * dynamicScale

            -- Position below name or above box
            local weaponY = bpY - (weaponSize + 3)
            if cachedCfg.HealthBarSide == "Top" then
                weaponY = weaponY - 8
            end
            if cachedCfg.ShowNames then
                weaponY = weaponY - (13 * cachedCfg.TextScale * dynamicScale)
            end

            drawings.Weapon.Text = weaponName
            drawings.Weapon.Position = Vector2_new(screenX, weaponY)
            drawings.Weapon.Color = Config.WeaponColor or Color3_new(1, 1, 1)
            drawings.Weapon.Size = weaponSize
            drawings.Weapon.Visible = true
            weaponShown = true
        end
    end
    if not weaponShown then
        drawings.Weapon.Visible = false
    end

    -- Distance (Meters)
    if cachedCfg.ShowDistance then
        local dynamicScale = cachedCfg.DynamicTextScaling and math_clamp(boxHeight * 0.016, 0.5, 1.0) or 1.0
        local distSize = 12 * cachedCfg.TextScale * dynamicScale

        -- P18: Prevent string allocation spam
        local distInt = math_floor(distance * 0.28)
        if espData._lastDist ~= distInt then
            espData._lastDist = distInt
            drawings.Distance.Text = "[" .. tostring(distInt) .. "m]"
        end

        drawings.Distance.Size = distSize

        -- Adjust position based on Health Bar if at Bottom
        local distY = bpY + boxHeight + 2
        if cachedCfg.HealthBarSide == "Bottom" then
            distY = distY + 6 -- Make room for bar
        end

        drawings.Distance.Position = Vector2_new(screenX, distY)
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
            barPos = Vector2_new(bpX, bpY + boxHeight + 2)
            outlineSize = Vector2_new(boxWidth + 2, 6)
            outlinePos = Vector2_new(bpX - 1, bpY + boxHeight + 1)
        elseif hbSide == "Right" then
            local barH = boxHeight * healthPercent
            barSize = Vector2_new(2, barH)
            barPos = Vector2_new(bpX + boxWidth + 3, bpY + (boxHeight - barH))
            outlineSize = Vector2_new(4, boxHeight + 2)
            outlinePos = Vector2_new(bpX + boxWidth + 2, bpY - 1)
        elseif hbSide == "Top" then
            local barW = boxWidth * healthPercent
            barSize = Vector2_new(barW, 4)
            barPos = Vector2_new(bpX, bpY - 6)
            outlineSize = Vector2_new(boxWidth + 2, 6)
            outlinePos = Vector2_new(bpX - 1, bpY - 7)
        else
            local barH = boxHeight * healthPercent
            barSize = Vector2_new(2, barH)
            barPos = Vector2_new(bpX - 5, bpY + (boxHeight - barH))
            outlineSize = Vector2_new(4, boxHeight + 2)
            outlinePos = Vector2_new(bpX - 6, bpY - 1)
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
        -- OPT: viewportX/Y cached per-frame in _genv (avoid Camera.ViewportSize per-actor)
        local vx = _genv._cachedViewportX or Camera.ViewportSize.X
        local vy = _genv._cachedViewportY or Camera.ViewportSize.Y
        drawings.Tracer.From = Vector2_new(vx * 0.5, vy)
        drawings.Tracer.To = Vector2_new(screenX, bpY + boxHeight)
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
    local dist = math.sqrt(dv.X * dv.X + dv.Y * dv.Y + dv.Z * dv.Z) -- Faster than .Magnitude

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
    local boxSize = Vector2.new(1000 / dist * width, 1000 / dist * height) * (Config.BoxScale or 1.0)
    local boxPos = Vector2.new(screenPos.X - boxSize.X / 2, screenPos.Y - boxSize.Y / 2)
    local boxHeight = boxSize.Y
    local boxWidth = boxSize.X

    local drawings = espData.Drawing
    local boxColor = Config.VehicleColor or Color3.new(0, 1, 1)

    -- BOX
    if Config.ShowVehicleBox then
        -- Update Outline First (Background) - Size offset to prevent occlusion
        drawings.BoxOutline.Color = Color3.new(0, 0, 0)
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
                c[3].From = Vector2.new(boxPos.X + boxWidth, boxPos.Y); c[3].To = Vector2.new(
                    boxPos.X + boxWidth - cornerLength, boxPos.Y)
                c[4].From = Vector2.new(boxPos.X + boxWidth, boxPos.Y); c[4].To = Vector2.new(boxPos.X + boxWidth,
                    boxPos.Y + cornerLength)
                -- BL
                c[5].From = Vector2.new(boxPos.X, boxPos.Y + boxHeight); c[5].To = Vector2.new(boxPos.X + cornerLength,
                    boxPos.Y + boxHeight)
                c[6].From = Vector2.new(boxPos.X, boxPos.Y + boxHeight); c[6].To = Vector2.new(boxPos.X,
                    boxPos.Y + boxHeight - cornerLength)
                -- BR
                c[7].From = Vector2.new(boxPos.X + boxWidth, boxPos.Y + boxHeight); c[7].To = Vector2.new(
                    boxPos.X + boxWidth - cornerLength, boxPos.Y + boxHeight)
                c[8].From = Vector2.new(boxPos.X + boxWidth, boxPos.Y + boxHeight); c[8].To = Vector2.new(
                    boxPos.X + boxWidth, boxPos.Y + boxHeight - cornerLength)

                for _, l in ipairs(c) do
                    l.Color = boxColor
                    l.Transparency = 1
                    l.Thickness = 1
                    l.ZIndex = 5
                    l.Visible = true
                end
            end
        else
            if drawings.Corners then for _, l in pairs(drawings.Corners) do l.Visible = false end end

            drawings.BoxOutline.Visible = true
            drawings.Box.Visible = true
        end
    else
        drawings.Box.Visible = false
        drawings.BoxOutline.Visible = false
        if drawings.Corners then for _, l in pairs(drawings.Corners) do l.Visible = false end end
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

        -- P20: Prevent vehicle string allocation spam
        local meters = math.floor(dist * 0.28) -- Convert studs to meters approx
        if espData._lastDist ~= meters then
            espData._lastDist = meters
            drawings.Distance.Text = "[" .. tostring(meters) .. "m]"
        end

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
            if type(v) == "number" then
                currentHp = currentHp + v; maxHp = maxHp + 100
            end
        end
        if maxHp == 0 then maxHp = 100 end
        local hpPercent = math.clamp(currentHp / maxHp, 0, 1)

        local barColor = Config.VehicleHealthColor or Color3.new(0, 1, 0)
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
        drawings.HealthBarOutline.Color = Color3.new(0, 0, 0)
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
                if espData.Highlight then pcall(function() espData.Highlight.Enabled = false end) end
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
    -- P8: Pre-determine type once at hook creation (not per-call)
    local oldIndexIsFunc = type(oldIndex) == "function"
    local oldIndexIsTable = type(oldIndex) == "table"

    mt.__index = newcclosure(function(self, key)
        -- P8: Only check Size spoof when hitbox expander is active
        if key == "Size" and OriginalSizes[self] then
            return OriginalSizes[self]
        end

        -- P8: Direct call without pcall (massive perf gain — fires thousands of times/frame)
        if oldIndexIsFunc then
            return oldIndex(self, key)
        elseif oldIndexIsTable then
            return oldIndex[key]
        end
        return nil
    end)
    setreadonly(mt, true)
end)

-- CRASH MITIGATION V3: Moved into SetupActorHooks() to prevent double-wrapping.
-- (Duplicate hook removed — SetupActorHooks already wraps ActorClass.Update in pcall)

-- OPTIMIZATION: Module-level cached config (avoid per-frame table allocation)
local _cachedCfg, _cachedCfgFrame = {}, -30
-- Merged with _cachedCfg above to reduce local count

local function RefreshCachedCfg()
    _cachedCfg.MaxDistance = Config.MaxDistance or 1000
    _cachedCfg.UseBoxESP = (Config.UseBoxESP ~= false) -- default true
    _cachedCfg.BoxStyle = Config.BoxStyle or "Full"
    _cachedCfg.BoxScale = Config.BoxScale or 1
    _cachedCfg.BoxColor = Config.BoxColor
    _cachedCfg.ShowNames = (Config.ShowNames ~= false)       -- default true
    _cachedCfg.ShowDistance = (Config.ShowDistance ~= false) -- default true
    _cachedCfg.ShowHealth = (Config.ShowHealth ~= false)     -- default true
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
    -- P4: Vehicle config cache (avoids per-vehicle Config lookups)
    _cachedCfg.ShowVehicles = Config.ShowVehicles
    _cachedCfg.VehicleColor = Config.VehicleColor or Color3_new(0, 1, 1)
    _cachedCfg.ShowVehicleBox = Config.ShowVehicleBox
    _cachedCfg.ShowVehicleName = Config.ShowVehicleName
    _cachedCfg.ShowVehicleHealth = Config.ShowVehicleHealth
    _cachedCfg.VehicleHealthColor = Config.VehicleHealthColor or Color3_new(0, 1, 0)
    _cachedCfg.VehicleHealthBarSide = Config.VehicleHealthBarSide
    _cachedCfg.VehicleBoxStyle = Config.VehicleBoxStyle
    _cachedCfg.IgnoreLocalVehicle = Config.IgnoreLocalVehicle
    -- OPTIMIZATION: Pre-compute combat active flag (avoids 10 Config lookups per frame)
    _cachedCfg._combatActive = Config.SilentAim or Config.RageMode or Config.ShowWeaponInfo
        or Config.ShowPrediction or Config.ShowFOV
        or Config.NoRecoil or Config.NoSpread or Config.CustomRPM
        or Config.TurretNoRecoil or Config.TurretNoSpread

    -- OPTIMIZATION: Cache Camera values once per frame (avoids per-actor Camera property reads)
    -- Camera.FieldOfView and ViewportSize would otherwise be read once per enemy (~20x per frame)
    local vp = Camera.ViewportSize
    local vpY = vp.Y
    local fov = Camera.FieldOfView
    _cachedCfg._cachedAspectHeight = vpY / (2 * math.tan(fov * 0.00872664625))
    _cachedCfg._cachedViewportX = vp.X
    _cachedCfg._cachedViewportY = vpY
    -- Also store in _genv for tracer access inside UpdateESPForActor
    _genv._cachedViewportX = vp.X
    _genv._cachedViewportY = vpY
end

-- P1: Module-level ESP processor (eliminates per-frame closure allocation)
local function ProcessESPList(list, localSquad, cachedCfg)
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
            -- Throttle Color Updates (every 30 frames)
            if (CurrentFrameId % 30) == 0 then
                espData.Color = GetEntityColor(actor, actor._entityType, localSquad)
            end
            UpdateESPForActor(uid, espData, CurrentFrameId, cachedCfg, localSquad)
        end
    end
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

    -- P1: Process as module-level call (no closure allocation per frame)
    if ActorManager.Initialized then
        ProcessESPList(ActorManager.Enemies, localSquad, cachedCfg)
        ProcessESPList(ActorManager.Teammates, localSquad, cachedCfg)
    end

    -- Cleanup stale ESP elements every 10 frames
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


-- Enable free Features
Compkiller:CustomIconHighlight() -- Auto-colorize ALL icons to match purple theme

-- Loader (Beautification)
-- Loader (Beautification) - Wrapped in pcall
pcall(function()
    if Compkiller.Loader then
        Compkiller:Loader(Compkiller.Logo, 2).yield();
    end
end)

-- Progress Notification (step-by-step loading feedback)
local loadNotify
pcall(function()
    loadNotify = Notifier.new({
        Title = "VoidSens",
        Content = "Initializing...",
        Duration = math.huge,
        Icon = Compkiller.Logo
    })
    loadNotify:SetProgress(0.1, 0.3)
end)
task.wait(0.15)

-- Create Window
local Window
local successWindow, errWindow = pcall(function()
    Window = Compkiller.new({
        Name = "VoidSens | Lubiebf4",
        Keybind = "LeftAlt",
        Logo = Compkiller.Logo,
        Scale = Compkiller.Scale.Window,
        TextSize = 15,
    })
end)

if not successWindow or not Window then
    warn("[BRM5] Błąd tworzenia okna GUI: " .. tostring(errWindow))
    print("[BRM5] Próba kontynuacji bez GUI...")
    return
end

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
    ExpireDate = "free",
    WindowName = "VoidSens",
    Logo = Compkiller.Logo
})

-- Watermark HUD (Top-Right Corner)
local WM = Window:Watermark()
WM:AddText({ Icon = "zap", Text = "VoidSens" })
WM:AddText({ Icon = "user", Text = LocalPlayer.DisplayName })
local wmFPS = WM:AddText({ Icon = "activity", Text = "0 FPS" })
local wmPing = WM:AddText({ Icon = "wifi", Text = "0ms" })

-- Update FPS + Ping in Watermark
-- OPTIMIZATION: FPS watermark without blocking RenderStepped:Wait()
local _wmFrameCount, _wmLastUpdate = 0, 0
-- Merged with _wmFrameCount above to reduce local count
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
-- HOME TAB (Welcome & Info) — free Layout
-- ══════════════════════════════════════════════════════
local HomeTab = Window:DrawTab({ Name = "Home", Icon = "home", Type = "Double" })

-- Helper for dynamic rich text colors
local function GetRGB(color)
    local r = math.floor(color.R * 255)
    local g = math.floor(color.G * 255)
    local b = math.floor(color.B * 255)
    return string.format("rgb(%d,%d,%d)", r, g, b)
end

-- ── LEFT COLUMN: Welcome + Features ──
local S_Welcome = HomeTab:DrawSection({ Name = "Welcome", Position = "left" })

S_Welcome:AddParagraph({
    Title = '<font color="' ..
    GetRGB(Compkiller.Colors.Risky) ..
    '">⚡</font>  VoidSens  <font color="' .. GetRGB(Compkiller.Colors.Toggle) .. '">v2.1</font>',
    Content = 'Welcome, <font color="' .. GetRGB(Compkiller.Colors.Highlight) .. '"><b>' ..
        LocalPlayer.DisplayName ..
        '</b></font>!\nYou are running the <font color="' ..
        GetRGB(Compkiller.Colors.Risky) .. '">free</font> edition.'
})

S_Welcome:AddParagraph({
    Title = '<font color="' .. GetRGB(Compkiller.Colors.Highlight) .. '">♦</font>  Credits',
    Content =
        'Developer: <font color="' ..
        GetRGB(Compkiller.Colors.Highlight) ..
        '">Lubiebf4</font>\nUI Framework: <font color="' ..
        GetRGB(Compkiller.Colors.Highlight) .. '">Compkiller</font> by 4lpaca'
})

local S_Features = HomeTab:DrawSection({ Name = "Features", Position = "left" })

S_Features:AddParagraph({
    Title = '<font color="' .. GetRGB(Compkiller.Colors.Highlight) .. '">🎯</font>  Combat',
    Content =
        '<font color="' ..
        GetRGB(Compkiller.Colors.SwitchColor) ..
        '">Silent Aim  ·  Ragebot  ·  No Recoil\nNo Spread  ·  Custom RPM  ·  Spinbot</font>'
})

S_Features:AddParagraph({
    Title = '<font color="' .. GetRGB(Compkiller.Colors.Highlight) .. '">👁</font>  Visuals',
    Content =
        '<font color="' ..
        GetRGB(Compkiller.Colors.SwitchColor) ..
        '">Box ESP  ·  Corner ESP  ·  Highlight\nHealth Bars  ·  Tracers  ·  Name Tags</font>'
})

S_Features:AddParagraph({
    Title = '<font color="' .. GetRGB(Compkiller.Colors.Highlight) .. '">🚀</font>  Movement',
    Content =
        '<font color="' ..
        GetRGB(Compkiller.Colors.SwitchColor) ..
        '">Vehicle Fly  ·  Speed Hack  ·  Noclip\nHitbox Expander  ·  Vehicle Teleport</font>'
})

-- ── RIGHT COLUMN: Changelog + Server ──
local S_Changelog = HomeTab:DrawSection({ Name = "Changelog", Position = "right" })

S_Changelog:AddParagraph({
    Title = '<font color="' .. GetRGB(Compkiller.Colors.Risky) .. '">★</font>  v3.0 — Security Update',
    Content = '<font color="' .. GetRGB(Compkiller.Colors.Toggle) .. '">+</font> Improved Ragebot Logic\n' ..
        '<font color="' .. GetRGB(Compkiller.Colors.Toggle) .. '">+</font> Added Auto Reload System\n' ..
        '<font color="' .. GetRGB(Compkiller.Colors.Toggle) .. '">+</font> Added Queue on Teleport\n' ..
        '<font color="' .. GetRGB(Compkiller.Colors.Toggle) .. '">+</font> Optimized Loading Speed\n' ..
        '<font color="' .. GetRGB(Compkiller.Colors.Toggle) .. '">+</font> Enhanced Security\n' ..
        '<font color="' .. GetRGB(Compkiller.Colors.Toggle) .. '">+</font> Menu Execute Handler\n' ..
        '<font color="' .. GetRGB(Compkiller.Colors.Toggle) .. '">+</font> Added Free User Detection (Kick)'
})
-- Keeping green for additions as it makes sense contextually

local S_Server = HomeTab:DrawSection({ Name = "Info", Position = "right" })

-- Dynamic Keybinds Paragraph (updates when keybinds change)
local KeybindsInfo = S_Server:AddParagraph({
    Title = '<font color="' .. GetRGB(Compkiller.Colors.Highlight) .. '">⌨</font>  Keybinds',
    Content =
        '<font color="' ..
        GetRGB(Compkiller.Colors.Risky) ..
        '">LeftAlt</font> — Toggle Menu\n<font color="' ..
        GetRGB(Compkiller.Colors.Risky) ..
        '">V</font> — Character Fly\n<font color="' .. GetRGB(Compkiller.Colors.Risky) .. '">X</font> — Vehicle Fly'
})

-- Global update function for keybinds display
getgenv()._KeybindDisplayKeys = { Menu = "LeftAlt", CharFly = "V", VehFly = "X" }
getgenv()._UpdateKeybindDisplay = function()
    pcall(function()
        local k = getgenv()._KeybindDisplayKeys
        local text = '<font color="' ..
            GetRGB(Compkiller.Colors.Risky) .. '">' .. tostring(k.Menu) .. '</font> — Toggle Menu'
            .. '\n<font color="' ..
            GetRGB(Compkiller.Colors.Risky) .. '">' .. tostring(k.CharFly) .. '</font> — Character Fly'
            .. '\n<font color="' ..
            GetRGB(Compkiller.Colors.Risky) .. '">' .. tostring(k.VehFly) .. '</font> — Vehicle Fly'
        if KeybindsInfo and KeybindsInfo.SetContent then
            KeybindsInfo:SetContent(text)
        end
    end)
end

S_Server:AddParagraph({
    Title = '<font color="' .. GetRGB(Compkiller.Colors.Highlight) .. '">💡</font>  Tip',
    Content = '<font color="' ..
    GetRGB(Compkiller.Colors.SwitchColor) .. '">Right-click any toggle to assign\na custom keybind to it.</font>'
})

S_Server:AddParagraph({
    Title = '<font color="' .. GetRGB(Compkiller.Colors.Highlight) .. '">🌐</font>  Server',
    Content = 'Place: <font color="' .. GetRGB(Compkiller.Colors.Risky) .. '">' ..
        tostring(game.PlaceId) ..
        '</font>\nJob: <font color="' ..
        GetRGB(Compkiller.Colors.Toggle) .. '">' .. string.sub(tostring(game.JobId), 1, 12) .. '...</font>'
})

S_Server:AddButton({
    Name = "📋  Copy Server Link",
    Callback = function()
        pcall(function()
            setclipboard("roblox://experiences/start?placeId=" ..
                tostring(game.PlaceId) .. "&gameInstanceId=" .. tostring(game.JobId))
        end)
        if Notifier and Notifier.new then
            Notifier.new({
                Title = "Copied!",
                Content = "Server join link copied to clipboard.",
                Duration = 3,
                Icon =
                "rbxassetid://120245531583106"
            })
        end
    end
})

pcall(function() loadNotify:Content("Building Combat tab...") end)
pcall(function() loadNotify:SetProgress(0.3, 0.3) end)
task.wait(0.1)

-- Combat Tab
local CombatTab = Window:DrawTab({ Name = "Combat", Icon = "swords", Type = "Double" })

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

-- Hitbox Expander
S_SilentAim:AddToggle({
    Name = "Hitbox Expander",
    Flag = "Comb_HitboxExpander",
    Default = false,
    Callback = function(v)
        Config.HitboxExpander = v
        if not v then
            -- Reset hitboxes when disabled
            if getgenv().ResetAllHitboxes then
                getgenv().ResetAllHitboxes()
            end
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

-- Initialize Config defaults for ESP (Compkiller UI may not fire callbacks for Default values)
if Config.UseBoxESP == nil then Config.UseBoxESP = true end
if Config.ShowNames == nil then Config.ShowNames = true end
if Config.ShowDistance == nil then Config.ShowDistance = true end
if Config.ShowHealth == nil then Config.ShowHealth = true end
if Config.UseTracers == nil then Config.UseTracers = false end
if Config.UseHighlight == nil then Config.UseHighlight = false end
if Config.SimpleESP == nil then Config.SimpleESP = false end
if Config.BoxStyle == nil then Config.BoxStyle = "Full" end
if Config.BoxScale == nil then Config.BoxScale = 1 end
if Config.MaxDistance == nil then Config.MaxDistance = 1000 end
if Config.TextScale == nil then Config.TextScale = 1.2 end
if Config.HealthBarSide == nil then Config.HealthBarSide = "Left" end
if Config.UseHealthGradient == nil then Config.UseHealthGradient = true end

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
    Name = "Show Weapon",
    Flag = "ESP_ShowWeapon",
    Default = false,
    Callback = function(v)
        Config.ShowWeapon = v
    end
})

S_ESP:AddColorPicker({
    Name = "Weapon Color",
    Flag = "ESP_WeaponColor",
    Default = Color3.fromRGB(255, 255, 255),
    Callback = function(v)
        Config.WeaponColor = v
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
        -- Use engine's built-in FLIR system discovered in ActorClass analysis
        if EnvironmentService then
            EnvironmentService.FLIR = v
        end
    end
})

local NVGColorCorrection = nil

local NVGColors = {
    ["Green"] = Color3.fromRGB(112, 245, 65), -- Green Phosphor (original)
    ["Blue"] = Color3.fromRGB(165, 233, 255)  -- White Phosphor (blue-ish)
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
    Values = { "Green", "Blue" },
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
    Values = { "Full", "Corner" },
    Default = "Full",
    Flag = "ESP_BoxStyle",
    Callback = function(v)
        Config.BoxStyle = v
    end
})


S_Layout:AddDropdown({
    Name = "Health Bar Position",
    Values = { "Left", "Right", "Top", "Bottom" },
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
    Values = { "Full", "Corner" },
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
    Values = { "Left", "Right", "Bottom" },
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

local NotifiedUsers = {}
-- System Tab (Settings & Appearance)
local SystemTab = Window:DrawTab({ Name = "System", Icon = "settings", Type = "Double" })
local S_Appearance = SystemTab:DrawSection({ Name = "Appearance", Position = "left" })
local S_Settings = SystemTab:DrawSection({ Name = "Settings", Position = "right" })

S_Settings:AddButton({
    Name = "Force Rescan (Fix)",
    Callback = function()
        Notifier.new({ Title = "System", Content = "Force rescanning services...", Duration = 3 })

        -- Clear Cache
        gcCache = nil
        ReplicatorService = nil
        BulletService = nil
        CharacterController = nil

        -- Force Scan
        local found = BulkScan(true) -- retry=true forces scan

        if found and found.ReplicatorService then
            Notifier.new({ Title = "System", Content = "Rescan Complete! Services updated.", Duration = 3 })
            RefreshFirearmControllers(true)
            SetupHooks()
        else
            Notifier.new({ Title = "System", Content = "Rescan Failed! Try spawning first.", Duration = 3 })
        end
    end
})

-- Appearance
S_Appearance:AddDropdown({
    Name = "Theme Preset",
    Flag = "ThemePreset",
    Default = "Default",
    Values = { "Purple free", "Default", "Dark Green", "Dark Blue", "Purple Rose", "Skeet" },
    Callback = function(v)
        Compkiller:SetTheme(v)
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
        pcall(function() Window:Unload() end)  -- If Window has Unload
        -- Manual Cleanup
        pcall(function() RunService:UnbindFromRenderStep("BRM5_free_ESP") end)
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
    Content = "BRM5 | free Edition"
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
-- espPriority inlined below to save 1 local register

RunService:BindToRenderStep("BRM5_free_ESP", Enum.RenderPriority.Camera.Value + 1, function(deltaTime)
    -- Calculate dynamic FPS to sync loop intervals (e.g. Memory Cleanup) with game's actual framerate
    deltaTime = deltaTime or 0.016
    local currentFps = math.clamp(math.floor(1 / deltaTime), 30, 9999)
    frameCount = (frameCount + 1) % currentFps

    -- GLOBAL CACHE AT START OF FRAME
    local now = tick()
    local camCF = Camera.CFrame
    _genv.LastTime = now
    _genv.LastCamCF = camCF

    -- OPTIMIZED: Spread work across frames
    if ActorManager then
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
            -- VelTrackCache cleanup (prevent memory leak from dead actors)
            for uid, entry in pairs(VelTrackCache) do
                if now - entry.time > 10 then
                    VelTrackCache[uid] = nil
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
    if _cachedCfg._combatActive then
        UpdateCombat(frameCount)
    end
end)

-- Close progress notification
pcall(function() loadNotify:SetProgress(1, 0.2) end)
task.wait(0.3)
pcall(function() loadNotify:Close() end)

-- Success notification
Notifier.new({
    Title = "BRM5 PREM",
    Content = "Welcome, " .. LocalPlayer.DisplayName .. "! Script loaded.",
    Duration = 4,
    Icon = Compkiller.Logo
});

task.delay(4.5, function()
    Notifier.new({
        Title = "Tip",
        Content = "Press LeftAlt to toggle. Hover (?) for info.",
        Duration = 5,
        Icon = Compkiller.Logo
    })
end)

-- Initial Map Detection
if Config.AutoDetectMap then
    Config.CurrentMapType = DetectMapType()
end
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

UserInputService.InputBegan:Connect(function(input, gameProcessed)
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
