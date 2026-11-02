local Base = require(game:GetService("ServerStorage").ServerModules["Template.h"])
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Opcodes = require(ReplicatedStorage.Shared.Opcodes)
local Config = require(ReplicatedStorage.Shared.Config)
local module = {}

-- TC's mail table, one record per character name: "mail:<name>" holds a list of
-- { Id, Sender, Subject, Body, Money, Items = { { Entry, Count } }, Sent, Read }.
-- Letters are written with Transform so two servers can deliver at once. Mail is
-- read at a mailbox (gameobject_template.type == "mailbox") and sent from one.

local function key(name: string): string
	return "mail:" .. name:lower()
end

function module:Store()
	return self.includes.Database["Database.h"]:Open("World")
end

local function nameOf(player: Player): string
	return player:GetAttribute("CharacterName") or player.Name
end

local function online(name: string): Player?
	for _, player in Players:GetPlayers() do
		if (player:GetAttribute("CharacterName") or ""):lower() == name:lower() then
			return player
		end
	end
	return nil
end

-- current letters, expired ones dropped
function module:Box(name: string)
	local store = self:Store()
	store:Refresh(key(name))
	local list = store:Get(key(name), {})
	local cutoff = os.time() - Config.Mail.ExpireDays * 86400
	local live = {}
	for _, mail in list do
		if (mail.Sent or 0) >= cutoff then
			table.insert(live, mail)
		end
	end
	if #live ~= #list then
		store:Set(key(name), live)
	end
	table.sort(live, function(a, b)
		return (a.Sent or 0) > (b.Sent or 0)
	end)
	return live
end

function module:Edit(name: string, fn: (any) -> any)
	return self:Store():Transform(key(name), function(list)
		return fn(list or {})
	end)
end

function module:Deliver(name: string, mail)
	mail.Id = ("%d%03d"):format(os.time(), math.random(0, 999))
	mail.Sent = os.time()
	mail.Read = false
	self:Edit(name, function(list)
		table.insert(list, mail)
		return list
	end)
	local recipient = online(name)
	if recipient then
		self.includes.Security["Packet.h"]:Send(recipient, Opcodes.SMSG_RECEIVED_MAIL, { From = mail.Sender, Subject = mail.Subject })
	end
end

local function describe(self, mail)
	local DB = self.includes.Database["WorldDB.h"]
	local items = {}
	for _, stack in (mail.Items or {}) do
		local template = DB:Get("item_template", stack.Entry) or {}
		table.insert(items, { Entry = stack.Entry, Count = stack.Count, Name = template.name or "?", Quality = template.quality or 1,
			Slot = template.slot, Class = template.class, Level = template.level, Health = template.health, Damage = template.damage, Armor = template.armor })
	end
	return { Id = mail.Id, Sender = mail.Sender, Subject = mail.Subject, Body = mail.Body, Money = mail.Money or 0, Items = items, Sent = mail.Sent, Read = mail.Read == true }
end

function module:List(player: Player, guid)
	local list = {}
	for _, mail in self:Box(nameOf(player)) do
		table.insert(list, describe(self, mail))
	end
	self.includes.Security["Packet.h"]:Send(player, Opcodes.SMSG_MAIL_LIST_RESULT, { Guid = guid and tostring(guid), Mails = list })
end

-- Mailbox prompt
function module:Open(player: Player, guid)
	local entity = self.includes.Entities["EntityPlayer.h"]:Get(player)
	if entity and entity.Active then
		self:List(player, guid)
	end
end

local function nearMailbox(self, player: Player, guid): boolean
	local model = self.includes.Content["GameObjects.h"]:Find(guid)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	return model ~= nil and root ~= nil and (model:GetPivot().Position - root.Position).Magnitude <= Config.Mail.MailboxRange
end

function module:Result(player: Player, ok: boolean, reason: string?)
	self.includes.Security["Packet.h"]:Send(player, Opcodes.SMSG_SEND_MAIL_RESULT, { Ok = ok, Reason = reason })
	if reason then
		self.includes.Chat["Chat.h"]:System(player, reason)
	end
end

function module:Send(player: Player, data)
	local Entities = self.includes.Entities["EntityPlayer.h"]
	local entity = Entities:Get(player)
	local c = entity and entity.Active
	if not c or not nearMailbox(self, player, data.Guid) then
		return self:Result(player, false, "You are too far from a mailbox.")
	end
	local target = self.includes.Database["WorldDatabase.h"]:LookupName(typeof(data.To) == "string" and data.To or nil)
	if not target then
		return self:Result(player, false, "Recipient not found.")
	end
	local subject = (typeof(data.Subject) == "string" and data.Subject or ""):sub(1, 64)
	local body = (typeof(data.Body) == "string" and data.Body or ""):sub(1, 500)
	local money = math.max(0, math.floor(tonumber(data.Money) or 0))
	local slots = if typeof(data.Items) == "table" then data.Items else {}
	if #slots > Config.Mail.Attachments then
		return self:Result(player, false, "Too many attachments.")
	end
	if #subject == 0 then
		return self:Result(player, false, "Your letter needs a subject.")
	end
	local cost = Config.Mail.Postage + money
	if (c.Money or 0) < cost then
		return self:Result(player, false, "Not enough money.")
	end
	for _, slot in slots do
		if not Entities:StackAt(player, tonumber(slot) or 0) then
			return self:Result(player, false, "One of the attached items is gone.")
		end
	end
	local Filter = self.includes.Chat["ChatFunctions.h"]
	local items = {}
	for _, slot in slots do
		local stack = Entities:TakeSlot(player, tonumber(slot))
		table.insert(items, { Entry = stack.entry, Count = stack.count })
	end
	Entities:AddMoney(player, -cost)
	self:Deliver(target.Name, { Sender = nameOf(player), Subject = Filter:Filter(player, subject), Body = Filter:Filter(player, body), Money = money, Items = items })
	self:Result(player, true)
	self.includes.Chat["Chat.h"]:System(player, "Your mail has been sent.")
	Entities:SendInventory(player, false)
