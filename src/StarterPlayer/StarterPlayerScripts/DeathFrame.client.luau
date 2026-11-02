local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Fusion = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Fusion"))
local Opcodes = require(ReplicatedStorage.Shared.Opcodes)
local Ui = require(script.Parent:WaitForChild("Ui"))
local Components = require(script.Parent:WaitForChild("Components"))
local player = Players.LocalPlayer
local netSend = script.Parent:WaitForChild("NetSend") :: BindableEvent

-- Death: "You have died" with Release Spirit; as a ghost, a reminder to run back
-- to the corpse marker and resurrect there.

local scope = Fusion.scoped(Fusion)
local Children = Fusion.Children

local dead = Components.attribute(scope, player, "Dead", false)
local ghost = Components.attribute(scope, player, "Ghost", false)
local resurrectFrom = Components.attribute(scope, player, "ResurrectFrom", nil)
local bgDeath = Components.attribute(scope, player, "DeadInBattleground", nil)
local now = scope:Value(os.clock())
game:GetService("RunService").Heartbeat:Connect(function()
	now:set(os.clock())
end)

local showDead = scope:Computed(function(use)
	return use(dead) == true and use(ghost) ~= true
end)

scope:New "ScreenGui" {
	Name = "DeathFrame",
	ResetOnSpawn = false,
	DisplayOrder = 30,
	Enabled = scope:Computed(function(use)
		return use(showDead) or use(ghost) == true or use(resurrectFrom) ~= nil
	end),
	Parent = player:WaitForChild("PlayerGui"),
	[Children] = {
		scope:New "Frame" {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0.18, 0),
			Size = UDim2.fromOffset(320, 110),
			BackgroundColor3 = Ui.PANEL,
			BackgroundTransparency = 0.15,
			BorderSizePixel = 0,
			Visible = showDead,
			[Children] = {
				scope:New "UICorner" { CornerRadius = UDim.new(0, 8) },
				scope:New "UIStroke" { Color = Color3.fromRGB(150, 40, 40) },
				Components.Text(scope, { Size = UDim2.new(1, 0, 0, 40), Position = UDim2.fromOffset(0, 10), Text = "You have died.", Font = Enum.Font.Garamond, TextSize = 30, Color = Color3.fromRGB(230, 90, 90), Align = Enum.TextXAlignment.Center }),
				Components.Button(scope, { Size = UDim2.fromOffset(180, 34), Position = UDim2.new(0.5, -90, 1, -46), Text = "Release Spirit", Visible = scope:Computed(function(use)
					return use(bgDeath) == nil
				end), OnClick = function()
					netSend:Fire(Opcodes.CMSG_REPOP_REQUEST, {})
				end }),
				Components.Text(scope, { Size = UDim2.new(1, 0, 0, 24), Position = UDim2.new(0, 0, 1, -42), Align = Enum.TextXAlignment.Center, Color = Ui.GOLD, Visible = scope:Computed(function(use)
					return use(bgDeath) ~= nil
				end), Text = scope:Computed(function(use)
					local raw = use(bgDeath)
					local seconds, at = (raw or ""):match("^(%d+) ([%d%.]+)$")
					if not seconds then
						return ""
					end
					return ("Resurrecting at your base in %d..."):format(math.max(0, math.ceil(tonumber(seconds) - (use(now) - tonumber(at)))))
				end) }),
			},
		},
		scope:New "Frame" {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0.36, 0),
			Size = UDim2.fromOffset(340, 100),
			BackgroundColor3 = Ui.PANEL,
			BackgroundTransparency = 0.15,
			BorderSizePixel = 0,
			Visible = scope:Computed(function(use)
				return use(resurrectFrom) ~= nil
			end),
			[Children] = {
				scope:New "UICorner" { CornerRadius = UDim.new(0, 8) },
				scope:New "UIStroke" { Color = Ui.GOLD },
				Components.Text(scope, { Size = UDim2.new(1, -20, 0, 40), Position = UDim2.fromOffset(10, 8), Wrapped = true, Align = Enum.TextXAlignment.Center, Text = scope:Computed(function(use)
					return ("%s wants to resurrect you."):format(tostring(use(resurrectFrom)))
				end) }),
				Components.Button(scope, { Size = UDim2.fromOffset(120, 32), Position = UDim2.new(0.5, -126, 1, -42), Text = "Accept", OnClick = function()
					netSend:Fire(Opcodes.CMSG_RESURRECT_RESPONSE, { Accept = true })
					player:SetAttribute("ResurrectFrom", nil)
				end }),
				Components.Button(scope, { Size = UDim2.fromOffset(120, 32), Position = UDim2.new(0.5, 6, 1, -42), Text = "Decline", OnClick = function()
					netSend:Fire(Opcodes.CMSG_RESURRECT_RESPONSE, { Accept = false })
					player:SetAttribute("ResurrectFrom", nil)
				end }),
			},
		},
		scope:New "TextLabel" {
			Size = UDim2.new(1, 0, 0, 30),
			Position = UDim2.new(0, 0, 0.1, 0),
			BackgroundTransparency = 1,
			Font = Enum.Font.Gotham,
			TextSize = 18,
			TextColor3 = Color3.fromRGB(180, 200, 255),
			TextStrokeTransparency = 0.5,
			Text = "You are a ghost. Return to your corpse and resurrect.",
			Visible = scope:Computed(function(use)
				return use(ghost) == true
			end),
		},
	},
}
