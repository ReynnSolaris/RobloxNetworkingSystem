local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Fusion = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Fusion"))
local Opcodes = require(ReplicatedStorage.Shared.Opcodes)
local Config = require(ReplicatedStorage.Shared.Config)
local Ui = require(script.Parent:WaitForChild("Ui"))
local Components = require(script.Parent:WaitForChild("Components"))
local Drag = require(script.Parent:WaitForChild("Drag"))
local Preview = require(script.Parent:WaitForChild("Preview"))
local player = Players.LocalPlayer
local netSend = script.Parent:WaitForChild("NetSend") :: BindableEvent

-- Character sheet on C, WoW's paper doll: a column of slots each side of a
-- turning preview of the character, weapons beneath, and the stat sheet below
-- in Attributes, Melee, Spell and Defense blocks with the total item score.
-- Drop a bag item on a slot to equip it, drag a slot to the bag or right-click
-- to unequip, Shift or Alt over an item compares with what is worn.

local scope = Fusion.scoped(Fusion)
local Children, OnEvent, peek = Fusion.Children, Fusion.OnEvent, Fusion.peek

local TILE, GAP = 46, 6
local LEFT = { "head", "neck", "shoulders", "back", "chest", "wrist", "hands", "waist" }
local RIGHT = { "legs", "feet", "ring", "ring2", "trinket", "trinket2" }
local BOTTOM = { "mainhand", "offhand" }
local WIDTH, HEIGHT = 480, 640

local open = scope:Value(false)
local equipment = Components.attribute(scope, player, "Equipment", "{}")
local stats = Components.attribute(scope, player, "Stats", "{}")
local money = Components.attribute(scope, player, "Money", 0)
local level = Components.attribute(scope, player, "CharacterLevel", 1)
local charName = Components.attribute(scope, player, "CharacterName", player.DisplayName)
local charClass = Components.attribute(scope, player, "CharacterClass", "")
local charRace = Components.attribute(scope, player, "CharacterRace", "")
local honor = Components.attribute(scope, player, "Honor", 0)
local honorKills = Components.attribute(scope, player, "HonorKills", 0)

local function decode(json: string, default)
	local ok, value = pcall(HttpService.JSONDecode, HttpService, json)
	return if ok and typeof(value) == "table" then value else default
end

local worn = scope:Computed(function(use)
	return decode(use(equipment), {})
end)
local gearScore = scope:Computed(function(use)
	local total = 0
	for slot, item in use(worn) do
		if slot:sub(1, 3) ~= "bag" then
			total += Ui.itemScore(item)
		end
	end
	return total
end)

local function abbreviation(name: string): string
	local first, second = name:match("^(%w)%w*%s+(%w)")
	return (first and (first .. second) or name:sub(1, 2)):upper()
end

