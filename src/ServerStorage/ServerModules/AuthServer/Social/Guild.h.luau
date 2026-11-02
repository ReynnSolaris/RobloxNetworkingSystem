local Base = require(game:GetService("ServerStorage").ServerModules["Template.h"])
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Opcodes = require(ReplicatedStorage.Shared.Opcodes)
local Config = require(ReplicatedStorage.Shared.Config)
local module = {}

-- TC guild and guild_member in one record per guild on the World store:
-- "guild:<id>" = { Id, Name, Leader, Motd, Members = { [lowername] = { Name, Rank, Joined } } }
-- with "guildnames" = { [lowername] = id } for uniqueness. A character keeps its
-- guild id in Guild. Ranks: 0 Guild Master, 1 Officer, 2 Member.

local RANKS = { [0] = "Guild Master", [1] = "Officer", [2] = "Member" }
local invites: { [Player]: { Guild: string, From: string, At: number } } = {}

local function key(id: string): string
	return "guild:" .. id
end

local function nameOf(player: Player): string
	return player:GetAttribute("CharacterName") or player.Name
end

function module:Store()
	return self.includes.Database["Database.h"]:Open("World")
end

local function char(self, player: Player)
	local entity = self.includes.Entities["EntityPlayer.h"]:Get(player)
	return entity and entity.Active
end

local function say(self, player: Player, text: string)
	self.includes.Chat["Chat.h"]:System(player, text)
end

function module:Load(id: string?)
	if not id then
		return nil
	end
	self:Store():Refresh(key(id))
	local guild = self:Store():Get(key(id), nil)
	return if guild and guild.Name then guild else nil
end

function module:Edit(id: string, fn: (any) -> any)
	return self:Store():Transform(key(id), fn)
end

-- The player's guild, forgetting a membership that no longer exists.
function module:Of(player: Player)
	local c = char(self, player)
	if not c or not c.Guild then
		return nil
	end
	local guild = self:Load(c.Guild)
	if not guild or not guild.Members[c.Name:lower()] then
		c.Guild = nil
		self.includes.Database["WorldDatabase.h"]:Commit(player)
		return nil
	end
	return guild
end

function module:Rank(player: Player, guild): number?
	local c = char(self, player)
	local member = c and guild and guild.Members[c.Name:lower()]
	return member and member.Rank
end

function module:Online(player: Player): { Player }
	local guild = self:Of(player)
	local out = {}
	if guild then
		for _, other in Players:GetPlayers() do
			local name = other:GetAttribute("CharacterName")
			if name and guild.Members[name:lower()] then
				table.insert(out, other)
			end
		end
	end
	return out
end

function module:Event(guild, text: string)
	for _, other in Players:GetPlayers() do
		local name = other:GetAttribute("CharacterName")
		if name and guild.Members[name:lower()] then
			self.includes.Security["Packet.h"]:Send(other, Opcodes.SMSG_GUILD_EVENT, { Text = text })
		end
	end
end

function module:Roster(player: Player)
	local guild = self:Of(player)
	if not guild then
		player:SetAttribute("Guild", nil)
		player:SetAttribute("GuildRank", nil)
		return self.includes.Security["Packet.h"]:Send(player, Opcodes.SMSG_GUILD_ROSTER, {})
	end
	local Zones = self.includes.Zones["Zones.h"]
	local members = {}
	for _, member in guild.Members do
		local other
		for _, p in Players:GetPlayers() do
			if (p:GetAttribute("CharacterName") or ""):lower() == member.Name:lower() then
				other = p
			end
		end
		local zone = other and Zones:Current(other)
		table.insert(members, { Name = member.Name, Rank = member.Rank, RankName = RANKS[member.Rank] or "Member", Online = other ~= nil,
			Level = other and other:GetAttribute("CharacterLevel"), Class = other and other:GetAttribute("CharacterClass"), Zone = zone and zone.Name })
	end
	table.sort(members, function(a, b)
		if a.Online ~= b.Online then
			return a.Online
		elseif a.Rank ~= b.Rank then
			return a.Rank < b.Rank
		end
		return a.Name < b.Name
	end)
	local rank = self:Rank(player, guild)
	player:SetAttribute("Guild", guild.Name)
	player:SetAttribute("GuildRank", RANKS[rank] or "Member")
	self.includes.Security["Packet.h"]:Send(player, Opcodes.SMSG_GUILD_ROSTER, { Id = guild.Id, Name = guild.Name, Motd = guild.Motd or "", Rank = rank, Members = members })
