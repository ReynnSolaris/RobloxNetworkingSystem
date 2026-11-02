local Base = require(game:GetService("ServerStorage").ServerModules["Template.h"])
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Opcodes = require(ReplicatedStorage.Shared.Opcodes)
local Config = require(ReplicatedStorage.Shared.Config)
local module = {}

-- spell_template: { id, name, rank, description, class?, school, effect = damage|heal|
-- aura|hearth|summon, base, per_level, cost, cast_time, cooldown, range,
-- target = enemy|friend|self, aura = { kind, stat, mult, interval, duration,
-- harmful }, icon, npc }. playercreateinfo_spell: { id, class, spell } are known
-- from the start; npc_trainer: { id, entry, spell, cost, reqlevel } sells the
-- rest. A character keeps Spells = { [id] = true } and ActionBar = { [slot] = id }.
-- Mana, cooldowns and the current cast live here per player while online.
-- Creatures cast too: creature_template.spells names the spells its brain uses.

local function spell(class, name, school, effect, target, base, per, cost, cast, cd, range, icon, text, extra)
	local row = { class = class, name = name, school = school, effect = effect, target = target, base = base, per_level = per, cost = cost,
		cast_time = cast, cooldown = cd, range = range, icon = icon, description = text }
	for k, v in (extra or {}) do
		row[k] = v
	end
	return row
end
local function dmg(class, name, school, base, per, cost, cast, cd, range, icon, text, starter)
	return spell(class, name, school, "damage", "enemy", base, per, cost, cast, cd, range, icon, text, { starter = starter })
end
local function heal(class, name, base, per, cost, cast, icon, text)
	return spell(class, name, "holy", "heal", "friend", base, per, cost, cast, 0, 30, icon, text)
end
-- periodic damage: base per tick, scaled by level
local function dot(class, name, school, base, per, cost, cd, range, interval, duration, icon, text)
	return spell(class, name, school, "aura", "enemy", base, per, cost, 0, cd, range, icon, text,
		{ aura = { kind = "periodic", interval = interval, duration = duration, harmful = true } })
end
local function hot(class, name, base, per, cost, interval, duration, icon, text)
	return spell(class, name, "holy", "aura", "friend", base, per, cost, 0, 0, 30, icon, text,
		{ aura = { kind = "periodic", interval = interval, duration = duration } })
end
local function stat(class, name, school, statName, base, per, cost, duration, icon, text)
	return spell(class, name, school, "aura", "friend", base, per, cost, 0, 0, 30, icon, text,
		{ aura = { kind = "stat", stat = statName, duration = duration } })
end
local function speed(class, name, mult, duration, cost, cd, icon, text)
	return spell(class, name, "physical", "aura", "self", 0, 0, cost, 0, cd, 0, icon, text, { aura = { kind = "speed", mult = mult, duration = duration } })
end
local function slow(class, name, school, mult, duration, cost, cd, range, icon, text)
	return spell(class, name, school, "aura", "enemy", 0, 0, cost, 0, cd, range, icon, text, { aura = { kind = "speed", mult = mult, duration = duration, harmful = true } })
end
local function stun(class, name, school, duration, cost, cd, range, icon, text)
	return spell(class, name, school, "aura", "enemy", 0, 0, cost, 0, cd, range, icon, text, { aura = { kind = "stun", duration = duration, harmful = true } })
end

