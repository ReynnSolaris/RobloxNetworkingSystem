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

-- Mount and form bodies. Motor6D.Transform is local and applied after physics,
-- so every client animates every body it sees without fighting the welds.
-- Legs are planted with IK: a ray from each hip finds the ground, the foot
-- target steps forward and back with the stride while moving and lifts
-- between steps, and the leg points from hip to foot. The body motor floats up
-- or down so the legs reach the ground on slopes. Wings flap in the air.
local bodyOffset: { [Motor6D]: number } = {}
local castParams = RaycastParams.new()
castParams.FilterType = Enum.RaycastFilterType.Exclude

-- Rigged bodies (imported rigs) play their own clips by state.
local rigTracks: { [Model]: { [string]: AnimationTrack } } = {}
local rigState: { [Model]: string } = {}
local function rigPlay(body: Model, state: string)
	if rigState[body] == state then
		return
	end
	local controller = body:FindFirstChildOfClass("AnimationController") or body:FindFirstChildOfClass("Humanoid")
	if not controller then
		return
	end
	local animator = controller:FindFirstChildOfClass("Animator") or Instance.new("Animator", controller)
	rigTracks[body] = rigTracks[body] or {}
	local tracks = rigTracks[body]
	local id = body:GetAttribute("Anim" .. state)
	if typeof(id) == "number" then
		id = "rbxassetid://" .. id
	end
	for name, track in tracks do
		if name ~= state and track.IsPlaying then
			track:Stop(0.25)
		end
	end
	if not id then
		rigState[body] = state
		return
	end
	if not tracks[state] then
		local animation = Instance.new("Animation")
		animation.AnimationId = id
		local ok, track = pcall(animator.LoadAnimation, animator, animation)
		if not ok then
			return
		end
		track.Looped = state ~= "Special"
		track.Priority = Enum.AnimationPriority.Movement
		tracks[state] = track
	end
	tracks[state]:Play(0.25)
	rigState[body] = state
	body.Destroying:Once(function()
		rigTracks[body], rigState[body] = nil, nil
	end)
end

local function hingeOf(motor: Motor6D): CFrame
	return motor.Part0.CFrame * motor.C0
end

-- the Transform that puts the hinge at `target` (world)
local function transformTo(motor: Motor6D, target: CFrame): CFrame
	return (motor.Part0.CFrame * motor.C0):Inverse() * target
end

