local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local player = Players.LocalPlayer

-- Flying mounts have two states. Mounted on the ground you walk as usual;
-- Space takes off. In the air a LinearVelocity carries you where the camera
-- looks: WASD along the camera, Space rises, Shift descends, no input hovers.
-- Holding Shift near the ground, or the mount going away, lands you.

local camera = workspace.CurrentCamera
local controls = nil
pcall(function()
	controls = require(player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule")):GetControls()
end)

local state = "ground"
local velocity: LinearVelocity? = nil
local orientation: AlignOrientation? = nil
local attachment: Attachment? = nil

local function parts()
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart"), character and character:FindFirstChildOfClass("Humanoid")
end

local function land()
	for _, instance in { velocity, orientation, attachment } do
		if instance then
			instance:Destroy()
		end
	end
	velocity, orientation, attachment = nil, nil, nil
	local _, humanoid = parts()
	if humanoid then
		humanoid.PlatformStand = false
	end
	state = "ground"
	player:SetAttribute("FlightState", if player:GetAttribute("MountFlying") then "ground" else nil)
end

local function takeOff()
	local root, humanoid = parts()
	if not root or not humanoid or state == "air" then
		return
	end
	humanoid.PlatformStand = true
	attachment = Instance.new("Attachment")
	attachment.Parent = root
	velocity = Instance.new("LinearVelocity")
	velocity.Attachment0 = attachment
	velocity.MaxForce = math.huge
	velocity.RelativeTo = Enum.ActuatorRelativeTo.World
	velocity.VectorVelocity = Vector3.new(0, Config.Flight.Vertical * 0.6, 0)
	velocity.Parent = root
	orientation = Instance.new("AlignOrientation")
	orientation.Attachment0 = attachment
	orientation.Mode = Enum.OrientationAlignmentMode.OneAttachment
	orientation.MaxTorque = math.huge
	orientation.Responsiveness = 40
	orientation.Parent = root
	state = "air"
	player:SetAttribute("FlightState", "air")
end

local function groundBelow(root: BasePart, distance: number): boolean
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { player.Character }
	return workspace:Raycast(root.Position, Vector3.new(0, -distance, 0), params) ~= nil
end

RunService.RenderStepped:Connect(function()
	if state ~= "air" or not velocity or not velocity.Parent then
		return
	end
	local root = parts()
	local move = if controls then controls:GetMoveVector() else Vector3.zero
	local look = camera.CFrame
	local flat = Vector3.new(look.LookVector.X, 0, look.LookVector.Z)
	local forward = if flat.Magnitude > 0.01 then flat.Unit else Vector3.zAxis
	local right = Vector3.new(-forward.Z, 0, forward.X)
	local horizontal = forward * -move.Z + right * move.X
	local vertical = 0
	local descending = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)
	if UserInputService:IsKeyDown(Enum.KeyCode.Space) then
		vertical = 1
	elseif descending then
		vertical = -1
	end
	if descending and root and groundBelow(root, 4.5) then
		return land()
	end
	local pitch = if move.Z < -0.1 then look.LookVector.Y * Config.Flight.Speed else 0
	velocity.VectorVelocity = horizontal * Config.Flight.Speed + Vector3.new(0, vertical * Config.Flight.Vertical + pitch, 0)
	orientation.CFrame = CFrame.lookAt(Vector3.zero, forward)
end)

UserInputService.JumpRequest:Connect(function()
	if player:GetAttribute("MountFlying") and state == "ground" then
		takeOff()
	end
end)

player:GetAttributeChangedSignal("MountFlying"):Connect(function()
	if player:GetAttribute("MountFlying") then
		state = "ground"
		player:SetAttribute("FlightState", "ground")
	else
		land()
	end
end)
player.CharacterAdded:Connect(land)
