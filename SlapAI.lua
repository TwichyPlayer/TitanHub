--!strict
--[[
    PROJECT: SLAP_AI_CORE [Tryhard Edition]
    ARCH: NEURAL CONTEXT STEERING + NEX INTEGRATION
    STATUS: UNDETECTED // EXECUTOR TIER
    AUTHOR: AGENT
]]

local SlapAI = {}
SlapAI.__index = SlapAI

-- // [0] SECURITY PROTOCOLS (NEXER1234 BYPASS) //
do
    local function Secure()
        local cloneref = cloneref or function(o) return o end
        local game = game
        local RS = cloneref(game:GetService("ReplicatedStorage"))
        local ScriptContext = cloneref(game:GetService("ScriptContext"))
        
        -- Silent Block Function
        local function Nuke(inst)
            pcall(function() 
                inst.Name = "SECURITY_NULL_" .. math.random(1,99999) 
                inst.Parent = nil 
            end)
        end

        -- Remote Interception
        if hookmetamethod then
            local old
            old = hookmetamethod(game, "__namecall", function(self, ...)
                local method = getnamecallmethod()
                if method == "FireServer" then
                    local n = tostring(self)
                    if n == "Ban" or n == "WalkSpeedChanged" or n == "AdminGUI" or n == "GRAB" or n == "WS" or n == "WS2" or n == "SpecialGloveAccess" then
                        return nil
                    end
                end
                return old(self, ...)
            end)
        end

        -- Instance Cleanup
        local bad = {"Ban", "WalkSpeedChanged", "AdminGUI", "GRAB", "SpecialGloveAccess", "WS", "WS2"}
        for _, v in pairs(bad) do
            if RS:FindFirstChild(v) then Nuke(RS[v]) end
            if RS:FindFirstChild("Events") and RS.Events:FindFirstChild(v) then Nuke(RS.Events[v]) end
        end
        
        -- Client Anti-Cheat Nuke
        local StarterPlayer = game:GetService("StarterPlayer")
        if StarterPlayer:FindFirstChild("StarterPlayerScripts") then
            local CAC = StarterPlayer.StarterPlayerScripts:FindFirstChild("ClientAnticheat")
            if CAC then Nuke(CAC) end
        end
    end
    Secure()
end

-- // [1] SERVICE BUS //
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local VirtualUser = game:GetService("VirtualUser")
local Workspace = game:GetService("Workspace")
local Camera = Workspace.CurrentCamera

local LOCAL_PLAYER = Players.LocalPlayer
local CHARACTER = LOCAL_PLAYER.Character or LOCAL_PLAYER.CharacterAdded:Wait()
local ROOT = CHARACTER:WaitForChild("HumanoidRootPart")
local HUMANOID = CHARACTER:WaitForChild("Humanoid")

LOCAL_PLAYER.CharacterAdded:Connect(function(n)
    CHARACTER = n
    ROOT = n:WaitForChild("HumanoidRootPart")
    HUMANOID = n:WaitForChild("Humanoid")
end)

-- // [2] DEPENDENCY INJECTION //
local Dependencies = { NEX = nil, PathAI = nil }

-- NEX Loader
task.spawn(function()
    repeat 
        local s, r = pcall(function()
            return loadstring(game:HttpGet('https://raw.githubusercontent.com/Pro666Pro/OpenSourceScripts/refs/heads/main/Modules/SlapBattlesModuleScript.lua'))()
        end)
        if s and r then Dependencies.NEX = r; Dependencies.NEX:SetDB(false) end
        if not Dependencies.NEX then task.wait(0.5) end
    until Dependencies.NEX
end)

-- TitanHub Pathfinding Loader
task.spawn(function()
    repeat
        local s, r = pcall(function()
            return loadstring(game:HttpGet('https://raw.githubusercontent.com/TwichyPlayer/TitanHub/main/pathfindingsystem.lua'))()
        end)
        if s and r then Dependencies.PathAI = r end
        if not Dependencies.PathAI then task.wait(0.5) end
    until Dependencies.PathAI
end)

