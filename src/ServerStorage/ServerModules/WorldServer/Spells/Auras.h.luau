local Base = require(game:GetService("ServerStorage").ServerModules["Template.h"])
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Opcodes = require(ReplicatedStorage.Shared.Opcodes)
local Config = require(ReplicatedStorage.Shared.Config)
local module = {}

-- Timed effects on a unit (player or creature state). A spell with an `aura`
-- block applies one: { kind = periodic|stat|speed|jump|stun, amount, interval,
-- stat = Health|Damage|Armor|Mana, mult, duration, harmful }. Periodic auras
-- tick through Combat so DoTs and HoTs log and aggro like direct spells; stat
-- auras feed EntityPlayer:ApplyStats; speed and stun shape the Humanoid.
-- Reapplying refreshes the duration. The list rides on the unit's "Auras"
-- attribute (Player or creature Model) so every client can draw it.

local function key(unit)
	return if typeof(unit) == "Instance" then unit else tostring(unit.Row.guid)
end

local function instanceOf(unit): Instance?
	return if typeof(unit) == "Instance" then unit else unit.Model
end

function module:List(unit)
	local k = key(unit)
	local list = self.information[k]
	if not list then
		list = { Unit = unit, Auras = {} }
		self.information[k] = list
	end
	return list.Auras
end

function module:Has(unit, kind: string): boolean
	for _, aura in self:List(unit) do
		if aura.Kind == kind then
			return true
		end
	end
	return false
end

-- The shapeshift form a unit is in, if any.
function module:CurrentForm(unit): string?
	for _, aura in self:List(unit) do
		if aura.Kind == "form" then
			return aura.Form
		end
	end
	return nil
end

function module:Find(unit, id)
	for _, aura in self:List(unit) do
		if aura.Id == id then
			return aura
		end
	end
	return nil
end

-- Sum of stat modifiers and the movement multiplier from every aura.
function module:Mods(unit)
	local mods = { Health = 0, Damage = 0, Armor = 0, Mana = 0, Speed = 1, Jump = 1, Stun = false, Stamina = 0, Strength = 0, Agility = 0, Intellect = 0, Spirit = 0, Pct = 0, Stats = {} }
	for _, aura in self:List(unit) do
		if aura.Kind == "stat" and aura.Stat then
			mods[aura.Stat] = (mods[aura.Stat] or 0) + (aura.Amount or 0)
		elseif aura.Kind == "stats" or aura.Kind == "form" then
			mods.Pct += aura.Pct or 0
			for stat, value in (aura.Stats or {}) do
				mods.Stats[stat] = (mods.Stats[stat] or 0) + value * math.max(aura.Amount or 1, 1)
			end
			mods.Speed *= aura.Mult or 1
		elseif aura.Kind == "speed" or aura.Kind == "mount" or aura.Kind == "stealth" then
			mods.Speed *= aura.Mult or 1
		elseif aura.Kind == "jump" then
			mods.Jump *= aura.Mult or 1
		elseif aura.Kind == "stun" then
			mods.Stun = true
		end
	end
	return mods
end

