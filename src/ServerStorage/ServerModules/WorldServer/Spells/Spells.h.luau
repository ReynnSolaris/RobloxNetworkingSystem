local Base = require(game:GetService("ServerStorage").ServerModules["Template.h"])
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Opcodes = require(ReplicatedStorage.Shared.Opcodes)
local Config = require(ReplicatedStorage.Shared.Config)
local module = {}

-- spell_template: { id, name, description, class?, school, effect = damage|heal|buff,
-- base, per_level, cost, cast_time, cooldown, range, target = enemy|self, buff, mult,
-- duration, icon }. playercreateinfo_spell: { id, class, spell } are known from the
-- start; npc_trainer: { id, entry, spell, cost, reqlevel } sells the rest. A character
-- keeps Spells = { [id] = true } and ActionBar = { [slot] = id }. Mana, cooldowns and
-- the current cast live here per player while they are online.

local EFFECT = { physical = "Hit", holy = "Holy", fire = "Fire", nature = "Nature", frost = "Frost", shadow = "Shadow", arcane = "Arcane" }

local function dmg(class, name, school, base, per, cost, cast, cd, range, icon, text, starter)
	return { class = class, name = name, school = school, effect = "damage", base = base, per_level = per, cost = cost, cast_time = cast, cooldown = cd, range = range, target = "enemy", icon = icon, description = text, starter = starter }
end
local function heal(class, name, base, per, cost, cast, icon, text)
	return { class = class, name = name, school = "holy", effect = "heal", base = base, per_level = per, cost = cost, cast_time = cast, cooldown = 0, range = 30, target = "self", icon = icon, description = text }
end
local function speed(class, name, mult, duration, cost, cd, icon, text)
	return { class = class, name = name, school = "physical", effect = "buff", buff = "speed", mult = mult, duration = duration, cost = cost, cast_time = 0, cooldown = cd, range = 0, target = "self", icon = icon, description = text }
end

local SEED = {
	dmg("Warrior", "Heroic Strike", "physical", 8, 2, 10, 0, 3, 8, "HS", "A strong attack that deals extra damage.", true),
	speed("Warrior", "Battle Shout", 1.25, 20, 15, 30, "BS", "Quickens your step for 20 sec."),
	dmg("Paladin", "Crusader Strike", "holy", 8, 2, 10, 0, 4, 8, "CS", "An instant strike that deals holy damage.", true),
	heal("Paladin", "Holy Light", 20, 5, 30, 2.5, "HL", "Heals a friendly target."),
	dmg("Hunter", "Arcane Shot", "arcane", 9, 2, 12, 0, 6, 35, "AS", "An instant shot that deals arcane damage.", true),
	speed("Hunter", "Aspect of the Cheetah", 1.3, 30, 20, 30, "AC", "Increases movement speed for 30 sec."),
	dmg("Rogue", "Sinister Strike", "physical", 8, 2, 10, 0, 2, 8, "SS", "An instant strike that deals extra damage.", true),
	speed("Rogue", "Sprint", 1.6, 15, 15, 60, "SP", "Greatly increases movement speed for 15 sec."),
	dmg("Priest", "Smite", "holy", 14, 3, 18, 2, 0, 30, "SM", "Smites an enemy with holy damage.", true),
	heal("Priest", "Lesser Heal", 20, 5, 25, 2, "LH", "Heals a friendly target."),
	dmg("Death Knight", "Icy Touch", "frost", 9, 2, 12, 0, 4, 20, "IT", "Chills the target for frost damage.", true),
	dmg("Death Knight", "Death Coil", "shadow", 12, 3, 20, 0, 10, 30, "DC", "Fires a blast of unholy energy."),
	dmg("Shaman", "Lightning Bolt", "nature", 14, 3, 18, 2.5, 0, 30, "LB", "Casts a bolt of lightning at the target.", true),
	heal("Shaman", "Healing Wave", 24, 6, 30, 3, "HW", "Heals a friendly target."),
	dmg("Mage", "Fireball", "fire", 16, 3, 20, 3, 0, 35, "FB", "Hurls a fiery ball that causes fire damage.", true),
	dmg("Mage", "Frostbolt", "frost", 13, 3, 18, 2.5, 0, 30, "FR", "Launches a bolt of frost at the enemy."),
	dmg("Warlock", "Shadow Bolt", "shadow", 16, 3, 20, 3, 0, 30, "SB", "Sends a shadowy bolt at the enemy.", true),
	dmg("Warlock", "Immolate", "fire", 10, 2, 15, 0, 8, 30, "IM", "Burns the enemy for fire damage."),
	dmg("Druid", "Wrath", "nature", 14, 3, 18, 2, 0, 30, "WR", "Causes nature damage to the target.", true),
	heal("Druid", "Healing Touch", 24, 6, 30, 3, "HT", "Heals a friendly target."),
	-- item spells: no class, never trained
	{ name = "Hearthstone", school = "arcane", effect = "hearth", cost = 0, cast_time = 10, cooldown = 60, range = 0, target = "self", icon = "HS", description = "Returns you to your home. Speak to an innkeeper to change your home." },
	{ name = "Food", school = "physical", effect = "heal", base = 15, per_level = 3, cost = 0, cast_time = 0, cooldown = 5, range = 0, target = "self", icon = "FD", description = "Restores health." },
}

