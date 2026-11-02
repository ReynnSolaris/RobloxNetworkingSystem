local Base = require(game:GetService("ServerStorage").ServerModules["Template.h"])
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Opcodes = require(ReplicatedStorage.Shared.Opcodes)
local Config = require(ReplicatedStorage.Shared.Config)
local module = {}

-- Pets. A pet is a creature state spawned from a creature_template with no
-- database row and an Owner; the brain follows the owner, attacks what the
-- owner attacks or what attacks the owner, and leashes back. Hunters tame a
-- beast (Tame Beast) and call it back (Call Pet); warlocks summon an Imp. The
-- character keeps Pet = { Entry, Name }. information[owner] = pet state.

function module:Of(owner: Player)
	local pet = self.information[owner]
	return if pet and not pet.Dead and pet.Model.Parent then pet else nil
end

local function char(self, player: Player)
	local entity = self.includes.Entities["EntityPlayer.h"]:Get(player)
	return entity and entity.Active
end

function module:Sync(owner: Player)
	local pet = self:Of(owner)
	owner:SetAttribute("PetGuid", pet and pet.Row.guid or nil)
	owner:SetAttribute("PetMode", pet and pet.Mode or nil)
end

-- Spawns the pet beside its owner.
function module:Summon(owner: Player, entry, name: string?): boolean
	local Creatures = self.includes.Content["Creatures.h"]
	local Combat = self.includes.Combat["Combat.h"]
	local root = Combat:Root(owner)
	local template = Creatures:Template(entry)
	if not root or not template then
		return false
	end
	self:Dismiss(owner, true)
	local level = owner:GetAttribute("CharacterLevel") or 1
	local at = root.CFrame * CFrame.new(3, 0, 2)
	local state = Creatures:SpawnPet(template, at, owner, level, name)
	if not state then
		return false
	end
	self.information[owner] = state
	self:Sync(owner)
	return true
end

function module:Dismiss(owner: Player, quiet: boolean?)
	local pet = self.information[owner]
	self.information[owner] = nil
	if pet then
		self.includes.Content["Creatures.h"]:Despawn(pet.Row.guid)
		if not quiet then
			self.includes.Chat["Chat.h"]:System(owner, ("%s has been dismissed."):format(pet.Model.Name))
		end
	end
	self:Sync(owner)
end

-- A tamed beast becomes the character's pet.
function module:Tame(owner: Player, creature): boolean
	local c = char(self, owner)
	if not c then
		return false
	end
	c.Pet = { Entry = creature.Row.id, Name = creature.Template.name }
	c.PetDiedAt = nil
	self.includes.Database["WorldDatabase.h"]:Commit(owner)
	self.includes.Content["Creatures.h"]:Despawn(creature.Row.guid)
	task.delay(creature.Row.spawntimesecs or Config.Combat.DefaultRespawn, function()
		local Creatures = self.includes.Content["Creatures.h"]
		local row = Creatures:DB():Get("creature", creature.Row.guid)
		if row and not Creatures:State(row.guid) then
			Creatures:Spawn(row)
		end
	end)
	self.includes.Chat["Chat.h"]:System(owner, ("You have tamed %s."):format(creature.Template.name))
	return self:Summon(owner, creature.Row.id, creature.Template.name)
end

function module:Call(owner: Player): boolean
	local c = char(self, owner)
	if not c or not c.Pet then
		self.includes.Chat["Chat.h"]:System(owner, "You have no pet to call.")
		return false
	end
	if c.PetDiedAt and os.time() - c.PetDiedAt < Config.Pets.ResummonSeconds then
		self.includes.Chat["Chat.h"]:System(owner, "Your pet is still recovering.")
		return false
	end
	return self:Summon(owner, c.Pet.Entry, c.Pet.Name)
end

function module:OnPetDeath(state)
	local owner = state.Owner
	if self.information[owner] == state then
		self.information[owner] = nil
	end
	local c = owner and char(self, owner)
	if c then
		c.PetDiedAt = os.time()
	end
	if owner and owner.Parent == Players then
		self.includes.Chat["Chat.h"]:System(owner, ("Your pet %s has died."):format(state.Model.Name))
		self:Sync(owner)
	end
end

