local Base = require(game:GetService("ServerStorage").ServerModules["Template.h"])
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Opcodes = require(ReplicatedStorage.Shared.Opcodes)
local Config = require(ReplicatedStorage.Shared.Config)
local module = {}

-- A zone is any Part tagged "Zone". Its Name is the zone name; attributes Pvp and
-- Safe describe it. Players are polled, and a change sends SMSG_ZONE_UPDATE.

local function contains(part: BasePart, position: Vector3): boolean
	local rel = part.CFrame:PointToObjectSpace(position)
	local half = part.Size / 2
	return math.abs(rel.X) <= half.X and math.abs(rel.Y) <= half.Y and math.abs(rel.Z) <= half.Z
end

function module:All(): { BasePart }
	return CollectionService:GetTagged("Zone")
end

function module:At(position: Vector3): BasePart?
	for _, part in self:All() do
		if part:IsA("BasePart") and contains(part, position) then
			return part
		end
	end
	return nil
end

function module:Current(player: Player): BasePart?
	return self.information[player]
end

function module:Start()
	local Packet = self.includes.Security["Packet.h"]
	task.spawn(function()
		while true do
			task.wait(Config.ZonePollSeconds)
			for _, player in Players:GetPlayers() do
				local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
				local zone = root and self:At(root.Position) or nil
				if zone ~= self.information[player] then
					self.information[player] = zone
					if zone then
						self.includes.Entities["EntityPlayer.h"]:Discover(player, zone.Name)
					end
					Packet:Send(player, Opcodes.SMSG_ZONE_UPDATE, if zone then {
						Name = zone.Name,
						Pvp = zone:GetAttribute("Pvp") == true,
						Safe = zone:GetAttribute("Safe") == true,
					} else {})
				end
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		self.information[player] = nil
	end)
end

return Base(module, {
	{ Path = "Auth/Security", Imports = "Packet.h" },
	{ Path = "Auth/Entities", Imports = "EntityPlayer.h" },
})