end

-- Everyone online in the guild gets a fresh roster.
function module:Refresh(guild)
	for _, other in Players:GetPlayers() do
		local name = other:GetAttribute("CharacterName")
		if name and guild.Members[name:lower()] then
			self:Roster(other)
		end
	end
end

function module:Create(player: Player, name: string?)
	local c = char(self, player)
	if not c then
		return
	end
	if self:Of(player) then
		return say(self, player, "You are already in a guild.")
	end
	name = typeof(name) == "string" and name:gsub("^%s+", ""):gsub("%s+$", "") or ""
	if #name < 2 or #name > 24 or not name:match("^[%a][%a ]*$") then
		return say(self, player, "Guild names are 2 to 24 letters and spaces.")
	end
	if (c.Money or 0) < Config.Guild.CreateCost then
		return say(self, player, "You don't have enough money to found a guild.")
	end
	local taken = false
	local id = ("%d%03d"):format(os.time(), math.random(0, 999))
	self:Store():Transform("guildnames", function(index)
		index = index or {}
		if index[name:lower()] then
			taken = true
		else
			index[name:lower()] = id
		end
		return index
	end)
	if taken then
		return say(self, player, "That guild name is already taken.")
	end
	local guild = { Id = id, Name = name, Leader = c.Name, Motd = "", Created = os.time(), Members = { [c.Name:lower()] = { Name = c.Name, Rank = 0, Joined = os.time() } } }
	self:Store():Set(key(id), guild)
	c.Guild = id
	self.includes.Entities["EntityPlayer.h"]:AddMoney(player, -Config.Guild.CreateCost)
	self.includes.Database["WorldDatabase.h"]:Commit(player)
	say(self, player, ("You have founded the guild <%s>."):format(name))
	self:Roster(player)
end

local function findOnline(name: string?): Player?
	if typeof(name) ~= "string" then
		return nil
	end
	for _, p in Players:GetPlayers() do
		if (p:GetAttribute("CharacterName") or ""):lower() == name:lower() then
			return p
		end
	end
	return nil
end

function module:Invite(player: Player, name: string?)
	local guild = self:Of(player)
	if not guild then
		return say(self, player, "You are not in a guild.")
	end
	if (self:Rank(player, guild) or 2) > 1 then
		return say(self, player, "You don't have permission to do that.")
	end
	local target = findOnline(name)
	if not target or target == player then
		return say(self, player, "Player not found.")
	end
	if self:Of(target) then
		return say(self, player, nameOf(target) .. " is already in a guild.")
	end
	local count = 0
	for _ in guild.Members do
		count += 1
	end
	if count >= Config.Guild.MaxMembers then
		return say(self, player, "Your guild is full.")
	end
	invites[target] = { Guild = guild.Id, From = nameOf(player), At = os.time() }
	self.includes.Security["Packet.h"]:Send(target, Opcodes.SMSG_GUILD_INVITE, { From = nameOf(player), Guild = guild.Name })
	say(self, player, ("You have invited %s to join your guild."):format(nameOf(target)))
end

function module:Accept(player: Player)
	local invite = invites[player]
	invites[player] = nil
	local c = char(self, player)
	if not invite or not c or os.time() - invite.At > Config.Guild.InviteSeconds then
		return say(self, player, "You have no pending guild invitation.")
	end
	if self:Of(player) then
		return say(self, player, "You are already in a guild.")
	end
	local guild = self:Edit(invite.Guild, function(g)
		if g and g.Name then
			g.Members[c.Name:lower()] = { Name = c.Name, Rank = 2, Joined = os.time() }
		end
		return g
	end)
	if not guild or not guild.Name then
		return say(self, player, "That guild no longer exists.")
	end
	c.Guild = guild.Id
	self.includes.Database["WorldDatabase.h"]:Commit(player)
	say(self, player, ("Welcome to <%s>."):format(guild.Name))
	self:Event(guild, ("%s has joined the guild."):format(c.Name))
	self:Refresh(guild)
