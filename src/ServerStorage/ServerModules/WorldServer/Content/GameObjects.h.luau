local Base = require(game:GetService("ServerStorage").ServerModules["Template.h"])
local ServerStorage = game:GetService("ServerStorage")
local InsertService = game:GetService("InsertService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Opcodes = require(ReplicatedStorage.Shared.Opcodes)
local Config = require(ReplicatedStorage.Shared.Config)
local module = {}

-- gameobject_template is the asset: { entry, name, modelid, size, type, mingold,
-- maxgold, skill, reqskill }. gameobject is a spawn: { guid, id = entry, x, y, z, o,
-- scale, spawntimesecs }. modelid is a Model name under ServerStorage/
-- ObjectTemplates or "asset:<id>". Types: mailbox opens mail; chest rolls
-- gameobject_loot_template and despawns until it respawns; door swings on its
-- hinge; node (vein, herb) is a chest that needs a profession skill.

local LOOT_SEED = {
	{ object = "chest", item = "Linen Cloth", chance = 80, mincount = 2, maxcount = 5 },
	{ object = "chest", item = "Tough Jerky", chance = 40, mincount = 1, maxcount = 2 },
	{ object = "chest", item = "Ring of Precision", chance = 10, mincount = 1, maxcount = 1 },
	{ object = "copper_vein", item = "Copper Ore", chance = 100, mincount = 1, maxcount = 3 },
	{ object = "copper_vein", item = "Rough Stone", chance = 50, mincount = 1, maxcount = 2 },
	{ object = "peacebloom", item = "Peacebloom", chance = 100, mincount = 1, maxcount = 2 },
	{ object = "peacebloom", item = "Silverleaf", chance = 40, mincount = 1, maxcount = 1 },
}

local function folder(): Folder
	local f = workspace:FindFirstChild("GameObjects")
	if not f then
		f = Instance.new("Folder")
		f.Name = "GameObjects"
		f.Parent = workspace
	end
	return f
end

local function build(modelid: string): Model
	local assetId = modelid:match("^asset:(%d+)$")
	if assetId then
		local ok, asset = pcall(InsertService.LoadAsset, InsertService, tonumber(assetId))
		assert(ok, "could not load asset " .. assetId)
		local model = asset:FindFirstChildOfClass("Model") or asset
		model.Parent = nil
		return model
	end
	local source = ServerStorage:WaitForChild("ObjectTemplates"):FindFirstChild(modelid)
	assert(source, "no object template named " .. modelid)
	return source:Clone()
end

-- Ground height under a point, ignoring characters and placed content.
function module.GroundY(position: Vector3, ignore: { Instance }): number
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	local hit = workspace:Raycast(position + Vector3.new(0, 10, 0), Vector3.new(0, -60, 0), params)
	return if hit then hit.Position.Y else position.Y
end

function module:DB()
	return self.includes.Database["WorldDB.h"]
end

function module:Template(entry)
	return self:DB():Get("gameobject_template", entry)
end

function module:State(guid)
	return self.information[tostring(guid)]
end

function module:Find(guid): Model?
	local state = self:State(guid)
	return state and state.Model
end

function module:Near(position: Vector3, radius: number): { Model }
	local out = {}
	for _, child in folder():GetChildren() do
		if (child:GetPivot().Position - position).Magnitude <= radius then
			table.insert(out, child)
		end
	end
	table.sort(out, function(a, b)
		return (a:GetPivot().Position - position).Magnitude < (b:GetPivot().Position - position).Magnitude
	end)
	return out
end

local function prompt(model: Model, action: string, label: string, handler)
	local p = Instance.new("ProximityPrompt")
	p.ActionText = action
	p.ObjectText = label
	p.MaxActivationDistance = 8
	p.RequiresLineOfSight = false
	p.Parent = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
	p.Triggered:Connect(handler)
	return p
end

-- Chests and nodes: first opener rolls the loot; everyone may take from it.
function module:OpenChest(player: Player, state)
	local template = state.Template
	local Loot = self.includes.Combat["Loot.h"]
	if template.skill then
		local ok, reason = self.includes.Spells["Skills.h"]:CanGather(player, template.skill, template.reqskill or 1)
		if not ok then
			return self.includes.Chat["Chat.h"]:System(player, reason)
		end
	end
	if not Loot:Source(state.Row.guid) then
		local loot = Loot:Roll("gameobject_loot_template", state.Row.id, template.mingold, template.maxgold)
		if Loot:IsEmpty(loot) then
			loot.Money = math.random(1, 10)
		end
		Loot:Register({ Guid = state.Row.guid, Name = template.name, Root = state.Model.PrimaryPart or state.Model:FindFirstChildWhichIsA("BasePart"), Loot = loot,
			OnEmpty = function()
				if template.skill then
					self.includes.Spells["Skills.h"]:OnGather(player, template.skill, template.reqskill or 1)
				end
				self:Despawn(state.Row.guid)
				task.delay(state.Row.spawntimesecs or 300, function()
					local row = self:DB():Get("gameobject", state.Row.guid)
					if row and not self.information[tostring(state.Row.guid)] then
						self:Spawn(row)
					end
				end)
			end })
	end
	Loot:Open(player, state.Row.guid)
end

-- Doors swing ninety degrees around the hinge edge of their panel.
function module:ToggleDoor(state)
	local panel = state.Model.PrimaryPart or state.Model:FindFirstChildWhichIsA("BasePart")
	if not panel then
		return
	end
	local hinge = panel.CFrame * CFrame.new(-panel.Size.X / 2, 0, 0)
	local angle = if state.Open then -math.pi / 2 else math.pi / 2
	state.Model:PivotTo(hinge * CFrame.Angles(0, angle, 0) * hinge:Inverse() * state.Model:GetPivot())
	state.Open = not state.Open
	state.Model:SetAttribute("Open", state.Open)
	local p = state.Model:FindFirstChildWhichIsA("ProximityPrompt", true)
	if p then
		p.ActionText = if state.Open then "Close" else "Open"
	end
end

function module:Use(player: Player, guid)
	local state = self:State(guid)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not state or not root or (state.Model:GetPivot().Position - root.Position).Magnitude > 12 then
		return
	end
	local kind = state.Template.type
	if kind == "mailbox" then
		self.includes.Mail["Mail.h"]:Open(player, guid)
	elseif kind == "chest" or kind == "node" then
		self:OpenChest(player, state)
	elseif kind == "door" then
		self:ToggleDoor(state)
	elseif kind == "auctioneer" then
		self.includes.Content["Auction.h"]:Open(player, guid)
	end
end

function module:Despawn(guid)
	local state = self.information[tostring(guid)]
	if state then
		self.information[tostring(guid)] = nil
		self.includes.Combat["Loot.h"]:Unregister(guid)
		state.Model:Destroy()
	end
end

local LABEL = { mailbox = "Mailbox", chest = "Chest", door = "Door", node = "Gather", auctioneer = "Auction House" }

function module:Spawn(row)
	local template = self:Template(row.id)
	self:Despawn(row.guid)
	if not template then
		return nil
	end
	local model = build(template.modelid)
	model.Name = template.name
	model:SetAttribute("Guid", tostring(row.guid))
	model:SetAttribute("Entry", tostring(row.id))
	model:SetAttribute("Type", template.type)
	local scale = (row.scale or 1) * (template.size or 1)
	if scale ~= 1 then
		model:ScaleTo(scale)
	end
	local box, size = model:GetBoundingBox()
	local lift = model:GetPivot().Position.Y - (box.Position.Y - size.Y / 2)
	model:PivotTo(self:DB().ToCFrame(row) * CFrame.new(0, lift, 0))
	local state = { Row = row, Template = template, Model = model, Open = false }
	self.information[tostring(row.guid)] = state
	if template.type and LABEL[template.type] then
		prompt(model, if template.type == "node" then "Gather" else "Open", if template.type == "node" then template.name else LABEL[template.type], function(player)
			self:Use(player, row.guid)
		end)
	end
	model.Parent = folder()
	return model
end

function module:Add(entry, ground: CFrame, scale: number?, by: Player)
	assert(self:Template(entry), "no gameobject_template entry " .. tostring(entry))
	local row = self:DB().ToRow(ground)
	row.id = tonumber(entry) or entry
	row.scale = scale or 1
	row.by = by.UserId
	row = self:DB():Insert("gameobject", row)
	self:Spawn(row)
	return row
end

function module:Move(guid, ground: CFrame): boolean
	local row = self:DB():Update("gameobject", guid, self:DB().ToRow(ground))
	if row then
		self:Spawn(row)
	end
	return row ~= nil
end

function module:Turn(guid, degrees: number): boolean
	local current = self:DB():Get("gameobject", guid)
	if not current then
		return false
	end
	self:Spawn(self:DB():Update("gameobject", guid, { o = ((current.o or 0) + degrees) % 360 }))
	return true
end

function module:Delete(guid): boolean
	local had = self:State(guid) ~= nil
	self:Despawn(guid)
	return self:DB():Delete("gameobject", guid) or had
end

function module:Respawn(entry)
	for _, row in self:DB():Select("gameobject") do
		if entry == nil or tostring(row.id) == tostring(entry) then
			self:Spawn(row)
		end
	end
end

function module:Start()
	local DB = self:DB()
	local byName = {}
	for _, row in DB:Select("gameobject_template") do
		byName[row.name] = row
	end
	for _, model in ServerStorage:WaitForChild("ObjectTemplates"):GetChildren() do
		local fields = { type = model:GetAttribute("Type"), skill = model:GetAttribute("Skill"), reqskill = model:GetAttribute("ReqSkill"),
			mingold = model:GetAttribute("MinGold"), maxgold = model:GetAttribute("MaxGold") }
		local existing = byName[model.Name]
		if not existing then
			fields.name, fields.modelid, fields.size = model.Name, model.Name, 1
			byName[model.Name] = DB:Insert("gameobject_template", fields)
		else
			local changed = {}
			for key, value in fields do
				if existing[key] ~= value then
					changed[key] = value
				end
			end
			if next(changed) then
				DB:Update("gameobject_template", existing.entry, changed)
			end
		end
	end
	local seeded = {}
	for _, row in DB:Select("gameobject_loot_template") do
		seeded[tostring(row.entry)] = true
	end
	for _, loot in LOOT_SEED do
		local object = byName[loot.object]
		local item = self.includes.Content["Items.h"]:ByName(loot.item)
		if object and item and not seeded[tostring(object.entry)] then
			DB:Insert("gameobject_loot_template", { entry = object.entry, item = item.entry, chance = loot.chance, mincount = loot.mincount, maxcount = loot.maxcount })
		end
	end
	self:Respawn()
	DB:OnRemote("gameobject", function(op, key, row)
		if op == "set" then
			self:Spawn(row)
		else
			self:Despawn(key)
		end
	end)
	DB:OnRemote("gameobject_template", function(_, key)
		self:Respawn(key)
	end)
	self.includes.Security["Packet.h"]:On(Opcodes.CMSG_GAMEOBJ_USE, function(player, data)
		if typeof(data) == "table" and data.Guid ~= nil then
			self:Use(player, data.Guid)
		end
	end)
end

return Base(module, {
	{ Path = "World/Database", Imports = "WorldDB.h" },
	{ Path = "World/Mail", Imports = "Mail.h" },
	{ Path = "World/Combat", Imports = "Loot.h" },
	{ Path = "World/Spells", Imports = "Skills.h" },
	{ Path = "World/Content", Imports = "Auction.h|Items.h" },
	{ Path = "Auth/Chat", Imports = "Chat.h" },
	{ Path = "Auth/Security", Imports = "Packet.h" },
})
