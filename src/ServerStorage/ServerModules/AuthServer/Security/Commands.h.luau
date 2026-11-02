local Base = require(game:GetService("ServerStorage").ServerModules["Template.h"])
local Players = game:GetService("Players")
local Opcodes = require(game:GetService("ReplicatedStorage").Shared.Opcodes)
local module = {}

-- WoW-style GM dot commands, typed in chat: ".hurt Rainn 25"
-- Each entry: required role level, usage line, run(self, caller, args).

local function findPlayer(name: string): Player?
	name = name:lower()
	for _, player in Players:GetPlayers() do
		if player.Name:lower():sub(1, #name) == name then
			return player
		end
	end
	return nil
end

local function target(args): Player
	local name = args[1]
	assert(name and #name > 0, "no player given")
	return assert(findPlayer(name), "no such player")
end

local commands = {}

commands.help = { level = 0, usage = ".help", run = function(self, caller)
	local role = self.includes.Security["RBAC_Permissions.h"]:GetRole(caller)
	local lines = {}
	for name, cmd in commands do
		if role >= cmd.level then
			table.insert(lines, cmd.usage)
		end
	end
	table.sort(lines)
	self:Reply(caller, table.concat(lines, "\n"))
end }

commands.who = { level = 1, usage = ".who", run = function(self, caller)
	local RBAC = self.includes.Security["RBAC_Permissions.h"]
	local lines = {}
	for _, player in Players:GetPlayers() do
		table.insert(lines, ("%s [%s]"):format(player.Name, RBAC:GetRoleName(RBAC:GetRole(player))))
	end
	self:Reply(caller, table.concat(lines, ", "))
end }

commands.hurt = { level = 2, usage = ".hurt <player> <amount>", run = function(self, caller, args)
	self.includes.Entities["EntityPlayer.h"]:Hurt(target(args), assert(tonumber(args[2])))
end }

commands.heal = { level = 2, usage = ".heal [player]", run = function(self, caller, args)
	self.includes.Entities["EntityPlayer.h"]:Heal(if args[1] then target(args) else caller)
end }

commands.tele = { level = 2, usage = ".tele <x> <y> <z> | .tele <player>", run = function(self, caller, args)
	local Entities = self.includes.Entities["EntityPlayer.h"]
	if #args == 3 then
		local x, y, z = tonumber(args[1]), tonumber(args[2]), tonumber(args[3])
		Entities:Teleport(caller, CFrame.new(assert(x), assert(y), assert(z)))
	else
		local other = target(args)
		local character = assert(other.Character, "target has no character")
		Entities:Teleport(caller, character:GetPivot() * CFrame.new(0, 0, 3))
	end
end }

commands.kick = { level = 1, usage = ".kick <player> [reason]", run = function(self, caller, args)
	target(args):Kick(table.concat(args, " ", 2))
end }

commands.ban = { level = 2, usage = ".ban <player> [reason]", run = function(self, caller, args)
	self.includes.Database["AuthDatabase.h"]:Ban(target(args).UserId, table.concat(args, " ", 2), caller)
end }

commands.unban = { level = 2, usage = ".unban <userId>", run = function(self, caller, args)
	self.includes.Database["AuthDatabase.h"]:Unban(assert(tonumber(args[1])))
	self:Reply(caller, "Unbanned " .. args[1])
end }

commands.role = { level = 4, usage = ".role <player> <PLAYER|MODERATOR|GAMEMASTER|OWNER>", run = function(self, caller, args)
	local RBAC = self.includes.Security["RBAC_Permissions.h"]
	local other = target(args)
	local level = assert(RBAC:Parse(args[2] or ""), "unknown role")
	self.includes.Database["AuthDatabase.h"]:SetRole(other.UserId, level)
	local session = self.includes.Security["Session.h"]:Get(other)
	if session then
		session.Role = level
	end
	self:Reply(caller, ("%s is now %s"):format(other.Name, RBAC:GetRoleName(level)))
end }

commands.announce = { level = 2, usage = ".announce <text>", run = function(self, caller, args)
	self.includes.Security["Packet.h"]:Broadcast(Opcodes.SMSG_NOTIFICATION, { Text = table.concat(args, " ") })
end }

function module:Reply(player: Player, text: string)
	self.includes.Chat["Chat.h"]:System(player, text)
end

-- line is the chat message without its leading dot.
function module:Run(caller: Player, line: string)
	local args = line:split(" ")
	local name = table.remove(args, 1):lower()
	local command = commands[name]
	if not command then
		return self:Reply(caller, "Unknown command. Try .help")
	end
	if not self.includes.Security["RBAC_Permissions.h"]:HasLevel(caller, command.level) then
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
})
