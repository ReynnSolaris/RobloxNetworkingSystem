local Base = require(game:GetService("ServerStorage").ServerModules["Template.h"])
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Opcodes = require(ReplicatedStorage.Shared.Opcodes)
local Config = require(ReplicatedStorage.Shared.Config)
local module = {}

-- quest_template: { id, title, details, objectives, minlevel, level, reward_xp,
-- reward_money, reward_items = { { entry, count } }, req_creature = { { entry, count } },
-- req_item = { { entry, count } }, class?, race?, prevquest? (a chain), reward_rep? }. creature_queststarter / creature_questender:
-- { id, entry (creature), quest }. A character's quest state lives on its record:
-- Quests = { [questId] = { Status = active|complete, Kills = { [entry] = n } } },
-- Done = { [questId] = true }.

local SEED = {
	{
		title = "Vermin Problem",
		details = "Kobolds have crept into the valley again, digging up every cellar and candle they can find. Thin their numbers before they grow bold.",
		objectives = "Slay 5 Kobold Vermin and return to the Town Guard.",
		minlevel = 1, level = 2, reward_xp = 150, reward_money = 50,
		reward_items = { { item = "Recruit's Tunic", count = 1 } },
		req_creature = { { creature = "Kobold Vermin", count = 5 } },
		starter = "Town Guard", ender = "Town Guard",
	},
	{
		title = "Wolves at the Gate",
		details = "Young wolves have taken to the road and the travellers have taken to my common room, which would be fine if any of them paid. Clear the wolves and bring me cloth for bandages.",
		objectives = "Slay 3 Young Wolves and bring 3 Linen Cloth to the Innkeeper.",
		minlevel = 1, level = 3, reward_xp = 220, reward_money = 80,
		reward_items = { { item = "Recruit's Boots", count = 1 } },
		req_creature = { { creature = "Young Wolf", count = 3 } },
		req_item = { { item = "Linen Cloth", count = 3 } },
		starter = "Innkeeper", ender = "Innkeeper",
	},
	{
		title = "Goldtooth's Candles",
		details = "The kobolds you thinned answer to a chieftain called Goldtooth, who hoards every candle in the valley. Put him down before the rest rally to him.",
		objectives = "Slay Goldtooth and return to the Town Guard.",
		minlevel = 4, level = 6, reward_xp = 600, reward_money = 500, prevquest = "Vermin Problem",
		reward_items = { { item = "Kobold Candle Pendant", count = 1 } },
		req_creature = { { creature = "Goldtooth", count = 1 } },
		starter = "Town Guard", ender = "Town Guard",
	},
}
-- one per class from the class trainer: prove yourself on the kobolds, take a weapon
local CLASS_QUESTS = {
	Warrior = { title = "The Way of Arms", weapon = "Trainee's Broadsword" }, Paladin = { title = "The Light's Charge", weapon = "Trainee's Hammer" },
	Hunter = { title = "Etched Sigil", weapon = "Trainee's Bow" }, Rogue = { title = "Encrypted Letter", weapon = "Trainee's Dirk" },
	Priest = { title = "Hallowed Scroll", weapon = "Trainee's Holy Staff" }, ["Death Knight"] = { title = "In Service of the Lich King", weapon = "Trainee's Runeblade" },
	Shaman = { title = "Call of Earth", weapon = "Trainee's Totem Mace" }, Mage = { title = "Glyphic Letter", weapon = "Trainee's Arcane Staff" },
	Warlock = { title = "Tainted Scroll", weapon = "Trainee's Shadow Staff" }, Druid = { title = "Verdant Note", weapon = "Trainee's Wild Staff" },
}
for class, info in CLASS_QUESTS do
	table.insert(SEED, {
		title = info.title, class = class,
		details = ("Your trainer wants proof that a %s of Northshire can hold their own. Kobolds will do; bring back three of their candles as well."):format(class),
		objectives = "Slay 4 Kobold Vermin and collect 3 Linen Cloth, then return to the Class Trainer.",
		minlevel = 2, level = 3, reward_xp = 250, reward_money = 100,
		reward_items = { { item = info.weapon, count = 1 } },
		req_creature = { { creature = "Kobold Vermin", count = 4 } },
		req_item = { { item = "Linen Cloth", count = 3 } },
		starter = "Class Trainer", ender = "Class Trainer",
	})
