local Base = require(game:GetService("ServerStorage").ServerModules["Template.h"])
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Opcodes = require(ReplicatedStorage.Shared.Opcodes)
local Config = require(ReplicatedStorage.Shared.Config)
local module = {}

-- WoW groups: /invite, /accept, /decline, /leave, /uninvite, /promote. A party
-- is { Leader = Player, Members = { Player } }; information[player] = its party.

local invites: { [Player]: { From: Player, Party: any, At: number } } = {}

local function say(self, player: Player, text: string)
	self.includes.Chat["Chat.h"]:System(player, text)
end

function module:Of(player: Player)
	return self.information[player]
end

-- Everyone in the player's party, or an empty list.
function module:MembersOf(player: Player): { Player }
	local party = self.information[player]
	return if party then party.Members else {}
end

function module:Update(party)
	local Packet = self.includes.Security["Packet.h"]
	local names = {}
	for _, member in party.Members do
		table.insert(names, member.Name)
	end
	for _, member in party.Members do
		Packet:Send(member, Opcodes.SMSG_PARTY_UPDATE, { Leader = party.Leader.Name, Members = names })
	end
end

function module:Invite(leader: Player, name: string?)
	local target = name and Players:FindFirstChild(name)
	if not target or target == leader then
		return say(self, leader, "No player named " .. tostring(name))
	end
	local party = self.information[leader]
	if party and party.Leader ~= leader then
		return say(self, leader, "You are not the party leader.")
	end
	if party and #party.Members >= Config.Party.MaxSize then
		return say(self, leader, "Your party is full.")
	end
	if self.information[target] then
		return say(self, leader, target.Name .. " is already in a group.")
	end
	invites[target] = { From = leader, Party = party, At = os.time() }
	self.includes.Security["Packet.h"]:Send(target, Opcodes.SMSG_PARTY_INVITE, { From = leader.DisplayName })
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
		party = { Leader = invite.From, Members = { invite.From } }
		self.information[invite.From] = party
	end
	if #party.Members >= Config.Party.MaxSize then
		return say(self, player, "That party is full.")
	end
	table.insert(party.Members, player)
	self.information[player] = party
	for _, member in party.Members do
		say(self, member, player.Name .. " joins the party.")
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
	local index = table.find(party.Members, player)
	if index then
		table.remove(party.Members, index)
	end
	self.includes.Security["Packet.h"]:Send(player, Opcodes.SMSG_PARTY_UPDATE, { Members = {} })
	for _, member in party.Members do
		say(self, member, player.Name .. (if kicked then " has been removed from the group." else " leaves the party."))
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
			say(self, member, party.Leader.Name .. " is now the group leader.")
		end
	end
	self:Update(party)
end

function module:Uninvite(leader: Player, name: string?)
	local party = self.information[leader]
	local target = name and Players:FindFirstChild(name)
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
	local target = name and Players:FindFirstChild(name)
	if not party or party.Leader ~= leader then
		return say(self, leader, "You are not the party leader.")
	end
	if not target or self.information[target] ~= party then
		return say(self, leader, tostring(name) .. " is not in your party.")
	end
	party.Leader = target
	for _, member in party.Members do
		say(self, member, target.Name .. " is now the group leader.")
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
})
