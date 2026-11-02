local Base = require(game:GetService("ServerStorage").ServerModules["Template.h"])
local Config = require(game:GetService("ReplicatedStorage").Shared.Config)
local module = {}

local ROLES = { PLAYER = 0, MODERATOR = 1, GAMEMASTER = 2, OWNER = 4, CONSOLE = 5 }
module.ROLES = ROLES

local function isCreator(player: Player): boolean
	return game.CreatorType == Enum.CreatorType.User and player.UserId == game.CreatorId
end

function module:GetRole(player: Player): number
	if isCreator(player) or table.find(Config.Owners, player.UserId) then
		return ROLES.OWNER
	end
	local account = self.includes.Database["AuthDatabase.h"]:Get(player)
	return if account and account.Role then account.Role else ROLES.PLAYER
end

function module:GetRoleName(level: number): string
	for name, value in ROLES do
		if value == level then
			return name
		end
	end
	return "PLAYER"
end

function module:Parse(name: string): number?
	return ROLES[name:upper()]
end

function module:HasLevel(player: Player, level: number): boolean
	return self:GetRole(player) >= level
end

return Base(module, {
	{ Path = "Auth/Database", Imports = "AuthDatabase.h" },
})