local SEED = {
	dmg("Warrior", "Heroic Strike", "physical", 8, 2, 10, 0, 3, 8, "HS", "A strong attack that deals extra damage.", true),
	speed("Warrior", "Battle Shout", 1.25, 20, 15, 30, "BS", "Quickens your step for 20 sec."),
	dot("Warrior", "Rend", "physical", 3, 1, 10, 0, 8, 3, 15, "RE", "Wounds the target, causing them to bleed."),
	slow("Warrior", "Hamstring", "physical", 0.5, 15, 10, 0, 8, "HM", "Maims the enemy, reducing movement speed by 50% for 15 sec."),
	dmg("Paladin", "Crusader Strike", "holy", 8, 2, 10, 0, 4, 8, "CS", "An instant strike that deals holy damage.", true),
	heal("Paladin", "Holy Light", 20, 5, 30, 2.5, "HL", "Heals a friendly target."),
	spell("Paladin", "Redemption", "holy", "resurrect", "friend", 0, 0, 60, 10, 0, 30, "RD", "Brings a dead player back to life with half their health."),
	stat("Paladin", "Blessing of Might", "holy", "Damage", 3, 1, 20, 600, "BM", "Places a Blessing on the friendly target, increasing melee damage for 10 min."),
	stun("Paladin", "Hammer of Justice", "holy", 6, 15, 60, 10, "HJ", "Stuns the target for 6 sec."),
	dmg("Hunter", "Arcane Shot", "arcane", 9, 2, 12, 0, 6, 35, "AS", "An instant shot that deals arcane damage.", true),
	spell("Hunter", "Tame Beast", "nature", "tame", "enemy", 0, 0, 0, 6, 0, 20, "TB", "Begins taming a beast to be your companion. The beast must be your level or lower."),
	spell("Hunter", "Call Pet", "nature", "callpet", "self", 0, 0, 0, 0, 5, 0, "CP", "Summons your pet to you."),
	spell("Hunter", "Dismiss Pet", "nature", "dismiss", "self", 0, 0, 0, 0, 0, 0, "DP", "Dismisses your pet."),
	speed("Hunter", "Aspect of the Cheetah", 1.3, 30, 20, 30, "AC", "Increases movement speed for 30 sec."),
	dot("Hunter", "Serpent Sting", "nature", 4, 1, 15, 0, 35, 3, 15, "SS", "Stings the target, causing nature damage over 15 sec."),
	slow("Hunter", "Concussive Shot", "physical", 0.5, 4, 10, 12, 35, "CO", "Dazes the target, slowing movement speed by 50% for 4 sec."),
	dmg("Rogue", "Sinister Strike", "physical", 8, 2, 10, 0, 2, 8, "SS", "An instant strike that deals extra damage.", true),
	speed("Rogue", "Sprint", 1.6, 15, 15, 60, "SP", "Greatly increases movement speed for 15 sec."),
	dot("Rogue", "Rupture", "physical", 4, 1, 15, 0, 8, 2, 12, "RU", "Causes the target to bleed over 12 sec."),
	stun("Rogue", "Gouge", "physical", 4, 15, 30, 8, "GO", "Stuns the target for 4 sec."),
	dmg("Priest", "Smite", "holy", 14, 3, 18, 2, 0, 30, "SM", "Smites an enemy with holy damage.", true),
	heal("Priest", "Lesser Heal", 20, 5, 25, 2, "LH", "Heals a friendly target."),
	spell("Priest", "Resurrection", "holy", "resurrect", "friend", 0, 0, 60, 10, 0, 30, "RS", "Brings a dead player back to life with half their health."),
	hot("Priest", "Renew", 5, 1, 20, 3, 15, "RN", "Heals the target over 15 sec."),
	stat("Priest", "Power Word: Fortitude", "holy", "Stamina", 3, 1, 25, 1800, "PF", "Increases the target's Stamina for 30 min."),
	dot("Priest", "Shadow Word: Pain", "shadow", 4, 1, 20, 0, 30, 3, 18, "SW", "A word of darkness that causes shadow damage over 18 sec."),
	dmg("Death Knight", "Icy Touch", "frost", 9, 2, 12, 0, 4, 20, "IT", "Chills the target for frost damage.", true),
	dmg("Death Knight", "Death Coil", "shadow", 12, 3, 20, 0, 10, 30, "DC", "Fires a blast of unholy energy."),
	dot("Death Knight", "Plague Strike", "shadow", 3, 1, 15, 0, 8, 3, 15, "PS", "A vicious strike that infects the target with Blood Plague."),
	slow("Death Knight", "Chains of Ice", "frost", 0.3, 8, 15, 20, 20, "CI", "Shackles the target, reducing movement speed by 70% for 8 sec."),
	dmg("Shaman", "Lightning Bolt", "nature", 14, 3, 18, 2.5, 0, 30, "LB", "Casts a bolt of lightning at the target.", true),
	heal("Shaman", "Healing Wave", 24, 6, 30, 3, "HW", "Heals a friendly target."),
	spell("Shaman", "Ancestral Spirit", "nature", "resurrect", "friend", 0, 0, 60, 10, 0, 30, "AN", "Returns the spirit to a dead player with half their health."),
	dot("Shaman", "Flame Shock", "fire", 4, 1, 18, 6, 20, 3, 12, "FS", "Sears the target with fire, then burns it over 12 sec."),
	dmg("Shaman", "Earth Shock", "nature", 12, 3, 20, 0, 6, 20, "ES", "Instantly shocks the target with concussive force."),
	dmg("Mage", "Fireball", "fire", 16, 3, 20, 3, 0, 35, "FB", "Hurls a fiery ball that causes fire damage.", true),
	dmg("Mage", "Frostbolt", "frost", 13, 3, 18, 2.5, 0, 30, "FR", "Launches a bolt of frost at the enemy."),
	stun("Mage", "Frost Nova", "frost", 6, 20, 25, 10, "FN", "Blasts nearby enemies with frost, freezing them in place for 6 sec."),
	stat("Mage", "Arcane Intellect", "arcane", "Intellect", 3, 1, 25, 1800, "AI", "Increases the target's Intellect for 30 min."),
	dmg("Warlock", "Shadow Bolt", "shadow", 16, 3, 20, 3, 0, 30, "SB", "Sends a shadowy bolt at the enemy.", true),
	dmg("Warlock", "Immolate", "fire", 10, 2, 15, 0, 8, 30, "IM", "Burns the enemy for fire damage."),
	spell("Warlock", "Summon Imp", "fire", "summon", "self", 0, 0, 30, 5, 0, 0, "SI", "Summons an Imp under the command of the Warlock.", { summon = "Imp" }),
	spell("Warlock", "Dismiss Pet", "shadow", "dismiss", "self", 0, 0, 0, 0, 0, 0, "DP", "Dismisses your minion."),
	dot("Warlock", "Corruption", "shadow", 4, 1, 15, 0, 30, 3, 18, "CR", "Corrupts the target, causing shadow damage over 18 sec."),
	dmg("Druid", "Wrath", "nature", 14, 3, 18, 2, 0, 30, "WR", "Causes nature damage to the target.", true),
	heal("Druid", "Healing Touch", 24, 6, 30, 3, "HT", "Heals a friendly target."),
	spell("Druid", "Rebirth", "nature", "resurrect", "friend", 0, 0, 60, 10, 600, 30, "RB", "Returns the spirit to a dead player with half their health."),
	hot("Druid", "Rejuvenation", 5, 1, 20, 3, 12, "RJ", "Heals the target over 12 sec."),
	stat("Druid", "Mark of the Wild", "nature", "Armor", 2, 1, 25, 1800, "MW", "Increases the friendly target's armor for 30 min."),
	dot("Druid", "Moonfire", "arcane", 3, 1, 15, 0, 30, 3, 12, "MF", "Burns the enemy with arcane energy over 12 sec."),
	-- item spells: no class, never trained
	{ name = "Hearthstone", school = "arcane", effect = "hearth", cost = 0, cast_time = 10, cooldown = 60, range = 0, target = "self", icon = "HS", description = "Returns you to your home. Speak to an innkeeper to change your home." },
	{ name = "Food", school = "physical", effect = "heal", base = 15, per_level = 3, cost = 0, cast_time = 0, cooldown = 5, range = 0, target = "self", icon = "FD", description = "Restores health." },
	{ name = "Minor Healing Potion", school = "nature", effect = "heal", base = 40, per_level = 5, cost = 0, cast_time = 0, cooldown = 60, range = 0, target = "self", icon = "HP", description = "Restores health instantly." },
	{ name = "Linen Bandage", school = "physical", effect = "aura", base = 8, per_level = 2, cost = 0, cast_time = 0, cooldown = 30, range = 0, target = "self", icon = "LB", description = "Heals over 6 sec.", aura = { kind = "periodic", interval = 2, duration = 6 } },
	{ name = "Summon Brown Horse", school = "physical", effect = "aura", cost = 0, cast_time = 3, cooldown = 3, range = 0, target = "self", icon = "BH", description = "Summons and dismisses a rideable Brown Horse. Increases movement speed by 60%. Taking damage dismounts you.", aura = { kind = "mount", mult = 1.6, duration = 0 } },
	{ name = "Summon Gryphon", school = "physical", effect = "aura", cost = 0, cast_time = 3, cooldown = 3, range = 0, target = "self", icon = "GR", description = "Summons and dismisses a rideable Gryphon. This mount can fly: hold Space to rise and Shift to descend. Taking damage dismounts you.", aura = { kind = "mount", mult = 2.2, duration = 0, fly = true } },
	-- creature spells: cast by brains, never learned
	{ name = "Bite", npc = true, school = "physical", effect = "aura", target = "enemy", base = 2, per_level = 1, cost = 0, cast_time = 0, cooldown = 12, range = 6, icon = "BI", description = "A savage bite that leaves the victim bleeding.", aura = { kind = "periodic", interval = 3, duration = 9, harmful = true } },
	{ name = "Throw Torch", npc = true, school = "fire", effect = "damage", target = "enemy", base = 4, per_level = 1, cost = 0, cast_time = 0, cooldown = 8, range = 20, icon = "TT", description = "Hurls a burning torch." },
	{ name = "Fire Blast", npc = true, school = "fire", effect = "damage", target = "enemy", base = 6, per_level = 2, cost = 0, cast_time = 1.5, cooldown = 6, range = 25, icon = "FB", description = "Blasts the target with fire." },
	{ name = "Firebolt", npc = true, school = "fire", effect = "damage", target = "enemy", base = 5, per_level = 1, cost = 0, cast_time = 1.5, cooldown = 4, range = 25, icon = "FI", description = "Hurls a bolt of fire." },
}

