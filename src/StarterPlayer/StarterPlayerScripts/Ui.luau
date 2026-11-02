-- Theme, text helpers and the shared tooltip. Window layout lives in Components.
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local player = Players.LocalPlayer

local Ui = {}
Ui.GOLD = Color3.fromRGB(255, 210, 100)
Ui.DIM = Color3.fromRGB(170, 170, 180)
Ui.PANEL = Color3.fromRGB(14, 14, 22)
Ui.ROW = Color3.fromRGB(28, 26, 34)
Ui.ROW_HOVER = Color3.fromRGB(52, 44, 28)
Ui.BORDER = Color3.fromRGB(120, 95, 40)
Ui.BAR_TOP = Color3.fromRGB(80, 60, 24)
Ui.BAR_BOTTOM = Color3.fromRGB(30, 24, 14)

function Ui.quality(q: number?): string
	return Config.Quality[q or 1] or Config.Quality[1]
end

function Ui.money(copper: number): string
	local g, s, c = copper // 10000, (copper % 10000) // 100, copper % 100
	local parts = {}
	if g > 0 then table.insert(parts, g .. "g") end
	if s > 0 then table.insert(parts, s .. "s") end
	if c > 0 or #parts == 0 then table.insert(parts, c .. "c") end
	return table.concat(parts, " ")
end

function Ui.itemName(item): string
	local count = if (item.Count or 1) > 1 then " x" .. item.Count else ""
	return ('<font color="%s">[%s]</font>%s'):format(Ui.quality(item.Quality), item.Name or "?", count)
end

function Ui.itemTooltip(item, price: string?): string
	local lines = { ('<font color="%s"><b>%s</b></font>'):format(Ui.quality(item.Quality), item.Name or "?") }
	if item.Slot then
		table.insert(lines, item.Slot:sub(1, 1):upper() .. item.Slot:sub(2))
	elseif item.Class then
		table.insert(lines, item.Class)
	end
	if (item.Armor or 0) > 0 then table.insert(lines, ("%d Armor"):format(item.Armor)) end
	if (item.Damage or 0) > 0 then table.insert(lines, ('<font color="#1EFF00">+%d Melee Damage</font>'):format(item.Damage)) end
	if (item.Health or 0) > 0 then table.insert(lines, ('<font color="#1EFF00">+%d Health</font>'):format(item.Health)) end
	if (item.Level or 1) > 1 then table.insert(lines, ("Requires Level %d"):format(item.Level)) end
	if price then table.insert(lines, ('<font color="#FFD700">%s</font>'):format(price)) end
	return table.concat(lines, "\n")
end

-- One tooltip for everything, following the mouse.
local tipGui = Instance.new("ScreenGui")
tipGui.Name = "Tooltip"
tipGui.ResetOnSpawn = false
tipGui.DisplayOrder = 50
local tip = Instance.new("TextLabel")
tip.AutomaticSize = Enum.AutomaticSize.XY
tip.BackgroundColor3 = Ui.PANEL
tip.BackgroundTransparency = 0.05
tip.BorderSizePixel = 0
tip.Font = Enum.Font.Gotham
tip.TextSize = 13
tip.TextColor3 = Color3.new(1, 1, 1)
tip.TextXAlignment = Enum.TextXAlignment.Left
tip.RichText = true
tip.Visible = false
tip.Parent = tipGui
Instance.new("UICorner", tip).CornerRadius = UDim.new(0, 4)
Instance.new("UIStroke", tip).Color = Ui.BORDER
local pad = Instance.new("UIPadding", tip)
pad.PaddingLeft, pad.PaddingRight, pad.PaddingTop, pad.PaddingBottom = UDim.new(0, 8), UDim.new(0, 8), UDim.new(0, 6), UDim.new(0, 6)
tipGui.Parent = player:WaitForChild("PlayerGui")
UserInputService.InputChanged:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseMovement and tip.Visible then
		tip.Position = UDim2.fromOffset(input.Position.X + 16, input.Position.Y + 16)
	end
end)

function Ui.showTip(text: string)
	tip.Text = text
	tip.Visible = true
end

function Ui.hideTip()
	tip.Visible = false
end

return Ui
