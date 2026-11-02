local Base = require(game:GetService("ServerStorage").ServerModules["Template.h"])
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Opcodes = require(ReplicatedStorage.Shared.Opcodes)
local Config = require(ReplicatedStorage.Shared.Config)
local module = {}

-- creature_template is the asset: { entry, name, subname, modelid, scale, gossip,
-- faction (friendly|hostile), minlevel, maxlevel, health, dmgmin, dmgmax, aggro,
-- speed, mingold, maxgold, spells = { names }, wander (studs), faction_id,
-- innkeeper, banker, flightmaster, auctioneer, trainer_skill }. creature is a
-- spawn: { guid, id, x, y, z, o, spawntimesecs, waypoints = { {x,y,z} } }.
-- Friendly creatures stand with a Talk prompt, or patrol their waypoints.
-- Hostile ones get a level, health and a brain: aggro, chase, melee, spells,
-- call for help, leash, wander. Loot comes from creature_loot_template.

local SEED = {
	{ name = "Innkeeper", subname = "Innkeeper", modelid = "default", scale = 1, gossip = "Welcome, traveler. Rest your feet a while.", faction = "friendly", innkeeper = true },
	{ name = "Town Guard", subname = "Guard", modelid = "default", scale = 1.05, gossip = "Move along, citizen.", faction = "friendly" },
	{ name = "Banker", subname = "Banker", modelid = "default", scale = 1, gossip = "Your deposits are safe with us.", faction = "friendly", banker = true },
	{ name = "Class Trainer", subname = "Trainer", modelid = "default", scale = 1, gossip = "What would you like to learn?", faction = "friendly" },
	{ name = "General Goods", subname = "Vendor", modelid = "default", scale = 1, gossip = "Fine wares, fair prices.", faction = "friendly" },
	{ name = "Kobold Vermin", modelid = "default", scale = 0.85, faction = "hostile", minlevel = 1, maxlevel = 2, health = 40, dmgmin = 2, dmgmax = 4, aggro = 15, speed = 12, mingold = 1, maxgold = 5, wander = 8, spells = { "Throw Torch" } },
	{ name = "Young Wolf", modelid = "default", scale = 0.9, faction = "hostile", minlevel = 2, maxlevel = 3, health = 55, dmgmin = 3, dmgmax = 5, aggro = 18, speed = 14, mingold = 0, maxgold = 3, wander = 12, spells = { "Bite" }, beast = true },
	{ name = "Kobold Geomancer", modelid = "default", scale = 0.85, faction = "hostile", minlevel = 3, maxlevel = 4, health = 60, dmgmin = 2, dmgmax = 4, aggro = 20, speed = 12, mingold = 3, maxgold = 9, spells = { "Fire Blast" } },
	{ name = "Imp", subname = "Minion", modelid = "default", scale = 0.6, faction = "pet", health = 45, dmgmin = 3, dmgmax = 6, speed = 16, spells = { "Firebolt" } },
	{ name = "Festival Vendor", subname = "Harvest Festival", modelid = "default", scale = 1, gossip = "Fresh from the fields! Only while the festival lasts.", faction = "friendly" },
}
-- creature by name, item by entry; resolved to entries when seeded
local LOOT_SEED = {
	{ creature = "Kobold Vermin", item = "Linen Cloth", chance = 60, mincount = 1, maxcount = 3 },
	{ creature = "Kobold Vermin", item = "Tough Jerky", chance = 25, mincount = 1, maxcount = 1 },
	{ creature = "Young Wolf", item = "Linen Cloth", chance = 30, mincount = 1, maxcount = 2 },
	{ creature = "Young Wolf", item = "Stringy Wolf Meat", chance = 70, mincount = 1, maxcount = 2 },
	{ creature = "Young Wolf", item = "Ring of Precision", chance = 5, mincount = 1, maxcount = 1 },
	{ creature = "Kobold Geomancer", item = "Linen Cloth", chance = 70, mincount = 1, maxcount = 3 },
	{ creature = "Kobold Geomancer", item = "Kobold Mining Helm", chance = 8, mincount = 1, maxcount = 1 },
	{ creature = "Kobold Geomancer", item = "Copper Ore", chance = 30, mincount = 1, maxcount = 2 },
}

