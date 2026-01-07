--!strict
--[[
    PROJECT: TRYHARD_CORE [AI AGENT v3.0]
    GAME: SLAP BATTLES
    TYPE: MASTER CONTROLLER (EXECUTOR)
    DEPENDENCIES: NEX (Internal), TitanHub/PathAI (External)
    
    [SYSTEM STATUS]
    - NEX: LINKED
    - PATH_AI: LINKED
    - COGNITION: AGGRESSIVE
]]

-- // 1. BOOTSTRAPPER & DEPENDENCY INJECTION //
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")
local VirtualUser = game:GetService("VirtualUser")

local Dependencies = {
    NEX = nil,
    PathAI = nil
}

-- [LOADER: NEX LIBRARY]
task.spawn(function()
    repeat 
        local Success, Result = pcall(function()
            return loadstring(game:HttpGet('https://raw.githubusercontent.com/Pro666Pro/OpenSourceScripts/refs/heads/main/Modules/SlapBattlesModuleScript.lua'))()
        end)
        if Success and Result then 
            Dependencies.NEX = Result
            -- Initialize NEX settings
            Dependencies.NEX:SetDB(false) -- Enable Anti-Void (Fall forever)
        else
            task.wait(0.5)
        end
    until Dependencies.NEX
end)

-- [LOADER: PATHFINDING SYSTEM (TitanHub)]
task.spawn(function()
    repeat
        local Success, Result = pcall(function()
            -- Converted blob link to raw for execution
            return loadstring(game:HttpGet('https://raw.githubusercontent.com/TwichyPlayer/TitanHub/main/pathfindingsystem.lua'))()
        end)
        if Success and Result then
            Dependencies.PathAI = Result
        else
            task.wait(0.5)
        end
    until Dependencies.PathAI
end)

-- Wait for critical dependencies
local StartTime = tick()
repeat task.wait() until (Dependencies.NEX and Dependencies.PathAI) or (tick() - StartTime > 10)

if not Dependencies.NEX or not Dependencies.PathAI then
    warn("[CRITICAL]: FAILED TO LOAD DEPENDENCIES. SOME SYSTEMS MAY FAIL.")
end

local NEX = Dependencies.NEX
local PathAI = Dependencies.PathAI

-- // 2. AI CORE CONFIGURATION //

local SlapAI = {}
SlapAI.__index = SlapAI

local LOCAL_PLAYER = Players.LocalPlayer
local CONFIG = {
    ReachThreshold = 14.5, -- Tuned for "Flick" tech
    FlickAngle = 85,       -- Corner abuse angle
    TickRate = 0.015,
    PredictionFactor = 0.625, -- Ping compensation
    JumpReadThreshold = 0.4,  -- Height diff to trigger jump read
}

local State = {
    Active = false,
    CurrentMode = "Idle", -- "Target", "Run", "Pathing"
    TargetPlayer = nil :: Player?,
    TargetCriteria = "nearest", 
    TargetGloveName = "",
    TargetPlayerName = "",
    EvadePoint = Vector3.zero,
    LastSlapTime = 0,
    LastJumpTime = 0,
    StuckCheck = {Pos = Vector3.zero, Time = 0},
    Connection = nil :: RBXScriptConnection?
}

-- // 3. UTILITY FUNCTIONS (WRAPPING NEX) //

local function GetChar(Plr: Player)
    return NEX:GetCharacter(Plr)
end

local function GetRoot(Plr: Player)
    local Char = GetChar(Plr)
    return Char and NEX:GetRoot(Char)
end

local function IsAlive(Plr: Player): boolean
    local Char = GetChar(Plr)
    return Char and NEX:HasHumanoid(Char) and NEX:GetHumanoid(Char).Health > 0
end

local function GetEnemyGlove(Plr: Player): string
    -- NEX.GetGlove() is for local only, implementing scanner for enemies
    if not Plr then return "Unknown" end
    local Leaderstats = Plr:FindFirstChild("leaderstats")
    if Leaderstats then
        local Glove = Leaderstats:FindFirstChild("Glove")
        if Glove then return tostring(Glove.Value) end
    end
    if Plr.Character then
        local Tool = Plr.Character:FindFirstChildOfClass("Tool")
        if Tool then return Tool.Name end
    end
    return "Default"
end

-- // 4. COMBAT MECHANICS //

