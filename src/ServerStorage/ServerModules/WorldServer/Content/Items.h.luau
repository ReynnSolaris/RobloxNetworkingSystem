local Base = require(game:GetService("ServerStorage").ServerModules["Template.h"])
local Opcodes = require(game:GetService("ReplicatedStorage").Shared.Opcodes)
local module = {}

-- item_template: { entry, name, quality 0-5, stack }. Inventories live on the
-- character record; this module seeds the table and answers CMSG_INVENTORY.

local SEED = {
	{ name = "Hearthstone", quality = 1, stack = 1 },
	{ name = "Linen Cloth", quality = 1, stack = 20 },
	{ name = "Worn Shortsword", quality = 1, stack = 1 },
	{ name = "Tough Jerky", quality = 1, stack = 20 },
	{ name = "Ring of Precision", quality = 3, stack = 1 },
}

function module:Start()
	local DB = self.includes.Database["WorldDB.h"]
	if #DB:Select("item_template") == 0 then
		for _, item in SEED do
			DB:Insert("item_template", item)
		end
	end
	self.includes.Security["Packet.h"]:On(Opcodes.CMSG_INVENTORY, function(player)
		self.includes.Entities["EntityPlayer.h"]:SendInventory(player)
	end)
end

return Base(module, {
	{ Path = "World/Database", Imports = "WorldDB.h" },
	{ Path = "Auth/Security", Imports = "Packet.h" },
	{ Path = "Auth/Entities", Imports = "EntityPlayer.h" },
})
