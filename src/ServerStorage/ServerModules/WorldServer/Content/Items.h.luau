local Base = require(game:GetService("ServerStorage").ServerModules["Template.h"])
local Opcodes = require(game:GetService("ReplicatedStorage").Shared.Opcodes)
local module = {}

-- item_template: { entry, name, quality 0-5, stack, class (weapon|armor|consumable|
-- misc|reagent|recipe), slot, health, damage, armor, strength, agility, stamina,
-- intellect, spirit, spellpower, buyprice, sellprice (copper), level, use (spell
-- name), consumable, flavor, bind (pickup|equip), recipe (skill_recipe id),
-- mount (speed mult) }. Describe builds the one shape every window and tooltip
-- reads. Seeds reach existing databases by name.

local SEED = {
	{ name = "Hearthstone", quality = 1, stack = 1, class = "misc", buyprice = 0, use = "Hearthstone", bind = "pickup" },
	{ name = "Linen Cloth", quality = 1, stack = 20, class = "reagent", buyprice = 10 },
	{ name = "Worn Shortsword", quality = 1, stack = 1, class = "weapon", slot = "mainhand", damage = 3, buyprice = 60, level = 1 },
	{ name = "Tough Jerky", quality = 1, stack = 20, class = "consumable", buyprice = 5, use = "Food", consumable = true },
	{ name = "Ring of Precision", quality = 3, stack = 1, class = "armor", slot = "ring", agility = 3, stamina = 2, buyprice = 2500, level = 3, flavor = "It never misses." },
	{ name = "Recruit's Tunic", quality = 1, stack = 1, class = "armor", slot = "chest", armor = 2, stamina = 1, buyprice = 80, level = 1 },
	{ name = "Recruit's Pants", quality = 1, stack = 1, class = "armor", slot = "legs", armor = 2, buyprice = 60, level = 1 },
	{ name = "Recruit's Boots", quality = 1, stack = 1, class = "armor", slot = "feet", armor = 1, buyprice = 40, level = 1 },
	{ name = "Kobold Mining Helm", quality = 2, stack = 1, class = "armor", slot = "head", armor = 2, stamina = 2, strength = 1, buyprice = 400, level = 2 },
	{ name = "Copper Ore", quality = 1, stack = 20, class = "reagent", buyprice = 20 },
	{ name = "Copper Bar", quality = 1, stack = 20, class = "reagent", buyprice = 40 },
	{ name = "Rough Stone", quality = 0, stack = 20, class = "reagent", buyprice = 2 },
	{ name = "Peacebloom", quality = 1, stack = 20, class = "reagent", buyprice = 20 },
	{ name = "Silverleaf", quality = 1, stack = 20, class = "reagent", buyprice = 20 },
	{ name = "Minor Healing Potion", quality = 1, stack = 5, class = "consumable", buyprice = 50, use = "Minor Healing Potion", consumable = true },
	{ name = "Linen Bandage", quality = 1, stack = 20, class = "consumable", buyprice = 20, use = "Linen Bandage", consumable = true },
	{ name = "Copper Chain Belt", quality = 1, stack = 1, class = "armor", slot = "chest", armor = 3, stamina = 1, buyprice = 200, level = 3 },
	{ name = "Rough Copper Sword", quality = 1, stack = 1, class = "weapon", slot = "mainhand", damage = 5, buyprice = 300, level = 3 },
	{ name = "Spiced Wolf Meat", quality = 1, stack = 20, class = "consumable", buyprice = 30, use = "Food", consumable = true },
	{ name = "Stringy Wolf Meat", quality = 1, stack = 20, class = "reagent", buyprice = 5 },
	{ name = "Brown Horse Bridle", quality = 2, stack = 1, class = "misc", buyprice = 100000, level = 20, use = "Summon Brown Horse", flavor = "A trusted companion of the road." },
	{ name = "Linen Bag", quality = 1, stack = 1, class = "container", slot = "bag", container = 6, buyprice = 500, level = 1 },
	{ name = "Woolen Bag", quality = 2, stack = 1, class = "container", slot = "bag", container = 8, buyprice = 2500, level = 10 },
	{ name = "Gryphon Reins", quality = 3, stack = 1, class = "misc", buyprice = 5000000, level = 30, use = "Summon Gryphon", flavor = "The skies of Azeroth await." },
}

