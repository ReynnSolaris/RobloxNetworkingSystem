local Base = require(game:GetService("ServerStorage").ServerModules["Template.h"])
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Opcodes = require(ReplicatedStorage.Shared.Opcodes)
local module = {}

-- Achievements. achievement: { id, name, description, category, points,
-- criteria = { type = level|kills|quests|explore|money|honor|skill|duels|
-- reputation, value, name? } }. A character keeps Achievements = { [id] = time }
-- and the counters the criteria read (Kills, QuestsDone, Explored, DuelsWon).
-- Earning one toasts the player, tells nearby players and the guild.

local SEED = {
	{ name = "Level 10", description = "Reach level 10.", category = "General", points = 10, criteria = { type = "level", value = 10 } },
	{ name = "Level 20", description = "Reach level 20.", category = "General", points = 10, criteria = { type = "level", value = 20 } },
	{ name = "Level 40", description = "Reach level 40.", category = "General", points = 10, criteria = { type = "level", value = 40 } },
	{ name = "Level 80", description = "Reach level 80.", category = "General", points = 20, criteria = { type = "level", value = 80 } },
	{ name = "Creature Comforts", description = "Slay 50 creatures.", category = "Kill", points = 10, criteria = { type = "kills", value = 50 } },
	{ name = "Need More Candles", description = "Slay 500 creatures.", category = "Kill", points = 10, criteria = { type = "kills", value = 500 }, title = "Candlekeeper %s" },
	{ name = "First Steps", description = "Complete a quest.", category = "Quests", points = 10, criteria = { type = "quests", value = 1 } },
	{ name = "50 Quests Completed", description = "Complete 50 quests.", category = "Quests", points = 10, criteria = { type = "quests", value = 50 } },
	{ name = "Explore Northshire", description = "Discover Northshire Valley.", category = "Exploration", points = 10, criteria = { type = "explore", name = "Northshire Valley" } },
	{ name = "Explore Elwynn Forest", description = "Discover Elwynn Forest.", category = "Exploration", points = 10, criteria = { type = "explore", name = "Elwynn Forest" }, title = "%s the Explorer" },
	{ name = "Got My Mind On My Money", description = "Loot 100 gold.", category = "General", points = 10, criteria = { type = "money", value = 1000000 } },
	{ name = "Duel-icious", description = "Win a duel.", category = "PvP", points = 10, criteria = { type = "duels", value = 1 }, title = "%s the Duelist" },
	{ name = "That Takes Class", description = "Earn 10 honorable kills.", category = "PvP", points = 10, criteria = { type = "honor", value = 10 } },
	{ name = "Journeyman Cook", description = "Reach 75 skill in Cooking.", category = "Professions", points = 10, criteria = { type = "skill", name = "Cooking", value = 75 } },
	{ name = "Professional", description = "Reach 75 skill in any profession.", category = "Professions", points = 10, criteria = { type = "skill", value = 75 } },
	{ name = "Somebody Likes Me", description = "Reach Honored with a faction.", category = "Reputation", points = 10, criteria = { type = "reputation", value = 9000 } },
}

function module:DB()
	return self.includes.Database["WorldDB.h"]
end

local function char(self, player: Player)
	local entity = self.includes.Entities["EntityPlayer.h"]:Get(player)
	local c = entity and entity.Active
	if c then
		c.Achievements = c.Achievements or {}
	end
	return c
end

function module:Sync(player: Player)
	local c = char(self, player)
	if not c then
		return
	end
	local list, points = {}, 0
	for _, row in self:DB():Select("achievement") do
		local when = c.Achievements[tostring(row.id)]
		if when then
			points += row.points or 10
		end
		table.insert(list, { Id = row.id, Name = row.name, Description = row.description, Category = row.category, Points = row.points or 10, Earned = when })
	end
	player:SetAttribute("Achievements", HttpService:JSONEncode({ Points = points, List = list }))
end

