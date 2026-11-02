local Base = require(game:GetService("ServerStorage").ServerModules["Template.h"])
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Opcodes = require(ReplicatedStorage.Shared.Opcodes)
local Config = require(ReplicatedStorage.Shared.Config)
local Players = game:GetService("Players")
local module = {}

-- Loot windows, WoW style, over any source: a corpse, a chest, a gathering
-- node. A source is { Guid, Name, Root, Loot = { Items = { { Entry, Count } },
-- Money }, MayLoot = fn(player)?, OnEmpty = fn() }. The opener takes items one
-- by one or the money; an emptied source gets OnEmpty.

local LOOT_RANGE = 10
local sources = {}
local rolls = {}
local nextRoll = 0

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
	if self:IsEmpty(source.Loot) and (source.Rolling or 0) == 0 then
		self:Unregister(source.Guid)
		self:Release(player)
		if source.OnEmpty then
			source.OnEmpty()
		end
	end
end

-- Group loot: in a party, an item at or above Config.Loot.RollQuality starts a
-- Need, Greed or Pass roll among the members nearby instead of being taken.
function module:StartRoll(player: Player, source, index: number, entry)
	local Party = self.includes.Social["Party.h"]
	local Items = self.includes.Content["Items.h"]
	local members = {}
	for _, member in Party:MembersOf(player) do
		local root = member.Character and member.Character:FindFirstChild("HumanoidRootPart")
		if root and source.Root and (root.Position - source.Root.Position).Magnitude <= 100 then
			table.insert(members, member)
		end
	end
	if #members < 2 then
		return false
	end
	nextRoll += 1
	local item = Items:Describe(entry.Entry, { Count = entry.Count })
	local roll = { Id = nextRoll, Source = source, Index = index, Entry = entry, Item = item, Players = members, Votes = {}, Ends = os.time() + Config.Loot.RollSeconds }
	rolls[roll.Id] = roll
	source.Loot.Items[index] = nil
	source.Rolling = (source.Rolling or 0) + 1
	for _, member in members do
		self.includes.Security["Packet.h"]:Send(member, Opcodes.SMSG_LOOT_ROLL_START, { Id = roll.Id, Item = item, Seconds = Config.Loot.RollSeconds })
	end
	self.includes.Security["Packet.h"]:Send(player, Opcodes.SMSG_LOOT_REMOVED, { Index = index })
	return true
end

function module:Vote(player: Player, id, vote: string)
	local roll = rolls[id]
	if not roll or not table.find(roll.Players, player) or roll.Votes[player] or not table.find({ "need", "greed", "pass" }, vote) then
		return
	end
	roll.Votes[player] = vote
	local name = player:GetAttribute("CharacterName") or player.Name
	local text = ("%s has selected %s for: [%s]"):format(name, vote:sub(1, 1):upper() .. vote:sub(2), roll.Item.Name)
	for _, member in roll.Players do
		self.includes.Chat["Chat.h"]:System(member, text)
	end
	for _, member in roll.Players do
		if member.Parent == Players and not roll.Votes[member] then
			return
		end
	end
	self:Resolve(roll)
end

function module:Resolve(roll)
	rolls[roll.Id] = nil
	local Chat = self.includes.Chat["Chat.h"]
	local best, bestRoll, bestVote = nil, 0, nil
	for _, member in roll.Players do
		local vote = roll.Votes[member] or "pass"
		if member.Parent == Players and vote ~= "pass" then
			local r = math.random(1, 100)
			local beats = best == nil or (vote == "need" and bestVote ~= "need") or (vote == bestVote and r > bestRoll)
			for _, other in roll.Players do
				Chat:System(other, ("%s rolls %d (1-100) for [%s] (%s)."):format(member:GetAttribute("CharacterName") or member.Name, r, roll.Item.Name, vote))
			end
			if beats then
				best, bestRoll, bestVote = member, r, vote
			end
		end
	end
	local source = roll.Source
	source.Rolling = math.max(0, (source.Rolling or 1) - 1)
	if not best then
		for _, other in roll.Players do
			Chat:System(other, ("Everyone passed on [%s]."):format(roll.Item.Name))
		end
		source.Loot.Items[roll.Index] = roll.Entry
		return
	end
	for _, other in roll.Players do
		Chat:System(other, ("%s won: [%s]"):format(best:GetAttribute("CharacterName") or best.Name, roll.Item.Name))
	end
	local Entities = self.includes.Entities["EntityPlayer.h"]
	if not Entities:AddItem(best, roll.Entry.Entry, roll.Entry.Count) then
		self.includes.Mail["Mail.h"]:Deliver(best:GetAttribute("CharacterName") or best.Name, { Sender = "Group Loot", Subject = roll.Item.Name, Body = "Your bags were full when you won this roll.", Items = { { Entry = roll.Entry.Entry, Count = roll.Entry.Count } }, Money = 0 })
	end
	if source.Rolling == 0 and self:IsEmpty(source.Loot) and self:Source(source.Guid) == source then
		self:Unregister(source.Guid)
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
	local template = self.includes.Content["Items.h"]:Template(entry.Entry)
	if template and (template.quality or 1) >= Config.Loot.RollQuality then
		local method, master = self.includes.Social["Party.h"]:LootMethod(player)
		if method == "master" and master and master ~= player then
			return self.includes.Chat["Chat.h"]:System(player, ("Only the master looter, %s, may take that."):format(master:GetAttribute("CharacterName") or master.Name))
		elseif method == "group" and self:StartRoll(player, source, index, entry) then
			return
		end
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
	Packet:On(Opcodes.CMSG_LOOT_ROLL, function(player, data)
		if typeof(data) == "table" then
			self:Vote(player, tonumber(data.Id), tostring(data.Vote))
		end
	end)
	task.spawn(function()
		while true do
			task.wait(1)
			for _, roll in rolls do
				if os.time() >= roll.Ends then
					self:Resolve(roll)
				end
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		self.information[player] = nil
	end)
end

return Base(module, {
	{ Path = "Auth/Security", Imports = "Packet.h" },
	{ Path = "Auth/Entities", Imports = "EntityPlayer.h" },
	{ Path = "Auth/Chat", Imports = "Chat.h" },
	{ Path = "Auth/Social", Imports = "Party.h" },
	{ Path = "World/Content", Imports = "Items.h" },
	{ Path = "World/Mail", Imports = "Mail.h" },
	{ Path = "World/Database", Imports = "WorldDB.h" },
})
