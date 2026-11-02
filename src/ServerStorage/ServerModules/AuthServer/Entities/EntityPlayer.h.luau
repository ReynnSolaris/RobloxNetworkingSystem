local Base = require(game:GetService("ServerStorage").ServerModules["Template.h"])
local InsertService = game:GetService("InsertService")
local ServerStorage = game:GetService("ServerStorage")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Opcodes = require(ReplicatedStorage.Shared.Opcodes)
local Config = require(ReplicatedStorage.Shared.Config)
local module = {}

local function humanoidOf(entity): Humanoid?
	return entity and entity.Character and entity.Character:FindFirstChildOfClass("Humanoid")
end

function module:Add(player: Player)
	self.information[player] = {
		Instance = player,
		Character = nil,
		Record = self.includes.Database["WorldDatabase.h"]:Load(player),
		Active = nil, -- the character record chosen at PLAYER_LOGIN
	}
end

function module:Select(player: Player, slot: number)
	local entity = self.information[player]
	local char = entity and entity.Record.Characters[slot]
	if not char then
		return false
	end
	entity.Active = char
	entity.LoginAt = os.time()
	char.Level = char.Level or 1
	char.Xp = char.Xp or 0
	player:SetAttribute("CharacterName", char.Name)
	player:SetAttribute("CharacterClass", char.Class)
	player:SetAttribute("CharacterFaction", char.Faction or "Alliance")
	player:SetAttribute("CharacterRace", char.Race or "Human")
	player:SetAttribute("Money", char.Money or 0)
	self:SyncLevel(player)
	return true
end

function module:SyncLevel(player: Player)
	local char = self.information[player] and self.information[player].Active
	if char then
		player:SetAttribute("CharacterLevel", char.Level)
		player:SetAttribute("CharacterXp", char.Xp)
		player:SetAttribute("CharacterXpNext", Config.Xp.ForLevel(char.Level))
	end
end

-- Class base stats by level, plus equipment, auras and talents, into the
-- derived numbers combat reads. Max health keeps its fraction when it changes.
local EMPTY = { Health = 100, Mana = 0, Damage = 0, Armor = 0, Crit = 5, Dodge = 5, SpellPower = 0, Strength = 0, Agility = 0, Stamina = 0, Intellect = 0, Spirit = 0 }
function module:Stats(player: Player)
	local entity = self.information[player]
	return entity and entity.Stats or EMPTY
end

function module:ApplyStats(player: Player)
	local entity = self.information[player]
	local char = entity and entity.Active
	if not char then
		return
	end
	local DB = self.includes.Database["WorldDB.h"]
	local S = Config.Stats
	local level = char.Level or 1
	local base, grow = S.Base[char.Class] or S.Base.Warrior, S.PerLevel[char.Class] or S.PerLevel.Warrior
	local stats = { Health = Config.Xp.HealthForLevel(level), Mana = 0, Damage = 0, Armor = 0, SpellPower = 0, Crit = 5, Dodge = 5, SchoolMult = {} }
	for i, name in S.Names do
		stats[name] = math.floor(base[i] + grow[i] * (level - 1))
	end
	for slot, entry in (char.Equipment or {}) do
		local item = DB:Get("item_template", entry)
		local broken = item and self:MaxDurability(item) and (char.Durability or {})[slot] == 0
		if item and not broken then
			stats.Health += item.health or 0
			stats.Damage += item.damage or 0
			stats.Armor += item.armor or 0
			stats.SpellPower += item.spellpower or 0
			for _, name in S.Names do
				stats[name] += item[name:lower()] or 0
			end
		end
	end
	local mods = self.includes.Spells["Auras.h"]:Mods(player)
	for _, name in S.Names do
		stats[name] += (mods[name] or 0) + (mods.Stats[name] or 0)
		stats[name] = math.max(0, stats[name] * (1 + (mods.Pct or 0)))
	end
	stats.Health += (mods.Health or 0) + stats.Stamina * S.HealthPerStamina
	stats.Mana += (mods.Mana or 0) + stats.Intellect * S.ManaPerIntellect
	stats.Damage += (mods.Damage or 0) + stats.Strength * S.DamagePerStrength
	stats.Armor += (mods.Armor or 0) + stats.Agility * S.ArmorPerAgility
	stats.SpellPower += stats.Intellect * S.SpellPowerPerIntellect
	stats.Crit += stats.Agility * S.CritPerAgility
	stats.Dodge += stats.Agility * S.DodgePerAgility
	self.includes.Spells["Talents.h"]:ApplyMods(player, stats)
	for key, value in stats do
		if typeof(value) == "number" then
			stats[key] = math.floor(value * 10 + 0.5) / 10
		end
	end
	stats.Health = math.floor(stats.Health)
	entity.Stats = stats
	local humanoid = humanoidOf(entity)
	if humanoid then
		local fraction = if humanoid.MaxHealth > 0 then humanoid.Health / humanoid.MaxHealth else 1
		humanoid.MaxHealth = stats.Health
		humanoid.Health = math.max(1, stats.Health * fraction)
	end
	self:SendEquipment(player)
end

function module:SetLevel(player: Player, level: number)
	local entity = self.information[player]
	local char = entity and entity.Active
	if not char then
		return
	end
	char.Level = math.clamp(level, 1, Config.Xp.MaxLevel)
	char.Xp = 0
	self:ApplyStats(player)
	self:SyncLevel(player)
	self.includes.Security["Packet.h"]:Send(player, Opcodes.SMSG_LEVELUP, { Level = char.Level })
	self.includes.Spells["Talents.h"]:OnLevel(player)
end

