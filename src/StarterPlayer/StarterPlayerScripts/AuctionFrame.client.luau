local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Fusion = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Fusion"))
local Opcodes = require(ReplicatedStorage.Shared.Opcodes)
local Ui = require(script.Parent:WaitForChild("Ui"))
local Components = require(script.Parent:WaitForChild("Components"))
local Drag = require(script.Parent:WaitForChild("Drag"))
local player = Players.LocalPlayer
local netSend = script.Parent:WaitForChild("NetSend") :: BindableEvent
local auctionOpen = script.Parent:WaitForChild("AuctionOpen") :: BindableEvent
local auctionList = script.Parent:WaitForChild("AuctionList") :: BindableEvent

-- Auction house: Browse (search, bid, buyout), Bids and Auctions tabs, and a
-- Sell panel: drag a bag item onto it, set the starting bid and buyout in
-- copper, pick a duration, Create Auction.

local scope = Fusion.scoped(Fusion)
local Children, OnEvent, peek = Fusion.Children, Fusion.OnEvent, Fusion.peek

local open = scope:Value(false)
local mode = scope:Value("browse")
local filter = scope:Value("")
local items = scope:Value({})
local picked = scope:Value(nil :: any)
local sellItem = scope:Value(nil :: any)
local bid, buyout, hours = scope:Value(""), scope:Value(""), scope:Value(12)
local bidAmount = scope:Value("")

local function request()
	netSend:Fire(Opcodes.CMSG_AUCTION_LIST_ITEMS, { Mode = peek(mode), Filter = peek(filter) })
end