local function PerformTryhardFlick(TargetPos: Vector3, TargetRoot: BasePart)
    if not State.Active then return end
    
    local MyRoot = GetRoot(LOCAL_PLAYER)
    if not MyRoot then return end

    -- [A] THE FLICK: Rotate 85 degrees to hit with corner of Hitbox
    local LookCFrame = CFrame.new(MyRoot.Position, Vector3.new(TargetPos.X, MyRoot.Position.Y, TargetPos.Z))
    local FlickCFrame = LookCFrame * CFrame.Angles(0, math.rad(CONFIG.FlickAngle), 0)
    
    MyRoot.CFrame = FlickCFrame
    
    -- [B] THE SLAP: Use NEX for secure remote firing + VirtualUser for input redundancy
    -- NEX expects a table: {[1] = RootPart}
    task.spawn(function()
        NEX:Slap({[1] = TargetRoot})
        VirtualUser:Button1Down(Vector2.new(0,0), workspace.CurrentCamera.CFrame)
    end)

    -- [C] RECOVERY: Snap back instantly
    task.delay(0.05, function()
        if MyRoot then
            MyRoot.CFrame = LookCFrame
            VirtualUser:Button1Up(Vector2.new(0,0), workspace.CurrentCamera.CFrame)
        end
    end)
end

local function PredictMovement(Target: Player): Vector3
    local TRoot = GetRoot(Target)
    if not TRoot then return Vector3.zero end
    
    local Velocity = TRoot.Velocity
    local Pos = TRoot.Position
    
    -- JUMP READING: If they are in the air, they can't strafe well. Predict landing.
    if math.abs(Velocity.Y) > 5 then
        return Pos + (Vector3.new(Velocity.X, 0, Velocity.Z) * CONFIG.PredictionFactor)
    end
    
    return Pos + (Velocity * (CONFIG.PredictionFactor * 0.5))
end

-- // 5. TARGET SELECTION ENGINE //

local function SelectTarget()
    local BestTarget = nil
    local BestScore = (State.TargetCriteria == "nearest") and math.huge or -math.huge
    local MyRoot = GetRoot(LOCAL_PLAYER)
    if not MyRoot then return end
    local MyPos = MyRoot.Position

    for _, Plr in ipairs(Players:GetPlayers()) do
        if Plr ~= LOCAL_PLAYER and IsAlive(Plr) then
            local TRoot = GetRoot(Plr)
            if TRoot then
                local Dist = (MyPos - TRoot.Position).Magnitude
                
                -- Arena Check (Roughly)
                if Dist < 600 then 
                    if State.TargetCriteria == "nearest" then
                        if Dist < BestScore then
                            BestScore = Dist
                            BestTarget = Plr
                        end
                    elseif State.TargetCriteria == "farthest" then
                        if Dist > BestScore then
                            BestScore = Dist
                            BestTarget = Plr
                        end
                    elseif State.TargetCriteria == "random" then
                        if math.random() > 0.5 then BestTarget = Plr end
                    elseif State.TargetCriteria == "glove" then
                        if GetEnemyGlove(Plr) == State.TargetGloveName then
                            BestTarget = Plr
                            break
                        end
                    elseif State.TargetCriteria == "name" then
                        if string.find(string.lower(Plr.Name), string.lower(State.TargetPlayerName)) or 
                           string.find(string.lower(Plr.DisplayName), string.lower(State.TargetPlayerName)) then
                            BestTarget = Plr
                            break
                        end
                    end
                end
            end
        end
    end
    State.TargetPlayer = BestTarget
end

-- // 6. MAIN EXECUTION LOOP //

