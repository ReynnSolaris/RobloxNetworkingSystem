local Base = require(game:GetService("ServerStorage").ServerModules["Template.h"])
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Opcodes = require(ReplicatedStorage.Shared.Opcodes)
local module = {}

-- Particle effects from ReplicatedStorage/Assets/Particles. Play sends a one-shot
-- to every client (the target is a player name, a creature guid or a position);
-- Attach puts an enabled emitter on a part so it replicates on its own.

local function emitter(name: string): ParticleEmitter?
	local folder = ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("Particles")
	return folder and folder:FindFirstChild(name)
end

function module:Play(name: string, target: Player | string | Vector3, count: number?)
	local spec = { Name = name, Count = count or 12 }
	if typeof(target) == "Instance" and target:IsA("Player") then
		spec.Player = target.Name
	elseif typeof(target) == "Vector3" then
		spec.Position = { target.X, target.Y, target.Z }
	else
		spec.Guid = tostring(target)
	end
	self.includes.Security["Packet.h"]:Broadcast(Opcodes.SMSG_PLAY_EFFECT, spec)
end

function module:Attach(name: string, part: BasePart): ParticleEmitter?
	local source = emitter(name)
	if not source then
		return nil
	end
	local clone = source:Clone()
	clone.Name = "Effect_" .. name
	clone.Enabled = true
	clone.Parent = part
	return clone
end

function module:Detach(name: string, part: BasePart)
	local existing = part:FindFirstChild("Effect_" .. name)
	if existing then
		existing:Destroy()
	end
end

return Base(module, {
	{ Path = "Auth/Security", Imports = "Packet.h" },
})
