local Base = require(game:GetService("ServerStorage").ServerModules["Template.h"])
local InsertService = game:GetService("InsertService")
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

-- Max health follows level; current health keeps its fraction.
local function applyLevelHealth(humanoid: Humanoid, level: number)
	local fraction = if humanoid.MaxHealth > 0 then humanoid.Health / humanoid.MaxHealth else 1
	humanoid.MaxHealth = Config.Xp.HealthForLevel(level)
	humanoid.Health = math.max(1, humanoid.MaxHealth * fraction)
end

function module:SetLevel(player: Player, level: number)
	local entity = self.information[player]
	local char = entity and entity.Active
	if not char then
		return
	end
	char.Level = math.clamp(level, 1, Config.Xp.MaxLevel)
	char.Xp = 0
	local humanoid = humanoidOf(entity)
	if humanoid then
		applyLevelHealth(humanoid, char.Level)
	end
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
		local humanoid = humanoidOf(entity)
		if humanoid then
			applyLevelHealth(humanoid, char.Level)
		end
		self.includes.Security["Packet.h"]:Send(player, Opcodes.SMSG_LEVELUP, { Level = char.Level })
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

-- Inventory is a list of { entry, count }; stacks merge up to the template's stack size.
function module:AddItem(player: Player, entry: number, count: number): boolean
	local char = self.information[player] and self.information[player].Active
	local template = self.includes.Database["WorldDB.h"]:Get("item_template", entry)
	if not char or not template or count <= 0 then
		return false
	end
	char.Inventory = char.Inventory or {}
	local left = count
	for _, stack in char.Inventory do
		if stack.entry == entry and stack.count < (template.stack or 1) then
			local room = (template.stack or 1) - stack.count
			local add = math.min(room, left)
			stack.count += add
			left -= add
		end
	end
	while left > 0 do
		local add = math.min(template.stack or 1, left)
		table.insert(char.Inventory, { entry = entry, count = add })
		left -= add
	end
	self.includes.Security["Packet.h"]:Send(player, Opcodes.SMSG_ITEM_PUSH,
		{ Entry = entry, Name = template.name, Quality = template.quality or 1, Count = count })
	return true
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

function module:SendInventory(player: Player)
	local char = self.information[player] and self.information[player].Active
	local DB = self.includes.Database["WorldDB.h"]
	local items = {}
	for _, stack in (char and char.Inventory or {}) do
		local template = DB:Get("item_template", stack.entry) or {}
		table.insert(items, { Entry = stack.entry, Name = template.name or "?", Quality = template.quality or 1, Count = stack.count })
	end
	self.includes.Security["Packet.h"]:Send(player, Opcodes.SMSG_INVENTORY, { Items = items, Money = char and char.Money or 0 })
end

function module:Get(player: Player)
	return self.information[player]
end

-- Spawns the active character at `at`, else at its saved position, else at Config.Spawn.
function module:Spawn(player: Player, at: CFrame?)
	local entity = self.information[player]
	local saved = entity and entity.Active
	if not saved then
		return
	end
	local Packet = self.includes.Security["Packet.h"]
	at = at or (saved.Position and CFrame.new(table.unpack(saved.Position))) or Config.Spawn

	player:LoadCharacter()
	local character = player.Character or player.CharacterAdded:Wait()
	self.includes.Movement["Anticheat.h"]:Allow(player)
	character:PivotTo(at)
	entity.Character = character

	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	humanoid.DisplayName = saved.Name
	humanoid.MaxHealth = Config.Xp.HealthForLevel(saved.Level or 1)
	humanoid.Health = humanoid.MaxHealth
	if saved.Health then
		humanoid.Health = math.clamp(saved.Health, 1, humanoid.MaxHealth)
		saved.Health = nil
	end

	humanoid.HealthChanged:Connect(function(health)
		Packet:Send(player, Opcodes.SMSG_HEALTH_UPDATE, { Health = health, MaxHealth = humanoid.MaxHealth })
	end)
	humanoid.Died:Once(function()
		Packet:Send(player, Opcodes.SMSG_DESPAWN, {})
		task.delay(Config.RespawnDelay, function()
			local e = self.information[player]
			if e and e.Active == saved and e.Character == character then
				self:Spawn(player, Config.Spawn)
			end
		end)
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
	if entity and entity.Active and humanoid and humanoid.Health > 0 then
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
})