end

function module:DB()
	return self.includes.Database["WorldDB.h"]
end

function module:Template(id)
	return self:DB():Get("quest_template", id)
end

local function char(self, player: Player)
	local entity = self.includes.Entities["EntityPlayer.h"]:Get(player)
	local c = entity and entity.Active
	if c then
		c.Quests = c.Quests or {}
		c.Done = c.Done or {}
	end
	return c
end

local function commit(self, player: Player)
	self.includes.Database["WorldDatabase.h"]:Commit(player)
end

-- rows for a creature entry
local function startersOf(self, entry)
	local out = {}
	for _, row in self:DB():Select("creature_queststarter") do
		if tostring(row.entry) == tostring(entry) then
			table.insert(out, row.quest)
		end
	end
	return out
end

local function endersOf(self, entry)
	local out = {}
	for _, row in self:DB():Select("creature_questender") do
		if tostring(row.entry) == tostring(entry) then
			table.insert(out, row.quest)
		end
	end
	return out
end

-- May this character take the quest: level, class, race and the quest before it.
function module:Eligible(c, template): boolean
	if (c.Level or 1) < (template.minlevel or 1) then
		return false
	elseif template.class and template.class ~= c.Class then
		return false
	elseif template.race and template.race ~= c.Race then
		return false
	elseif template.prevquest and not (c.Done or {})[tostring(template.prevquest)] then
		return false
	end
	return true
end

function module:IsQuestgiver(entry): boolean
	return #startersOf(self, entry) > 0 or #endersOf(self, entry) > 0
end

-- Objective progress for one active quest: list of { Text, Have, Need }.
function module:Progress(player: Player, id)
	local c = char(self, player)
	local template = self:Template(id)
	local state = c and c.Quests[tostring(id)]
	if not template or not state then
		return {}
	end
	local DB = self:DB()
	local lines = {}
	for _, req in (template.req_creature or {}) do
		local creature = DB:Get("creature_template", req.entry) or {}
		table.insert(lines, { Text = (creature.name or "?") .. " slain", Have = math.min(state.Kills[tostring(req.entry)] or 0, req.count), Need = req.count })
	end
	for _, req in (template.req_item or {}) do
		local item = DB:Get("item_template", req.entry) or {}
		table.insert(lines, { Text = item.name or "?", Have = math.min(self.includes.Entities["EntityPlayer.h"]:CountItem(player, req.entry), req.count), Need = req.count })
	end
	return lines
end

function module:IsComplete(player: Player, id): boolean
	for _, line in self:Progress(player, id) do
		if line.Have < line.Need then
			return false
		end
	end
	return true
end

-- Status a questgiver shows this player: "available", "complete", "incomplete" or nil.
function module:StatusFor(player: Player, entry): string?
	local c = char(self, player)
	if not c then
		return nil
	end
	local level = c.Level or 1
	for _, id in endersOf(self, entry) do
		local state = c.Quests[tostring(id)]
		if state then
			return if self:IsComplete(player, id) then "complete" else "incomplete"
		end
	end
	for _, id in startersOf(self, entry) do
		local template = self:Template(id)
		if template and not c.Quests[tostring(id)] and not c.Done[tostring(id)] and self:Eligible(c, template) then
			return "available"
		end
	end
	return nil
end

-- Every spawned questgiver's status, for the markers.
function module:SendStatuses(player: Player)
	local list = {}
	for guid, state in self.includes.Content["Creatures.h"].information do
		if not state.Dead and self:IsQuestgiver(state.Row.id) then
			list[guid] = self:StatusFor(player, state.Row.id) or "none"
		end
	end
	self.includes.Security["Packet.h"]:Send(player, Opcodes.SMSG_QUESTGIVER_STATUS_MULTIPLE, { Statuses = list })
end

function module:SendLog(player: Player)
	local c = char(self, player)
	if not c then
		return
	end
	local log = {}
	for id, state in c.Quests do
		local template = self:Template(id)
		if template then
			table.insert(log, { Id = tonumber(id), Title = template.title, Level = template.level, Objectives = template.objectives,
				Complete = self:IsComplete(player, id), Progress = self:Progress(player, id) })
		end
	end
	table.sort(log, function(a, b)
		return a.Id < b.Id
	end)
	self.includes.Security["Packet.h"]:Send(player, Opcodes.SMSG_QUESTLOG, { Quests = log })
