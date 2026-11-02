local Base = require(game:GetService("ServerStorage").ServerModules["Template.h"])
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Opcodes = require(ReplicatedStorage.Shared.Opcodes)
local Config = require(ReplicatedStorage.Shared.Config)
local module = {}

-- Damage and healing between units. A unit is a Player or a creature state
-- (the table Creatures keeps per spawn). Melee: the client picks a target
-- (CMSG_SET_TARGET) and toggles auto-attack (CMSG_ATTACK); the server swings on
-- its own timer. Spells and auras land through Damage and Heal so every path
-- logs the same way, aggros creatures and respects duels.

local EFFECT = { physical = "Hit", holy = "Holy", fire = "Fire", nature = "Nature", frost = "Frost", shadow = "Shadow", arcane = "Arcane" }
module.EFFECT = EFFECT

function module:Log(player: Player, text: string, color: string?)
	self.includes.Security["Packet.h"]:Send(player, Opcodes.SMSG_COMBAT_LOG, { Text = text, Color = color })
end

function module:IsPlayer(unit): boolean
	return typeof(unit) == "Instance" and unit:IsA("Player")
end

function module:Humanoid(unit): Humanoid?
	if self:IsPlayer(unit) then
		return unit.Character and unit.Character:FindFirstChildOfClass("Humanoid")
	end
	return unit and unit.Humanoid
end

function module:Root(unit): BasePart?
	if self:IsPlayer(unit) then
		return unit.Character and unit.Character:FindFirstChild("HumanoidRootPart")
	end
	return unit and unit.Root
end

function module:Name(unit): string
	if self:IsPlayer(unit) then
		return unit:GetAttribute("CharacterName") or unit.Name
	end
	return unit and unit.Template and unit.Template.name or "?"
end

function module:Alive(unit): boolean
	local humanoid = self:Humanoid(unit)
	if not humanoid or humanoid.Health <= 0 then
		return false
	end
	if self:IsPlayer(unit) then
		local entity = self.includes.Entities["EntityPlayer.h"]:Get(unit)
		return entity ~= nil and entity.Active ~= nil and not entity.Ghost
	end
	return not unit.Dead and unit.Model.Parent ~= nil
end

-- Effect target for Effects:Play: player, creature guid.
local function effectTarget(self, unit)
	return if self:IsPlayer(unit) then unit else unit.Row.guid
end

-- Entering combat flags the player for Config.Combat.LeaveCombatSeconds.
function module:Enter(unit)
	if self:IsPlayer(unit) then
		local s = self:State(unit)
		s.CombatUntil = os.clock() + Config.Combat.LeaveCombatSeconds
		if unit:GetAttribute("InCombat") ~= true then
			unit:SetAttribute("InCombat", true)
		end
	end
end

function module:InCombat(player: Player): boolean
	local s = self.information[player]
	return s ~= nil and (s.CombatUntil or 0) > os.clock()
end

-- May `attacker` hurt `target` right now? Creatures hurt players; players hurt
-- hostile creatures, duel opponents and enemy-faction players in PvP zones.
function module:CanAttack(attacker, target): (boolean, string?)
	if attacker == target or not self:Alive(target) then
		return false, "Invalid target."
	end
	if not self:IsPlayer(attacker) then
		return self:IsPlayer(target), "Invalid target."
	end
	if self:IsPlayer(target) then
		if self.includes.Combat["Duel.h"]:Opponent(attacker) == target then
			return true
		end
		if self.includes.Combat["Pvp.h"]:Hostile(attacker, target) then
			return true
		end
		return false, "You cannot attack that target."
	end
	return target.Hostile == true, "Invalid target."
end

-- Deals damage. source is "Your Fireball" or a creature's spell name; the log
-- lines read like WoW's. Returns the damage dealt.
function module:Damage(attacker, target, amount: number, school: string?, source: string?): number
	local humanoid = self:Humanoid(target)
	if not humanoid or not self:Alive(target) then
		return 0
	end
	local Entities = self.includes.Entities["EntityPlayer.h"]
	local Effects = self.includes.System["Effects.h"]
	local Duel = self.includes.Combat["Duel.h"]
	source = source or "attack"
	if self:IsPlayer(target) then
		self.includes.Spells["Auras.h"]:RemoveKind(target, "mount")
		if attacker and self:IsPlayer(attacker) and Duel:Opponent(attacker) == target then
			return Duel:Hit(attacker, target, amount, source)
		end
		if (school or "physical") == "physical" then
			amount = math.max(1, amount - Entities:Stats(target).Armor)
		end
		amount = math.min(amount, math.floor(humanoid.Health))
		humanoid:TakeDamage(amount)
		Effects:Play(EFFECT[school or "physical"] or "Hit", target, 6)
		self:Enter(target)
		local who = if attacker then self:Name(attacker) else "Something"
		self:Log(target, ("%s's %s hits you for %d."):format(who, (source:gsub("^Your ", "")), amount), Config.Chat.Colors.HURT)
		if attacker and self:IsPlayer(attacker) then
			self:Enter(attacker)
			self:Log(attacker, ("%s hits %s for %d."):format(source, self:Name(target), amount), Config.Chat.Colors.HIT)
			if humanoid.Health <= 0 then
				self.includes.Combat["Pvp.h"]:OnKill(attacker, target)
			end
		end
		return amount
	end
	amount = math.min(amount, math.floor(humanoid.Health))
	humanoid:TakeDamage(amount)
	Effects:Play(EFFECT[school or "physical"] or "Hit", target.Row.guid, 8)
	if attacker and self:IsPlayer(attacker) then
		self.includes.Content["Creatures.h"]:Aggro(target.Row.guid, attacker)
		self:Enter(attacker)
		self:Log(attacker, ("%s hits %s for %d."):format(source, self:Name(target), amount), Config.Chat.Colors.HIT)
	end
	return amount
