local Base = require(game:GetService("ServerStorage").ServerModules["Template.h"])
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Opcodes = require(ReplicatedStorage.Shared.Opcodes)
local module = {}

-- Corpse loot, WoW style. A killed creature keeps its rolled loot on its state;
-- the killer (or their party) opens it with the Loot prompt and takes items one by
-- one or the money; an emptied corpse clears. information[player] = guid being looted.

local LOOT_RANGE = 10

local function describe(self, loot)
	local DB = self.includes.Database["WorldDB.h"]
	local items = {}
	for index, entry in loot.Items do
		local template = DB:Get("item_template", entry.Entry) or {}
		items[index] = { Index = index, Entry = entry.Entry, Count = entry.Count, Name = template.name or "?", Quality = template.quality or 1,
			Slot = template.slot, Class = template.class, Level = template.level, Health = template.health, Damage = template.damage, Armor = template.armor }
	end
	return items
end

local function mayLoot(self, player: Player, creature): boolean
	local killer = creature.LastAttacker
	if not killer or killer == player then
		return true
	end
	return table.find(self.includes.Social["Party.h"]:MembersOf(killer), player) ~= nil
end

function module:Open(player: Player, guid)
	local Creatures = self.includes.Content["Creatures.h"]
	local creature = Creatures:State(guid)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not creature or not creature.Dead or not creature.Loot or not root then
		return
	end
	if (creature.Root.Position - root.Position).Magnitude > LOOT_RANGE then
		return self.includes.Chat["Chat.h"]:System(player, "You are too far away.")
	end
	if not mayLoot(self, player, creature) then
		return self.includes.Chat["Chat.h"]:System(player, "You don't have permission to loot that corpse.")
	end
	self.information[player] = tostring(guid)
	self.includes.Security["Packet.h"]:Send(player, Opcodes.SMSG_LOOT_RESPONSE,
		{ Guid = tostring(guid), Name = creature.Template.name, Items = describe(self, creature.Loot), Money = creature.Loot.Money or 0 })
end

local function current(self, player: Player)
	local guid = self.information[player]
	local creature = guid and self.includes.Content["Creatures.h"]:State(guid)
	return guid, creature
end

local function settle(self, player: Player, creature)
	local loot = creature.Loot
	local empty = (loot.Money or 0) == 0
	for _ in loot.Items do
		empty = false
	end
	if empty then
		self.includes.Content["Creatures.h"]:ClearCorpse(creature.Row.guid)
		self:Release(player)
	end
end

function module:TakeItem(player: Player, index: number)
	local _, creature = current(self, player)
	local entry = creature and creature.Loot and creature.Loot.Items[index]
	if not entry then
		return
	end
	if self.includes.Entities["EntityPlayer.h"]:AddItem(player, entry.Entry, entry.Count) then
		creature.Loot.Items[index] = nil
		self.includes.Security["Packet.h"]:Send(player, Opcodes.SMSG_LOOT_REMOVED, { Index = index })
		settle(self, player, creature)
	end
end

function module:TakeMoney(player: Player)
	local _, creature = current(self, player)
	if not creature or not creature.Loot or (creature.Loot.Money or 0) == 0 then
		return
	end
	self.includes.Entities["EntityPlayer.h"]:AddMoney(player, creature.Loot.Money)
	creature.Loot.Money = 0
	self.includes.Security["Packet.h"]:Send(player, Opcodes.SMSG_LOOT_REMOVED, { Money = true })
	settle(self, player, creature)
end

function module:Release(player: Player)
	if self.information[player] then
		self.information[player] = nil
		self.includes.Security["Packet.h"]:Send(player, Opcodes.SMSG_LOOT_RELEASE_RESPONSE, {})
	end
end

function module:Start()
	local Packet = self.includes.Security["Packet.h"]
	Packet:On(Opcodes.CMSG_LOOT, function(player, data)
		if typeof(data) == "table" and data.Guid ~= nil then
			self:Open(player, data.Guid)
		end
	end)
	Packet:On(Opcodes.CMSG_AUTOSTORE_LOOT_ITEM, function(player, data)
		if typeof(data) == "table" then
			self:TakeItem(player, tonumber(data.Index) or 0)
		end
	end)
	Packet:On(Opcodes.CMSG_LOOT_MONEY, function(player)
		self:TakeMoney(player)
	end)
	Packet:On(Opcodes.CMSG_LOOT_RELEASE, function(player)
		self:Release(player)
	end)
	game:GetService("Players").PlayerRemoving:Connect(function(player)
		self.information[player] = nil
	end)
end

return Base(module, {
	{ Path = "Auth/Security", Imports = "Packet.h" },
	{ Path = "Auth/Entities", Imports = "EntityPlayer.h" },
	{ Path = "Auth/Chat", Imports = "Chat.h" },
	{ Path = "Auth/Social", Imports = "Party.h" },
	{ Path = "World/Content", Imports = "Creatures.h" },
	{ Path = "World/Database", Imports = "WorldDB.h" },
})
