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
local guildBankOpen = script.Parent:WaitForChild("GuildBankOpen") :: BindableEvent

-- Guild vault from a banker's gossip: shared slots and money. Drag bag stacks
-- in to deposit; right-click to withdraw (officers), money boxes below.

local scope = Fusion.scoped(Fusion)
local Children, OnEvent, peek = Fusion.Children, Fusion.OnEvent, Fusion.peek

local COLUMNS, TILE, GAP = 8, 50, 6

local open = scope:Value(false)
local bankJson = Components.attribute(scope, player, "GuildBank", "{}")
local data = scope:Computed(function(use)
	local ok, value = pcall(HttpService.JSONDecode, HttpService, use(bankJson))
	return if ok and typeof(value) == "table" then value else {}
end)
local bySlot = scope:Computed(function(use)
	local map = {}
	for _, stack in (use(data).Items or {}) do
		map[stack.Bank or 0] = stack
	end
	return map
end)
local amount = scope:Value("")

local function abbreviation(name: string): string
	local first, second = name:match("^(%w)%w*%s+(%w)")
	return (first and (first .. second) or name:sub(1, 2)):upper()
end

local function tile(scope, slot: number)
	local stack = scope:Computed(function(use)
		return use(bySlot)[slot]
	end)
	local row, col = (slot - 1) // COLUMNS, (slot - 1) % COLUMNS
	local button = scope:New "TextButton" {
		Position = UDim2.fromOffset(12 + col * (TILE + GAP), 12 + row * (TILE + GAP)),
		Size = UDim2.fromOffset(TILE, TILE),
		AutoButtonColor = false,
		BorderSizePixel = 0,
		BackgroundColor3 = Ui.ROW,
		Font = Enum.Font.GothamBold,
		TextSize = 15,
		TextColor3 = scope:Computed(function(use)
			local s = use(stack)
			return if s then Color3.fromHex(Ui.quality(s.Quality)) else Color3.fromRGB(60, 60, 70)
		end),
		Text = scope:Computed(function(use)
			local s = use(stack)
			return if s then abbreviation(s.Name or "?") .. (if (s.Count or 1) > 1 then " " .. s.Count else "") else ""
		end),
		[OnEvent "MouseEnter"] = function()
			local s = peek(stack)
			if s and not Drag.active() then
				Ui.showTip(Ui.itemTooltip(s) .. (if peek(data).CanWithdraw then '\n<font color="#AAAAAA">Right-click to withdraw</font>' else ""), Ui.itemBorder(s))
			end
		end,
		[OnEvent "MouseLeave"] = Ui.hideTip,
		[OnEvent "MouseButton2Click"] = function()
			if peek(stack) and peek(data).CanWithdraw then
				netSend:Fire(Opcodes.CMSG_GUILD_BANK, { Action = "withdraw", Slot = slot })
			end
		end,
		[Children] = {
			scope:New "UICorner" { CornerRadius = UDim.new(0, 4) },
			scope:New "UIStroke" { Thickness = 2, Color = scope:Computed(function(use)
				local s = use(stack)
				return if s then Color3.fromHex(Ui.quality(s.Quality)) else Color3.fromRGB(45, 45, 55)
			end) },
		},
	}
	Drag.target(button, function(payload)
		if payload.Bag then
			netSend:Fire(Opcodes.CMSG_GUILD_BANK, { Action = "deposit", Bag = payload.Bag, Slot = slot })
		end
	end)
	return button
end

local tiles = {}
for slot = 1, Config.GuildBank.Slots do
	table.insert(tiles, tile(scope, slot))
end
local rows = math.ceil(Config.GuildBank.Slots / COLUMNS)

Components.Panel(scope, {
	Name = "GuildBankFrame",
	Size = UDim2.fromOffset(COLUMNS * (TILE + GAP) - GAP + 24, rows * (TILE + GAP) - GAP + 24 + 36 + 44),
	Position = UDim2.new(0.5, 0, 0.5, 0),
	Enabled = open,
	Parent = player:WaitForChild("PlayerGui"),
	Title = scope:Computed(function(use)
		return "Guild Vault" .. (if use(data).Guild then ", " .. use(data).Guild else "")
	end),
	OnDrop = function(payload)
		if payload.Bag then
			netSend:Fire(Opcodes.CMSG_GUILD_BANK, { Action = "deposit", Bag = payload.Bag })
		end
	end,
	[Children] = {
		tiles,
		Components.Text(scope, { Position = UDim2.new(0, 12, 1, -38), Size = UDim2.fromOffset(200, 28), Color = Ui.GOLD, Text = scope:Computed(function(use)
			return "Vault: " .. Ui.money(use(data).Money or 0)
		end) }),
		scope:New "TextBox" {
			Position = UDim2.new(1, -312, 1, -38),
			Size = UDim2.fromOffset(110, 28),
			BackgroundColor3 = Ui.ROW,
			BorderSizePixel = 0,
			Font = Enum.Font.Gotham,
			TextSize = 13,
			TextColor3 = Color3.new(1, 1, 1),
			PlaceholderText = "copper",
			PlaceholderColor3 = Color3.fromRGB(120, 120, 130),
			ClearTextOnFocus = false,
			Text = amount,
			[Fusion.Out "Text"] = amount,
			[Children] = { scope:New "UICorner" { CornerRadius = UDim.new(0, 4) }, scope:New "UIStroke" { Color = Ui.BORDER }, scope:New "UIPadding" { PaddingLeft = UDim.new(0, 6) } },
		},
		Components.Button(scope, { Size = UDim2.fromOffset(90, 28), Position = UDim2.new(1, -196, 1, -38), Text = "Deposit", OnClick = function()
			netSend:Fire(Opcodes.CMSG_GUILD_BANK, { Action = "depositmoney", Amount = tonumber(peek(amount)) or 0 })
		end }),
		Components.Button(scope, { Size = UDim2.fromOffset(90, 28), Position = UDim2.new(1, -100, 1, -38), Text = "Withdraw", Visible = scope:Computed(function(use)
			return use(data).CanWithdraw == true
		end), OnClick = function()
			netSend:Fire(Opcodes.CMSG_GUILD_BANK, { Action = "withdrawmoney", Amount = tonumber(peek(amount)) or 0 })
		end }),
	},
})

guildBankOpen.Event:Connect(function()
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