local t_start = tick()
repeat task.wait() until (Dependencies.NEX and Dependencies.PathAI) or (tick() - t_start > 10)
local NEX = Dependencies.NEX
local PathAI = Dependencies.PathAI

-- // [3] ADVANCED CONFIGURATION MATRIX //
local CONFIG = {
    Movement = {
        Smoothness = 0.18,      -- Lower = Snappier, Higher = Smoother (0.0 - 1.0)
        RotationSpeed = 0.25,   -- Slerp factor for rotation
        OrbitDistance = 14,     -- Sweet spot for engagement
        VoidBuffer = 12,        -- Studs to avoid edge
        WallBuffer = 4,         -- Studs to avoid walls
        StrafeWidth = 6,        -- Sine wave amplitude
        StrafeFreq = 3,         -- Sine wave speed
    },
    Combat = {
        Reach = 15.5,           -- Max slap distance
        FlickAngle = 85,        -- Degrees to snap
        Prediction = 0.145,     -- Ping compensation (seconds)
        JumpReadHeight = 3,     -- Height diff to trigger jump read
        VerticalTolerance = 12, -- Ignore targets above/below this Y diff
    },
    Dodge = {
        Enabled = true,
        Sensitivity = 16,       -- Distance to start calculating dodge
        ReactionTime = 0.2,     -- Artificial delay for humanization
        Cooldown = 0.8,
    }
}

-- // [4] STATE MACHINE //
local State = {
    Active = false,
    Mode = "Idle", -- "Target", "Run", "Pathing"
    Target = nil :: Player?,
    TargetCriteria = "nearest",
    TargetParams = "",
    
    -- Physics State
    MoveDir = Vector3.zero,
    OrbitAngle = 0,
    StrafePhase = 0,
    StuckTimer = 0,
    LastPos = Vector3.zero,
    
    -- Combat State
    LastSlap = 0,
    LastDodge = 0,
    IsFlicking = false,
    
    -- Navigation
    EvadePoint = Vector3.zero,
    NearVoid = false,
}

-- // [5] UTILITY KERNEL //
local function GetRoot(p) return p.Character and p.Character:FindFirstChild("HumanoidRootPart") end
local function IsAlive(p) 
    local c = p.Character
    return c and c:FindFirstChild("Humanoid") and c.Humanoid.Health > 0 and c:FindFirstChild("HumanoidRootPart")
end

local function GetGlove(p)
    if not p then return "Default" end
    local ls = p:FindFirstChild("leaderstats")
    if ls and ls:FindFirstChild("Glove") then return tostring(ls.Glove.Value) end
    return "Default"
end

-- // [6] CONTEXT STEERING ENGINE (TITAN PORT) //
local RayParams = RaycastParams.new()
RayParams.FilterType = Enum.RaycastFilterType.Exclude

