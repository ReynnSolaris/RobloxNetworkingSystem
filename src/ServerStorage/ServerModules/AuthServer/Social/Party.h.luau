local Base = require(game:GetService("ServerStorage").ServerModules["Template.h"])
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Opcodes = require(ReplicatedStorage.Shared.Opcodes)
local Config = require(ReplicatedStorage.Shared.Config)
local module = {}

-- WoW groups: /invite, /accept, /decline, /leave, /uninvite, /promote, and
-- /raid to convert a party into a raid of up to RaidSize in Subgroups groups
-- (/setgroup). A party is { Leader, Members, Raid, Groups = { [Player] = n } };
-- information[player] = its party.

local invites: { [Player]: { From: Player, Party: any, At: number } } = {}

local function say(self, player: Player, text: string)
	self.includes.Chat["Chat.h"]:System(player, text)
end

local function nameOf(player: Player): string
	return player:GetAttribute("CharacterName") or player.Name
end

function module:Of(player: Player)
	return self.information[player]
end

-- Everyone in the player's party, or an empty list.
function module:MembersOf(player: Player): { Player }
	local party = self.information[player]
	return if party then party.Members else {}
end

local function limit(party): number
	return if party and party.Raid then Config.Party.RaidSize else Config.Party.MaxSize
end

-- First subgroup with room, for a member joining a raid.
local function freeGroup(party): number
	local counts = {}
	for _, n in party.Groups do
		counts[n] = (counts[n] or 0) + 1
	end
	for n = 1, Config.Party.Subgroups do
		if (counts[n] or 0) < Config.Party.MaxSize then
			return n
		end
	end
	return 1
end

function module:Update(party)
	local Packet = self.includes.Security["Packet.h"]
	local names, groups = {}, {}
	for _, member in party.Members do
		table.insert(names, member.Name)
		groups[member.Name] = party.Groups[member] or 1
	end
	for _, member in party.Members do
		Packet:Send(member, Opcodes.SMSG_PARTY_UPDATE, { Leader = party.Leader.Name, Members = names, Raid = party.Raid == true, Groups = groups, LootMethod = party.LootMethod or "group", MasterLooter = party.MasterLooter and party.MasterLooter.Name })
	end
end

-- Loot method: "group" rolls on uncommon and better, "ffa" takes freely,
-- "master" leaves those items to the master looter.
function module:LootMethod(player: Player): (string, Player?)
	local party = self.information[player]
	if not party then
		return "ffa", nil
	end
	return party.LootMethod or "group", party.MasterLooter or party.Leader
end

function module:SetLootMethod(leader: Player, method: string?, name: string?)
	local party = self.information[leader]
	if not party or party.Leader ~= leader then
		return say(self, leader, "You are not the party leader.")
	elseif method ~= "group" and method ~= "ffa" and method ~= "master" then
		return say(self, leader, "Loot methods are group, ffa and master.")
	end
	party.LootMethod = method
	if method == "master" then
		local target = if name then self.includes.Entities["EntityPlayer.h"]:FindByName(name) else leader
		if not target or self.information[target] ~= party then
			return say(self, leader, tostring(name) .. " is not in your party.")
		end
		party.MasterLooter = target
	end
	local text = if method == "master" then ("Loot method set to Master Looter: %s."):format(nameOf(party.MasterLooter)) elseif method == "ffa" then "Loot method set to Free for All." else "Loot method set to Group Loot."
	for _, member in party.Members do
		say(self, member, text)
	end
	self:Update(party)
end

-- A party made for the player list (the dungeon finder), first member leads.
function module:Form(members: { Player }): any?
	local party = { Leader = members[1], Members = {}, Groups = {}, LootMethod = "group" }
	for _, member in members do
		if self.information[member] then
			self:Leave(member)
		end
		table.insert(party.Members, member)
		party.Groups[member] = 1
		self.information[member] = party
	end
	if #party.Members < 2 then
		for _, member in party.Members do
			self.information[member] = nil
		end
		return nil
	end
	for _, member in party.Members do
		say(self, member, "Your group has been formed.")
	end
	self:Update(party)
	return party
end

function module:IsRaid(player: Player): boolean
	local party = self.information[player]
	return party ~= nil and party.Raid == true
end

function module:Convert(player: Player)
	local party = self.information[player]
	if not party or party.Leader ~= player then
		return say(self, player, "You are not the party leader.")
	elseif party.Raid then
		return say(self, player, "You are already in a raid.")
	end
	party.Raid = true
	for i, member in party.Members do
		party.Groups[member] = 1
	end
	for _, member in party.Members do
		say(self, member, "Your party has been converted to a raid.")
	end
	self:Update(party)
end

function module:SetSubgroup(leader: Player, name: string?, group: number?)
	local party = self.information[leader]
	local target = self.includes.Entities["EntityPlayer.h"]:FindByName(name)
	group = math.floor(tonumber(group) or 0)
	if not party or not party.Raid or party.Leader ~= leader then
		return say(self, leader, "You are not the raid leader.")
	elseif not target or self.information[target] ~= party then
		return say(self, leader, tostring(name) .. " is not in your raid.")
	elseif group < 1 or group > Config.Party.Subgroups then
		return say(self, leader, ("Groups run 1 to %d."):format(Config.Party.Subgroups))
	end
	local count = 0
	for _, n in party.Groups do
		if n == group then
			count += 1
		end
	end
	if count >= Config.Party.MaxSize then
		return say(self, leader, "That group is full.")
	end
	party.Groups[target] = group
	self:Update(party)
