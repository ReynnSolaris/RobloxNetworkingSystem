local Base = require(game:GetService("ServerStorage").ServerModules["Template.h"])
local Players = game:GetService("Players")
local module = {}

-- GM tickets. Players open one with "/ticket <text>"; online staff are told and
-- handle it with .ticket list|view|reply|close. Stored under one key.

local MAX_OPEN_PER_PLAYER = 1

local function blank()
	return { Next = 1, Open = {} }
end

function module:Store()
	return self.includes.Database["Database.h"]:Open("Tickets")
end

-- Always the live value: every server edits this record.
function module:State()
	self:Store():Refresh("state")
	return self:Store():Get("state", blank())
end

function module:Open(player: Player, text: string): string
	local created
	self:Store():Transform("state", function(state)
		state = state or blank()
		for _, ticket in state.Open do
			if ticket.UserId == player.UserId then
				return state
			end
		end
		created = { Id = state.Next, UserId = player.UserId, Name = player.Name, Text = text, At = os.time() }
		state.Next += 1
		table.insert(state.Open, created)
		return state
	end)
	if not created then
		return "You already have an open ticket. A GM will get to it."
	end
	local notice = ("New ticket #%d from %s: %s"):format(created.Id, player.Name, text)
	self:NotifyStaff(notice)
	self.includes.System["Global.h"]:Publish("TICKET", { Notice = notice })
	return ("Ticket #%d submitted. A GM will respond."):format(created.Id)
end

function module:Get(id: number)
	for index, ticket in self:State().Open do
		if ticket.Id == id then
			return ticket, index
		end
	end
	return nil
end

function module:Close(id: number): boolean
	local closed
	self:Store():Transform("state", function(state)
		state = state or blank()
		for index, ticket in state.Open do
			if ticket.Id == id then
				closed = table.remove(state.Open, index)
				break
			end
		end
		return state
	end)
	if not closed then
		return false
	end
	self:Deliver(closed.UserId, ("Your ticket #%d has been closed."):format(id))
	return true
end

function module:Reply(id: number, text: string): string
	local ticket = self:Get(id)
	if not ticket then
		return "No such ticket."
	end
	self:Deliver(ticket.UserId, ("GM reply to ticket #%d: %s"):format(id, text))
	return "Reply sent."
end

-- System message to a player wherever they are: here, or via the bus.
function module:Deliver(userId: number, text: string)
	local online = Players:GetPlayerByUserId(userId)
	if online then
		self.includes.Chat["Chat.h"]:System(online, text)
	else
		self.includes.System["Global.h"]:Publish("DELIVER", { UserId = userId, Text = text })
	end
end

function module:Start()
	local Global = self.includes.System["Global.h"]
	Global:On("TICKET", function(data)
		self:NotifyStaff(tostring(data.Notice))
	end)
	Global:On("DELIVER", function(data)
		local online = Players:GetPlayerByUserId(tonumber(data.UserId) or 0)
		if online then
			self.includes.Chat["Chat.h"]:System(online, tostring(data.Text))
		end
	end)
end

function module:NotifyStaff(text: string)
	local RBAC = self.includes.Security["RBAC_Permissions.h"]
	for _, player in Players:GetPlayers() do
		if RBAC:HasLevel(player, RBAC.ROLES.MODERATOR) then
			self.includes.Chat["Chat.h"]:System(player, text)
		end
	end
end

return Base(module, {
	{ Path = "Global/Database", Imports = "Database.h" },
	{ Path = "Auth/Chat", Imports = "Chat.h" },
	{ Path = "Auth/Security", Imports = "RBAC_Permissions.h" },
	{ Path = "Global/System", Imports = "Global.h" },
})