end

function module:Decline(player: Player)
	local invite = invites[player]
	invites[player] = nil
	if invite then
		local from = findOnline(invite.From)
		if from then
			say(self, from, nameOf(player) .. " declines your guild invitation.")
		end
	end
end

local function removeMember(self, guild, name: string)
	return self:Edit(guild.Id, function(g)
		if g and g.Members then
			g.Members[name:lower()] = nil
		end
		return g
	end)
end

function module:Leave(player: Player)
	local guild = self:Of(player)
	local c = char(self, player)
	if not guild or not c then
		return say(self, player, "You are not in a guild.")
	end
	local count = 0
	for _ in guild.Members do
		count += 1
	end
	if self:Rank(player, guild) == 0 and count > 1 then
		return say(self, player, "You must promote another member to Guild Master first.")
	end
	if count == 1 then
		return self:Disband(player)
	end
	guild = removeMember(self, guild, c.Name)
	c.Guild = nil
	self.includes.Database["WorldDatabase.h"]:Commit(player)
	say(self, player, ("You are no longer a member of <%s>."):format(guild.Name))
	self:Event(guild, ("%s has left the guild."):format(c.Name))
	self:Roster(player)
	self:Refresh(guild)
end

function module:Kick(player: Player, name: string?)
	local guild = self:Of(player)
	local rank = self:Rank(player, guild)
	local member = guild and typeof(name) == "string" and guild.Members[name:lower()]
	if not member then
		return say(self, player, "Player not found in your guild.")
	end
	if not rank or rank > 1 or member.Rank <= rank then
		return say(self, player, "You don't have permission to do that.")
	end
	guild = removeMember(self, guild, member.Name)
	local target = findOnline(member.Name)
	if target and char(self, target) then
		char(self, target).Guild = nil
		self.includes.Database["WorldDatabase.h"]:Commit(target)
		self:Roster(target)
	end
	self:Event(guild, ("%s has been kicked out of the guild by %s."):format(member.Name, nameOf(player)))
	self:Refresh(guild)
end

function module:SetRank(player: Player, name: string?, delta: number)
	local guild = self:Of(player)
	local rank = self:Rank(player, guild)
	local member = guild and typeof(name) == "string" and guild.Members[name:lower()]
	if not member then
		return say(self, player, "Player not found in your guild.")
	end
	if rank ~= 0 or member.Rank == 0 then
		return say(self, player, "You don't have permission to do that.")
	end
	local newRank = math.clamp(member.Rank + delta, 1, 2)
	if newRank == member.Rank then
		return say(self, player, if delta < 0 then member.Name .. " cannot be promoted further." else member.Name .. " cannot be demoted further.")
	end
	guild = self:Edit(guild.Id, function(g)
		g.Members[member.Name:lower()].Rank = newRank
		return g
	end)
	self:Event(guild, ("%s has %s %s to %s."):format(nameOf(player), if delta < 0 then "promoted" else "demoted", member.Name, RANKS[newRank]))
	self:Refresh(guild)
end

function module:SetLeader(player: Player, name: string?)
	local guild = self:Of(player)
	local c = char(self, player)
	local member = guild and typeof(name) == "string" and guild.Members[name:lower()]
	if not member or not c then
		return say(self, player, "Player not found in your guild.")
	end
	if self:Rank(player, guild) ~= 0 or member.Name == c.Name then
		return say(self, player, "You don't have permission to do that.")
	end
	guild = self:Edit(guild.Id, function(g)
		g.Members[c.Name:lower()].Rank = 1
		g.Members[member.Name:lower()].Rank = 0
		g.Leader = member.Name
		return g
	end)
	self:Event(guild, ("%s has made %s the new Guild Master."):format(c.Name, member.Name))
	self:Refresh(guild)