end

function module:Invite(leader: Player, name: string?)
	local target = self.includes.Entities["EntityPlayer.h"]:FindByName(name)
	if not target or target == leader or self.includes.Social["Social.h"]:IsIgnoring(target, leader) then
		return say(self, leader, "No player named " .. tostring(name))
	end
	local party = self.information[leader]
	if party and party.Leader ~= leader then
		return say(self, leader, "You are not the party leader.")
	end
	if party and #party.Members >= limit(party) then
		return say(self, leader, "Your party is full.")
	end
	if self.information[target] then
		return say(self, leader, target.Name .. " is already in a group.")
	end
	invites[target] = { From = leader, Party = party, At = os.time() }
	self.includes.Security["Packet.h"]:Send(target, Opcodes.SMSG_PARTY_INVITE, { From = nameOf(leader) })
	say(self, leader, "You have invited " .. target.Name .. " to join your group.")
end

function module:Accept(player: Player)
	local invite = invites[player]
	invites[player] = nil
	if not invite or os.time() - invite.At > Config.Party.InviteSeconds or invite.From.Parent ~= Players then
		return say(self, player, "You have no pending invitation.")
	end
	local party = invite.Party or self.information[invite.From]
	if not party then
		party = { Leader = invite.From, Members = { invite.From }, Groups = {} }
		self.information[invite.From] = party
	end
	if #party.Members >= limit(party) then
		return say(self, player, "That party is full.")
	end
	table.insert(party.Members, player)
	party.Groups[player] = if party.Raid then freeGroup(party) else 1
	self.information[player] = party
	for _, member in party.Members do
		say(self, member, nameOf(player) .. " joins the party.")
	end
	self:Update(party)
end

function module:Decline(player: Player)
	local invite = invites[player]
	invites[player] = nil
	if invite and invite.From.Parent == Players then
		say(self, invite.From, player.Name .. " declines your group invitation.")
	end
end

function module:Leave(player: Player, kicked: boolean?)
	local party = self.information[player]
	if not party then
		return
	end
	self.information[player] = nil
	party.Groups[player] = nil
	local index = table.find(party.Members, player)
	if index then
		table.remove(party.Members, index)
	end
	self.includes.Security["Packet.h"]:Send(player, Opcodes.SMSG_PARTY_UPDATE, { Members = {} })
	for _, member in party.Members do
		say(self, member, nameOf(player) .. (if kicked then " has been removed from the group." else " leaves the party."))
	end
	if #party.Members <= 1 then
		for _, member in party.Members do
			self.information[member] = nil
			say(self, member, "Your group has been disbanded.")
			self.includes.Security["Packet.h"]:Send(member, Opcodes.SMSG_PARTY_UPDATE, { Members = {} })
		end
		return
	end
	if party.Leader == player then
		party.Leader = party.Members[1]
		for _, member in party.Members do
			say(self, member, nameOf(party.Leader) .. " is now the group leader.")
		end
	end
	self:Update(party)
end

function module:Uninvite(leader: Player, name: string?)
	local party = self.information[leader]
	local target = self.includes.Entities["EntityPlayer.h"]:FindByName(name)
	if not party or party.Leader ~= leader then
		return say(self, leader, "You are not the party leader.")
	end
	if not target or self.information[target] ~= party then
		return say(self, leader, tostring(name) .. " is not in your party.")
	end
	self:Leave(target, true)
end

function module:Promote(leader: Player, name: string?)
	local party = self.information[leader]
	local target = self.includes.Entities["EntityPlayer.h"]:FindByName(name)
	if not party or party.Leader ~= leader then
		return say(self, leader, "You are not the party leader.")
	end
	if not target or self.information[target] ~= party then
		return say(self, leader, tostring(name) .. " is not in your party.")
	end
	party.Leader = target
	for _, member in party.Members do
		say(self, member, nameOf(target) .. " is now the group leader.")
	end
	self:Update(party)
end

function module:Start()
	local actions = {
		invite = function(player, target) self:Invite(player, target) end,
		accept = function(player) self:Accept(player) end,
		decline = function(player) self:Decline(player) end,
		leave = function(player) self:Leave(player) end,
		uninvite = function(player, target) self:Uninvite(player, target) end,
		promote = function(player, target) self:Promote(player, target) end,
	}
	self.includes.Security["Packet.h"]:On(Opcodes.CMSG_LOOT_METHOD, function(player, data)
		if typeof(data) == "table" then
			self:SetLootMethod(player, data.Method, data.Target)
		end
	end)
	self.includes.Security["Packet.h"]:On(Opcodes.CMSG_CONVERT_RAID, function(player)
		self:Convert(player)
	end)
	self.includes.Security["Packet.h"]:On(Opcodes.CMSG_SET_SUBGROUP, function(player, data)
		if typeof(data) == "table" then
			self:SetSubgroup(player, data.Target, tonumber(data.Group))
		end
	end)
	self.includes.Security["Packet.h"]:On(Opcodes.CMSG_PARTY, function(player, data)
		local action = typeof(data) == "table" and actions[data.Action]
		if action then
			action(player, if typeof(data.Target) == "string" then data.Target else nil)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		invites[player] = nil
		self:Leave(player)
	end)
end

return Base(module, {
	{ Path = "Auth/Security", Imports = "Packet.h" },
	{ Path = "Auth/Chat", Imports = "Chat.h" },
	{ Path = "Auth/Entities", Imports = "EntityPlayer.h" },
	{ Path = "Auth/Social", Imports = "Social.h" },
})
