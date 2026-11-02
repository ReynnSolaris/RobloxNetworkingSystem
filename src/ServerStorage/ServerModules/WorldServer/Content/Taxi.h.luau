local Base = require(game:GetService("ServerStorage").ServerModules["Template.h"])
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Opcodes = require(ReplicatedStorage.Shared.Opcodes)
local Config = require(ReplicatedStorage.Shared.Config)
local module = {}

-- Flight paths. taxi_nodes: { id, name, x, y, z, cost }. taxi_path: { id, from,
-- to, cost, points = { {x,y,z} } }. A character keeps Taxi = { [nodeId] = true }
-- for the nodes it has discovered; talking to a flight master (creature with
-- flightmaster = true) discovers its node and lists the known destinations
-- with a path from here. Flying tweens the character along the path, high up,
-- with input locked and anticheat allowing the jump.

function module:DB()
	return self.includes.Database["WorldDB.h"]
end

function module:Node(id)
	return self:DB():Get("taxi_nodes", id)
end

-- The node a flight master stands at: the nearest within 20 studs.
function module:NodeAt(position: Vector3)
	local best, bestD = nil, 20
	for _, node in self:DB():Select("taxi_nodes") do
		local d = (Vector3.new(node.x, node.y, node.z) - position).Magnitude
		if d < bestD then
			best, bestD = node, d
		end
	end
	return best
end

function module:Path(from, to)
	for _, path in self:DB():Select("taxi_path") do
		if tostring(path.from) == tostring(from) and tostring(path.to) == tostring(to) then
			return path
		end
	end
	return nil
end

local function char(self, player: Player)
	local entity = self.includes.Entities["EntityPlayer.h"]:Get(player)
	local c = entity and entity.Active
	if c then
		c.Taxi = c.Taxi or {}
	end
	return c
end

function module:Discover(player: Player, node)
	local c = char(self, player)
	if c and not c.Taxi[tostring(node.id)] then
		c.Taxi[tostring(node.id)] = true
		self.includes.Database["WorldDatabase.h"]:Commit(player)
		self.includes.Chat["Chat.h"]:System(player, ("New flight path learned: %s."):format(node.name))
	end
end

function module:Show(player: Player, guid)
	local creature = self.includes.Content["Creatures.h"]:State(guid)
	local c = char(self, player)
	if not creature or not c then
		return
	end
	local here = self:NodeAt(creature.Root.Position)
	if not here then
		return self.includes.Chat["Chat.h"]:System(player, "This flight master has no flight path yet.")
	end
	self:Discover(player, here)
	local list = {}
	for id in c.Taxi do
		local node = self:Node(id)
		local path = node and self:Path(here.id, node.id)
		if node and path and node.id ~= here.id then
			table.insert(list, { Id = node.id, Name = node.name, Cost = path.cost or node.cost or 0 })
		end
	end
	table.sort(list, function(a, b)
		return a.Name < b.Name
	end)
	self.includes.Security["Packet.h"]:Send(player, Opcodes.SMSG_SHOWTAXINODES, { Guid = tostring(guid), Here = here.name, Nodes = list })
end

function module:Fly(player: Player, guid, to)
	local creature = self.includes.Content["Creatures.h"]:State(guid)
	local c = char(self, player)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local Chat = self.includes.Chat["Chat.h"]
	if not creature or not c or not root or self.information[player] then
		return
	end
	local here = self:NodeAt(creature.Root.Position)
	local node = self:Node(to)
	local path = here and node and self:Path(here.id, node.id)
	if not path or not c.Taxi[tostring(node.id)] then
		return Chat:System(player, "You don't know that flight path.")
	end
	local cost = path.cost or node.cost or 0
	if (c.Money or 0) < cost then
		return Chat:System(player, "You don't have enough money.")
	end
	self.includes.Entities["EntityPlayer.h"]:AddMoney(player, -cost)
	self.includes.Combat["Combat.h"]:Enter(player)
	local points = { root.Position }
	for _, p in (path.points or {}) do
		table.insert(points, Vector3.new(p[1], p[2], p[3]))
	end
	local landing = Vector3.new(node.x, node.y, node.z)
	table.insert(points, landing + Vector3.new(0, Config.Taxi.Height, 0))
	table.insert(points, landing + Vector3.new(0, 4, 0))
	if #path.points == 0 then
		table.insert(points, 2, root.Position + Vector3.new(0, Config.Taxi.Height, 0))
	end
	self.information[player] = true
	player:SetAttribute("Flying", node.name)
	local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
	task.spawn(function()
		root.Anchored = true
		for i = 2, #points do
			if player.Parent ~= Players or not root.Parent then
				break
			end
			local from, dest = points[i - 1], points[i]
			local time = (dest - from).Magnitude / Config.Taxi.Speed
			local look = CFrame.lookAt(from, Vector3.new(dest.X, from.Y, dest.Z) + (if (Vector3.new(dest.X, 0, dest.Z) - Vector3.new(from.X, 0, from.Z)).Magnitude < 0.1 then root.CFrame.LookVector else Vector3.zero))
			self.includes.Movement["Anticheat.h"]:Allow(player)
			local tween = TweenService:Create(root, TweenInfo.new(math.max(0.2, time), Enum.EasingStyle.Linear), { CFrame = CFrame.new(dest) * look.Rotation })
			tween:Play()
			tween.Completed:Wait()
		end
		if root.Parent then
			root.Anchored = false
		end
		self.includes.Movement["Anticheat.h"]:Allow(player)
		self.information[player] = nil
		player:SetAttribute("Flying", nil)
		if humanoid and humanoid.Parent then
			self.includes.Security["Packet.h"]:Send(player, Opcodes.SMSG_TAXI_DONE, { Name = node.name })
		end
	end)
end

function module:IsFlying(player: Player): boolean
	return self.information[player] == true
end

-- GM helpers
function module:AddNode(name: string, position: Vector3, cost: number?)
	return self:DB():Insert("taxi_nodes", { name = name, x = position.X, y = position.Y, z = position.Z, cost = cost or 100 })
end

function module:Connect(from, to, cost: number?)
	local a, b = self:Node(from), self:Node(to)
	assert(a and b, "no such node")
	for _, pair in { { a, b }, { b, a } } do
		if not self:Path(pair[1].id, pair[2].id) then
			self:DB():Insert("taxi_path", { from = pair[1].id, to = pair[2].id, cost = cost or 100, points = {} })
		end
	end
end

function module:Start()
	local Packet = self.includes.Security["Packet.h"]
	Packet:On(Opcodes.CMSG_ACTIVATETAXI, function(player, data)
		if typeof(data) == "table" then
			self:Fly(player, data.Guid, tonumber(data.Node))
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		self.information[player] = nil
	end)
end

return Base(module, {
	{ Path = "Auth/Security", Imports = "Packet.h" },
	{ Path = "Auth/Entities", Imports = "EntityPlayer.h" },
	{ Path = "Auth/Chat", Imports = "Chat.h" },
	{ Path = "World/Content", Imports = "Creatures.h" },
	{ Path = "World/Combat", Imports = "Combat.h" },
	{ Path = "World/Movement", Imports = "Anticheat.h" },
	{ Path = "World/Database", Imports = "WorldDB.h|WorldDatabase.h" },
})
