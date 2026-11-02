local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local player = Players.LocalPlayer

-- Swing and cast animations for every character and creature, driven by
-- replicated attributes: Swing (a clock stamp) plays a slash, CastingSpell /
-- Casting hold a casting pose while set, SpellGo plays the release. Roblox's
-- own R15 animations are used so nothing needs uploading.

local IDS = { slash = "rbxassetid://522635514", cast = "rbxassetid://507770453", release = "rbxassetid://522638767", ride = "rbxassetid://2506281703" }
local RunService = game:GetService("RunService")

local tracks: { [Model]: { [string]: AnimationTrack } } = {}

local function trackFor(model: Model, name: string): AnimationTrack?
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and (humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator", humanoid))
	if not animator then
		return nil
	end
	tracks[model] = tracks[model] or {}
	local track = tracks[model][name]
	if not track then
		local animation = Instance.new("Animation")
		animation.AnimationId = IDS[name]
		local ok, loaded = pcall(animator.LoadAnimation, animator, animation)
		if not ok then
			return nil
		end
		track = loaded
		track.Priority = if name == "ride" then Enum.AnimationPriority.Movement else Enum.AnimationPriority.Action
		track.Looped = name == "cast" or name == "ride"
		tracks[model][name] = track
	end
	return track
end

local function play(model: Model, name: string, speed: number?)
	local track = trackFor(model, name)
	if track then
		track:Play(0.1, 1, speed or 1)
	end
end

local function stop(model: Model, name: string)
	local t = tracks[model] and tracks[model][name]
	if t and t.IsPlaying then
		t:Stop(0.2)
	end
end

-- Hooks the attributes of whatever owns them (a Player or a creature Model) to a character model.
local function watch(owner: Instance, model: () -> Model?)
	local connections = {}
	table.insert(connections, owner:GetAttributeChangedSignal("Swing"):Connect(function()
		local m = model()
		if m then
			play(m, "slash", 1.4)
		end
	end))
	for _, attribute in { "CastingSpell", "Casting" } do
		table.insert(connections, owner:GetAttributeChangedSignal(attribute):Connect(function()
			local m = model()
			if m then
				if owner:GetAttribute(attribute) then
					play(m, "cast")
				else
					stop(m, "cast")
				end
			end
		end))
	end
	-- shapeshifting bursts; the form body animates below
	table.insert(connections, owner:GetAttributeChangedSignal("Form"):Connect(function()
		local m = model()
		if m and owner:GetAttribute("Form") then
			play(m, "release", 1.2)
		end
	end))
	-- riding: sit on the mount; wings and legs animate below
	table.insert(connections, owner:GetAttributeChangedSignal("Mounted"):Connect(function()
		local m = model()
		if m then
			if owner:GetAttribute("Mounted") then
				task.delay(0.1, function()
					play(m, "ride")
				end)
			else
				stop(m, "ride")
			end
		end
	end))
	table.insert(connections, owner:GetAttributeChangedSignal("SpellGo"):Connect(function()
		local m = model()
		if m then
			stop(m, "cast")
			play(m, "release", 1.6)
		end
	end))
	return connections
end

local function watchPlayer(other: Player)
	watch(other, function()
		return other.Character
	end)
	other.CharacterRemoving:Connect(function(character)
		tracks[character] = nil
	end)
end
Players.PlayerAdded:Connect(watchPlayer)
for _, other in Players:GetPlayers() do
	watchPlayer(other)
end

local function watchCreature(model: Instance)
	if not model:IsA("Model") then
		return
	end
	watch(model, function()
		return model
	end)
	model.Destroying:Connect(function()
		tracks[model] = nil
	end)
end
local creatures = workspace:WaitForChild("Creatures", 30)
if creatures then
	creatures.ChildAdded:Connect(watchCreature)
	for _, model in creatures:GetChildren() do
		watchCreature(model)
	end
end

-- Mount motors: wings flap in the air and glide on the ground, legs swing with
-- the mount's speed. Motor6D transforms are local, so each client animates
-- every mount it can see the same way.
local baseC0: { [Motor6D]: CFrame } = {}
RunService.RenderStepped:Connect(function()
	local t = os.clock()
	for _, other in Players:GetPlayers() do
		local character = other.Character
		local body = character and (character:FindFirstChild("Mount") or character:FindFirstChild("Form"))
		if not body then
			continue
		end
		local root = character:FindFirstChild("HumanoidRootPart")
		local speed = if root then Vector3.new(root.AssemblyLinearVelocity.X, 0, root.AssemblyLinearVelocity.Z).Magnitude else 0
		local flying = other:GetAttribute("FlightState") == "air"
		for _, motor in body:GetDescendants() do
			if motor:IsA("Motor6D") and motor.Name == "MountMotor" then
				baseC0[motor] = baseC0[motor] or motor.C0
				local kind, side, phase = motor:GetAttribute("Kind"), motor:GetAttribute("Side") or 1, motor:GetAttribute("Phase") or 0
				if kind == "wing" then
					local flap = if flying then math.sin(t * 7) * 0.55 elseif speed > 1 then math.sin(t * 3) * 0.15 else -0.25
					motor.C0 = baseC0[motor] * CFrame.Angles(0, 0, side * flap)
				elseif kind == "leg" then
					local swing = if flying then 0.3 else math.sin(t * math.clamp(speed * 0.35, 0, 14) + phase) * math.clamp(speed / 16, 0, 1) * 0.7
					motor.C0 = baseC0[motor] * CFrame.Angles(swing, 0, 0)
				end
			end
		end
	end
end)
