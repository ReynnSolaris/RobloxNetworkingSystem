-- Theme, text helpers and the shared tooltip. Window layout lives in Components.
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
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

local SLOT_NAMES = { head = "Head", neck = "Neck", shoulders = "Shoulder", back = "Back", chest = "Chest", wrist = "Wrist", hands = "Hands", waist = "Waist", legs = "Legs", feet = "Feet",
	mainhand = "Main Hand", offhand = "Off Hand", ring = "Finger", ring2 = "Finger", trinket = "Trinket", trinket2 = "Trinket", bag = "Bag", bag1 = "Bag", bag2 = "Bag", bag3 = "Bag", bag4 = "Bag" }
Ui.SLOT_NAMES = SLOT_NAMES
local CLASS_NAMES = { armor = "Armor", weapon = "Weapon", consumable = "Consumable", misc = "Miscellaneous", container = "Bag", reagent = "Trade Goods" }

-- WoW item tooltip: name in quality colour, binding, slot and type, armor, green
-- stats, level requirement (red when too low), Use line, flavour, sell price.
-- `price` replaces the sell line (vendor cost, buyback).
function Ui.itemTooltip(item, price: string?): string
	local lines = { ('<font size="17" color="%s"><b>%s</b></font>'):format(Ui.quality(item.Quality), item.Name or "?") }
	local function white(text: string)
		table.insert(lines, '<font color="#FFFFFF">' .. text .. "</font>")
	end
	if item.Bind == "pickup" then
		white("Binds when picked up")
	elseif item.Slot then
		white("Binds when equipped")
	end
	if item.Slot then
		local sub, armor = if typeof(item.Subclass) == "string" then item.Subclass else nil, if typeof(item.ArmorType) == "string" then item.ArmorType else nil
		local kind = if sub then (sub:sub(1, 1):upper() .. sub:sub(2)) elseif armor then (armor:sub(1, 1):upper() .. armor:sub(2)) elseif item.Class then (CLASS_NAMES[item.Class] or item.Class) else nil
		local hands = if (item.Hands or 1) == 2 then "Two-Hand" elseif item.Slot == "mainhand" and item.Class == "weapon" then "One-Hand" else nil
		-- the type goes red when your class cannot use it
		local usable = true
		for _, class in Config.Classes do
			if class.Name == player:GetAttribute("CharacterClass") and not item.AnyClass then
				if sub and not table.find(class.Weapons, sub) then usable = false end
				if armor and not table.find(class.Armor, armor) then usable = false end
			end
		end
		white(("%s%s"):format(hands or SLOT_NAMES[item.Slot] or item.Slot, if kind then ('<font color="%s">   %s</font>'):format(if usable then "#AAAAAA" else "#FF2020", kind) else ""))
	elseif item.Class and item.Class ~= "misc" then
		white(CLASS_NAMES[item.Class] or item.Class)
	end
	if (item.Armor or 0) > 0 then white(("%d Armor"):format(item.Armor)) end
	if (item.Damage or 0) > 0 then table.insert(lines, ('<font color="#1EFF00">+%d Melee Damage</font>'):format(item.Damage)) end
	if (item.Health or 0) > 0 then table.insert(lines, ('<font color="#1EFF00">+%d Health</font>'):format(item.Health)) end
	for _, stat in { "Strength", "Agility", "Stamina", "Intellect", "Spirit" } do
		if (item[stat] or 0) > 0 then white(("+%d %s"):format(item[stat], stat)) end
	end
	if (item.SpellPower or 0) > 0 then table.insert(lines, ('<font color="#1EFF00">Equip: Increases spell power by %d.</font>'):format(item.SpellPower)) end
	if (item.Level or 1) > 1 then
		local mine = player:GetAttribute("CharacterLevel") or 1
		table.insert(lines, ('<font color="%s">Requires Level %d</font>'):format(if mine >= item.Level then "#FFFFFF" else "#FF2020", item.Level))
	end
	if item.Container then white(("%d Slot Bag"):format(item.Container)) end
	if item.Proc then table.insert(lines, ('<font color="#1EFF00">%s (%d%% chance)</font>'):format(item.Proc, math.floor((item.ProcChance or 0.1) * 100 + 0.5))) end
	if item.Use then table.insert(lines, ('<font color="#1EFF00">Use: %s</font>'):format(item.Use)) end
	if item.MaxDurability then
		table.insert(lines, ('<font color="%s">Durability %d / %d%s</font>'):format(if (item.Durability or 0) == 0 then "#FF2020" else "#FFFFFF", item.Durability or 0, item.MaxDurability, if (item.Durability or 0) == 0 then "  (Broken)" else ""))
	end
	if item.Flavor then table.insert(lines, ('<font color="#FFD100"><i>"%s"</i></font>'):format(item.Flavor)) end
	if (item.Stack or 1) > 1 then table.insert(lines, ('<font color="#AAAAAA">Max Stack: %d</font>'):format(item.Stack)) end
	if item.Slot then
		table.insert(lines, ('<font color="#AAAAAA">Item Score %d</font>'):format(Ui.itemScore(item)))
	end
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

