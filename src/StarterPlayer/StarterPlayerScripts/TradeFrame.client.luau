local Players = game:GetService("Players")
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
local tradeStatus = script.Parent:WaitForChild("TradeStatus") :: BindableEvent

-- Trade window: your six slots and money on the left, theirs on the right.
-- Drag bag items into your slots, type money, Accept. Both accepted trades.

local scope = Fusion.scoped(Fusion)
local Children, OnEvent, peek = Fusion.Children, Fusion.OnEvent, Fusion.peek

local TILE, GAP = 50, 6
local open = scope:Value(false)
local partner = scope:Value("")
local mine = scope:Value({ Items = {}, Money = 0, Accepted = false })
local theirs = scope:Value({ Items = {}, Money = 0, Accepted = false })
local moneyText = scope:Value("")

local function slot(scope, side, index: number)
	local item = scope:Computed(function(use)
		return use(side).Items[tostring(index)]
	end)
	local button = scope:New "TextButton" {
		Position = UDim2.fromOffset(12 + ((index - 1) % 3) * (TILE + GAP), 40 + ((index - 1) // 3) * (TILE + GAP)),
		Size = UDim2.fromOffset(TILE, TILE),
		AutoButtonColor = false,
		BorderSizePixel = 0,
		BackgroundColor3 = Ui.ROW,
		Font = Enum.Font.GothamBold,
		TextSize = 15,
		TextColor3 = scope:Computed(function(use)
			local i = use(item)
			return if i then Color3.fromHex(Ui.quality(i.Quality)) else Color3.fromRGB(60, 60, 70)
		end),
		Text = scope:Computed(function(use)
			local i = use(item)
			return if i then (i.Name or "?"):sub(1, 2):upper() .. (if (i.Count or 1) > 1 then " " .. i.Count else "") else ""
		end),
		[OnEvent "MouseEnter"] = function()
			local i = peek(item)
			if i then
				Ui.showTip(Ui.itemTooltip(i), Ui.itemBorder(i))
			end
		end,
		[OnEvent "MouseLeave"] = Ui.hideTip,
		[OnEvent "MouseButton2Click"] = function()
			if side == mine and peek(item) then
				netSend:Fire(Opcodes.CMSG_SET_TRADE_ITEM, { Slot = index })
			end
		end,
		[Children] = {
			scope:New "UICorner" { CornerRadius = UDim.new(0, 4) },
			scope:New "UIStroke" { Thickness = 2, Color = scope:Computed(function(use)
				local i = use(item)
				return if i then Color3.fromHex(Ui.quality(i.Quality)) else Color3.fromRGB(45, 45, 55)
			end) },
		},
	}
	if side == mine then
		Drag.target(button, function(payload)
			if payload.Bag then
				netSend:Fire(Opcodes.CMSG_SET_TRADE_ITEM, { Slot = index, Bag = payload.Bag })
			end
		end)
	end
	return button
end

local function column(side, x: number, title, editable: boolean)
	local slots = {}
	for i = 1, Config.Trade.Slots do
		table.insert(slots, slot(scope, side, i))
	end
	return scope:New "Frame" {
		Position = UDim2.fromOffset(x, 10),
		Size = UDim2.fromOffset(12 * 2 + 3 * TILE + 2 * GAP, 200),
		BackgroundColor3 = Color3.fromRGB(20, 18, 14),
		BackgroundTransparency = 0.3,
		BorderSizePixel = 0,
		[Children] = {
			scope:New "UICorner" { CornerRadius = UDim.new(0, 6) },
			Components.Text(scope, { Position = UDim2.fromOffset(12, 8), Size = UDim2.new(1, -24, 0, 24), Font = Enum.Font.GothamBold, Text = title }),
			slots,
			if editable then scope:New "TextBox" {
				Position = UDim2.fromOffset(12, 160),
				Size = UDim2.new(1, -24, 0, 28),
				BackgroundColor3 = Ui.ROW,
				BorderSizePixel = 0,
				Font = Enum.Font.Gotham,
				TextSize = 13,
				TextColor3 = Ui.GOLD,
				PlaceholderText = "Money (copper)",
				PlaceholderColor3 = Color3.fromRGB(120, 120, 130),
				ClearTextOnFocus = false,
				Text = moneyText,
				[Fusion.Out "Text"] = moneyText,
				[OnEvent "FocusLost"] = function()
					netSend:Fire(Opcodes.CMSG_SET_TRADE_GOLD, { Amount = tonumber(peek(moneyText)) or 0 })
				end,
				[Children] = { scope:New "UICorner" { CornerRadius = UDim.new(0, 4) }, scope:New "UIStroke" { Color = Ui.BORDER }, scope:New "UIPadding" { PaddingLeft = UDim.new(0, 6) } },
			} else Components.Text(scope, { Position = UDim2.fromOffset(12, 160), Size = UDim2.new(1, -24, 0, 28), Color = Ui.GOLD, Text = scope:Computed(function(use)
				return Ui.money(use(side).Money or 0)
			end) }),
		},
	}
end

Components.Panel(scope, {
	Name = "TradeFrame",
	Size = UDim2.fromOffset(420, 320),
	Position = UDim2.new(0.5, 0, 0.5, -40),
	Enabled = open,
	Parent = player:WaitForChild("PlayerGui"),
	Title = scope:Computed(function(use)
		return "Trade with " .. use(partner)
	end),
	[Children] = {
		column(mine, 12, "You", true),
		column(theirs, 216, partner, false),
		Components.Text(scope, { Position = UDim2.new(0, 12, 1, -56), Size = UDim2.new(1, -24, 0, 20), TextSize = 12, Color = Ui.DIM, Align = Enum.TextXAlignment.Center, Text = scope:Computed(function(use)
			return ("%s%s"):format(if use(mine).Accepted then "You have accepted. " else "", if use(theirs).Accepted then use(partner) .. " has accepted." else "")
		end) }),
		Components.Button(scope, { Size = UDim2.fromOffset(120, 30), Position = UDim2.new(0.5, -126, 1, -36), Text = scope:Computed(function(use)
			return if use(mine).Accepted then "Accepted" else "Accept"
		end), OnClick = function()
			netSend:Fire(Opcodes.CMSG_ACCEPT_TRADE, {})
		end }),
		Components.Button(scope, { Size = UDim2.fromOffset(120, 30), Position = UDim2.new(0.5, 6, 1, -36), Text = "Cancel", OnClick = function()
			netSend:Fire(Opcodes.CMSG_CANCEL_TRADE, {})
			open:set(false)
		end }),
	},
})

tradeStatus.Event:Connect(function(d)
	if d.Status == "request" then
		return
	elseif d.Status == "open" then
		partner:set(d.Partner or "?")
		mine:set(d.Mine or { Items = {}, Money = 0 })
		theirs:set(d.Theirs or { Items = {}, Money = 0 })
		open:set(true)
	else
		open:set(false)
		moneyText:set("")
	end
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if not processed and input.KeyCode == Enum.KeyCode.Escape and peek(open) then
		netSend:Fire(Opcodes.CMSG_CANCEL_TRADE, {})
		open:set(false)
	end
end)
player:GetAttributeChangedSignal("InWorld"):Connect(function()
	if player:GetAttribute("InWorld") ~= true then
		open:set(false)
	end
end)