end

function module:Heal(healer, target, amount: number, source: string?): number
	local humanoid = self:Humanoid(target)
	if not humanoid or not self:Alive(target) then
		return 0
	end
	amount = math.min(math.floor(amount), math.max(0, math.floor(humanoid.MaxHealth - humanoid.Health)))
	humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + amount)
	if amount <= 0 then
		return 0
	end
	self.includes.System["Effects.h"]:Play("Heal", effectTarget(self, target), 12)
	if healer and self:IsPlayer(healer) then
		local who = if healer == target then "you" else self:Name(target)
		self:Log(healer, ("%s heals %s for %d."):format(source or "Your spell", who, amount), Config.Chat.Colors.LOOT)
	end
	if self:IsPlayer(target) and target ~= healer then
		self:Log(target, ("%s's %s heals you for %d."):format(if healer then self:Name(healer) else "Something", ((source or "spell"):gsub("^Your ", "")), amount), Config.Chat.Colors.LOOT)
	end
	return amount
end

function module:State(player: Player)
	local s = self.information[player]
	if not s then
		s = { Target = nil, TargetPlayer = nil, Attacking = false, NextSwing = 0, CombatUntil = 0 }
		self.information[player] = s
	end
	return s
end

-- The unit a player has targeted: a creature state or another player.
function module:Target(player: Player)
	local s = self.information[player]
	if not s then
		return nil
	end
	if s.Target then
		return self.includes.Content["Creatures.h"]:State(s.Target)
	elseif s.TargetPlayer then
		local other = self.includes.Entities["EntityPlayer.h"]:FindByName(s.TargetPlayer)
		return if other ~= player then other else nil
	end
	return nil
end

function module:Swing(player: Player, state)
	local target = self:Target(player)
	local Auras = self.includes.Spells["Auras.h"]
	if not target or not self:CanAttack(player, target) then
		state.Attacking = false
		return
	end
	if not self:Alive(player) or Auras:Has(player, "stun") then
		state.Attacking = false
		return
	end
	local root, targetRoot = self:Root(player), self:Root(target)
	if not root or not targetRoot or (root.Position - targetRoot.Position).Magnitude > Config.Combat.Range then
		return
	end
	if os.clock() < state.NextSwing then
		return
	end
	state.NextSwing = os.clock() + Config.Combat.SwingSeconds
	local Entities = self.includes.Entities["EntityPlayer.h"]
	local level = player:GetAttribute("CharacterLevel") or 1
	local stats = Entities:Stats(player)
	local roll = self:Roll(player, target)
	if roll == "miss" or roll == "dodge" then
		self:Log(player, ("Your attack %s %s."):format(if roll == "miss" then "misses" else "was dodged by", self:Name(target)), Config.Chat.Colors.HIT)
		if self:IsPlayer(target) then
			self:Log(target, ("%s's attack %s."):format(self:Name(player), if roll == "miss" then "misses you" else "was dodged"), Config.Chat.Colors.HURT)
		end
		return
	end
	local damage = math.round((Config.Combat.Damage(level) + stats.Damage) * (0.8 + math.random() * 0.4))
	if roll == "crit" then
		damage *= 2
	end
	self:Damage(player, target, math.max(1, damage), "physical", if roll == "crit" then "Your attack crits" else "Your attack")
end

-- Attack roll: miss, dodge, crit or hit. Agility raises crit and dodge.
function module:Roll(attacker, target): string
	local Entities = self.includes.Entities["EntityPlayer.h"]
	local crit = if self:IsPlayer(attacker) then Entities:Stats(attacker).Crit or 5 else 5
	local dodge = if self:IsPlayer(target) then Entities:Stats(target).Dodge or 5 else 5
	local r = math.random() * 100
	if r < 5 then
		return "miss"
	elseif r < 5 + dodge then
		return "dodge"
	elseif r < 5 + dodge + crit then
		return "crit"
	end
	return "hit"
end

function module:Start()
	local Packet = self.includes.Security["Packet.h"]
	Packet:On(Opcodes.CMSG_SET_TARGET, function(player, data)
		local s = self:State(player)
		s.Target = if typeof(data) == "table" and data.Guid ~= nil then tostring(data.Guid) else nil
		s.TargetPlayer = if typeof(data) == "table" and typeof(data.Player) == "string" then data.Player else nil
		s.Attacking = false
	end)
	Packet:On(Opcodes.CMSG_ATTACK, function(player, data)
		local s = self:State(player)
		s.Attacking = typeof(data) == "table" and data.On == true and (s.Target ~= nil or s.TargetPlayer ~= nil)
	end)
	Players.PlayerRemoving:Connect(function(player)
		self.information[player] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(0.1)
			for player, s in self.information do
				if s.Attacking then
					self:Swing(player, s)
				end
				if (s.CombatUntil or 0) <= os.clock() and player:GetAttribute("InCombat") then
					player:SetAttribute("InCombat", nil)
				end
			end
		end
	end)
end

return Base(module, {
	{ Path = "Auth/Security", Imports = "Packet.h" },
	{ Path = "World/Content", Imports = "Creatures.h" },
	{ Path = "World/Combat", Imports = "Duel.h|Pvp.h" },
	{ Path = "World/Spells", Imports = "Auras.h" },
	{ Path = "Auth/Entities", Imports = "EntityPlayer.h" },
	{ Path = "Global/System", Imports = "Effects.h" },
})