local function slotTile(scope, slotName: string, position: UDim2, labelRight: boolean)
	local item = scope:Computed(function(use)
		return use(worn)[slotName]
	end)
	local hovered = scope:Value(false)
	local function showTip()
		local i = peek(item)
		if i and not Drag.active() then
			Ui.showItemTip(i, if i.Use then "Right-click to use, drag to the bag to unequip" else "Right-click to unequip")
		elseif peek(hovered) then
			Ui.hideTip()
		end
	end
	scope:Observer(item):onChange(function()
		if peek(hovered) then
			task.defer(showTip)
		end
	end)
	local button = scope:New "TextButton" {
		Position = position,
		Size = UDim2.fromOffset(TILE, TILE),
		AutoButtonColor = false,
		BorderSizePixel = 0,
		BackgroundColor3 = scope:Computed(function(use)
			return if use(hovered) then Ui.ROW_HOVER else Ui.ROW
		end),
		Font = Enum.Font.GothamBold,
		TextSize = 15,
		TextColor3 = scope:Computed(function(use)
			local i = use(item)
			return if i then Color3.fromHex(Ui.quality(i.Quality)) else Color3.fromRGB(70, 70, 80)
		end),
		Text = scope:Computed(function(use)
			local i = use(item)
			return if i then abbreviation(i.Name or "?") else ""
		end),
		[OnEvent "MouseEnter"] = function()
			hovered:set(true)
			showTip()
		end,
		[OnEvent "MouseLeave"] = function()
			hovered:set(false)
			Ui.hideTip()
		end,
		[OnEvent "MouseButton1Down"] = function()
			local i = peek(item)
			if not i then
				return
			end
			if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.RightShift) then
				local insert = script.Parent:FindFirstChild("ChatInsert")
				if insert then
					insert:Fire("[" .. (i.Name or "?") .. "]")
				end
				return
			end
			Ui.hideTip()
			Drag.begin({ Equip = slotName, Item = i }, abbreviation(i.Name or "?"), Color3.fromHex(Ui.quality(i.Quality)))
		end,
		[OnEvent "MouseButton2Click"] = function()
			local i = peek(item)
			if i and i.Use then
				netSend:Fire(Opcodes.CMSG_USE_ITEM, { Bag = slotName })
			elseif i then
				netSend:Fire(Opcodes.CMSG_UNEQUIP, { Slot = slotName })
			end
		end,
		[Children] = {
			scope:New "UICorner" { CornerRadius = UDim.new(0, 4) },
			scope:New "UIStroke" {
				Thickness = 2,
				Color = scope:Computed(function(use)
					local i = use(item)
					if i and i.MaxDurability and (i.Durability or 0) == 0 then
						return Color3.fromRGB(255, 40, 40)
					end
					return if i then Color3.fromHex(Ui.quality(i.Quality)) else Color3.fromRGB(45, 45, 55)
				end),
			},
			scope:New "TextLabel" {
				Position = if labelRight then UDim2.fromOffset(TILE + 6, 0) else UDim2.fromOffset(-70, 0),
				Size = UDim2.fromOffset(64, TILE),
				BackgroundTransparency = 1,
				Font = Enum.Font.Gotham,
				TextSize = 11,
				TextColor3 = Ui.DIM,
				TextXAlignment = if labelRight then Enum.TextXAlignment.Left else Enum.TextXAlignment.Right,
				TextWrapped = true,
				Text = Ui.SLOT_NAMES[slotName] or slotName,
			},
		},
	}
	Drag.target(button, function(payload)
		local accepts = payload.Item and (payload.Item.Slot == slotName or (Config.PairedSlots[payload.Item.Slot] and table.find(Config.PairedSlots[payload.Item.Slot], slotName)))
		if payload.Bag and accepts then
			netSend:Fire(Opcodes.CMSG_EQUIP, { Bag = payload.Bag })
		end
	end)
	return button
end

local tiles = {}
for i, slotName in LEFT do
	table.insert(tiles, slotTile(scope, slotName, UDim2.fromOffset(84, 8 + (i - 1) * (TILE + GAP)), false))
end
for i, slotName in RIGHT do
	table.insert(tiles, slotTile(scope, slotName, UDim2.fromOffset(WIDTH - 84 - TILE, 8 + (i - 1) * (TILE + GAP)), true))
