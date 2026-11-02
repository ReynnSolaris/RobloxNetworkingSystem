local Base = require(game:GetService("ServerStorage").ServerModules["Template.h"])
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Opcodes = require(ReplicatedStorage.Shared.Opcodes)
local Config = require(ReplicatedStorage.Shared.Config)
local module = {}

-- WoW-style GM dot commands typed in chat. Levels: 1 MODERATOR, 2 GAMEMASTER, 4 OWNER.
-- A PLAYER typing a dot command gets "There is no such command".

local started = os.time()
local commands = {}

local function add(name: string, level: number, usage: string, run)
	commands[name] = { level = level, usage = usage, run = run }
end

local function findPlayer(name: string?): Player
	assert(name and #name > 0, "no player given")
	local lower = name:lower()
	for _, player in Players:GetPlayers() do
		if player.Name:lower():sub(1, #lower) == lower or player.DisplayName:lower():sub(1, #lower) == lower then
			return player
		end
	end
	error("no player named " .. name, 0)
end

local function humanoid(player: Player): Humanoid
	local character = assert(player.Character, player.Name .. " has no character")
	return assert(character:FindFirstChildOfClass("Humanoid"), player.Name .. " has no humanoid")
end

local function toggle(word: string?): boolean
	assert(word == "on" or word == "off", "expected on or off")
	return word == "on"
end

local function minutes(seconds: number): string
	return ("%d min"):format(math.ceil(seconds / 60))
end

-- Pick the target: args[i] if given, else the caller.
local function targetOrSelf(args, i: number, caller: Player): Player
	return if args[i] then findPlayer(args[i]) else caller
end

-- info

add("help", 1, ".help", function(self, caller)
	local RBAC = self.includes.Security["RBAC_Permissions.h"]
	local role = RBAC:GetRole(caller)
	local lines = {}
	for _, cmd in commands do
		if role >= cmd.level then
			table.insert(lines, cmd.usage)
		end
	end
	table.sort(lines)
	self:Reply(caller, ("Commands for %s:"):format(RBAC:GetRoleName(role)))
	for _, line in lines do
		self:Reply(caller, "  " .. line)
	end
end)

add("who", 1, ".who", function(self, caller)
	local RBAC = self.includes.Security["RBAC_Permissions.h"]
	local Session = self.includes.Security["Session.h"]
	for _, player in Players:GetPlayers() do
		local session = Session:Get(player)
		self:Reply(caller, ("%s (%s) %s%s"):format(player.Name, RBAC:GetRoleName(RBAC:GetRole(player)),
			if session and session.Gm then "<GM> " else "", if session and session.Invisible then "[invisible]" else ""))
	end
end)

add("server", 1, ".server info", function(self, caller)
	local up = os.time() - started
	self:Reply(caller, ("Build %d, up %dh %dm, %d players, %d Hz"):format(
		Config.Build, up // 3600, (up % 3600) // 60, #Players:GetPlayers(), math.round(1 / game:GetService("RunService").Heartbeat:Wait())))
end)

-- gm mode and visibility

add("gm", 1, ".gm on|off | .gm invis on|off | .gm list", function(self, caller, args)
	local Session = self.includes.Security["Session.h"]
	local session = assert(Session:Get(caller), "no session")
	local sub = args[1]
	if sub == "list" then
		for _, player in Players:GetPlayers() do
			local other = Session:Get(player)
			if other and other.Gm then
				self:Reply(caller, player.Name .. (if other.Invisible then " [invisible]" else ""))
			end
		end
	elseif sub == "invis" then
		session.Invisible = toggle(args[2])
		self:Reply(caller, if session.Invisible then "You are now invisible to players." else "You are now visible.")
	else
		session.Gm = toggle(sub)
		self:Reply(caller, if session.Gm then "GM mode on." else "GM mode off.")
	end
	self:BroadcastState(caller)
end)

-- movement

add("tele", 2, ".tele <x> <y> <z> | .tele <player>", function(self, caller, args)
	local Entities = self.includes.Entities["EntityPlayer.h"]
	if #args == 3 then
		local x, y, z = tonumber(args[1]), tonumber(args[2]), tonumber(args[3])
		Entities:Teleport(caller, CFrame.new(assert(x), assert(y), assert(z)))
	else
		local other = findPlayer(args[1])
		Entities:Teleport(caller, assert(other.Character, "target has no character"):GetPivot() * CFrame.new(0, 0, 3))
	end
end)

add("appear", 2, ".appear <player>", function(self, caller, args)
	commands.tele.run(self, caller, { args[1] })
end)

add("summon", 2, ".summon <player>", function(self, caller, args)
	local other = findPlayer(args[1])
	local here = assert(caller.Character, "you have no character"):GetPivot() * CFrame.new(0, 0, -3)
	self.includes.Entities["EntityPlayer.h"]:Teleport(other, here)
	self:Reply(other, ("Summoned by %s."):format(caller.Name))
end)

add("speed", 2, ".speed <0.1-10> [player]", function(self, caller, args)
	local mult = assert(tonumber(args[1]), "expected a number")
	humanoid(targetOrSelf(args, 2, caller)).WalkSpeed = 16 * math.clamp(mult, 0.1, 10)
end)

add("freeze", 1, ".freeze <player>", function(self, caller, args)
	local other = findPlayer(args[1])
	humanoid(other).WalkSpeed = 0
	humanoid(other).JumpPower = 0
	self:Reply(other, "You have been frozen.")
end)

add("unfreeze", 1, ".unfreeze <player>", function(self, caller, args)
	local other = findPlayer(args[1])
	humanoid(other).WalkSpeed = 16
	humanoid(other).JumpPower = 50
	self:Reply(other, "You have been unfrozen.")
end)

-- health

add("hurt", 2, ".hurt <player> <amount>", function(self, caller, args)
	self.includes.Entities["EntityPlayer.h"]:Hurt(findPlayer(args[1]), assert(tonumber(args[2]), "expected an amount"))
end)

add("heal", 2, ".heal [player]", function(self, caller, args)
	self.includes.Entities["EntityPlayer.h"]:Heal(targetOrSelf(args, 1, caller))
end)

add("kill", 2, ".kill [player]", function(self, caller, args)
	humanoid(targetOrSelf(args, 1, caller)).Health = 0
end)

add("revive", 2, ".revive [player]", function(self, caller, args)
	local other = targetOrSelf(args, 1, caller)
	self.includes.Entities["EntityPlayer.h"]:Spawn(other, other.Character and other.Character:GetPivot())
end)

add("maxhealth", 2, ".maxhealth <amount> [player]", function(self, caller, args)
	local h = humanoid(targetOrSelf(args, 2, caller))
	h.MaxHealth = assert(tonumber(args[1]), "expected an amount")
	h.Health = h.MaxHealth
end)

-- discipline

add("mute", 1, ".mute <player> <minutes> [reason]", function(self, caller, args)
	local other = findPlayer(args[1])
	local until_ = os.time() + assert(tonumber(args[2]), "expected minutes") * 60
	local session = self.includes.Security["Session.h"]:Get(other)
	if session then
		session.MutedUntil = until_
	end
	self.includes.Database["AuthDatabase.h"]:Edit(other.UserId, function(account)
		account.MutedUntil = until_
	end)
	self:Reply(other, ("You have been muted for %s. %s"):format(minutes(until_ - os.time()), table.concat(args, " ", 3)))
	self:Reply(caller, other.Name .. " muted.")
end)

add("unmute", 1, ".unmute <player>", function(self, caller, args)
	local other = findPlayer(args[1])
	local session = self.includes.Security["Session.h"]:Get(other)
	if session then
		session.MutedUntil = 0
	end
	self.includes.Database["AuthDatabase.h"]:Edit(other.UserId, function(account)
		account.MutedUntil = nil
	end)
	self:Reply(other, "You have been unmuted.")
end)

add("kick", 1, ".kick <player> [reason]", function(self, caller, args)
	findPlayer(args[1]):Kick(table.concat(args, " ", 2))
end)

add("ban", 2, ".ban <player> [reason]", function(self, caller, args)
	self.includes.Database["AuthDatabase.h"]:Ban(findPlayer(args[1]).UserId, table.concat(args, " ", 2), caller)
end)

add("unban", 2, ".unban <userId>", function(self, caller, args)
	self.includes.Database["AuthDatabase.h"]:Unban(assert(tonumber(args[1]), "expected a UserId"))
	self:Reply(caller, "Unbanned " .. args[1])
end)

add("role", 4, ".role <player> <PLAYER|MODERATOR|GAMEMASTER|OWNER>", function(self, caller, args)
	local RBAC = self.includes.Security["RBAC_Permissions.h"]
	local other = findPlayer(args[1])
	local level = assert(RBAC:Parse(args[2] or ""), "unknown role")
	self.includes.Database["AuthDatabase.h"]:SetRole(other.UserId, level)
	local session = self.includes.Security["Session.h"]:Get(other)
	if session then
		session.Role = level
	end
	self:Reply(caller, ("%s is now %s"):format(other.Name, RBAC:GetRoleName(level)))
end)

-- world

add("announce", 2, ".announce <text>", function(self, caller, args)
	self.includes.Security["Packet.h"]:Broadcast(Opcodes.SMSG_NOTIFICATION, { Text = table.concat(args, " ") })
end)

add("save", 2, ".save [player]", function(self, caller, args)
	self.includes.Entities["EntityPlayer.h"]:Save(targetOrSelf(args, 1, caller))
	self.includes.Database["Database.h"]:FlushAll()
	self:Reply(caller, "Saved.")
end)

add("saveall", 2, ".saveall", function(self, caller)
	for _, player in Players:GetPlayers() do
		self.includes.Entities["EntityPlayer.h"]:Save(player)
	end
	self.includes.Database["Database.h"]:FlushAll()
	self:Reply(caller, "All players saved.")
end)

-- plumbing

function module:Reply(player: Player, text: string)
	self.includes.Chat["Chat.h"]:System(player, text)
end

-- Tell every client how to draw this GM (tag, visibility).
function module:BroadcastState(player: Player)
	local session = self.includes.Security["Session.h"]:Get(player)
	if session then
		self.includes.Security["Packet.h"]:Broadcast(Opcodes.SMSG_GM_STATE,
			{ Name = player.Name, Gm = session.Gm, Invisible = session.Invisible })
	end
end

-- Bring a newcomer up to date on every GM that is tagged or hidden.
function module:SyncState(player: Player)
	local Session = self.includes.Security["Session.h"]
	for _, other in Players:GetPlayers() do
		local session = Session:Get(other)
		if session and (session.Gm or session.Invisible) then
			self.includes.Security["Packet.h"]:Send(player, Opcodes.SMSG_GM_STATE,
				{ Name = other.Name, Gm = session.Gm, Invisible = session.Invisible })
		end
	end
end

-- line is the chat message without its leading dot.
function module:Run(caller: Player, line: string)
	local RBAC = self.includes.Security["RBAC_Permissions.h"]
	if RBAC:GetRole(caller) < RBAC.ROLES.MODERATOR then
		return self:Reply(caller, "There is no such command")
	end
	local args = line:split(" ")
	local name = table.remove(args, 1):lower()
	local command = commands[name]
	if not command then
		return self:Reply(caller, "There is no such command. Try .help")
	end
	if not RBAC:HasLevel(caller, command.level) then
		return self:Reply(caller, "You do not have permission for ." .. name)
	end
	local ok, err = pcall(command.run, self, caller, args)
	if not ok then
		self:Reply(caller, ("%s\nUsage: %s"):format((tostring(err):gsub("^.-:%d+: ", "")), command.usage))
	end
end

return Base(module, {
	{ Path = "Auth/Security", Imports = "RBAC_Permissions.h|Session.h|Packet.h" },
	{ Path = "Auth/Entities", Imports = "EntityPlayer.h" },
	{ Path = "Auth/Database", Imports = "AuthDatabase.h" },
	{ Path = "Auth/Chat", Imports = "Chat.h" },
	{ Path = "Global/Database", Imports = "Database.h" },
})