-- Adds experience, levelling as many times as it takes. reason is shown to the player.
-- Race shapes and colours the Roblox body: height and width through the
-- Humanoid scale values, skin on head and arms, a tunic in the class colour.
local BODY = { Head = true, LeftUpperArm = true, LeftLowerArm = true, LeftHand = true, RightUpperArm = true, RightLowerArm = true, RightHand = true }
local LEGS = { LeftUpperLeg = true, LeftLowerLeg = true, LeftFoot = true, RightUpperLeg = true, RightLowerLeg = true, RightFoot = true }
function module.Dress(character: Model, char)
	local race, class
	for _, r in Config.Races do
		if r.Name == (char.Race or "Human") then
			race = r
		end
	end
	for _, c in Config.Classes do
		if c.Name == char.Class then
			class = c
		end
	end
	race = race or Config.Races[1]
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		for name, value in { BodyHeightScale = race.Scale, BodyWidthScale = race.Width, BodyDepthScale = race.Width, HeadScale = race.Scale } do
			local scale = humanoid:FindFirstChild(name)
			if scale and scale:IsA("NumberValue") then
				scale.Value = value
			end
		end
	end
	local skin = Color3.new(table.unpack(race.Skin))
	local tunic = if class then Color3.fromHex(class.Color):Lerp(Color3.new(0, 0, 0), 0.45) else Color3.fromRGB(80, 70, 60)
	for _, part in character:GetChildren() do
		if part:IsA("BasePart") then
			if BODY[part.Name] then
				part.Color = skin
			elseif LEGS[part.Name] then
				part.Color = Color3.fromRGB(45, 38, 32)
			elseif part.Name == "UpperTorso" or part.Name == "LowerTorso" then
				part.Color = tunic
			end
		elseif part:IsA("Shirt") or part:IsA("Pants") or part:IsA("ShirtGraphic") then
			part:Destroy()
		end
	end
end

-- Resting near an innkeeper or in an Inn zone banks rested XP.
function module:IsResting(player: Player): boolean
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not root then
		return false
	end
	local zone = self.includes.Zones["Zones.h"]:Current(player)
	if zone and zone:GetAttribute("Inn") == true then
		return true
	end
	for _, state in self.includes.Content["Creatures.h"].information do
		if state.Template.innkeeper and not state.Dead and (state.Root.Position - root.Position).Magnitude <= Config.Rested.Range then
			return true
		end
	end
	return false
end

function module:GrantXp(player: Player, amount: number, reason: string?, fromKill: boolean?)
	local entity = self.information[player]
	local char = entity and entity.Active
	if not char or amount <= 0 or char.Level >= Config.Xp.MaxLevel then
		return
	end
	if fromKill then
		amount *= self.includes.Zones["GameEvents.h"]:XpMultiplier()
	end
	local rested = 0
	if fromKill and (char.Rested or 0) > 0 then
		rested = math.min(math.floor(amount), math.floor(char.Rested))
		char.Rested -= rested
		amount += rested
	end
	char.Xp += math.floor(amount)
	self.includes.Security["Packet.h"]:Send(player, Opcodes.SMSG_XP_GAIN, { Amount = math.floor(amount), Reason = reason, Rested = if rested > 0 then rested else nil })
	while char.Level < Config.Xp.MaxLevel and char.Xp >= Config.Xp.ForLevel(char.Level) do
		char.Xp -= Config.Xp.ForLevel(char.Level)
		char.Level += 1
		self:ApplyStats(player)
		self.includes.Security["Packet.h"]:Send(player, Opcodes.SMSG_LEVELUP, { Level = char.Level })
		self.includes.System["Effects.h"]:Play("LevelUp", player, 40)
		self.includes.Spells["Talents.h"]:OnLevel(player)
		self.includes.Social["Achievements.h"]:OnLevel(player, char.Level)
	end
	if char.Level >= Config.Xp.MaxLevel then
		char.Xp = 0
	end
	self:SyncLevel(player)
end

-- First visit to a zone pays exploration experience.
function module:Discover(player: Player, zoneName: string)
	local char = self.information[player] and self.information[player].Active
	if not char then
		return
	end
	char.Explored = char.Explored or {}
	if char.Explored[zoneName] then
		return
	end
	char.Explored[zoneName] = os.time()
	self:GrantXp(player, Config.Xp.Explore * char.Level, "Discovered " .. zoneName)
	self.includes.Social["Achievements.h"]:OnExplore(player, zoneName)
end

-- The bag: a list of stacks { slot, entry, count }, one per occupied slot out of
-- Config.BagSlots. Stacks merge up to the template's stack size, then the first
-- free slot is used; a full bag refuses, WoW style.

-- Backpack slots plus every equipped bag's slots.
function module:BagSize(player: Player): number
	local char = self.information[player] and self.information[player].Active
	local size = Config.BagSlots
	if char then
		local DB = self.includes.Database["WorldDB.h"]
		for _, slot in Config.BagSlotNames do
			local entry = char.Equipment and char.Equipment[slot]
			local item = entry and DB:Get("item_template", entry)
			size += item and item.container or 0
		end
	end
	return size
end

local function bag(char)
	char.Inventory = char.Inventory or {}
	for i, stack in char.Inventory do
		if stack.slot == nil then
			stack.slot = i -- records from before slots
		end
	end
	return char.Inventory
end

local function stackAt(items, slot: number)
	for _, stack in items do
		if stack.slot == slot then
			return stack
		end
	end
	return nil
end

local function freeSlot(items, size: number?): number?
	for slot = 1, size or Config.BagSlots do
		if not stackAt(items, slot) then
			return slot
		end
	end
	return nil
end

function module:System(player: Player, text: string)
	self.includes.Security["Packet.h"]:Send(player, Opcodes.SMSG_MESSAGECHAT, { Channel = "SYSTEM", Text = text })
end

function module:AddItem(player: Player, entry: number, count: number, quiet: boolean?): boolean
	local char = self.information[player] and self.information[player].Active
	local template = self.includes.Database["WorldDB.h"]:Get("item_template", entry)
	if not char or not template or count <= 0 then
		return false
	end
	local items = bag(char)
	local size = template.stack or 1
	local left = count
	for _, stack in items do
		if stack.entry == entry and stack.count < size and left > 0 then
			local add = math.min(size - stack.count, left)
			stack.count += add
			left -= add
		end
	end
	local needed = math.ceil(left / size)
	local bagSize = self:BagSize(player)
	local free = 0
	for slot = 1, bagSize do
		if not stackAt(items, slot) then
			free += 1
		end
	end
	if needed > free then
		self:System(player, "Inventory is full.")
		self:SendInventory(player, false)
		return false
	end
	while left > 0 do
		local add = math.min(size, left)
		table.insert(items, { slot = freeSlot(items, bagSize), entry = entry, count = add })
		left -= add
	end
	if not quiet then
		self.includes.Security["Packet.h"]:Send(player, Opcodes.SMSG_ITEM_PUSH,
			{ Entry = entry, Name = template.name, Quality = template.quality or 1, Count = count })
	end
	self:SendInventory(player, false)
	self.includes.Quests["Quests.h"]:OnItemChange(player)
	return true
