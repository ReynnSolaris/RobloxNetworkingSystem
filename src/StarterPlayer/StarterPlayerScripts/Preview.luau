-- Character preview: a ViewportFrame with the server's bare R15 rig, shaped and
-- coloured like the server does on spawn (race scale and skin, class tunic),
-- turning slowly. Race and Class are states.
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Fusion = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Fusion"))
local Config = require(ReplicatedStorage.Shared.Config)

local Children, peek = Fusion.Children, Fusion.peek

local BODY = { Head = true, LeftUpperArm = true, LeftLowerArm = true, LeftHand = true, RightUpperArm = true, RightLowerArm = true, RightHand = true }
local LEGS = { LeftUpperLeg = true, LeftLowerLeg = true, LeftFoot = true, RightUpperLeg = true, RightLowerLeg = true, RightFoot = true }

local Preview = {}

function Preview.race(name: string?)
	for _, race in Config.Races do
		if race.Name == name then
			return race
		end
	end
	return Config.Races[1]
end

function Preview.class(name: string?)
	for _, class in Config.Classes do
		if class.Name == name then
			return class
		end
	end
	return nil
end

function Preview.dress(model: Model, raceName: string?, className: string?)
	local race, class = Preview.race(raceName), Preview.class(className)
	local skin = Color3.new(table.unpack(race.Skin))
	local tunic = if class then Color3.fromHex(class.Color):Lerp(Color3.new(0, 0, 0), 0.45) else Color3.fromRGB(80, 70, 60)
	for _, part in model:GetChildren() do
		if part:IsA("BasePart") then
			if BODY[part.Name] then
				part.Color = skin
			elseif LEGS[part.Name] then
				part.Color = Color3.fromRGB(45, 38, 32)
			elseif part.Name == "UpperTorso" or part.Name == "LowerTorso" then
				part.Color = tunic
			end
		elseif part:IsA("Shirt") or part:IsA("Pants") or part:IsA("ShirtGraphic") or part:IsA("Accessory") then
			part:Destroy()
		end
	end
	model:ScaleTo(race.Scale)
end

-- props: Race, Class (states), Size, Position, AnchorPoint, Visible
function Preview.new(scope, props)
	local camera = Instance.new("Camera")
	local viewport = scope:New "ViewportFrame" {
		Size = props.Size,
		Position = props.Position,
		AnchorPoint = props.AnchorPoint,
		Visible = props.Visible,
		BackgroundTransparency = 1,
		Ambient = Color3.fromRGB(140, 140, 160),
		LightColor = Color3.fromRGB(255, 240, 220),
		LightDirection = Vector3.new(-1, -2, -1),
		CurrentCamera = camera,
		[Children] = scope:New "WorldModel" {},
	} :: ViewportFrame
	camera.Parent = viewport
	local world = viewport:FindFirstChildOfClass("WorldModel")

	local rig: Model? = nil
	local angle = 0
	local function rebuild()
		if rig then
			rig:Destroy()
			rig = nil
		end
		local source = ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("PreviewRig")
		if not source then
			return
		end
		rig = source:Clone()
		local humanoid = rig:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		end
		Preview.dress(rig, peek(props.Race), peek(props.Class))
		rig:PivotTo(CFrame.new())
		rig.Parent = world
	end
	rebuild()
	scope:Observer(props.Race):onChange(rebuild)
	scope:Observer(props.Class):onChange(rebuild)
	task.spawn(function()
		local source = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("PreviewRig", 30)
		if source and not rig then
			rebuild()
		end
	end)

	RunService.RenderStepped:Connect(function(dt)
		if rig and viewport.Visible then
			angle += dt * 0.6
			local scale = Preview.race(peek(props.Race)).Scale
			rig:PivotTo(CFrame.new(0, 0, 0) * CFrame.Angles(0, angle, 0))
			camera.CFrame = CFrame.lookAt(Vector3.new(0, 1.2 * scale, 9 * scale), Vector3.new(0, 0.6 * scale, 0))
		end
	end)
	return viewport
end

return Preview