local function left(seconds: number): string
	if seconds >= 3600 then
		return ("%dh"):format(seconds // 3600)
	elseif seconds >= 60 then
		return ("%dm"):format(seconds // 60)
	end
	return "<1m"
end

local rows = scope:Computed(function(use)
	local out = {}
	for _, item in use(items) do
		table.insert(out, {
			Text = Ui.itemName(item) .. ('  <font color="#AAAAAA">%s</font>'):format(item.Owner or ""),
			Right = ("%s%s   %s"):format(Ui.money(item.Bid or 0), if item.Buyout then "  /  " .. Ui.money(item.Buyout) else "", left(item.Left or 0)),
			Tooltip = Ui.itemTooltip(item) .. ('\n<font color="#AAAAAA">Bid %s%s%s</font>'):format(Ui.money(item.Bid or 0), if item.Buyout then ", buyout " .. Ui.money(item.Buyout) else "", if item.Bidder then ", high bidder " .. item.Bidder else ""),
			TooltipBorder = Ui.itemBorder(item),
			Link = "[" .. (item.Name or "?") .. "]",
			OnClick = function()
				picked:set(item)
				bidAmount:set(tostring(if item.Bidder then math.floor(item.Bid * 1.05) + 1 else item.Bid or 0))
			end,
		})
	end
	return out
end)

-- A text box bound both ways to a Value.
local function box(scope, props)
	return scope:New "TextBox" {
		Position = props.Position,
		Size = props.Size,
		BackgroundColor3 = Ui.ROW,
		BorderSizePixel = 0,
		Font = Enum.Font.Gotham,
		TextSize = 13,
		TextColor3 = Color3.new(1, 1, 1),
		PlaceholderText = props.Placeholder,
		PlaceholderColor3 = Color3.fromRGB(120, 120, 130),
		ClearTextOnFocus = false,
		Text = props.Value,
		[Fusion.Out "Text"] = props.Value,
		[OnEvent "FocusLost"] = function(enter)
			if enter and props.OnEnter then
				props.OnEnter()
			end
		end,
		[Children] = { scope:New "UICorner" { CornerRadius = UDim.new(0, 4) }, scope:New "UIStroke" { Color = Ui.BORDER }, scope:New "UIPadding" { PaddingLeft = UDim.new(0, 6) } },
	}
end

local sellTile = scope:New "TextButton" {
	Position = UDim2.fromOffset(12, 10),
	Size = UDim2.fromOffset(58, 58),
	AutoButtonColor = false,
	BorderSizePixel = 0,
	BackgroundColor3 = Ui.ROW,
	Font = Enum.Font.GothamBold,
	TextSize = 16,
	TextColor3 = scope:Computed(function(use)
		local s = use(sellItem)
		return if s then Color3.fromHex(Ui.quality(s.Quality)) else Color3.fromRGB(60, 60, 70)
	end),
	Text = scope:Computed(function(use)
		local s = use(sellItem)
		return if s then (s.Name or "?"):sub(1, 2):upper() else "+"
	end),
	[OnEvent "MouseEnter"] = function()
		local s = peek(sellItem)
		if s then
			Ui.showTip(Ui.itemTooltip(s), Ui.itemBorder(s))
		else
			Ui.showTip("Drag an item from your bags here to sell it.")
		end
	end,
	[OnEvent "MouseLeave"] = Ui.hideTip,
	[Children] = { scope:New "UICorner" { CornerRadius = UDim.new(0, 4) }, scope:New "UIStroke" { Color = Ui.BORDER, Thickness = 2 } },
}
Drag.target(sellTile, function(payload)
	if payload.Bag and payload.Item then
		local item = table.clone(payload.Item)
		item.Bag = payload.Bag
		sellItem:set(item)
		mode:set("sell")
	end
end)

local function tabButton(name: string, label: string, x: number)
	return Components.Button(scope, { Size = UDim2.fromOffset(100, 26), Position = UDim2.fromOffset(x, 8), Text = label, Active = scope:Computed(function(use)
		return use(mode) == name
	end), OnClick = function()
		mode:set(name)
		picked:set(nil)
		if name ~= "sell" then
			request()
		end
	end })
end

Components.Panel(scope, {
	Name = "AuctionFrame",
	Size = UDim2.fromOffset(700, 480),
	Position = UDim2.new(0.5, 0, 0.5, 0),
	Enabled = open,
	Parent = player:WaitForChild("PlayerGui"),
	Title = "Auction House",
	[Children] = {
		tabButton("browse", "Browse", 12),
		tabButton("bidder", "Bids", 118),
		tabButton("owner", "Auctions", 224),
		tabButton("sell", "Sell", 330),
		-- browse / bids / auctions
		scope:New "Frame" {
			Position = UDim2.fromOffset(0, 40),
			Size = UDim2.new(1, 0, 1, -40),
			BackgroundTransparency = 1,
			Visible = scope:Computed(function(use)
				return use(mode) ~= "sell"
			end),
			[Children] = {
				box(scope, { Position = UDim2.fromOffset(12, 4), Size = UDim2.fromOffset(240, 26), Placeholder = "Search", Value = filter, OnEnter = request }),
				Components.Button(scope, { Size = UDim2.fromOffset(80, 26), Position = UDim2.fromOffset(258, 4), Text = "Search", OnClick = request }),
				Components.List(scope, { Size = UDim2.new(1, -24, 1, -90), Position = UDim2.fromOffset(12, 38), Rows = rows }),
				scope:New "Frame" {
					Position = UDim2.new(0, 12, 1, -44),
					Size = UDim2.new(1, -24, 0, 32),
					BackgroundTransparency = 1,
					Visible = scope:Computed(function(use)
						return use(picked) ~= nil
					end),
					[Children] = {
						Components.Text(scope, { Size = UDim2.new(0.5, 0, 1, 0), Text = scope:Computed(function(use)
							local p = use(picked)
							return if p then Ui.itemName(p) else ""
						end) }),
						box(scope, { Position = UDim2.new(1, -430, 0, 2), Size = UDim2.fromOffset(120, 28), Placeholder = "Bid (copper)", Value = bidAmount }),
						Components.Button(scope, { Size = UDim2.fromOffset(90, 28), Position = UDim2.new(1, -300, 0, 2), Text = "Bid", Visible = scope:Computed(function(use)
							return use(mode) == "browse" or use(mode) == "bidder"
						end), OnClick = function()
							local p = peek(picked)
							if p then
								netSend:Fire(Opcodes.CMSG_AUCTION_PLACE_BID, { Id = p.Id, Amount = tonumber(peek(bidAmount)) or p.Bid, Mode = peek(mode), Filter = peek(filter) })
							end
						end }),
						Components.Button(scope, { Size = UDim2.fromOffset(120, 28), Position = UDim2.new(1, -200, 0, 2), Text = scope:Computed(function(use)
							local p = use(picked)
							return if p and p.Buyout then "Buyout " .. Ui.money(p.Buyout) else "No buyout"
						end), Visible = scope:Computed(function(use)
							local p = use(picked)
							return p ~= nil and p.Buyout ~= nil and use(mode) ~= "owner"
						end), OnClick = function()
							local p = peek(picked)
							if p and p.Buyout then
								netSend:Fire(Opcodes.CMSG_AUCTION_PLACE_BID, { Id = p.Id, Amount = p.Buyout, Mode = peek(mode), Filter = peek(filter) })
							end
						end }),
						Components.Button(scope, { Size = UDim2.fromOffset(100, 28), Position = UDim2.new(1, -70, 0, 2), AnchorPoint = Vector2.new(1, 0), Text = "Cancel", Visible = scope:Computed(function(use)
							return use(mode) == "owner"
						end), OnClick = function()
							local p = peek(picked)
							if p then
								netSend:Fire(Opcodes.CMSG_AUCTION_REMOVE_ITEM, { Id = p.Id })
								picked:set(nil)
							end
						end }),
					},
				},
			},
		},
		-- sell
		scope:New "Frame" {
			Position = UDim2.fromOffset(0, 40),
			Size = UDim2.new(1, 0, 1, -40),
			BackgroundTransparency = 1,
			Visible = scope:Computed(function(use)
				return use(mode) == "sell"
			end),
			[Children] = {
				sellTile,
				Components.Text(scope, { Position = UDim2.fromOffset(80, 14), Size = UDim2.new(1, -92, 0, 24), Font = Enum.Font.GothamBold, Text = scope:Computed(function(use)
					local s = use(sellItem)
					return if s then Ui.itemName(s) else "Drag an item here"
				end) }),
				Components.Text(scope, { Position = UDim2.fromOffset(80, 40), Size = UDim2.new(1, -92, 0, 20), TextSize = 12, Color = Ui.DIM, Text = scope:Computed(function(use)
					local s = use(sellItem)
					return if s then "Vendor price " .. Ui.money((s.Sell or 0) * (s.Count or 1)) else ""
				end) }),
				Components.Text(scope, { Position = UDim2.fromOffset(12, 84), Size = UDim2.fromOffset(140, 20), Text = "Starting bid (copper)" }),
				box(scope, { Position = UDim2.fromOffset(160, 80), Size = UDim2.fromOffset(160, 28), Placeholder = "e.g. 500 = 5s", Value = bid }),
				Components.Text(scope, { Position = UDim2.fromOffset(12, 120), Size = UDim2.fromOffset(140, 20), Text = "Buyout (copper)" }),
				box(scope, { Position = UDim2.fromOffset(160, 116), Size = UDim2.fromOffset(160, 28), Placeholder = "optional", Value = buyout }),
				Components.Text(scope, { Position = UDim2.fromOffset(12, 156), Size = UDim2.fromOffset(140, 20), Text = "Duration" }),
				Components.Button(scope, { Size = UDim2.fromOffset(60, 26), Position = UDim2.fromOffset(160, 154), Text = "12h", Active = scope:Computed(function(use) return use(hours) == 12 end), OnClick = function() hours:set(12) end }),
				Components.Button(scope, { Size = UDim2.fromOffset(60, 26), Position = UDim2.fromOffset(226, 154), Text = "24h", Active = scope:Computed(function(use) return use(hours) == 24 end), OnClick = function() hours:set(24) end }),
				Components.Button(scope, { Size = UDim2.fromOffset(60, 26), Position = UDim2.fromOffset(292, 154), Text = "48h", Active = scope:Computed(function(use) return use(hours) == 48 end), OnClick = function() hours:set(48) end }),
				Components.Text(scope, { Position = UDim2.fromOffset(12, 196), Size = UDim2.new(1, -24, 0, 20), TextSize = 12, Color = Ui.DIM, Text = scope:Computed(function(use)
					local b = tonumber(use(bid)) or 0
					return ("Deposit %s (5%% of the bid, per 12 hours)"):format(Ui.money(math.max(1, math.floor(b * 0.05 * (use(hours) / 12)))))
				end) }),
				Components.Button(scope, { Size = UDim2.fromOffset(160, 32), Position = UDim2.new(1, -172, 1, -44), Text = "Create Auction", Visible = scope:Computed(function(use)
					return use(sellItem) ~= nil
				end), OnClick = function()
					local s = peek(sellItem)
					if s then
						netSend:Fire(Opcodes.CMSG_AUCTION_SELL_ITEM, { Bag = s.Bag, Bid = tonumber(peek(bid)) or 0, Buyout = tonumber(peek(buyout)) or 0, Hours = peek(hours) })
						sellItem:set(nil)
						mode:set("owner")
					end
				end }),
			},
		},
	},
})

auctionOpen.Event:Connect(function()
	open:set(true)
	mode:set("browse")
end)
auctionList.Event:Connect(function(d)
	if d.Mode == peek(mode) or peek(mode) == "sell" then
		items:set(d.Items or {})
	end
	if d.Mode == "owner" and peek(mode) == "owner" then
		items:set(d.Items or {})
	end
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