local function folder(): Folder
	local f = workspace:FindFirstChild("Creatures")
	if not f then
		f = Instance.new("Folder")
		f.Name = "Creatures"
		f.Parent = workspace
	end
	return f
end

local function build(modelid: string): Model
	local kind, arg = modelid:match("^(%w+):(.+)$")
	if kind == "model" then
		local source = ServerStorage:FindFirstChild("CreatureModels") and ServerStorage.CreatureModels:FindFirstChild(arg)
		assert(source, "no creature model named " .. arg)
		return source:Clone()
	end
	local description = Instance.new("HumanoidDescription")
	if kind == "user" then
		local ok, desc = pcall(Players.GetHumanoidDescriptionFromUserId, Players, tonumber(arg) or 0)
		if ok then
			description = desc
		end
	end
	return Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R15)
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

-- A dead model stays whole: every part anchored and passable, the body laid on
-- its back on the ground, and an invisible Hitbox part the size of the corpse
-- for prompts and clicks. Returns the hitbox.
function module.LayDown(model: Model): BasePart
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanCollide = false
		end
	end
	local box, size = model:GetBoundingBox()
	local ground = box.Position.Y - size.Y / 2
	local target = CFrame.new(box.Position.X, ground + size.Z / 2, box.Position.Z) * box.Rotation * CFrame.Angles(-math.pi / 2, 0, 0)
	model:PivotTo(target * box:Inverse() * model:GetPivot())
	local hitbox = Instance.new("Part")
	hitbox.Name = "Hitbox"
	hitbox.Size = Vector3.new(size.X, size.Z, size.Y)
	hitbox.CFrame = CFrame.new(target.Position) * box.Rotation
	hitbox.Anchored, hitbox.CanCollide, hitbox.Transparency = true, false, 1
	hitbox.Parent = model
	return hitbox
end

function module:DB()
	return self.includes.Database["WorldDB.h"]
end

function module:Template(entry)
	return self:DB():Get("creature_template", entry)
end

function module:ByName(name: string)
	for _, row in self:DB():Select("creature_template") do
		if row.name == name then
			return row
		end
	end
	return nil
end

-- Runtime state per spawned creature, keyed by guid string.
function module:State(guid)
	return self.information[tostring(guid)]
end

function module:Find(guid): Model?
	local state = self:State(guid)
	return state and state.Model
end

function module:Near(position: Vector3, radius: number): { Model }
	local out = {}
	for _, state in self.information do
		if state.Model.Parent and (state.Model:GetPivot().Position - position).Magnitude <= radius then
			table.insert(out, state.Model)
		end
	end
	table.sort(out, function(a, b)
		return (a:GetPivot().Position - position).Magnitude < (b:GetPivot().Position - position).Magnitude
	end)
	return out
end

-- The creature speaks in SAY to everyone within range.
function module:Say(model: Model, text: string)
	local origin = model:GetPivot().Position
	local packet = { Channel = "SAY", Sender = model.Name, Text = text }
	for _, player in Players:GetPlayers() do
		local character = player.Character
		if character and (character:GetPivot().Position - origin).Magnitude <= Config.Chat.SayRange then
			self.includes.Security["Packet.h"]:Send(player, Opcodes.SMSG_MESSAGECHAT, packet)
		end
	end
end

function module:Despawn(guid)
	local state = self.information[tostring(guid)]
	if state then
		self.information[tostring(guid)] = nil
		self.includes.Spells["Auras.h"]:Forget(state)
		self.includes.Combat["Loot.h"]:Unregister(guid)
		state.Model:Destroy()
	end
end