function module:DB()
	return self.includes.Database["WorldDB.h"]
end

function module:Template(id)
	return self:DB():Get("spell_template", id)
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
	return Config.Spells.ManaForLevel(player:GetAttribute("CharacterLevel") or 1)
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

function module:Amount(spell, level: number): number
	return (spell.base or 0) + (spell.per_level or 0) * (level - 1)
end

function module:Describe(spell, level: number)
	return { Id = spell.id, Name = spell.name, Description = spell.description, Class = spell.class, School = spell.school, Effect = spell.effect,
		Cost = spell.cost or 0, CastTime = spell.cast_time or 0, Cooldown = spell.cooldown or 0, Range = spell.range or 0, Target = spell.target,
		Icon = spell.icon, Amount = self:Amount(spell, level), Duration = spell.duration }
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
			table.insert(list, self:Describe(spell, level))
		end
	end
	table.sort(list, function(a, b)
		return a.Id < b.Id
	end)
	local Packet = self.includes.Security["Packet.h"]
	Packet:Send(player, Opcodes.SMSG_INITIAL_SPELLS, { Spells = list })
	Packet:Send(player, Opcodes.SMSG_ACTION_BUTTONS, { Buttons = c.ActionBar })
end

function module:Learn(player: Player, id, quiet: boolean?)
	local c = char(self, player)
	local spell = self:Template(id)
	if not c or not spell or c.Spells[tostring(spell.id)] then
		return false
	end
	c.Spells[tostring(spell.id)] = true
	for slot = 1, Config.Spells.ActionButtons do
		if c.ActionBar[tostring(slot)] == nil then
			c.ActionBar[tostring(slot)] = spell.id
			break
		end
	end
	commit(self, player)
	if not quiet then
		self.includes.Security["Packet.h"]:Send(player, Opcodes.SMSG_LEARNED_SPELL, { Id = spell.id, Name = spell.name })
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

local function rootOf(player: Player): BasePart?
	return player.Character and player.Character:FindFirstChild("HumanoidRootPart")
end

function module:Cast(player: Player, id, guid, item)
	local c = char(self, player)
	local spell = self:Template(id)
	local entity = self.includes.Entities["EntityPlayer.h"]:Get(player)
	local root = rootOf(player)
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if not c or not spell or not root or not humanoid or (not item and not c.Spells[tostring(spell.id)]) then
		return
	end
	if spell.effect == "hearth" and not c.Home then
		return self:Fail(player, "You have no home set. Speak to an innkeeper.")
	end
	if humanoid.Health <= 0 or (entity and entity.Ghost) then
		return self:Fail(player, "You can't do that while dead.")
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
	local target = player
	if spell.target == "enemy" then
		local creature = self.includes.Content["Creatures.h"]:State(guid)
		if not creature or creature.Dead or not creature.Hostile then
			return self:Fail(player, "Invalid target.")
		end
		if (creature.Root.Position - root.Position).Magnitude > (spell.range or 0) then
			return self:Fail(player, "Out of range.")
		end
		target = tostring(guid)
	end
	s.Gcd = now + Config.Spells.GlobalCooldown
	if (spell.cast_time or 0) > 0 then
		s.Casting = { Spell = spell, Target = target, Ends = now + spell.cast_time, From = root.Position, Item = item }
		self.includes.Security["Packet.h"]:Send(player, Opcodes.SMSG_SPELL_START, { Id = spell.id, Name = spell.name, CastTime = spell.cast_time })
	else
		self:Apply(player, spell, target, item)
	end
end

