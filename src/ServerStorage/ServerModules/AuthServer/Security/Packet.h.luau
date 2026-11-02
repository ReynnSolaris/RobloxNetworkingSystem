local Base = require(game:GetService("ServerStorage").ServerModules["Template.h"])
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Opcodes = require(ReplicatedStorage.Shared.Opcodes)
local Config = require(ReplicatedStorage.Shared.Config)
local module = {}

-- One RemoteEvent carries everything: (opcode, sequence, data).
-- Incoming packets must carry an increasing sequence, pass a token bucket,
-- and pass the guard (set by Session.h) before reaching a handler.

local handlers: { [number]: (Player, any) -> () } = {}
local guard = function(_player: Player, _opcode: number)
	return true
end
local clients: { [Player]: { tokens: number, last: number, seqIn: number, seqOut: number } } = {}

local function remote(): RemoteEvent
	local event = ReplicatedStorage:FindFirstChild("Packets")
	if not event then
		event = Instance.new("RemoteEvent")
		event.Name = "Packets"
		event.Parent = ReplicatedStorage
	end
	return event
end

local function state(player: Player)
	local s = clients[player]
	if not s then
		s = { tokens = Config.RateLimit.Burst, last = os.clock(), seqIn = 0, seqOut = 0 }
		clients[player] = s
	end
	return s
end

local function allow(s): boolean
	local now = os.clock()
	s.tokens = math.min(Config.RateLimit.Burst, s.tokens + (now - s.last) * Config.RateLimit.PerSecond)
	s.last = now
	if s.tokens < 1 then
		return false
	end
	s.tokens -= 1
	return true
end

function module:On(opcode: number, handler: (Player, any) -> ())
	handlers[opcode] = handler
end

function module:SetGuard(fn: (Player, number) -> boolean)
	guard = fn
end

function module:Send(player: Player, opcode: number, data: any)
	local s = state(player)
	s.seqOut += 1
	remote():FireClient(player, opcode, s.seqOut, data)
end

function module:Broadcast(opcode: number, data: any, except: Player?)
	for _, player in Players:GetPlayers() do
		if player ~= except then
			self:Send(player, opcode, data)
		end
	end
end

function module:Start()
	remote().OnServerEvent:Connect(function(player, opcode, seq, data)
		if typeof(opcode) ~= "number" or typeof(seq) ~= "number" or not Opcodes.IsClient(opcode) then
			return
		end
		local s = state(player)
		if seq <= s.seqIn then
			return
		end
		s.seqIn = seq
		if not allow(s) or not guard(player, opcode) then
			return
		end
		local handler = handlers[opcode]
		if handler then
			handler(player, data)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		clients[player] = nil
	end)
end

return Base(module)
