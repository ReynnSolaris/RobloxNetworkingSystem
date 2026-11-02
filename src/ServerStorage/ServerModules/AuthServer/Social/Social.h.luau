local Base = require(game:GetService("ServerStorage").ServerModules["Template.h"])
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Opcodes = require(ReplicatedStorage.Shared.Opcodes)
local Config = require(ReplicatedStorage.Shared.Config)
local module = {}

-- character_social: a character's Friends and Ignore lists (names). Friends see
-- each other come and go, ignored players are silent everywhere. /who lists who
-- is in the world, /played the time spent on the character.

local function nameOf(player: Player): string
	return player:GetAttribute("CharacterName") or player.Name
end

local function char(self, player: Player)
	local entity = self.includes.Entities["EntityPlayer.h"]:Get(player)
	local c = entity and entity.Active
	if c then
		c.Friends = c.Friends or {}
		c.Ignore = c.Ignore or {}
	end
	return c
end

local function online(name: string): Player?
	for _, player in Players:GetPlayers() do
		if (player:GetAttribute("CharacterName") or ""):lower() == name:lower() then
			return player
		end
	end
	return nil
end

local function has(list, name: string): number?
	for i, entry in list do
		if entry:lower() == name:lower() then
			return i
		end
	end
	return nil
end

function module:IsIgnoring(player: Player, other: Player): boolean
	local c = self.includes.Entities["EntityPlayer.h"]:Get(player)
	c = c and c.Active
	return c ~= nil and c.Ignore ~= nil and has(c.Ignore, nameOf(other)) ~= nil
end

local function describe(self, name: string)
	local other = online(name)
	local zone = other and self.includes.Zones["Zones.h"]:Current(other)
	return { Name = name, Online = other ~= nil, Level = other and other:GetAttribute("CharacterLevel"), Class = other and other:GetAttribute("CharacterClass"), Zone = zone and zone.Name }
end

function module:List(player: Player)
	local c = char(self, player)
	if not c then
		return
	end
	local friends = {}
	for _, name in c.Friends do
		table.insert(friends, describe(self, name))
	end
	self.includes.Security["Packet.h"]:Send(player, Opcodes.SMSG_CONTACT_LIST, { Friends = friends, Ignore = c.Ignore })
end

local function say(self, player: Player, text: string)
	self.includes.Chat["Chat.h"]:System(player, text)
end

function module:Add(player: Player, listName: string, name: string?)
	local c = char(self, player)
	if not c or typeof(name) ~= "string" or #name == 0 then
		return
	end
	local known = self.includes.Database["WorldDatabase.h"]:LookupName(name)
	if not known then
		return say(self, player, "Player not found.")
	end
	if known.Name == c.Name then
		return say(self, player, if listName == "Friends" then "You cannot add yourself to your friends list." else "You cannot ignore yourself.")
	end
	local list = c[listName]
	if has(list, known.Name) then
		return say(self, player, known.Name .. " is already on your " .. (if listName == "Friends" then "friends" else "ignore") .. " list.")
	end
	if #list >= (if listName == "Friends" then Config.Social.MaxFriends else Config.Social.MaxIgnore) then
		return say(self, player, "Your list is full.")
	end
	table.insert(list, known.Name)
	self.includes.Database["WorldDatabase.h"]:Commit(player)
	say(self, player, if listName == "Friends" then known.Name .. " added to friends." else known.Name .. " is now being ignored.")
	self:List(player)
end

function module:Remove(player: Player, listName: string, name: string?)
	local c = char(self, player)
	local i = c and typeof(name) == "string" and has(c[listName], name)
	if not i then
		return say(self, player, "Player not found.")
	end
	local removed = table.remove(c[listName], i)
	self.includes.Database["WorldDatabase.h"]:Commit(player)
	say(self, player, if listName == "Friends" then removed .. " removed from friends." else removed .. " is no longer being ignored.")
	self:List(player)
end

-- Tell everyone who lists this character as a friend that they came or went.
local function announce(self, player: Player, isOnline: boolean)
	local name = nameOf(player)
	for _, other in Players:GetPlayers() do
		local c = other ~= player and char(self, other)
		if c and has(c.Friends, name) then
			self.includes.Security["Packet.h"]:Send(other, Opcodes.SMSG_FRIEND_STATUS, { Name = name, Online = isOnline })
			self:List(other)
		end
	end
end

function module:OnLogin(player: Player)
	self:List(player)
	announce(self, player, true)
end

function module:OnLogout(player: Player)
	if char(self, player) then
		announce(self, player, false)
	end
end

function module:Who(player: Player, filter: string?)
	local needle = (typeof(filter) == "string" and filter or ""):lower()
	local list = {}
	for _, other in Players:GetPlayers() do
		local c = char(self, other)
		if c then
			local zone = self.includes.Zones["Zones.h"]:Current(other)
			local row = { Name = c.Name, Level = c.Level or 1, Class = c.Class, Zone = zone and zone.Name or "Unknown" }
			local haystack = (row.Name .. " " .. (row.Class or "") .. " " .. row.Zone):lower()
			if needle == "" or haystack:find(needle, 1, true) then
				table.insert(list, row)
			end
		end
	end
	table.sort(list, function(a, b)
		return a.Name < b.Name
	end)
	self.includes.Security["Packet.h"]:Send(player, Opcodes.SMSG_WHO, { Players = list })
