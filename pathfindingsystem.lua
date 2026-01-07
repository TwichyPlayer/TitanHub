--!strict
--[[
    MODULE: ADVANCED_PATHFINDING_CORE
    TYPE: CLIENT-SIDE MOVEMENT ENGINE
    DEPENDENCY: NONE (STANDALONE)
]]

local PathingAI = {}
PathingAI.__index = PathingAI

-- // SERVICES //
local PathfindingService = game:GetService("PathfindingService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

-- // CONSTANTS //
local AGENT_PARAMS = {
    AgentRadius = 2.0,
    AgentHeight = 5.0,
    AgentCanJump = true,
    WaypointSpacing = 4,
    Costs = {
        Water = 20,
        Neon = math.huge -- Example: Avoid hazards if tagged
    }
}

local JUMP_POWER_ESTIMATE = 50
local GRAVITY = Workspace.Gravity

-- // STATE //
local ActivePath = nil
local CurrentTarget = nil
local IsMoving = false
local CurrentWaypoints = {}
local CurrentWaypointIndex = 1
local Connection: RBXScriptConnection? = nil

local LocalPlayer = Players.LocalPlayer
local Character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
local Humanoid = Character:WaitForChild("Humanoid")
local RootPart = Character:WaitForChild("HumanoidRootPart")

LocalPlayer.CharacterAdded:Connect(function(NewChar)
    Character = NewChar
    Humanoid = NewChar:WaitForChild("Humanoid")
    RootPart = NewChar:WaitForChild("HumanoidRootPart")
end)

-- // PHYSICS UTILITIES //

-- Casts a ray downwards to check for ground
local function CheckGround(Origin: Vector3, Depth: number): boolean
    local RayParams = RaycastParams.new()
    RayParams.FilterDescendantsInstances = {Character}
    RayParams.FilterType = Enum.RaycastFilterType.Exclude
    
    local Result = Workspace:Raycast(Origin, Vector3.new(0, -Depth, 0), RayParams)
    return Result ~= nil
end

-- Checks if there is a wall in front
local function CheckWall(Dir: Vector3): boolean
    local RayParams = RaycastParams.new()
    RayParams.FilterDescendantsInstances = {Character}
    
    local Result = Workspace:Raycast(RootPart.Position, Dir * 3, RayParams)
    return Result ~= nil
end

-- Calculates required jump velocity (Projectile Motion)
local function CalculateJumpTrajectory(Start: Vector3, End: Vector3): boolean
    local Dist = (Vector3.new(End.X, 0, End.Z) - Vector3.new(Start.X, 0, Start.Z)).Magnitude
    local HeightDiff = End.Y - Start.Y
    
    -- Heuristic: If target is far and higher/level, we need to jump
    if Dist > 4 or HeightDiff > 1 then
        return true
    end
    return false
end

-- // CORE LOGIC //

function PathingAI.Stop()
    IsMoving = false
    if Connection then Connection:Disconnect() end
    Humanoid:Move(Vector3.zero)
    CurrentWaypoints = {}
end

function PathingAI.MoveTo(TargetPosition: Vector3)
    PathingAI.Stop()
    IsMoving = true
    CurrentTarget = TargetPosition
    
    task.spawn(function()
        local Path = PathfindingService:CreatePath(AGENT_PARAMS)
        
        local success, errorMessage = pcall(function()
            Path:ComputeAsync(RootPart.Position, TargetPosition)
        end)
        
        if success and Path.Status == Enum.PathStatus.Success then
            CurrentWaypoints = Path:GetWaypoints()
            CurrentWaypointIndex = 2 -- Skip current position
            
            -- EXECUTION LOOP
            Connection = RunService.Heartbeat:Connect(function(Delta)
                if not IsMoving then return end
                if CurrentWaypointIndex > #CurrentWaypoints then
                    PathingAI.Stop()
                    return
                end
                
                local Waypoint = CurrentWaypoints[CurrentWaypointIndex]
                local TargetVec = Waypoint.Position
                local MyPos = RootPart.Position
                
                -- Flat distance ignoring Y (for navigation precision)
                local DistXZ = (Vector3.new(TargetVec.X, 0, TargetVec.Z) - Vector3.new(MyPos.X, 0, MyPos.Z)).Magnitude
                local DistFull = (TargetVec - MyPos).Magnitude
                
                -- Move Direction
                local MoveDir = (TargetVec - MyPos).Unit
                
                -- // PARKOUR LOGIC //
                
                -- 1. Jump Action from Pathfinding
                if Waypoint.Action == Enum.PathWaypointAction.Jump then
                   Humanoid.Jump = true
                end
                
                -- 2. Smart Gap Jumping (Raycast Forward-Down)
                -- We cast a ray slightly in front of feet to detect void
                local LookAhead = RootPart.Position + (Humanoid.MoveDirection * 2)
                if not CheckGround(LookAhead, 10) then
                    -- Void detected ahead. Check if next waypoint is across the gap
                    if CheckGround(TargetVec, 10) then
                        Humanoid.Jump = true
                    end
                end
                
                -- 3. Wall/Obstacle Vaulting
                if CheckWall(MoveDir) and Humanoid.FloorMaterial ~= Enum.Material.Air then
                    Humanoid.Jump = true
                end
                
                -- 4. Shift-Lock Rotation & Movement
                Humanoid:Move(MoveDir)
                
                -- Face direction smoothly (Mock Shift-Lock)
                local LookCFrame = CFrame.new(MyPos, Vector3.new(TargetVec.X, MyPos.Y, TargetVec.Z))
                RootPart.CFrame = RootPart.CFrame:Lerp(LookCFrame, 0.2)
                
                -- // WAYPOINT COMPLETION //
                local Threshold = (Waypoint.Action == Enum.PathWaypointAction.Jump) and 2 or 4
                
                -- If close enough, proceed to next
                if DistXZ < 3 and math.abs(MyPos.Y - TargetVec.Y) < 4 then
                    CurrentWaypointIndex = CurrentWaypointIndex + 1
                    
                    -- Check if we are stuck (Stuck heuristic would go here, simple version:)
                    -- If velocity is 0 while trying to move, jump
                    if RootPart.Velocity.Magnitude < 0.1 then
                        Humanoid.Jump = true
                    end
                end
            end)
        else
            warn("[PathAI]: Path computation failed - " .. tostring(errorMessage))
            PathingAI.Stop()
        end
    end)
end

-- // VISUAL DEBUG (Optional) //
function PathingAI.Visualize()
    if not IsMoving then return end
    for i, wp in ipairs(CurrentWaypoints) do
        local part = Instance.new("Part")
        part.Size = Vector3.new(1,1,1)
        part.Position = wp.Position
        part.Anchored = true
        part.CanCollide = false
        part.Color = Color3.fromRGB(0, 255, 0)
        part.Parent = Workspace
        part.Material = Enum.Material.Neon
        game:GetService("Debris"):AddItem(part, 2)
    end
end

return PathingAI