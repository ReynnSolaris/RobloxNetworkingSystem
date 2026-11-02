local Base = require(game:GetService("ServerStorage").ServerModules["Template.h"])
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Opcodes = require(ReplicatedStorage.Shared.Opcodes)
local Config = require(ReplicatedStorage.Shared.Config)
local module = {}

-- Professions. skill_line: { id, name, kind = primary|secondary, description }.
-- skill_recipe: { id, skill (name), name, result (item entry), count, reagents =
-- { { item, count } }, reqskill }. A character keeps Skills = { [skillId] =
-- { Value, Max } }; two primary professions at most. Recipes are known once the
-- skill reaches reqskill. Crafting and gathering raise the skill: orange
-- (within 10 of reqskill) always, yellow often, green sometimes, grey never.
-- Nodes (gameobject type node) need skill >= reqskill; trainers teach and
-- raise the rank cap.

local SEED = {
	{ name = "Mining", kind = "primary", description = "Dig ore from veins and smelt it into bars." },
	{ name = "Herbalism", kind = "primary", description = "Gather herbs from the wild." },
	{ name = "Blacksmithing", kind = "primary", description = "Forge weapons and armor from metal bars." },
	{ name = "Alchemy", kind = "primary", description = "Brew potions from herbs." },
	{ name = "Cooking", kind = "secondary", description = "Cook food that restores health." },
	{ name = "First Aid", kind = "secondary", description = "Make bandages from cloth." },
}
local RECIPES = {
	{ skill = "Mining", name = "Smelt Copper", result = "Copper Bar", count = 1, reagents = { { "Copper Ore", 1 } }, reqskill = 1 },
	{ skill = "Blacksmithing", name = "Rough Copper Sword", result = "Rough Copper Sword", count = 1, reagents = { { "Copper Bar", 2 }, { "Linen Cloth", 1 } }, reqskill = 1 },
	{ skill = "Blacksmithing", name = "Copper Chain Belt", result = "Copper Chain Belt", count = 1, reagents = { { "Copper Bar", 3 } }, reqskill = 15 },
	{ skill = "Alchemy", name = "Minor Healing Potion", result = "Minor Healing Potion", count = 1, reagents = { { "Peacebloom", 1 }, { "Silverleaf", 1 } }, reqskill = 1 },
	{ skill = "Cooking", name = "Spiced Wolf Meat", result = "Spiced Wolf Meat", count = 1, reagents = { { "Stringy Wolf Meat", 1 } }, reqskill = 1 },
	{ skill = "First Aid", name = "Linen Bandage", result = "Linen Bandage", count = 1, reagents = { { "Linen Cloth", 1 } }, reqskill = 1 },
}

function module:DB()
	return self.includes.Database["WorldDB.h"]
end

function module:Line(id)
	return self:DB():Get("skill_line", id)
end

function module:ByName(name: string)
	for _, row in self:DB():Select("skill_line") do
		if row.name == name then
			return row
		end
	end
	return nil
end

local function char(self, player: Player)
	local entity = self.includes.Entities["EntityPlayer.h"]:Get(player)
	local c = entity and entity.Active
	if c then
		c.Skills = c.Skills or {}
	end
	return c
end

function module:Value(player: Player, name: string): number?
	local c = char(self, player)
	local line = self:ByName(name)
	local skill = c and line and c.Skills[tostring(line.id)]
	return skill and skill.Value
end

function module:Recipes(skillName: string)
	local out = {}
	for _, row in self:DB():Select("skill_recipe") do
		if row.skill == skillName then
			table.insert(out, row)
		end
	end
	table.sort(out, function(a, b)
		return (a.reqskill or 1) < (b.reqskill or 1)
	end)
	return out
end

-- Difficulty colour for a recipe or node at the player's skill.
function module:Difficulty(value: number, req: number): string
	if value < req + 10 then
		return "orange"
	elseif value < req + 20 then
		return "yellow"
	elseif value < req + 35 then
		return "green"
	end
	return "grey"
end

local CHANCE = { orange = 1, yellow = 0.6, green = 0.25, grey = 0 }

function module:Sync(player: Player)
	local c = char(self, player)
	if not c then
		return
	end
	local Items = self.includes.Content["Items.h"]
	local list = {}
	for id, skill in c.Skills do
		local line = self:Line(id)
		if line then
			local recipes = {}
			for _, recipe in self:Recipes(line.name) do
				if (recipe.reqskill or 1) <= skill.Value then
					local reagents = {}
					for _, r in recipe.reagents do
						table.insert(reagents, { Entry = r[1], Name = (Items:Template(r[1]) or {}).name or "?", Count = r[2], Have = self.includes.Entities["EntityPlayer.h"]:CountItem(player, r[1]) })
					end
					table.insert(recipes, { Id = recipe.id, Name = recipe.name, Result = Items:Describe(recipe.result, { Count = recipe.count }), Reagents = reagents,
						ReqSkill = recipe.reqskill or 1, Difficulty = self:Difficulty(skill.Value, recipe.reqskill or 1) })
				end
			end
			table.insert(list, { Id = line.id, Name = line.name, Kind = line.kind, Description = line.description, Value = skill.Value, Max = skill.Max, Recipes = recipes })
		end
	end
	table.sort(list, function(a, b)
		return a.Name < b.Name
	end)
	player:SetAttribute("Skills", HttpService:JSONEncode(list))
