local Base = require(game:GetService("ServerStorage").ServerModules["Template.h"])
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Opcodes = require(ReplicatedStorage.Shared.Opcodes)
local Config = require(ReplicatedStorage.Shared.Config)
local module = {}

-- Auction house, TrinityCore shaped. auctionhouse rows: { id, item, count, owner
-- (character name), ownerId, bid, buyout, bidder, bidderId, expires, deposit }.
-- Listing takes a deposit and the item; a bid holds the bidder's money and
-- returns the previous bidder's by mail; buyout or expiry mails the item to the
-- winner and the money (less the house cut) to the seller. Unsold items return
-- to the owner by mail. Reached through an auctioneer creature or object.

local function nameOf(player: Player): string
	return player:GetAttribute("CharacterName") or player.Name
end

function module:DB()
	return self.includes.Database["WorldDB.h"]
end

local function inRange(self, player: Player): boolean
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not root then
		return false
	end
	for _, state in self.includes.Content["Creatures.h"].information do
		if state.Template.auctioneer and not state.Dead and (state.Root.Position - root.Position).Magnitude <= Config.VendorRange then
			return true
		end
	end
	for _, state in self.includes.Content["GameObjects.h"].information do
		if state.Template.type == "auctioneer" and (state.Model:GetPivot().Position - root.Position).Magnitude <= Config.VendorRange then
			return true
		end
	end
	return false
end

local function describe(self, row)
	local Items = self.includes.Content["Items.h"]
	return Items:Describe(row.item, { Id = row.id, Count = row.count, Owner = row.owner, Bid = row.bid, Buyout = row.buyout, Bidder = row.bidder,
		Left = math.max(0, (row.expires or 0) - os.time()) })
end

function module:Result(player: Player, action: string, ok: boolean, reason: string?)
	self.includes.Security["Packet.h"]:Send(player, Opcodes.SMSG_AUCTION_COMMAND_RESULT, { Action = action, Ok = ok, Reason = reason })
	if reason then
		self.includes.Chat["Chat.h"]:System(player, reason)
	end
end

-- Browse: filter by name, "owner" (mine) or "bidder" (my bids).
function module:List(player: Player, data)
	if not inRange(self, player) then
		return
	end
	local filter = if typeof(data.Filter) == "string" then data.Filter:lower() else ""
	local mode = data.Mode or "browse"
	local me = nameOf(player)
	local list = {}
	for _, row in self:DB():Select("auctionhouse") do
		local info = describe(self, row)
		local keep = if mode == "owner" then row.owner == me elseif mode == "bidder" then row.bidder == me else (filter == "" or info.Name:lower():find(filter, 1, true) ~= nil)
		if keep and (row.expires or 0) > os.time() then
			table.insert(list, info)
		end
	end
	table.sort(list, function(a, b)
		return a.Left < b.Left
	end)
	self.includes.Security["Packet.h"]:Send(player, Opcodes.SMSG_AUCTION_LIST_RESULT, { Mode = mode, Items = list })
end

function module:Open(player: Player, guid)
	self:List(player, { Mode = "browse" })
	player:SetAttribute("AuctionOpen", os.clock())
end

function module:Sell(player: Player, data)
	if not inRange(self, player) then
		return
	end
	local Entities = self.includes.Entities["EntityPlayer.h"]
	local bid, buyout, hours = tonumber(data.Bid) or 0, tonumber(data.Buyout) or 0, tonumber(data.Hours) or Config.Auction.Hours[1]
	if bid <= 0 or (buyout > 0 and buyout < bid) or not table.find(Config.Auction.Hours, hours) then
		return self:Result(player, "sell", false, "That is not a valid price.")
	end
	local me = nameOf(player)
	local mine = 0
	for _, row in self:DB():Select("auctionhouse") do
		if row.owner == me then
			mine += 1
		end
	end
	if mine >= Config.Auction.MaxListings then
		return self:Result(player, "sell", false, "You have too many auctions.")
	end
	local stack = Entities:StackAt(player, tonumber(data.Bag) or 0)
	if not stack then
		return self:Result(player, "sell", false, "Nothing there.")
	end
	local template = self.includes.Content["Items.h"]:Template(stack.entry)
	if template and template.bind == "pickup" then
		return self:Result(player, "sell", false, "That item is soulbound.")
	end
	local deposit = math.max(1, math.floor(bid * Config.Auction.Deposit * (hours / 12)))
	if (player:GetAttribute("Money") or 0) < deposit then
		return self:Result(player, "sell", false, "You don't have enough money for the deposit.")
	end
	Entities:AddMoney(player, -deposit)
	Entities:TakeSlot(player, stack.slot)
	self:DB():Insert("auctionhouse", { item = stack.entry, count = stack.count, owner = me, ownerId = player.UserId, bid = bid, buyout = if buyout > 0 then buyout else nil,
		expires = os.time() + hours * 3600, deposit = deposit })
	self:Result(player, "sell", true)
	self.includes.Chat["Chat.h"]:System(player, "Auction created.")
	self:List(player, { Mode = "owner" })
end

