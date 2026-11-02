local Base = require(game:GetService("ServerStorage").ServerModules["Template.h"])
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Opcodes = require(ReplicatedStorage.Shared.Opcodes)
local Config = require(ReplicatedStorage.Shared.Config)
local module = {}

-- creature_template is the asset: { entry, name, subname, modelid, scale, gossip,
-- faction (friendly|hostile), minlevel, maxlevel, health, dmgmin, dmgmax, aggro,
-- speed, mingold, maxgold }. creature is a spawn: { guid, id, x, y, z, o, spawntimesecs }.
-- Friendly creatures stand anchored with a Talk prompt. Hostile ones get a level,
-- health, a simple brain (aggro, chase, melee, leash) and drop loot from
-- creature_loot_template { id, entry, item, chance, mincount, maxcount }.

local SEED = {
	{ name = "Innkeeper", subname = "Innkeeper", modelid = "default", scale = 1, gossip = "Welcome, traveler. Rest your feet a while.", faction = "friendly" },
	{ name = "Town Guard", subname = "Guard", modelid = "default", scale = 1.05, gossip = "Move along, citizen.", faction = "friendly" },
	{ name = "General Goods", subname = "Vendor", modelid = "default", scale = 1, gossip = "Fine wares, fair prices.", faction = "friendly" },
	{ name = "Kobold Vermin", modelid = "default", scale = 0.85, faction = "hostile", minlevel = 1, maxlevel = 2, health = 40, dmgmin = 2, dmgmax = 4, aggro = 15, speed = 12, mingold = 1, maxgold = 5 },
	{ name = "Young Wolf", modelid = "default", scale = 0.9, faction = "hostile", minlevel = 2, maxlevel = 3, health = 55, dmgmin = 3, dmgmax = 5, aggro = 18, speed = 14, mingold = 0, maxgold = 3 },
}
-- creature by name, item by entry; resolved to entries when seeded
local LOOT_SEED = {
	{ creature = "Kobold Vermin", item = 2, chance = 60, mincount = 1, maxcount = 3 },
	{ creature = "Kobold Vermin", item = 4, chance = 25, mincount = 1, maxcount = 1 },
	{ creature = "Young Wolf", item = 2, chance = 30, mincount = 1, maxcount = 2 },
	{ creature = "Young Wolf", item = 5, chance = 5, mincount = 1, maxcount = 1 },
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

function module:DB()
	return self.includes.Database["WorldDB.h"]
end

function module:Template(entry)
	return self:DB():Get("creature_template", entry)
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
		state.Model:Destroy()
	end
end

function module:Spawn(row)
	local template = self:Template(row.id)
	self:Despawn(row.guid)
	if not template then
		return nil
	end
	local hostile = template.faction == "hostile"
	local level = math.random(template.minlevel or 1, math.max(template.maxlevel or 1, template.minlevel or 1))
	local model = build(template.modelid or "default")
	model.Name = template.name
	model:SetAttribute("Guid", tostring(row.guid))
	model:SetAttribute("Entry", tostring(row.id))
	model:SetAttribute("Level", level)
	model:SetAttribute("Faction", template.faction or "friendly")
	local humanoid = assert(model:FindFirstChildOfClass("Humanoid"), "creature model needs a Humanoid") :: Humanoid
	local root = assert(model:FindFirstChild("HumanoidRootPart"), "creature model needs a HumanoidRootPart") :: BasePart
	humanoid.DisplayName = template.name
	humanoid.WalkSpeed = template.speed or 12
	if template.scale and template.scale ~= 1 then
		model:ScaleTo(template.scale)
	end
	if hostile then
		humanoid.MaxHealth = math.floor((template.health or 40) * (1 + 0.15 * (level - (template.minlevel or 1))))
		humanoid.Health = humanoid.MaxHealth
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer
	else
		root.Anchored = true
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Talk"
		prompt.ObjectText = template.subname or template.name
		prompt.MaxActivationDistance = 8
		prompt.RequiresLineOfSight = false
		prompt.Parent = root
		prompt.Triggered:Connect(function(player)
			self.includes.Security["Packet.h"]:Send(player, Opcodes.SMSG_MESSAGECHAT,
				{ Channel = "SAY", Sender = template.name, Text = template.gossip or "Greetings, traveler." })
		end)
	end

	local box, size = model:GetBoundingBox()
	local lift = model:GetPivot().Position.Y - (box.Position.Y - size.Y / 2)
	local home = self:DB().ToCFrame(row) * CFrame.new(0, lift, 0)
	model:PivotTo(home)
	model.Parent = folder()
	if hostile then
		root:SetNetworkOwner(nil)
	end

	local state = { Row = row, Template = template, Model = model, Humanoid = humanoid, Root = root, Home = home, Level = level,
		Hostile = hostile, Target = nil, NextSwing = 0, LastAttacker = nil, Dead = false }
	self.information[tostring(row.guid)] = state
	humanoid.Died:Once(function()
		self:OnDeath(state)
	end)
	return model
end

-- Called by Combat when a player lands a hit.
function module:Aggro(guid, player: Player)
	local state = self:State(guid)
	if state and state.Hostile and not state.Dead then
		state.LastAttacker = player
		state.Target = state.Target or player
	end
end

function module:OnDeath(state)
	if state.Dead then
		return
	end
	state.Dead = true
	local Entities = self.includes.Entities["EntityPlayer.h"]
	local Combat = self.includes.Combat["Combat.h"]
	local killer = state.LastAttacker
	if killer and killer.Parent == Players then
		Combat:Log(killer, ("%s dies."):format(state.Template.name), Config.Chat.Colors.HIT)
		local xp = Config.Combat.KillXp(killer:GetAttribute("CharacterLevel") or 1, state.Level)
		if xp > 0 then
			Entities:GrantXp(killer, xp, state.Template.name .. " slain")
		end
		for _, loot in self:DB():Select("creature_loot_template") do
			if tostring(loot.entry) == tostring(state.Row.id) and math.random() * 100 < (loot.chance or 0) then
				Entities:AddItem(killer, loot.item, math.random(loot.mincount or 1, math.max(loot.maxcount or 1, loot.mincount or 1)))
			end
		end
		local gold = math.random(state.Template.mingold or 0, math.max(state.Template.maxgold or 0, state.Template.mingold or 0))
		if gold > 0 then
			Entities:AddMoney(killer, gold)
		end
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

-- One brain step for a hostile creature.
function module:Think(state)
	if state.Dead or not state.Model.Parent then
		return
	end
	local Combat = self.includes.Combat["Combat.h"]
	local template, root, humanoid = state.Template, state.Root, state.Humanoid
	local here = root.Position
	local fromHome = (flat(here) - flat(state.Home.Position)).Magnitude

	local target = state.Target
	local targetRoot = target and target.Character and target.Character:FindFirstChild("HumanoidRootPart")
	local targetHumanoid = target and target.Character and target.Character:FindFirstChildOfClass("Humanoid")
	if target and (not targetRoot or not targetHumanoid or targetHumanoid.Health <= 0 or target.Parent ~= Players
		or (flat(targetRoot.Position) - flat(state.Home.Position)).Magnitude > 60) then
		state.Target = nil
		target = nil
	end

	if not target then
		local nearest, best = nil, template.aggro or 15
		for _, player in Players:GetPlayers() do
			local r = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			local h = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
			if r and h and h.Health > 0 and player:GetAttribute("InWorld") then
				local d = (r.Position - here).Magnitude
				if d < best then
					nearest, best = player, d
				end
			end
		end
		state.Target = nearest
		if not nearest then
			if fromHome > 2 then
				humanoid:MoveTo(state.Home.Position)
			elseif humanoid.Health < humanoid.MaxHealth then
				humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + humanoid.MaxHealth * 0.1)
			end
			return
		end
		target, targetRoot, targetHumanoid = nearest, nearest.Character.HumanoidRootPart, nearest.Character:FindFirstChildOfClass("Humanoid")
	end

	local distance = (targetRoot.Position - here).Magnitude
	if distance > Config.Combat.Range then
		humanoid:MoveTo(targetRoot.Position)
	else
		humanoid:MoveTo(here)
		if os.clock() >= state.NextSwing then
			state.NextSwing = os.clock() + Config.Combat.SwingSeconds
			local damage = math.random(template.dmgmin or 1, math.max(template.dmgmax or 1, template.dmgmin or 1))
			targetHumanoid:TakeDamage(damage)
			Combat:Log(target, ("%s hits you for %d."):format(template.name, damage), Config.Chat.Colors.HURT)
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
		if not byName[template.name] then
			byName[template.name] = DB:Insert("creature_template", table.clone(template))
		end
	end
	if #DB:Select("creature_loot_template") == 0 then
		for _, loot in LOOT_SEED do
			local creature = byName[loot.creature]
			if creature then
				DB:Insert("creature_loot_template", { entry = creature.entry, item = loot.item, chance = loot.chance, mincount = loot.mincount, maxcount = loot.maxcount })
			end
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
				if state.Hostile then
					self:Think(state)
				end
			end
		end
	end)
end

return Base(module, {
	{ Path = "World/Database", Imports = "WorldDB.h" },
	{ Path = "World/Combat", Imports = "Combat.h" },
	{ Path = "Auth/Security", Imports = "Packet.h" },
	{ Path = "Auth/Entities", Imports = "EntityPlayer.h" },
})
