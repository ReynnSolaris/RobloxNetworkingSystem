local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Fusion = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Fusion"))
local Opcodes = require(ReplicatedStorage.Shared.Opcodes)
local Config = require(ReplicatedStorage.Shared.Config)
local Ui = require(script.Parent:WaitForChild("Ui"))
local Components = require(script.Parent:WaitForChild("Components"))
local player = Players.LocalPlayer
local netSend = script.Parent:WaitForChild("NetSend") :: BindableEvent

-- Character sheet on C, built with Fusion: equipped slots and stats. Click a slot
-- to unequip; equipping is done from the backpack (B).

local scope = Fusion.scoped(Fusion)
local Children = Fusion.Children

local function decode(json: string, default)
	local ok, value = pcall(HttpService.JSONDecode, HttpService, json)
	return if ok and typeof(value) == "table" then value else default
end

local open = scope:Value(false)
local equipment = Components.attribute(scope, player, "Equipment", "{}")
local stats = Components.attribute(scope, player, "Stats", "{}")
local money = Components.attribute(scope, player, "Money", 0)
local level = Components.attribute(scope, player, "CharacterLevel", 1)
local charName = Components.attribute(scope, player, "CharacterName", player.DisplayName)
local charClass = Components.attribute(scope, player, "CharacterClass", "")

local slotRows = scope:Computed(function(use)
	local equipped = decode(use(equipment), {})
	local rows = {}
	for _, slot in Config.Slots do
		local item = equipped[slot]
		table.insert(rows, {
			Text = ('<font color="#AAAAAA">%s</font>  %s'):format(slot, if item then Ui.itemName(item) else '<font color="#555555">empty</font>'),
			Tooltip = if item then Ui.itemTooltip(item) .. "\nClick to unequip" else nil,
			OnClick = if item then function()
				netSend:Fire(Opcodes.CMSG_UNEQUIP, { Slot = slot })
			end else nil,
		})
	end
	return rows
end)

Components.Panel(scope, {
	Name = "CharacterSheet",
	Size = UDim2.fromOffset(340, 400),
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
		Components.List(scope, { Size = UDim2.new(1, -24, 1, -84), Position = UDim2.fromOffset(12, 52), Rows = slotRows }),
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
		open:set(not Fusion.peek(open))
		if Fusion.peek(open) then
			netSend:Fire(Opcodes.CMSG_INVENTORY, {})
		end
	elseif input.KeyCode == Enum.KeyCode.Escape then
		open:set(false)
	end
end)
player:GetAttributeChangedSignal("InWorld"):Connect(function()
	if player:GetAttribute("InWorld") ~= true then
		open:set(false)
	end
end)
