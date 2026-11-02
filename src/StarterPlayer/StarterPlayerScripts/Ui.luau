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

-- WoW layout: name in quality colour, slot and type, armor, green stats, level
-- requirement (red when the character is too low), then the price line.
function Ui.itemTooltip(item, price: string?): string
	local function cap(word: string?): string
		return if word then word:sub(1, 1):upper() .. word:sub(2) else ""
	end
	local lines = { ('<font size="18" color="%s"><b>%s</b></font>'):format(Ui.quality(item.Quality), item.Name or "?") }
	if item.Slot or item.Class then
		table.insert(lines, ('<font color="#FFFFFF">%s</font>%s'):format(cap(item.Slot or item.Class),
			if item.Slot and item.Class then ('   <font color="#AAAAAA">%s</font>'):format(cap(item.Class)) else ""))
	end
	if (item.Armor or 0) > 0 then table.insert(lines, ('<font color="#FFFFFF">%d Armor</font>'):format(item.Armor)) end
	if (item.Damage or 0) > 0 then table.insert(lines, ('<font color="#1EFF00">+%d Melee Damage</font>'):format(item.Damage)) end
	if (item.Health or 0) > 0 then table.insert(lines, ('<font color="#1EFF00">+%d Health</font>'):format(item.Health)) end
	if (item.Level or 1) > 1 then
		local mine = player:GetAttribute("CharacterLevel") or 1
		table.insert(lines, ('<font color="%s">Requires Level %d</font>'):format(if mine >= item.Level then "#FFFFFF" else "#FF2020", item.Level))
	end
	if price then table.insert(lines, ('<font color="#FFD700">%s</font>'):format(price)) end
	return table.concat(lines, "\n")
end

-- Border colour for an item's tooltip.
function Ui.itemBorder(item): Color3
	return Color3.fromHex(Ui.quality(item.Quality))
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
tip.TextSize = 14
tip.LineHeight = 1.15
tip.TextColor3 = Color3.new(1, 1, 1)
tip.TextXAlignment = Enum.TextXAlignment.Left
tip.RichText = true
tip.Visible = false
tip.Parent = tipGui
Instance.new("UICorner", tip).CornerRadius = UDim.new(0, 5)
local tipStroke = Instance.new("UIStroke", tip)
tipStroke.Color = Ui.BORDER
tipStroke.Thickness = 1.5
local pad = Instance.new("UIPadding", tip)
pad.PaddingLeft, pad.PaddingRight, pad.PaddingTop, pad.PaddingBottom = UDim.new(0, 12), UDim.new(0, 12), UDim.new(0, 8), UDim.new(0, 8)
local minWidth = Instance.new("UISizeConstraint", tip)
minWidth.MinSize = Vector2.new(200, 0)
tipGui.Parent = player:WaitForChild("PlayerGui")

-- Keep the tooltip on screen, flipping to the other side of the cursor when needed.
local function place(x: number, y: number)
	local view = workspace.CurrentCamera.ViewportSize
	local size = tip.AbsoluteSize
	local px = if x + 18 + size.X > view.X then x - 18 - size.X else x + 18
	local py = if y + 18 + size.Y > view.Y then y - 18 - size.Y else y + 18
	tip.Position = UDim2.fromOffset(math.max(px, 4), math.max(py, 4))
end
UserInputService.InputChanged:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseMovement and tip.Visible then
		place(input.Position.X, input.Position.Y)
	end
end)

function Ui.showTip(text: string, border: Color3?)
	tip.Text = text
	tipStroke.Color = border or Ui.BORDER
	tip.Visible = true
	local m = UserInputService:GetMouseLocation()
	task.defer(place, m.X, m.Y)
end

function Ui.hideTip()
	tip.Visible = false
end

return Ui
