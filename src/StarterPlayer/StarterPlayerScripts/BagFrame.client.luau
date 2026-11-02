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
local vendorOpen = script.Parent:WaitForChild("VendorOpen") :: BindableEvent
local chatInsert = script.Parent:WaitForChild("ChatInsert") :: BindableEvent

-- The backpack on B: a grid of bag slots. Drag a stack onto another slot to move
-- or swap it, onto an equipment slot to equip, onto a vendor to sell. Right-click
-- equips, or sells while a vendor is open. Shift-click links the item in chat.

local scope = Fusion.scoped(Fusion)
local Children, OnEvent, peek = Fusion.Children, Fusion.OnEvent, Fusion.peek

local COLUMNS, TILE, GAP = 4, 58, 6

local open = scope:Value(false)
local inventory = Components.attribute(scope, player, "Inventory", "[]")
local money = Components.attribute(scope, player, "Money", 0)
local bagSlots = Components.attribute(scope, player, "BagSlots", Config.BagSlots)
local vendorGuid = Components.attribute(scope, player, "VendorGuid", nil)
local vendorShowing = scope:Value(false)

local function decode(json: string)
	local ok, value = pcall(HttpService.JSONDecode, HttpService, json)
	return if ok and typeof(value) == "table" then value else {}
end

local bySlot = scope:Computed(function(use)
	local map = {}
	for _, stack in decode(use(inventory)) do
		map[stack.Bag or 0] = stack
	end
	return map
end)

local function abbreviation(name: string): string
	local first, second = name:match("^(%w)%w*%s+(%w)")
	return (first and (first .. second) or name:sub(1, 2)):upper()
end

local function shiftHeld(): boolean
	return UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
end

local function tile(scope, slot: number)
	local stack = scope:Computed(function(use)
		return use(bySlot)[slot]
	end)
	local hovered = scope:Value(false)
	local row, col = (slot - 1) // COLUMNS, (slot - 1) % COLUMNS
	local button = scope:New "TextButton" {
		Position = UDim2.fromOffset(12 + col * (TILE + GAP), 12 + row * (TILE + GAP)),
		Size = UDim2.fromOffset(TILE, TILE),
		AutoButtonColor = false,
		BorderSizePixel = 0,
		BackgroundColor3 = scope:Computed(function(use)
			return if use(hovered) then Ui.ROW_HOVER else Ui.ROW
		end),
		Font = Enum.Font.GothamBold,
		TextSize = 18,
		TextColor3 = scope:Computed(function(use)
			local s = use(stack)
			return if s then Color3.fromHex(Ui.quality(s.Quality)) else Color3.fromRGB(60, 60, 70)
		end),
		Text = scope:Computed(function(use)
			local s = use(stack)
			return if s then abbreviation(s.Name or "?") else ""
		end),
		[OnEvent "MouseEnter"] = function()
			hovered:set(true)
			local s = peek(stack)
			if s and not Drag.active() then
				local hint = if peek(vendorShowing) then "Right-click to sell for " .. Ui.money((s.Sell or 0) * (s.Count or 1))
					elseif s.Slot then "Right-click to equip" else nil
				Ui.showTip(Ui.itemTooltip(s) .. (if hint then '\n<font color="#AAAAAA">' .. hint .. "</font>" else ""), Ui.itemBorder(s))
			end
		end,
		[OnEvent "MouseLeave"] = function()
			hovered:set(false)
			Ui.hideTip()
		end,
		[OnEvent "MouseButton1Down"] = function()
			local s = peek(stack)
			if not s then
				return
			end
			if shiftHeld() then
				chatInsert:Fire("[" .. (s.Name or "?") .. "]")
				return
			end
			Ui.hideTip()
			Drag.begin({ Bag = slot, Item = s }, abbreviation(s.Name or "?"), Color3.fromHex(Ui.quality(s.Quality)))
		end,
		[OnEvent "MouseButton2Click"] = function()
			local s = peek(stack)
			if not s then
				return
			end
			if peek(vendorShowing) then
				netSend:Fire(Opcodes.CMSG_VENDOR_SELL, { Guid = peek(vendorGuid), Bag = slot })
			elseif s.Slot then
				netSend:Fire(Opcodes.CMSG_EQUIP, { Bag = slot })
			end
		end,
		[Children] = {
			scope:New "UICorner" { CornerRadius = UDim.new(0, 4) },
			scope:New "UIStroke" {
				Thickness = 2,
				Color = scope:Computed(function(use)
					local s = use(stack)
					return if s then Color3.fromHex(Ui.quality(s.Quality)) else Color3.fromRGB(45, 45, 55)
				end),
			},
			scope:New "TextLabel" {
				AnchorPoint = Vector2.new(1, 1),
				Position = UDim2.new(1, -3, 1, -1),
				Size = UDim2.fromOffset(24, 14),
				BackgroundTransparency = 1,
				Font = Enum.Font.GothamBold,
				TextSize = 12,
				TextColor3 = Color3.new(1, 1, 1),
				TextXAlignment = Enum.TextXAlignment.Right,
				Text = scope:Computed(function(use)
					local s = use(stack)
					return if s and (s.Count or 1) > 1 then tostring(s.Count) else ""
				end),
			},
		},
	}
	Drag.target(button, function(payload)
		if payload.Bag and payload.Bag ~= slot then
			netSend:Fire(Opcodes.CMSG_SWAP_INV_ITEM, { From = payload.Bag, To = slot })
		elseif payload.Equip then
			netSend:Fire(Opcodes.CMSG_UNEQUIP, { Slot = payload.Equip, To = slot })
		end
	end)
	return button
end

local tiles = scope:Computed(function(use)
	local list = {}
	for slot = 1, use(bagSlots) do
		table.insert(list, slot)
	end
	return list
end)

local rows = math.ceil(Config.BagSlots / COLUMNS)
Components.Panel(scope, {
	Name = "BagFrame",
	Size = UDim2.fromOffset(12 * 2 + COLUMNS * TILE + (COLUMNS - 1) * GAP, 36 + 12 * 2 + rows * TILE + (rows - 1) * GAP + 26),
	Position = UDim2.new(1, -170, 0.5, 60),
	Enabled = open,
	Parent = player:WaitForChild("PlayerGui"),
	Title = "Backpack",
	[Children] = {
		scope:ForValues(tiles, function(use, scope, slot)
			return tile(scope, slot)
		end),
		Components.Text(scope, { Size = UDim2.new(1, -24, 0, 20), Position = UDim2.new(0, 12, 1, -24), Color = Ui.GOLD, Align = Enum.TextXAlignment.Right, Text = scope:Computed(function(use)
			return Ui.money(use(money))
		end) }),
	},
})

vendorOpen.Event:Connect(function()
	vendorShowing:set(true)
	open:set(true)
	netSend:Fire(Opcodes.CMSG_INVENTORY, {})
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed or player:GetAttribute("InWorld") ~= true then
		return
	end
	if input.KeyCode == Enum.KeyCode.B then
		open:set(not peek(open))
		if peek(open) then
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
player:GetAttributeChangedSignal("VendorGuid"):Connect(function()
	if player:GetAttribute("VendorGuid") == nil then
		vendorShowing:set(false)
	end
end)