local function GetSmartDirection(TargetPos: Vector3): Vector3
    local MyPos = ROOT.Position
    local DesiredDir = (TargetPos - MyPos).Unit
    
    RayParams.FilterDescendantsInstances = {CHARACTER}
    
    local BestDir = Vector3.zero
    local BestScore = -math.huge
    
    -- Cast 32 Rays for High-Res Environmental Awareness
    for i = 0, 31 do
        local Angle = math.rad(i * (360/32))
        local Dir = Vector3.new(math.cos(Angle), 0, math.sin(Angle))
        
        -- [SCORING]
        -- 1. Alignment with Goal
        local Alignment = Dir:Dot(DesiredDir)
        local Score = Alignment * 2
        
        -- 2. Void Detection (Critical)
        local LookAhead = MyPos + (Dir * CONFIG.Movement.VoidBuffer)
        local VoidRay = Workspace:Raycast(LookAhead + Vector3.new(0, 5, 0), Vector3.new(0, -20, 0), RayParams)
        
        if not VoidRay then
            Score = Score - 15 -- Massive penalty for void
        end
        
        -- 3. Obstacle Avoidance
        local WallRay = Workspace:Raycast(MyPos, Dir * CONFIG.Movement.WallBuffer, RayParams)
        if WallRay then
            Score = Score - 8
        end
        
        -- 4. Dynamic Dodge (If targeted)
        if State.Target and State.Mode == "Target" then
            local Dist = (State.Target.Character.HumanoidRootPart.Position - MyPos).Magnitude
            if Dist < 8 then
                -- Backwards bias if too close
                local BackDir = (MyPos - State.Target.Character.HumanoidRootPart.Position).Unit
                Score = Score + (Dir:Dot(BackDir) * 3)
            end
        end

        if Score > BestScore then
            BestScore = Score
            BestDir = Dir
        end
    end
    
    return BestDir
end

-- // [7] COMBAT LOGIC //

local function PredictPos(T: Player): Vector3
    local TRoot = GetRoot(T)
    if not TRoot then return Vector3.zero end
    
    local Vel = TRoot.Velocity
    local Pos = TRoot.Position
    
    -- Jump Reading logic
    if math.abs(Vel.Y) > 5 then
         -- Airborne: Trajectory is predictable
         return Pos + (Vector3.new(Vel.X, 0, Vel.Z) * CONFIG.Combat.Prediction)
    else
         -- Ground: Standard linear prediction
         return Pos + (Vel * (CONFIG.Combat.Prediction * 0.5))
    end
end

local function PerformFlick(TargetRoot: BasePart)
    if State.IsFlicking then return end
    State.IsFlicking = true
    
    local LookCF = CFrame.new(ROOT.Position, Vector3.new(TargetRoot.Position.X, ROOT.Position.Y, TargetRoot.Position.Z))
    local FlickCF = LookCF * CFrame.Angles(0, math.rad(CONFIG.Combat.FlickAngle), 0)
    
    -- Snap
    ROOT.CFrame = FlickCF
    
    -- Slap (NEX Integration)
    task.spawn(function()
        NEX:Slap({[1] = TargetRoot})
        VirtualUser:Button1Down(Vector2.new(0,0), Camera.CFrame)
    end)
    
    -- Restore
    task.delay(0.06, function()
        if ROOT then
            ROOT.CFrame = LookCF
            VirtualUser:Button1Up(Vector2.new(0,0), Camera.CFrame)
        end
        State.IsFlicking = false
    end)
end

local function CheckDodge(TRoot: BasePart)
    local Dist = (TRoot.Position - ROOT.Position).Magnitude
    if Dist < CONFIG.Dodge.Sensitivity and (tick() - State.LastDodge > CONFIG.Dodge.Cooldown) then
        local TLook = TRoot.CFrame.LookVector
        local ToMe = (ROOT.Position - TRoot.Position).Unit
        
        -- Dot product > 0.7 means they are looking directly at us
        if TLook:Dot(ToMe) > 0.7 then
            -- Trigger Dodge
            HUMANOID.Jump = true
            -- Force strafe vector
            local Right = ToMe:Cross(Vector3.new(0,1,0))
            State.MoveDir = (Right * (math.random() > 0.5 and 1 or -1)) * 2
            State.LastDodge = tick()
        end
    end
end