end

function module:CountItem(player: Player, entry: number): number
	local char = self.information[player] and self.information[player].Active
	local total = 0
	for _, stack in (char and bag(char) or {}) do
		if stack.entry == entry then
			total += stack.count
		end
	end
	return total
end

function module:RemoveItem(player: Player, entry: number, count: number): boolean
	local char = self.information[player] and self.information[player].Active
	if not char or self:CountItem(player, entry) < count then
		return false
	end
	local items = bag(char)
	local left = count
	for i = #items, 1, -1 do
		local stack = items[i]
		if stack.entry == entry and left > 0 then
			local take = math.min(stack.count, left)
			stack.count -= take
			left -= take
			if stack.count == 0 then
				table.remove(items, i)
			end
		end
	end
	self:SendInventory(player, false)
	self.includes.Quests["Quests.h"]:OnItemChange(player)
	return true
end

-- Takes a whole stack out of a bag slot and returns it.
-- Bank: a second slotted container, reached through a banker's gossip.
local function bank(char)
	char.Bank = char.Bank or {}
	return char.Bank
end

function module:SendBank(player: Player, open: boolean?)
	local char = self.information[player] and self.information[player].Active
	if not char then
		return
	end
	local Items = self.includes.Content["Items.h"]
	local items = {}
	for _, stack in bank(char) do
		table.insert(items, Items:Describe(stack.entry, { Bank = stack.slot, Count = stack.count }))
	end
	self.includes.Security["Packet.h"]:Send(player, Opcodes.SMSG_SHOW_BANK, { Items = items, Slots = Config.BankSlots, Open = open == true })
end

-- Move a stack between the bag and the bank, swapping with whatever sits in the
-- destination slot. from/to are "bag"/"bank".
function module:MoveStack(player: Player, from: string, fromSlot: number, to: string, toSlot: number?)
	local char = self.information[player] and self.information[player].Active
	if not char then
		return
	end
	local lists = { bag = bag(char), bank = bank(char) }
	local limits = { bag = self:BagSize(player), bank = Config.BankSlots }
	local source, dest = lists[from], lists[to]
	if not source or not dest then
		return
	end
	local a = stackAt(source, fromSlot)
	if not a then
		return
	end
	if not toSlot then
		for slot = 1, limits[to] do
			if not stackAt(dest, slot) then
				toSlot = slot
				break
			end
		end
		if not toSlot then
			return self:System(player, if to == "bag" then "Inventory is full." else "Your bank is full.")
		end
	end
	if toSlot < 1 or toSlot > limits[to] then
		return
	end
	local b = stackAt(dest, toSlot)
	if source == dest and a == b then
		return
	end
	table.remove(source, table.find(source, a))
	if b then
		table.remove(dest, table.find(dest, b))
		b.slot = fromSlot
		table.insert(source, b)
	end
	a.slot = toSlot
	table.insert(dest, a)
	self.includes.Database["WorldDatabase.h"]:Commit(player)
	self:SendInventory(player, false)
	self:SendBank(player)
	self.includes.Quests["Quests.h"]:OnItemChange(player)
end

function module:StackAt(player: Player, slot: number)
	local char = self.information[player] and self.information[player].Active
	return char and stackAt(bag(char), slot)
end

-- Hearthstone home: where the innkeeper stood and the zone's name.
function module:SetHome(player: Player, position: Vector3, name: string)
	local char = self.information[player] and self.information[player].Active
	if not char then
		return
	end
	char.Home = { position.X, position.Y, position.Z, Name = name }
	self.includes.Database["WorldDatabase.h"]:Commit(player)
	self.includes.Security["Packet.h"]:Send(player, Opcodes.SMSG_BINDPOINTUPDATE, { Name = name })
end

function module:TakeSlot(player: Player, slot: number)
	local char = self.information[player] and self.information[player].Active
	local items = char and bag(char)
	local stack = items and stackAt(items, slot)
	if not stack then
		return nil
	end
	table.remove(items, table.find(items, stack))
	self:SendInventory(player, false)
	return stack
end

-- Move or swap bag slots; partial stacks of the same item merge, WoW style.
function module:SwapSlots(player: Player, from: number, to: number)
	local char = self.information[player] and self.information[player].Active
	local size = self:BagSize(player)
	if not char or from == to or from < 1 or to < 1 or from > size or to > size then
		return
	end
	local items = bag(char)
	local a, b = stackAt(items, from), stackAt(items, to)
	if not a then
		return
	end
	if b and b.entry == a.entry then
		local size = (self.includes.Database["WorldDB.h"]:Get("item_template", a.entry) or {}).stack or 1
		local move = math.min(size - b.count, a.count)
		if move > 0 then
			b.count += move
			a.count -= move
			if a.count == 0 then
				table.remove(items, table.find(items, a))
			end
			self:SendInventory(player, false)
			return
		end
	end
	a.slot = to
	if b then
		b.slot = from
	end
	self:SendInventory(player, false)
end

-- Equip the item in a bag slot; whatever was worn goes back to that slot.
function module:Equip(player: Player, slot: number): (boolean, string?)
	local char = self.information[player] and self.information[player].Active
	local items = char and bag(char)
	local stack = items and stackAt(items, slot)
	local item = stack and self.includes.Database["WorldDB.h"]:Get("item_template", stack.entry)
	if not item then
		return false, "Nothing there."
	end
	if not item.slot then
		return false, "That cannot be equipped."
	end
	if (item.level or 1) > (char.Level or 1) then
		return false, ("You need to be level %d."):format(item.level)
	end
	char.Equipment = char.Equipment or {}
	char.Durability = char.Durability or {}
	local allowed, why = self:MayEquip(player, item)
	if not allowed then
		return false, why
	end
	local slotName = item.slot
	if slotName == "bag" then
		slotName = nil
		for _, name in Config.BagSlotNames do
			if not char.Equipment[name] then
				slotName = name
				break
			end
		end
		if not slotName then
			return false, "All your bag slots are full."
		end
	elseif Config.PairedSlots[slotName] then
		-- rings and trinkets: the first empty of the pair, else the first
		local pair = Config.PairedSlots[slotName]
		slotName = pair[1]
		for _, name in pair do
			if not char.Equipment[name] then
				slotName = name
				break
			end
		end
	end
	local previous = char.Equipment[slotName]
	if previous and item.container then
		return false, "Take the old bag off first."
	end
	stack.count -= 1
	if stack.count == 0 then
		table.remove(items, table.find(items, stack))
	end
	char.Equipment[slotName] = stack.entry
	local previousDurability = char.Durability[slotName]
	char.Durability[slotName] = stack.durability or self:MaxDurability(item)
	if previous then
		table.insert(items, { slot = freeSlot(items, self:BagSize(player)) or slot, entry = previous, count = 1, durability = previousDurability })
	end
	self:SendInventory(player, false)
	self:ApplyStats(player)
	return true
