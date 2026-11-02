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

-- Vendor window, built with Fusion: stock on the left (click to buy one), your
-- bag on the right (click to sell one). Closes on Escape, X, or walking away.

local scope = Fusion.scoped(Fusion)
local Children = Fusion.Children

local function decode(json: string)
	local ok, value = pcall(HttpService.JSONDecode, HttpService, json)
	return if ok and typeof(value) == "table" then value else {}
end

local open = scope:Value(false)
local guid = scope:Value(nil :: string?)
local title = scope:Value("Vendor")
local stock = Components.attribute(scope, player, "Vendor", "[]")
local inventory = Components.attribute(scope, player, "Inventory", "[]")
local money = Components.attribute(scope, player, "Money", 0)
local model: Model? = nil

local stockRows = scope:Computed(function(use)
	local rows = {}
	for _, item in decode(use(stock)) do
		local price = Ui.money(item.Price or 0)
		table.insert(rows, { Text = Ui.itemName(item), Right = price, Tooltip = Ui.itemTooltip(item, price), OnClick = function()
			netSend:Fire(Opcodes.CMSG_VENDOR_BUY, { Guid = Fusion.peek(guid), Entry = item.Entry, Count = 1 })
		end })
	end
	return rows
end)

local bagRows = scope:Computed(function(use)
	local rows = {}
	for _, item in decode(use(inventory)) do
		local price = Ui.money(item.Sell or 0)
		table.insert(rows, { Text = Ui.itemName(item), Right = price, Tooltip = Ui.itemTooltip(item, "Sells for " .. price), OnClick = function()
			netSend:Fire(Opcodes.CMSG_VENDOR_SELL, { Guid = Fusion.peek(guid), Entry = item.Entry, Count = 1 })
		end })
	end
	return rows
end)

Components.Panel(scope, {
	Name = "VendorFrame",
	Size = UDim2.fromOffset(640, 400),
	Enabled = open,
	Parent = player:WaitForChild("PlayerGui"),
	Title = title,
	[Children] = {
		Components.Text(scope, { Size = UDim2.new(0.5, -20, 0, 20), Position = UDim2.fromOffset(12, 8), Text = "Buy", Color = Ui.DIM }),
		Components.Text(scope, { Size = UDim2.new(0.5, -20, 0, 20), Position = UDim2.new(0.5, 8, 0, 8), Color = Ui.GOLD, Align = Enum.TextXAlignment.Right, Text = scope:Computed(function(use)
			return Ui.money(use(money))
		end) }),
		Components.Text(scope, { Size = UDim2.new(0.5, -20, 0, 20), Position = UDim2.new(0.5, 8, 0, 28), Text = "Sell from your bag", Color = Ui.DIM }),
		Components.List(scope, { Size = UDim2.new(0.5, -18, 1, -60), Position = UDim2.fromOffset(12, 30), Rows = stockRows }),
		Components.List(scope, { Size = UDim2.new(0.5, -18, 1, -60), Position = UDim2.new(0.5, 8, 0, 50), Rows = bagRows }),
	},
})

vendorOpen.Event:Connect(function(openGuid: string)
	guid:set(openGuid)
	model = nil
	local creatures = workspace:FindFirstChild("Creatures")
	for _, child in (creatures and creatures:GetChildren() or {}) do
		if child:GetAttribute("Guid") == openGuid then
			model = child
		end
	end
	title:set(if model then model.Name else "Vendor")
	open:set(true)
	netSend:Fire(Opcodes.CMSG_INVENTORY, {})
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

while true do
	task.wait(0.5)
	if Fusion.peek(open) then
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if not model or not model.Parent or not root or (model:GetPivot().Position - root.Position).Magnitude > Config.VendorRange then
			open:set(false)
		end
	end
end
