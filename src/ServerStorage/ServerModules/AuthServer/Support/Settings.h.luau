local Base = require(game:GetService("ServerStorage").ServerModules["Template.h"])
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Opcodes = require(ReplicatedStorage.Shared.Opcodes)
local module = {}

-- Client UI settings, kept per account: window positions, chat choices and
-- whatever else the client sends as a JSON object under 8 KB. Sent back on
-- authentication so windows open where they were left.

local LIMIT = 8192

function module:Send(player: Player)
	local account = self.includes.Database["AuthDatabase.h"]:Get(player)
	self.includes.Security["Packet.h"]:Send(player, Opcodes.SMSG_SETTINGS, { Settings = account and account.Settings or {} })
end

function module:Save(player: Player, settings)
	local account = self.includes.Database["AuthDatabase.h"]:Get(player)
	if not account or typeof(settings) ~= "table" then
		return
	end
	local ok, encoded = pcall(HttpService.JSONEncode, HttpService, settings)
	if not ok or #encoded > LIMIT then
		return
	end
	account.Settings = settings
	self.includes.Database["AuthDatabase.h"]:Save(player)
end

function module:Start()
	self.includes.Security["Packet.h"]:On(Opcodes.CMSG_SAVE_SETTINGS, function(player, data)
		if typeof(data) == "table" then
			self:Save(player, data.Settings)
		end
	end)
end

return Base(module, {
	{ Path = "Auth/Security", Imports = "Packet.h" },
	{ Path = "Auth/Database", Imports = "AuthDatabase.h" },
})
