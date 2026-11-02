local Base = require(game:GetService("ServerStorage").ServerModules["Template.h"])
local HttpService = game:GetService("HttpService")
local module = {}

function module:GenerateUUID(): string
	return HttpService:GenerateGUID(false)
end

return Base(module)