end

-- Does the character know a passive spell by name (Dual Wield, Titan's Grip)?
function module:Knows(player: Player, spellName: string): boolean
	local char = self.information[player] and self.information[player].Active
	local DB = self.includes.Database["WorldDB.h"]
	for id in (char and char.Spells or {}) do
		local spell = DB:Get("spell_template", id)
		if spell and spell.name == spellName then
			return true
		end
	end
	return false
end

-- TC's equip rules: class proficiencies for weapon subclass and armor type,
-- shields and weapons in the off hand, two-handers.
function module:MayEquip(player: Player, item): (boolean, string?)
	local char = self.information[player] and self.information[player].Active
	local class
	for _, c in Config.Classes do
		if c.Name == (char and char.Class) then
			class = c
		end
	end
	if not class then
		return true
	end
	if not item.anyclass then
		if typeof(item.subclass) == "string" and not table.find(class.Weapons, item.subclass) then
			return false, ("%ss cannot use %s weapons."):format(class.Name, if item.subclass == "shield" then "shields as" else item.subclass)
		end
		if typeof(item.armortype) == "string" and not table.find(class.Armor, item.armortype) then
			return false, ("%ss cannot wear %s."):format(class.Name, item.armortype)
		end
	end
	local DB = self.includes.Database["WorldDB.h"]
	local main = char.Equipment and char.Equipment.mainhand and DB:Get("item_template", char.Equipment.mainhand)
	local off = char.Equipment and char.Equipment.offhand and DB:Get("item_template", char.Equipment.offhand)
	if item.slot == "offhand" then
		if item.class == "weapon" and not self:Knows(player, Config.Equip.DualWield) then
			return false, "You need the Dual Wield skill to hold a weapon in your off hand."
		end
		if main and (main.hands or 1) == 2 and not self:Knows(player, Config.Equip.TitansGrip) then
			return false, "You cannot use an off hand with a two-handed weapon."
		end
	elseif item.slot == "mainhand" and (item.hands or 1) == 2 and off and not self:Knows(player, Config.Equip.TitansGrip) then
		-- a two-hander pushes the off hand back to the bag
		if not self:Unequip(player, "offhand") then
			return false, "Free a bag slot for your off hand first."
		end
	end
	return true
end

-- Durability: armor and weapons wear with damage taken and death; at zero the
-- item gives nothing until repaired at a vendor with `repair`.
function module:MaxDurability(item): number?
	if not item or not item.slot or item.slot == "bag" or item.class == "misc" then
		return nil
	end
	return if item.class == "weapon" then Config.Durability.Weapon else Config.Durability.Armor
end

function module:Wear(player: Player, fraction: number, chance: number?)
	local char = self.information[player] and self.information[player].Active
	if not char or not char.Equipment then
		return
	end
	local DB = self.includes.Database["WorldDB.h"]
	char.Durability = char.Durability or {}
	local broke = false
	for slot, entry in char.Equipment do
		local item = DB:Get("item_template", entry)
		local max = self:MaxDurability(item)
		if max and (chance == nil or math.random() < chance) then
			local current = char.Durability[slot] or max
			local after = math.max(0, current - math.max(1, math.floor(max * fraction)))
			char.Durability[slot] = after
			if after == 0 and current > 0 then
				broke = true
				self:System(player, ("Your %s is broken."):format(item.name))
			end
		end
	end
	self:ApplyStats(player)
	if broke then
		self.includes.System["Effects.h"]:Play("Smoke", player, 6)
	end
end

function module:RepairCost(player: Player): number
	local char = self.information[player] and self.information[player].Active
	local DB = self.includes.Database["WorldDB.h"]
	local cost = 0
	for slot, entry in (char and char.Equipment or {}) do
		local item = DB:Get("item_template", entry)
		local max = self:MaxDurability(item)
		if max then
			local missing = max - ((char.Durability or {})[slot] or max)
			cost += missing * Config.Durability.CostPerPoint * math.max(1, item.level or 1) * math.max(1, (item.quality or 1))
		end
	end
	return cost
end

function module:Repair(player: Player): boolean
	local char = self.information[player] and self.information[player].Active
	if not char then
		return false
	end
	local cost = self:RepairCost(player)
	if cost == 0 then
		self:System(player, "Your equipment needs no repairs.")
		return true
	elseif (char.Money or 0) < cost then
		self:System(player, "You don't have enough money to repair.")
		return false
	end
	self:AddMoney(player, -cost)
	local DB = self.includes.Database["WorldDB.h"]
	for slot, entry in char.Equipment do
		local max = self:MaxDurability(DB:Get("item_template", entry))
		if max then
			char.Durability[slot] = max
		end
	end
	self:System(player, "Your equipment has been repaired.")
	self:ApplyStats(player)
	return true
end

function module:Unequip(player: Player, slotName: string, toSlot: number?): boolean
	local char = self.information[player] and self.information[player].Active
	local entry = char and char.Equipment and char.Equipment[slotName]
	if not entry then
		return false
	end
	local items = bag(char)
	local size = self:BagSize(player)
	local item = self.includes.Database["WorldDB.h"]:Get("item_template", entry)
	if item and item.container then
		local after = size - item.container
		for _, stack in items do
			if stack.slot > after then
				self:System(player, "That bag is not empty.")
				return false
			end
		end
		size = after
	end
	local free = if toSlot and toSlot >= 1 and toSlot <= size and not stackAt(items, toSlot) then toSlot else freeSlot(items, size)
	if not free then
		self:System(player, "Inventory is full.")
		return false
	end
	char.Equipment[slotName] = nil
	table.insert(items, { slot = free, entry = entry, count = 1, durability = char.Durability and char.Durability[slotName] })
	if char.Durability then
		char.Durability[slotName] = nil
	end
	self:SendInventory(player, false)
	self:ApplyStats(player)
	return true
end
function module:SendEquipment(player: Player)
	local entity = self.information[player]
	local char = entity and entity.Active
	if not char then
		return
	end
	local Items = self.includes.Content["Items.h"]
	local slots = {}
	for slot, entry in (char.Equipment or {}) do
		local item = Items:Template(entry)
		local max = self:MaxDurability(item)
		slots[slot] = Items:Describe(entry, { Durability = max and ((char.Durability or {})[slot] or max), MaxDurability = max })
	end
	self.includes.Security["Packet.h"]:Send(player, Opcodes.SMSG_EQUIPMENT, { Slots = slots, Stats = entity.Stats })
end

-- Copper, WoW style: 100 copper to a silver, 100 silver to a gold.
function module:AddMoney(player: Player, copper: number)
	local char = self.information[player] and self.information[player].Active
	if not char or copper == 0 then
		return
	end
	char.Money = math.max(0, (char.Money or 0) + copper)
	player:SetAttribute("Money", char.Money)
	self.includes.Security["Packet.h"]:Send(player, Opcodes.SMSG_MONEY, { Amount = copper, Total = char.Money })
	if copper > 0 then
		char.MoneyLooted = (char.MoneyLooted or 0) + copper
		self.includes.Social["Achievements.h"]:OnMoney(player, char.MoneyLooted)
	end
end

-- announce: print the list in chat (the /inv request); otherwise it is a silent refresh.
function module:SendInventory(player: Player, announce: boolean?)
	local char = self.information[player] and self.information[player].Active
	local Items = self.includes.Content["Items.h"]
	local items = {}
	for _, stack in (char and bag(char) or {}) do
		local max = self:MaxDurability(Items:Template(stack.entry))
		table.insert(items, Items:Describe(stack.entry, { Bag = stack.slot, Count = stack.count, Durability = max and (stack.durability or max), MaxDurability = max }))
	end
	self.includes.Security["Packet.h"]:Send(player, Opcodes.SMSG_INVENTORY, { Items = items, Money = char and char.Money or 0, Bags = if char then self:BagSize(player) else Config.BagSlots, Announce = announce == true })
end

function module:Get(player: Player)
	return self.information[player]
end

-- Character name, username or display name, case-insensitive, exact first then prefix.
function module:FindByName(name: string?): Player?
	if not name or #name == 0 then
		return nil
	end
	local lower = name:lower()
	local prefix = nil
	for _, player in Players:GetPlayers() do
		local names = { player:GetAttribute("CharacterName") or "", player.Name, player.DisplayName }
		for _, candidate in names do
			local c = candidate:lower()
			if c == lower then
				return player
			elseif c:sub(1, #lower) == lower then
				prefix = prefix or player
			end
		end
	end
	return prefix
end

-- Spawns the active character at `at`, else at its saved position, else at Config.Spawn.
-- ghost spawns the translucent, fast, untouchable form used between death and reclaim.
function module:Spawn(player: Player, at: CFrame?, ghost: boolean?)
	local entity = self.information[player]
	local saved = entity and entity.Active
	if not saved then
		return
	end
	entity.Ghost = ghost == true
	local Packet = self.includes.Security["Packet.h"]
	at = at or (saved.Position and CFrame.new(table.unpack(saved.Position))) or Config.Spawn

	player:LoadCharacter()
	local character = player.Character or player.CharacterAdded:Wait()
	self.includes.Movement["Anticheat.h"]:Allow(player)
	character:PivotTo(at)
	entity.Character = character

	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	humanoid.DisplayName = saved.Name
	humanoid.BreakJointsOnDeath = false
	module.Dress(character, saved)
	self.includes.Spells["Auras.h"]:Clear(player)
	self:ApplyStats(player)
	humanoid.Health = humanoid.MaxHealth
	self.includes.Spells["Spells.h"]:Reset(player)
	if saved.Health and not ghost then
		humanoid.Health = math.clamp(saved.Health, 1, humanoid.MaxHealth)
		saved.Health = nil
	end
	if ghost then
		humanoid.WalkSpeed = Config.Combat.GhostSpeed
		for _, part in character:GetDescendants() do
			if part:IsA("BasePart") then
				part.Transparency = math.max(part.Transparency, 0.6)
			elseif part:IsA("Decal") then
				part.Transparency = 0.6
			end
		end
	end

	humanoid.HealthChanged:Connect(function(health)
		Packet:Send(player, Opcodes.SMSG_HEALTH_UPDATE, { Health = health, MaxHealth = humanoid.MaxHealth })
	end)
	humanoid.Died:Once(function()
		Packet:Send(player, Opcodes.SMSG_DESPAWN, {})
		local e = self.information[player]
		if e and e.Active == saved and e.Character == character and not ghost then
			self:Wear(player, Config.Durability.DeathLoss)
			self.includes.Combat["Death.h"]:OnDeath(player, character:GetPivot())
		end
	end)

	local session = self.includes.Security["Session.h"]:Get(player)
	if session then
		session.State = self.includes.Security["Session.h"].STATE.IN_WORLD
	end
	Packet:Send(player, Opcodes.SMSG_SPAWN, {
		Position = { at.X, at.Y, at.Z },
		Health = humanoid.Health,
		MaxHealth = humanoid.MaxHealth,
	})
end

function module:Hurt(player: Player, amount: number)
	local humanoid = humanoidOf(self.information[player])
	if humanoid then
		humanoid:TakeDamage(amount)
	end
end

function module:Heal(player: Player)
	local humanoid = humanoidOf(self.information[player])
	if humanoid then
		humanoid.Health = humanoid.MaxHealth
		self.includes.System["Effects.h"]:Play("Heal", player, 20)
	end
end

function module:Teleport(player: Player, at: CFrame)
	local entity = self.information[player]
	if entity and entity.Character then
		self.includes.Movement["Anticheat.h"]:Allow(player)
		entity.Character:PivotTo(at)
	end
end

-- Timed multiplier on movement ("speed") or jumping ("jump") as an aura; < 1 is a debuff.
local BUFFS = { speed = { Id = -1, Name = "Swiftness", Icon = "SW" }, jump = { Id = -2, Name = "Spring", Icon = "SP" } }
module.BUFFS = BUFFS

function module:Buff(player: Player, effect: string, mult: number, seconds: number): boolean
	local spec = BUFFS[effect]
	if not spec or not humanoidOf(self.information[player]) then
		return false
	end
	self.includes.Spells["Auras.h"]:Apply(nil, player, { id = spec.Id, name = spec.Name, icon = spec.Icon, school = "arcane",
		description = ("%s %s by %d%%."):format(if effect == "speed" then "Movement speed" else "Jump height", if mult >= 1 then "increased" else "reduced", math.abs(mult - 1) * 100),
		aura = { kind = effect, mult = mult, duration = seconds } })
	return true
end

-- Attached bodies: mounts and shapeshift forms. A body is a list of parts
-- { name, size, offset (from the rider's root), color, parent?, motor? }, or a
-- Model under ServerStorage/MountTemplates or FormTemplates whose parts sit
-- around the origin as the rider's root: attributes Parent (part name to hang
-- on, default the first part), Motor ("leg" or "wing"), Side (-1 or 1), Phase
-- and Pivot (hinge offset from the root). Clients animate every MountMotor.
local function attachBody(character: Model, name: string, parts, root: BasePart): Model
	local model = Instance.new("Model")
	model.Name = name
	local made: { [string]: BasePart } = {}
	local first: BasePart? = nil
	for _, spec in parts do
		local p = Instance.new("Part")
		p.Name = spec.name
		p.Size = spec.size
		p.Color = spec.color
		p.Material = spec.material or Enum.Material.SmoothPlastic
		p.CanCollide = false
		p.Massless = true
		p.CFrame = root.CFrame * spec.offset
		local parent = (spec.parent and made[spec.parent]) or first or root
		if spec.motor then
			local m = Instance.new("Motor6D")
			m.Name = "MountMotor"
			m.Part0, m.Part1 = parent, p
			local hinge = root.CFrame * spec.motor.pivot
			m.C0 = parent.CFrame:ToObjectSpace(hinge)
			m.C1 = p.CFrame:ToObjectSpace(hinge)
			m:SetAttribute("Kind", spec.motor.kind)
			m:SetAttribute("Side", spec.motor.side or 1)
			m:SetAttribute("Phase", spec.motor.phase or 0)
			m.Parent = p
		else
			local weld = Instance.new("WeldConstraint")
			weld.Part0, weld.Part1 = parent, p
			weld.Parent = p
		end
		p.Parent = model
		made[spec.name] = p
		first = first or p
	end
	model.Parent = character
	return model
end

-- Reads a template Model into the part list attachBody takes.
local function templateParts(folderName: string, templateName: string)
	local folder = ServerStorage:FindFirstChild(folderName)
	local template = folder and folder:FindFirstChild(templateName)
	if not template then
		return nil
	end
	local parts = {}
	for _, part in template:GetChildren() do
		if part:IsA("BasePart") then
			local spec = { name = part.Name, size = part.Size, offset = part.CFrame, color = part.Color, material = part.Material, parent = part:GetAttribute("Parent") }
			local kind = part:GetAttribute("Motor")
			if kind then
				local pivot = part:GetAttribute("Pivot")
				spec.motor = { kind = kind, side = part:GetAttribute("Side") or 1, phase = part:GetAttribute("Phase") or 0,
					pivot = CFrame.new(if typeof(pivot) == "Vector3" then pivot else part.Position) }
			end
			table.insert(parts, spec)
		end
	end
	-- the body first so the others can hang on it
	table.sort(parts, function(a, b)
		return (a.name == "Body" and b.name ~= "Body") or (a.name ~= "Body" and b.name ~= "Body" and a.name < b.name)
	end)
	return parts
end

local function legs(kind, y, zs, xs, color, size)
	local out = {}
	for _, x in xs do
		for i, z in zs do
			table.insert(out, { name = "Leg", size = size or Vector3.new(0.6, 2.6, 0.6), offset = CFrame.new(x, y, z), color = color, parent = "Body",
				motor = { kind = kind, side = if x < 0 then -1 else 1, phase = if (i == 1) == (x > 0) then 0 else math.pi, pivot = CFrame.new(x, y + 1.1, z) } })
		end
	end
	return out
end

local BODIES = {}
function BODIES.horse()
	local brown, dark, leather = Color3.fromRGB(96, 62, 36), Color3.fromRGB(40, 28, 18), Color3.fromRGB(70, 45, 28)
	local parts = {
		{ name = "Body", size = Vector3.new(2.2, 2, 5), offset = CFrame.new(0, -2.6, 0), color = brown },
		{ name = "Saddle", size = Vector3.new(2.4, 0.5, 2), offset = CFrame.new(0, -1.5, 0), color = leather },
		{ name = "Neck", size = Vector3.new(1.2, 2.4, 1.2), offset = CFrame.new(0, -1.4, -2.8) * CFrame.Angles(math.rad(-30), 0, 0), color = brown },
		{ name = "Head", size = Vector3.new(1.1, 1.1, 2), offset = CFrame.new(0, -0.4, -3.9), color = brown },
		{ name = "Mane", size = Vector3.new(0.4, 1.6, 1.6), offset = CFrame.new(0, -0.8, -2.6), color = dark },
		{ name = "Tail", size = Vector3.new(0.5, 2, 0.5), offset = CFrame.new(0, -3, 2.8) * CFrame.Angles(math.rad(25), 0, 0), color = dark },
	}
	for _, leg in legs("leg", -4.8, { -1.8, 1.8 }, { -0.75, 0.75 }, dark) do table.insert(parts, leg) end
	return parts
end
function BODIES.gryphon()
	local feather, gold, leather = Color3.fromRGB(230, 232, 240), Color3.fromRGB(214, 170, 70), Color3.fromRGB(70, 45, 28)
	local parts = {
		{ name = "Body", size = Vector3.new(2.4, 2, 5.5), offset = CFrame.new(0, -2.6, 0.3), color = feather },
		{ name = "Saddle", size = Vector3.new(2.6, 0.5, 2.2), offset = CFrame.new(0, -1.5, 0), color = leather },
		{ name = "Neck", size = Vector3.new(1.4, 2.2, 1.4), offset = CFrame.new(0, -1.3, -2.8) * CFrame.Angles(math.rad(-25), 0, 0), color = feather },
		{ name = "Head", size = Vector3.new(1.3, 1.2, 1.8), offset = CFrame.new(0, -0.3, -3.9), color = feather },
		{ name = "Beak", size = Vector3.new(0.5, 0.5, 0.9), offset = CFrame.new(0, -0.5, -5.1), color = gold },
		{ name = "Tail", size = Vector3.new(1.6, 0.3, 2.2), offset = CFrame.new(0, -2.4, 3.9), color = feather },
	}
	for _, side in { -1, 1 } do
		table.insert(parts, { name = "Wing" .. side, size = Vector3.new(5, 0.3, 3), offset = CFrame.new(side * 3.6, -1.6, 0) * CFrame.Angles(0, 0, side * math.rad(18)), color = feather,
			motor = { kind = "wing", side = side, pivot = CFrame.new(side * 1.2, -1.6, 0) } })
		table.insert(parts, { name = "WingTip" .. side, size = Vector3.new(2.4, 0.25, 2), offset = CFrame.new(side * 7, -0.6, 0.3) * CFrame.Angles(0, 0, side * math.rad(32)), color = feather, parent = "Wing" .. side })
	end
	for _, leg in legs("leg", -4.7, { -1.8, 1.8 }, { -0.8, 0.8 }, gold, Vector3.new(0.6, 2.4, 0.6)) do table.insert(parts, leg) end
	return parts
end
-- shapeshift forms stand where the body was
local function quadruped(color, dark, size, headSize, tail)
	local parts = {
		{ name = "Body", size = size, offset = CFrame.new(0, -1.2, 0), color = color },
		{ name = "Head", size = headSize, offset = CFrame.new(0, -0.6, -size.Z / 2 - headSize.Z / 2 + 0.3), color = color },
		{ name = "Snout", size = Vector3.new(headSize.X * 0.5, headSize.Y * 0.5, 0.8), offset = CFrame.new(0, -0.8, -size.Z / 2 - headSize.Z + 0.1), color = dark },
		{ name = "EarL", size = Vector3.new(0.4, 0.5, 0.2), offset = CFrame.new(-headSize.X / 3, headSize.Y / 2 - 0.6, -size.Z / 2 - headSize.Z / 2 + 0.3), color = dark },
		{ name = "EarR", size = Vector3.new(0.4, 0.5, 0.2), offset = CFrame.new(headSize.X / 3, headSize.Y / 2 - 0.6, -size.Z / 2 - headSize.Z / 2 + 0.3), color = dark },
	}
	if tail then
		table.insert(parts, { name = "Tail", size = Vector3.new(0.3, 0.3, 2), offset = CFrame.new(0, -1, size.Z / 2 + 0.9) * CFrame.Angles(math.rad(20), 0, 0), color = dark })
	end
	for _, leg in legs("leg", -2.4, { -size.Z / 2 + 0.6, size.Z / 2 - 0.6 }, { -size.X / 2 + 0.35, size.X / 2 - 0.35 }, dark, Vector3.new(0.55, 1.6, 0.55)) do table.insert(parts, leg) end
	return parts
end
function BODIES.bear() return quadruped(Color3.fromRGB(80, 52, 30), Color3.fromRGB(45, 30, 18), Vector3.new(2.8, 2.2, 4.4), Vector3.new(1.6, 1.4, 1.6), false) end
function BODIES.cat() return quadruped(Color3.fromRGB(190, 140, 70), Color3.fromRGB(110, 70, 30), Vector3.new(1.4, 1.2, 3.6), Vector3.new(1, 0.9, 1.1), true) end
function BODIES.travel() return quadruped(Color3.fromRGB(210, 170, 90), Color3.fromRGB(120, 90, 40), Vector3.new(1.3, 1.1, 3.8), Vector3.new(0.9, 0.8, 1), true) end
function BODIES.wolf() return quadruped(Color3.fromRGB(150, 160, 190), Color3.fromRGB(90, 100, 130), Vector3.new(1.6, 1.3, 3.8), Vector3.new(1, 0.9, 1.3), true) end
function BODIES.moonkin()
	local feather, dark = Color3.fromRGB(120, 90, 150), Color3.fromRGB(70, 50, 90)
	local parts = {
		{ name = "Body", size = Vector3.new(2.6, 3, 2.2), offset = CFrame.new(0, -0.6, 0), color = feather },
		{ name = "Head", size = Vector3.new(2, 1.6, 1.8), offset = CFrame.new(0, 1.7, 0), color = feather },
		{ name = "Beak", size = Vector3.new(0.5, 0.5, 0.6), offset = CFrame.new(0, 1.5, -1.1), color = Color3.fromRGB(214, 170, 70) },
		{ name = "HornL", size = Vector3.new(0.3, 1, 0.3), offset = CFrame.new(-0.8, 2.6, 0) * CFrame.Angles(0, 0, math.rad(20)), color = dark },
		{ name = "HornR", size = Vector3.new(0.3, 1, 0.3), offset = CFrame.new(0.8, 2.6, 0) * CFrame.Angles(0, 0, math.rad(-20)), color = dark },
	}
	for _, side in { -1, 1 } do
		table.insert(parts, { name = "Wing" .. side, size = Vector3.new(2.4, 2, 0.4), offset = CFrame.new(side * 2.2, -0.4, 0), color = dark, motor = { kind = "wing", side = side, pivot = CFrame.new(side * 1.2, 0.4, 0) } })
	end
	for _, leg in legs("leg", -3, { 0 }, { -0.6, 0.6 }, dark, Vector3.new(0.6, 1.4, 0.6)) do table.insert(parts, leg) end
	return parts
end
function BODIES.tree()
	local bark, leaf = Color3.fromRGB(90, 60, 35), Color3.fromRGB(60, 130, 50)
	return {
		{ name = "Body", size = Vector3.new(1.8, 4.2, 1.8), offset = CFrame.new(0, 0, 0), color = bark, material = Enum.Material.Wood },
		{ name = "Crown", size = Vector3.new(3.6, 2.2, 3.6), offset = CFrame.new(0, 2.8, 0), color = leaf, material = Enum.Material.Grass },
		{ name = "BranchL", size = Vector3.new(2.4, 0.4, 0.4), offset = CFrame.new(-1.6, 1, 0) * CFrame.Angles(0, 0, math.rad(25)), color = bark },
		{ name = "BranchR", size = Vector3.new(2.4, 0.4, 0.4), offset = CFrame.new(1.6, 1, 0) * CFrame.Angles(0, 0, math.rad(-25)), color = bark },
		{ name = "RootL", size = Vector3.new(0.6, 1.2, 0.6), offset = CFrame.new(-0.6, -2.6, 0), color = bark, motor = { kind = "leg", side = -1, pivot = CFrame.new(-0.6, -2, 0) } },
		{ name = "RootR", size = Vector3.new(0.6, 1.2, 0.6), offset = CFrame.new(0.6, -2.6, 0), color = bark, motor = { kind = "leg", side = 1, phase = math.pi, pivot = CFrame.new(0.6, -2, 0) } },
	}
end
function BODIES.shadow()
	return {}
end

local function hideBody(character: Model, hidden: boolean)
	for _, part in character:GetChildren() do
		if (part:IsA("BasePart") and part.Name ~= "HumanoidRootPart") or part:IsA("Accessory") then
			local target = if part:IsA("Accessory") then part:FindFirstChildWhichIsA("BasePart") else part
			if target then
				if hidden and target:GetAttribute("ShownTransparency") == nil then
					target:SetAttribute("ShownTransparency", target.Transparency)
				end
				target.Transparency = if hidden then 1 else (target:GetAttribute("ShownTransparency") or 0)
				if not hidden then
					target:SetAttribute("ShownTransparency", nil)
				end
				for _, decal in target:GetChildren() do
					if decal:IsA("Decal") then
						decal.Transparency = if hidden then 1 else 0
					end
				end
			end
		end
	end
end

-- A mount: a template by name or a built-in body, saddle and all; flight from
-- the client's controller once MountFlying is set.
function module:Mount(player: Player, on: boolean, fly: boolean?, modelName: string?)
	local entity = self.information[player]
	local character = entity and entity.Character
	if not character then
		return
	end
	local existing = character:FindFirstChild("Mount")
	if existing then
		existing:Destroy()
	end
	player:SetAttribute("Mounted", if on then true else nil)
	player:SetAttribute("MountFlying", if on and fly then true else nil)
	if not on then
		return
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	local parts = (modelName and templateParts("MountTemplates", modelName)) or (if fly then BODIES.gryphon() else BODIES.horse())
	attachBody(character, "Mount", parts, root)
end

-- Shapeshift: the body is hidden and a form body stands in its place; nil
-- shifts back. Forms come from ServerStorage/FormTemplates/<form> or BODIES.
function module:Shapeshift(player: Player, form: string?)
	local entity = self.information[player]
	local character = entity and entity.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not character or not root then
		return
	end
	local existing = character:FindFirstChild("Form")
	if existing then
		existing:Destroy()
	end
	self.includes.System["Effects.h"]:Detach("Shadow", root)
	hideBody(character, false)
	player:SetAttribute("Form", form)
	if not form then
		return
	end
	self.includes.System["Effects.h"]:Play("Nature", player, 18)
	if form == "shadow" then
		self.includes.System["Effects.h"]:Attach("Shadow", root)
		return
	end
	local parts = templateParts("FormTemplates", form) or (BODIES[form] and BODIES[form]()) or BODIES.cat()
	hideBody(character, true)
	attachBody(character, "Form", parts, root)
end

-- Stealth: translucent to everyone and marked for the creature brains.
function module:Stealth(player: Player, on: boolean)
	local entity = self.information[player]
	local character = entity and entity.Character
	if not character then
		return
	end
	player:SetAttribute("Stealthed", if on then true else nil)
	for _, part in character:GetDescendants() do
		if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" and part.Transparency < 1 then
			part.Transparency = if on then 0.75 else 0
		end
	end
end

function module:GiveHat(player: Player, assetId: number): boolean
	local entity = self.information[player]
	if not entity or not entity.Character then
		return false
	end
	local ok, asset = pcall(InsertService.LoadAsset, InsertService, assetId)
	if not ok then
		return false
	end
	local hat = asset:GetChildren()[1]
	hat.Parent = entity.Character
	asset:Destroy()
	return true
end

-- Writes the active character's position and health into the record.
function module:Save(player: Player)
	local entity = self.information[player]
	local humanoid = humanoidOf(entity)
	if entity and entity.Active and entity.LoginAt then
		entity.Active.Played = (entity.Active.Played or 0) + (os.time() - entity.LoginAt)
		entity.LoginAt = os.time()
	end
	if entity and entity.Active and humanoid and humanoid.Health > 0 and not entity.Ghost then
		local position = entity.Character:GetPivot().Position
		entity.Active.Position = { position.X, position.Y, position.Z }
		entity.Active.Health = humanoid.Health
		self.includes.Database["WorldDatabase.h"]:Commit(player)
	end
end

-- Back to character select: save, drop the character, forget the selection.
function module:Despawn(player: Player)
	local entity = self.information[player]
	if not entity then
		return
	end
	self:Save(player)
	self.includes.Spells["Auras.h"]:Clear(player)
	if entity.Character then
		entity.Character:Destroy()
		entity.Character = nil
	end
	entity.Active = nil
	player:SetAttribute("CharacterName", nil)
	player:SetAttribute("CharacterClass", nil)
	player:SetAttribute("CharacterLevel", nil)
end

function module:Remove(player: Player)
	self:Save(player)
	self.information[player] = nil
	self.includes.Database["WorldDatabase.h"]:Forget(player)
end

return Base(module, {
	{ Path = "Auth/Security", Imports = "Packet.h|Session.h" },
	{ Path = "World/Database", Imports = "WorldDatabase.h|WorldDB.h" },
	{ Path = "World/Movement", Imports = "Anticheat.h" },
	{ Path = "World/Combat", Imports = "Death.h" },
	{ Path = "World/Quests", Imports = "Quests.h" },
	{ Path = "World/Spells", Imports = "Spells.h|Auras.h|Talents.h" },
	{ Path = "World/Zones", Imports = "Zones.h|GameEvents.h" },
	{ Path = "World/Content", Imports = "Creatures.h|Items.h" },
	{ Path = "Auth/Social", Imports = "Achievements.h" },
	{ Path = "Global/System", Imports = "Effects.h" },
})