function module:DB()
	return self.includes.Database["WorldDB.h"]
end

function module:Template(id)
	return self:DB():Get("spell_template", id)
end

function module:ByName(name: string)
	for _, row in self:DB():Select("spell_template") do
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
		c.Spells = c.Spells or {}
		c.ActionBar = c.ActionBar or {}
	end
	return c
end

local function commit(self, player: Player)
	self.includes.Database["WorldDatabase.h"]:Commit(player)
end

function module:MaxMana(player: Player): number
	local stats = self.includes.Entities["EntityPlayer.h"]:Stats(player)
	return math.floor(Config.Spells.ManaForLevel(player:GetAttribute("CharacterLevel") or 1) + (stats.Mana or 0))
end

function module:State(player: Player)
	local s = self.information[player]
	if not s then
		s = { Mana = self:MaxMana(player), Cooldowns = {}, Gcd = 0, Casting = nil }
		self.information[player] = s
	end
	return s
end

function module:Sync(player: Player)
	local s = self:State(player)
	player:SetAttribute("Mana", math.floor(s.Mana))
	player:SetAttribute("MaxMana", self:MaxMana(player))
end

function module:Reset(player: Player)
	local s = self:State(player)
	s.Mana = self:MaxMana(player)
	s.Casting = nil
	self:Sync(player)
