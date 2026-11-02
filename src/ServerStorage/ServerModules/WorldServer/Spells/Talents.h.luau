local Base = require(game:GetService("ServerStorage").ServerModules["Template.h"])
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Opcodes = require(ReplicatedStorage.Shared.Opcodes)
local Config = require(ReplicatedStorage.Shared.Config)
local module = {}

-- Talent trees, WoW style: three tabs a class, five tiers, a point per level
-- from level 10. talent: { id, class, tab, tier, col, name, description,
-- max_rank, mod = { kind, stat|school, value } } where kind is pct (a stat by
-- percent), flat (a stat by amount), school (damage of a school by percent)
-- or rating (crit or dodge in points). A character keeps Talents = { [id] = rank }
-- and TalentResets. A tier opens once TierPoints sit in the tab below it.

local TABS = {
	Warrior = { "Arms", "Fury", "Protection" }, Paladin = { "Holy", "Protection", "Retribution" }, Hunter = { "Beast Mastery", "Marksmanship", "Survival" },
	Rogue = { "Assassination", "Combat", "Subtlety" }, Priest = { "Discipline", "Holy", "Shadow" }, ["Death Knight"] = { "Blood", "Frost", "Unholy" },
	Shaman = { "Elemental", "Enhancement", "Restoration" }, Mage = { "Arcane", "Fire", "Frost" }, Warlock = { "Affliction", "Demonology", "Destruction" },
	Druid = { "Balance", "Feral Combat", "Restoration" },
}
-- each tab: five tiers of { name, mod }
local function pct(stat, value) return { kind = "pct", stat = stat, value = value } end
local function flat(stat, value) return { kind = "flat", stat = stat, value = value } end
local function school(name, value) return { kind = "school", school = name, value = value } end
local function rating(stat, value) return { kind = "rating", stat = stat, value = value } end
-- the last tier of every tree teaches the spell named after the talent
local function grant(name) return { kind = "spell", spell = name, value = 0 } end

