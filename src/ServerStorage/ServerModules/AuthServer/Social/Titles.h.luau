local Base = require(game:GetService("ServerStorage").ServerModules["Template.h"])
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Opcodes = require(ReplicatedStorage.Shared.Opcodes)
local Config = require(ReplicatedStorage.Shared.Config)
local module = {}

-- Titles. PvP ranks come from honor earned (Config.Titles.Ranks), achievements
-- may carry a `title`. A character keeps Titles = { [name] = true } and Title,
-- the one shown; "%s" in a title marks where the name goes ("%s the Explorer"),
-- otherwise the title goes in front ("Private %s").

local function char(self, player: Player)
	local entity = self.includes.Entities["EntityPlayer.h"]:Get(player)
	local c = entity and entity.Active
	if c then
		c.Titles = c.Titles or {}
	end
	return c
end

function module.Format(title: string?, name: string): string
	if not title or title == "" then
		return name
	end
	return if title:find("%%s") then title:format(name) else title .. " " .. name
end

function module:Sync(player: Player)
	local c = char(self, player)
	if not c then
		return
	end
	local list = {}
	for title in c.Titles do
		table.insert(list, title)
	end
	table.sort(list)
	player:SetAttribute("Titles", HttpService:JSONEncode(list))
	player:SetAttribute("CharacterTitle", c.Title or "")
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayName = module.Format(c.Title, c.Name)
	end
end

function module:Grant(player: Player, title: string)
	local c = char(self, player)
	if not c or c.Titles[title] then
		return
	end
	c.Titles[title] = true
	self.includes.Database["WorldDatabase.h"]:Commit(player)
	self.includes.Chat["Chat.h"]:System(player, ("You have earned the title \"%s\"."):format(module.Format(title, c.Name)))
	self:Sync(player)
end

function module:Set(player: Player, title: string?)
	local c = char(self, player)
	if not c then
		return
	end
	if title == nil or title == "" then
		c.Title = nil
	elseif c.Titles[title] then
		c.Title = title
	else
		return self.includes.Chat["Chat.h"]:System(player, "You have not earned that title.")
	end
	self.includes.Database["WorldDatabase.h"]:Commit(player)
	self:Sync(player)
end

-- Honor changed: grant every rank reached.
function module:OnHonor(player: Player, honor: number)
	for _, rank in Config.Titles.Ranks do
		if honor >= rank.Honor then
			self:Grant(player, rank.Name)
		end
	end
end

function module:OnLogin(player: Player)
	local c = char(self, player)
	if c then
		self:OnHonor(player, c.Honor or 0)
		self:Sync(player)
	end
end

function module:Start()
	self.includes.Security["Packet.h"]:On(Opcodes.CMSG_SET_TITLE, function(player, data)
		self:Set(player, typeof(data) == "table" and typeof(data.Title) == "string" and data.Title or nil)
	end)
end

return Base(module, {
	{ Path = "Auth/Security", Imports = "Packet.h" },
	{ Path = "Auth/Entities", Imports = "EntityPlayer.h" },
	{ Path = "Auth/Chat", Imports = "Chat.h" },
	{ Path = "World/Database", Imports = "WorldDatabase.h" },
})
