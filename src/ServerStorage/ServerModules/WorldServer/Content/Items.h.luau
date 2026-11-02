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
	-- WotLK starter sets by class: chest, legs, feet and a weapon each
	{ name = "Squire's Shirt", quality = 1, stack = 1, class = "armor", slot = "chest", armor = 2, stamina = 1, buyprice = 80, level = 1 },
	{ name = "Squire's Pants", quality = 1, stack = 1, class = "armor", slot = "legs", armor = 2, buyprice = 60, level = 1 },
	{ name = "Squire's Boots", quality = 1, stack = 1, class = "armor", slot = "feet", armor = 1, buyprice = 40, level = 1 },
	{ name = "Trapper's Shirt", quality = 1, stack = 1, class = "armor", slot = "chest", armor = 1, agility = 1, buyprice = 80, level = 1 },
	{ name = "Trapper's Pants", quality = 1, stack = 1, class = "armor", slot = "legs", armor = 1, buyprice = 60, level = 1 },
	{ name = "Trapper's Boots", quality = 1, stack = 1, class = "armor", slot = "feet", armor = 1, buyprice = 40, level = 1 },
	{ name = "Thug's Shirt", quality = 1, stack = 1, class = "armor", slot = "chest", armor = 1, agility = 1, buyprice = 80, level = 1 },
	{ name = "Thug's Pants", quality = 1, stack = 1, class = "armor", slot = "legs", armor = 1, buyprice = 60, level = 1 },
	{ name = "Thug's Boots", quality = 1, stack = 1, class = "armor", slot = "feet", armor = 1, buyprice = 40, level = 1 },
	{ name = "Neophyte's Shirt", quality = 1, stack = 1, class = "armor", slot = "chest", armor = 1, spirit = 1, buyprice = 80, level = 1 },
	{ name = "Neophyte's Pants", quality = 1, stack = 1, class = "armor", slot = "legs", armor = 1, buyprice = 60, level = 1 },
	{ name = "Neophyte's Boots", quality = 1, stack = 1, class = "armor", slot = "feet", armor = 1, buyprice = 40, level = 1 },
	{ name = "Acherus Knight's Tunic", quality = 2, stack = 1, class = "armor", slot = "chest", armor = 4, strength = 2, stamina = 2, buyprice = 400, level = 1 },
	{ name = "Acherus Knight's Legplates", quality = 2, stack = 1, class = "armor", slot = "legs", armor = 4, stamina = 2, buyprice = 300, level = 1 },
	{ name = "Acherus Knight's Boots", quality = 2, stack = 1, class = "armor", slot = "feet", armor = 3, strength = 1, buyprice = 200, level = 1 },
	{ name = "Primitive Mantle", quality = 1, stack = 1, class = "armor", slot = "chest", armor = 2, intellect = 1, buyprice = 80, level = 1 },
	{ name = "Primitive Kilt", quality = 1, stack = 1, class = "armor", slot = "legs", armor = 2, buyprice = 60, level = 1 },
	{ name = "Primitive Boots", quality = 1, stack = 1, class = "armor", slot = "feet", armor = 1, buyprice = 40, level = 1 },
	{ name = "Apprentice's Robe", quality = 1, stack = 1, class = "armor", slot = "chest", armor = 1, intellect = 1, buyprice = 80, level = 1 },
	{ name = "Apprentice's Pants", quality = 1, stack = 1, class = "armor", slot = "legs", armor = 1, buyprice = 60, level = 1 },
	{ name = "Apprentice's Boots", quality = 1, stack = 1, class = "armor", slot = "feet", armor = 1, buyprice = 40, level = 1 },
	{ name = "Acolyte's Robe", quality = 1, stack = 1, class = "armor", slot = "chest", armor = 1, intellect = 1, buyprice = 80, level = 1 },
	{ name = "Acolyte's Pants", quality = 1, stack = 1, class = "armor", slot = "legs", armor = 1, buyprice = 60, level = 1 },
	{ name = "Acolyte's Boots", quality = 1, stack = 1, class = "armor", slot = "feet", armor = 1, buyprice = 40, level = 1 },
	{ name = "Novice's Robe", quality = 1, stack = 1, class = "armor", slot = "chest", armor = 1, spirit = 1, buyprice = 80, level = 1 },
	{ name = "Novice's Pants", quality = 1, stack = 1, class = "armor", slot = "legs", armor = 1, buyprice = 60, level = 1 },
	{ name = "Novice's Boots", quality = 1, stack = 1, class = "armor", slot = "feet", armor = 1, buyprice = 40, level = 1 },
	{ name = "Worn Mace", quality = 1, stack = 1, class = "weapon", slot = "mainhand", damage = 3, buyprice = 60, level = 1 },
	{ name = "Worn Dagger", quality = 1, stack = 1, class = "weapon", slot = "mainhand", damage = 2, agility = 1, buyprice = 60, level = 1 },
	{ name = "Worn Shortbow", quality = 1, stack = 1, class = "weapon", slot = "mainhand", damage = 3, buyprice = 60, level = 1 },
	{ name = "Neophyte's Staff", quality = 1, stack = 1, class = "weapon", slot = "mainhand", damage = 2, spellpower = 2, buyprice = 60, level = 1 },
	{ name = "Apprentice's Staff", quality = 1, stack = 1, class = "weapon", slot = "mainhand", damage = 2, spellpower = 2, buyprice = 60, level = 1 },
	{ name = "Acolyte's Staff", quality = 1, stack = 1, class = "weapon", slot = "mainhand", damage = 2, spellpower = 2, buyprice = 60, level = 1 },
	{ name = "Novice's Staff", quality = 1, stack = 1, class = "weapon", slot = "mainhand", damage = 2, spellpower = 2, buyprice = 60, level = 1 },
	{ name = "Rusted Runeblade", quality = 2, stack = 1, class = "weapon", slot = "mainhand", damage = 6, strength = 2, buyprice = 500, level = 1 },
	-- racial food
	{ name = "Tough Hunk of Bread", quality = 1, stack = 20, class = "consumable", buyprice = 5, use = "Food", consumable = true },
	{ name = "Darnassian Bleu", quality = 1, stack = 20, class = "consumable", buyprice = 5, use = "Food", consumable = true },
	{ name = "Shiny Red Apple", quality = 1, stack = 20, class = "consumable", buyprice = 5, use = "Food", consumable = true },
	{ name = "Forsaken Hardbread", quality = 1, stack = 20, class = "consumable", buyprice = 5, use = "Food", consumable = true },
	-- the other paper-doll slots
	{ name = "Kobold Candle Pendant", quality = 2, stack = 1, class = "armor", slot = "neck", stamina = 2, intellect = 1, buyprice = 600, level = 3, flavor = "Still smells of tallow." },
	{ name = "Recruit's Gloves", quality = 1, stack = 1, class = "armor", slot = "hands", armor = 1, buyprice = 40, level = 1 },
	{ name = "Recruit's Belt", quality = 1, stack = 1, class = "armor", slot = "waist", armor = 1, buyprice = 40, level = 1 },
	{ name = "Recruit's Bracers", quality = 1, stack = 1, class = "armor", slot = "wrist", armor = 1, buyprice = 40, level = 1 },
	{ name = "Recruit's Shoulderpads", quality = 1, stack = 1, class = "armor", slot = "shoulders", armor = 2, buyprice = 80, level = 3 },
	{ name = "Linen Cloak", quality = 1, stack = 1, class = "armor", slot = "back", armor = 1, buyprice = 60, level = 2 },
	{ name = "Rough Wooden Shield", quality = 1, stack = 1, class = "armor", slot = "offhand", armor = 4, buyprice = 120, level = 1 },
	{ name = "Kobold Candle", quality = 2, stack = 1, class = "armor", slot = "trinket", spirit = 3, buyprice = 900, level = 4, flavor = "You take candle." },
	-- class quest rewards
	{ name = "Trainee's Broadsword", quality = 2, stack = 1, class = "weapon", slot = "mainhand", damage = 6, strength = 1, buyprice = 800, level = 3 },
	{ name = "Trainee's Hammer", quality = 2, stack = 1, class = "weapon", slot = "mainhand", damage = 5, strength = 1, intellect = 1, buyprice = 800, level = 3 },
	{ name = "Trainee's Bow", quality = 2, stack = 1, class = "weapon", slot = "mainhand", damage = 6, agility = 1, buyprice = 800, level = 3 },
	{ name = "Trainee's Dirk", quality = 2, stack = 1, class = "weapon", slot = "mainhand", damage = 4, agility = 2, buyprice = 800, level = 3 },
	{ name = "Trainee's Holy Staff", quality = 2, stack = 1, class = "weapon", slot = "mainhand", damage = 3, spellpower = 5, spirit = 1, buyprice = 800, level = 3 },
	{ name = "Trainee's Runeblade", quality = 2, stack = 1, class = "weapon", slot = "mainhand", damage = 8, strength = 2, buyprice = 800, level = 3 },
	{ name = "Trainee's Totem Mace", quality = 2, stack = 1, class = "weapon", slot = "mainhand", damage = 5, intellect = 2, buyprice = 800, level = 3 },
	{ name = "Trainee's Arcane Staff", quality = 2, stack = 1, class = "weapon", slot = "mainhand", damage = 3, spellpower = 5, intellect = 1, buyprice = 800, level = 3 },
	{ name = "Trainee's Shadow Staff", quality = 2, stack = 1, class = "weapon", slot = "mainhand", damage = 3, spellpower = 5, stamina = 1, buyprice = 800, level = 3 },
	{ name = "Trainee's Wild Staff", quality = 2, stack = 1, class = "weapon", slot = "mainhand", damage = 3, spellpower = 4, spirit = 2, buyprice = 800, level = 3 },
	-- the gamemaster's set, from .gm gear
	{ name = "Gamemaster's Hood", quality = 5, stack = 1, class = "armor", slot = "head", armor = 500, stamina = 200, strength = 100, intellect = 100, buyprice = 0, level = 1, bind = "pickup", flavor = "Whatever you say goes." },
	{ name = "Gamemaster's Robe", quality = 5, stack = 1, class = "armor", slot = "chest", armor = 800, stamina = 300, strength = 100, intellect = 100, spirit = 100, buyprice = 0, level = 1, bind = "pickup" },
	{ name = "Gamemaster's Leggings", quality = 5, stack = 1, class = "armor", slot = "legs", armor = 700, stamina = 250, agility = 100, buyprice = 0, level = 1, bind = "pickup" },
	{ name = "Gamemaster's Boots", quality = 5, stack = 1, class = "armor", slot = "feet", armor = 400, stamina = 150, agility = 100, buyprice = 0, level = 1, bind = "pickup" },
	{ name = "Gamemaster's Blade", quality = 5, stack = 1, class = "weapon", slot = "mainhand", damage = 500, spellpower = 500, buyprice = 0, level = 1, bind = "pickup", flavor = "One swing is usually enough." },
	{ name = "Gamemaster's Shield", quality = 5, stack = 1, class = "armor", slot = "offhand", armor = 900, stamina = 200, buyprice = 0, level = 1, bind = "pickup" },
	{ name = "Gamemaster's Band", quality = 5, stack = 1, class = "armor", slot = "ring", stamina = 100, intellect = 100, strength = 100, agility = 100, spirit = 100, buyprice = 0, level = 1, bind = "pickup" },
	{ name = "Gryphon Reins", quality = 3, stack = 1, class = "misc", buyprice = 5000000, level = 30, use = "Summon Gryphon", flavor = "The skies of Azeroth await." },
}

