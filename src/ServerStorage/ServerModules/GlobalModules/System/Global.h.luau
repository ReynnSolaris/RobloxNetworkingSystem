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

local queue = {}
local MAX_QUEUE = 500
local PUBLISH_INTERVAL = 0.5

function module:Publish(kind: string, data: {})
	if not online then
		return false
	end
	data.Kind = kind
	data.Origin = game.JobId
	table.insert(queue, data)
	if #queue > MAX_QUEUE then
		table.remove(queue, 1)
	end
	return true
end

-- Publishes drain at a rate MessagingService accepts; seeding a fresh database
-- can queue hundreds in a second.
task.spawn(function()
	local failures = 0
	while true do
		task.wait(PUBLISH_INTERVAL)
		local data = table.remove(queue, 1)
		if data and online then
			local ok, err = pcall(MessagingService.PublishAsync, MessagingService, TOPIC, data)
			if not ok then
				failures += 1
				if failures <= 3 then
					warn("[Global] publish failed:", err)
				end
				task.wait(5)
			else
				failures = 0
			end
		end
	end
end)

-- Subscribing can stall in Studio, so it runs off the boot thread; publishes
-- before it lands are simply not heard by this server.
function module:Start()
	task.spawn(function()
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
	end)
end

return Base(module)
