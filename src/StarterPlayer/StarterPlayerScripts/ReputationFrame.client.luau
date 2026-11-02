local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Fusion = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Fusion"))
local Ui = require(script.Parent:WaitForChild("Ui"))
local Components = require(script.Parent:WaitForChild("Components"))
local SpellUi = require(script.Parent:WaitForChild("SpellUi"))
local player = Players.LocalPlayer

-- Reputation on U: every faction with a standing bar in its standing colour.

local scope = Fusion.scoped(Fusion)
local Children, peek = Fusion.Children, Fusion.peek

local open = scope:Value(false)
local reputationJson = Components.attribute(scope, player, "Reputation", "[]")
local list = scope:Computed(function(use)
	return SpellUi.decode(use(reputationJson), {})
end)

local function row(scope, faction, index)
	local color = Color3.fromHex(faction.Color or "#FFFF00")
	local span = math.max(1, (faction.Max or 1) - (faction.Min or 0) + 1)
	return scope:New "Frame" {
		Size = UDim2.new(1, -6, 0, 44),
		LayoutOrder = index,
		BackgroundColor3 = Ui.ROW,
		BorderSizePixel = 0,
		[Children] = {
			scope:New "UICorner" { CornerRadius = UDim.new(0, 4) },
			Components.Text(scope, { Position = UDim2.fromOffset(10, 4), Size = UDim2.new(0.6, 0, 0, 18), Font = Enum.Font.GothamBold, Text = faction.Name or "?" }),
			Components.Text(scope, { Position = UDim2.new(0.6, 0, 0, 4), Size = UDim2.new(0.4, -10, 0, 18), Align = Enum.TextXAlignment.Right, TextSize = 12, Color = color, Text = faction.Standing or "" }),
			Components.Bar(scope, { Position = UDim2.fromOffset(10, 26), Size = UDim2.new(1, -20, 0, 12), Value = scope:Value(faction.Value - (faction.Min or 0)), Max = scope:Value(span), Color = color, Back = Color3.fromRGB(30, 30, 40), Text = false }),
			scope:New "TextLabel" {
				Position = UDim2.fromOffset(10, 26),
				Size = UDim2.new(1, -20, 0, 12),
				BackgroundTransparency = 1,
				Font = Enum.Font.GothamBold,
				TextSize = 10,
				TextColor3 = Color3.new(1, 1, 1),
				Text = ("%d / %d"):format(faction.Value - (faction.Min or 0), span),
			},
			scope:New "TextButton" {
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				Text = "",
				[Fusion.OnEvent "MouseEnter"] = function()
					Ui.showTip(('<font size="16" color="#FFFFFF"><b>%s</b></font>\n<font color="#FFD100">%s</font>%s'):format(faction.Name, faction.Description or "", if faction.Team then ('\n<font color="#AAAAAA">%s</font>'):format(faction.Team) else ""), color)
				end,
				[Fusion.OnEvent "MouseLeave"] = Ui.hideTip,
			},
		},
	}
end

Components.Panel(scope, {
	Name = "ReputationFrame",
	Size = UDim2.fromOffset(420, 440),
	Position = UDim2.new(0.5, -200, 0.5, 0),
	Enabled = open,
	Parent = player:WaitForChild("PlayerGui"),
	Title = "Reputation",
	[Children] = scope:New "ScrollingFrame" {
		Position = UDim2.fromOffset(12, 10),
		Size = UDim2.new(1, -24, 1, -20),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		[Children] = {
			scope:New "UIListLayout" { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder },
			scope:ForPairs(list, function(use, scope, index, faction)
				return index, row(scope, faction, index)
			end),
		},
	},
})

UserInputService.InputBegan:Connect(function(input, processed)
	if processed or player:GetAttribute("InWorld") ~= true then
		return
	end
	if input.KeyCode == Enum.KeyCode.U then
		open:set(not peek(open))
	elseif input.KeyCode == Enum.KeyCode.Escape then
		open:set(false)
	end
end)
player:GetAttributeChangedSignal("InWorld"):Connect(function()
	if player:GetAttribute("InWorld") ~= true then
		open:set(false)
	end
end)
