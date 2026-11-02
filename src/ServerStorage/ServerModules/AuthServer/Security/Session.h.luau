local Base = require(game:GetService("ServerStorage").ServerModules["Template.h"])
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Opcodes = require(ReplicatedStorage.Shared.Opcodes)
local Config = require(ReplicatedStorage.Shared.Config)
local module = {}

local STATE = { CONNECTED = 0, AUTHED = 1, IN_WORLD = 2 }
module.STATE = STATE

local onAuthed: { (Player) -> () } = {}

-- Called when a player passes CMSG_AUTH_SESSION.
function module:OnAuthed(fn: (Player) -> ())
	table.insert(onAuthed, fn)
end

function module:Open(player: Player)
	local AuthDatabase = self.includes.Database["AuthDatabase.h"]
	local account = AuthDatabase:Load(player)
	if account.Banned then
		AuthDatabase:Save(player)
		player:Kick("Banned: " .. (account.Banned.Reason or "no reason given"))
		return nil
	end
	local session = {
		Player = player,
		Id = self.includes.Database["DatabaseUUID.h"]:GenerateUUID(),
		State = STATE.CONNECTED,
		Role = self.includes.Security["RBAC_Permissions.h"]:GetRole(player),
		Opened = os.time(),
		MutedUntil = account.MutedUntil or 0,
		Gm = false,
		Invisible = false,
	}
	self.information[player] = session
	return session
end

function module:Get(player: Player)
	return self.information[player]
end

function module:Close(player: Player)
	if self.information[player] then
		self.includes.Database["AuthDatabase.h"]:Save(player)
		self.information[player] = nil
	end
end

function module:Start()
	local Packet = self.includes.Security["Packet.h"]
	local RBAC = self.includes.Security["RBAC_Permissions.h"]

	Packet:SetGuard(function(player, opcode)
		local session = self.information[player]
		if not session then
			return false
		end
		return session.State >= STATE.AUTHED
			or opcode == Opcodes.CMSG_AUTH_SESSION
			or opcode == Opcodes.CMSG_PING
	end)

	Packet:On(Opcodes.CMSG_AUTH_SESSION, function(player, data)
		local session = self.information[player]
		if not session or session.State ~= STATE.CONNECTED then
			return
		end
		local ok = typeof(data) == "table" and data.Build == Config.Build
		Packet:Send(player, Opcodes.SMSG_AUTH_RESPONSE, {
			Ok = ok,
			SessionId = if ok then session.Id else nil,
			Role = RBAC:GetRoleName(session.Role),
			Level = session.Role,
			Reason = if ok then nil else "BUILD_MISMATCH",
		})
		if not ok then
			task.delay(1, player.Kick, player, "Client build mismatch")
			return
		end
		session.State = STATE.AUTHED
		for _, fn in onAuthed do
			task.spawn(fn, player)
		end
	end)

	Packet:On(Opcodes.CMSG_PING, function(player, data)
		Packet:Send(player, Opcodes.SMSG_PONG, { Time = if typeof(data) == "table" then data.Time else nil })
	end)
end

return Base(module, {
	{ Path = "Auth/Security", Imports = "Packet.h|RBAC_Permissions.h" },
	{ Path = "Auth/Database", Imports = "AuthDatabase.h" },
	{ Path = "Global/Database", Imports = "DatabaseUUID.h" },
})