end

-- Spell power from the caster's stats: Intellect for spells, melee damage for
-- physical abilities.
function module:Amount(spell, level: number, caster): number
	local amount = (spell.base or 0) + (spell.per_level or 0) * (level - 1)
	local Combat = self.includes.Combat["Combat.h"]
	if caster and Combat:IsPlayer(caster) then
		local stats = self.includes.Entities["EntityPlayer.h"]:Stats(caster)
		if spell.effect == "damage" or (spell.aura and spell.aura.kind == "periodic") then
			amount += if spell.school == "physical" then (stats.Damage or 0) * 0.5 else (stats.SpellPower or 0) * 0.3
		elseif spell.effect == "heal" then
			amount += (stats.SpellPower or 0) * 0.3
		end
		amount *= (stats.SchoolMult and stats.SchoolMult[spell.school]) or 1
	end
	return amount
end

function module:Describe(spell, level: number, caster)
	local out = { Id = spell.id, Name = spell.name, Rank = spell.rank, Description = spell.description, Class = spell.class, School = spell.school, Effect = spell.effect,
		Cost = spell.cost or 0, CastTime = spell.cast_time or 0, Cooldown = spell.cooldown or 0, Range = spell.range or 0, Target = spell.target,
		Icon = spell.icon, Amount = math.floor(self:Amount(spell, level, caster)) }
	if spell.aura then
		out.Aura = { Kind = spell.aura.kind, Stat = spell.aura.stat, Mult = spell.aura.mult, Interval = spell.aura.interval, Duration = spell.aura.duration, Harmful = spell.aura.harmful }
	end
	return out
end

function module:SendSpells(player: Player)
	local c = char(self, player)
	if not c then
		return
	end
	local level = c.Level or 1
	local list = {}
	for id in c.Spells do
		local spell = self:Template(id)
		if spell then
			table.insert(list, self:Describe(spell, level, player))
		end
	end
	table.sort(list, function(a, b)
		return a.Id < b.Id
	end)
	local Packet = self.includes.Security["Packet.h"]
	Packet:Send(player, Opcodes.SMSG_INITIAL_SPELLS, { Spells = list })
	Packet:Send(player, Opcodes.SMSG_ACTION_BUTTONS, { Buttons = c.ActionBar })
end

-- Learning a higher rank replaces the lower one wherever it sat.
function module:Learn(player: Player, id, quiet: boolean?)
	local c = char(self, player)
	local spell = self:Template(id)
	if not c or not spell or spell.npc or c.Spells[tostring(spell.id)] then
		return false
	end
	local replaced = nil
	if spell.rank then
		for known in c.Spells do
			local other = self:Template(known)
			if other and other.name == spell.name and (other.rank or 1) < spell.rank then
				replaced = other.id
			end
		end
	end
	c.Spells[tostring(spell.id)] = true
	if replaced then
		c.Spells[tostring(replaced)] = nil
		for slot, spellId in c.ActionBar do
			if spellId == replaced then
				c.ActionBar[slot] = spell.id
			end
		end
	else
		for slot = 1, Config.Spells.ActionButtons do
			if c.ActionBar[tostring(slot)] == nil then
				c.ActionBar[tostring(slot)] = spell.id
				break
			end
		end
	end
	commit(self, player)
	if not quiet then
		self.includes.Security["Packet.h"]:Send(player, Opcodes.SMSG_LEARNED_SPELL, { Id = spell.id, Name = spell.name, Rank = spell.rank })
		self:SendSpells(player)
	end
	return true
end

