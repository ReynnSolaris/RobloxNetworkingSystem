local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Fusion = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Fusion"))
local Opcodes = require(ReplicatedStorage.Shared.Opcodes)
local Ui = require(script.Parent:WaitForChild("Ui"))
local Components = require(script.Parent:WaitForChild("Components"))
local player = Players.LocalPlayer
local netSend = script.Parent:WaitForChild("NetSend") :: BindableEvent
local lootOpen = script.Parent:WaitForChild("LootOpen") :: BindableEvent

-- WoW loot window: one row per item, a coin row, Loot All. Click a row to take
-- it; Escape, X or walking away releases the corpse.

local scope = Fusion.scoped(Fusion)
local Children, peek = Fusion.Children, Fusion.peek

local open = scope:Value(false)
local loot = Components.attribute(scope, player, "Loot", "{}")

local function decode(json: string)
	local ok, value = pcall(HttpService.JSONDecode, HttpService, json)
	return if ok and typeof(value) == "table" then value else {}
end

local rows = scope:Computed(function(use)
	local data = decode(use(loot))
	local list = {}
	if (data.Money or 0) > 0 then
		table.insert(list, { Text = '<font color="#FFD700">' .. Ui.money(data.Money) .. "</font>", OnClick = function()
			netSend:Fire(Opcodes.CMSG_LOOT_MONEY, {})
		end })
	end
	local items = data.Items or {}
	local indexes = {}
	for index in items do
		table.insert(indexes, tonumber(index))
	end
	table.sort(indexes)
	for _, index in indexes do
		local item = items[tostring(index)] or items[index]
		table.insert(list, { Text = Ui.itemName(item), Tooltip = Ui.itemTooltip(item), TooltipBorder = Ui.itemBorder(item), Link = "[" .. (item.Name or "?") .. "]", OnClick = function()
			netSend:Fire(Opcodes.CMSG_AUTOSTORE_LOOT_ITEM, { Index = index })
		end })
	end
	return list
end)

local function release()
	if peek(open) then
		open:set(false)
		netSend:Fire(Opcodes.CMSG_LOOT_RELEASE, {})
	end
end

Components.Panel(scope, {
	Name = "LootFrame",
	Size = UDim2.fromOffset(300, 260),
	Position = UDim2.new(0.5, 260, 0.5, -40),
	Enabled = open,
	Parent = player:WaitForChild("PlayerGui"),
	Title = scope:Computed(function(use)
		return decode(use(loot)).Name or "Loot"
	end),
	[Children] = {
		Components.List(scope, { Size = UDim2.new(1, -24, 1, -60), Position = UDim2.fromOffset(12, 8), Rows = rows }),
		Components.Button(scope, { Size = UDim2.new(1, -24, 0, 30), Position = UDim2.new(0, 12, 1, -40), Text = "Loot All", OnClick = function()
			local data = decode(peek(loot))
			if (data.Money or 0) > 0 then
				netSend:Fire(Opcodes.CMSG_LOOT_MONEY, {})
			end
			for index in (data.Items or {}) do
				netSend:Fire(Opcodes.CMSG_AUTOSTORE_LOOT_ITEM, { Index = tonumber(index) })
			end
		end }),
	},
})

lootOpen.Event:Connect(function()
	open:set(true)
end)
player:GetAttributeChangedSignal("Loot"):Connect(function()
	if player:GetAttribute("Loot") == nil then
		open:set(false)
	end
end)
UserInputService.InputBegan:Connect(function(input, processed)
	if not processed and input.KeyCode == Enum.KeyCode.Escape then
		release()
	end
end)
player:GetAttributeChangedSignal("InWorld"):Connect(function()
	if player:GetAttribute("InWorld") ~= true then
		open:set(false)
	end
end)