-- The owner attacked or was attacked: the pet joins in unless passive.
function module:Assist(owner: Player, target)
	local pet = self:Of(owner)
	if pet and pet.Mode ~= "passive" and target ~= pet then
		pet.Target = target
	end
end

function module:Command(owner: Player, action: string)
	local pet = self:Of(owner)
	if action == "dismiss" then
		return self:Dismiss(owner)
	end
	if not pet then
		return
	end
	if action == "attack" then
		local target = self.includes.Combat["Combat.h"]:Target(owner)
		if target and self.includes.Combat["Combat.h"]:CanAttack(pet, target) then
			pet.Mode = "defensive"
			pet.Target = target
		end
	elseif action == "follow" then
		pet.Target = nil
		pet.Mode = "defensive"
	elseif action == "passive" then
		pet.Target = nil
		pet.Mode = "passive"
	elseif action == "aggressive" or action == "defensive" then
		pet.Mode = action
	end
	self:Sync(owner)
end

-- One brain step, called by Creatures for a state with an Owner.
function module:Think(state)
	local Combat = self.includes.Combat["Combat.h"]
	local owner = state.Owner
	local humanoid, here = state.Humanoid, state.Root.Position
	if not owner or owner.Parent ~= Players then
		return self.includes.Content["Creatures.h"]:Despawn(state.Row.guid)
	end
	local oroot = Combat:Root(owner)
	if not oroot or not Combat:Alive(owner) then
		return self:Dismiss(owner, true)
	end
	local fromOwner = (oroot.Position - here).Magnitude
	if fromOwner > Config.Pets.LeashDistance then
		state.Target = nil
		state.Model:PivotTo(oroot.CFrame * CFrame.new(3, 0, 2))
		return
	end
	local target = state.Target
	if target and (not Combat:Alive(target) or not Combat:CanAttack(state, target)) then
		state.Target = nil
		target = nil
	end
	if not target and state.Mode == "aggressive" then
		for _, other in self.includes.Content["Creatures.h"].information do
			if other.Hostile and not other.Dead and not other.Owner and (other.Root.Position - here).Magnitude < 15 then
				target = other
				state.Target = other
				break
			end
		end
	end
	if not target then
		if fromOwner > Config.Pets.FollowDistance + 1 then
			humanoid:MoveTo(oroot.Position + (here - oroot.Position).Unit * Config.Pets.FollowDistance)
		else
			humanoid:MoveTo(here)
		end
		if humanoid.Health < humanoid.MaxHealth then
			humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + humanoid.MaxHealth * 0.02)
		end
		return
	end
	local troot = Combat:Root(target)
	if not troot then
		return
	end
	local distance = (troot.Position - here).Magnitude
	if distance > Config.Combat.Range then
		humanoid:MoveTo(troot.Position)
	else
		humanoid:MoveTo(here)
		if os.clock() >= state.NextSwing then
			state.NextSwing = os.clock() + Config.Combat.SwingSeconds
			state.Model:SetAttribute("Swing", os.clock())
			local template = state.Template
			local scale = 1 + 0.1 * ((state.Level or 1) - 1)
			local damage = math.round(math.random(template.dmgmin or 1, math.max(template.dmgmax or 1, template.dmgmin or 1)) * scale)
			Combat:Damage(state, target, math.max(1, damage), "physical", "attack")
		end
	end
end

function module:OnLogout(owner: Player)
	self:Dismiss(owner, true)
end

function module:Start()
	local Packet = self.includes.Security["Packet.h"]
	Packet:On(Opcodes.CMSG_PET_ACTION, function(player, data)
		if typeof(data) == "table" and typeof(data.Action) == "string" then
			self:Command(player, data.Action)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		self:Dismiss(player, true)
	end)
end

return Base(module, {
	{ Path = "Auth/Security", Imports = "Packet.h" },
	{ Path = "Auth/Entities", Imports = "EntityPlayer.h" },
	{ Path = "Auth/Chat", Imports = "Chat.h" },
	{ Path = "World/Content", Imports = "Creatures.h" },
	{ Path = "World/Combat", Imports = "Combat.h" },
	{ Path = "World/Database", Imports = "WorldDatabase.h" },
})