end

function module:Motd(player: Player, text: string?)
	local guild = self:Of(player)
	if not guild or (self:Rank(player, guild) or 2) > 1 then
		return say(self, player, "You don't have permission to do that.")
	end
	local motd = self.includes.Chat["ChatFunctions.h"]:Filter(player, (typeof(text) == "string" and text or ""):sub(1, 128))
	guild = self:Edit(guild.Id, function(g)
		g.Motd = motd
		return g
	end)
	self:Event(guild, "Guild Message of the Day: " .. motd)
	self:Refresh(guild)
end

function module:Disband(player: Player)
	local guild = self:Of(player)
	if not guild or self:Rank(player, guild) ~= 0 then
		return say(self, player, "You don't have permission to do that.")
	end
	self:Event(guild, ("<%s> has been disbanded."):format(guild.Name))
	local members = guild.Members
	self:Store():Set(key(guild.Id), { Disbanded = true })
	self:Store():Transform("guildnames", function(index)
		index = index or {}
		index[guild.Name:lower()] = nil
		return index
	end)
	for name in members do
		local other = findOnline(name)
		if other then
			local c = char(self, other)
			if c then
				c.Guild = nil
				self.includes.Database["WorldDatabase.h"]:Commit(other)
			end
			self:Roster(other)
		end
	end
end

-- Guild bank: a slotted vault and money on the guild record. Members deposit,
-- officers and the guild master withdraw.
function module:SendBank(player: Player, open: boolean?)
	local guild = self:Of(player)
	if not guild then
		return say(self, player, "You are not in a guild.")
	end
	local Items = self.includes.Content["Items.h"]
	local items = {}
	for slot, stack in (guild.Bank or {}) do
		table.insert(items, Items:Describe(stack.entry, { Bank = tonumber(slot), Count = stack.count }))
	end
	local rank = self:Rank(player, guild) or 2
	self.includes.Security["Packet.h"]:Send(player, Opcodes.SMSG_GUILD_BANK_LIST, { Guild = guild.Name, Items = items, Money = guild.Money or 0, Slots = Config.GuildBank.Slots, CanWithdraw = rank <= 1, Open = open == true })
end

function module:Bank(player: Player, data)
	local guild = self:Of(player)
	local Entities = self.includes.Entities["EntityPlayer.h"]
	if not guild then
		return say(self, player, "You are not in a guild.")
	end
	local rank = self:Rank(player, guild) or 2
	local action = data.Action
	local id = guild.Id
	if action == "open" then
		return self:SendBank(player, true)
	elseif action == "deposit" then
		local stack = Entities:StackAt(player, tonumber(data.Bag) or 0)
		if not stack then
			return
		end
		local template = self.includes.Content["Items.h"]:Template(stack.entry)
		if template and template.bind == "pickup" then
			return say(self, player, "That item is soulbound.")
		end
		local placed = false
		self:Edit(id, function(g)
			g.Bank = g.Bank or {}
			local slot = tonumber(data.Slot)
			if not slot or g.Bank[tostring(slot)] then
				slot = nil
				for i = 1, Config.GuildBank.Slots do
					if not g.Bank[tostring(i)] then
						slot = i
						break
					end
				end
			end
			if slot then
				g.Bank[tostring(slot)] = { entry = stack.entry, count = stack.count }
				placed = true
			end
			return g
		end)
		if not placed then
			return say(self, player, "The guild vault is full.")
		end
		Entities:TakeSlot(player, stack.slot)
		self:Event(self:Load(id), ("%s deposited %s into the guild vault."):format(nameOf(player), (template and template.name) or "an item"))
	elseif action == "withdraw" then
		if rank > 1 then
			return say(self, player, "Only officers may withdraw from the guild vault.")
		end
		local taken
		self:Edit(id, function(g)
			g.Bank = g.Bank or {}
			taken = g.Bank[tostring(tonumber(data.Slot) or 0)]
			g.Bank[tostring(tonumber(data.Slot) or 0)] = nil
			return g
		end)
		if taken and not Entities:AddItem(player, taken.entry, taken.count) then
			self:Edit(id, function(g)
				g.Bank[tostring(tonumber(data.Slot) or 0)] = taken
				return g
			end)
		end
	elseif action == "depositmoney" then
		local amount = math.clamp(math.floor(tonumber(data.Amount) or 0), 0, player:GetAttribute("Money") or 0)
		if amount <= 0 then
			return
		end
		Entities:AddMoney(player, -amount)
		self:Edit(id, function(g)
			g.Money = (g.Money or 0) + amount
			return g
		end)
	elseif action == "withdrawmoney" then
		if rank > 1 then
			return say(self, player, "Only officers may withdraw from the guild vault.")
		end
		local amount = math.floor(tonumber(data.Amount) or 0)
		local ok = false
		self:Edit(id, function(g)
			if amount > 0 and (g.Money or 0) >= amount then
				g.Money -= amount
				ok = true
			end
			return g
		end)
		if ok then
			Entities:AddMoney(player, amount)
		end
	end
	for _, member in self:Online(player) do
		self:SendBank(member)
	end