local TREES = {
	Warrior = {
		{ { "Deflection", rating("Dodge", 1) }, { "Improved Heroic Strike", pct("Damage", 2) }, { "Tactical Mastery", pct("Strength", 2) }, { "Deep Wounds", school("physical", 3) }, { "Mortal Strike", grant("Mortal Strike") } },
		{ { "Cruelty", rating("Crit", 1) }, { "Unbridled Wrath", pct("Strength", 2) }, { "Enrage", school("physical", 3) }, { "Flurry", rating("Crit", 2) }, { "Bloodthirst", grant("Bloodthirst") } },
		{ { "Shield Specialization", pct("Armor", 3) }, { "Anticipation", rating("Dodge", 1) }, { "Toughness", pct("Armor", 4) }, { "Last Stand", pct("Health", 3) }, { "Shield Slam", grant("Shield Slam") } },
	},
	Paladin = {
		{ { "Divine Strength", pct("Strength", 2) }, { "Divine Intellect", pct("Intellect", 2) }, { "Healing Light", pct("SpellPower", 3) }, { "Illumination", pct("Spirit", 3) }, { "Holy Shock", grant("Holy Shock") } },
		{ { "Redoubt", pct("Armor", 3) }, { "Toughness", pct("Stamina", 2) }, { "Anticipation", rating("Dodge", 1) }, { "Sacred Duty", pct("Health", 3) }, { "Holy Shield", grant("Holy Shield") } },
		{ { "Benediction", pct("Damage", 2) }, { "Conviction", rating("Crit", 1) }, { "Seal of Command", school("holy", 3) }, { "Vengeance", pct("Damage", 3) }, { "Repentance", grant("Repentance") } },
	},
	Hunter = {
		{ { "Endurance Training", pct("Health", 2) }, { "Thick Hide", pct("Armor", 3) }, { "Unleashed Fury", pct("Damage", 2) }, { "Ferocity", rating("Crit", 1) }, { "Bestial Wrath", grant("Bestial Wrath") } },
		{ { "Lethal Shots", rating("Crit", 1) }, { "Efficiency", pct("Intellect", 2) }, { "Mortal Shots", school("arcane", 3) }, { "Ranged Weapon Specialization", pct("Damage", 3) }, { "Trueshot Aura", grant("Trueshot Aura") } },
		{ { "Monster Slaying", school("physical", 2) }, { "Deflection", rating("Dodge", 1) }, { "Survivalist", pct("Health", 3) }, { "Killer Instinct", rating("Crit", 2) }, { "Lightning Reflexes", grant("Lightning Reflexes") } },
	},
	Rogue = {
		{ { "Malice", rating("Crit", 1) }, { "Ruthlessness", pct("Damage", 2) }, { "Lethality", school("physical", 3) }, { "Vile Poisons", pct("Agility", 3) }, { "Cold Blood", grant("Cold Blood") } },
		{ { "Lightning Reflexes", rating("Dodge", 1) }, { "Precision", pct("Damage", 2) }, { "Dual Wield Specialization", school("physical", 3) }, { "Blade Flurry", pct("Agility", 3) }, { "Adrenaline Rush", grant("Adrenaline Rush") } },
		{ { "Master of Deception", pct("Agility", 2) }, { "Camouflage", rating("Dodge", 1) }, { "Elusiveness", pct("Health", 3) }, { "Ghostly Strike", rating("Dodge", 2) }, { "Preparation", grant("Preparation") } },
	},
	Priest = {
		{ { "Unbreakable Will", pct("Stamina", 2) }, { "Silent Resolve", pct("Spirit", 2) }, { "Improved Power Word: Fortitude", pct("Health", 3) }, { "Mental Strength", pct("Intellect", 3) }, { "Power Infusion", grant("Power Infusion") } },
		{ { "Healing Focus", pct("SpellPower", 2) }, { "Spiritual Healing", pct("Spirit", 3) }, { "Holy Specialization", school("holy", 3) }, { "Spiritual Guidance", pct("SpellPower", 3) }, { "Circle of Healing", grant("Circle of Healing") } },
		{ { "Spirit Tap", pct("Spirit", 2) }, { "Blackout", school("shadow", 2) }, { "Shadow Focus", pct("Intellect", 3) }, { "Darkness", school("shadow", 4) }, { "Shadowform", grant("Shadowform") } },
	},
	["Death Knight"] = {
		{ { "Butchery", pct("Strength", 2) }, { "Blade Barrier", pct("Armor", 3) }, { "Bladed Armor", pct("Damage", 2) }, { "Veteran of the Third War", pct("Stamina", 3) }, { "Dancing Rune Weapon", grant("Dancing Rune Weapon") } },
		{ { "Improved Icy Touch", school("frost", 3) }, { "Toughness", pct("Armor", 3) }, { "Black Ice", school("frost", 3) }, { "Killing Machine", rating("Crit", 2) }, { "Howling Blast", grant("Howling Blast") } },
		{ { "Vicious Strikes", rating("Crit", 1) }, { "Virulence", school("shadow", 3) }, { "Anticipation", rating("Dodge", 1) }, { "Necrosis", school("shadow", 3) }, { "Summon Gargoyle", grant("Summon Gargoyle") } },
	},
	Shaman = {
		{ { "Convection", pct("Intellect", 2) }, { "Concussion", school("nature", 3) }, { "Call of Flame", school("fire", 3) }, { "Elemental Fury", rating("Crit", 2) }, { "Elemental Mastery", grant("Elemental Mastery") } },
		{ { "Ancestral Knowledge", pct("Intellect", 2) }, { "Thundering Strikes", rating("Crit", 1) }, { "Improved Weapon Totems", pct("Damage", 3) }, { "Flurry", pct("Strength", 3) }, { "Stormstrike", grant("Stormstrike") } },
		{ { "Improved Healing Wave", pct("SpellPower", 2) }, { "Tidal Focus", pct("Spirit", 2) }, { "Totemic Focus", pct("Health", 3) }, { "Nature's Guidance", pct("SpellPower", 3) }, { "Mana Tide", grant("Mana Tide") } },
	},
	Mage = {
		{ { "Arcane Subtlety", pct("Intellect", 2) }, { "Arcane Focus", school("arcane", 3) }, { "Arcane Concentration", pct("Spirit", 3) }, { "Arcane Mind", pct("Intellect", 3) }, { "Arcane Power", grant("Arcane Power") } },
		{ { "Improved Fireball", school("fire", 2) }, { "Ignite", school("fire", 3) }, { "Incinerate", rating("Crit", 2) }, { "Fire Power", school("fire", 4) }, { "Combustion", grant("Combustion") } },
		{ { "Frost Warding", pct("Armor", 3) }, { "Elemental Precision", school("frost", 3) }, { "Ice Shards", rating("Crit", 2) }, { "Piercing Ice", school("frost", 4) }, { "Ice Barrier", grant("Ice Barrier") } },
	},
	Warlock = {
		{ { "Suppression", pct("Spirit", 2) }, { "Improved Corruption", school("shadow", 3) }, { "Fel Concentration", pct("Intellect", 3) }, { "Shadow Mastery", school("shadow", 4) }, { "Unstable Affliction", grant("Unstable Affliction") } },
		{ { "Demonic Embrace", pct("Stamina", 3) }, { "Fel Vitality", pct("Health", 3) }, { "Demonic Aegis", pct("Armor", 4) }, { "Master Demonologist", pct("SpellPower", 3) }, { "Demonic Sacrifice", grant("Demonic Sacrifice") } },
		{ { "Improved Shadow Bolt", school("shadow", 2) }, { "Cataclysm", pct("Intellect", 2) }, { "Bane", school("fire", 3) }, { "Devastation", rating("Crit", 2) }, { "Conflagrate", grant("Conflagrate") } },
	},
	Druid = {
		{ { "Starlight Wrath", school("nature", 2) }, { "Focused Starlight", rating("Crit", 1) }, { "Improved Moonfire", school("arcane", 3) }, { "Vengeance", rating("Crit", 2) }, { "Moonkin Form", grant("Moonkin Form") } },
		{ { "Ferocity", pct("Damage", 2) }, { "Feral Instinct", pct("Agility", 2) }, { "Thick Hide", pct("Armor", 4) }, { "Sharpened Claws", rating("Crit", 2) }, { "Heart of the Wild", grant("Heart of the Wild") } },
		{ { "Improved Mark of the Wild", pct("Armor", 2) }, { "Furor", pct("Spirit", 2) }, { "Naturalist", pct("SpellPower", 3) }, { "Intensity", pct("Intellect", 3) }, { "Tree of Life", grant("Tree of Life") } },
	},
}

