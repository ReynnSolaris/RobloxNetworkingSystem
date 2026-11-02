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
local player = Players.LocalPlayer
local netSend = script.Parent:WaitForChild("NetSend") :: BindableEvent

-- Character sheet on C: equipment slots as tiles plus stats. Drop a bag item on a
-- slot to equip it, drag a slot back to the bag to unequip; right-click unequips.

local scope = Fusion.scoped(Fusion)
local Children, OnEvent, peek = Fusion.Children, Fusion.OnEvent, Fusion.peek

local TILE, GAP = 58, 8

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

local function abbreviation(name: string): string
	local first, second = name:match("^(%w)%w*%s+(%w)")
	return (first and (first .. second) or name:sub(1, 2)):upper()
end

local function slotTile(scope, index: number, slotName: string)
	local item = scope:Computed(function(use)
		return use(worn)[slotName]
	end)
	local hovered = scope:Value(false)
	local col, row = (index - 1) % 2, (index - 1) // 2
	local button = scope:New "TextButton" {
		Position = UDim2.fromOffset(12 + col * (TILE + 90), 60 + row * (TILE + GAP)),
		Size = UDim2.fromOffset(TILE, TILE),
		AutoButtonColor = false,
		BorderSizePixel = 0,
		BackgroundColor3 = scope:Computed(function(use)
			return if use(hovered) then Ui.ROW_HOVER else Ui.ROW
		end),
		Font = Enum.Font.GothamBold,
		TextSize = 18,
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
			local i = peek(item)
			if i and not Drag.active() then
				Ui.showTip(Ui.itemTooltip(i) .. '\n<font color="#AAAAAA">Right-click to unequip</font>', Ui.itemBorder(i))
			end
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
			if peek(item) then
				netSend:Fire(Opcodes.CMSG_UNEQUIP, { Slot = slotName })
			end
		end,
		[Children] = {
			scope:New "UICorner" { CornerRadius = UDim.new(0, 4) },
			scope:New "UIStroke" {
				Thickness = 2,
				Color = scope:Computed(function(use)
					local i = use(item)
					return if i then Color3.fromHex(Ui.quality(i.Quality)) else Color3.fromRGB(45, 45, 55)
				end),
			},
			scope:New "TextLabel" {
				Position = UDim2.fromOffset(TILE + 8, 0),
				Size = UDim2.fromOffset(80, TILE),
				BackgroundTransparency = 1,
				Font = Enum.Font.Gotham,
				TextSize = 12,
				TextColor3 = Ui.DIM,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextWrapped = true,
				Text = slotName:sub(1, 1):upper() .. slotName:sub(2),
			},
		},
	}
	Drag.target(button, function(payload)
		if payload.Bag and payload.Item and payload.Item.Slot == slotName then
			netSend:Fire(Opcodes.CMSG_EQUIP, { Bag = payload.Bag })
		end
	end)
	return button
end

local tiles = {}
for index, slotName in Config.Slots do
	table.insert(tiles, slotTile(scope, index, slotName))
end

local rows = math.ceil(#Config.Slots / 2)
Components.Panel(scope, {
	Name = "CharacterSheet",
	Size = UDim2.fromOffset(340, 36 + 60 + rows * (TILE + GAP) + 40),
	Position = UDim2.new(0.5, -360, 0.5, 0),
	Enabled = open,
	Parent = player:WaitForChild("PlayerGui"),
	Title = scope:Computed(function(use)
		return ("%s, Level %d %s %s"):format(use(charName), use(level), use(charRace), use(charClass))
	end),
	[Children] = {
		Components.Text(scope, { Size = UDim2.new(1, -24, 0, 44), Position = UDim2.fromOffset(12, 6), TextSize = 12, Color = Ui.DIM, Wrapped = true, Text = scope:Computed(function(use)
			local s = decode(use(stats), {})
			return ("Str %d  Agi %d  Sta %d  Int %d  Spi %d\nHealth %d   Melee +%d   Spell +%d   Armor %d   Crit %.1f%%   Dodge %.1f%%"):format(
				s.Strength or 0, s.Agility or 0, s.Stamina or 0, s.Intellect or 0, s.Spirit or 0, s.Health or 0, s.Damage or 0, s.SpellPower or 0, s.Armor or 0, s.Crit or 0, s.Dodge or 0)
		end) }),
		tiles,
		Components.Text(scope, { Size = UDim2.new(0.5, -12, 0, 20), Position = UDim2.new(0, 12, 1, -26), TextSize = 12, Color = Ui.DIM, Text = scope:Computed(function(use)
			return ("Honor %d   HK %d"):format(use(honor) or 0, use(honorKills) or 0)
		end) }),
		Components.Text(scope, { Size = UDim2.new(0.5, -12, 0, 20), Position = UDim2.new(0.5, 0, 1, -26), Color = Ui.GOLD, Align = Enum.TextXAlignment.Right, Text = scope:Computed(function(use)
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
