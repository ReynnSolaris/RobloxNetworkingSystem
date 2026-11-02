local Base = require(game:GetService("ServerStorage").ServerModules["Template.h"])
local module = {}

-- game_tele: named locations for .tele. Saved rows first, then any Zone part.
-- Names compare without case or spaces, so "GM Island" is .tele gmisland.

local function key(name: string): string
	return (name:lower():gsub("%s", ""))
end

function module:DB()
	return self.includes.Database["WorldDB.h"]
end

function module:All()
	return self:DB():Select("game_tele")
end

function module:Resolve(name: string): (CFrame?, string?)
	local wanted = key(name)
	for _, row in self:All() do
		if key(row.name) == wanted then
			return self:DB().ToCFrame(row), row.name
		end
	end
	for _, part in self.includes.Zones["Zones.h"]:All() do
		if key(part.Name) == wanted then
			return CFrame.new(part.Position - Vector3.new(0, part.Size.Y / 2, 0) + Vector3.new(0, 5, 0)), part.Name
		end
	end
	return nil
end

function module:Add(name: string, cframe: CFrame, by: Player)
	for _, row in self:All() do
		if key(row.name) == key(name) then
			self:DB():Delete("game_tele", row.id)
		end
	end
	local row = self:DB().ToRow(cframe)
	row.name, row.by = name, by.UserId
	self:DB():Insert("game_tele", row)
end

function module:Remove(name: string): boolean
	for _, row in self:All() do
		if key(row.name) == key(name) then
			return self:DB():Delete("game_tele", row.id)
		end
	end
	return false
end

return Base(module, {
	{ Path = "World/Database", Imports = "WorldDB.h" },
	{ Path = "World/Zones", Imports = "Zones.h" },
})
