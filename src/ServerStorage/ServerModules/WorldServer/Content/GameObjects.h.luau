local Base = require(game:GetService("ServerStorage").ServerModules["Template.h"])
local ServerStorage = game:GetService("ServerStorage")
local InsertService = game:GetService("InsertService")
local module = {}

-- gameobject_template is the asset: { entry, name, modelid, size }. gameobject is a
-- spawn: { guid, id = entry, x, y, z, o, scale }. modelid is a Model name under
-- ServerStorage/ObjectTemplates or "asset:<id>". Spawns sit flush on the ground.

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

function module:Find(guid): Model?
	for _, child in folder():GetChildren() do
		if child:GetAttribute("Guid") == tostring(guid) then
			return child
		end
	end
	return nil
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

function module:Spawn(row)
	local template = self:Template(row.id)
	local existing = self:Find(row.guid)
	if existing then
		existing:Destroy()
	end
	if not template then
		return nil
	end
	local model = build(template.modelid)
	model.Name = template.name
	model:SetAttribute("Guid", tostring(row.guid))
	model:SetAttribute("Entry", tostring(row.id))
	local scale = (row.scale or 1) * (template.size or 1)
	if scale ~= 1 then
		model:ScaleTo(scale)
	end
	local box, size = model:GetBoundingBox()
	local lift = model:GetPivot().Position.Y - (box.Position.Y - size.Y / 2)
	model:PivotTo(self:DB().ToCFrame(row) * CFrame.new(0, lift, 0))
	if template.type == "mailbox" then
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Open"
		prompt.ObjectText = "Mailbox"
		prompt.MaxActivationDistance = 8
		prompt.RequiresLineOfSight = false
		prompt.Parent = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
		prompt.Triggered:Connect(function(player)
			self.includes.Mail["Mail.h"]:Open(player, row.guid)
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
	local model = self:Find(guid)
	if model then
		model:Destroy()
	end
	return self:DB():Delete("gameobject", guid) or model ~= nil
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
		local kind = model:GetAttribute("Type")
		if not byName[model.Name] then
			DB:Insert("gameobject_template", { name = model.Name, modelid = model.Name, size = 1, type = kind })
		elseif kind and byName[model.Name].type ~= kind then
			DB:Update("gameobject_template", byName[model.Name].entry, { type = kind })
		end
	end
	self:Respawn()
	DB:OnRemote("gameobject", function(op, key, row)
		if op == "set" then
			self:Spawn(row)
		else
			local model = self:Find(key)
			if model then
				model:Destroy()
			end
		end
	end)
	DB:OnRemote("gameobject_template", function(_, key)
		self:Respawn(key)
	end)
end

return Base(module, {
	{ Path = "World/Database", Imports = "WorldDB.h" },
	{ Path = "World/Mail", Imports = "Mail.h" },
})
