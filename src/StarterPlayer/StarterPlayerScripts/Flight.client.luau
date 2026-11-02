local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local player = Players.LocalPlayer

-- Flight controller for flying mounts. While MountFlying is set the character
-- platform-stands and a LinearVelocity carries it where the camera looks:
-- WASD moves along the camera, Space rises, Shift descends, no input hovers.

local camera = workspace.CurrentCamera
local controls = nil
pcall(function()
	controls = require(player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule")):GetControls()
end)

local velocity: LinearVelocity? = nil
local orientation: AlignOrientation? = nil
local attachment: Attachment? = nil

local function stop()
	for _, instance in { velocity, orientation, attachment } do
		if instance then
			instance:Destroy()
		end
	end
	velocity, orientation, attachment = nil, nil, nil
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.PlatformStand = false
	end
end

local function start()
	stop()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid then
		return
	end
	humanoid.PlatformStand = true
	attachment = Instance.new("Attachment")
	attachment.Parent = root
	velocity = Instance.new("LinearVelocity")
	velocity.Attachment0 = attachment
	velocity.MaxForce = math.huge
	velocity.RelativeTo = Enum.ActuatorRelativeTo.World
	velocity.VectorVelocity = Vector3.zero
	velocity.Parent = root
	orientation = Instance.new("AlignOrientation")
	orientation.Attachment0 = attachment
	orientation.Mode = Enum.OrientationAlignmentMode.OneAttachment
	orientation.MaxTorque = math.huge
	orientation.Responsiveness = 40
	orientation.Parent = root
end

RunService.RenderStepped:Connect(function()
	if not velocity or not orientation or not velocity.Parent then
		return
	end
	local move = if controls then controls:GetMoveVector() else Vector3.zero
	local look = camera.CFrame
	local flat = Vector3.new(look.LookVector.X, 0, look.LookVector.Z)
	local forward = if flat.Magnitude > 0.01 then flat.Unit else Vector3.zAxis
	local right = Vector3.new(-forward.Z, 0, forward.X)
	local horizontal = (forward * -move.Z + right * move.X)
	local vertical = 0
	if UserInputService:IsKeyDown(Enum.KeyCode.Space) then
		vertical = 1
	elseif UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then
		vertical = -1
	end
	-- pitch follows the camera while moving forward, like WoW flight
	local pitch = if move.Z < -0.1 then look.LookVector.Y * Config.Flight.Speed else 0
	velocity.VectorVelocity = horizontal * Config.Flight.Speed + Vector3.new(0, vertical * Config.Flight.Vertical + pitch, 0)
	orientation.CFrame = CFrame.lookAt(Vector3.zero, forward)
end)

player:GetAttributeChangedSignal("MountFlying"):Connect(function()
	if player:GetAttribute("MountFlying") then
		start()
	else
		stop()
	end
end)
player.CharacterAdded:Connect(stop)
