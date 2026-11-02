local Base = require(game:GetService("ServerStorage").ServerModules["Template.h"])
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Opcodes = require(ReplicatedStorage.Shared.Opcodes)
local Config = require(ReplicatedStorage.Shared.Config)
local module = {}

-- Player melee. The client picks a target (CMSG_SET_TARGET) and toggles
-- auto-attack (CMSG_ATTACK); the server swings on its own timer when the target
-- is a living hostile creature in range. Everything is logged to the client.

function module:Log(player: Player, text: string, color: string?)
	self.includes.Security["Packet.h"]:Send(player, Opcodes.SMSG_COMBAT_LOG, { Text = text, Color = color })
end

function module:Swing(player: Player, state)
	local Creatures = self.includes.Content["Creatures.h"]
	local Duel = self.includes.Combat["Duel.h"]
	local creature = state.Target and Creatures:State(state.Target)
	local opponent = state.TargetPlayer and Duel:Opponent(player)
	if opponent and (opponent:GetAttribute("CharacterName") or opponent.Name) ~= state.TargetPlayer then
		opponent = nil
	end
	if (not creature or creature.Dead or not creature.Hostile) and not opponent then
		state.Attacking = false
		return
	end
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	local entity = self.includes.Entities["EntityPlayer.h"]:Get(player)
	if not root or not humanoid or humanoid.Health <= 0 or (entity and entity.Ghost) then
		state.Attacking = false
		return
	end
	local targetRoot = if opponent then opponent.Character and opponent.Character:FindFirstChild("HumanoidRootPart") else creature.Root
	if not targetRoot or (root.Position - targetRoot.Position).Magnitude > Config.Combat.Range then
		return
	end
	if os.clock() < state.NextSwing then
		return
	end
	state.NextSwing = os.clock() + Config.Combat.SwingSeconds
	local level = player:GetAttribute("CharacterLevel") or 1
	local bonus = self.includes.Entities["EntityPlayer.h"]:Stats(player).Damage
	local damage = math.max(1, math.round((Config.Combat.Damage(level) + bonus) * (0.8 + math.random() * 0.4)))
	if opponent then
		Duel:Hit(player, opponent, damage, "Your attack")
		return
	end
	creature.Humanoid:TakeDamage(damage)
	self.includes.System["Effects.h"]:Play("Hit", state.Target, 6)
	Creatures:Aggro(state.Target, player)
	self:Log(player, ("Your attack hits %s for %d."):format(creature.Template.name, damage), Config.Chat.Colors.HIT)
end

function module:Start()
	local Packet = self.includes.Security["Packet.h"]
	local function state(player: Player)
		local s = self.information[player]
		if not s then
			s = { Target = nil, Attacking = false, NextSwing = 0 }
			self.information[player] = s
		end
		return s
	end
	Packet:On(Opcodes.CMSG_SET_TARGET, function(player, data)
		local s = state(player)
		s.Target = if typeof(data) == "table" and data.Guid ~= nil then tostring(data.Guid) else nil
		s.TargetPlayer = if typeof(data) == "table" and typeof(data.Player) == "string" then data.Player else nil
		s.Attacking = false
	end)
	Packet:On(Opcodes.CMSG_ATTACK, function(player, data)
		local s = state(player)
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
			end
		end
	end)
end

return Base(module, {
	{ Path = "Auth/Security", Imports = "Packet.h" },
	{ Path = "World/Content", Imports = "Creatures.h" },
	{ Path = "World/Combat", Imports = "Duel.h" },
	{ Path = "Auth/Entities", Imports = "EntityPlayer.h" },
	{ Path = "Global/System", Imports = "Effects.h" },
})