function module:Award(player: Player, row)
	local c = char(self, player)
	if not c or c.Achievements[tostring(row.id)] then
		return
	end
	c.Achievements[tostring(row.id)] = os.time()
	self.includes.Database["WorldDatabase.h"]:Commit(player)
	if row.title then
		self.includes.Social["Titles.h"]:Grant(player, row.title)
	end
	local Packet = self.includes.Security["Packet.h"]
	Packet:Send(player, Opcodes.SMSG_ACHIEVEMENT_EARNED, { Id = row.id, Name = row.name, Description = row.description, Points = row.points or 10 })
	local name = player:GetAttribute("CharacterName") or player.Name
	local text = ("%s has earned the achievement [%s]!"):format(name, row.name)
	local Functions = self.includes.Chat["ChatFunctions.h"]
	local Registry = self.includes.Chat["ChatRegistry.h"]
	local told = { [player] = true }
	for _, channel in { "SAY", "GUILD" } do
		for _, recipient in Functions:Recipients(Registry:Get(channel), player) do
			told[recipient] = true
		end
	end
	for recipient in told do
		if recipient ~= player then
			self.includes.Chat["Chat.h"]:System(recipient, text)
		end
	end
	self:Sync(player)
end

-- Check every achievement of a criteria type against the character's counters.
function module:Check(player: Player, kind: string, value: number?, name: string?)
	local c = char(self, player)
	if not c then
		return
	end
	for _, row in self:DB():Select("achievement") do
		local crit = row.criteria or {}
		if crit.type == kind and not c.Achievements[tostring(row.id)] then
			local nameOk = crit.name == nil or crit.name == name
			local valueOk = crit.value == nil or (value or 0) >= crit.value
			if nameOk and valueOk then
				self:Award(player, row)
			end
		end
	end
end

function module:OnLevel(player: Player, level: number)
	self:Check(player, "level", level)
end

function module:OnKill(player: Player)
	local c = char(self, player)
	if c then
		c.Kills = (c.Kills or 0) + 1
		self:Check(player, "kills", c.Kills)
	end
end

function module:OnQuest(player: Player)
	local c = char(self, player)
	if c then
		c.QuestsDone = (c.QuestsDone or 0) + 1
		self:Check(player, "quests", c.QuestsDone)
	end
end

function module:OnExplore(player: Player, zone: string)
	self:Check(player, "explore", nil, zone)
end

function module:OnMoney(player: Player, total: number)
	self:Check(player, "money", total)
end

function module:OnDuel(player: Player)
	local c = char(self, player)
	if c then
		c.DuelsWon = (c.DuelsWon or 0) + 1
		self:Check(player, "duels", c.DuelsWon)
	end
end

function module:OnHonor(player: Player, kills: number)
	self:Check(player, "honor", kills)
end

function module:OnSkill(player: Player, skill: string, value: number)
	self:Check(player, "skill", value, skill)
	self:Check(player, "skill", value, nil)
end

function module:OnReputation(player: Player, value: number)
	self:Check(player, "reputation", value)
end

function module:OnLogin(player: Player)
	local c = char(self, player)
	if c then
		self:Check(player, "level", c.Level or 1)
		self:Sync(player)
	end
end

function module:Start()
	local DB = self:DB()
	local byName = {}
	for _, row in DB:Select("achievement") do
		byName[row.name] = row
	end
	for _, seed in SEED do
		if not byName[seed.name] then
			DB:Insert("achievement", table.clone(seed))
		end
	end
end

return Base(module, {
	{ Path = "Auth/Security", Imports = "Packet.h" },
	{ Path = "Auth/Entities", Imports = "EntityPlayer.h" },
	{ Path = "Auth/Chat", Imports = "Chat.h|ChatFunctions.h|ChatRegistry.h" },
	{ Path = "Auth/Social", Imports = "Titles.h" },
	{ Path = "World/Database", Imports = "WorldDB.h|WorldDatabase.h" },
})