end

function module:Played(player: Player)
	local entity = self.includes.Entities["EntityPlayer.h"]:Get(player)
	local c = entity and entity.Active
	if c then
		local total = (c.Played or 0) + (os.time() - (entity.LoginAt or os.time()))
		self.includes.Security["Packet.h"]:Send(player, Opcodes.SMSG_PLAYED_TIME, { Total = total, Session = os.time() - (entity.LoginAt or os.time()) })
	end
end

-- Inspect: another player's gear, stats and talent spread.
function module:Inspect(player: Player, name: string?)
	local Entities = self.includes.Entities["EntityPlayer.h"]
	local target = Entities:FindByName(name)
	local entity = target and Entities:Get(target)
	local c = entity and entity.Active
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local troot = target and target.Character and target.Character:FindFirstChild("HumanoidRootPart")
	if not c or not root or not troot or (troot.Position - root.Position).Magnitude > 30 then
		return self.includes.Chat["Chat.h"]:System(player, "No player named " .. tostring(name) .. " nearby.")
	end
	local Items = self.includes.Content["Items.h"]
	local slots = {}
	for slot, entry in (c.Equipment or {}) do
		slots[slot] = Items:Describe(entry)
	end
	local tabs = {}
	for id, rank in (c.Talents or {}) do
		local row = self.includes.Database["WorldDB.h"]:Get("talent", id)
		if row then
			tabs[row.tab] = (tabs[row.tab] or 0) + rank
		end
	end
	self.includes.Security["Packet.h"]:Send(player, Opcodes.SMSG_INSPECT_RESULT, { Name = c.Name, Class = c.Class, Race = c.Race, Level = c.Level, Guild = target:GetAttribute("Guild"),
		Equipment = slots, Stats = Entities:Stats(target), Talents = tabs, Honor = c.Honor or 0, HonorKills = c.HonorKills or 0 })
end

-- /roll: a number between 1 and max, told to the party or those in SAY range.
function module:Roll(player: Player, max: number?)
	max = math.clamp(math.floor(max or 100), 2, 1000000)
	local result = math.random(1, max)
	local name = player:GetAttribute("CharacterName") or player.Name
	local text = ("%s rolls %d (1-%d)"):format(name, result, max)
	local Functions = self.includes.Chat["ChatFunctions.h"]
	local Registry = self.includes.Chat["ChatRegistry.h"]
	local party = Functions:Recipients(Registry:Get("PARTY"), player)
	local recipients = if #party > 0 then party else Functions:Recipients(Registry:Get("SAY"), player)
	local told = { [player] = true }
	for _, r in recipients do
		told[r] = true
	end
	for r in told do
		self.includes.Chat["Chat.h"]:System(r, text)
	end
end

function module:Start()
	local Packet = self.includes.Security["Packet.h"]
	Packet:On(Opcodes.CMSG_INSPECT, function(player, data)
		if typeof(data) == "table" then self:Inspect(player, data.Name) end
	end)
	Packet:On(Opcodes.CMSG_RANDOM_ROLL, function(player, data)
		self:Roll(player, typeof(data) == "table" and tonumber(data.Max) or nil)
	end)
	Packet:On(Opcodes.CMSG_CONTACT_LIST, function(player)
		self:List(player)
	end)
	Packet:On(Opcodes.CMSG_ADD_FRIEND, function(player, data)
		if typeof(data) == "table" then self:Add(player, "Friends", data.Name) end
	end)
	Packet:On(Opcodes.CMSG_DEL_FRIEND, function(player, data)
		if typeof(data) == "table" then self:Remove(player, "Friends", data.Name) end
	end)
	Packet:On(Opcodes.CMSG_ADD_IGNORE, function(player, data)
		if typeof(data) == "table" then self:Add(player, "Ignore", data.Name) end
	end)
	Packet:On(Opcodes.CMSG_DEL_IGNORE, function(player, data)
		if typeof(data) == "table" then self:Remove(player, "Ignore", data.Name) end
	end)
	Packet:On(Opcodes.CMSG_WHO, function(player, data)
		self:Who(player, typeof(data) == "table" and data.Filter or nil)
	end)
	Packet:On(Opcodes.CMSG_PLAYED_TIME, function(player)
		self:Played(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		self:OnLogout(player)
	end)
end

return Base(module, {
	{ Path = "Auth/Security", Imports = "Packet.h" },
	{ Path = "Auth/Entities", Imports = "EntityPlayer.h" },
	{ Path = "Auth/Chat", Imports = "Chat.h|ChatFunctions.h|ChatRegistry.h" },
	{ Path = "World/Zones", Imports = "Zones.h" },
	{ Path = "World/Content", Imports = "Items.h" },
	{ Path = "World/Database", Imports = "WorldDatabase.h|WorldDB.h" },
})
