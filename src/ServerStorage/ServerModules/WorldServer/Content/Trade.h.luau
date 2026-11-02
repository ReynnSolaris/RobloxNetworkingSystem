local Base = require(game:GetService("ServerStorage").ServerModules["Template.h"])
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Opcodes = require(ReplicatedStorage.Shared.Opcodes)
local Config = require(ReplicatedStorage.Shared.Config)
local module = {}

-- Player trade, WoW style. /trade asks the target; accepting opens both windows.
-- Each side offers bag slots and money, then accepts; changing anything clears
-- both accepts. Both accepted and both bags fit: items and money swap.
-- information[player] = trade = { A, B, Offers = { [player] = { Slots = { [i] = bagSlot }, Money, Accepted } } }

local requests: { [Player]: { From: Player, At: number } } = {}

local function nameOf(player: Player): string
	return player:GetAttribute("CharacterName") or player.Name
end

local function other(trade, player: Player): Player
	return if trade.A == player then trade.B else trade.A
end

local function say(self, player: Player, text: string)
	self.includes.Chat["Chat.h"]:System(player, text)
end

-- Both windows see both offers, described.
function module:Update(trade, status: string?)
	local Items = self.includes.Content["Items.h"]
	local Entities = self.includes.Entities["EntityPlayer.h"]
	local function offer(player)
		local o = trade.Offers[player]
		local items = {}
		for i, bagSlot in o.Slots do
			local stack = Entities:StackAt(player, bagSlot)
			if stack then
				items[tostring(i)] = Items:Describe(stack.entry, { Count = stack.count, Bag = bagSlot })
			end
		end
		return { Items = items, Money = o.Money, Accepted = o.Accepted }
	end
	for _, player in { trade.A, trade.B } do
		self.includes.Security["Packet.h"]:Send(player, Opcodes.SMSG_TRADE_STATUS,
			{ Status = status or "open", Partner = nameOf(other(trade, player)), Mine = offer(player), Theirs = offer(other(trade, player)) })
	end
end

function module:Request(player: Player, name: string?)
	local target = self.includes.Entities["EntityPlayer.h"]:FindByName(name)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local troot = target and target.Character and target.Character:FindFirstChild("HumanoidRootPart")
	if not target or target == player or not troot or not root then
		return say(self, player, "No player named " .. tostring(name))
	elseif (troot.Position - root.Position).Magnitude > Config.Trade.Range then
		return say(self, player, "You are too far away to trade.")
	elseif self.information[player] or self.information[target] then
		return say(self, player, "That player is busy.")
	elseif self.includes.Social["Social.h"]:IsIgnoring(target, player) then
		return say(self, player, nameOf(target) .. " is ignoring you.")
	end
	requests[target] = { From = player, At = os.time() }
	self.includes.Security["Packet.h"]:Send(target, Opcodes.SMSG_TRADE_STATUS, { Status = "request", Partner = nameOf(player) })
	say(self, player, ("You have requested to trade with %s."):format(nameOf(target)))
end

function module:Begin(player: Player)
	local request = requests[player]
	requests[player] = nil
	if not request or os.time() - request.At > 30 or request.From.Parent ~= Players or self.information[player] or self.information[request.From] then
		return say(self, player, "You have no trade request.")
	end
	local trade = { A = request.From, B = player, Offers = {} }
	trade.Offers[trade.A] = { Slots = {}, Money = 0, Accepted = false }
	trade.Offers[trade.B] = { Slots = {}, Money = 0, Accepted = false }
	self.information[trade.A], self.information[trade.B] = trade, trade
	self:Update(trade)
end

function module:Cancel(player: Player, reason: string?)
	local trade = self.information[player]
	requests[player] = nil
	if not trade then
		return
	end
	self.information[trade.A], self.information[trade.B] = nil, nil
	for _, p in { trade.A, trade.B } do
		if p.Parent == Players then
			self.includes.Security["Packet.h"]:Send(p, Opcodes.SMSG_TRADE_STATUS, { Status = "cancelled" })
			say(self, p, reason or "Trade cancelled.")
		end
	end
end

local function reset(trade)
	trade.Offers[trade.A].Accepted = false
	trade.Offers[trade.B].Accepted = false
end

function module:SetItem(player: Player, slot: number, bagSlot: number?)
	local trade = self.information[player]
	if not trade or slot < 1 or slot > Config.Trade.Slots then
		return
	end
	local offer = trade.Offers[player]
	if bagSlot then
		local stack = self.includes.Entities["EntityPlayer.h"]:StackAt(player, bagSlot)
		local template = stack and self.includes.Content["Items.h"]:Template(stack.entry)
		if not stack then
			return
		elseif template and template.bind == "pickup" then
			return say(self, player, "That item is soulbound.")
		end
		for i, existing in offer.Slots do
			if existing == bagSlot then
				offer.Slots[i] = nil
			end
		end
		offer.Slots[slot] = bagSlot
	else
		offer.Slots[slot] = nil
	end
	reset(trade)
	self:Update(trade)