local function MainLoop()
    if not State.Active or not IsAlive(LOCAL_PLAYER) then return end
    local MyRoot = GetRoot(LOCAL_PLAYER)
    local MyHum = NEX:GetHumanoid(GetChar(LOCAL_PLAYER))
    
    if not MyRoot or not MyHum then return end

    -- [MODE: TARGET] --
    if State.CurrentMode == "Target" then
        if not State.TargetPlayer or not IsAlive(State.TargetPlayer) then
            SelectTarget()
        end

        if State.TargetPlayer then
            local TRoot = GetRoot(State.TargetPlayer)
            if TRoot then
                local PredictedPos = PredictMovement(State.TargetPlayer)
                local Dist = (MyRoot.Position - PredictedPos).Magnitude
                
                -- Movement: Strafe Logic (Fluidity)
                local MoveDir = Vector3.zero
                
                if Dist > CONFIG.ReachThreshold then
                    MoveDir = (PredictedPos - MyRoot.Position).Unit
                elseif Dist < (CONFIG.ReachThreshold - 5) then
                    -- Back up but keep facing (Kiting)
                    MoveDir = (MyRoot.Position - PredictedPos).Unit
                else
                    -- "Shift-Lock Dancing": Circle Strafe
                    local RightVector = (PredictedPos - MyRoot.Position).Unit:Cross(Vector3.new(0, 1, 0))
                    MoveDir = (RightVector * math.sin(tick() * 4)) + ((PredictedPos - MyRoot.Position).Unit * 0.3)
                end
                
                -- Stuck Check
                if (tick() - State.StuckCheck.Time) > 0.5 then
                    if (State.StuckCheck.Pos - MyRoot.Position).Magnitude < 0.5 then
                        MyHum.Jump = true -- Bunny hop if stuck
                    end
                    State.StuckCheck.Pos = MyRoot.Position
                    State.StuckCheck.Time = tick()
                end

                -- Apply Move
                MyHum:Move(MoveDir)
                
                -- Face Target (Required for Flick)
                local LookCFrame = CFrame.new(MyRoot.Position, Vector3.new(PredictedPos.X, MyRoot.Position.Y, PredictedPos.Z))
                MyRoot.CFrame = MyRoot.CFrame:Lerp(LookCFrame, 0.5)

                -- Attack Trigger
                if Dist <= (CONFIG.ReachThreshold + 1.5) and (tick() - State.LastSlapTime > 0.35) then
                    PerformTryhardFlick(PredictedPos, TRoot)
                    State.LastSlapTime = tick()
                end
            end
        else
            -- No target found, idle movement
            MyHum:Move(Vector3.new(math.sin(tick()), 0, math.cos(tick())))
        end

    -- [MODE: RUN] --
    elseif State.CurrentMode == "Run" then
        local AvoidVec = Vector3.zero
        local Count = 0
        
        for _, Plr in ipairs(Players:GetPlayers()) do
            if Plr ~= LOCAL_PLAYER and IsAlive(Plr) then
                local TRoot = GetRoot(Plr)
                if TRoot then
                    local Diff = (MyRoot.Position - TRoot.Position)
                    if Diff.Magnitude < 25 then
                        AvoidVec = AvoidVec + (Diff.Unit * (50 / Diff.Magnitude))
                        Count = Count + 1
                    end
                end
            end
        end
        
        if Count > 0 then
            MyHum:Move(AvoidVec.Unit)
            MyRoot.CFrame = CFrame.new(MyRoot.Position, MyRoot.Position + AvoidVec)
            if Count > 2 then MyHum.Jump = true end -- Panic jump
        else
            if State.EvadePoint ~= Vector3.zero then
                MyHum:MoveTo(State.EvadePoint)
            else
                MyHum:Move(Vector3.zero)
            end
        end

    -- [MODE: PATHING] --
    elseif State.CurrentMode == "Pathing" then
        -- This is handled by PathAI internally, but we ensure SlapAI doesn't override it
        -- We just monitor if it stopped
        if not State.Active then
            PathAI.Stop()
        end
    end
end

-- // 7. PUBLIC API //

function SlapAI.target(TargetIdentifier: any?)
    if not State.Active then
        State.Active = true
        State.Connection = RunService.Heartbeat:Connect(MainLoop)
    end
    
    -- Reset pathfinding if it was active
    if State.CurrentMode == "Pathing" and PathAI then PathAI.Stop() end
    
    State.CurrentMode = "Target"
    
    if type(TargetIdentifier) == "string" then
        local Lower = string.lower(TargetIdentifier)
        if table.find({"nearest", "farthest", "random"}, Lower) then
            State.TargetCriteria = Lower
        else
            State.TargetCriteria = "name"
            State.TargetPlayerName = TargetIdentifier
        end
        
        if string.find(TargetIdentifier, "Glove:") then
            State.TargetCriteria = "glove"
            State.TargetGloveName = string.split(TargetIdentifier, ":")[2]
        end
    elseif type(TargetIdentifier) == "nil" then
        State.TargetCriteria = "nearest"
    end
    
    SelectTarget()
end

function SlapAI.run(Mode: string?, X: number?, Y: number?, Z: number?)
    if not State.Active then
        State.Active = true
        State.Connection = RunService.Heartbeat:Connect(MainLoop)
    end
    
    if State.CurrentMode == "Pathing" and PathAI then PathAI.Stop() end
    State.CurrentMode = "Run"
    
    if X and Y and Z then
        State.EvadePoint = Vector3.new(X, Y, Z)
    else
        State.EvadePoint = Vector3.zero
    end
end

function SlapAI.reset()
    NEX:Reset(false, 0)
    SlapAI.stop()
end

function SlapAI.stop()
    State.Active = false
    if State.Connection then
        State.Connection:Disconnect()
        State.Connection = nil
    end
    
    local MyHum = NEX:GetHumanoid(GetChar(LOCAL_PLAYER))
    if MyHum then MyHum:Move(Vector3.zero) end
    
    if PathAI then PathAI.Stop() end
    State.CurrentMode = "Idle"
end

function SlapAI.AdvancedPathfinding(TargetVec: Vector3)
    if not PathAI then 
        warn("PathAI not loaded yet!") 
        return 
    end
    
    SlapAI.stop() -- Stop internal loop, hand over to PathAI
    
    State.Active = true
    State.CurrentMode = "Pathing"
    
    -- TitanHub PathAI Integration
    PathAI.MoveTo(TargetVec)
    
    -- Optional: Visualize
    if PathAI.Visualize then PathAI.Visualize() end
end

-- Helper to equip gloves via NEX
function SlapAI.equip(GloveName: string)
    NEX:EquipGlove(GloveName)
end

-- Helper to get current slaps
function SlapAI.getSlaps()
    return NEX.GetSlaps()
end

print(">> PROJECT_TRYHARD_CORE v3.0 // NEX INTEGRATED // AI ONLINE <<")

return SlapAI