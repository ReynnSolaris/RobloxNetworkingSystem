local Base = require(game:GetService("ServerStorage").ServerModules["Template.h"])
local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Opcodes = require(ReplicatedStorage.Shared.Opcodes)
local Config = require(ReplicatedStorage.Shared.Config)
local module = {}

-- Time of day, weather and game events, all derived from the real clock so
-- every server agrees. game_event: { id, name, description, start (unix),
-- length (minutes), occurrence (minutes), xp_mult }. Creatures and objects with
-- `event = id` on their spawn row exist only while it runs. Weather is a state
-- per WeatherMinutes window that clients draw.

local SEED = {
	{ name = "Harvest Festival", description = "The farmers of Elwynn celebrate the harvest. Festival vendors set up in Northshire.", start = 0, length = 120, occurrence = 1440, xp_mult = 1 },
	{ name = "Darkmoon Faire", description = "Silas Darkmoon's travelling faire is in town, with games and prizes.", start = 86400 * 3, length = 60 * 24 * 7, occurrence = 60 * 24 * 28, xp_mult = 1 },
	{ name = "Weekend Bonus", description = "Experience from kills is increased by half.", start = 86400 * 2, length = 60 * 48, occurrence = 60 * 24 * 7, xp_mult = 1.5 },
}

function module:DB()
	return self.includes.Database["WorldDB.h"]
end

function module:IsActive(event): boolean
	local period = (event.occurrence or 0) * 60
	local length = (event.length or 0) * 60
	if length <= 0 then
		return false
	end
	local since = os.time() - (event.start or 0)
	if since < 0 then
		return false
	end
	return if period > 0 then (since % period) < length else since < length
end

function module:Active()
	local out = {}
	for _, event in self:DB():Select("game_event") do
		if self:IsActive(event) then
			table.insert(out, event)
		end
	end
	return out
end

function module:IsEventActive(id): boolean
	local event = self:DB():Get("game_event", id)
	return event ~= nil and self:IsActive(event)
end

function module:XpMultiplier(): number
	local mult = 1
	for _, event in self:Active() do
		mult *= event.xp_mult or 1
	end
	return mult
end

-- Hour of the game day, 0 to 24.
function module:Hour(): number
	local day = Config.World.DayMinutes * 60
	return (os.time() % day) / day * 24
end

-- Deterministic weather for the current window.
function module:Weather(): (string, number)
	local window = os.time() // (Config.World.WeatherMinutes * 60)
	local rng = Random.new(window)
	local kinds = Config.World.Weathers
	return kinds[rng:NextInteger(1, #kinds)], rng:NextNumber(0.4, 1)
end

function module:SendWeather(player: Player, kind: string, intensity: number)
	self.includes.Security["Packet.h"]:Send(player, Opcodes.SMSG_WEATHER, { Kind = kind, Intensity = intensity })
end

function module:SendEvents(player: Player, started)
	local list = {}
	for _, event in self:Active() do
		table.insert(list, { Id = event.id, Name = event.name, Description = event.description })
	end
	self.includes.Security["Packet.h"]:Send(player, Opcodes.SMSG_GAME_EVENT, { Active = list, Started = started })
end

function module:OnLogin(player: Player)
	local kind, intensity = self:Weather()
	self:SendWeather(player, kind, intensity)
	self:SendEvents(player)
end

function module:Start()
	local DB = self:DB()
	local byName = {}
	for _, row in DB:Select("game_event") do
		byName[row.name] = row
	end
	for _, seed in SEED do
		if not byName[seed.name] then
			DB:Insert("game_event", table.clone(seed))
		end
	end
	Lighting.ClockTime = self:Hour()
	local lastWeather, lastActive, first = nil, {}, true
	local function announce(text: string, started: string?)
		for _, player in Players:GetPlayers() do
			self.includes.Chat["Chat.h"]:System(player, text)
			self:SendEvents(player, started)
		end
		self.includes.Content["Creatures.h"]:Respawn()
		self.includes.Content["GameObjects.h"]:Respawn()
	end
	task.spawn(function()
		while true do
			Lighting.ClockTime = self:Hour()
			local kind, intensity = self:Weather()
			if kind ~= lastWeather then
				lastWeather = kind
				for _, player in Players:GetPlayers() do
					self:SendWeather(player, kind, intensity)
				end
			end
			local active = {}
			for _, event in self:Active() do
				active[event.id] = event
				if not first and not lastActive[event.id] then
					announce(("%s has begun! %s"):format(event.name, event.description or ""), event.name)
				end
			end
			for id, event in lastActive do
				if not active[id] then
					announce(("%s has ended."):format(event.name))
				end
			end
			lastActive, first = active, false
			task.wait(5)
		end
	end)
end

return Base(module, {
	{ Path = "Auth/Security", Imports = "Packet.h" },
	{ Path = "Auth/Chat", Imports = "Chat.h" },
	{ Path = "World/Content", Imports = "Creatures.h|GameObjects.h" },
	{ Path = "World/Database", Imports = "WorldDB.h" },
})
