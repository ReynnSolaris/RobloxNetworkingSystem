local Base = require(game:GetService("ServerStorage").ServerModules["Template.h"])
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local module = {}

-- Reputation with factions, WoW style. faction table: { id, name, description,
-- team = Alliance|Horde|nil, base = { Alliance = n, Horde = n } }. Standing runs
-- Hated .. Exalted over Config.Reputation thresholds. A character keeps
-- Reputation = { [factionId] = value }. Creatures carry faction_id and
-- rep_kill (what killing one is worth, negative with that faction) plus
-- rep_ally (gained with the opposing faction). Quests give reward_rep.

local SEED = {
	{ name = "Stormwind", team = "Alliance", description = "The humans of Stormwind, heart of the Alliance.", base = { Alliance = 3000, Horde = -3000 } },
	{ name = "Ironforge", team = "Alliance", description = "The dwarves and gnomes of Ironforge.", base = { Alliance = 3000, Horde = -3000 } },
	{ name = "Darnassus", team = "Alliance", description = "The night elves of Teldrassil.", base = { Alliance = 3000, Horde = -3000 } },
	{ name = "Orgrimmar", team = "Horde", description = "The orcs and trolls of Durotar.", base = { Alliance = -3000, Horde = 3000 } },
	{ name = "Undercity", team = "Horde", description = "The Forsaken beneath Lordaeron.", base = { Alliance = -3000, Horde = 3000 } },
	{ name = "Thunder Bluff", team = "Horde", description = "The tauren of Mulgore.", base = { Alliance = -3000, Horde = 3000 } },
	{ name = "Kobold Clans", description = "The candle-hoarding kobolds of the mines.", base = { Alliance = -6000, Horde = -6000 } },
	{ name = "Argent Dawn", description = "Defenders against the undead Scourge.", base = { Alliance = 0, Horde = 0 } },
}

function module:DB()
	return self.includes.Database["WorldDB.h"]
end

function module:Faction(id)
	return self:DB():Get("faction", id)
end

function module:ByName(name: string)
	for _, row in self:DB():Select("faction") do
		if row.name == name then
			return row
		end
	end
	return nil
end

local function char(self, player: Player)
	local entity = self.includes.Entities["EntityPlayer.h"]:Get(player)
	local c = entity and entity.Active
	if c then
		c.Reputation = c.Reputation or {}
	end
	return c
end

-- Current value with a faction: the stored change plus the team's base.
function module:Value(player: Player, factionId): number
	local c = char(self, player)
	local faction = self:Faction(factionId)
	if not c or not faction then
		return 0
	end
	local base = faction.base and faction.base[c.Faction or "Alliance"] or 0
	return math.clamp(base + (c.Reputation[tostring(faction.id)] or 0), Config.Reputation.Min, Config.Reputation.Max)
end

-- Standing name and progress within it for a value.
function module:Standing(value: number)
	local standing = Config.Reputation.Standings[1]
	for _, s in Config.Reputation.Standings do
		if value >= s.Min then
			standing = s
		end
	end
	return standing
end

function module:List(player: Player)
	local out = {}
	for _, faction in self:DB():Select("faction") do
		local value = self:Value(player, faction.id)
		local standing = self:Standing(value)
		table.insert(out, { Id = faction.id, Name = faction.name, Description = faction.description, Team = faction.team, Value = value,
			Standing = standing.Name, Color = standing.Color, Min = standing.Min, Max = standing.Max })
	end
	return out
end

function module:Sync(player: Player)
	player:SetAttribute("Reputation", HttpService:JSONEncode(self:List(player)))
end

function module:Modify(player: Player, factionId, amount: number, quiet: boolean?)
	local c = char(self, player)
	local faction = self:Faction(factionId)
	if not c or not faction or amount == 0 then
		return
	end
	local before = self:Standing(self:Value(player, faction.id))
	c.Reputation[tostring(faction.id)] = (c.Reputation[tostring(faction.id)] or 0) + amount
	local value = self:Value(player, faction.id)
	local after = self:Standing(value)
	self.includes.Database["WorldDatabase.h"]:Commit(player)
	if not quiet then
		local Chat = self.includes.Chat["Chat.h"]
		Chat:System(player, if amount > 0 then ("Your reputation with %s has increased by %d."):format(faction.name, amount) else ("Your reputation with %s has decreased by %d."):format(faction.name, -amount))
		if after ~= before then
			Chat:System(player, ("You are now %s with %s."):format(after.Name, faction.name))
		end
	end
	self.includes.Social["Achievements.h"]:OnReputation(player, value)
	self:Sync(player)
end

function module:OnKill(player: Player, template)
	if template.faction_id then
		self:Modify(player, template.faction_id, -(template.rep_kill or 5))
	end
	if template.rep_ally then
		self:Modify(player, template.rep_ally, template.rep_kill or 5)
	end
	-- party members nearby share the standing change
end

-- Vendor prices fall with standing: friendly 5%, honored 10%, revered 15%, exalted 20%.
function module:Discount(player: Player, template): number
	if not template or not template.faction_id then
		return 0
	end
	local standing = self:Standing(self:Value(player, template.faction_id))
	return standing.Discount or 0
end

function module:OnLogin(player: Player)
	self:Sync(player)
end

function module:Start()
	local DB = self:DB()
	local byName = {}
	for _, row in DB:Select("faction") do
		byName[row.name] = row
	end
	for _, seed in SEED do
		if not byName[seed.name] then
			byName[seed.name] = DB:Insert("faction", table.clone(seed))
		end
	end
	-- the starter creatures belong somewhere
	local kobolds, stormwind = byName["Kobold Clans"], byName["Stormwind"]
	for _, creature in DB:Select("creature_template") do
		if creature.faction_id == nil then
			if creature.name:find("Kobold") and kobolds then
				DB:Update("creature_template", creature.entry, { faction_id = kobolds.id, rep_kill = 5, rep_ally = stormwind and stormwind.id })
			elseif creature.faction == "friendly" and stormwind then
				DB:Update("creature_template", creature.entry, { faction_id = stormwind.id })
			end
		end
	end
end

return Base(module, {
	{ Path = "Auth/Entities", Imports = "EntityPlayer.h" },
	{ Path = "Auth/Chat", Imports = "Chat.h" },
	{ Path = "Auth/Social", Imports = "Achievements.h" },
	{ Path = "World/Database", Imports = "WorldDB.h|WorldDatabase.h" },
})