end

function module:Learn(player: Player, name: string, free: boolean?): boolean
	local c = char(self, player)
	local line = self:ByName(name)
	local Chat = self.includes.Chat["Chat.h"]
	if not c or not line then
		return false
	end
	if c.Skills[tostring(line.id)] then
		Chat:System(player, "You already know " .. line.name .. ".")
		return false
	end
	if line.kind == "primary" then
		local primaries = 0
		for id in c.Skills do
			local other = self:Line(id)
			if other and other.kind == "primary" then
				primaries += 1
			end
		end
		if primaries >= Config.Skills.MaxPrimary then
			Chat:System(player, ("You already know %d primary professions. Unlearn one first."):format(Config.Skills.MaxPrimary))
			return false
		end
	end
	if not free then
		if (c.Money or 0) < Config.Skills.LearnCost then
			Chat:System(player, "You don't have enough money.")
			return false
		end
		self.includes.Entities["EntityPlayer.h"]:AddMoney(player, -Config.Skills.LearnCost)
	end
	c.Skills[tostring(line.id)] = { Value = 1, Max = Config.Skills.Ranks[1].Max }
	self.includes.Database["WorldDatabase.h"]:Commit(player)
	Chat:System(player, ("You have learned %s %s."):format(Config.Skills.Ranks[1].Name, line.name))
	self:Sync(player)
	return true
end

function module:Unlearn(player: Player, name: string)
	local c = char(self, player)
	local line = self:ByName(name)
	if c and line and c.Skills[tostring(line.id)] then
		c.Skills[tostring(line.id)] = nil
		self.includes.Database["WorldDatabase.h"]:Commit(player)
		self.includes.Chat["Chat.h"]:System(player, ("You have unlearned %s."):format(line.name))
		self:Sync(player)
	end
end

-- Raise the cap to the next rank, for a price.
function module:Rank(player: Player, name: string): boolean
	local c = char(self, player)
	local line = self:ByName(name)
	local skill = c and line and c.Skills[tostring(line.id)]
	local Chat = self.includes.Chat["Chat.h"]
	if not skill then
		return false
	end
	for i, rank in Config.Skills.Ranks do
		if skill.Max == rank.Max then
			local nextRank = Config.Skills.Ranks[i + 1]
			if not nextRank then
				Chat:System(player, "There is nothing more to learn.")
				return false
			elseif skill.Value < rank.Max then
				Chat:System(player, ("You need %d skill in %s first."):format(rank.Max, line.name))
				return false
			end
			local cost = Config.Skills.RankCost[i] or 0
			if (c.Money or 0) < cost then
				Chat:System(player, "You don't have enough money.")
				return false
			end
			self.includes.Entities["EntityPlayer.h"]:AddMoney(player, -cost)
			skill.Max = nextRank.Max
			self.includes.Database["WorldDatabase.h"]:Commit(player)
			Chat:System(player, ("You are now a %s %s."):format(nextRank.Name, line.name))
			self:Sync(player)
			return true
		end
	end
	return false
end

local function skillUp(self, player: Player, line, skill, req: number)
	if skill.Value >= skill.Max or math.random() >= CHANCE[self:Difficulty(skill.Value, req)] then
		return
	end
	skill.Value += 1
	self.includes.Database["WorldDatabase.h"]:Commit(player)
	self.includes.Chat["Chat.h"]:System(player, ("Your skill in %s has increased to %d."):format(line.name, skill.Value))
	self.includes.Social["Achievements.h"]:OnSkill(player, line.name, skill.Value)
end

function module:CanGather(player: Player, skillName: string, req: number): (boolean, string?)
	local c = char(self, player)
	local line = self:ByName(skillName)
	local skill = c and line and c.Skills[tostring(line.id)]
	if not skill then
		return false, ("Requires %s."):format(skillName)
	elseif skill.Value < req then
		return false, ("Requires %s (%d)."):format(skillName, req)
	end
	return true
end

function module:OnGather(player: Player, skillName: string, req: number)
	local c = char(self, player)
	local line = self:ByName(skillName)
	local skill = c and line and c.Skills[tostring(line.id)]
	if skill then
		skillUp(self, player, line, skill, req)
		self:Sync(player)
	end