-- // [8] TARGET SELECTION //
local function UpdateTarget()
    local Best = nil
    local BestScore = (State.TargetCriteria == "nearest") and math.huge or -math.huge
    local MyPos = ROOT.Position
    
    for _, v in ipairs(Players:GetPlayers()) do
        if v ~= LOCAL_PLAYER and IsAlive(v) then
            local TRoot = GetRoot(v)
            local Dist = (MyPos - TRoot.Position).Magnitude
            local YDiff = math.abs(MyPos.Y - TRoot.Position.Y)
            
            -- Filter: Vertical Exclusion Zone (Anti-Fly/Tower)
            if YDiff <= CONFIG.Combat.VerticalTolerance then
                local Valid = false
                
                if State.TargetCriteria == "nearest" then
                    if Dist < BestScore then BestScore = Dist; Valid = true end
                elseif State.TargetCriteria == "farthest" then
                    if Dist > BestScore then BestScore = Dist; Valid = true end
                elseif State.TargetCriteria == "glove" then
                    if GetGlove(v) == State.TargetParams then Valid = true end
                elseif State.TargetCriteria == "name" then
                    if string.find(v.Name:lower(), State.TargetParams:lower()) then Valid = true end
                else -- Random
                     if math.random() > 0.5 then Valid = true end
                end
                
                if Valid then Best = v end
                if Valid and (State.TargetCriteria == "glove" or State.TargetCriteria == "name") then break end
            end
        end
    end
    State.Target = Best
end

-- // [9] MAIN HEARTBEAT LOOP //
local function Loop(DT: number)
    if not State.Active or not IsAlive(LOCAL_PLAYER) then return end
    
    -- Stuck Check
    if (tick() - State.StuckTimer > 0.5) then
        if (ROOT.Position - State.LastPos).Magnitude < 0.5 and State.Mode ~= "Idle" then
            HUMANOID.Jump = true -- Bunnyhop out of stuck state
        end
        State.LastPos = ROOT.Position
        State.StuckTimer = tick()
    end

    -- [MODE: TARGET]
    if State.Mode == "Target" then
        if not State.Target or not IsAlive(State.Target) then
            UpdateTarget()
        else
            local TRoot = GetRoot(State.Target)
            if TRoot then
                local Predicted = PredictPos(State.Target)
                local Dist = (ROOT.Position - Predicted).Magnitude
                
                -- DESTINATION CALCULATION
                local Dest = Predicted
                
                -- Orbit/Strafe Logic
                if Dist < CONFIG.Movement.OrbitDistance + 5 then
                    State.OrbitAngle = State.OrbitAngle + (DT * 2) -- Orbit speed
                    State.StrafePhase = State.StrafePhase + (DT * CONFIG.Movement.StrafeFreq)
                    
                    local SineOffset = math.sin(State.StrafePhase) * CONFIG.Movement.StrafeWidth
                    local X = math.cos(State.OrbitAngle) * (CONFIG.Movement.OrbitDistance + SineOffset)
                    local Z = math.sin(State.OrbitAngle) * (CONFIG.Movement.OrbitDistance + SineOffset)
                    
                    Dest = Predicted + Vector3.new(X, 0, Z)
                end
                
                -- Micro-Spacing (In-Out)
                if Dist < CONFIG.Combat.Reach - 2 then
                    -- Too close, back up
                    Dest = ROOT.Position + (ROOT.Position - Predicted).Unit * 10
                end
                
                -- Context Steering Application
                local SmartDir = GetSmartDirection(Dest)
                
                -- SMOOTHING (LERP)
                State.MoveDir = State.MoveDir:Lerp(SmartDir, CONFIG.Movement.Smoothness)
                HUMANOID:Move(State.MoveDir)
                
                -- ROTATION SMOOTHING
                if not State.IsFlicking then
                    local LookPos = Vector3.new(Predicted.X, ROOT.Position.Y, Predicted.Z)
                    local TargetCF = CFrame.new(ROOT.Position, LookPos)
                    ROOT.CFrame = ROOT.CFrame:Lerp(TargetCF, CONFIG.Movement.RotationSpeed)
                end
                
                -- COMBAT TRIGGERS
                if Dist <= CONFIG.Combat.Reach and (tick() - State.LastSlap > 0.35) then
                    PerformFlick(TRoot)
                    State.LastSlap = tick()
                end
                
                -- DODGE TRIGGER
                CheckDodge(TRoot)
                
            else
                UpdateTarget() -- Lost target root
            end
        end
        
    -- [MODE: RUN]
    elseif State.Mode == "Run" then
        local FleeVec = Vector3.zero
        
        -- Inverse Square Law Repulsion
        for _, v in ipairs(Players:GetPlayers()) do
            if v ~= LOCAL_PLAYER and IsAlive(v) then
                local TRoot = GetRoot(v)
                local Diff = (ROOT.Position - TRoot.Position)
                local D = Diff.Magnitude
                if D < 30 then
                    FleeVec = FleeVec + (Diff.Unit * (100 / D))
                end
            end
        end
        
        local Dest = (FleeVec.Magnitude > 0) and (ROOT.Position + FleeVec) or State.EvadePoint
        local SmartDir = GetSmartDirection(Dest)
        
        State.MoveDir = State.MoveDir:Lerp(SmartDir, CONFIG.Movement.Smoothness)
        HUMANOID:Move(State.MoveDir)
        
        if FleeVec.Magnitude > 0 then
            local Look = ROOT.Position + State.MoveDir
            ROOT.CFrame = ROOT.CFrame:Lerp(CFrame.new(ROOT.Position, Vector3.new(Look.X, ROOT.Position.Y, Look.Z)), 0.2)
        end
    
    -- [MODE: PATHING]
    elseif State.Mode == "Pathing" then
        -- PathAI handles logic, but we check if we need to abort for combat
        UpdateTarget()
        if State.Target and (GetRoot(State.Target).Position - ROOT.Position).Magnitude < 30 then
            -- Enemy nearby, switch to combat
            if PathAI then PathAI.Stop() end
            State.Mode = "Target"
        end
    end