-- Item subclasses (TC's weapon and armor types) and hands by name, applied to
-- every seed and to old rows missing them.
local KIND = {
	["Worn Shortsword"] = { "sword", 1 }, ["Rough Copper Sword"] = { "sword", 1 }, ["Trainee's Broadsword"] = { "sword", 2 }, ["Rusted Runeblade"] = { "sword", 2 }, ["Trainee's Runeblade"] = { "sword", 2 },
	["Worn Mace"] = { "mace", 1 }, ["Trainee's Hammer"] = { "mace", 2 }, ["Trainee's Totem Mace"] = { "mace", 1 },
	["Worn Dagger"] = { "dagger", 1 }, ["Trainee's Dirk"] = { "dagger", 1 },
	["Worn Shortbow"] = { "bow", 2 }, ["Trainee's Bow"] = { "bow", 2 },
	["Neophyte's Staff"] = { "staff", 2 }, ["Apprentice's Staff"] = { "staff", 2 }, ["Acolyte's Staff"] = { "staff", 2 }, ["Novice's Staff"] = { "staff", 2 },
	["Trainee's Holy Staff"] = { "staff", 2 }, ["Trainee's Arcane Staff"] = { "staff", 2 }, ["Trainee's Shadow Staff"] = { "staff", 2 }, ["Trainee's Wild Staff"] = { "staff", 2 },
	["Rough Wooden Shield"] = { "shield", 1 },
	["Gamemaster's Blade"] = { "sword", 1 }, ["Gamemaster's Shield"] = { "shield", 1 },
}
local ARMOR_KIND = {
	plate = { "Acherus Knight's Tunic", "Acherus Knight's Legplates", "Acherus Knight's Boots", "Gamemaster's Hood", "Gamemaster's Robe", "Gamemaster's Leggings", "Gamemaster's Boots" },
	mail = { "Squire's Shirt", "Squire's Pants", "Squire's Boots", "Primitive Mantle", "Primitive Kilt", "Primitive Boots", "Copper Chain Belt", "Kobold Mining Helm" },
	leather = { "Trapper's Shirt", "Trapper's Pants", "Trapper's Boots", "Thug's Shirt", "Thug's Pants", "Thug's Boots", "Novice's Robe", "Novice's Pants", "Novice's Boots" },
	cloth = { "Recruit's Tunic", "Recruit's Pants", "Recruit's Boots", "Neophyte's Shirt", "Neophyte's Pants", "Neophyte's Boots", "Apprentice's Robe", "Apprentice's Pants", "Apprentice's Boots",
		"Acolyte's Robe", "Acolyte's Pants", "Acolyte's Boots", "Recruit's Gloves", "Recruit's Belt", "Recruit's Bracers", "Recruit's Shoulderpads", "Linen Cloak" },
}
local function kindOf(item)
	local out = {}
	local k = KIND[item.name]
	if k then
		out.subclass, out.hands = k[1], k[2]
	end
	for armor, names in ARMOR_KIND do
		if table.find(names, item.name) then
			out.armor = armor
		end
	end
	return out
end

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
		Bind = template.bind, Recipe = template.recipe, Mount = template.mount, Container = template.container, Subclass = template.subclass, Hands = template.hands, ArmorType = template.armor }
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
		for key, value in kindOf(item) do
			item[key] = value
		end
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
