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

-- Vendor window: stock on the left (click to buy one), buyback on the right
-- (click to take it back). Selling is done from the backpack. Closes on Escape,
-- X, or walking away; closing clears VendorGuid so the bag stops selling.

local scope = Fusion.scoped(Fusion)
local Children = Fusion.Children

local function decode(json: string)
	local ok, value = pcall(HttpService.JSONDecode, HttpService, json)
	return if ok and typeof(value) == "table" then value else {}
end

local open = scope:Value(false)
local title = scope:Value("Vendor")
local stock = Components.attribute(scope, player, "Vendor", "[]")
local buyback = Components.attribute(scope, player, "Buyback", "[]")
local money = Components.attribute(scope, player, "Money", 0)
local model: Model? = nil

local stockRows = scope:Computed(function(use)
	local rows = {}
	for _, item in decode(use(stock)) do
		local price = Ui.money(item.Price or 0)
		table.insert(rows, { Text = Ui.itemName(item), Right = price, Tooltip = Ui.itemTooltip(item, "Price: " .. price), TooltipBorder = Ui.itemBorder(item), Link = "[" .. (item.Name or "?") .. "]", OnClick = function()
			netSend:Fire(Opcodes.CMSG_VENDOR_BUY, { Guid = player:GetAttribute("VendorGuid"), Entry = item.Entry, Count = 1 })
		end })
	end
	return rows
end)

local buybackRows = scope:Computed(function(use)
	local rows = {}
	for index, item in decode(use(buyback)) do
		local price = Ui.money(item.Price or 0)
		table.insert(rows, { Text = Ui.itemName(item), Right = price, Tooltip = Ui.itemTooltip(item, "Buy back for " .. price), TooltipBorder = Ui.itemBorder(item), Link = "[" .. (item.Name or "?") .. "]", OnClick = function()
			netSend:Fire(Opcodes.CMSG_BUYBACK_ITEM, { Guid = player:GetAttribute("VendorGuid"), Index = index })
		end })
	end
	return rows
end)

Components.Panel(scope, {
	Name = "VendorFrame",
	Size = UDim2.fromOffset(640, 400),
	Position = UDim2.new(0.5, -120, 0.5, 0),
	Enabled = open,
	Parent = player:WaitForChild("PlayerGui"),
	Title = title,
	OnDrop = function(payload)
		if payload.Bag then
			netSend:Fire(Opcodes.CMSG_VENDOR_SELL, { Guid = player:GetAttribute("VendorGuid"), Bag = payload.Bag })
		end
	end,
	[Children] = {
		Components.Text(scope, { Size = UDim2.new(0.5, -20, 0, 20), Position = UDim2.fromOffset(12, 8), Text = "Goods", Color = Ui.DIM }),
		Components.Text(scope, { Size = UDim2.new(0.5, -20, 0, 20), Position = UDim2.new(0.5, 8, 0, 8), Text = "Buyback", Color = Ui.DIM }),
		Components.List(scope, { Size = UDim2.new(0.5, -18, 1, -60), Position = UDim2.fromOffset(12, 30), Rows = stockRows }),
		Components.List(scope, { Size = UDim2.new(0.5, -18, 1, -60), Position = UDim2.new(0.5, 8, 0, 30), Rows = buybackRows }),
		Components.Text(scope, { Size = UDim2.new(1, -24, 0, 20), Position = UDim2.new(0, 12, 1, -26), Color = Ui.DIM, Text = "Drag an item here, or right-click it in your backpack, to sell it." }),
		Components.Text(scope, { Size = UDim2.new(0.5, -20, 0, 20), Position = UDim2.new(0.5, 8, 1, -26), Color = Ui.GOLD, Align = Enum.TextXAlignment.Right, Text = scope:Computed(function(use)
			return Ui.money(use(money))
		end) }),
	},
})

local function close()
	open:set(false)
	player:SetAttribute("VendorGuid", nil)
end

vendorOpen.Event:Connect(function(openGuid: string)
	model = nil
	local creatures = workspace:FindFirstChild("Creatures")
	for _, child in (creatures and creatures:GetChildren() or {}) do
		if child:GetAttribute("Guid") == openGuid then
			model = child
		end
	end
	title:set(if model then model.Name else "Vendor")
	open:set(true)
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if not processed and input.KeyCode == Enum.KeyCode.Escape and Fusion.peek(open) then
		close()
	end
end)
player:GetAttributeChangedSignal("InWorld"):Connect(function()
	if player:GetAttribute("InWorld") ~= true and Fusion.peek(open) then
		close()
	end
end)
Fusion.Observer(scope, open):onChange(function()
	if not Fusion.peek(open) then
		player:SetAttribute("VendorGuid", nil)
	end
end)

while true do
	task.wait(0.5)
	if Fusion.peek(open) then
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if not model or not model.Parent or not root or (model:GetPivot().Position - root.Position).Magnitude > Config.VendorRange then
			close()
		end
	end
end
