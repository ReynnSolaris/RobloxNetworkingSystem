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
local vendorOpen = script.Parent:WaitForChild("VendorOpen") :: BindableEvent

-- The backpack on B: a grid of bag slots. Right-click a tile to equip gear, or to
-- sell the stack while a vendor window is open. Opens with any vendor.

local scope = Fusion.scoped(Fusion)
local Children, OnEvent = Fusion.Children, Fusion.OnEvent

local COLUMNS, TILE, GAP = 4, 58, 6

local open = scope:Value(false)
local inventory = Components.attribute(scope, player, "Inventory", "[]")
local money = Components.attribute(scope, player, "Money", 0)
local bagSlots = Components.attribute(scope, player, "BagSlots", Config.BagSlots)
local vendorGuid = Components.attribute(scope, player, "VendorGuid", nil)
local vendorShowing = scope:Value(false)
local held = scope:Value(nil :: number?) -- bag slot picked up with a left click
local chatInsert = script.Parent:WaitForChild("ChatInsert") :: BindableEvent

local function decode(json: string)
	local ok, value = pcall(HttpService.JSONDecode, HttpService, json)
	return if ok and typeof(value) == "table" then value else {}
end

-- slot number -> stack
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

local function tile(scope, slot: number)
	local stack = scope:Computed(function(use)
		return use(bySlot)[slot]
	end)
	local hovered = scope:Value(false)
	local row, col = (slot - 1) // COLUMNS, (slot - 1) % COLUMNS
	return scope:New "TextButton" {
		Position = UDim2.fromOffset(12 + col * (TILE + GAP), 12 + row * (TILE + GAP)),
		Size = UDim2.fromOffset(TILE, TILE),
		AutoButtonColor = false,
		BorderSizePixel = 0,
		BackgroundColor3 = scope:Computed(function(use)
			return if use(hovered) and use(stack) then Ui.ROW_HOVER else Ui.ROW
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
			local s = Fusion.peek(stack)
			if s then
				local hint = if s.Slot then "Right-click to equip" else ""
				hint = hint .. (if hint ~= "" then "\n" else "") .. "Click to move, Shift-click to link"
				if Fusion.peek(vendorShowing) then
					hint = "Right-click to sell for " .. Ui.money((s.Sell or 0) * (s.Count or 1))
				end
				Ui.showTip(Ui.itemTooltip(s) .. (if hint ~= "" then "\n" .. hint else ""))
			end
		end,
		[OnEvent "MouseLeave"] = function()
			hovered:set(false)
			Ui.hideTip()
		end,
		[OnEvent "MouseButton1Click"] = function()
			local s = Fusion.peek(stack)
			local shift = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
			if shift and s then
				chatInsert:Fire("[" .. (s.Name or "?") .. "]")
				return
			end
			local from = Fusion.peek(held)
			if from == nil then
				if s then
					held:set(slot)
				end
			elseif from == slot then
				held:set(nil)
			else
				netSend:Fire(Opcodes.CMSG_SWAP_INV_ITEM, { From = from, To = slot })
				held:set(nil)
			end
		end,
		[OnEvent "MouseButton2Click"] = function()
			local s = Fusion.peek(stack)
			if not s then
				return
			end
			if Fusion.peek(vendorShowing) then
				netSend:Fire(Opcodes.CMSG_VENDOR_SELL, { Guid = Fusion.peek(vendorGuid), Bag = slot })
			elseif s.Slot then
				netSend:Fire(Opcodes.CMSG_EQUIP, { Bag = slot })
			end
		end,
		[Children] = {
			scope:New "UICorner" { CornerRadius = UDim.new(0, 4) },
			scope:New "UIStroke" {
				Thickness = scope:Computed(function(use)
					return if use(held) == slot then 3 else 2
				end),
				Color = scope:Computed(function(use)
					if use(held) == slot then
						return Color3.new(1, 1, 1)
					end
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

-- The vendor window tells us when it closes by clearing VendorGuid.
player:GetAttributeChangedSignal("VendorGuid"):Connect(function()
	if player:GetAttribute("VendorGuid") == nil then
		vendorShowing:set(false)
	end
end)
