local Base = require(game:GetService("ServerStorage").ServerModules["Template.h"])
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Opcodes = require(ReplicatedStorage.Shared.Opcodes)
local Config = require(ReplicatedStorage.Shared.Config)
local module = {}

-- npc_vendor: { id, entry (creature), item }. Talking to a creature with rows
-- opens the vendor window; buying and selling are validated here.

local SEED = { creature = "General Goods", items = { "Tough Jerky", "Linen Cloth", "Worn Shortsword", "Recruit's Tunic", "Recruit's Pants", "Recruit's Boots" } }

function module:DB()
	return self.includes.Database["WorldDB.h"]
end

function module:Stock(entry)
	local DB = self:DB()
	local items = {}
	for _, row in DB:Select("npc_vendor") do
		if tostring(row.entry) == tostring(entry) then
			local item = DB:Get("item_template", row.item)
			if item then
				table.insert(items, { Entry = item.entry, Name = item.name, Quality = item.quality or 1, Price = item.buyprice or 0,
					Slot = item.slot, Class = item.class, Level = item.level, Health = item.health, Damage = item.damage, Armor = item.armor })
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
	local stock = self:Stock(entry)
	if #stock > 0 then
		self.includes.Security["Packet.h"]:Send(player, Opcodes.SMSG_VENDOR_LIST, { Guid = tostring(guid), Items = stock })
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
		for _, stock in self:Stock(state.Row.id) do
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

	Packet:On(Opcodes.CMSG_VENDOR_SELL, function(player, data)
		if typeof(data) ~= "table" or not inRange(self, player, data.Guid) then
			return Chat:System(player, "You are too far away from the vendor.")
		end
		local entry, count = tonumber(data.Entry), math.clamp(tonumber(data.Count) or 1, 1, 20)
		local item = entry and DB:Get("item_template", entry)
		if not item then
			return
		end
		local price = (item.sellprice or math.floor((item.buyprice or 0) / 4)) * count
		if Entities:RemoveItem(player, entry, count) then
			Entities:AddMoney(player, price)
			Chat:System(player, ("You sell %s%s."):format(item.name, if count > 1 then " x" .. count else ""))
		end
	end)

	Packet:On(Opcodes.CMSG_EQUIP, function(player, data)
		local ok, reason = Entities:Equip(player, tonumber(typeof(data) == "table" and data.Entry) or 0)
		if not ok then
			Chat:System(player, reason or "You cannot equip that.")
		end
	end)
	Packet:On(Opcodes.CMSG_UNEQUIP, function(player, data)
		if typeof(data) == "table" and typeof(data.Slot) == "string" then
			Entities:Unequip(player, data.Slot)
		end
	end)
end

return Base(module, {
	{ Path = "World/Database", Imports = "WorldDB.h" },
	{ Path = "World/Content", Imports = "Creatures.h" },
	{ Path = "Auth/Security", Imports = "Packet.h" },
	{ Path = "Auth/Entities", Imports = "EntityPlayer.h" },
	{ Path = "Auth/Chat", Imports = "Chat.h" },
})
