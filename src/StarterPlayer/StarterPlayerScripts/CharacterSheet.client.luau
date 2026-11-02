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
			if i then
				Ui.hideTip()
				Drag.begin({ Equip = slotName, Item = i }, abbreviation(i.Name or "?"), Color3.fromHex(Ui.quality(i.Quality)))
			end
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
		return ("%s, Level %d %s"):format(use(charName), use(level), use(charClass))
	end),
	[Children] = {
		Components.Text(scope, { Size = UDim2.new(1, -24, 0, 40), Position = UDim2.fromOffset(12, 8), TextSize = 13, Color = Ui.DIM, Text = scope:Computed(function(use)
			local s = decode(use(stats), {})
			return ("Health %d    Melee +%d    Armor %d"):format(s.Health or 0, s.Damage or 0, s.Armor or 0)
		end) }),
		tiles,
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