end

function module:OnLogin(player: Player)
	local guild = self:Of(player)
	self:Roster(player)
	if guild then
		if (guild.Motd or "") ~= "" then
			self.includes.Security["Packet.h"]:Send(player, Opcodes.SMSG_GUILD_EVENT, { Text = "Guild Message of the Day: " .. guild.Motd })
		end
		self:Event(guild, ("%s has come online."):format(nameOf(player)))
		self:Refresh(guild)
	end
end

function module:OnLogout(player: Player)
	local guild = char(self, player) and self:Of(player)
	player:SetAttribute("Guild", nil)
	player:SetAttribute("GuildRank", nil)
	if guild then
		local name = nameOf(player)
		for _, other in Players:GetPlayers() do
			local n = other:GetAttribute("CharacterName")
			if other ~= player and n and guild.Members[n:lower()] then
				self.includes.Security["Packet.h"]:Send(other, Opcodes.SMSG_GUILD_EVENT, { Text = ("%s has gone offline."):format(name) })
			end
		end
	end
end

function module:Start()
	local actions = {
		create = function(player, data) self:Create(player, data.Text or data.Target) end,
		invite = function(player, data) self:Invite(player, data.Target) end,
		accept = function(player) self:Accept(player) end,
		decline = function(player) self:Decline(player) end,
		leave = function(player) self:Leave(player) end,
		kick = function(player, data) self:Kick(player, data.Target) end,
		promote = function(player, data) self:SetRank(player, data.Target, -1) end,
		demote = function(player, data) self:SetRank(player, data.Target, 1) end,
		leader = function(player, data) self:SetLeader(player, data.Target) end,
		motd = function(player, data) self:Motd(player, data.Text) end,
		disband = function(player) self:Disband(player) end,
		roster = function(player) self:Roster(player) end,
	}
	self.includes.Security["Packet.h"]:On(Opcodes.CMSG_GUILD_BANK, function(player, data)
		if typeof(data) == "table" then
			self:Bank(player, data)
		end
	end)
	self.includes.Security["Packet.h"]:On(Opcodes.CMSG_GUILD, function(player, data)
		local action = typeof(data) == "table" and actions[data.Action]
		if action then
			action(player, data)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		invites[player] = nil
		self:OnLogout(player)
	end)
end

return Base(module, {
	{ Path = "World/Content", Imports = "Items.h" },
	{ Path = "Auth/Security", Imports = "Packet.h" },
	{ Path = "Auth/Entities", Imports = "EntityPlayer.h" },
	{ Path = "Auth/Chat", Imports = "Chat.h|ChatFunctions.h" },
	{ Path = "World/Zones", Imports = "Zones.h" },
	{ Path = "World/Database", Imports = "WorldDatabase.h" },
	{ Path = "Global/Database", Imports = "Database.h" },
})
