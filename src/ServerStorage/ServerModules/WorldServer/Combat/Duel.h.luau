local Base = require(game:GetService("ServerStorage").ServerModules["Template.h"])
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Opcodes = require(ReplicatedStorage.Shared.Opcodes)
local Config = require(ReplicatedStorage.Shared.Config)
local module = {}

-- Duels: /duel <name> asks, the other accepts, three second countdown, then the
-- two may hit each other until one would drop below 1 health, who loses. Moving
-- FleeRange studs from the start flag forfeits. Nobody dies in a duel.

local requests: { [Player]: { From: Player, At: number } } = {}

local function nameOf(player: Player): string
	return player:GetAttribute("CharacterName") or player.Name
end

local function say(self, player: Player, text: string)
	self.includes.Chat["Chat.h"]:System(player, text)
end

function module:Opponent(player: Player): Player?
	local duel = self.information[player]
	return if duel and duel.Active then duel.Opponent else nil
end

local function update(self, player: Player, opponent: Player?)
	player:SetAttribute("DuelOpponent", opponent and nameOf(opponent))
	self.includes.Security["Packet.h"]:Send(player, Opcodes.SMSG_DUEL_UPDATE, { Opponent = opponent and nameOf(opponent) })
end

function module:Request(player: Player, name: string?)
	local Entities = self.includes.Entities["EntityPlayer.h"]
	local target = Entities:FindByName(name)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local troot = target and target.Character and target.Character:FindFirstChild("HumanoidRootPart")
	if not target or target == player or not troot or not root then
		return say(self, player, "No player named " .. tostring(name))
	end
	if self.information[player] or self.information[target] then
		return say(self, player, "Already in a duel.")
	end
	if (root.Position - troot.Position).Magnitude > Config.Duel.Range then
		return say(self, player, "Target is too far away.")
	end
	requests[target] = { From = player, At = os.time() }
	self.includes.Security["Packet.h"]:Send(target, Opcodes.SMSG_DUEL_REQUESTED, { From = nameOf(player) })
	say(self, player, ("You have challenged %s to a duel."):format(nameOf(target)))
end

function module:Accept(player: Player)
	local request = requests[player]
	requests[player] = nil
	if not request or os.time() - request.At > Config.Duel.RequestSeconds or request.From.Parent ~= Players then
		return say(self, player, "Nobody has challenged you.")
	end
	local a, b = request.From, player
	local root = a.Character and a.Character:FindFirstChild("HumanoidRootPart")
	local broot = b.Character and b.Character:FindFirstChild("HumanoidRootPart")
	if not root or not broot or self.information[a] or self.information[b] then
		return
	end
	local flag = (root.Position + broot.Position) / 2
	self.information[a] = { Opponent = b, Active = false, Flag = flag }
	self.information[b] = { Opponent = a, Active = false, Flag = flag }
	self.includes.System["Effects.h"]:Play("Sparkle", flag, 20)
	task.spawn(function()
		for i = Config.Duel.Countdown, 1, -1 do
			for _, p in { a, b } do
				say(self, p, ("Duel starting in %d..."):format(i))
			end
			task.wait(1)
		end
		local da, db = self.information[a], self.information[b]
		if da and db and da.Opponent == b and db.Opponent == a then
			da.Active, db.Active = true, true
			update(self, a, b)
			update(self, b, a)
		end
	end)
end

function module:Decline(player: Player)
	local request = requests[player]
	requests[player] = nil
	if request and request.From.Parent == Players then
		say(self, request.From, nameOf(player) .. " declines your duel.")
	end
end

function module:End(winner: Player, loser: Player, reason: string)
	local a, b = self.information[winner], self.information[loser]
	self.information[winner], self.information[loser] = nil, nil
	if not a and not b then
		return
	end
	update(self, winner, nil)
	update(self, loser, nil)
	if reason ~= "flee" then
		self.includes.Social["Achievements.h"]:OnDuel(winner)
	end
	local text = if reason == "flee" then ("%s has fled from a duel with %s."):format(nameOf(loser), nameOf(winner))
		else ("%s has defeated %s in a duel."):format(nameOf(winner), nameOf(loser))
	local Functions = self.includes.Chat["ChatFunctions.h"]
	local Registry = self.includes.Chat["ChatRegistry.h"]
	local told = {}
	for _, p in { winner, loser } do
		for _, recipient in Functions:Recipients(Registry:Get("YELL"), p) do
			told[recipient] = true
		end
	end
	told[winner], told[loser] = true, true
	for recipient in told do
		say(self, recipient, text)
	end
end

-- Damage inside a duel never kills: the loser stays at 1 health.
function module:Hit(attacker: Player, victim: Player, damage: number, source: string): number
	local humanoid = victim.Character and victim.Character:FindFirstChildOfClass("Humanoid")
	if not humanoid or self:Opponent(attacker) ~= victim then
		return 0
	end
	local Combat = self.includes.Combat["Combat.h"]
	local armor = self.includes.Entities["EntityPlayer.h"]:Stats(victim).Armor
	damage = math.max(1, damage - armor)
	Combat:Enter(attacker)
	Combat:Enter(victim)
	if humanoid.Health - damage <= 1 then
		damage = math.max(0, humanoid.Health - 1)
		humanoid.Health = 1
		Combat:Log(attacker, ("%s hits %s for %d."):format(source, nameOf(victim), damage), Config.Chat.Colors.HIT)
		Combat:Log(victim, ("%s's %s hits you for %d."):format(nameOf(attacker), source:gsub("^Your ", ""), damage), Config.Chat.Colors.HURT)
		self:End(attacker, victim, "win")
		return damage
	end
	humanoid:TakeDamage(damage)
	self.includes.System["Effects.h"]:Play("Hit", victim, 6)
	Combat:Log(attacker, ("%s hits %s for %d."):format(source, nameOf(victim), damage), Config.Chat.Colors.HIT)
	Combat:Log(victim, ("%s's %s hits you for %d."):format(nameOf(attacker), source:gsub("^Your ", ""), damage), Config.Chat.Colors.HURT)
	return damage
end

-- Dying to something else, logging out or walking away loses the duel.
function module:Forfeit(player: Player)
	local duel = self.information[player]
	if duel then
		self:End(duel.Opponent, player, "flee")
	end
end

function module:Start()
	local Packet = self.includes.Security["Packet.h"]
	Packet:On(Opcodes.CMSG_DUEL, function(player, data)
		if typeof(data) ~= "table" then
			return
		end
		if data.Action == "request" then
			self:Request(player, data.Target)
		elseif data.Action == "accept" then
			self:Accept(player)
		elseif data.Action == "decline" then
			self:Decline(player)
		elseif data.Action == "cancel" then
			self:Forfeit(player)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		requests[player] = nil
		self:Forfeit(player)
	end)
	task.spawn(function()
		while true do
			task.wait(0.5)
			for player, duel in self.information do
				local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
				if duel.Active and root and (root.Position - duel.Flag).Magnitude > Config.Duel.FleeRange then
					self:Forfeit(player)
				end
			end
		end
	end)
end

return Base(module, {
	{ Path = "Auth/Social", Imports = "Achievements.h" },
	{ Path = "Auth/Security", Imports = "Packet.h" },
	{ Path = "Auth/Entities", Imports = "EntityPlayer.h" },
	{ Path = "Auth/Chat", Imports = "Chat.h|ChatFunctions.h|ChatRegistry.h" },
	{ Path = "World/Combat", Imports = "Combat.h" },
	{ Path = "Global/System", Imports = "Effects.h" },
})