end

local function find(list, id)
	for i, mail in list do
		if mail.Id == id then
			return i, mail
		end
	end
	return nil
end

function module:TakeMoney(player: Player, id, guid)
	local Entities = self.includes.Entities["EntityPlayer.h"]
	local taken = 0
	self:Edit(nameOf(player), function(list)
		local _, mail = find(list, id)
		if mail and (mail.Money or 0) > 0 then
			taken = mail.Money
			mail.Money = 0
		end
		return list
	end)
	if taken > 0 then
		Entities:AddMoney(player, taken)
	end
	self:List(player, guid)
end

function module:TakeItem(player: Player, id, index, guid)
	local Entities = self.includes.Entities["EntityPlayer.h"]
	local name = nameOf(player)
	local list = self:Box(name)
	local _, mail = find(list, id)
	local stack = mail and mail.Items and mail.Items[tonumber(index) or 0]
	if not stack then
		return
	end
	if not Entities:AddItem(player, stack.Entry, stack.Count) then
		return
	end
	self:Edit(name, function(current)
		local _, m = find(current, id)
		if m and m.Items then
			for i, s in m.Items do
				if s.Entry == stack.Entry and s.Count == stack.Count then
					table.remove(m.Items, i)
					break
				end
			end
		end
		return current
	end)
	self:List(player, guid)
end

function module:Delete(player: Player, id, guid)
	local blocked = false
	self:Edit(nameOf(player), function(list)
		local i, mail = find(list, id)
		if mail then
			if (mail.Money or 0) > 0 or (mail.Items and #mail.Items > 0) then
				blocked = true
			else
				table.remove(list, i)
			end
		end
		return list
	end)
	if blocked then
		self.includes.Chat["Chat.h"]:System(player, "Take the attachments before deleting the letter.")
	end
	self:List(player, guid)
end

function module:MarkRead(player: Player, id)
	self:Edit(nameOf(player), function(list)
		local _, mail = find(list, id)
		if mail then
			mail.Read = true
		end
		return list
	end)
end

function module:OnLogin(player: Player)
	local unread = 0
	for _, mail in self:Box(nameOf(player)) do
		if not mail.Read then
			unread += 1
		end
	end
	if unread > 0 then
		self.includes.Security["Packet.h"]:Send(player, Opcodes.SMSG_RECEIVED_MAIL, { Unread = unread })
	end
end

function module:Start()
	local Packet = self.includes.Security["Packet.h"]
	Packet:On(Opcodes.CMSG_SEND_MAIL, function(player, data)
		if typeof(data) == "table" then self:Send(player, data) end
	end)
	Packet:On(Opcodes.CMSG_GET_MAIL_LIST, function(player, data)
		self:List(player, typeof(data) == "table" and data.Guid or nil)
	end)
	Packet:On(Opcodes.CMSG_MAIL_TAKE_MONEY, function(player, data)
		if typeof(data) == "table" then self:TakeMoney(player, tostring(data.Id), data.Guid) end
	end)
	Packet:On(Opcodes.CMSG_MAIL_TAKE_ITEM, function(player, data)
		if typeof(data) == "table" then self:TakeItem(player, tostring(data.Id), data.Index, data.Guid) end
	end)
	Packet:On(Opcodes.CMSG_MAIL_DELETE, function(player, data)
		if typeof(data) == "table" then self:Delete(player, tostring(data.Id), data.Guid) end
	end)
	Packet:On(Opcodes.CMSG_MAIL_MARK_AS_READ, function(player, data)
		if typeof(data) == "table" then self:MarkRead(player, tostring(data.Id)) end
	end)
end

return Base(module, {
	{ Path = "Auth/Security", Imports = "Packet.h" },
	{ Path = "Auth/Entities", Imports = "EntityPlayer.h" },
	{ Path = "Auth/Chat", Imports = "Chat.h|ChatFunctions.h" },
	{ Path = "World/Content", Imports = "GameObjects.h" },
	{ Path = "World/Database", Imports = "WorldDB.h|WorldDatabase.h" },
	{ Path = "Global/Database", Imports = "Database.h" },
})
