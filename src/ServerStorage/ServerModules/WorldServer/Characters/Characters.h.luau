local Base = require(game:GetService("ServerStorage").ServerModules["Template.h"])
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")
local Opcodes = require(ReplicatedStorage.Shared.Opcodes)
local Config = require(ReplicatedStorage.Shared.Config)
local module = {}

-- The 3.3.5a login sequence after auth: CHAR_ENUM lists the account's
-- characters, CHAR_CREATE / CHAR_DELETE edit them, PLAYER_LOGIN picks one and
-- spawns it, LOGOUT_REQUEST goes back to the list.

local function classByName(name: string?)
	for _, class in Config.Classes do
		if class.Name == name then
			return class
		end
	end
	return nil
end

local function validName(name: any): (boolean, string?)
	if typeof(name) ~= "string" or #name < 2 or #name > 12 or not name:match("^%a+$") then
		return false, "Names are 2 to 12 letters."
	end
	return true
end

function module:Enum(player: Player)
	local record = self.includes.Database["WorldDatabase.h"]:Get(player)
	local list = {}
	for slot, char in (record and record.Characters or {}) do
		list[slot] = { Slot = slot, Name = char.Name, Class = char.Class, Level = char.Level }
	end
	self.includes.Security["Packet.h"]:Send(player, Opcodes.SMSG_CHAR_ENUM, { Characters = list, Max = Config.MaxCharacters })
end

function module:Result(player: Player, ok: boolean, reason: string?)
	self.includes.Security["Packet.h"]:Send(player, Opcodes.SMSG_CHAR_RESULT, { Ok = ok, Reason = reason })
end

function module:Create(player: Player, data)
	local record = self.includes.Database["WorldDatabase.h"]:Get(player)
	if not record then
		return
	end
	if #record.Characters >= Config.MaxCharacters then
		return self:Result(player, false, "All character slots are full.")
	end
	local ok, reason = validName(data.Name)
	if not ok then
		return self:Result(player, false, reason)
	end
	local name = data.Name:sub(1, 1):upper() .. data.Name:sub(2):lower()
	for _, char in record.Characters do
		if char.Name == name then
			return self:Result(player, false, "You already have a character with that name.")
		end
	end
	local class = classByName(data.Class)
	if not class then
		return self:Result(player, false, "Pick a class.")
	end
	local filtered = pcall(function()
		return TextService:FilterStringAsync(name, player.UserId):GetNonChatStringForBroadcastAsync()
	end)
	if not filtered then
		return self:Result(player, false, "That name is not allowed.")
	end
	table.insert(record.Characters, { Name = name, Class = class.Name, Level = 1, Created = os.time() })
	self.includes.Database["WorldDatabase.h"]:Commit(player)
	self:Result(player, true)
	self:Enum(player)
end

function module:Delete(player: Player, data)
	local record = self.includes.Database["WorldDatabase.h"]:Get(player)
	local slot = tonumber(data.Slot)
	if not record or not slot or not record.Characters[slot] then
		return self:Result(player, false, "No such character.")
	end
	table.remove(record.Characters, slot)
	self.includes.Database["WorldDatabase.h"]:Commit(player)
	self:Result(player, true)
	self:Enum(player)
end

function module:Login(player: Player, data)
	local Session = self.includes.Security["Session.h"]
	local session = Session:Get(player)
	local record = self.includes.Database["WorldDatabase.h"]:Get(player)
	local slot = tonumber(data.Slot)
	if not session or session.State ~= Session.STATE.AUTHED then
		return
	end
	if not record or not slot or not record.Characters[slot] then
		return self:Result(player, false, "No such character.")
	end
	self.includes.Entities["EntityPlayer.h"]:Select(player, slot)
	if not self.includes.Combat["Death.h"]:Restore(player) then
		self.includes.Entities["EntityPlayer.h"]:Spawn(player)
	end
	self.includes.Chat["Chat.h"]:System(player, ("Welcome to %s, %s."):format(Config.RealmName, record.Characters[slot].Name))
end

function module:Logout(player: Player)
	local Session = self.includes.Security["Session.h"]
	local session = Session:Get(player)
	if not session or session.State ~= Session.STATE.IN_WORLD then
		return
	end
	self.includes.Combat["Death.h"]:Forget(player)
	self.includes.Entities["EntityPlayer.h"]:Despawn(player)
	session.State = Session.STATE.AUTHED
	self:Enum(player)
end

function module:Start()
	local Packet = self.includes.Security["Packet.h"]
	Packet:On(Opcodes.CMSG_CHAR_ENUM, function(player)
		self:Enum(player)
	end)
	Packet:On(Opcodes.CMSG_CHAR_CREATE, function(player, data)
		if typeof(data) == "table" then
			self:Create(player, data)
		end
	end)
	Packet:On(Opcodes.CMSG_CHAR_DELETE, function(player, data)
		if typeof(data) == "table" then
			self:Delete(player, data)
		end
	end)
	Packet:On(Opcodes.CMSG_PLAYER_LOGIN, function(player, data)
		if typeof(data) == "table" then
			self:Login(player, data)
		end
	end)
	Packet:On(Opcodes.CMSG_LOGOUT_REQUEST, function(player)
		self:Logout(player)
	end)
end

return Base(module, {
	{ Path = "Auth/Security", Imports = "Packet.h|Session.h" },
	{ Path = "Auth/Entities", Imports = "EntityPlayer.h" },
	{ Path = "World/Database", Imports = "WorldDatabase.h" },
	{ Path = "Auth/Chat", Imports = "Chat.h" },
	{ Path = "World/Combat", Imports = "Death.h" },
})