function module:Unlearn(player: Player, id)
	local c = char(self, player)
	if c and c.Spells[tostring(id)] then
		c.Spells[tostring(id)] = nil
		for slot, spellId in c.ActionBar do
			if spellId == tonumber(id) then
				c.ActionBar[slot] = nil
			end
		end
		commit(self, player)
		self:SendSpells(player)
	end
end

function module:OnLogin(player: Player)
	local c = char(self, player)
	if not c then
		return
	end
	for _, row in self:DB():Select("playercreateinfo_spell") do
		if row.class == c.Class then
			self:Learn(player, row.spell, true)
		end
	end
	self:SendSpells(player)
	self:Sync(player)
end

function module:SetActionButton(player: Player, slot, id)
	local c = char(self, player)
	slot = tonumber(slot)
	if not c or not slot or slot < 1 or slot > Config.Spells.ActionButtons then
		return
	end
	id = tonumber(id)
	c.ActionBar[tostring(slot)] = if id and c.Spells[tostring(id)] then id else nil
	commit(self, player)
	self.includes.Security["Packet.h"]:Send(player, Opcodes.SMSG_ACTION_BUTTONS, { Buttons = c.ActionBar })
end

-- Right-clicking an item with a spell casts it; consumables go when it lands.
function module:UseItem(player: Player, slot, guid)
	local Entities = self.includes.Entities["EntityPlayer.h"]
	local stack = Entities:StackAt(player, tonumber(slot) or 0)
	local template = stack and self:DB():Get("item_template", stack.entry)
	if template and template.spell then
		self:Cast(player, template.spell, guid, { Entry = stack.entry, Consume = template.consumable == true })
	end
end

function module:Fail(player: Player, reason: string)
	self.includes.Security["Packet.h"]:Send(player, Opcodes.SMSG_SPELL_FAILURE, { Reason = reason })
end

-- Who a player's spell lands on. Enemy spells need a hostile creature, duel
-- opponent or PvP enemy; friendly spells take a targeted player or the caster.
function module:ResolveTarget(player: Player, spell, guid)
	local Combat = self.includes.Combat["Combat.h"]
	local root = Combat:Root(player)
	local function inRange(unit)
		local other = Combat:Root(unit)
		return other ~= nil and root ~= nil and (other.Position - root.Position).Magnitude <= math.max(spell.range or 0, Config.Combat.Range)
	end
	if spell.effect == "resurrect" then
		local target = Combat:Target(player)
		if not target or not Combat:IsPlayer(target) or not self.includes.Combat["Death.h"]:IsDead(target) then
			return nil, "Target is not dead."
		end
		local at = self.includes.Combat["Death.h"]:CorpseAt(target)
		local other = Combat:Root(target)
		local near = (at and (at.Position - root.Position).Magnitude <= (spell.range or 30)) or (other and (other.Position - root.Position).Magnitude <= (spell.range or 30))
		if not near then
			return nil, "Out of range."
		end
		return target
	elseif spell.effect == "tame" then
		local target = if guid ~= nil then self.includes.Content["Creatures.h"]:State(guid) else Combat:Target(player)
		if not target or Combat:IsPlayer(target) or not target.Template.beast then
			return nil, "That creature cannot be tamed."
		elseif (target.Level or 1) > (player:GetAttribute("CharacterLevel") or 1) then
			return nil, "That beast is too high level to tame."
		elseif self.includes.Content["Pets.h"]:Of(player) then
			return nil, "You already have a pet out."
		elseif not inRange(target) then
			return nil, "Out of range."
		end
		return target
	elseif spell.target == "enemy" then
		local target = if guid ~= nil then self.includes.Content["Creatures.h"]:State(guid) else Combat:Target(player)
		if not target or not Combat:CanAttack(player, target) then
			return nil, "Invalid target."
		end
		if not inRange(target) then
			return nil, "Out of range."
		end
		return target
	elseif spell.target == "friend" then
		local target = Combat:Target(player)
		if target and Combat:IsPlayer(target) and not Combat:CanAttack(player, target) and Combat:Alive(target) then
			if not inRange(target) then
				return nil, "Out of range."
			end
			return target
		end
		return player
	end
	return player
end