-- Push the list to the attribute and apply movement and stats.
function module:Sync(unit)
	local Combat = self.includes.Combat["Combat.h"]
	local target = instanceOf(unit)
	local now = os.clock()
	local out = {}
	for _, aura in self:List(unit) do
		table.insert(out, { Id = aura.Id, Name = aura.Name, Icon = aura.Icon, School = aura.School, Kind = aura.Kind, Harmful = aura.Harmful,
			Left = if aura.Ends == math.huge then -1 else math.max(0, aura.Ends - now), Duration = aura.Duration, Description = aura.Description, Stacks = aura.Stacks })
	end
	if target and target.Parent then
		target:SetAttribute("Auras", if #out > 0 then HttpService:JSONEncode(out) else nil)
	end
	local mods = self:Mods(unit)
	local humanoid = Combat:Humanoid(unit)
	if Combat:IsPlayer(unit) then
		local Entities = self.includes.Entities["EntityPlayer.h"]
		local entity = Entities:Get(unit)
		if humanoid and entity and not entity.Ghost then
			humanoid.WalkSpeed = if mods.Stun then 0 else 16 * mods.Speed
			humanoid.JumpPower = if mods.Stun then 0 else 50 * mods.Jump
		end
		Entities:ApplyStats(unit)
	elseif humanoid then
		humanoid.WalkSpeed = if mods.Stun then 0 else (unit.Template.speed or 12) * mods.Speed
	end
end

-- Apply `spell`'s aura to unit. amount is the per-tick or stat value already
-- scaled for the caster's level.
function module:Apply(caster, unit, spell, amount: number?)
	local Combat = self.includes.Combat["Combat.h"]
	local spec = spell.aura
	if not spec or not Combat:Humanoid(unit) then
		return nil
	end
	local list = self:List(unit)
	local aura = self:Find(unit, spell.id)
	if not aura then
		if #list >= Config.Spells.MaxAuras then
			table.remove(list, 1)
		end
		aura = { Id = spell.id, Stacks = 0 }
		table.insert(list, aura)
	end
	local now = os.clock()
	aura.Name, aura.Icon, aura.School, aura.Description = spell.name, spell.icon, spell.school, spell.description
	aura.Kind, aura.Stat, aura.Mult = spec.kind, spec.stat, spec.mult
	aura.Pct, aura.Stats, aura.Form, aura.Group = spec.pct, spec.stats, spec.form, spec.group
	-- one of a group at a time: stances, aspects, presences, forms
	if spec.group then
		for _, other in table.clone(list) do
			if other ~= aura and other.Group == spec.group then
				self:Remove(unit, other.Id, true)
			end
		end
	end
	aura.Amount = amount or spec.amount or 0
	aura.Interval = spec.interval or 3
	aura.Duration = spec.duration or 0
	aura.Ends = if aura.Duration > 0 then now + aura.Duration else math.huge
	aura.NextTick = now + aura.Interval
	aura.Harmful = spec.harmful == true or spec.kind == "stun" or ((spec.kind == "speed" or spec.kind == "jump") and (spec.mult or 1) < 1)
	if spec.kind == "mount" then
		self.includes.Entities["EntityPlayer.h"]:Mount(unit, true, spec.fly == true, spec.model)
	elseif spec.kind == "form" then
		self.includes.Entities["EntityPlayer.h"]:Shapeshift(unit, spec.form)
	elseif spec.kind == "stealth" then
		self.includes.Entities["EntityPlayer.h"]:Stealth(unit, true)
	end
	aura.Caster = caster
	aura.Stacks = math.min((aura.Stacks or 0) + 1, spec.stacks or 1)
	self:Sync(unit)
	if Combat:IsPlayer(unit) then
		Combat:Log(unit, (if aura.Harmful then "You are afflicted by %s." else "You gain %s."):format(spell.name), if aura.Harmful then Config.Chat.Colors.HURT else Config.Chat.Colors.LOOT)
	end
	if aura.Harmful and caster and Combat:IsPlayer(caster) and not Combat:IsPlayer(unit) then
		self.includes.Content["Creatures.h"]:Aggro(unit.Row.guid, caster)
		Combat:Enter(caster)
	end
	return aura
end

function module:RemoveKind(unit, kind: string)
	for _, aura in table.clone(self:List(unit)) do
		if aura.Kind == kind then
			self:Remove(unit, aura.Id)
		end
	end
end

function module:Remove(unit, id, quiet: boolean?)
	local list = self:List(unit)
	for i, aura in list do
		if aura.Id == id then
			table.remove(list, i)
			if aura.Kind == "mount" then
				self.includes.Entities["EntityPlayer.h"]:Mount(unit, false)
			elseif aura.Kind == "form" then
				self.includes.Entities["EntityPlayer.h"]:Shapeshift(unit, nil)
			elseif aura.Kind == "stealth" then
				self.includes.Entities["EntityPlayer.h"]:Stealth(unit, false)
			end
			self:Sync(unit)
			local Combat = self.includes.Combat["Combat.h"]
			if not quiet and Combat:IsPlayer(unit) then
				Combat:Log(unit, ("%s fades from you."):format(aura.Name), Config.Chat.Colors.COMMAND)
			end
			return true
		end
	end
	return false
end

function module:Clear(unit)
	local k = key(unit)
	if self.information[k] then
		if self.includes.Combat["Combat.h"]:IsPlayer(unit) then
			if self:Has(unit, "mount") then
				self.includes.Entities["EntityPlayer.h"]:Mount(unit, false)
			end
			if self:Has(unit, "form") then
				self.includes.Entities["EntityPlayer.h"]:Shapeshift(unit, nil)
			end
			if self:Has(unit, "stealth") then
				self.includes.Entities["EntityPlayer.h"]:Stealth(unit, false)
			end
		end
		self.information[k].Auras = {}
		self:Sync(unit)
		self.information[k] = nil
	end
end

function module:Forget(unit)
	self.information[key(unit)] = nil
end

local function tick(self, unit, aura)
	local Combat = self.includes.Combat["Combat.h"]
	local caster = aura.Caster
	if Combat:IsPlayer(caster) and caster.Parent ~= Players then
		caster = nil
	end
	if aura.Harmful then
		Combat:Damage(caster, unit, math.max(1, math.round(aura.Amount * (aura.Stacks or 1))), aura.School, if caster and Combat:IsPlayer(caster) then "Your " .. aura.Name else aura.Name)
	else
		Combat:Heal(caster, unit, math.max(1, math.round(aura.Amount)), if caster and Combat:IsPlayer(caster) then "Your " .. aura.Name else aura.Name)
	end
end

function module:Start()
	local Packet = self.includes.Security["Packet.h"]
	Packet:On(Opcodes.CMSG_CANCEL_AURA, function(player, data)
		local aura = typeof(data) == "table" and self:Find(player, tonumber(data.Id))
		if aura and not aura.Harmful then
			self:Remove(player, aura.Id)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		self.information[player] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(Config.Spells.AuraTick)
			local now = os.clock()
			local Combat = self.includes.Combat["Combat.h"]
			for k, list in self.information do
				local unit = list.Unit
				if not Combat:Humanoid(unit) or (not Combat:IsPlayer(unit) and not unit.Model.Parent) then
					self.information[k] = nil
					continue
				end
				local changed = false
				for i = #list.Auras, 1, -1 do
					local aura = list.Auras[i]
					if aura.Kind == "periodic" and now >= aura.NextTick and now < aura.Ends + 0.5 then
						aura.NextTick += aura.Interval
						tick(self, unit, aura)
					end
					if now >= aura.Ends then
						table.remove(list.Auras, i)
						changed = true
						if aura.Kind == "mount" then
							self.includes.Entities["EntityPlayer.h"]:Mount(unit, false)
						elseif aura.Kind == "form" then
							self.includes.Entities["EntityPlayer.h"]:Shapeshift(unit, nil)
						elseif aura.Kind == "stealth" then
							self.includes.Entities["EntityPlayer.h"]:Stealth(unit, false)
						end
						if Combat:IsPlayer(unit) then
							Combat:Log(unit, ("%s fades from you."):format(aura.Name), Config.Chat.Colors.COMMAND)
						end
					end
				end
				if changed then
					self:Sync(unit)
				end
			end
		end
	end)
end

return Base(module, {
	{ Path = "Auth/Security", Imports = "Packet.h" },
	{ Path = "Auth/Entities", Imports = "EntityPlayer.h" },
	{ Path = "World/Combat", Imports = "Combat.h" },
	{ Path = "World/Content", Imports = "Creatures.h" },
})