end
for i, slotName in BOTTOM do
	table.insert(tiles, slotTile(scope, slotName, UDim2.fromOffset(WIDTH / 2 - TILE - 10 + (i - 1) * (TILE + 20), 8 + #LEFT * (TILE + GAP)), i == 2))
end

local statsTop = 8 + #LEFT * (TILE + GAP) + TILE + 14
local function block(title: string, x: number, lines)
	return scope:New "Frame" {
		Position = UDim2.fromOffset(x, statsTop),
		Size = UDim2.fromOffset((WIDTH - 36) / 2, 110),
		BackgroundColor3 = Color3.fromRGB(20, 18, 14),
		BackgroundTransparency = 0.3,
		BorderSizePixel = 0,
		[Children] = {
			scope:New "UICorner" { CornerRadius = UDim.new(0, 6) },
			Components.Text(scope, { Position = UDim2.fromOffset(10, 4), Size = UDim2.new(1, -20, 0, 18), Font = Enum.Font.GothamBold, TextSize = 12, Color = Ui.GOLD, Text = title }),
			Components.Text(scope, { Position = UDim2.fromOffset(10, 24), Size = UDim2.new(1, -20, 1, -28), TextSize = 12, Color = Color3.fromRGB(220, 220, 230), Wrapped = true, Text = lines }),
		},
	}
end
local statText = scope:Computed(function(use)
	return decode(use(stats), {})
end)
local blocks = {
	block("Attributes", 12, scope:Computed(function(use)
		local s = use(statText)
		return ("Strength %d\nAgility %d\nStamina %d\nIntellect %d\nSpirit %d"):format(s.Strength or 0, s.Agility or 0, s.Stamina or 0, s.Intellect or 0, s.Spirit or 0)
	end)),
	block("Melee and Spell", 24 + (WIDTH - 36) / 2, scope:Computed(function(use)
		local s = use(statText)
		return ("Melee damage +%d\nCrit chance %.1f%%\nSpell power %d\nMana %d"):format(s.Damage or 0, s.Crit or 0, s.SpellPower or 0, s.Mana or 0)
	end)),
}
local defense = scope:New "Frame" {
	Position = UDim2.fromOffset(12, statsTop + 118),
	Size = UDim2.new(1, -24, 0, 66),
	BackgroundColor3 = Color3.fromRGB(20, 18, 14),
	BackgroundTransparency = 0.3,
	BorderSizePixel = 0,
	[Children] = {
		scope:New "UICorner" { CornerRadius = UDim.new(0, 6) },
		Components.Text(scope, { Position = UDim2.fromOffset(10, 4), Size = UDim2.new(1, -20, 0, 18), Font = Enum.Font.GothamBold, TextSize = 12, Color = Ui.GOLD, Text = "Defense and Honor" }),
		Components.Text(scope, { Position = UDim2.fromOffset(10, 24), Size = UDim2.new(1, -20, 1, -28), TextSize = 12, Color = Color3.fromRGB(220, 220, 230), Wrapped = true, Text = scope:Computed(function(use)
			local s = use(statText)
			return ("Health %d    Armor %d    Dodge %.1f%%\nHonor %d    Honorable kills %d    Item score %d"):format(s.Health or 0, s.Armor or 0, s.Dodge or 0, use(honor) or 0, use(honorKills) or 0, use(gearScore))
		end) }),
	},
}

Components.Panel(scope, {
	Name = "CharacterSheet",
	Size = UDim2.fromOffset(WIDTH, HEIGHT),
	Position = UDim2.new(0.5, -360, 0.5, 0),
	Enabled = open,
	Parent = player:WaitForChild("PlayerGui"),
	Title = scope:Computed(function(use)
		return ("%s, Level %d %s %s"):format(use(charName), use(level), use(charRace), use(charClass))
	end),
	[Children] = {
		scope:New "Frame" {
			Position = UDim2.fromOffset(84 + TILE + 8, 8),
			Size = UDim2.fromOffset(WIDTH - 2 * (84 + TILE + 8), #LEFT * (TILE + GAP) - GAP),
			BackgroundColor3 = Color3.fromRGB(20, 18, 14),
			BackgroundTransparency = 0.4,
			BorderSizePixel = 0,
			[Children] = {
				scope:New "UICorner" { CornerRadius = UDim.new(0, 6) },
				Preview.new(scope, { Size = UDim2.fromScale(1, 1), Race = charRace, Class = charClass, Visible = open }),
			},
		},
		tiles,
		blocks,
		defense,
		Components.Text(scope, { Size = UDim2.new(1, -24, 0, 20), Position = UDim2.new(0, 12, 1, -26), Color = Ui.GOLD, Align = Enum.TextXAlignment.Right, Text = scope:Computed(function(use)
			return Ui.money(use(money))
		end) }),
	},
})

UserInputService.InputBegan:Connect(function(input, processed)
	if processed or player:GetAttribute("InWorld") ~= true then
		return
	end
	if input.KeyCode == Enum.KeyCode.C then
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
