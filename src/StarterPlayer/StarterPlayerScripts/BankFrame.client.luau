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
local bankOpen = script.Parent:WaitForChild("BankOpen") :: BindableEvent
local chatInsert = script.Parent:WaitForChild("ChatInsert") :: BindableEvent

-- Bank window from a banker's gossip: a grid of bank slots. Drag bag stacks in
-- to deposit, bank stacks onto the bag to withdraw, between bank slots to move.

local scope = Fusion.scoped(Fusion)
local Children, OnEvent, peek = Fusion.Children, Fusion.OnEvent, Fusion.peek

local COLUMNS, TILE, GAP = 6, 58, 6

local open = scope:Value(false)
local bankJson = Components.attribute(scope, player, "Bank", "[]")
local slots = Components.attribute(scope, player, "BankSlots", Config.BankSlots)
local bySlot = scope:Computed(function(use)
	local ok, list = pcall(HttpService.JSONDecode, HttpService, use(bankJson))
	local map = {}
	for _, stack in (if ok and typeof(list) == "table" then list else {}) do
		map[stack.Bank or 0] = stack
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
				Ui.showItemTip(s, "Right-click to withdraw")
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
			Drag.begin({ Bank = slot, Item = s }, abbreviation(s.Name or "?"), Color3.fromHex(Ui.quality(s.Quality)))
		end,
		[OnEvent "MouseButton2Click"] = function()
			if peek(stack) then
				netSend:Fire(Opcodes.CMSG_BANK_WITHDRAW, { Bank = slot })
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
		if payload.Bag then
			netSend:Fire(Opcodes.CMSG_BANK_DEPOSIT, { Bag = payload.Bag, Bank = slot })
		elseif payload.Bank and payload.Bank ~= slot then
			netSend:Fire(Opcodes.CMSG_BANK_SWAP, { From = payload.Bank, To = slot })
		end
	end)
	return button
end

local tiles = scope:Computed(function(use)
	local list = {}
	for slot = 1, use(slots) do
		table.insert(list, tile(scope, slot))
	end
	return list
end)

Components.Panel(scope, {
	Name = "BankFrame",
	Size = scope:Computed(function(use)
		local rows = math.ceil(use(slots) / COLUMNS)
		return UDim2.fromOffset(COLUMNS * (TILE + GAP) - GAP + 24, rows * (TILE + GAP) - GAP + 24 + 36)
	end),
	Position = UDim2.new(0.5, -200, 0.5, 0),
	Enabled = open,
	Parent = player:WaitForChild("PlayerGui"),
	Title = "Bank",
	OnDrop = function(payload)
		if payload.Bag then
			netSend:Fire(Opcodes.CMSG_BANK_DEPOSIT, { Bag = payload.Bag })
		end
	end,
	[Children] = tiles,
})

bankOpen.Event:Connect(function()
	open:set(true)
end)
UserInputService.InputBegan:Connect(function(input, processed)
	if not processed and input.KeyCode == Enum.KeyCode.Escape then
		open:set(false)
	end
end)
player:GetAttributeChangedSignal("InWorld"):Connect(function()
	if player:GetAttribute("InWorld") ~= true then
		open:set(false)
	end
end)
