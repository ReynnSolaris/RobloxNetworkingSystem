local Base = require(game:GetService("ServerStorage").ServerModules["Template.h"])
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Opcodes = require(ReplicatedStorage.Shared.Opcodes)
local Config = require(ReplicatedStorage.Shared.Config)
local Players = game:GetService("Players")
local module = {}

-- npc_vendor: { id, entry (creature), item }. Talking to a creature with rows
-- opens the vendor window; buying and selling are validated here.

local SEED = { creature = "General Goods", items = { "Tough Jerky", "Linen Cloth", "Worn Shortsword", "Recruit's Tunic", "Recruit's Pants", "Recruit's Boots" } }

function module:DB()
	return self.includes.Database["WorldDB.h"]
end

-- Prices fall with the player's standing toward the vendor's faction.
function module:Stock(entry, player: Player?)
	local DB = self:DB()
	local Items = self.includes.Content["Items.h"]
	local discount = if player then self.includes.Social["Reputation.h"]:Discount(player, DB:Get("creature_template", entry)) else 0
	local items = {}
	for _, row in DB:Select("npc_vendor") do
		if tostring(row.entry) == tostring(entry) then
			local item = DB:Get("item_template", row.item)
			if item then
				table.insert(items, Items:Describe(item, { Price = math.floor((item.buyprice or 0) * (1 - discount)) }))
			end
		end
	end
	return items
end

-- The creature the player is trading with must still be in range.
local function inRange(self, player: Player, guid): boolean
	local state = self.includes.Content["Creatures.h"]:State(guid)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	return state ~= nil and root ~= nil and (state.Root.Position - root.Position).Magnitude <= Config.VendorRange
end

function module:Open(player: Player, guid, entry)
	local stock = self:Stock(entry, player)
	if #stock > 0 then
		self.includes.Security["Packet.h"]:Send(player, Opcodes.SMSG_VENDOR_LIST, { Guid = tostring(guid), Items = stock })
		if self.SendBuyback then
			self.SendBuyback(player)
		end
	end
end

function module:Start()
	local Packet = self.includes.Security["Packet.h"]
	local Entities = self.includes.Entities["EntityPlayer.h"]
	local Chat = self.includes.Chat["Chat.h"]
	local DB = self:DB()

	local vendor
	for _, row in DB:Select("creature_template") do
		if row.name == SEED.creature then
			vendor = row
		end
	end
	if vendor and #DB:Select("npc_vendor") == 0 then
		for _, item in DB:Select("item_template") do
			if table.find(SEED.items, item.name) then
				DB:Insert("npc_vendor", { entry = vendor.entry, item = item.entry })
			end
		end
	end

	Packet:On(Opcodes.CMSG_VENDOR_BUY, function(player, data)
		if typeof(data) ~= "table" or not inRange(self, player, data.Guid) then
			return Chat:System(player, "You are too far away from the vendor.")
		end
		local state = self.includes.Content["Creatures.h"]:State(data.Guid)
		local entry, count = tonumber(data.Entry), math.clamp(tonumber(data.Count) or 1, 1, 20)
		local item
		for _, stock in self:Stock(state.Row.id, player) do
			if stock.Entry == entry then
				item = stock
			end
		end
		if not item then
			return Chat:System(player, "That vendor does not sell that.")
		end
		local cost = item.Price * count
		if (player:GetAttribute("Money") or 0) < cost then
			return Chat:System(player, "You don't have enough money.")
		end
		Entities:AddMoney(player, -cost)
		Entities:AddItem(player, entry, count)
	end)

	-- Selling takes the whole stack out of a bag slot and parks it for buyback.
	local function sendBuyback(player: Player)
		local list = {}
		for _, item in (self.information[player] or {}) do
			table.insert(list, self.includes.Content["Items.h"]:Describe(item.entry, { Count = item.count, Price = item.price }))
		end
		Packet:Send(player, Opcodes.SMSG_BUYBACK_LIST, { Items = list })
	end
	self.SendBuyback = sendBuyback

	Packet:On(Opcodes.CMSG_VENDOR_SELL, function(player, data)
		if typeof(data) ~= "table" or not inRange(self, player, data.Guid) then
			return Chat:System(player, "You are too far away from the vendor.")
		end
		local stack = Entities:TakeSlot(player, tonumber(data.Bag) or 0)
		if not stack then
			return
		end
		local item = DB:Get("item_template", stack.entry) or {}
		local price = (item.sellprice or math.floor((item.buyprice or 0) / 4)) * stack.count
		Entities:AddMoney(player, price)
		Chat:System(player, ("You sell %s%s."):format(item.name or "?", if stack.count > 1 then " x" .. stack.count else ""))
		local list = self.information[player] or {}
		self.information[player] = list
		table.insert(list, 1, { entry = stack.entry, count = stack.count, price = price })
		if #list > Config.BuybackSlots then
			table.remove(list)
		end
		sendBuyback(player)
	end)

	Packet:On(Opcodes.CMSG_BUYBACK_ITEM, function(player, data)
		local list = self.information[player] or {}
		local index = tonumber(typeof(data) == "table" and data.Index) or 0
		local item = list[index]
		if not item or not inRange(self, player, data.Guid) then
			return
		end
		if (player:GetAttribute("Money") or 0) < item.price then
			return Chat:System(player, "You don't have enough money.")
		end
		if Entities:AddItem(player, item.entry, item.count, true) then
			Entities:AddMoney(player, -item.price)
			table.remove(list, index)
			sendBuyback(player)
		end
	end)

	Packet:On(Opcodes.CMSG_EQUIP, function(player, data)
		local ok, reason = Entities:Equip(player, tonumber(typeof(data) == "table" and data.Bag) or 0)
		if not ok then
			Chat:System(player, reason or "You cannot equip that.")
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		self.information[player] = nil
	end)

	Packet:On(Opcodes.CMSG_UNEQUIP, function(player, data)
		if typeof(data) == "table" and typeof(data.Slot) == "string" then
			Entities:Unequip(player, data.Slot, tonumber(data.To))
		end
	end)
end

return Base(module, {
	{ Path = "World/Database", Imports = "WorldDB.h" },
	{ Path = "World/Content", Imports = "Creatures.h|Items.h" },
	{ Path = "Auth/Social", Imports = "Reputation.h" },
	{ Path = "Auth/Security", Imports = "Packet.h" },
	{ Path = "Auth/Entities", Imports = "EntityPlayer.h" },
	{ Path = "Auth/Chat", Imports = "Chat.h" },
})
