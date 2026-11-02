local Base = require(game:GetService("ServerStorage").ServerModules["Template.h"])
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Opcodes = require(ReplicatedStorage.Shared.Opcodes)
local Config = require(ReplicatedStorage.Shared.Config)
local module = {}

-- Dungeon finder. lfg_dungeon: { id, name, minlevel, maxlevel, x, y, z, o } with
-- the entrance set by .lfg entrance. Players queue with a role; once the queue
-- holds Config.Lfg.Roles for a dungeon a party forms, loot goes to group
-- rolls, and everyone ports to the entrance. information[player] = { Dungeon, Role }.

local SEED = { { name = "Kobold Mines", minlevel = 5, maxlevel = 15 }, { name = "Northshire Crypt", minlevel = 10, maxlevel = 20 } }

function module:DB()
	return self.includes.Database["WorldDB.h"]
end

local function counts(self, dungeonId)
	local have = { tank = {}, healer = {}, dps = {} }
	for player, entry in self.information do
		if player.Parent == Players and entry.Dungeon == dungeonId then
			table.insert(have[entry.Role], player)
		end
	end
	return have
end

function module:Status(player: Player)
	local entry = self.information[player]
	if not entry then
		return self.includes.Security["Packet.h"]:Send(player, Opcodes.SMSG_LFG_STATUS, { Status = "none" })
	end
	local dungeon = self:DB():Get("lfg_dungeon", entry.Dungeon)
	local have = counts(self, entry.Dungeon)
	self.includes.Security["Packet.h"]:Send(player, Opcodes.SMSG_LFG_STATUS, { Status = "queued", Dungeon = dungeon and dungeon.name, Role = entry.Role,
		Have = { tank = #have.tank, healer = #have.healer, dps = #have.dps }, Need = Config.Lfg.Roles })
end

function module:List(player: Player)
	local list = {}
	local level = player:GetAttribute("CharacterLevel") or 1
	for _, row in self:DB():Select("lfg_dungeon") do
		table.insert(list, { Id = row.id, Name = row.name, MinLevel = row.minlevel or 1, MaxLevel = row.maxlevel or 80, Ready = row.x ~= nil, Eligible = level >= (row.minlevel or 1) and level <= (row.maxlevel or 80) })
	end
	self.includes.Security["Packet.h"]:Send(player, Opcodes.SMSG_LFG_STATUS, { Status = "list", Dungeons = list })
end

function module:Join(player: Player, dungeonId, role: string)
	local Chat = self.includes.Chat["Chat.h"]
	local dungeon = self:DB():Get("lfg_dungeon", dungeonId)
	if not dungeon or not dungeon.x then
		return Chat:System(player, "That dungeon has no entrance set yet.")
	elseif not Config.Lfg.Roles[role] then
		return Chat:System(player, "Pick a role: tank, healer or dps.")
	end
	local level = player:GetAttribute("CharacterLevel") or 1
	if level < (dungeon.minlevel or 1) or level > (dungeon.maxlevel or 80) then
		return Chat:System(player, ("%s is for levels %d to %d."):format(dungeon.name, dungeon.minlevel or 1, dungeon.maxlevel or 80))
	end
	self.information[player] = { Dungeon = dungeon.id, Role = role }
	Chat:System(player, ("You are in the queue for %s as %s."):format(dungeon.name, role))
	self:TryForm(dungeon.id)
	for other, entry in self.information do
		if entry.Dungeon == dungeon.id then
			self:Status(other)
		end
	end
end

function module:Leave(player: Player, quiet: boolean?)
	local entry = self.information[player]
	self.information[player] = nil
	if not quiet then
		self:Status(player)
	end
	if entry then
		for other, e in self.information do
			if e.Dungeon == entry.Dungeon then
				self:Status(other)
			end
		end
	end
end

function module:TryForm(dungeonId)
	local have = counts(self, dungeonId)
	for role, need in Config.Lfg.Roles do
		if #have[role] < need then
			return
		end
	end
	local members = {}
	for role, need in Config.Lfg.Roles do
		for i = 1, need do
			table.insert(members, have[role][i])
		end
	end
	-- tanks lead
	table.sort(members, function(a, b)
		local ra, rb = self.information[a].Role, self.information[b].Role
		return (ra == "tank" and rb ~= "tank") or (ra == "healer" and rb == "dps")
	end)
	for _, member in members do
		self.information[member] = nil
	end
	local party = self.includes.Social["Party.h"]:Form(members)
	if not party then
		return
	end
	local dungeon = self:DB():Get("lfg_dungeon", dungeonId)
	local at = self:DB().ToCFrame(dungeon) * CFrame.new(0, 3, 0)
	for _, member in members do
		self.includes.Chat["Chat.h"]:System(member, ("Your group for %s is ready. Teleporting to the entrance."):format(dungeon.name))
		self:Status(member)
		self.includes.Entities["EntityPlayer.h"]:Teleport(member, at)
	end
end

function module:SetEntrance(id, cframe: CFrame)
	assert(self:DB():Get("lfg_dungeon", id), "no such dungeon")
	self:DB():Update("lfg_dungeon", id, self:DB().ToRow(cframe))
end

function module:Start()
	local DB = self:DB()
	local byName = {}
	for _, row in DB:Select("lfg_dungeon") do
		byName[row.name] = row
	end
	for _, seed in SEED do
		if not byName[seed.name] then
			DB:Insert("lfg_dungeon", table.clone(seed))
		end
	end
	local Packet = self.includes.Security["Packet.h"]
	Packet:On(Opcodes.CMSG_LFG_JOIN, function(player, data)
		if typeof(data) ~= "table" then
			return
		end
		if data.List then
			return self:List(player)
		end
		self:Join(player, tonumber(data.Dungeon), tostring(data.Role))
	end)
	Packet:On(Opcodes.CMSG_LFG_LEAVE, function(player)
		self:Leave(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		self:Leave(player, true)
	end)
end

return Base(module, {
	{ Path = "Auth/Security", Imports = "Packet.h" },
	{ Path = "Auth/Entities", Imports = "EntityPlayer.h" },
	{ Path = "Auth/Chat", Imports = "Chat.h" },
	{ Path = "Auth/Social", Imports = "Party.h" },
	{ Path = "World/Database", Imports = "WorldDB.h" },
})
