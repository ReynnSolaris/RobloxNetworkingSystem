-- Theme, text helpers and the shared tooltip. Window layout lives in Components.
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
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

-- "12g 34s 56c" in coin colours (rich text; every label here renders rich text).
function Ui.money(copper: number): string
	copper = math.max(0, math.floor(copper or 0))
	local g, s, c = copper // 10000, (copper % 10000) // 100, copper % 100
	local parts = {}
	if g > 0 then table.insert(parts, ('<font color="#FFD700">%dg</font>'):format(g)) end
	if s > 0 then table.insert(parts, ('<font color="#C7C7CF">%ds</font>'):format(s)) end
	if c > 0 or #parts == 0 then table.insert(parts, ('<font color="#EDA55F">%dc</font>'):format(c)) end
	return table.concat(parts, " ")
end

function Ui.itemName(item): string
	local count = if (item.Count or 1) > 1 then " x" .. item.Count else ""
	return ('<font color="%s">[%s]</font>%s'):format(Ui.quality(item.Quality), item.Name or "?", count)
end

local SLOT_NAMES = { head = "Head", chest = "Chest", legs = "Legs", feet = "Feet", mainhand = "Main Hand", ring = "Finger", trinket = "Trinket" }
local CLASS_NAMES = { armor = "Armor", weapon = "Weapon", consumable = "Consumable", misc = "Miscellaneous" }

-- WoW item tooltip: name in quality colour, binding, slot and type, armor, green
-- stats, level requirement (red when too low), Use line, flavour, sell price.
-- `price` replaces the sell line (vendor cost, buyback).
function Ui.itemTooltip(item, price: string?): string
	local lines = { ('<font size="17" color="%s"><b>%s</b></font>'):format(Ui.quality(item.Quality), item.Name or "?") }
	local function white(text: string)
		table.insert(lines, '<font color="#FFFFFF">' .. text .. "</font>")
	end
	if item.Slot then
		white("Binds when equipped")
		white(("%s%s"):format(SLOT_NAMES[item.Slot] or item.Slot, if item.Class then ('<font color="#AAAAAA">   %s</font>'):format(CLASS_NAMES[item.Class] or item.Class) else ""))
	elseif item.Class and item.Class ~= "misc" then
		white(CLASS_NAMES[item.Class] or item.Class)
	end
	if (item.Armor or 0) > 0 then white(("%d Armor"):format(item.Armor)) end
	if (item.Damage or 0) > 0 then table.insert(lines, ('<font color="#1EFF00">+%d Melee Damage</font>'):format(item.Damage)) end
	if (item.Health or 0) > 0 then table.insert(lines, ('<font color="#1EFF00">+%d Health</font>'):format(item.Health)) end
	if (item.Level or 1) > 1 then
		local mine = player:GetAttribute("CharacterLevel") or 1
		table.insert(lines, ('<font color="%s">Requires Level %d</font>'):format(if mine >= item.Level then "#FFFFFF" else "#FF2020", item.Level))
	end
	if item.Use then table.insert(lines, ('<font color="#1EFF00">Use: %s</font>'):format(item.Use)) end
	if item.Flavor then table.insert(lines, ('<font color="#FFD100"><i>"%s"</i></font>'):format(item.Flavor)) end
	if (item.Stack or 1) > 1 then table.insert(lines, ('<font color="#AAAAAA">Max Stack: %d</font>'):format(item.Stack)) end
	if price then
		white(price)
	elseif (item.Sell or 0) > 0 then
		white("Sell Price: " .. Ui.money(item.Sell * (item.Count or 1)))
	end
	return table.concat(lines, "\n")
end

-- Border colour for an item's tooltip.
function Ui.itemBorder(item): Color3
	return Color3.fromHex(Ui.quality(item.Quality))
end

-- One tooltip for everything. Like WoW's GameTooltip it does not follow the
-- mouse: over a UI element it sits beside that element (right of it, or left
-- when there is no room); over the world it sits in the bottom right corner.
local tipGui = Instance.new("ScreenGui")
tipGui.Name = "Tooltip"
tipGui.ResetOnSpawn = false
tipGui.DisplayOrder = 50
tipGui.IgnoreGuiInset = true
local tip = Instance.new("Frame")
tip.AutomaticSize = Enum.AutomaticSize.XY
tip.BackgroundColor3 = Color3.fromRGB(6, 6, 12)
tip.BackgroundTransparency = 0.08
tip.BorderSizePixel = 0
tip.Visible = false
tip.Parent = tipGui
Instance.new("UICorner", tip).CornerRadius = UDim.new(0, 4)
local tipStroke = Instance.new("UIStroke", tip)
tipStroke.Color = Ui.BORDER
tipStroke.Thickness = 1.5
tipStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
local gradient = Instance.new("UIGradient", tip)
gradient.Color = ColorSequence.new(Color3.fromRGB(26, 26, 48), Color3.fromRGB(6, 6, 12))
gradient.Rotation = 90
local pad = Instance.new("UIPadding", tip)
pad.PaddingLeft, pad.PaddingRight, pad.PaddingTop, pad.PaddingBottom = UDim.new(0, 12), UDim.new(0, 12), UDim.new(0, 9), UDim.new(0, 9)
local tipText = Instance.new("TextLabel")
tipText.AutomaticSize = Enum.AutomaticSize.XY
tipText.BackgroundTransparency = 1
tipText.Font = Enum.Font.Gotham
tipText.TextSize = 14
tipText.LineHeight = 1.2
tipText.TextColor3 = Color3.new(1, 1, 1)
tipText.TextXAlignment = Enum.TextXAlignment.Left
tipText.TextYAlignment = Enum.TextYAlignment.Top
tipText.RichText = true
tipText.Parent = tip
local size = Instance.new("UISizeConstraint", tipText)
size.MinSize = Vector2.new(180, 0)
size.MaxSize = Vector2.new(340, math.huge)
tipText.TextWrapped = true
tipGui.Parent = player:WaitForChild("PlayerGui")