function module:DB()
	return self.includes.Database["WorldDB.h"]
end

function module:Template(entry)
	return self:DB():Get("item_template", entry)
end

function module:ByName(name: string)
	for _, row in self:DB():Select("item_template") do
		if row.name:lower() == name:lower() then
			return row
		end
	end
	return nil
end

local STATS = { "strength", "agility", "stamina", "intellect", "spirit", "spellpower" }
module.STATS = STATS

-- Everything a tooltip shows, from an entry or a template row; extra fields
-- (Bag, Count, Index, Price) are merged in.
function module:Describe(item, extra)
	local DB = self:DB()
	local template = if typeof(item) == "table" then item else (self:Template(item) or {})
	local spell = template.spell and DB:Get("spell_template", template.spell)
	local out = { Entry = template.entry, Name = template.name or "?", Quality = template.quality or 1, Stack = template.stack, Slot = template.slot,
		Class = template.class, Level = template.level, Health = template.health, Damage = template.damage, Armor = template.armor,
		Sell = template.sellprice or math.floor((template.buyprice or 0) / 4), Use = spell and spell.description, Flavor = template.flavor,
		Bind = template.bind, Recipe = template.recipe, Mount = template.mount, Container = template.container }
	for _, stat in STATS do
		out[stat:sub(1, 1):upper() .. stat:sub(2)] = template[stat]
	end
	for key, value in (extra or {}) do
		out[key] = value
	end
	return out
end

function module:Start()
	local DB = self:DB()
	local byName = {}
	for _, row in DB:Select("item_template") do
		byName[row.name] = row
	end
	for _, item in SEED do
		local existing = byName[item.name]
		if not existing then
			byName[item.name] = DB:Insert("item_template", table.clone(item))
		else
			local fields = {}
			for key, value in item do
				if key ~= "name" and key ~= "quality" and key ~= "stack" and existing[key] == nil then
					fields[key] = value
				end
			end
			if next(fields) then
				DB:Update("item_template", existing.entry, fields)
			end
		end
	end
	local Packet = self.includes.Security["Packet.h"]
	local Entities = self.includes.Entities["EntityPlayer.h"]
	Packet:On(Opcodes.CMSG_INVENTORY, function(player)
		Entities:SendInventory(player, true)
	end)
	Packet:On(Opcodes.CMSG_SWAP_INV_ITEM, function(player, data)
		if typeof(data) == "table" then
			Entities:SwapSlots(player, tonumber(data.From) or 0, tonumber(data.To) or 0)
		end
	end)
	Packet:On(Opcodes.CMSG_BANK_DEPOSIT, function(player, data)
		if typeof(data) == "table" then Entities:MoveStack(player, "bag", tonumber(data.Bag) or 0, "bank", tonumber(data.Bank)) end
	end)
	Packet:On(Opcodes.CMSG_BANK_WITHDRAW, function(player, data)
		if typeof(data) == "table" then Entities:MoveStack(player, "bank", tonumber(data.Bank) or 0, "bag", tonumber(data.Bag)) end
	end)
	Packet:On(Opcodes.CMSG_BANK_SWAP, function(player, data)
		if typeof(data) == "table" then Entities:MoveStack(player, "bank", tonumber(data.From) or 0, "bank", tonumber(data.To)) end
	end)
	-- What the client needs to draw a tooltip for an item it only knows by entry (chat links).
	Packet:On(Opcodes.CMSG_ITEM_QUERY_SINGLE, function(player, data)
		local item = self:Template(tonumber(typeof(data) == "table" and data.Entry) or 0)
		if item then
			Packet:Send(player, Opcodes.SMSG_ITEM_QUERY_SINGLE_RESPONSE, self:Describe(item, { Price = item.buyprice }))
		end
	end)
end

return Base(module, {
	{ Path = "World/Database", Imports = "WorldDB.h" },
	{ Path = "Auth/Security", Imports = "Packet.h" },
	{ Path = "Auth/Entities", Imports = "EntityPlayer.h" },
})
