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

local function marker(player: Player, at: CFrame): BasePart
	local part = Instance.new("Part")
	part.Name = "Corpse of " .. (player:GetAttribute("CharacterName") or player.Name)
	part.Size = Vector3.new(2, 0.6, 3)
	part.Anchored = true
	part.CanCollide = false
	part.Material = Enum.Material.Slate
	part.Color = Color3.fromRGB(70, 70, 78)
	part.CFrame = at * CFrame.new(0, -2, 0)
	part:SetAttribute("Owner", player.UserId)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Resurrect"
	prompt.ObjectText = part.Name
	prompt.MaxActivationDistance = Config.Combat.ReclaimRange
	prompt.RequiresLineOfSight = false
	prompt.Parent = part
	part.Parent = workspace
	return part
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
	local state = { At = at, Marker = nil, Ghost = false }
	self.information[player] = state
	remember(self, player, state)
	self.includes.System["Effects.h"]:Play("Smoke", player, 10)
	self.includes.Security["Packet.h"]:Send(player, Opcodes.SMSG_DEATH, {})
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
	if not state or state.Ghost then
		return
	end
	state.Ghost = true
	remember(self, player, state)
	state.Marker = marker(player, state.At)
	state.Marker.ProximityPrompt.Triggered:Connect(function(who)
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

function module:Start()
	local DB = self.includes.Database["WorldDB.h"]
	if #DB:Select("game_graveyard") == 0 then
		for _, row in SEED do
			DB:Insert("game_graveyard", table.clone(row))
		end
	end
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
	{ Path = "World/Combat", Imports = "Duel.h" },
	{ Path = "Auth/Security", Imports = "Packet.h" },
	{ Path = "Auth/Entities", Imports = "EntityPlayer.h" },
	{ Path = "Auth/Chat", Imports = "Chat.h" },
	{ Path = "World/Database", Imports = "WorldDB.h|WorldDatabase.h" },
	{ Path = "Global/System", Imports = "Effects.h" },
})
