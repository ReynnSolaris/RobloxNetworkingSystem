local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Fusion = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Fusion"))
local Opcodes = require(ReplicatedStorage.Shared.Opcodes)
local Config = require(ReplicatedStorage.Shared.Config)
local Ui = require(script.Parent:WaitForChild("Ui"))
local Components = require(script.Parent:WaitForChild("Components"))
local SpellUi = require(script.Parent:WaitForChild("SpellUi"))
local player = Players.LocalPlayer
local netSend = script.Parent:WaitForChild("NetSend") :: BindableEvent

-- Battleground HUD at the top: scores for both factions, flag states, a Leave
-- button; "Queued for X" while waiting. Reads the Battleground attribute.

local scope = Fusion.scoped(Fusion)
local Children = Fusion.Children

local bgJson = Components.attribute(scope, player, "BattlegroundStatus", "{}")
local status = scope:Computed(function(use)
	return SpellUi.decode(use(bgJson), {})
end)
local visible = scope:Computed(function(use)
	local s = use(status).Status
	return s == "active" or s == "ended" or s == "queued"
end)

local function side(faction: string, x: number)
	local color = Color3.fromHex(Config.Factions[faction].Color)
	return scope:New "Frame" {
		Position = UDim2.fromOffset(x, 6),
		Size = UDim2.fromOffset(150, 44),
		BackgroundTransparency = 1,
		[Children] = {
			Components.Text(scope, { Size = UDim2.new(1, 0, 0, 22), Font = Enum.Font.GothamBold, TextSize = 16, Color = color, Align = Enum.TextXAlignment.Center, Text = scope:Computed(function(use)
				local s = use(status)
				return ("%s  %d / %d"):format(faction, (s.Scores or {})[faction] or 0, s.ToWin or Config.Battleground.ScoreToWin)
			end) }),
			Components.Text(scope, { Position = UDim2.fromOffset(0, 22), Size = UDim2.new(1, 0, 0, 18), TextSize = 11, Color = Ui.DIM, Align = Enum.TextXAlignment.Center, Text = scope:Computed(function(use)
				local flag = ((use(status).Flags or {})[faction]) or "home"
				return "Flag: " .. flag
			end) }),
		},
	}
end

scope:New "ScreenGui" {
	Name = "BattlegroundFrame",
	ResetOnSpawn = false,
	Enabled = visible,
	Parent = player:WaitForChild("PlayerGui"),
	[Children] = scope:New "Frame" {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 8),
		Size = UDim2.fromOffset(400, 56),
		BackgroundColor3 = Ui.PANEL,
		BackgroundTransparency = 0.15,
		BorderSizePixel = 0,
		[Children] = {
			scope:New "UICorner" { CornerRadius = UDim.new(0, 6) },
			scope:New "UIStroke" { Color = Ui.BORDER },
			scope:New "Frame" {
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				Visible = scope:Computed(function(use)
					return use(status).Status ~= "queued"
				end),
				[Children] = {
					side("Alliance", 10),
					side("Horde", 180),
					Components.Button(scope, { Size = UDim2.fromOffset(54, 24), Position = UDim2.new(1, -62, 0, 16), Text = "Leave", TextSize = 11, OnClick = function()
						netSend:Fire(Opcodes.CMSG_LEAVE_BATTLEFIELD, {})
					end }),
				},
			},
			Components.Text(scope, { Size = UDim2.new(1, -70, 1, 0), Position = UDim2.fromOffset(10, 0), Font = Enum.Font.GothamBold, Color = Ui.GOLD, Visible = scope:Computed(function(use)
				return use(status).Status == "queued"
			end), Text = scope:Computed(function(use)
				return ("Queued for %s, waiting for players..."):format(use(status).Name or "battle")
			end) }),
			Components.Button(scope, { Size = UDim2.fromOffset(54, 24), Position = UDim2.new(1, -62, 0, 16), Text = "Cancel", TextSize = 11, Visible = scope:Computed(function(use)
				return use(status).Status == "queued"
			end), OnClick = function()
				netSend:Fire(Opcodes.CMSG_LEAVE_BATTLEFIELD, {})
			end }),
		},
	},
}
