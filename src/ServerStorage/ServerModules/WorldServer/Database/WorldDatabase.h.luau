local Base = require(game:GetService("ServerStorage").ServerModules["Template.h"])
local module = {}

-- Character state keyed by UserId: Position {x, y, z}, Health

local function key(userId: number): string
	return "character:" .. userId
end

function module:Store()
	return self.includes.Database["Database.h"]:Open("World")
end

function module:Load(player: Player)
	local data = self:Store():Get(key(player.UserId), {})
	self.information[player.UserId] = data
	return data
end

function module:Save(player: Player, character: Model?)
	local data = self.information[player.UserId]
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not data or not humanoid or humanoid.Health <= 0 then
		return
	end
	local position = character:GetPivot().Position
	data.Position = { position.X, position.Y, position.Z }
	data.Health = humanoid.Health
	self:Store():Set(key(player.UserId), data)
end

function module:Forget(player: Player)
	self:Store():Forget(key(player.UserId))
	self.information[player.UserId] = nil
end

return Base(module, {
	{ Path = "Global/Database", Imports = "Database.h" },
})
