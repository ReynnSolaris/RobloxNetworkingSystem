local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Fusion = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Fusion"))
local Opcodes = require(ReplicatedStorage.Shared.Opcodes)
local Components = require(script.Parent:WaitForChild("Components"))
local player = Players.LocalPlayer
local netSend = script.Parent:WaitForChild("NetSend") :: BindableEvent

-- Pet frame under the buff row: the pet's name, level and health, with Attack,
-- Follow, Passive and Dismiss. The pet is the creature whose Guid matches the
-- PetGuid attribute.

local scope = Fusion.scoped(Fusion)
local Children, peek = Fusion.Children, Fusion.peek

local petGuid = Components.attribute(scope, player, "PetGuid", nil)
local mode = Components.attribute(scope, player, "PetMode", "defensive")
local inWorld = Components.attribute(scope, player, "InWorld", false)
local name, level = scope:Value(""), scope:Value(1)
local health, maxHealth = scope:Value(0), scope:Value(1)

local function command(action: string)
	return function()
		netSend:Fire(Opcodes.CMSG_PET_ACTION, { Action = action })
	end
end

scope:New "ScreenGui" {
	Name = "PetFrame",
	ResetOnSpawn = false,
	Enabled = scope:Computed(function(use)
		return use(inWorld) == true and use(petGuid) ~= nil
	end),
	Parent = player:WaitForChild("PlayerGui"),
	[Children] = {
		Components.UnitFrame(scope, {
			Position = UDim2.fromOffset(16, 150),
			Size = UDim2.fromOffset(220, 60),
			Title = name,
			TitleColor = Color3.fromRGB(120, 200, 120),
			Info = scope:Computed(function(use)
				return ("Level %d Pet  (%s)"):format(use(level), use(mode) or "defensive")
			end),
			Health = health,
			MaxHealth = maxHealth,
			HealthColor = Color3.fromRGB(60, 200, 80),
		}),
		scope:New "Frame" {
			Position = UDim2.fromOffset(16, 214),
			Size = UDim2.fromOffset(220, 24),
			BackgroundTransparency = 1,
			[Children] = {
				scope:New "UIListLayout" { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4) },
				Components.Button(scope, { Size = UDim2.fromOffset(52, 24), Text = "Attack", TextSize = 11, OnClick = command("attack") }),
				Components.Button(scope, { Size = UDim2.fromOffset(52, 24), Text = "Follow", TextSize = 11, OnClick = command("follow") }),
				Components.Button(scope, { Size = UDim2.fromOffset(52, 24), Text = "Passive", TextSize = 11, OnClick = command("passive") }),
				Components.Button(scope, { Size = UDim2.fromOffset(52, 24), Text = "Dismiss", TextSize = 11, OnClick = command("dismiss") }),
			},
		},
	},
}

task.spawn(function()
	while true do
		task.wait(0.2)
		local guid = peek(petGuid)
		local creatures = workspace:FindFirstChild("Creatures")
		if guid and creatures then
			for _, model in creatures:GetChildren() do
				if model:GetAttribute("Guid") == guid then
					local humanoid = model:FindFirstChildOfClass("Humanoid")
					name:set(model.Name)
					level:set(model:GetAttribute("Level") or 1)
					if humanoid then
						health:set(humanoid.Health)
						maxHealth:set(humanoid.MaxHealth)
					end
				end
			end
		end
	end
end)