function module:Spawn(row)
	local template = self:Template(row.id)
	self:Despawn(row.guid)
	if not template or (row.event and not self.includes.Zones["GameEvents.h"]:IsEventActive(row.event)) then
		return nil
	end
	local hostile = template.faction == "hostile"
	local moves = hostile or (row.waypoints and #row.waypoints > 0) or (template.wander or 0) > 0
	local level = math.random(template.minlevel or 1, math.max(template.maxlevel or 1, template.minlevel or 1))
	local model = build(template.modelid or "default")
	model.Name = template.name
	model:SetAttribute("Guid", tostring(row.guid))
	model:SetAttribute("Entry", tostring(row.id))
	model:SetAttribute("Level", level)
	model:SetAttribute("Subname", template.subname)
	model:SetAttribute("Faction", template.faction or "friendly")
	local humanoid = assert(model:FindFirstChildOfClass("Humanoid"), "creature model needs a Humanoid") :: Humanoid
	local root = assert(model:FindFirstChild("HumanoidRootPart"), "creature model needs a HumanoidRootPart") :: BasePart
	humanoid.DisplayName = template.name
	humanoid.WalkSpeed = template.speed or 12
	humanoid.BreakJointsOnDeath = false
	if template.scale and template.scale ~= 1 then
		model:ScaleTo(template.scale)
	end
	if hostile then
		humanoid.MaxHealth = math.floor((template.health or 40) * (1 + 0.15 * (level - (template.minlevel or 1))))
		humanoid.Health = humanoid.MaxHealth
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer
	else
		root.Anchored = not moves
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Talk"
		prompt.ObjectText = template.subname or template.name
		prompt.MaxActivationDistance = 8
		prompt.RequiresLineOfSight = false
		prompt.Parent = root
		prompt.Triggered:Connect(function(player)
			self.includes.Quests["Quests.h"]:Gossip(player, row.guid)
		end)
	end

	local box, size = model:GetBoundingBox()
	local lift = model:GetPivot().Position.Y - (box.Position.Y - size.Y / 2)
	local home = self:DB().ToCFrame(row) * CFrame.new(0, lift, 0)
	model:PivotTo(home)
	model.Parent = folder()
	if moves then
		root:SetNetworkOwner(nil)
	end

	local state = { Row = row, Template = template, Model = model, Humanoid = humanoid, Root = root, Home = home, Level = level,
		Hostile = hostile, Moves = moves, Target = nil, NextSwing = 0, LastAttacker = nil, Dead = false, Waypoint = 1, NextWander = 0, Cooldowns = {} }
	self.information[tostring(row.guid)] = state
	humanoid.Died:Once(function()
		self:OnDeath(state)
	end)
	return model
end

-- A pet: built from a template with no row, owned by a player, levelled to them.
function module:SpawnPet(template, at: CFrame, owner: Player, level: number, name: string?)
	local guid = "pet:" .. owner.UserId
	self:Despawn(guid)
	local model = build(template.modelid or "default")
	model.Name = name or template.name
	model:SetAttribute("Guid", guid)
	model:SetAttribute("Entry", tostring(template.entry))
	model:SetAttribute("Level", level)
	model:SetAttribute("Subname", (owner:GetAttribute("CharacterName") or owner.Name) .. "'s Pet")
	model:SetAttribute("Faction", "pet")
	model:SetAttribute("Owner", owner.Name)
	local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart
	humanoid.DisplayName = model.Name
	humanoid.BreakJointsOnDeath = false
	humanoid.WalkSpeed = math.max(template.speed or 12, 18)
	if template.scale and template.scale ~= 1 then
		model:ScaleTo(template.scale)
	end
	humanoid.MaxHealth = math.floor((template.health or 40) * (1 + 0.12 * (level - 1)))
	humanoid.Health = humanoid.MaxHealth
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer
	local box, size = model:GetBoundingBox()
	local lift = model:GetPivot().Position.Y - (box.Position.Y - size.Y / 2)
	model:PivotTo(at * CFrame.new(0, lift, 0))
	model.Parent = folder()
	root:SetNetworkOwner(nil)
	local state = { Row = { guid = guid, id = template.entry }, Template = template, Model = model, Humanoid = humanoid, Root = root, Home = at, Level = level,
		Hostile = false, Moves = true, Owner = owner, Mode = "defensive", Target = nil, NextSwing = 0, Dead = false, Cooldowns = {} }
	self.information[guid] = state
	humanoid.Died:Once(function()
		if state.Dead then
			return
		end
		state.Dead = true
		self.includes.Spells["Auras.h"]:Clear(state)
		self.includes.System["Effects.h"]:Play("Smoke", guid, 8)
		self.includes.Content["Pets.h"]:OnPetDeath(state)
		task.delay(3, function()
			if self.information[guid] == state then
				self:Despawn(guid)
			end
		end)
	end)
	return state
end

-- An emptied corpse clears a moment later.
function module:ClearCorpse(guid)
	local state = self:State(guid)
	if state then
		local part = state.Hitbox or state.Root
		self.includes.System["Effects.h"]:Detach("Sparkle", part)
		local prompt = part:FindFirstChildOfClass("ProximityPrompt")
		if prompt then
			prompt:Destroy()
		end
		task.delay(2, function()
			if self.information[tostring(guid)] == state then
				self:Despawn(guid)
			end
		end)
	end
end

-- Called when a player hurts the creature. Nearby creatures of the same kind
-- join in.
function module:Aggro(guid, attacker, quiet: boolean?)
	local state = self:State(guid)
	if not state or not state.Hostile or state.Dead then
		return
	end
	local owner = if typeof(attacker) == "table" then attacker.Owner else attacker
	state.LastAttacker = owner or state.LastAttacker
	state.Target = state.Target or attacker
	if not quiet then
		for _, other in self.information do
			if other ~= state and other.Hostile and not other.Dead and not other.Target and other.Row.id == state.Row.id
				and (other.Root.Position - state.Root.Position).Magnitude <= Config.Combat.AssistRange then
				other.Target = attacker
			end
		end
	end
end

function module:OnDeath(state)
	if state.Dead then
		return
	end
	state.Dead = true
	state.Model:SetAttribute("Casting", nil)
	state.Model:SetAttribute("Dead", true)
	self.includes.Spells["Auras.h"]:Clear(state)
	state.Hitbox = module.LayDown(state.Model)
	local Entities = self.includes.Entities["EntityPlayer.h"]
	local Combat = self.includes.Combat["Combat.h"]
	local Loot = self.includes.Combat["Loot.h"]
	local killer = state.LastAttacker
	self.includes.System["Effects.h"]:Play("Smoke", state.Row.guid, 8)
	if killer and killer.Parent == Players then
		Combat:Log(killer, ("%s dies."):format(state.Template.name), Config.Chat.Colors.HIT)
		local xp = Config.Combat.KillXp(killer:GetAttribute("CharacterLevel") or 1, state.Level)
		if xp > 0 then
			Entities:GrantXp(killer, xp, state.Template.name .. " slain", true)
		end
		self.includes.Quests["Quests.h"]:OnKill(killer, state.Row.id, state.Root.Position)
		self.includes.Social["Reputation.h"]:OnKill(killer, state.Template)
		self.includes.Social["Achievements.h"]:OnKill(killer)
	end
	local loot = Loot:Roll("creature_loot_template", state.Row.id, state.Template.mingold, state.Template.maxgold)
	if not Loot:IsEmpty(loot) then
		local Party = self.includes.Social["Party.h"]
		Loot:Register({ Guid = state.Row.guid, Name = state.Template.name, Root = state.Hitbox, Loot = loot,
			MayLoot = function(player)
				return not killer or killer == player or table.find(Party:MembersOf(killer), player) ~= nil
			end,
			OnEmpty = function()
				self:ClearCorpse(state.Row.guid)
			end })
		self.includes.System["Effects.h"]:Attach("Sparkle", state.Hitbox)
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Loot"
		prompt.ObjectText = state.Template.name
		prompt.MaxActivationDistance = 8
		prompt.RequiresLineOfSight = false
		prompt.Parent = state.Hitbox
		prompt.Triggered:Connect(function(player)
			Loot:Open(player, state.Row.guid)
		end)
	end
	local guid = state.Row.guid
	task.delay(Config.Combat.CorpseSeconds, function()
		if self.information[tostring(guid)] == state then
			self:Despawn(guid)
		end
	end)
	task.delay(state.Row.spawntimesecs or Config.Combat.DefaultRespawn, function()
		local row = self:DB():Get("creature", guid)
		if row and not self.information[tostring(guid)] then
			self:Spawn(row)
		end
	end)
end

-- Idle movement: walk the spawn's waypoints in order, or wander around home.
local function idle(self, state)
	local humanoid, here = state.Humanoid, state.Root.Position
	local points = state.Row.waypoints
	if points and #points > 0 then
		local p = points[state.Waypoint]
		local goal = Vector3.new(p[1], p[2], p[3])
		if (flat(here) - flat(goal)).Magnitude < 3 then
			state.Waypoint = state.Waypoint % #points + 1
			if os.clock() < state.NextWander then
				return
			end
			state.NextWander = os.clock() + (p.wait or 0)
		else
			humanoid:MoveTo(goal)
		end
		return
	end
	local fromHome = (flat(here) - flat(state.Home.Position)).Magnitude
	local wander = state.Template.wander or 0
	if fromHome > math.max(2, wander + 4) then
		humanoid:MoveTo(state.Home.Position)
	elseif wander > 0 and os.clock() >= state.NextWander then
		state.NextWander = os.clock() + Config.Combat.WanderSeconds * (0.5 + math.random())
		local angle = math.random() * math.pi * 2
		humanoid:MoveTo(state.Home.Position + Vector3.new(math.cos(angle), 0, math.sin(angle)) * wander * math.random())
	end
	if state.Hostile and humanoid.Health < humanoid.MaxHealth and not state.Target then
		humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + humanoid.MaxHealth * 0.05)
	end
