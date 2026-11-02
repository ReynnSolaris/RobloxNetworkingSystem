local Base = require(game:GetService("ServerStorage").ServerModules["Template.h"])
local Players = game:GetService("Players")
local module = {}

-- Account records keyed by UserId: FirstSeen, LastSeen, Logins, Name, Role?, Banned?

local function key(userId: number): string
	return "account:" .. userId
end

local function blank()
	return { FirstSeen = os.time(), Logins = 0 }
end

function module:Store()
	return self.includes.Database["Database.h"]:Open("Auth")
end

function module:Load(player: Player)
	local account = self:Store():Get(key(player.UserId), blank())
	account.Logins += 1
	account.LastSeen = os.time()
	account.Name = player.Name
	self:Store():Set(key(player.UserId), account)
	self.information[player.UserId] = account
	return account
end

function module:Get(player: Player)
	return self.information[player.UserId]
end

-- Writes the record and drops it from memory. Called when the player leaves.
function module:Save(player: Player)
	self:Store():Forget(key(player.UserId))
	self.information[player.UserId] = nil
end

-- Change one account, online or not, and write it through.
function module:Edit(userId: number, fn: (any) -> ())
	self:Store():Update(key(userId), function(account)
		account = account or blank()
		fn(account)
		return account
	end)
	self:Store():Flush(key(userId))
end

function module:SetRole(userId: number, level: number)
	self:Edit(userId, function(account)
		account.Role = level
	end)
end

function module:Ban(userId: number, reason: string?, by: Player?)
	self:Edit(userId, function(account)
		account.Banned = { Reason = reason, By = by and by.UserId, At = os.time() }
	end)
	local online = Players:GetPlayerByUserId(userId)
	if online then
		online:Kick("Banned: " .. (reason or "no reason given"))
	end
end

function module:Unban(userId: number)
	self:Edit(userId, function(account)
		account.Banned = nil
	end)
end

return Base(module, {
	{ Path = "Global/Database", Imports = "Database.h" },
})