-- Hands the item to a winner and the money to the seller.
local function settle(self, row, winner: string, winnerId: number, price: number)
	local Mail = self.includes.Mail["Mail.h"]
	local Items = self.includes.Content["Items.h"]
	local name = (Items:Template(row.item) or {}).name or "item"
	Mail:Deliver(winner, { Sender = "Auction House", Subject = ("Auction won: %s"):format(name), Body = "You won this item at auction.", Items = { { Entry = row.item, Count = row.count } }, Money = 0 })
	local cut = math.floor(price * Config.Auction.Cut)
	Mail:Deliver(row.owner, { Sender = "Auction House", Subject = ("Auction successful: %s"):format(name),
		Body = ("Your item sold to %s for %d copper. The house took %d and your deposit of %d is returned."):format(winner, price, cut, row.deposit or 0), Items = {}, Money = price - cut + (row.deposit or 0) })
	self:DB():Delete("auctionhouse", row.id)
end

function module:Bid(player: Player, data)
	if not inRange(self, player) then
		return
	end
	local Entities = self.includes.Entities["EntityPlayer.h"]
	local Mail = self.includes.Mail["Mail.h"]
	local row = self:DB():Get("auctionhouse", tonumber(data.Id) or 0)
	local amount = tonumber(data.Amount) or 0
	local me = nameOf(player)
	if not row or (row.expires or 0) <= os.time() then
		return self:Result(player, "bid", false, "That auction is gone.")
	elseif row.owner == me then
		return self:Result(player, "bid", false, "You cannot bid on your own auction.")
	elseif row.bidder == me then
		return self:Result(player, "bid", false, "You are already the high bidder.")
	end
	local minimum = if row.bidder then math.floor(row.bid * 1.05) + 1 else row.bid
	local buyout = row.buyout and amount >= row.buyout
	if not buyout and amount < minimum then
		return self:Result(player, "bid", false, ("The minimum bid is %d copper."):format(minimum))
	end
	if buyout then
		amount = row.buyout
	end
	if (player:GetAttribute("Money") or 0) < amount then
		return self:Result(player, "bid", false, "You don't have enough money.")
	end
	Entities:AddMoney(player, -amount)
	if row.bidder then
		Mail:Deliver(row.bidder, { Sender = "Auction House", Subject = "Outbid", Body = ("You were outbid on an auction. Your bid of %d copper is returned."):format(row.bid), Items = {}, Money = row.bid })
	end
	if buyout then
		settle(self, row, me, player.UserId, amount)
		self:Result(player, "buyout", true)
		self.includes.Chat["Chat.h"]:System(player, "You won the auction. The item is in your mail.")
	else
		self:DB():Update("auctionhouse", row.id, { bid = amount, bidder = me, bidderId = player.UserId })
		self:Result(player, "bid", true)
		self.includes.Chat["Chat.h"]:System(player, "Bid accepted.")
	end
	self:List(player, { Mode = data.Mode or "browse", Filter = data.Filter })
end

function module:Cancel(player: Player, data)
	if not inRange(self, player) then
		return
	end
	local row = self:DB():Get("auctionhouse", tonumber(data.Id) or 0)
	local me = nameOf(player)
	if not row or row.owner ~= me then
		return self:Result(player, "cancel", false, "That is not your auction.")
	end
	local Mail = self.includes.Mail["Mail.h"]
	if row.bidder then
		Mail:Deliver(row.bidder, { Sender = "Auction House", Subject = "Auction cancelled", Body = "The seller cancelled the auction. Your bid is returned.", Items = {}, Money = row.bid })
	end
	Mail:Deliver(me, { Sender = "Auction House", Subject = "Auction cancelled", Body = "Your item is returned. The deposit is forfeit.", Items = { { Entry = row.item, Count = row.count } }, Money = 0 })
	self:DB():Delete("auctionhouse", row.id)
	self:Result(player, "cancel", true)
	self:List(player, { Mode = "owner" })
end

-- Expired auctions go to the high bidder, or back to the owner.
function module:Expire()
	local Mail = self.includes.Mail["Mail.h"]
	for _, row in self:DB():Select("auctionhouse") do
		if (row.expires or 0) <= os.time() then
			if row.bidder then
				settle(self, row, row.bidder, row.bidderId, row.bid)
			else
				Mail:Deliver(row.owner, { Sender = "Auction House", Subject = "Auction expired", Body = "Your item did not sell and is returned.", Items = { { Entry = row.item, Count = row.count } }, Money = 0 })
				self:DB():Delete("auctionhouse", row.id)
			end
		end
	end
end

function module:Start()
	local Packet = self.includes.Security["Packet.h"]
	Packet:On(Opcodes.CMSG_AUCTION_LIST_ITEMS, function(player, data)
		if typeof(data) == "table" then self:List(player, data) end
	end)
	Packet:On(Opcodes.CMSG_AUCTION_SELL_ITEM, function(player, data)
		if typeof(data) == "table" then self:Sell(player, data) end
	end)
	Packet:On(Opcodes.CMSG_AUCTION_PLACE_BID, function(player, data)
		if typeof(data) == "table" then self:Bid(player, data) end
	end)
	Packet:On(Opcodes.CMSG_AUCTION_REMOVE_ITEM, function(player, data)
		if typeof(data) == "table" then self:Cancel(player, data) end
	end)
	task.spawn(function()
		while true do
			task.wait(60)
			self:Expire()
		end
	end)
end

return Base(module, {
	{ Path = "Auth/Security", Imports = "Packet.h" },
	{ Path = "Auth/Entities", Imports = "EntityPlayer.h" },
	{ Path = "Auth/Chat", Imports = "Chat.h" },
	{ Path = "World/Mail", Imports = "Mail.h" },
	{ Path = "World/Content", Imports = "Items.h|Creatures.h|GameObjects.h" },
	{ Path = "World/Database", Imports = "WorldDB.h" },
})
