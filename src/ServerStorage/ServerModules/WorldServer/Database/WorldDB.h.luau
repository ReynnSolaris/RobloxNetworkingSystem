local Base = require(game:GetService("ServerStorage").ServerModules["Template.h"])
local module = {}

-- The world database, TrinityCore shaped: static templates and spawn rows in
-- named tables with a primary key. Each table is one DataStore record edited
-- with UpdateAsync; every write is published so other servers apply it live.

local TABLES = {
	creature_template = "entry",
	creature = "guid",
	gameobject_template = "entry",
	gameobject = "guid",
	game_tele = "id",
	item_template = "entry",
	creature_loot_template = "id",
	gameobject_loot_template = "id",
	npc_vendor = "id",
	game_graveyard = "id",
	quest_template = "id",
	creature_queststarter = "id",
	creature_questender = "id",
	spell_template = "id",
	npc_trainer = "id",
	playercreateinfo_spell = "id",
	faction = "id",
	skill_line = "id",
	skill_recipe = "id",
	talent = "id",
	auctionhouse = "id",
	taxi_nodes = "id",
	taxi_path = "id",
	achievement = "id",
	game_event = "id",
}
module.TABLES = TABLES

local listeners: { [string]: (string, string, any) -> () } = {}

function module:Store()
	return self.includes.Database["Database.h"]:Open("WorldDB")
end

local function keyOf(tableName: string, row): string
	return tostring(row[assert(TABLES[tableName], "no table " .. tableName)])
end

-- Every row of a table as an array, sorted by key.
function module:Select(tableName: string, where: ((any) -> boolean)?): { any }
	self:Store():Refresh(tableName)
	local rows = {}
	for _, row in self:Store():Get(tableName, {}) do
		if not where or where(row) then
			table.insert(rows, row)
		end
	end
	table.sort(rows, function(a, b)
		return (tonumber(keyOf(tableName, a)) or 0) < (tonumber(keyOf(tableName, b)) or 0)
	end)
	return rows
end

function module:Get(tableName: string, key)
	self:Store():Refresh(tableName)
	return self:Store():Get(tableName, {})[tostring(key)]
end

function module:NextId(tableName: string): number
	return self:Store():Transform("next_" .. tableName, function(n)
		return (n or 0) + 1
	end)
end

local function publish(self, tableName: string, op: string, key: string, row)
	self.includes.System["Global.h"]:Publish("WDB", { Table = tableName, Op = op, Key = key, Row = row })
end

-- Insert assigns the primary key when the row has none.
function module:Insert(tableName: string, row)
	local pk = assert(TABLES[tableName], "no table " .. tableName)
	if row[pk] == nil then
		row[pk] = self:NextId(tableName)
	end
	local key = keyOf(tableName, row)
	self:Store():Transform(tableName, function(t)
		t = t or {}
		t[key] = row
		return t
	end)
	publish(self, tableName, "set", key, row)
	return row
end

function module:Update(tableName: string, key, fields)
	local updated
	self:Store():Transform(tableName, function(t)
		t = t or {}
		local row = t[tostring(key)]
		if row then
			for field, value in fields do
				row[field] = value
			end
			updated = row
		end
		return t
	end)
	if updated then
		publish(self, tableName, "set", tostring(key), updated)
	end
	return updated
end

function module:Delete(tableName: string, key): boolean
	local existed = false
	self:Store():Transform(tableName, function(t)
		t = t or {}
		existed = t[tostring(key)] ~= nil
		t[tostring(key)] = nil
		return t
	end)
	if existed then
		publish(self, tableName, "del", tostring(key), nil)
	end
	return existed
end

-- handler(op, key, row) for writes made on other servers.
function module:OnRemote(tableName: string, handler: (string, string, any) -> ())
	listeners[tableName] = handler
end

function module:Start()
	self.includes.System["Global.h"]:On("WDB", function(data)
		local handler = listeners[tostring(data.Table)]
		if handler then
			handler(tostring(data.Op), tostring(data.Key), data.Row)
		end
	end)
end

-- Orientation helpers shared by spawn tables: rows keep x y z and a yaw in degrees.
function module.ToRow(cframe: CFrame)
	local _, yaw = cframe:ToEulerAnglesYXZ()
	return { x = cframe.X, y = cframe.Y, z = cframe.Z, o = math.deg(yaw) }
end

function module.ToCFrame(row): CFrame
	return CFrame.new(row.x or 0, row.y or 0, row.z or 0) * CFrame.Angles(0, math.rad(row.o or 0), 0)
end

return Base(module, {
	{ Path = "Global/Database", Imports = "Database.h" },
	{ Path = "Global/System", Imports = "Global.h" },
})