local STAT_KEYS = { "Armor", "Damage", "Health", "Strength", "Agility", "Stamina", "Intellect", "Spirit", "SpellPower" }

-- Item score: weighted stats times a quality factor, like a gear score.
function Ui.itemScore(item): number
	if not item or not item.Slot then
		return 0
	end
	local total = 0
	for _, key in STAT_KEYS do
		total += (item[key] or 0) * (Config.ItemScore.Weights[key] or 0)
	end
	return math.floor(total * (Config.ItemScore.Quality[item.Quality or 1] or 1) * 10 + 0.5)
end

-- What is worn in the paper-doll slot(s) an item would fill.
function Ui.wornFor(item): { any }
	if not item or not item.Slot then
		return {}
	end
	local ok, worn = pcall(HttpService.JSONDecode, HttpService, player:GetAttribute("Equipment") or "{}")
	worn = if ok and typeof(worn) == "table" then worn else {}
	local slots = Config.PairedSlots[item.Slot] or { item.Slot }
	local out = {}
	for _, slot in slots do
		table.insert(out, worn[slot] or false)
	end
	return out
end

-- Lines of stat differences against a worn item, WoW green and red.
function Ui.itemDiff(item, worn): string
	local lines = {}
	for _, key in STAT_KEYS do
		local delta = (item[key] or 0) - (worn and worn[key] or 0)
		if delta ~= 0 then
			table.insert(lines, ('<font color="%s">%s%d %s</font>'):format(if delta > 0 then "#1EFF00" else "#FF2020", if delta > 0 then "+" else "", delta, if key == "SpellPower" then "Spell Power" else key))
		end
	end
	local score = Ui.itemScore(item) - (if worn then Ui.itemScore(worn) else 0)
	if score ~= 0 then
		table.insert(lines, ('<font color="%s">%s%d Item Score</font>'):format(if score > 0 then "#1EFF00" else "#FF2020", if score > 0 then "+" else "", score))
	end
	return table.concat(lines, "\n")
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

-- A second frame for "Currently Equipped" comparisons, left of the main one.
local cmp = tip:Clone()
cmp.Name = "Compare"
cmp.Parent = tipGui
local cmpText = cmp:FindFirstChildOfClass("TextLabel")
local cmpStroke = cmp:FindFirstChildOfClass("UIStroke")

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

local tipAnchor: GuiObject | boolean | nil = nil

-- Is the mouse still over the element the tooltip belongs to?
local function overAnchor(): boolean
	local anchor = tipAnchor
	if typeof(anchor) ~= "Instance" then
		return true
	end
	if not anchor:IsDescendantOf(player.PlayerGui) or not anchor.Visible then
		return false
	end
	local screen = anchor:FindFirstAncestorOfClass("ScreenGui")
	if screen and not screen.Enabled then
		return false
	end
	local m = UserInputService:GetMouseLocation()
	if not (screen and screen.IgnoreGuiInset) then
		m -= GuiService:GetGuiInset()
	end
	local p, s = anchor.AbsolutePosition, anchor.AbsoluteSize
	return m.X >= p.X - 2 and m.X <= p.X + s.X + 2 and m.Y >= p.Y - 2 and m.Y <= p.Y + s.Y + 2
end

local function place(anchor: GuiObject | boolean | nil)
	local view = workspace.CurrentCamera.ViewportSize
	local w, h = tip.AbsoluteSize.X, tip.AbsoluteSize.Y
	if anchor == nil then
		anchor = elementUnderMouse() or false
	end
	tipAnchor = anchor
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

local currentItem, currentHint, currentAnchor = nil, nil, nil

local function compareHeld(): (boolean, number)
	if UserInputService:IsKeyDown(Enum.KeyCode.LeftAlt) or UserInputService:IsKeyDown(Enum.KeyCode.RightAlt) then
		return true, 2
	elseif UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.RightShift) then
		return true, 1
	end
	return false, 1
end

