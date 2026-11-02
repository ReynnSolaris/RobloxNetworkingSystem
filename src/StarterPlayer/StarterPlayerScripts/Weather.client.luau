local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local player = Players.LocalPlayer

-- Weather from SMSG_WEATHER (the Weather attribute): rain and snow emitters
-- above the camera, fog and dimmer light for storms and fog. The server sets
-- ClockTime for day and night.

local camera = workspace.CurrentCamera
local holder = Instance.new("Part")
holder.Name = "WeatherEmitter"
holder.Anchored, holder.CanCollide, holder.CanQuery, holder.Transparency = true, false, false, 1
holder.Size = Vector3.new(60, 1, 60)
holder.Parent = workspace

local folder = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Particles")
local emitters: { [string]: ParticleEmitter } = {}
for _, name in { "Rain", "Snow" } do
	local source = folder:FindFirstChild(name)
	if source then
		local clone = source:Clone()
		clone.Enabled = false
		clone.Parent = holder
		emitters[name] = clone
	end
end

local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
local base = { Fog = atmosphere and atmosphere.Density or 0.3, Brightness = Lighting.Brightness }

local function apply(kind: string, intensity: number)
	for _, e in emitters do
		e.Enabled = false
	end
	local fog, bright = base.Fog, base.Brightness
	if (kind == "rain" or kind == "storm") and emitters.Rain then
		emitters.Rain.Enabled = true
		emitters.Rain.Rate = (if kind == "storm" then 400 else 180) * intensity
		fog += if kind == "storm" then 0.25 else 0.1
		bright *= if kind == "storm" then 0.6 else 0.85
	elseif kind == "snow" and emitters.Snow then
		emitters.Snow.Enabled = true
		emitters.Snow.Rate = 120 * intensity
		fog += 0.12
	elseif kind == "fog" then
		fog += 0.35 * intensity
		bright *= 0.8
	end
	if atmosphere then
		TweenService:Create(atmosphere, TweenInfo.new(4), { Density = math.clamp(fog, 0, 1) }):Play()
	end
	TweenService:Create(Lighting, TweenInfo.new(4), { Brightness = bright }):Play()
end

player:GetAttributeChangedSignal("Weather"):Connect(function()
	local raw = player:GetAttribute("Weather") or "clear 0"
	local kind, intensity = raw:match("^(%a+) ([%d%.]+)$")
	apply(kind or "clear", tonumber(intensity) or 0.5)
end)

game:GetService("RunService").RenderStepped:Connect(function()
	holder.CFrame = CFrame.new(camera.CFrame.Position + Vector3.new(0, 30, 0))
end)
