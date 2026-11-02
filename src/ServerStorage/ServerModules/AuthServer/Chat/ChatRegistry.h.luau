local Base = require(game:GetService("ServerStorage").ServerModules["Template.h"])
local Config = require(game:GetService("ReplicatedStorage").Shared.Config)
local module = {}

local CHANNELS = {
	SAY = { Range = Config.Chat.SayRange },
	YELL = { Range = Config.Chat.YellRange },
	WORLD = {},
	WHISPER = { Target = true },
	PARTY = { Party = true },
	SYSTEM = { ServerOnly = true },
}
module.CHANNELS = CHANNELS

function module:Get(name: string)
	return CHANNELS[name]
end

return Base(module)