end

function module:Craft(player: Player, recipeId, count: number)
	local c = char(self, player)
	local recipe = self:DB():Get("skill_recipe", recipeId)
	local line = recipe and self:ByName(recipe.skill)
	local skill = c and line and c.Skills[tostring(line.id)]
	local Chat = self.includes.Chat["Chat.h"]
	local Entities = self.includes.Entities["EntityPlayer.h"]
	if not skill or skill.Value < (recipe.reqskill or 1) then
		return Chat:System(player, "You don't know that recipe.")
	end
	count = math.clamp(count or 1, 1, 20)
	for _ = 1, count do
		for _, r in recipe.reagents do
			if Entities:CountItem(player, r[1]) < r[2] then
				Chat:System(player, "You don't have the required reagents.")
				self:Sync(player)
				return
			end
		end
		for _, r in recipe.reagents do
			Entities:RemoveItem(player, r[1], r[2])
		end
		if not Entities:AddItem(player, recipe.result, recipe.count or 1) then
			break
		end
		skillUp(self, player, line, skill, recipe.reqskill or 1)
	end
	self:Sync(player)
end

-- Profession trainer gossip: every skill line, with what the player may do.
function module:TrainerList(player: Player, guid)
	local c = char(self, player)
	local creature = self.includes.Content["Creatures.h"]:State(guid)
	if not c or not creature then
		return
	end
	local list = {}
	for _, line in self:DB():Select("skill_line") do
		local skill = c.Skills[tostring(line.id)]
		local rankIndex = 1
		for i, rank in Config.Skills.Ranks do
			if skill and skill.Max == rank.Max then
				rankIndex = i
			end
		end
		table.insert(list, { Name = line.name, Kind = line.kind, Description = line.description, Known = skill ~= nil, Value = skill and skill.Value, Max = skill and skill.Max,
			Price = if skill then (Config.Skills.RankCost[rankIndex] or 0) else Config.Skills.LearnCost,
			NextRank = if skill and Config.Skills.Ranks[rankIndex + 1] then Config.Skills.Ranks[rankIndex + 1].Name else nil })
	end
	self.includes.Security["Packet.h"]:Send(player, Opcodes.SMSG_SKILL_TRAINER, { Guid = tostring(guid), Name = creature.Template.name, Greeting = creature.Template.gossip, Skills = list })
end

function module:OnLogin(player: Player)
	self:Sync(player)
end

function module:Start()
	local DB = self:DB()
	local Items = self.includes.Content["Items.h"]
	local byName = {}
	for _, row in DB:Select("skill_line") do
		byName[row.name] = row
	end
	for _, seed in SEED do
		if not byName[seed.name] then
			byName[seed.name] = DB:Insert("skill_line", table.clone(seed))
		end
	end
	local recipes = {}
	for _, row in DB:Select("skill_recipe") do
		recipes[row.name] = row
	end
	for _, seed in RECIPES do
		local result = Items:ByName(seed.result)
		if not recipes[seed.name] and result then
			local reagents = {}
			for _, r in seed.reagents do
				local item = Items:ByName(r[1])
				if item then
					table.insert(reagents, { item.entry, r[2] })
				end
			end
			DB:Insert("skill_recipe", { skill = seed.skill, name = seed.name, result = result.entry, count = seed.count, reagents = reagents, reqskill = seed.reqskill })
		end
	end
	local Packet = self.includes.Security["Packet.h"]
	Packet:On(Opcodes.CMSG_CRAFT, function(player, data)
		if typeof(data) == "table" then
			self:Craft(player, tonumber(data.Recipe), tonumber(data.Count) or 1)
		end
	end)
	Packet:On(Opcodes.CMSG_LEARN_SKILL, function(player, data)
		if typeof(data) ~= "table" or typeof(data.Skill) ~= "string" then
			return
		end
		local creature = self.includes.Content["Creatures.h"]:State(data.Guid)
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if not creature or not root or (creature.Root.Position - root.Position).Magnitude > Config.VendorRange then
			return
		end
		if data.Action == "unlearn" then
			self:Unlearn(player, data.Skill)
		elseif self:Value(player, data.Skill) then
			self:Rank(player, data.Skill)
		else
			self:Learn(player, data.Skill)
		end
		self:TrainerList(player, data.Guid)
	end)
end

return Base(module, {
	{ Path = "Auth/Security", Imports = "Packet.h" },
	{ Path = "Auth/Entities", Imports = "EntityPlayer.h" },
	{ Path = "Auth/Chat", Imports = "Chat.h" },
	{ Path = "Auth/Social", Imports = "Achievements.h" },
	{ Path = "World/Content", Imports = "Items.h|Creatures.h" },
	{ Path = "World/Database", Imports = "WorldDB.h|WorldDatabase.h" },
})
