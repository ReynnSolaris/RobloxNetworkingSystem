local Base = require(game:GetService("ServerStorage").ServerModules["Template.h"])
local MessagingService = game:GetService("MessagingService")
local module = {}

-- Cross-server bus on one MessagingService topic. Publish applies nothing
-- locally; the caller does its local work and every other server reacts.

local TOPIC = "RNS"
local handlers: { [string]: (any) -> () } = {}
local online = true

function module:On(kind: string, handler: (any) -> ())
	handlers[kind] = handler
end

function module:Publish(kind: string, data: {})
	if not online then
		return false
	end
	data.Kind = kind
	data.Origin = game.JobId
	local ok, err = pcall(MessagingService.PublishAsync, MessagingService, TOPIC, data)
	if not ok then
		warn("[Global] publish failed:", err)
	end
	return ok
end

function module:Start()
	local ok, err = pcall(MessagingService.SubscribeAsync, MessagingService, TOPIC, function(message)
		local data = message.Data
		if typeof(data) ~= "table" or data.Origin == game.JobId then
			return
		end
		local handler = handlers[data.Kind]
		if handler then
			task.spawn(handler, data)
		end
	end)
	if not ok then
		online = false
		warn("[Global] messaging unavailable, single-server mode:", err)
	end
end

return Base(module)
