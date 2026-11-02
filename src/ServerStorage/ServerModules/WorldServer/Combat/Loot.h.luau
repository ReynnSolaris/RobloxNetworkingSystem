local Base = require(game:GetService("ServerStorage").ServerModules["Template.h"])
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Opcodes = require(ReplicatedStorage.Shared.Opcodes)
local module = {}

-- Loot windows, WoW style, over any source: a corpse, a chest, a gathering
-- node. A source is { Guid, Name, Root, Loot = { Items = { { Entry, Count } },
-- Money }, MayLoot = fn(player)?, OnEmpty = fn() }. The opener takes items one
-- by one or the money; an emptied source gets OnEmpty.

local LOOT_RANGE = 10
local sources = {}

function module:Register(source)
	sources[tostring(source.Guid)] = source
	return source
end

function module:Unregister(guid)
	sources[tostring(guid)] = nil
end

function module:Source(guid)
	return sources[tostring(guid)]
end

-- Rolls a loot table's rows for an entry: { id, entry, item, chance, mincount, maxcount }.
function module:Roll(tableName: string, entry, mingold: number?, maxgold: number?)
	local loot = { Items = {}, Money = 0 }
	for _, row in self.includes.Database["WorldDB.h"]:Select(tableName) do
		if tostring(row.entry) == tostring(entry) and math.random() * 100 < (row.chance or 0) then
			table.insert(loot.Items, { Entry = row.item, Count = math.random(row.mincount or 1, math.max(row.maxcount or 1, row.mincount or 1)) })
		end
	end
	loot.Money = math.random(mingold or 0, math.max(maxgold or 0, mingold or 0))
	return loot
end

function module:IsEmpty(loot): boolean
	if (loot.Money or 0) > 0 then
		return false
	end
	for _ in loot.Items do
		return false
	end
	return true
end

local function describe(self, loot)
	local Items = self.includes.Content["Items.h"]
	local items = {}
	for index, entry in loot.Items do
		items[index] = Items:Describe(entry.Entry, { Index = index, Count = entry.Count })
	end
	return items
end

function module:Open(player: Player, guid)
	local source = self:Source(guid)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not source or not root or not source.Root or not source.Root.Parent then
		return
	end
	if (source.Root.Position - root.Position).Magnitude > LOOT_RANGE then
		return self.includes.Chat["Chat.h"]:System(player, "You are too far away.")
	end
	if source.MayLoot and not source.MayLoot(player) then
		return self.includes.Chat["Chat.h"]:System(player, "You don't have permission to loot that.")
	end
	self.information[player] = tostring(guid)
	self.includes.Security["Packet.h"]:Send(player, Opcodes.SMSG_LOOT_RESPONSE,
		{ Guid = tostring(guid), Name = source.Name, Items = describe(self, source.Loot), Money = source.Loot.Money or 0 })
end

local function current(self, player: Player)
	local guid = self.information[player]
	return guid and self:Source(guid)
end

local function settle(self, player: Player, source)
	if self:IsEmpty(source.Loot) then
		self:Unregister(source.Guid)
		self:Release(player)
		if source.OnEmpty then
			source.OnEmpty()
		end
	end
end

function module:TakeItem(player: Player, index: number)
	local source = current(self, player)
	local entry = source and source.Loot.Items[index]
	if not entry then
		return
	end
	if self.includes.Entities["EntityPlayer.h"]:AddItem(player, entry.Entry, entry.Count) then
		source.Loot.Items[index] = nil
		self.includes.Security["Packet.h"]:Send(player, Opcodes.SMSG_LOOT_REMOVED, { Index = index })
		settle(self, player, source)
	end
end

function module:TakeMoney(player: Player)
	local source = current(self, player)
	if not source or (source.Loot.Money or 0) == 0 then
		return
	end
	self.includes.Entities["EntityPlayer.h"]:AddMoney(player, source.Loot.Money)
	source.Loot.Money = 0
	self.includes.Security["Packet.h"]:Send(player, Opcodes.SMSG_LOOT_REMOVED, { Money = true })
	settle(self, player, source)
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
	{ Path = "World/Content", Imports = "Items.h" },
	{ Path = "World/Database", Imports = "WorldDB.h" },
})
