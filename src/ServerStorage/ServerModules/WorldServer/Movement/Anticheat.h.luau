local Base = require(game:GetService("ServerStorage").ServerModules["Template.h"])
local Players = game:GetService("Players")
local Config = require(game:GetService("ReplicatedStorage").Shared.Config)
local module = {}

-- Movement validation. Every sample, the horizontal distance a character moved
-- is compared with what the server's own WalkSpeed allows. Over the limit:
-- snap back to the last good position and count a strike. Server-side moves
-- (teleports, spawns) call Allow first. GM mode is exempt.

local cfg = Config.Anticheat
local enabled = cfg.Enabled

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

function module:Allow(player: Player)
	local state = self.information[player]
	if state then
		state.skip = true
	end
end

function module:Strikes(player: Player): number
	local state = self.information[player]
	return if state then state.strikes else 0
end

function module:Reset(player: Player)
	if self.information[player] then
		self.information[player].strikes = 0
	end
end

function module:SetEnabled(on: boolean)
	enabled = on
end

function module:Enabled(): boolean
	return enabled
end

function module:Check(player: Player, dt: number)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or humanoid.Health <= 0 then
		self.information[player] = nil
		return
	end
	local state = self.information[player]
	if not state or state.character ~= character or state.skip then
		self.information[player] = { character = character, last = root.CFrame, strikes = state and state.strikes or 0, lastStrike = state and state.lastStrike or 0 }
		return
	end
	local moved = (flat(root.Position) - flat(state.last.Position)).Magnitude
	local allowed = humanoid.WalkSpeed * dt * cfg.Tolerance + cfg.Slack
	if moved <= allowed then
		state.last = root.CFrame
		return
	end
	character:PivotTo(state.last)
	if os.time() - state.lastStrike > cfg.WindowSeconds then
		state.strikes = 0
	end
	state.strikes += 1
	state.lastStrike = os.time()
	if state.strikes == cfg.Strikes then
		self:Alert(("[Anticheat] %s moved %.0f studs in %.1fs (allowed %.0f), strike %d"):format(player.Name, moved, dt, allowed, state.strikes))
	end
end

function module:Alert(text: string)
	warn(text)
	local RBAC = self.includes.Security["RBAC_Permissions.h"]
	for _, player in Players:GetPlayers() do
		if RBAC:HasLevel(player, RBAC.ROLES.MODERATOR) then
			self.includes.Chat["Chat.h"]:System(player, text)
		end
	end
end

function module:Start()
	local Session = self.includes.Security["Session.h"]
	task.spawn(function()
		local last = os.clock()
		while true do
			task.wait(cfg.SampleSeconds)
			local now = os.clock()
			local dt = now - last
			last = now
			if enabled then
				for _, player in Players:GetPlayers() do
					local session = Session:Get(player)
					if not (session and session.Gm) then
						self:Check(player, dt)
					end
				end
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		self.information[player] = nil
	end)
end

return Base(module, {
	{ Path = "Auth/Security", Imports = "RBAC_Permissions.h|Session.h" },
	{ Path = "Auth/Chat", Imports = "Chat.h" },
})
