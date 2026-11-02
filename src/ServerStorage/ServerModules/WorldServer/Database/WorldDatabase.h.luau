local Base = require(game:GetService("ServerStorage").ServerModules["Template.h"])
local module = {}

-- World record keyed by UserId: { Characters = { { Name, Class, Level, Position, Health, Created } } }

local function key(userId: number): string
	return "character:" .. userId
end

function module:Store()
	return self.includes.Database["Database.h"]:Open("World")
end

function module:Load(player: Player)
	local record = self:Store():Get(key(player.UserId), {})
	if not record.Characters then
		-- Records from before character select held one unnamed character.
		record.Characters = if record.Position
			then { { Name = player.Name, Class = "Warrior", Level = 1, Position = record.Position, Health = record.Health, Created = os.time() } }
			else {}
		record.Position, record.Health = nil, nil
	end
	self.information[player.UserId] = record
	return record
end

function module:Get(player: Player)
	return self.information[player.UserId]
end

-- Write the player's record (characters, positions) back to the store.
function module:Commit(player: Player)
	local record = self.information[player.UserId]
	if record then
		self:Store():Set(key(player.UserId), record)
	end
end

-- Name index "names": { [lowercase] = { UserId, Name } }, so mail and friends
-- can reach characters that are offline.
function module:LookupName(name: string?)
	if not name or #name == 0 then
		return nil
	end
	self:Store():Refresh("names")
	return self:Store():Get("names", {})[name:lower()]
end

function module:Register(name: string, userId: number)
	self:Store():Transform("names", function(index)
		index = index or {}
		index[name:lower()] = { UserId = userId, Name = name }
		return index
	end)
end

function module:Unregister(name: string)
	self:Store():Transform("names", function(index)
		index = index or {}
		index[name:lower()] = nil
		return index
	end)
end

function module:Forget(player: Player)
	self:Commit(player)
	self:Store():Forget(key(player.UserId))
	self.information[player.UserId] = nil
end

return Base(module, {
	{ Path = "Global/Database", Imports = "Database.h" },
})
