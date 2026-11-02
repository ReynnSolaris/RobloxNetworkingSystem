local Base = require(game:GetService("ServerStorage").ServerModules["Template.h"])
local InsertService = game:GetService("InsertService")
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
	if item.subclass and not table.find(class.Weapons, item.subclass) then
		return false, ("%ss cannot use %s weapons."):format(class.Name, if item.subclass == "shield" then "shields as" else item.subclass)
	end
	if item.armor and not table.find(class.Armor, item.armor) then
		return false, ("%ss cannot wear %s."):format(class.Name, item.armor)
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

-- A mount is drawn as a horse or gryphon body welded under the character; the
-- speed comes from the aura, flight from the client's controller once
-- MountFlying is set.
function module:Mount(player: Player, on: boolean, fly: boolean?)
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
	local mount = Instance.new("Model")
	mount.Name = "Mount"
	-- parts weld to the root; wings and legs hang on Motor6Ds the clients animate
	local function part(name, size, offset, color, parent, motor)
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.Color = color
		p.Material = Enum.Material.SmoothPlastic
		p.CanCollide = false
		p.Massless = true
		p.CFrame = root.CFrame * offset
		if motor then
			local m = Instance.new("Motor6D")
			m.Name = "MountMotor"
			m.Part0, m.Part1 = parent, p
			m.C0 = parent.CFrame:ToObjectSpace(root.CFrame * motor.pivot)
			m.C1 = p.CFrame:ToObjectSpace(root.CFrame * motor.pivot)
			m:SetAttribute("Kind", motor.kind)
			m:SetAttribute("Side", motor.side)
			m:SetAttribute("Phase", motor.phase or 0)
			m.Parent = p
		else
			local weld = Instance.new("WeldConstraint")
			weld.Part0, weld.Part1 = parent, p
			weld.Parent = p
		end
		p.Parent = mount
		return p
	end
	local leather = Color3.fromRGB(70, 45, 28)
	if fly then
		local feather, gold = Color3.fromRGB(230, 232, 240), Color3.fromRGB(214, 170, 70)
		local body = part("Body", Vector3.new(2.4, 2, 5.5), CFrame.new(0, -2.6, 0.3), feather, root)
		part("Saddle", Vector3.new(2.6, 0.5, 2.2), CFrame.new(0, -1.5, 0), leather, body)
		part("Neck", Vector3.new(1.4, 2.2, 1.4), CFrame.new(0, -1.3, -2.8) * CFrame.Angles(math.rad(-25), 0, 0), feather, body)
		part("Head", Vector3.new(1.3, 1.2, 1.8), CFrame.new(0, -0.3, -3.9), feather, body)
		part("Beak", Vector3.new(0.5, 0.5, 0.9), CFrame.new(0, -0.5, -5.1), gold, body)
		part("Tail", Vector3.new(1.6, 0.3, 2.2), CFrame.new(0, -2.4, 3.9), feather, body)
		for _, side in { -1, 1 } do
			local wing = part("Wing", Vector3.new(5, 0.3, 3), CFrame.new(side * 3.6, -1.6, 0) * CFrame.Angles(0, 0, side * math.rad(18)), feather, body,
				{ kind = "wing", side = side, pivot = CFrame.new(side * 1.2, -1.6, 0) })
			part("WingTip", Vector3.new(2.4, 0.25, 2), CFrame.new(side * 7, -0.6, 0.3) * CFrame.Angles(0, 0, side * math.rad(32)), feather, wing)
			for i, z in { -1.8, 1.8 } do
				part("Leg", Vector3.new(0.6, 2.4, 0.6), CFrame.new(side * 0.8, -4.7, z), gold, body,
					{ kind = "leg", side = side, phase = if (i == 1) == (side == 1) then 0 else math.pi, pivot = CFrame.new(side * 0.8, -3.6, z) })
			end
		end
	else
		local brown, dark = Color3.fromRGB(96, 62, 36), Color3.fromRGB(40, 28, 18)
		local body = part("Body", Vector3.new(2.2, 2, 5), CFrame.new(0, -2.6, 0), brown, root)
		part("Saddle", Vector3.new(2.4, 0.5, 2), CFrame.new(0, -1.5, 0), leather, body)
		part("Neck", Vector3.new(1.2, 2.4, 1.2), CFrame.new(0, -1.4, -2.8) * CFrame.Angles(math.rad(-30), 0, 0), brown, body)
		part("Head", Vector3.new(1.1, 1.1, 2), CFrame.new(0, -0.4, -3.9), brown, body)
		part("Mane", Vector3.new(0.4, 1.6, 1.6), CFrame.new(0, -0.8, -2.6), dark, body)
		part("Tail", Vector3.new(0.5, 2, 0.5), CFrame.new(0, -3, 2.8) * CFrame.Angles(math.rad(25), 0, 0), dark, body)
		for _, x in { -0.75, 0.75 } do
			for i, z in { -1.8, 1.8 } do
				part("Leg", Vector3.new(0.6, 2.6, 0.6), CFrame.new(x, -4.8, z), dark, body,
					{ kind = "leg", side = if x < 0 then -1 else 1, phase = if (i == 1) == (x > 0) then 0 else math.pi, pivot = CFrame.new(x, -3.6, z) })
			end
		end
	end
	mount.Parent = character
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