end

local function describe(self, id, status: string)
	local template = self:Template(id)
	local DB = self:DB()
	local rewards = {}
	for _, reward in (template.reward_items or {}) do
		table.insert(rewards, self.includes.Content["Items.h"]:Describe(reward.entry, { Count = reward.count }))
	end
	return { Id = template.id, Title = template.title, Details = template.details, Objectives = template.objectives, Level = template.level,
		RewardXp = template.reward_xp or 0, RewardMoney = template.reward_money or 0, RewardItems = rewards, Status = status }
end

-- Talk. The gossip window lists the NPC's quests and its options (training,
-- goods, home binding); an NPC with a single purpose and no quests skips the
-- window and goes straight there.
function module:Gossip(player: Player, guid)
	local creature = self.includes.Content["Creatures.h"]:State(guid)
	if not creature then
		return
	end
	local entry, template = creature.Row.id, creature.Template
	local options = {}
	local Death = self.includes.Combat["Death.h"]
	if template.spirithealer then
		if Death:IsDead(player) then
			table.insert(options, { Id = "spirithealer", Text = "Return me to life. (I accept the sickness and the wear on my gear.)" })
			return self:Hello(player, guid, options)
		end
		return
	end
	if Death:IsDead(player) then
		return
	end
	if self.includes.Content["Creatures.h"]:IsHostileTo(creature, player) then
		return self.includes.Chat["Chat.h"]:System(player, ("%s has nothing to say to you."):format(template.name))
	end
	if self.includes.Spells["Spells.h"]:IsTrainer(entry) then
		table.insert(options, { Id = "train", Text = "I seek training." })
	end
	if #self.includes.Content["Vendors.h"]:Stock(entry) > 0 then
		table.insert(options, { Id = "vendor", Text = "Let me browse your goods." })
	end
	if template.innkeeper then
		table.insert(options, { Id = "bind", Text = "Make this inn your home." })
	end
	if template.banker then
		table.insert(options, { Id = "bank", Text = "I would like to check my deposit box." })
		if self.includes.Social["Guild.h"]:Of(player) then
			table.insert(options, { Id = "guildbank", Text = "I would like to open the guild vault." })
		end
	end
	if template.trainer_skill then
		table.insert(options, { Id = "profession", Text = "I would like to learn a profession." })
	end
	if template.repair then
		local cost = self.includes.Entities["EntityPlayer.h"]:RepairCost(player)
		table.insert(options, { Id = "repair", Text = if cost > 0 then ("Repair all my items. (%dg %ds %dc)"):format(cost // 10000, (cost % 10000) // 100, cost % 100) else "Repair all my items." })
	end
	if self.includes.Spells["Spells.h"]:IsTrainer(entry) and (player:GetAttribute("CharacterLevel") or 1) >= Config.Talents.FirstLevel then
		table.insert(options, { Id = "untalent", Text = ("I wish to unlearn my talents. (%s)"):format(self.includes.Spells["Talents.h"]:ResetCost(player) // 10000 .. "g") })
	end
	if template.flightmaster then
		table.insert(options, { Id = "taxi", Text = "I would like to fly somewhere." })
	end
	if template.auctioneer then
		table.insert(options, { Id = "auction", Text = "Let me browse the auctions." })
	end
	if template.battlemaster then
		for _, bg in self:DB():Select("battleground_template") do
			table.insert(options, { Id = "bg:" .. tostring(bg.id), Text = ("I would like to join %s."):format(bg.name) })
		end
		if self.includes.Combat["Battleground.h"]:In(player) then
			table.insert(options, { Id = "bgleave", Text = "Take me out of the battleground." })
		end
	end
	if not self:IsQuestgiver(entry) and #options <= 1 then
		if options[1] then
			return self:Select(player, guid, options[1].Id)
		end
		return self.includes.Security["Packet.h"]:Send(player, Opcodes.SMSG_MESSAGECHAT,
			{ Channel = "SAY", Sender = template.name, Text = template.gossip or "Greetings, traveler." })
	end
	self:Hello(player, guid, options)
end

function module:Select(player: Player, guid, option)
	local creature = self.includes.Content["Creatures.h"]:State(guid)
	if not creature then
		return
	end
	local entry, template = creature.Row.id, creature.Template
	if option == "train" then
		self.includes.Spells["Spells.h"]:TrainerList(player, guid)
	elseif option == "vendor" then
		self.includes.Content["Vendors.h"]:Open(player, guid, entry)
	elseif option == "bank" and template.banker then
		self.includes.Entities["EntityPlayer.h"]:SendBank(player, true)
	elseif option == "guildbank" and template.banker then
		self.includes.Social["Guild.h"]:SendBank(player, true)
	elseif option == "spirithealer" and template.spirithealer then
		self.includes.Combat["Death.h"]:SpiritHeal(player, guid)
	elseif option == "repair" and template.repair then
		self.includes.Entities["EntityPlayer.h"]:Repair(player)
	elseif option == "profession" and template.trainer_skill then
		self.includes.Spells["Skills.h"]:TrainerList(player, guid)
	elseif option == "untalent" then
		self.includes.Spells["Talents.h"]:Reset(player)
	elseif option == "taxi" and template.flightmaster then
		self.includes.Content["Taxi.h"]:Show(player, guid)
	elseif option == "auction" and template.auctioneer then
		self.includes.Content["Auction.h"]:Open(player, guid)
	elseif typeof(option) == "string" and option:sub(1, 3) == "bg:" and template.battlemaster then
		self.includes.Combat["Battleground.h"]:Queue(player, tonumber(option:sub(4)))
	elseif option == "bgleave" and template.battlemaster then
		self.includes.Combat["Battleground.h"]:Leave(player)
	elseif option == "bind" and template.innkeeper then
		local zone = self.includes.Zones["Zones.h"]:At(creature.Root.Position)
		self.includes.Entities["EntityPlayer.h"]:SetHome(player, creature.Root.Position, zone and zone.Name or template.name)
		self.includes.Chat["Chat.h"]:System(player, ("%s: This inn is your home now. Your Hearthstone will bring you back here."):format(template.name))
	end
end

function module:Hello(player: Player, guid, options)
	local creature = self.includes.Content["Creatures.h"]:State(guid)
	local c = char(self, player)
	if not creature or not c then
		return
	end
	local entry = creature.Row.id
	local list = {}
	for _, id in endersOf(self, entry) do
		if c.Quests[tostring(id)] then
			table.insert(list, { Id = id, Title = self:Template(id).title, Status = if self:IsComplete(player, id) then "complete" else "incomplete" })
		end
	end
	for _, id in startersOf(self, entry) do
		local template = self:Template(id)
		if template and not c.Quests[tostring(id)] and not c.Done[tostring(id)] and self:Eligible(c, template) then
			table.insert(list, { Id = id, Title = template.title, Status = "available" })
		end
	end
	self.includes.Security["Packet.h"]:Send(player, Opcodes.SMSG_QUESTGIVER_QUEST_LIST,
		{ Guid = tostring(guid), Name = creature.Template.name, Greeting = creature.Template.gossip, Quests = list, Options = options or {} })
end

function module:Query(player: Player, guid, id)
	local c = char(self, player)
	local template = self:Template(id)
	if not c or not template then
		return
	end
	local status = if c.Quests[tostring(id)] then (if self:IsComplete(player, id) then "complete" else "incomplete") else "available"
	local packet = describe(self, id, status)
	packet.Guid = tostring(guid)
	self.includes.Security["Packet.h"]:Send(player, Opcodes.SMSG_QUESTGIVER_QUEST_DETAILS, packet)
end

function module:Accept(player: Player, guid, id)
	local c = char(self, player)
	local template = self:Template(id)
	local creature = self.includes.Content["Creatures.h"]:State(guid)
	if not c or not template or not creature or not table.find(startersOf(self, creature.Row.id), template.id) then
		return
	end
	if c.Quests[tostring(id)] or c.Done[tostring(id)] or not self:Eligible(c, template) then
		return
	end
	local count = 0
	for _ in c.Quests do
		count += 1
	end
	if count >= Config.QuestLogSize then
		return self.includes.Chat["Chat.h"]:System(player, "Your quest log is full.")
	end
	c.Quests[tostring(id)] = { Status = "active", Kills = {} }
	commit(self, player)
	self.includes.Chat["Chat.h"]:System(player, "Quest accepted: " .. template.title)
	self:Refresh(player, id)
end

function module:Complete(player: Player, guid, id)
	local c = char(self, player)
	local template = self:Template(id)
	local creature = self.includes.Content["Creatures.h"]:State(guid)
	if not c or not template or not creature or not c.Quests[tostring(id)] then
		return
	end
	if not table.find(endersOf(self, creature.Row.id), template.id) or not self:IsComplete(player, id) then
		return
	end
	local Entities = self.includes.Entities["EntityPlayer.h"]
	for _, req in (template.req_item or {}) do
		Entities:RemoveItem(player, req.entry, req.count)
	end
	for _, reward in (template.reward_items or {}) do
		Entities:AddItem(player, reward.entry, reward.count)
	end
	if (template.reward_money or 0) > 0 then
		Entities:AddMoney(player, template.reward_money)
	end
	c.Quests[tostring(id)] = nil
	c.Done[tostring(id)] = true
	self.includes.Social["Achievements.h"]:OnQuest(player)
	if template.reward_rep then
		self.includes.Social["Reputation.h"]:Modify(player, template.reward_rep.faction, template.reward_rep.amount or 250)
	end
	commit(self, player)
	self.includes.Security["Packet.h"]:Send(player, Opcodes.SMSG_QUESTGIVER_QUEST_COMPLETE, { Id = template.id, Title = template.title, Xp = template.reward_xp or 0 })
	if (template.reward_xp or 0) > 0 then
		Entities:GrantXp(player, template.reward_xp, "Quest complete")
	end
	self:Refresh(player)
end

function module:Remove(player: Player, id)
	local c = char(self, player)
	if c and c.Quests[tostring(id)] then
		c.Quests[tostring(id)] = nil
		commit(self, player)
		self:Refresh(player)
	end
end

-- Log and markers after any change; check completion of one quest when given.
function module:Refresh(player: Player, id)
	local c = char(self, player)
	if id and c and c.Quests[tostring(id)] and self:IsComplete(player, id) and c.Quests[tostring(id)].Status ~= "complete" then
		c.Quests[tostring(id)].Status = "complete"
		self.includes.Security["Packet.h"]:Send(player, Opcodes.SMSG_QUESTUPDATE_COMPLETE, { Id = tonumber(id), Title = self:Template(id).title })
	end
	self:SendLog(player)
	self:SendStatuses(player)
end

-- Kill credit for the killer and party members nearby.
function module:OnKill(killer: Player, creatureEntry, position: Vector3)
	local credited = { killer }
	for _, member in self.includes.Social["Party.h"]:MembersOf(killer) do
		local root = member.Character and member.Character:FindFirstChild("HumanoidRootPart")
		if member ~= killer and root and (root.Position - position).Magnitude <= 100 then
			table.insert(credited, member)
		end
	end
	for _, player in credited do
		local c = char(self, player)
		if c then
			for id, state in c.Quests do
				local template = self:Template(id)
				for _, req in (template and template.req_creature or {}) do
					if tostring(req.entry) == tostring(creatureEntry) and (state.Kills[tostring(req.entry)] or 0) < req.count then
						state.Kills[tostring(req.entry)] = (state.Kills[tostring(req.entry)] or 0) + 1
						local creature = self:DB():Get("creature_template", req.entry) or {}
						self.includes.Security["Packet.h"]:Send(player, Opcodes.SMSG_QUESTUPDATE_ADD_KILL,
							{ Id = tonumber(id), Name = creature.name or "?", Have = state.Kills[tostring(req.entry)], Need = req.count })
						commit(self, player)
						self:Refresh(player, id)
					end
				end
			end
		end
	end
end

-- Collect objectives are counted from the bag, so any bag change may complete one.
function module:OnItemChange(player: Player)
	local c = char(self, player)
	if not c then
		return
	end
	local touched = false
	for id, state in c.Quests do
		local template = self:Template(id)
		if template and template.req_item and #template.req_item > 0 then
			touched = true
			local complete = self:IsComplete(player, id)
			if complete and state.Status ~= "complete" then
				self:Refresh(player, id)
			elseif not complete and state.Status == "complete" then
				state.Status = "active"
			end
		end
	end
	if touched then
		self:SendLog(player)
		self:SendStatuses(player)
	end
end

function module:Start()
	local DB = self:DB()
	local byTitle = {}
	for _, row in DB:Select("quest_template") do
		byTitle[row.title] = row
	end
	local creatures, items = {}, {}
	if true then
		for _, row in DB:Select("creature_template") do
			creatures[row.name] = row.entry
		end
		for _, row in DB:Select("item_template") do
			items[row.name] = row.entry
		end
		for _, seed in SEED do
			if byTitle[seed.title] then
				continue
			end
			local quest = { title = seed.title, details = seed.details, objectives = seed.objectives, minlevel = seed.minlevel, level = seed.level,
				reward_xp = seed.reward_xp, reward_money = seed.reward_money, reward_items = {}, req_creature = {}, req_item = {}, class = seed.class, race = seed.race,
				prevquest = seed.prevquest and byTitle[seed.prevquest] and byTitle[seed.prevquest].id }
			for _, r in (seed.reward_items or {}) do
				if items[r.item] then table.insert(quest.reward_items, { entry = items[r.item], count = r.count }) end
			end
			for _, r in (seed.req_creature or {}) do
				if creatures[r.creature] then table.insert(quest.req_creature, { entry = creatures[r.creature], count = r.count }) end
			end
			for _, r in (seed.req_item or {}) do
				if items[r.item] then table.insert(quest.req_item, { entry = items[r.item], count = r.count }) end
			end
			quest = DB:Insert("quest_template", quest)
			byTitle[quest.title] = quest
			if creatures[seed.starter] then
				DB:Insert("creature_queststarter", { entry = creatures[seed.starter], quest = quest.id })
			end
			if creatures[seed.ender] then
				DB:Insert("creature_questender", { entry = creatures[seed.ender], quest = quest.id })
			end
		end
	end

	local Packet = self.includes.Security["Packet.h"]
	Packet:On(Opcodes.CMSG_QUESTGIVER_HELLO, function(player, data)
		if typeof(data) == "table" then self:Hello(player, data.Guid) end
	end)
	Packet:On(Opcodes.CMSG_QUESTGIVER_QUERY_QUEST, function(player, data)
		if typeof(data) == "table" then self:Query(player, data.Guid, tonumber(data.Quest)) end
	end)
	Packet:On(Opcodes.CMSG_QUESTGIVER_ACCEPT_QUEST, function(player, data)
		if typeof(data) == "table" then self:Accept(player, data.Guid, tonumber(data.Quest)) end
	end)
	Packet:On(Opcodes.CMSG_QUESTGIVER_COMPLETE_QUEST, function(player, data)
		if typeof(data) == "table" then self:Complete(player, data.Guid, tonumber(data.Quest)) end
	end)
	Packet:On(Opcodes.CMSG_GOSSIP_SELECT_OPTION, function(player, data)
		if typeof(data) == "table" then self:Select(player, data.Guid, data.Option) end
	end)
	Packet:On(Opcodes.CMSG_QUESTLOG_REMOVE_QUEST, function(player, data)
		if typeof(data) == "table" then self:Remove(player, tonumber(data.Quest)) end
	end)
end

return Base(module, {
	{ Path = "Auth/Security", Imports = "Packet.h" },
	{ Path = "Auth/Entities", Imports = "EntityPlayer.h" },
	{ Path = "Auth/Chat", Imports = "Chat.h" },
	{ Path = "Auth/Social", Imports = "Party.h|Achievements.h|Reputation.h|Guild.h" },
	{ Path = "World/Content", Imports = "Creatures.h|Vendors.h|Items.h|Taxi.h|Auction.h" },
	{ Path = "World/Spells", Imports = "Spells.h|Talents.h|Skills.h" },
	{ Path = "World/Zones", Imports = "Zones.h" },
	{ Path = "World/Combat", Imports = "Battleground.h|Death.h" },
	{ Path = "World/Database", Imports = "WorldDB.h|WorldDatabase.h" },
})