-- The item tooltip with everything: hint line, and while Shift (first slot) or
-- Alt (second slot of a pair) is held, the worn item beside it with the
-- differences. Re-rendered when the item under the mouse changes.
function Ui.showItemTip(item, hint: string?, anchor: GuiObject | boolean | nil)
	currentItem, currentHint, currentAnchor = item, hint, anchor
	local text = Ui.itemTooltip(item)
	local held, which = compareHeld()
	local worn = Ui.wornFor(item)
	local target = held and item.Slot and worn[which]
	if held and item.Slot and (#worn > 0) then
		local diff = Ui.itemDiff(item, target or nil)
		if diff ~= "" then
			text ..= '\n<font color="#AAAAAA">Compared to equipped:</font>\n' .. diff
		end
	end
	if hint then
		text ..= '\n<font color="#AAAAAA">' .. hint .. "</font>"
	elseif item.Slot and not held then
		text ..= '\n<font color="#666666">Shift to compare</font>'
	end
	Ui.showTip(text, Ui.itemBorder(item), anchor)
	if target then
		cmpText.Text = '<font color="#AAAAAA">Currently Equipped</font>\n' .. Ui.itemTooltip(target)
		cmpStroke.Color = Ui.itemBorder(target)
		cmp.Visible = true
		task.defer(function()
			if cmp.Visible then
				local view = workspace.CurrentCamera.ViewportSize
				local x = tip.AbsolutePosition.X - cmp.AbsoluteSize.X - 6
				if x < 6 then
					x = tip.AbsolutePosition.X + tip.AbsoluteSize.X + 6
				end
				cmp.Position = clamp(x, tip.AbsolutePosition.Y, cmp.AbsoluteSize.X, cmp.AbsoluteSize.Y)
				if x + cmp.AbsoluteSize.X > view.X then
					cmp.Position = clamp(6, tip.AbsolutePosition.Y, cmp.AbsoluteSize.X, cmp.AbsoluteSize.Y)
				end
			end
		end)
	else
		cmp.Visible = false
	end
end

function Ui.hideTip()
	tip.Visible = false
	cmp.Visible = false
	currentItem = nil
end

-- modifiers change the item tooltip while it shows
UserInputService.InputBegan:Connect(function(input)
	if currentItem and tip.Visible and (input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.LeftAlt or input.KeyCode == Enum.KeyCode.RightShift or input.KeyCode == Enum.KeyCode.RightAlt) then
		Ui.showItemTip(currentItem, currentHint, currentAnchor)
	end
end)
UserInputService.InputEnded:Connect(function(input)
	if currentItem and tip.Visible and (input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.LeftAlt or input.KeyCode == Enum.KeyCode.RightShift or input.KeyCode == Enum.KeyCode.RightAlt) then
		Ui.showItemTip(currentItem, currentHint, currentAnchor)
	end
end)

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
				local faction = model:GetAttribute("Faction")
				local hostile = faction == "hostile" or ((faction == "Alliance" or faction == "Horde") and faction ~= (player:GetAttribute("CharacterFaction") or "Alliance"))
				local humanoid = model:FindFirstChildOfClass("Humanoid")
				local rank = model:GetAttribute("Rank")
				local rankText = if rank == "boss" then " Boss" elseif rank == "elite" then " Elite" elseif rank == "rare" then " Rare" else ""
				show = ('<font size="16" color="%s"><b>%s</b></font>%s\n<font color="#FFFFFF">Level %s%s %s</font>%s'):format(
					if rank == "boss" or rank == "elite" then "#FFD100" elseif rank == "rare" then "#C0C0FF" elseif hostile then "#FF5A5A" else "#5ADC5A", model.Name,
					if model:GetAttribute("Subname") then ('\n<font color="#AAAAAA">&lt;%s&gt;</font>'):format(model:GetAttribute("Subname")) else "",
					tostring(model:GetAttribute("Level") or "?"), rankText, if hostile then "Hostile" elseif faction == "pet" then "Pet" elseif faction == "Alliance" or faction == "Horde" then faction else "Friendly",
					if humanoid and humanoid.Health <= 0 then '\n<font color="#AAAAAA">Dead</font>' else "")
			elseif other and other ~= player then
				local class = other:GetAttribute("CharacterClass")
				local color = "#FFFFFF"
				for _, c in Config.Classes do
					if c.Name == class then
						color = c.Color
					end
				end
				show = ('<font size="16" color="%s"><b>%s</b></font>%s\n<font color="#FFFFFF">Level %d %s %s</font>%s'):format(color,
					other:GetAttribute("CharacterName") or other.DisplayName,
					if other:GetAttribute("Guild") then ('\n<font color="#40FB40">&lt;%s&gt;</font>'):format(other:GetAttribute("Guild")) else "",
					other:GetAttribute("CharacterLevel") or 1, other:GetAttribute("CharacterRace") or "", class or "",
					if other:GetAttribute("PvpFlag") then '\n<font color="#FF4040">PvP</font>' else "")
			end
		end
		if tip.Visible and not overAnchor() then
			Ui.hideTip()
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
