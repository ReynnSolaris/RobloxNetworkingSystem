local Base = require(game:GetService("ServerStorage").ServerModules["Template.h"])
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Opcodes = require(ReplicatedStorage.Shared.Opcodes)
local Config = require(ReplicatedStorage.Shared.Config)
local module = {}

-- Player death, WoW style. Dying leaves a corpse marker and offers Release Spirit;
-- releasing spawns a ghost at the nearest game_graveyard row; standing near the
-- marker and reclaiming brings the character back with half health.

local SEED = {
	{ name = "Northshire Graveyard", x = 40, y = 5, z = 40, o = 0 },
	{ name = "GM Island Graveyard", x = -380, y = 5, z = -380, o = 0 },
}

-- The corpse is the body itself, cloned before the ghost spawns and laid on
-- the ground; a stone marker stands in when there is no body to clone.
local function marker(self, player: Player, at: CFrame, character: Model?): Instance
	local name = "Corpse of " .. (player:GetAttribute("CharacterName") or player.Name)
	local corpse, hitbox
	if character and character:FindFirstChild("HumanoidRootPart") then
		character.Archivable = true
		corpse = character:Clone()
		for _, child in corpse:GetDescendants() do
			if child:IsA("Humanoid") or child:IsA("LuaSourceContainer") or child:IsA("ProximityPrompt") or child:IsA("ParticleEmitter") or child.Name == "Mount" then
				child:Destroy()
			end
		end
		corpse:PivotTo(at)
		hitbox = self.includes.Content["Creatures.h"].LayDown(corpse)
	else
		corpse = Instance.new("Part")
		corpse.Size = Vector3.new(2, 0.6, 3)
		corpse.Anchored, corpse.CanCollide = true, false
		corpse.Material = Enum.Material.Slate
		corpse.Color = Color3.fromRGB(70, 70, 78)
		corpse.CFrame = at * CFrame.new(0, -2, 0)
		hitbox = corpse
	end
	corpse.Name = name
	corpse:SetAttribute("Owner", player.UserId)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Resurrect"
	prompt.ObjectText = name
	prompt.MaxActivationDistance = Config.Combat.ReclaimRange
	prompt.RequiresLineOfSight = false
	prompt.Parent = hitbox
	corpse.Parent = workspace
	return corpse
end

function module:Nearest(position: Vector3): CFrame
	local best, bestDistance = Config.Spawn, math.huge
	for _, row in self.includes.Database["WorldDB.h"]:Select("game_graveyard") do
		local at = self.includes.Database["WorldDB.h"].ToCFrame(row)
		local d = (at.Position - position).Magnitude
		if d < bestDistance then
			best, bestDistance = at, d
		end
	end
	return best
end

local function remember(self, player: Player, state)
	local entity = self.includes.Entities["EntityPlayer.h"]:Get(player)
	local char = entity and entity.Active
	if char then
		char.Dead = state ~= nil
		char.CorpseAt = if state then { state.At.X, state.At.Y, state.At.Z } else nil
		char.Released = state ~= nil and state.Ghost or nil
		self.includes.Database["WorldDatabase.h"]:Commit(player)
	end
end

-- Called by EntityPlayer when a character's humanoid dies.
function module:OnDeath(player: Player, at: CFrame)
	self.includes.Combat["Duel.h"]:Forfeit(player)
	if player.Character then
		local hitbox = self.includes.Content["Creatures.h"].LayDown(player.Character)
		hitbox.Name = "DeathHitbox"
	end
	local inBattleground = self.includes.Combat["Battleground.h"]:OnDeath(player)
	local state = { At = at, Marker = nil, Ghost = false, Battleground = inBattleground }
	self.information[player] = state
	if not inBattleground then
		remember(self, player, state)
	end
	self.includes.System["Effects.h"]:Play("Smoke", player, 10)
	self.includes.Security["Packet.h"]:Send(player, Opcodes.SMSG_DEATH, { Battleground = inBattleground, Seconds = Config.Battleground.RespawnSeconds })
end

-- A character that logged out dead comes back dead: released ones as a ghost at
-- the graveyard with their marker, unreleased ones at the Release Spirit prompt.
function module:Restore(player: Player): boolean
	local entity = self.includes.Entities["EntityPlayer.h"]:Get(player)
	local char = entity and entity.Active
	if not char or not char.Dead or not char.CorpseAt then
		return false
	end
	local state = { At = CFrame.new(table.unpack(char.CorpseAt)), Marker = nil, Ghost = false }
	self.information[player] = state
	if char.Released then
		self:Repop(player)
	else
		self.includes.Entities["EntityPlayer.h"]:Spawn(player, state.At)
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.Health = 0
		end
	end
	return true
end

function module:Repop(player: Player)
	local state = self.information[player]
	if not state or state.Ghost or state.Battleground then
		return
	end
	state.Ghost = true
	remember(self, player, state)
	state.Marker = marker(self, player, state.At, player.Character)
	state.Marker:FindFirstChildWhichIsA("ProximityPrompt", true).Triggered:Connect(function(who)
		if who == player then
			self:Reclaim(player)
		end
	end)
	player:SetAttribute("Ghost", true)
	local Entities = self.includes.Entities["EntityPlayer.h"]
	Entities:Spawn(player, self:Nearest(state.At.Position), true)
end

function module:Reclaim(player: Player)
	local state = self.information[player]
	if not state or not state.Ghost then
		return
	end
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not root or (root.Position - state.At.Position).Magnitude > Config.Combat.ReclaimRange then
		return self.includes.Chat["Chat.h"]:System(player, "You are too far from your corpse.")
	end
	self:Resurrect(player, state.At)
end