function module:Apply(player: Player, spell, target, item)
	local s = self:State(player)
	local Packet = self.includes.Security["Packet.h"]
	local Combat = self.includes.Combat["Combat.h"]
	local Effects = self.includes.System["Effects.h"]
	local level = player:GetAttribute("CharacterLevel") or 1
	local amount = math.max(1, math.round(self:Amount(spell, level) * (0.9 + math.random() * 0.2)))
	s.Casting = nil
	s.Mana = math.max(0, s.Mana - (spell.cost or 0))
	if (spell.cooldown or 0) > 0 then
		s.Cooldowns[spell.id] = os.clock() + spell.cooldown
		Packet:Send(player, Opcodes.SMSG_SPELL_COOLDOWN, { Id = spell.id, Seconds = spell.cooldown })
	end
	local targetName = player:GetAttribute("CharacterName") or player.Name
	if spell.effect == "damage" then
		local Creatures = self.includes.Content["Creatures.h"]
		local creature = Creatures:State(target)
		if not creature or creature.Dead then
			self:Sync(player)
			return self:Fail(player, "Invalid target.")
		end
		creature.Humanoid:TakeDamage(amount)
		Creatures:Aggro(target, player)
		Effects:Play(EFFECT[spell.school] or "Hit", target, 10)
		targetName = creature.Template.name
		Combat:Log(player, ("Your %s hits %s for %d."):format(spell.name, targetName, amount), Config.Chat.Colors.HIT)
	elseif spell.effect == "heal" then
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			amount = math.min(amount, math.max(0, math.floor(humanoid.MaxHealth - humanoid.Health)))
			humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + amount)
		end
		Effects:Play("Heal", player, 14)
		Combat:Log(player, ("Your %s heals you for %d."):format(spell.name, amount), Config.Chat.Colors.LOOT)
	elseif spell.effect == "buff" then
		self.includes.Entities["EntityPlayer.h"]:Buff(player, spell.buff, spell.mult or 1, spell.duration or 10)
		Effects:Play("Holy", player, 12)
		Combat:Log(player, ("You gain %s."):format(spell.name), Config.Chat.Colors.LOOT)
		amount = 0
	elseif spell.effect == "hearth" then
		local home = char(self, player).Home
		if home then
			Effects:Play("Arcane", player, 16)
			self.includes.Entities["EntityPlayer.h"]:Teleport(player, CFrame.new(home[1], home[2] + 3, home[3]))
			self.includes.Chat["Chat.h"]:System(player, ("You return to %s."):format(home.Name or "your home"))
		end
		amount = 0
	end
	if item and item.Consume then
		self.includes.Entities["EntityPlayer.h"]:RemoveItem(player, item.Entry, 1)
	end
	Packet:Send(player, Opcodes.SMSG_SPELL_GO, { Id = spell.id, Name = spell.name, Target = targetName, Amount = amount })
	self:Sync(player)
end

function module:Interrupt(player: Player, reason: string)
	local s = self.information[player]
	if s and s.Casting then
		s.Casting = nil
		self:Fail(player, reason)
	end
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
			local info = self:Describe(spell, c.Level or 1)
			info.Price = row.cost or 0
			info.ReqLevel = row.reqlevel or 1
			info.Known = c.Spells[tostring(spell.id)] == true
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
	for _, seed in SEED do
		if not byName[seed.name] then
			local row = table.clone(seed)
			row.starter = nil
			byName[seed.name] = DB:Insert("spell_template", row)
		end
	end
	if fresh then
		local trainer
		for _, row in DB:Select("creature_template") do
			if row.name == "Class Trainer" then
				trainer = row
			end
		end
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

	-- casts finish or break on movement; mana regenerates once a second
	task.spawn(function()
		local tick = 0
		while true do
			task.wait(0.1)
			tick += 1
			for player, s in self.information do
				local cast = s.Casting
				if cast then
					local root = rootOf(player)
					if not root or (root.Position - cast.From).Magnitude > Config.Spells.InterruptDistance then
						self:Interrupt(player, "Interrupted.")
					elseif os.clock() >= cast.Ends then
						self:Apply(player, cast.Spell, cast.Target, cast.Item)
					end
				end
				if tick % 10 == 0 and char(self, player) then
					local max = self:MaxMana(player)
					if s.Mana < max then
						s.Mana = math.min(max, s.Mana + max * Config.Spells.ManaRegen)
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
	{ Path = "World/Content", Imports = "Creatures.h" },
	{ Path = "World/Combat", Imports = "Combat.h" },
	{ Path = "World/Database", Imports = "WorldDB.h|WorldDatabase.h" },
	{ Path = "Global/System", Imports = "Effects.h" },
})