-- Every tier below the last gets a second talent built from the tab, so five
-- points fit in a tier: Training (a stat), Focus (crit or dodge), Mastery
-- (the tab's school) and Expertise (health).
local SECOND = {
	{ suffix = "Training", mod = function(tab) return pct(tab.stat, 2) end, max = 3 },
	{ suffix = "Focus", mod = function(tab) return rating(tab.rating, 1) end, max = 2 },
	{ suffix = "Mastery", mod = function(tab) return school(tab.school, 2) end, max = 3 },
	{ suffix = "Expertise", mod = function() return pct("Health", 2) end, max = 3 },
}
local function tabProfile(tiers)
	local profile = { stat = "Stamina", rating = "Crit", school = "physical" }
	for _, talent in tiers do
		local mod = talent[2]
		if mod.kind == "school" then
			profile.school = mod.school
		elseif mod.kind == "pct" and mod.stat ~= "Health" and mod.stat ~= "Armor" and mod.stat ~= "Damage" and mod.stat ~= "SpellPower" then
			profile.stat = mod.stat
		elseif mod.kind == "rating" then
			profile.rating = mod.stat
		end
	end
	return profile
end

function module:DB()
	return self.includes.Database["WorldDB.h"]
end

local function describe(mod)
	local v = mod.value
	if mod.kind == "pct" then
		return ("Increases your %s by %d%% per rank."):format(mod.stat, v)
	elseif mod.kind == "flat" then
		return ("Increases your %s by %d per rank."):format(mod.stat, v)
	elseif mod.kind == "school" then
		return ("Increases the damage of your %s spells and abilities by %d%% per rank."):format(mod.school, v)
	elseif mod.kind == "spell" then
		return ("Teaches you %s."):format(mod.spell)
	end
	return ("Increases your %s chance by %d%% per rank."):format(mod.stat, v)
end

local function char(self, player: Player)
	local entity = self.includes.Entities["EntityPlayer.h"]:Get(player)
	local c = entity and entity.Active
	if c then
		c.Talents = c.Talents or {}
	end
	return c
end

function module:Points(player: Player): (number, number)
	local c = char(self, player)
	if not c then
		return 0, 0
	end
	local total = math.max(0, (c.Level or 1) - Config.Talents.FirstLevel + 1) * Config.Talents.PointsPerLevel
	local spent = 0
	for _, rank in c.Talents do
		spent += rank
	end
	return total - spent, spent
end

function module:Rows(class: string)
	local out = {}
	for _, row in self:DB():Select("talent") do
		if row.class == class then
			table.insert(out, row)
		end
	end
	return out
end

local function spentIn(c, rows, tab): number
	local n = 0
	for _, row in rows do
		if row.tab == tab then
			n += c.Talents[tostring(row.id)] or 0
		end
	end
	return n
end

function module:Sync(player: Player)
	local c = char(self, player)
	if not c then
		return
	end
	local rows = self:Rows(c.Class)
	local list = {}
	for _, row in rows do
		table.insert(list, { Id = row.id, Tab = row.tab, Tier = row.tier, Col = row.col, Name = row.name, Description = row.description,
			MaxRank = row.max_rank, Rank = c.Talents[tostring(row.id)] or 0, Mod = row.mod,
			Open = (row.tier - 1) * Config.Talents.TierPoints <= spentIn(c, rows, row.tab) })
	end
	local points = self:Points(player)
	player:SetAttribute("Talents", HttpService:JSONEncode({ Points = points, Tabs = TABS[c.Class] or {}, Talents = list }))
end

function module:Learn(player: Player, id)
	local c = char(self, player)
	local row = self:DB():Get("talent", id)
	local Chat = self.includes.Chat["Chat.h"]
	if not c or not row or row.class ~= c.Class then
		return
	end
	local rank = c.Talents[tostring(row.id)] or 0
	if self:Points(player) <= 0 then
		return Chat:System(player, "You have no talent points to spend.")
	elseif rank >= (row.max_rank or 1) then
		return Chat:System(player, "That talent is already at its maximum rank.")
	elseif (row.tier - 1) * Config.Talents.TierPoints > spentIn(c, self:Rows(c.Class), row.tab) then
		return Chat:System(player, ("You need %d points in %s first."):format((row.tier - 1) * Config.Talents.TierPoints, TABS[c.Class][row.tab]))
	end
	c.Talents[tostring(row.id)] = rank + 1
	self.includes.Database["WorldDatabase.h"]:Commit(player)
	Chat:System(player, ("You have learned %s (Rank %d)."):format(row.name, rank + 1))
	if row.mod and row.mod.kind == "spell" then
		local spell = self.includes.Spells["Spells.h"]:ByName(row.mod.spell)
		if spell then
			self.includes.Spells["Spells.h"]:Learn(player, spell.id)
		end
	end
	self.includes.Entities["EntityPlayer.h"]:ApplyStats(player)
	self:Sync(player)
end

function module:Reset(player: Player): boolean
	local c = char(self, player)
	if not c then
		return false
	end
	local cost = Config.Talents.ResetCost * ((c.TalentResets or 0) + 1)
	if (c.Money or 0) < cost then
		self.includes.Chat["Chat.h"]:System(player, "You don't have enough money to unlearn your talents.")
		return false
	end
	self.includes.Entities["EntityPlayer.h"]:AddMoney(player, -cost)
	local Spells = self.includes.Spells["Spells.h"]
	for id in c.Talents do
		local row = self:DB():Get("talent", id)
		local spell = row and row.mod and row.mod.kind == "spell" and Spells:ByName(row.mod.spell)
		if spell then
			Spells:Unlearn(player, spell.id)
		end
	end
	c.Talents = {}
	c.TalentResets = (c.TalentResets or 0) + 1
	self.includes.Database["WorldDatabase.h"]:Commit(player)
	self.includes.Chat["Chat.h"]:System(player, "Your talents have been reset.")
	self.includes.Entities["EntityPlayer.h"]:ApplyStats(player)
	self:Sync(player)
	return true
end

function module:ResetCost(player: Player): number
	local c = char(self, player)
	return Config.Talents.ResetCost * ((c and c.TalentResets or 0) + 1)
end

-- Fold learned talents into a stats table (EntityPlayer:ApplyStats).
function module:ApplyMods(player: Player, stats)
	local c = char(self, player)
	if not c or next(c.Talents) == nil then
		return
	end
	local DB = self:DB()
	for id, rank in c.Talents do
		local row = DB:Get("talent", id)
		local mod = row and row.mod
		if mod then
			local value = mod.value * rank
			if mod.kind == "pct" and stats[mod.stat] then
				stats[mod.stat] *= 1 + value / 100
			elseif mod.kind == "flat" and stats[mod.stat] then
				stats[mod.stat] += value
			elseif mod.kind == "rating" and stats[mod.stat] then
				stats[mod.stat] += value
			elseif mod.kind == "school" then
				stats.SchoolMult[mod.school] = (stats.SchoolMult[mod.school] or 1) * (1 + value / 100)
			end
		end
	end
end

function module:OnLevel(player: Player)
	local c = char(self, player)
	if c and (c.Level or 1) >= Config.Talents.FirstLevel then
		self.includes.Chat["Chat.h"]:System(player, ("You have %d unspent talent point%s."):format(self:Points(player), if self:Points(player) == 1 then "" else "s"))
	end
	self:Sync(player)
end

function module:OnLogin(player: Player)
	self:Sync(player)
end

function module:Start()
	local DB = self:DB()
	local existing = {}
	for _, row in DB:Select("talent") do
		existing[row.class .. "/" .. row.name] = row
	end
	for class, tabs in TREES do
		for tab, tiers in tabs do
			local profile = tabProfile(tiers)
			for tier, talent in tiers do
				local rows = { { name = talent[1], mod = talent[2], max = if tier == 5 then 1 else 3, col = if tier == 5 then 2 else 1 } }
				if tier < 5 then
					local second = SECOND[tier]
					table.insert(rows, { name = TABS[class][tab] .. " " .. second.suffix, mod = second.mod(profile), max = second.max, col = 3 })
				end
				for _, r in rows do
					local row = existing[class .. "/" .. r.name]
					if not row then
						DB:Insert("talent", { class = class, tab = tab, tier = tier, col = r.col, name = r.name, description = describe(r.mod), max_rank = r.max, mod = r.mod })
					elseif row.col ~= r.col or row.max_rank ~= r.max or (row.mod and row.mod.kind) ~= r.mod.kind then
						DB:Update("talent", row.id, { col = r.col, max_rank = r.max, mod = r.mod, description = describe(r.mod) })
					end
				end
			end
		end
	end
	self.includes.Security["Packet.h"]:On(Opcodes.CMSG_LEARN_TALENT, function(player, data)
		if typeof(data) == "table" then
			self:Learn(player, tonumber(data.Id))
		end
	end)
end

return Base(module, {
	{ Path = "Auth/Security", Imports = "Packet.h" },
	{ Path = "Auth/Entities", Imports = "EntityPlayer.h" },
	{ Path = "Auth/Chat", Imports = "Chat.h" },
	{ Path = "World/Database", Imports = "WorldDB.h|WorldDatabase.h" },
	{ Path = "World/Spells", Imports = "Spells.h" },
})