function module:Cast(player: Player, id, guid, item)
	local c = char(self, player)
	local spell = self:Template(id)
	local Combat = self.includes.Combat["Combat.h"]
	local root = Combat:Root(player)
	if not c or not spell or not root or spell.npc or (not item and not c.Spells[tostring(spell.id)]) then
		return
	end
	if spell.effect == "hearth" and not c.Home then
		return self:Fail(player, "You have no home set. Speak to an innkeeper.")
	end
	if spell.aura and spell.aura.kind == "mount" then
		if self.includes.Spells["Auras.h"]:Has(player, "mount") then
			self.includes.Spells["Auras.h"]:RemoveKind(player, "mount")
			return
		elseif self.includes.Combat["Combat.h"]:InCombat(player) then
			return self:Fail(player, "You can't mount while in combat.")
		end
	end
	if not Combat:Alive(player) then
		return self:Fail(player, "You can't do that while dead.")
	end
	if self.includes.Spells["Auras.h"]:Has(player, "stun") then
		return self:Fail(player, "You are stunned.")
	end
	local s = self:State(player)
	local now = os.clock()
	if s.Casting then
		return self:Fail(player, "Another action is in progress.")
	end
	if now < s.Gcd then
		return
	end
	if (s.Cooldowns[spell.id] or 0) > now then
		return self:Fail(player, "Spell is not ready yet.")
	end
	if s.Mana < (spell.cost or 0) then
		return self:Fail(player, "Not enough mana.")
	end
	local target, reason = self:ResolveTarget(player, spell, guid)
	if not target then
		return self:Fail(player, reason or "Invalid target.")
	end
	s.Gcd = now + Config.Spells.GlobalCooldown
	if (spell.cast_time or 0) > 0 then
		s.Casting = { Spell = spell, Target = target, Ends = now + spell.cast_time, From = root.Position, Item = item }
		self.includes.Security["Packet.h"]:Send(player, Opcodes.SMSG_SPELL_START, { Id = spell.id, Name = spell.name, CastTime = spell.cast_time })
	else
		self:Apply(player, spell, target, item)
	end
end

-- Lands a spell from any caster (player or creature state) on a unit.
function module:Apply(caster, spell, target, item)
	local Combat = self.includes.Combat["Combat.h"]
	local Packet = self.includes.Security["Packet.h"]
	local Effects = self.includes.System["Effects.h"]
	local Auras = self.includes.Spells["Auras.h"]
	local isPlayer = Combat:IsPlayer(caster)
	local level = if isPlayer then caster:GetAttribute("CharacterLevel") or 1 else caster.Level or 1
	local steady = spell.effect == "aura" and spell.aura and spell.aura.kind ~= "periodic"
	local amount = math.max(1, math.round(self:Amount(spell, level, caster) * (if steady then 1 else 0.9 + math.random() * 0.2)))
	local s = isPlayer and self:State(caster)
	if s then
		s.Casting = nil
		s.Mana = math.max(0, s.Mana - (spell.cost or 0))
		if (spell.cooldown or 0) > 0 then
			s.Cooldowns[spell.id] = os.clock() + spell.cooldown
			Packet:Send(caster, Opcodes.SMSG_SPELL_COOLDOWN, { Id = spell.id, Seconds = spell.cooldown })
		end
	end
	if spell.effect ~= "resurrect" and (not Combat:Alive(target) or (spell.target == "enemy" and spell.effect ~= "tame" and not Combat:CanAttack(caster, target))) then
		if isPlayer then
			self:Sync(caster)
			self:Fail(caster, "Invalid target.")
		end
		return
	end
	local source = if isPlayer then "Your " .. spell.name else spell.name
	if isPlayer and spell.target == "enemy" and spell.effect ~= "tame" then
		self.includes.Content["Pets.h"]:Assist(caster, target)
	end
	if spell.effect == "damage" then
		if isPlayer and Combat:Roll(caster, target) == "crit" then
			amount *= 1.5
			source = source .. " crits"
		end
		amount = Combat:Damage(caster, target, math.round(amount), spell.school, source)
	elseif spell.effect == "heal" then
		amount = Combat:Heal(caster, target, amount, source)
	elseif spell.effect == "aura" then
		Effects:Play(Combat.EFFECT[spell.school] or "Holy", if Combat:IsPlayer(target) then target else target.Row.guid, 10)
		Auras:Apply(caster, target, spell, amount)
		amount = 0
	elseif spell.effect == "tame" and isPlayer then
		if not target.Dead and target.Template.beast then
			self.includes.Content["Pets.h"]:Tame(caster, target)
		end
		amount = 0
	elseif spell.effect == "callpet" and isPlayer then
		self.includes.Content["Pets.h"]:Call(caster)
		amount = 0
	elseif spell.effect == "dismiss" and isPlayer then
		self.includes.Content["Pets.h"]:Dismiss(caster)
		amount = 0
	elseif spell.effect == "summon" and isPlayer then
		local template = self.includes.Content["Creatures.h"]:ByName(spell.summon or "")
		if template then
			Effects:Play("Shadow", caster, 16)
			self.includes.Content["Pets.h"]:Summon(caster, template.entry)
		end
		amount = 0
	elseif spell.effect == "resurrect" and isPlayer then
		self.includes.Combat["Death.h"]:Offer(target, caster)
		amount = 0
	elseif spell.effect == "hearth" and isPlayer then
		local home = char(self, caster).Home
		if home then
			Effects:Play("Arcane", caster, 16)
			self.includes.Entities["EntityPlayer.h"]:Teleport(caster, CFrame.new(home[1], home[2] + 3, home[3]))
			self.includes.Chat["Chat.h"]:System(caster, ("You return to %s."):format(home.Name or "your home"))
		end
		amount = 0
	end
	if isPlayer then
		if item and item.Consume then
			self.includes.Entities["EntityPlayer.h"]:RemoveItem(caster, item.Entry, 1)
		end
		Packet:Send(caster, Opcodes.SMSG_SPELL_GO, { Id = spell.id, Name = spell.name, Target = Combat:Name(target), Amount = amount })
		self:Sync(caster)
	end