-- Full return to life at `at` (the corpse, or wherever a GM says).
function module:Resurrect(player: Player, at: CFrame?)
	local state = self.information[player]
	if state and state.Marker then
		state.Marker:Destroy()
	end
	self.information[player] = nil
	player:SetAttribute("Ghost", nil)
	remember(self, player, nil)
	local Entities = self.includes.Entities["EntityPlayer.h"]
	Entities:Spawn(player, at or (state and state.At) or nil)
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.Health = humanoid.MaxHealth / 2
	end
	self.includes.System["Effects.h"]:Play("Resurrect", player, 20)
end

function module:IsDead(player: Player): boolean
	return self.information[player] ~= nil
end

function module:CorpseAt(player: Player): CFrame?
	local state = self.information[player]
	return state and state.At
end

-- A resurrection spell offers; the dead player accepts within a minute and
-- returns where their corpse lies with half health.
function module:Offer(target: Player, caster: Player)
	local state = self.information[target]
	if not state then
		return
	end
	state.Offer = { From = caster, At = os.time() }
	self.includes.Security["Packet.h"]:Send(target, Opcodes.SMSG_RESURRECT_REQUEST, { From = caster:GetAttribute("CharacterName") or caster.Name })
	self.includes.Chat["Chat.h"]:System(caster, ("You offer to resurrect %s."):format(target:GetAttribute("CharacterName") or target.Name))
end

function module:Respond(player: Player, accept: boolean)
	local state = self.information[player]
	local offer = state and state.Offer
	if not offer then
		return
	end
	state.Offer = nil
	if not accept or os.time() - offer.At > 60 then
		if offer.From.Parent == Players then
			self.includes.Chat["Chat.h"]:System(offer.From, ("%s declines your resurrection."):format(player:GetAttribute("CharacterName") or player.Name))
		end
		return
	end
	self:Resurrect(player, state.At)
end

-- Drop the live state (the record keeps Dead); used on leave and logout.
function module:Forget(player: Player)
	local state = self.information[player]
	if state and state.Marker then
		state.Marker:Destroy()
	end
	self.information[player] = nil
	player:SetAttribute("Ghost", nil)
end

-- A spirit healer brings a ghost back at the graveyard: half health, a quarter
-- of durability gone, and resurrection sickness from SicknessLevel.
function module:SpiritHeal(player: Player, guid)
	local state = self.information[player]
	local creature = self.includes.Content["Creatures.h"]:State(guid)
	if not state or not state.Ghost or not creature or not creature.Template.spirithealer then
		return
	end
	local Entities = self.includes.Entities["EntityPlayer.h"]
	self:Resurrect(player, creature.Root.CFrame * CFrame.new(3, 0, 3))
	Entities:Wear(player, Config.SpiritHealer.DurabilityLoss)
	if (player:GetAttribute("CharacterLevel") or 1) >= Config.SpiritHealer.SicknessLevel then
		local spell = self.includes.Spells["Spells.h"]:ByName("Resurrection Sickness")
		if spell then
			self.includes.Spells["Auras.h"]:Apply(nil, player, spell, 0)
		end
	end
	self.includes.Chat["Chat.h"]:System(player, "The spirit healer returns you to life.")
end

-- Every graveyard gets a spirit healer standing by it.
function module:PlaceHealers()
	local Creatures = self.includes.Content["Creatures.h"]
	local template = Creatures:ByName("Spirit Healer")
	if not template then
		return
	end
	local DB = self.includes.Database["WorldDB.h"]
	local spawns = {}
	for _, row in DB:Select("creature") do
		if tostring(row.id) == tostring(template.entry) then
			table.insert(spawns, Vector3.new(row.x, row.y, row.z))
		end
	end
	for _, yard in DB:Select("game_graveyard") do
		local at = Vector3.new(yard.x, yard.y, yard.z)
		local placed = false
		for _, p in spawns do
			if (p - at).Magnitude < 15 then
				placed = true
			end
		end
		if not placed then
			local row = DB.ToRow(DB.ToCFrame(yard) * CFrame.new(4, 0, 0))
			row.id = template.entry
			Creatures:Spawn(DB:Insert("creature", row))
		end
	end
end

function module:Start()
	local DB = self.includes.Database["WorldDB.h"]
	if #DB:Select("game_graveyard") == 0 then
		for _, row in SEED do
			DB:Insert("game_graveyard", table.clone(row))
		end
	end
	self:PlaceHealers()
	local Packet = self.includes.Security["Packet.h"]
	Packet:On(Opcodes.CMSG_REPOP_REQUEST, function(player)
		self:Repop(player)
	end)
	Packet:On(Opcodes.CMSG_RECLAIM_CORPSE, function(player)
		self:Reclaim(player)
	end)
	Packet:On(Opcodes.CMSG_RESURRECT_RESPONSE, function(player, data)
		self:Respond(player, typeof(data) == "table" and data.Accept == true)
	end)
	Players.PlayerRemoving:Connect(function(player)
		self:Forget(player)
	end)
end

return Base(module, {
	{ Path = "World/Content", Imports = "Creatures.h" },
	{ Path = "World/Combat", Imports = "Battleground.h" },
	{ Path = "World/Spells", Imports = "Spells.h|Auras.h" },
	{ Path = "World/Combat", Imports = "Duel.h" },
	{ Path = "Auth/Security", Imports = "Packet.h" },
	{ Path = "Auth/Entities", Imports = "EntityPlayer.h" },
	{ Path = "Auth/Chat", Imports = "Chat.h" },
	{ Path = "World/Database", Imports = "WorldDB.h|WorldDatabase.h" },
	{ Path = "Global/System", Imports = "Effects.h" },
})