end

-- One brain step.
function module:Think(state)
	if state.Dead or not state.Model.Parent then
		return
	end
	local Combat = self.includes.Combat["Combat.h"]
	local Auras = self.includes.Spells["Auras.h"]
	local template, root, humanoid = state.Template, state.Root, state.Humanoid
	local here = root.Position
	if Auras:Has(state, "stun") then
		humanoid:MoveTo(here)
		return
	end
	if state.Owner then
		return self.includes.Content["Pets.h"]:Think(state)
	end
	if not state.Hostile then
		return idle(self, state)
	end

	local target = state.Target
	local targetRoot = target and Combat:Root(target)
	if target and (not targetRoot or not Combat:Alive(target) or (Combat:IsPlayer(target) and target.Parent ~= Players)
		or (flat(targetRoot.Position) - flat(state.Home.Position)).Magnitude > 60) then
		state.Target = nil
		target = nil
	end

	if not target then
		local nearest, best = nil, template.aggro or 15
		for _, player in Players:GetPlayers() do
			local r = Combat:Root(player)
			if r and Combat:Alive(player) then
				local d = (r.Position - here).Magnitude
				if d < best then
					nearest, best = player, d
				end
			end
		end
		state.Target = nearest
		if not nearest then
			return idle(self, state)
		end
		target, targetRoot = nearest, Combat:Root(nearest)
		self:Aggro(state.Row.guid, nearest)
	end

	Combat:Enter(target)
	if Combat:IsPlayer(target) then
		self.includes.Content["Pets.h"]:Assist(target, state)
	end
	if state.Model:GetAttribute("Casting") then
		humanoid:MoveTo(here)
		return
	end
	-- spells first when one is ready, about a third of the time
	if template.spells and #template.spells > 0 and math.random() < 0.35 then
		local name = template.spells[math.random(#template.spells)]
		if self.includes.Spells["Spells.h"]:CreatureCast(state, name, target) then
			humanoid:MoveTo(here)
			return
		end
	end
	local distance = (targetRoot.Position - here).Magnitude
	if distance > Config.Combat.Range then
		humanoid:MoveTo(targetRoot.Position)
	else
		humanoid:MoveTo(here)
		if os.clock() >= state.NextSwing then
			state.NextSwing = os.clock() + Config.Combat.SwingSeconds
			local roll = Combat:Roll(state, target)
			if roll == "miss" or roll == "dodge" then
				Combat:Log(target, ("%s %s."):format(template.name, if roll == "miss" then "misses you" else "attacks. You dodge"), Config.Chat.Colors.HURT)
			else
				local damage = math.random(template.dmgmin or 1, math.max(template.dmgmax or 1, template.dmgmin or 1))
				Combat:Damage(state, target, if roll == "crit" then damage * 2 else damage, "physical", if roll == "crit" then "attack crits" else "attack")
			end
		end
	end
end

function module:Add(entry, ground: CFrame, by: Player)
	assert(self:Template(entry), "no creature_template entry " .. tostring(entry))
	local row = self:DB().ToRow(ground)
	row.id = tonumber(entry) or entry
	row.by = by.UserId
	row = self:DB():Insert("creature", row)
	self:Spawn(row)
	return row
end

function module:Move(guid, ground: CFrame): boolean
	local row = self:DB():Update("creature", guid, self:DB().ToRow(ground))
	if row then
		self:Spawn(row)
	end
	return row ~= nil
end

-- Waypoints are world positions walked in order; { x, y, z, wait = seconds }.
function module:AddWaypoint(guid, position: Vector3, wait: number?): number
	local row = assert(self:DB():Get("creature", guid), "no creature " .. tostring(guid))
	local points = row.waypoints or {}
	table.insert(points, { position.X, position.Y, position.Z, wait = wait })
	self:Spawn(self:DB():Update("creature", guid, { waypoints = points }))
	return #points
end

function module:ClearWaypoints(guid)
	self:Spawn(self:DB():Update("creature", guid, { waypoints = {} }))
end

function module:Delete(guid): boolean
	local had = self:State(guid) ~= nil
	self:Despawn(guid)
	return self:DB():Delete("creature", guid) or had
end

function module:Respawn(entry)
	for _, row in self:DB():Select("creature") do
		if entry == nil or tostring(row.id) == tostring(entry) then
			self:Spawn(row)
		end
	end
end

function module:Start()
	-- Seed any template that is missing by name, so new seeds reach old databases.
	local DB = self:DB()
	local byName = {}
	for _, row in DB:Select("creature_template") do
		byName[row.name] = row
	end
	for _, template in SEED do
		local existing = byName[template.name]
		if not existing then
			byName[template.name] = DB:Insert("creature_template", table.clone(template))
		else
			local fields = {}
			for _, key in { "innkeeper", "banker", "spells", "wander", "beast" } do
				if template[key] ~= nil and existing[key] == nil then
					fields[key] = template[key]
				end
			end
			if next(fields) then
				DB:Update("creature_template", existing.entry, fields)
			end
		end
	end
	local seededLoot = {}
	for _, row in DB:Select("creature_loot_template") do
		seededLoot[tostring(row.entry)] = true
	end
	for _, loot in LOOT_SEED do
		local creature = byName[loot.creature]
		local item = self.includes.Content["Items.h"]:ByName(loot.item)
		if creature and item and not seededLoot[tostring(creature.entry)] then
			DB:Insert("creature_loot_template", { entry = creature.entry, item = item.entry, chance = loot.chance, mincount = loot.mincount, maxcount = loot.maxcount })
		end
	end
	self:Respawn()
	DB:OnRemote("creature", function(op, key, row)
		if op == "set" then
			self:Spawn(row)
		else
			self:Despawn(key)
		end
	end)
	DB:OnRemote("creature_template", function(_, key)
		self:Respawn(key)
	end)
	task.spawn(function()
		while true do
			task.wait(0.25)
			for _, state in self.information do
				if state.Moves then
					self:Think(state)
				end
			end
		end
	end)
end

return Base(module, {
	{ Path = "World/Database", Imports = "WorldDB.h" },
	{ Path = "World/Combat", Imports = "Combat.h|Loot.h" },
	{ Path = "Global/System", Imports = "Effects.h" },
	{ Path = "Auth/Security", Imports = "Packet.h" },
	{ Path = "Auth/Entities", Imports = "EntityPlayer.h" },
	{ Path = "Auth/Social", Imports = "Party.h|Reputation.h|Achievements.h" },
	{ Path = "World/Content", Imports = "Vendors.h|Items.h|Pets.h" },
	{ Path = "World/Zones", Imports = "GameEvents.h" },
	{ Path = "World/Quests", Imports = "Quests.h" },
	{ Path = "World/Spells", Imports = "Spells.h|Auras.h" },
})
