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
		Saved = self.includes.Database["WorldDatabase.h"]:Load(player),
	}
end

function module:Get(player: Player)
	return self.information[player]
end

-- Spawns at `at`, else at the saved position, else at Config.Spawn.
function module:Spawn(player: Player, at: CFrame?)
	local entity = self.information[player]
	if not entity then
		return
	end
	local Packet = self.includes.Security["Packet.h"]
	local saved = entity.Saved
	at = at or (saved.Position and CFrame.new(table.unpack(saved.Position))) or Config.Spawn

	player:LoadCharacter()
	local character = player.Character or player.CharacterAdded:Wait()
	character:PivotTo(at)
	entity.Character = character

	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
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
			if self.information[player] then
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

function module:Save(player: Player)
	local entity = self.information[player]
	if entity then
		self.includes.Database["WorldDatabase.h"]:Save(player, entity.Character)
	end
end

function module:Remove(player: Player)
	local entity = self.information[player]
	self.information[player] = nil
	if entity then
		self.includes.Database["WorldDatabase.h"]:Save(player, entity.Character)
		self.includes.Database["WorldDatabase.h"]:Forget(player)
	end
end

return Base(module, {
	{ Path = "Auth/Security", Imports = "Packet.h|Session.h" },
	{ Path = "World/Database", Imports = "WorldDatabase.h" },
})