end

function module:Interrupt(player: Player, reason: string)
	local s = self.information[player]
	if s and s.Casting then
		s.Casting = nil
		self:Fail(player, reason)
	end
end

-- A creature's brain asks for a spell by name; cast time is a short delay.
function module:CreatureCast(state, name: string, target): boolean
	local spell = self:ByName(name)
	local Combat = self.includes.Combat["Combat.h"]
	if not spell or not Combat:Alive(target) then
		return false
	end
	state.Cooldowns = state.Cooldowns or {}
	local now = os.clock()
	if (state.Cooldowns[spell.id] or 0) > now then
		return false
	end
	local root, troot = state.Root, Combat:Root(target)
	if not troot or (troot.Position - root.Position).Magnitude > math.max(spell.range or 0, Config.Combat.Range) then
		return false
	end
	state.Cooldowns[spell.id] = now + (spell.cooldown or 5)
	if (spell.cast_time or 0) > 0 then
		state.Model:SetAttribute("Casting", spell.name)
		task.delay(spell.cast_time, function()
			state.Model:SetAttribute("Casting", nil)
			if not state.Dead and self.includes.Spells["Auras.h"]:Has(state, "stun") == false then
				self:Apply(state, spell, target, nil)
			end
		end)
	else
		self:Apply(state, spell, target, nil)
	end
	return true
end

-- Trainers sell the spells of the player's class they do not know yet.
local function trainerRows(self, entry)
	local out = {}
	for _, row in self:DB():Select("npc_trainer") do
		if tostring(row.entry) == tostring(entry) then
			table.insert(out, row)
		end
	end
	return out
end

function module:IsTrainer(entry): boolean
	return #trainerRows(self, entry) > 0
end

function module:TrainerList(player: Player, guid)
	local c = char(self, player)
	local creature = self.includes.Content["Creatures.h"]:State(guid)
	if not c or not creature then
		return
	end
	local list = {}
	for _, row in trainerRows(self, creature.Row.id) do
		local spell = self:Template(row.spell)
		if spell and (spell.class == nil or spell.class == c.Class) then
			local info = self:Describe(spell, c.Level or 1, player)
			info.Price = row.cost or 0
			info.ReqLevel = row.reqlevel or 1
			info.Known = c.Spells[tostring(spell.id)] == true
			for known in c.Spells do
				local other = self:Template(known)
				if other and other.name == spell.name and (other.rank or 1) >= (spell.rank or 1) then
					info.Known = true
				end
			end
			table.insert(list, info)
		end
	end
	table.sort(list, function(a, b)
		return a.ReqLevel < b.ReqLevel or (a.ReqLevel == b.ReqLevel and a.Id < b.Id)
	end)
	self.includes.Security["Packet.h"]:Send(player, Opcodes.SMSG_TRAINER_LIST,
		{ Guid = tostring(guid), Name = creature.Template.name, Greeting = creature.Template.gossip, Spells = list })
end

function module:TrainerBuy(player: Player, guid, id)
	local c = char(self, player)
	local creature = self.includes.Content["Creatures.h"]:State(guid)
	local spell = self:Template(id)
	if not c or not creature or not spell or c.Spells[tostring(spell.id)] then
		return
	end
	local Chat = self.includes.Chat["Chat.h"]
	for _, row in trainerRows(self, creature.Row.id) do
		if tonumber(row.spell) == spell.id then
			if spell.class and spell.class ~= c.Class then
				return Chat:System(player, "That spell is not for your class.")
			elseif (c.Level or 1) < (row.reqlevel or 1) then
				return Chat:System(player, ("You must be level %d to learn that."):format(row.reqlevel))
			elseif (c.Money or 0) < (row.cost or 0) then
				return Chat:System(player, "You don't have enough money.")
			end
			if (row.cost or 0) > 0 then
				self.includes.Entities["EntityPlayer.h"]:AddMoney(player, -row.cost)
			end
			self:Learn(player, spell.id)
			self:TrainerList(player, guid)
			return
		end
	end