RunService.RenderStepped:Connect(function()
	local t = os.clock()
	for _, other in Players:GetPlayers() do
		local character = other.Character
		local body = character and (character:FindFirstChild("Mount") or character:FindFirstChild("Form"))
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not body or not root then
			continue
		end
		castParams.FilterDescendantsInstances = { character }
		local velocity = root.AssemblyLinearVelocity
		local planar = Vector3.new(velocity.X, 0, velocity.Z)
		local speed = planar.Magnitude
		local moveDir = if speed > 0.5 then planar.Unit else root.CFrame.LookVector
		local flying = other:GetAttribute("FlightState") == "air"
		local special = (other:GetAttribute("MountSpecial") or -10)
		local specialAge = t - special
		if body:GetAttribute("Rigged") then
			rigPlay(body, if specialAge < 1.6 then "Special" elseif flying then "Fly" elseif speed > 1 then "Walk" else "Idle")
			continue
		end
		local legs, bodyMotor = {}, nil
		for _, motor in body:GetDescendants() do
			if motor:IsA("Motor6D") and motor.Name == "MountMotor" and motor.Part0 and motor.Part1 then
				local kind = motor:GetAttribute("Kind")
				if kind == "leg" then
					table.insert(legs, motor)
				elseif kind == "body" then
					bodyMotor = motor
				elseif kind == "wing" then
					local side = motor:GetAttribute("Side") or 1
					local flap = if flying then math.sin(t * 7) * 0.55 elseif speed > 1 then math.sin(t * 3) * 0.15 else -0.25
					motor.Transform = CFrame.Angles(0, 0, side * flap)
				end
			end
		end
		-- how far the ground is below each hip, with the body where it was built
		local lengths, grounds = {}, {}
		local need = nil
		for i, motor in legs do
			local length = motor:GetAttribute("Length") or 2.6
			local hinge = hingeOf(motor)
			-- undo any body float so the measurement is stable
			local hipWorld = hinge.Position - Vector3.new(0, bodyMotor and (bodyOffset[bodyMotor] or 0) or 0, 0)
			local hit = workspace:Raycast(hipWorld + Vector3.new(0, 1, 0), Vector3.new(0, -(length * 2 + 1), 0), castParams)
			lengths[i] = length
			grounds[i] = hit and hit.Position.Y or nil
			if hit then
				-- positive: this leg would sink by this much; negative: it hangs
				local sink = length - (hipWorld.Y - hit.Position.Y)
				need = if need then math.max(need, sink) else sink
			end
		end
		-- the body floats so the leg on the highest ground stands straight
		if bodyMotor then
			local target = if flying or not need then 0 else math.clamp(need, -1.5, 1.5)
			local current = bodyOffset[bodyMotor] or 0
			local smoothed = current + (target - current) * 0.2
			bodyOffset[bodyMotor] = smoothed
			-- moving: bob with the gait; idle: breathe; flying: tilt into the velocity; special: rear up
			local bob = if speed > 1 and not flying then math.abs(math.sin(t * math.clamp(speed * 0.35, 4, 14))) * 0.12 else math.sin(t * 1.6) * 0.04
			local pitch = 0
			if flying then
				local forward = root.CFrame:VectorToObjectSpace(velocity)
				pitch = math.clamp(-forward.Z * 0.01, -0.35, 0.35) - math.clamp(forward.Y * 0.012, -0.3, 0.3)
			elseif specialAge < 1.6 then
				local k = math.sin(math.min(specialAge / 1.6, 1) * math.pi)
				pitch = -0.6 * k
				bob += 0.8 * k
			end
			bodyMotor.Transform = CFrame.new(0, smoothed + bob, 0) * CFrame.Angles(pitch, 0, 0)
		end
		local gait = math.clamp(speed * 0.35, 0, 14)
		for i, motor in legs do
			local length = lengths[i]
			local phase = motor:GetAttribute("Phase") or 0
			local hinge = hingeOf(motor)
			local hip = hinge.Position
			local target
			local front = root.CFrame:PointToObjectSpace(hip).Z < 0
			if flying then
				target = hip + (-root.CFrame.UpVector * 0.7 + root.CFrame.LookVector * 0.7).Unit * length
			elseif specialAge < 1.6 and front then
				local k = math.sin(math.min(specialAge / 1.6, 1) * math.pi)
				target = hip + (-root.CFrame.UpVector * (1 - 0.8 * k) + root.CFrame.LookVector * 0.9 * k).Unit * length
			else
				local swing = if speed > 0.5 then math.sin(t * gait + phase) else 0
				local lift = if speed > 0.5 then math.max(0, math.cos(t * gait + phase)) * 0.45 else 0
				local stride = moveDir * swing * math.clamp(speed / 16, 0, 1) * 0.9
				local foot = hip + stride
				local ground = grounds[i]
				local hit = workspace:Raycast(foot + Vector3.new(0, 1, 0), Vector3.new(0, -(length * 2 + 1), 0), castParams)
				local y = if hit then hit.Position.Y elseif ground then ground else hip.Y - length
				-- a leg never reaches past its length; in the air it hangs
				y = math.max(y, hip.Y - length * 1.05)
				target = Vector3.new(foot.X, y + lift, foot.Z)
			end
			local reach = (target - hip).Magnitude
			if reach < 0.1 then
				target = hip - Vector3.new(0, length, 0)
			end
			motor.Transform = transformTo(motor, CFrame.lookAt(hip, target) * CFrame.Angles(math.pi / 2, 0, 0))
		end
	end
end)