end

local Connection: RBXScriptConnection? = nil

-- // [10] PUBLIC API //

function SlapAI.target(Params: any?)
    if not State.Active then
        State.Active = true
        Connection = RunService.Heartbeat:Connect(Loop)
    end
    
    if State.Mode == "Pathing" and PathAI then PathAI.Stop() end
    State.Mode = "Target"
    
    if type(Params) == "string" then
        local lower = Params:lower()
        if table.find({"nearest", "farthest", "random"}, lower) then
            State.TargetCriteria = lower
        else
            if Params:find("Glove:") then
                State.TargetCriteria = "glove"
                State.TargetParams = Params:split(":")[2]
            else
                State.TargetCriteria = "name"
                State.TargetParams = Params
            end
        end
    else
        State.TargetCriteria = "nearest"
    end
end

function SlapAI.run(X: number?, Y: number?, Z: number?)
    if not State.Active then
        State.Active = true
        Connection = RunService.Heartbeat:Connect(Loop)
    end
    if State.Mode == "Pathing" and PathAI then PathAI.Stop() end
    
    State.Mode = "Run"
    if X then State.EvadePoint = Vector3.new(X,Y,Z) else State.EvadePoint = Vector3.new(0,100,0) end
end

function SlapAI.AdvancedPathfinding(Dest: Vector3)
    if not PathAI then warn("PathAI Missing") return end
    SlapAI.stop() -- Stop local loop
    State.Active = true
    State.Mode = "Pathing"
    
    -- Hybrid System: Use PathAI for long distance
    PathAI.MoveTo(Dest)
    
    -- Monitor for completion or interrupt
    Connection = RunService.Heartbeat:Connect(Loop) -- Reconnect loop for monitoring threats
end

function SlapAI.stop()
    State.Active = false
    State.Mode = "Idle"
    if Connection then Connection:Disconnect(); Connection = nil end
    if PathAI then PathAI.Stop() end
    HUMANOID:Move(Vector3.zero)
end

function SlapAI.reset()
    NEX:Reset(false, 0)
    SlapAI.stop()
end

return SlapAI