end

function module:Start()
	local DB = self:DB()
	local byName = {}
	for _, row in DB:Select("spell_template") do
		byName[row.name] = row
	end
	local fresh = next(byName) == nil
	local trainer
	for _, row in DB:Select("creature_template") do
		if row.name == "Class Trainer" then
			trainer = row
		end
	end
	local HttpService = game:GetService("HttpService")
	for _, seed in SEED do
		local existing = byName[seed.name]
		if existing and seed.aura and HttpService:JSONEncode(existing.aura or {}) ~= HttpService:JSONEncode(seed.aura) then
			DB:Update("spell_template", existing.id, { aura = seed.aura, description = seed.description })
		end
		if not byName[seed.name] then
			local row = table.clone(seed)
			row.starter = nil
			byName[seed.name] = DB:Insert("spell_template", row)
			-- new class spells reach old databases through the trainer
			if not fresh and trainer and seed.class and not seed.starter then
				DB:Insert("npc_trainer", { entry = trainer.entry, spell = byName[seed.name].id, cost = 100, reqlevel = 2 })
			end
		end
	end
	if fresh then
		for _, seed in SEED do
			local spell = byName[seed.name]
			if seed.starter then
				DB:Insert("playercreateinfo_spell", { class = seed.class, spell = spell.id })
			elseif trainer and seed.class then
				DB:Insert("npc_trainer", { entry = trainer.entry, spell = spell.id, cost = 100, reqlevel = 2 })
			end
		end
	end
	-- items name their spell by `use`; resolve to the id once the spell exists
	for _, item in DB:Select("item_template") do
		local spell = item.use and byName[item.use]
		if spell and item.spell ~= spell.id then
			DB:Update("item_template", item.entry, { spell = spell.id })
		end
	end

	local Packet = self.includes.Security["Packet.h"]
	Packet:On(Opcodes.CMSG_CAST_SPELL, function(player, data)
		if typeof(data) == "table" then self:Cast(player, tonumber(data.Spell), data.Guid) end
	end)
	Packet:On(Opcodes.CMSG_USE_ITEM, function(player, data)
		if typeof(data) == "table" then self:UseItem(player, data.Bag, data.Guid) end
	end)
	Packet:On(Opcodes.CMSG_CANCEL_CAST, function(player)
		self:Interrupt(player, "Interrupted.")
	end)
	Packet:On(Opcodes.CMSG_SET_ACTION_BUTTON, function(player, data)
		if typeof(data) == "table" then self:SetActionButton(player, data.Slot, data.Spell) end
	end)
	Packet:On(Opcodes.CMSG_TRAINER_BUY_SPELL, function(player, data)
		if typeof(data) == "table" then self:TrainerBuy(player, data.Guid, tonumber(data.Spell)) end
	end)
	Players.PlayerRemoving:Connect(function(player)
		self.information[player] = nil
	end)

	-- casts finish or break on movement; mana regenerates once a second, faster
	-- out of combat and with Spirit
	task.spawn(function()
		local tick = 0
		local Combat = self.includes.Combat["Combat.h"]
		while true do
			task.wait(0.1)
			tick += 1
			for player, s in self.information do
				local cast = s.Casting
				if cast then
					local root = Combat:Root(player)
					if not root or (root.Position - cast.From).Magnitude > Config.Spells.InterruptDistance then
						self:Interrupt(player, "Interrupted.")
					elseif os.clock() >= cast.Ends then
						self:Apply(player, cast.Spell, cast.Target, cast.Item)
					end
				end
				if tick % 10 == 0 and char(self, player) then
					local max = self:MaxMana(player)
					if s.Mana < max then
						local spirit = self.includes.Entities["EntityPlayer.h"]:Stats(player).Spirit or 0
						local rate = Config.Spells.ManaRegen * (if Combat:InCombat(player) then 0.5 else 1) + spirit * 0.001
						s.Mana = math.min(max, s.Mana + max * rate)
						self:Sync(player)
					elseif player:GetAttribute("MaxMana") ~= max then
						self:Sync(player)
					end
				end
			end
		end
	end)
end

return Base(module, {
	{ Path = "Auth/Security", Imports = "Packet.h" },
	{ Path = "Auth/Entities", Imports = "EntityPlayer.h" },
	{ Path = "Auth/Chat", Imports = "Chat.h" },
	{ Path = "World/Content", Imports = "Creatures.h|Pets.h" },
	{ Path = "World/Combat", Imports = "Combat.h|Duel.h|Death.h" },
	{ Path = "World/Spells", Imports = "Auras.h" },
	{ Path = "World/Database", Imports = "WorldDB.h|WorldDatabase.h" },
	{ Path = "Global/System", Imports = "Effects.h" },
})
