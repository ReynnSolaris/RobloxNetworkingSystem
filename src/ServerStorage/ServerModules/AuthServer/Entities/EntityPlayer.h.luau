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
	char.Level = char.Level or 1
	char.Xp = char.Xp or 0
	player:SetAttribute("CharacterName", char.Name)
	player:SetAttribute("CharacterClass", char.Class)
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

-- Level plus equipment. Max health keeps its fraction when it changes.
function module:Stats(player: Player)
	local entity = self.information[player]
	return entity and entity.Stats or { Health = 100, Damage = 0, Armor = 0 }
end

function module:ApplyStats(player: Player)
	local entity = self.information[player]
	local char = entity and entity.Active
	if not char then
		return
	end
	local DB = self.includes.Database["WorldDB.h"]
	local stats = { Health = Config.Xp.HealthForLevel(char.Level or 1), Damage = 0, Armor = 0 }
	for _, entry in (char.Equipment or {}) do
		local item = DB:Get("item_template", entry)
		if item then
			stats.Health += item.health or 0
			stats.Damage += item.damage or 0
			stats.Armor += item.armor or 0
		end
	end
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
end

-- Adds experience, levelling as many times as it takes. reason is shown to the player.
function module:GrantXp(player: Player, amount: number, reason: string?)
	local entity = self.information[player]
	local char = entity and entity.Active
	if not char or amount <= 0 or char.Level >= Config.Xp.MaxLevel then
		return
	end
	char.Xp += math.floor(amount)
	self.includes.Security["Packet.h"]:Send(player, Opcodes.SMSG_XP_GAIN, { Amount = math.floor(amount), Reason = reason })
	while char.Level < Config.Xp.MaxLevel and char.Xp >= Config.Xp.ForLevel(char.Level) do
		char.Xp -= Config.Xp.ForLevel(char.Level)
		char.Level += 1
		self:ApplyStats(player)
		self.includes.Security["Packet.h"]:Send(player, Opcodes.SMSG_LEVELUP, { Level = char.Level })
		self.includes.System["Effects.h"]:Play("LevelUp", player, 40)
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
end

-- The bag: a list of stacks { slot, entry, count }, one per occupied slot out of
-- Config.BagSlots. Stacks merge up to the template's stack size, then the first
-- free slot is used; a full bag refuses, WoW style.

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

local function freeSlot(items): number?
	for slot = 1, Config.BagSlots do
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
	local free = 0
	for slot = 1, Config.BagSlots do
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
		table.insert(items, { slot = freeSlot(items), entry = entry, count = add })
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
	if not char or from == to or from < 1 or to < 1 or from > Config.BagSlots or to > Config.BagSlots then
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
	local previous = char.Equipment[item.slot]
	stack.count -= 1
	if stack.count == 0 then
		table.remove(items, table.find(items, stack))
	end
	char.Equipment[item.slot] = stack.entry
	if previous then
		table.insert(items, { slot = freeSlot(items) or slot, entry = previous, count = 1 })
	end
	self:SendInventory(player, false)
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
	local free = if toSlot and toSlot >= 1 and toSlot <= Config.BagSlots and not stackAt(items, toSlot) then toSlot else freeSlot(items)
	if not free then
		self:System(player, "Inventory is full.")
		return false
	end
	char.Equipment[slotName] = nil
	table.insert(items, { slot = free, entry = entry, count = 1 })
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
	local DB = self.includes.Database["WorldDB.h"]
	local slots = {}
	for slot, entry in (char.Equipment or {}) do
		local item = DB:Get("item_template", entry) or {}
		slots[slot] = { Entry = entry, Name = item.name or "?", Quality = item.quality or 1, Slot = slot, Class = item.class,
			Level = item.level, Health = item.health, Damage = item.damage, Armor = item.armor }
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
end

-- announce: print the list in chat (the /inv request); otherwise it is a silent refresh.
function module:SendInventory(player: Player, announce: boolean?)
	local char = self.information[player] and self.information[player].Active
	local DB = self.includes.Database["WorldDB.h"]
	local items = {}
	for _, stack in (char and bag(char) or {}) do
		local template = DB:Get("item_template", stack.entry) or {}
		table.insert(items, { Bag = stack.slot, Entry = stack.entry, Name = template.name or "?", Quality = template.quality or 1, Count = stack.count,
			Slot = template.slot, Class = template.class, Sell = template.sellprice or math.floor((template.buyprice or 0) / 4), Level = template.level,
			Health = template.health, Damage = template.damage, Armor = template.armor })
	end
	self.includes.Security["Packet.h"]:Send(player, Opcodes.SMSG_INVENTORY, { Items = items, Money = char and char.Money or 0, Bags = Config.BagSlots, Announce = announce == true })
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

-- Timed multiplier on WalkSpeed ("speed") or JumpPower ("jump"); < 1 is a debuff.
local BUFFS = { speed = { "WalkSpeed", 16 }, jump = { "JumpPower", 50 } }
module.BUFFS = BUFFS

function module:Buff(player: Player, effect: string, mult: number, seconds: number): boolean
	local spec = BUFFS[effect]
	local entity = self.information[player]
	local humanoid = humanoidOf(entity)
	if not spec or not humanoid then
		return false
	end
	local property, base = spec[1], spec[2]
	entity.Buffs = entity.Buffs or {}
	entity.Buffs[effect] = (entity.Buffs[effect] or 0) + 1
	local token = entity.Buffs[effect]
	humanoid[property] = base * mult
	task.delay(seconds, function()
		if self.information[player] == entity and entity.Buffs[effect] == token then
			local h = humanoidOf(entity)
			if h then
				h[property] = base
			end
		end
	end)
	return true
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
	{ Path = "World/Spells", Imports = "Spells.h" },
	{ Path = "Global/System", Imports = "Effects.h" },
})