end

function module:SetMoney(player: Player, amount: number)
	local trade = self.information[player]
	if not trade then
		return
	end
	trade.Offers[player].Money = math.clamp(math.floor(amount), 0, player:GetAttribute("Money") or 0)
	reset(trade)
	self:Update(trade)
end

function module:Accept(player: Player)
	local trade = self.information[player]
	if not trade then
		return
	end
	trade.Offers[player].Accepted = true
	local a, b = trade.Offers[trade.A], trade.Offers[trade.B]
	if not (a.Accepted and b.Accepted) then
		return self:Update(trade)
	end
	local Entities = self.includes.Entities["EntityPlayer.h"]
	local function count(o): number
		local n = 0
		for _ in o.Slots do
			n += 1
		end
		return n
	end
	local function free(p): number
		local used = 0
		for slot = 1, Config.BagSlots do
			if Entities:StackAt(p, slot) then
				used += 1
			end
		end
		return Config.BagSlots - used
	end
	if free(trade.A) + count(a) < count(b) or free(trade.B) + count(b) < count(a) then
		reset(trade)
		self:Update(trade)
		return self:Cancel(player, "A bag is full. Trade cancelled.")
	end
	if (trade.A:GetAttribute("Money") or 0) < a.Money or (trade.B:GetAttribute("Money") or 0) < b.Money then
		return self:Cancel(player, "Not enough money. Trade cancelled.")
	end
	local aItems, bItems = {}, {}
	for _, bagSlot in a.Slots do
		table.insert(aItems, Entities:TakeSlot(trade.A, bagSlot))
	end
	for _, bagSlot in b.Slots do
		table.insert(bItems, Entities:TakeSlot(trade.B, bagSlot))
	end
	for _, stack in aItems do
		if stack then
			Entities:AddItem(trade.B, stack.entry, stack.count)
		end
	end
	for _, stack in bItems do
		if stack then
			Entities:AddItem(trade.A, stack.entry, stack.count)
		end
	end
	if a.Money > 0 then
		Entities:AddMoney(trade.A, -a.Money)
		Entities:AddMoney(trade.B, a.Money)
	end
	if b.Money > 0 then
		Entities:AddMoney(trade.B, -b.Money)
		Entities:AddMoney(trade.A, b.Money)
	end
	self.information[trade.A], self.information[trade.B] = nil, nil
	for _, p in { trade.A, trade.B } do
		self.includes.Security["Packet.h"]:Send(p, Opcodes.SMSG_TRADE_STATUS, { Status = "complete" })
		say(self, p, "Trade complete.")
	end
end

function module:Start()
	local Packet = self.includes.Security["Packet.h"]
	Packet:On(Opcodes.CMSG_INITIATE_TRADE, function(player, data)
		self:Request(player, typeof(data) == "table" and data.Target or nil)
	end)
	Packet:On(Opcodes.CMSG_BEGIN_TRADE, function(player)
		self:Begin(player)
	end)
	Packet:On(Opcodes.CMSG_CANCEL_TRADE, function(player)
		local request = requests[player]
		requests[player] = nil
		if request and request.From.Parent == Players and not self.information[player] then
			say(self, request.From, nameOf(player) .. " declines your trade request.")
		end
		self:Cancel(player)
	end)
	Packet:On(Opcodes.CMSG_SET_TRADE_ITEM, function(player, data)
		if typeof(data) == "table" then
			self:SetItem(player, tonumber(data.Slot) or 0, tonumber(data.Bag))
		end
	end)
	Packet:On(Opcodes.CMSG_SET_TRADE_GOLD, function(player, data)
		if typeof(data) == "table" then
			self:SetMoney(player, tonumber(data.Amount) or 0)
		end
	end)
	Packet:On(Opcodes.CMSG_ACCEPT_TRADE, function(player)
		self:Accept(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		requests[player] = nil
		self:Cancel(player, "Trade cancelled.")
	end)
	task.spawn(function()
		while true do
			task.wait(1)
			for player, trade in self.information do
				local a, b = trade.A.Character and trade.A.Character:FindFirstChild("HumanoidRootPart"), trade.B.Character and trade.B.Character:FindFirstChild("HumanoidRootPart")
				if not a or not b or (a.Position - b.Position).Magnitude > Config.Trade.Range * 1.5 then
					self:Cancel(player, "Trade cancelled: too far away.")
				end
			end
		end
	end)
end

return Base(module, {
	{ Path = "Auth/Security", Imports = "Packet.h" },
	{ Path = "Auth/Entities", Imports = "EntityPlayer.h" },
	{ Path = "Auth/Chat", Imports = "Chat.h" },
	{ Path = "Auth/Social", Imports = "Social.h" },
	{ Path = "World/Content", Imports = "Items.h" },
})
