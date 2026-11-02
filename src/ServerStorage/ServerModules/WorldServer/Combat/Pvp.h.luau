local Base = require(game:GetService("ServerStorage").ServerModules["Template.h"])
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local module = {}

-- World PvP. In a zone with Pvp = true, players of the opposite faction are
-- attackable; a kill of someone within five levels awards honor and an
-- honorable kill, both kept on the character. Attacking flags you (PvpFlag)
-- for a while so you stay attackable after leaving the zone.

local FLAG_SECONDS = 300

local function factionOf(player: Player): string?
	return player:GetAttribute("CharacterFaction")
end

function module:Flagged(player: Player): boolean
	return (self.information[player] or 0) > os.clock()
end

function module:Flag(player: Player)
	self.information[player] = os.clock() + FLAG_SECONDS
	if player:GetAttribute("PvpFlag") ~= true then
		player:SetAttribute("PvpFlag", true)
	end
end

-- Hostile when factions differ and either both stand in a PvP zone or the
-- target is flagged.
function module:Hostile(attacker: Player, target: Player): boolean
	local a, b = factionOf(attacker), factionOf(target)
	if not a or not b or a == b then
		return false
	end
	if self.includes.Combat["Battleground.h"]:SameMatch(attacker, target) then
		return true
	end
	local Zones = self.includes.Zones["Zones.h"]
	local za, zb = Zones:Current(attacker), Zones:Current(target)
	if za and zb and za:GetAttribute("Safe") ~= true and zb:GetAttribute("Safe") ~= true and (za:GetAttribute("Pvp") == true or self:Flagged(target)) then
		self:Flag(attacker)
		return true
	end
	return false
end

function module:OnKill(killer: Player, victim: Player)
	local Entities = self.includes.Entities["EntityPlayer.h"]
	local entity = Entities:Get(killer)
	local char = entity and entity.Active
	if not char then
		return
	end
	local kl, vl = killer:GetAttribute("CharacterLevel") or 1, victim:GetAttribute("CharacterLevel") or 1
	local honor = if kl - vl >= 5 then 0 else math.max(1, math.floor(10 + vl * 1.5 - math.max(0, kl - vl) * 2))
	char.HonorKills = (char.HonorKills or 0) + 1
	char.Honor = (char.Honor or 0) + honor
	killer:SetAttribute("Honor", char.Honor)
	killer:SetAttribute("HonorKills", char.HonorKills)
	self.includes.Social["Achievements.h"]:OnHonor(killer, char.HonorKills)
	self.includes.Social["Titles.h"]:OnHonor(killer, char.Honor)
	local Chat = self.includes.Chat["Chat.h"]
	local name = victim:GetAttribute("CharacterName") or victim.Name
	Chat:System(killer, if honor > 0 then ("%s dies, honorable kill Rank: %d honor."):format(name, honor) else ("%s dies, no honor gained."):format(name))
	Chat:System(victim, ("%s has slain you."):format(killer:GetAttribute("CharacterName") or killer.Name))
end

function module:OnLogin(player: Player)
	local entity = self.includes.Entities["EntityPlayer.h"]:Get(player)
	local char = entity and entity.Active
	if char then
		player:SetAttribute("CharacterFaction", char.Faction or "Alliance")
		player:SetAttribute("Honor", char.Honor or 0)
		player:SetAttribute("HonorKills", char.HonorKills or 0)
	end
end

function module:Start()
	Players.PlayerRemoving:Connect(function(player)
		self.information[player] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(5)
			for player, until_ in self.information do
				if until_ <= os.clock() then
					self.information[player] = nil
					player:SetAttribute("PvpFlag", nil)
				end
			end
		end
	end)
end

return Base(module, {
	{ Path = "Auth/Entities", Imports = "EntityPlayer.h" },
	{ Path = "Auth/Chat", Imports = "Chat.h" },
	{ Path = "Auth/Social", Imports = "Achievements.h|Titles.h" },
	{ Path = "World/Zones", Imports = "Zones.h" },
	{ Path = "World/Combat", Imports = "Battleground.h" },
})
