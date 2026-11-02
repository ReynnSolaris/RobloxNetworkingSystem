local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Fusion = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Fusion"))
local Opcodes = require(ReplicatedStorage.Shared.Opcodes)
local Components = require(script.Parent:WaitForChild("Components"))
local player = Players.LocalPlayer
local mouse = player:GetMouse()
local netSend = script.Parent:WaitForChild("NetSend") :: BindableEvent

-- Target frame beside the player frame. Click a creature to target it, T or a
-- second click toggles auto-attack on a hostile one, Escape clears.

local scope = Fusion.scoped(Fusion)
local Children, peek = Fusion.Children, Fusion.peek

local target = scope:Value(nil :: Model?)
local attacking = scope:Value(false)
local health, maxHealth = scope:Value(0), scope:Value(1)
local hostile = scope:Computed(function(use)
	local model = use(target)
	return model ~= nil and model:GetAttribute("Faction") == "hostile"
end)

local TargetEvent = Instance.new("BindableEvent")
TargetEvent.Name = "Target"
TargetEvent.Parent = script.Parent

local function setAttacking(on: boolean)
	attacking:set(on and peek(hostile))
	netSend:Fire(Opcodes.CMSG_ATTACK, { On = peek(attacking) })
end

local function setTarget(model: Model?)
	target:set(model)
	setAttacking(false)
	netSend:Fire(Opcodes.CMSG_SET_TARGET, { Guid = model and model:GetAttribute("Guid") })
	TargetEvent:Fire(model)
end

scope:New "ScreenGui" {
	Name = "TargetFrame",
	ResetOnSpawn = false,
	Enabled = scope:Computed(function(use)
		return use(target) ~= nil
	end),
	Parent = player:WaitForChild("PlayerGui"),
	[Children] = Components.UnitFrame(scope, {
		Position = UDim2.fromOffset(312, 16),
		Size = UDim2.fromOffset(260, 68),
		Title = scope:Computed(function(use)
			local model = use(target)
			return if model then model.Name else ""
		end),
		TitleColor = scope:Computed(function(use)
			return if use(hostile) then Color3.fromRGB(255, 90, 90) else Color3.fromRGB(90, 220, 90)
		end),
		Info = scope:Computed(function(use)
			local model = use(target)
			return if model then ("Level %s %s"):format(tostring(model:GetAttribute("Level") or "?"), if use(hostile) then "Hostile" else "Friendly") else ""
		end),
		Right = scope:Computed(function(use)
			return if use(attacking) then "ATTACKING" else ""
		end),
		Health = health,
		MaxHealth = maxHealth,
		HealthColor = Color3.fromRGB(200, 60, 60),
	}),
}

local function creatureFrom(part: Instance?): Model?
	local creatures = workspace:FindFirstChild("Creatures")
	while part and part ~= workspace do
		if part:IsA("Model") and part:GetAttribute("Guid") and part.Parent == creatures then
			return part
		end
		part = part.Parent
	end
	return nil
end

mouse.Button1Down:Connect(function()
	if player:GetAttribute("InWorld") ~= true then
		return
	end
	local model = creatureFrom(mouse.Target)
	if model and model == peek(target) then
		setAttacking(not peek(attacking))
	elseif model then
		setTarget(model)
	end
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed or not peek(target) then
		return
	end
	if input.KeyCode == Enum.KeyCode.T then
		setAttacking(not peek(attacking))
	elseif input.KeyCode == Enum.KeyCode.Escape then
		setTarget(nil)
	end
end)

player:GetAttributeChangedSignal("InWorld"):Connect(function()
	if player:GetAttribute("InWorld") ~= true then
		setTarget(nil)
	end
end)

while true do
	task.wait(0.1)
	local model = peek(target)
	if model then
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		if not model.Parent or not humanoid then
			setTarget(nil)
		else
			health:set(humanoid.Health)
			maxHealth:set(humanoid.MaxHealth)
			if humanoid.Health <= 0 and peek(attacking) then
				setAttacking(false)
			end
		end
	end
end
