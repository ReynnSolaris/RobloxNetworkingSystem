local Base = require(game:GetService("ServerStorage").ServerModules["Template.h"])
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Opcodes = require(ReplicatedStorage.Shared.Opcodes)
local Config = require(ReplicatedStorage.Shared.Config)
local module = {}

-- creature_template is the asset: { entry, name, subname, modelid, scale, gossip }.
-- creature is a spawn of one: { guid, id = entry, x, y, z, o }. Models stand anchored
-- under Workspace/Creatures with Guid and Entry attributes and a Talk prompt.
-- modelid: "default", "user:<UserId>" (that account's look), "model:<Name>" (a rig
-- under ServerStorage/CreatureModels).

local SEED = {
	{ name = "Innkeeper", subname = "Innkeeper", modelid = "default", scale = 1, gossip = "Welcome, traveler. Rest your feet a while." },
	{ name = "Town Guard", subname = "Guard", modelid = "default", scale = 1.05, gossip = "Move along, citizen." },
	{ name = "General Goods", subname = "Vendor", modelid = "default", scale = 1, gossip = "Fine wares, fair prices." },
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

function module:DB()
	return self.includes.Database["WorldDB.h"]
end

function module:Template(entry)
	return self:DB():Get("creature_template", entry)
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

function module:Spawn(row)
	local template = self:Template(row.id)
	local existing = self:Find(row.guid)
	if existing then
		existing:Destroy()
	end
	if not template then
		return nil
	end
	local model = build(template.modelid or "default")
	model.Name = template.name
	model:SetAttribute("Guid", tostring(row.guid))
	model:SetAttribute("Entry", tostring(row.id))
	local humanoid = assert(model:FindFirstChildOfClass("Humanoid"), "creature model needs a Humanoid") :: Humanoid
	humanoid.DisplayName = template.name
	local root = assert(model:FindFirstChild("HumanoidRootPart"), "creature model needs a HumanoidRootPart") :: BasePart
	root.Anchored = true
	if template.scale and template.scale ~= 1 then
		model:ScaleTo(template.scale)
	end

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

	-- feet on the stored position: lift the pivot by its height above the box bottom
	local box, size = model:GetBoundingBox()
	local lift = model:GetPivot().Position.Y - (box.Position.Y - size.Y / 2)
	model:PivotTo(self:DB().ToCFrame(row) * CFrame.new(0, lift, 0))
	model.Parent = folder()
	return model
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
	local model = self:Find(guid)
	if model then
		model:Destroy()
	end
	return self:DB():Delete("creature", guid) or model ~= nil
end

function module:Respawn(entry)
	for _, row in self:DB():Select("creature") do
		if entry == nil or tostring(row.id) == tostring(entry) then
			self:Spawn(row)
		end
	end
end

function module:Start()
	local DB = self:DB()
	if #DB:Select("creature_template") == 0 then
		for _, template in SEED do
			DB:Insert("creature_template", template)
		end
	end
	self:Respawn()
	DB:OnRemote("creature", function(op, key, row)
		if op == "set" then
			self:Spawn(row)
		else
			local model = self:Find(key)
			if model then
				model:Destroy()
			end
		end
	end)
	DB:OnRemote("creature_template", function(_, key)
		self:Respawn(key)
	end)
end

return Base(module, {
	{ Path = "World/Database", Imports = "WorldDB.h" },
	{ Path = "Auth/Security", Imports = "Packet.h" },
})