local function clamp(x: number, y: number, w: number, h: number): UDim2
	local view = workspace.CurrentCamera.ViewportSize
	return UDim2.fromOffset(math.clamp(x, 6, math.max(6, view.X - w - 6)), math.clamp(y, 6, math.max(6, view.Y - h - 6)))
end

-- The UI element under the mouse, ignoring the tooltip itself and plain containers.
local function elementUnderMouse(): GuiObject?
	local m = UserInputService:GetMouseLocation()
	for _, gui in player.PlayerGui:GetGuiObjectsAtPosition(m.X, m.Y - GuiService:GetGuiInset().Y) do
		if not gui:IsDescendantOf(tipGui) and (gui:IsA("GuiButton") or gui:IsA("TextLabel") or gui:IsA("TextBox")) then
			return gui
		end
	end
	return nil
end

local function place(anchor: GuiObject | boolean | nil)
	local view = workspace.CurrentCamera.ViewportSize
	local w, h = tip.AbsoluteSize.X, tip.AbsoluteSize.Y
	if anchor == nil then
		anchor = elementUnderMouse() or false
	end
	if typeof(anchor) == "Instance" then
		local screen = anchor:FindFirstAncestorOfClass("ScreenGui")
		local inset = if screen and not screen.IgnoreGuiInset then GuiService:GetGuiInset().Y else 0
		local p, s = anchor.AbsolutePosition, anchor.AbsoluteSize
		local x = p.X + s.X + 6
		if x + w > view.X - 6 then
			x = p.X - w - 6
		end
		tip.Position = clamp(x, p.Y + inset + s.Y - h, w, h)
	else
		tip.Position = clamp(view.X - w - 16, view.Y - h - 90, w, h)
	end
end

-- anchor: a GuiObject to sit beside, false for the screen corner, nil to use
-- whatever UI element is under the mouse.
function Ui.showTip(text: string, border: Color3?, anchor: GuiObject | boolean | nil)
	tipText.Text = text
	tipStroke.Color = border or Ui.BORDER
	tip.Visible = true
	place(anchor)
	task.defer(place, anchor) -- once more after AutomaticSize has settled
end

function Ui.hideTip()
	tip.Visible = false
end

-- Mouseover tooltip for creatures and players in the world, WoW style in the
-- corner; UI under the mouse wins.
local hovering: Instance? = nil
task.spawn(function()
	local mouse = player:GetMouse()
	while true do
		task.wait(0.1)
		local target = mouse.Target
		local model = target and target:FindFirstAncestorOfClass("Model")
		local show = nil
		if model and player:GetAttribute("InWorld") == true and not elementUnderMouse() then
			local creatures = workspace:FindFirstChild("Creatures")
			local other = Players:GetPlayerFromCharacter(model)
			if model.Parent == creatures and model:GetAttribute("Guid") then
				local hostile = model:GetAttribute("Faction") == "hostile"
				local humanoid = model:FindFirstChildOfClass("Humanoid")
				show = ('<font size="16" color="%s"><b>%s</b></font>%s\n<font color="#FFFFFF">Level %s %s</font>%s'):format(
					if hostile then "#FF5A5A" else "#5ADC5A", model.Name,
					if model:GetAttribute("Subname") then ('\n<font color="#AAAAAA">&lt;%s&gt;</font>'):format(model:GetAttribute("Subname")) else "",
					tostring(model:GetAttribute("Level") or "?"), if hostile then "Hostile" else "Friendly",
					if humanoid and humanoid.Health <= 0 then '\n<font color="#AAAAAA">Dead</font>' else "")
			elseif other and other ~= player then
				local class = other:GetAttribute("CharacterClass")
				local color = "#FFFFFF"
				for _, c in Config.Classes do
					if c.Name == class then
						color = c.Color
					end
				end
				show = ('<font size="16" color="%s"><b>%s</b></font>%s\n<font color="#FFFFFF">Level %d %s</font>'):format(color,
					other:GetAttribute("CharacterName") or other.DisplayName,
					if other:GetAttribute("Guild") then ('\n<font color="#40FB40">&lt;%s&gt;</font>'):format(other:GetAttribute("Guild")) else "",
					other:GetAttribute("CharacterLevel") or 1, class or "")
			end
		end
		if show then
			hovering = model
			Ui.showTip(show, Ui.BORDER, false)
		elseif hovering then
			hovering = nil
			if tip.Visible and not elementUnderMouse() then
				Ui.hideTip()
			end
		end
	end
end)

return Ui
