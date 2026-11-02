local Base = require(game:GetService("ServerStorage").ServerModules["Template.h"])
local Opcodes = require(game:GetService("ReplicatedStorage").Shared.Opcodes)
local module = {}

-- item_template: { entry, name, quality 0-5, stack, class (weapon|armor|consumable|misc),
-- slot, health, damage, armor, buyprice, sellprice (copper), level }.
-- Seeds reach existing databases by name; missing columns on old rows are filled.

local SEED = {
	{ name = "Hearthstone", quality = 1, stack = 1, class = "misc", buyprice = 0 },
	{ name = "Linen Cloth", quality = 1, stack = 20, class = "misc", buyprice = 10 },
	{ name = "Worn Shortsword", quality = 1, stack = 1, class = "weapon", slot = "mainhand", damage = 3, buyprice = 60, level = 1 },
	{ name = "Tough Jerky", quality = 1, stack = 20, class = "consumable", buyprice = 5 },
	{ name = "Ring of Precision", quality = 3, stack = 1, class = "armor", slot = "ring", damage = 2, health = 10, buyprice = 2500, level = 3 },
	{ name = "Recruit's Tunic", quality = 1, stack = 1, class = "armor", slot = "chest", health = 15, armor = 1, buyprice = 80, level = 1 },
	{ name = "Recruit's Pants", quality = 1, stack = 1, class = "armor", slot = "legs", health = 10, armor = 1, buyprice = 60, level = 1 },
	{ name = "Recruit's Boots", quality = 1, stack = 1, class = "armor", slot = "feet", health = 5, buyprice = 40, level = 1 },
	{ name = "Kobold Mining Helm", quality = 2, stack = 1, class = "armor", slot = "head", health = 12, armor = 1, buyprice = 400, level = 2 },
}

function module:Start()
	local DB = self.includes.Database["WorldDB.h"]
	local byName = {}
	for _, row in DB:Select("item_template") do
		byName[row.name] = row
	end
	for _, item in SEED do
		local existing = byName[item.name]
		if not existing then
			byName[item.name] = DB:Insert("item_template", table.clone(item))
		elseif existing.class == nil then
			local fields = table.clone(item)
			fields.name, fields.quality, fields.stack = nil, nil, nil
			DB:Update("item_template", existing.entry, fields)
		end
	end
	self.includes.Security["Packet.h"]:On(Opcodes.CMSG_INVENTORY, function(player)
		self.includes.Entities["EntityPlayer.h"]:SendInventory(player, true)
	end)
end

return Base(module, {
	{ Path = "World/Database", Imports = "WorldDB.h" },
	{ Path = "Auth/Security", Imports = "Packet.h" },
	{ Path = "Auth/Entities", Imports = "EntityPlayer.h" },
})
