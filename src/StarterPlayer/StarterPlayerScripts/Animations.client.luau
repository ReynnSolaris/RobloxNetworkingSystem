local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local player = Players.LocalPlayer

-- Swing and cast animations for every character and creature, driven by
-- replicated attributes: Swing (a clock stamp) plays a slash, CastingSpell /
-- Casting hold a casting pose while set, SpellGo plays the release. Roblox's
-- own R15 animations are used so nothing needs uploading.

local IDS = { slash = "rbxassetid://522635514", cast = "rbxassetid://507770453", release = "rbxassetid://522638767" }

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
		track.Priority = Enum.AnimationPriority.Action
		track.Looped = name == "cast"
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
