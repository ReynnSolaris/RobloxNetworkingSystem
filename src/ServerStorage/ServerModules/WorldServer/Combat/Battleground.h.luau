local Base = require(game:GetService("ServerStorage").ServerModules["Template.h"])
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Opcodes = require(ReplicatedStorage.Shared.Opcodes)
local Config = require(ReplicatedStorage.Shared.Config)
local module = {}

-- Capture the flag between the factions, Warsong style. battleground_template:
-- { id, name, minlevel, spawn = { Alliance = {x,y,z,o}, Horde = {..} }, flag = {
-- Alliance = {x,y,z}, Horde = {..} } }, placed by a GM with .bg. A battlemaster
-- creature queues players by faction; with MinPerSide on each side a match
-- starts: everyone ports to their base, a flag pole stands at each flag point,
-- taking the enemy flag carries it on your back, bringing it to your own base
-- while your flag is home scores. ScoreToWin ends it, honor is paid and
-- everyone returns. Inside a match the other faction is always attackable and
-- death respawns at base after RespawnSeconds. information[player] = match.

local queue: { [Player]: number } = {}
local matches = {}
local nextMatch = 0

local function nameOf(player: Player): string
	return player:GetAttribute("CharacterName") or player.Name
end

local function factionOf(player: Player): string
	return player:GetAttribute("CharacterFaction") or "Alliance"
end

local function other(faction: string): string
	return if faction == "Alliance" then "Horde" else "Alliance"
end

function module:DB()
	return self.includes.Database["WorldDB.h"]
end

function module:Match(player: Player)
	return self.information[player]
end

function module:In(player: Player): boolean
	return self.information[player] ~= nil
end

function module:SameMatch(a: Player, b: Player): boolean
	return self.information[a] ~= nil and self.information[a] == self.information[b]
end

function module:Status(match, player: Player, status: string?)
	local flags = {}
	for faction, flag in match.Flags do
		flags[faction] = flag.State .. (if flag.Carrier then " " .. nameOf(flag.Carrier) else "")
	end
	self.includes.Security["Packet.h"]:Send(player, Opcodes.SMSG_BATTLEFIELD_STATUS,
		{ Status = status or "active", Name = match.Template.name, Scores = match.Scores, Flags = flags, Team = factionOf(player), Winner = match.Winner, ToWin = Config.Battleground.ScoreToWin })
end

function module:Broadcast(match, text: string, status: string?)
	for member in match.Members do
		if member.Parent == Players then
			self.includes.Chat["Chat.h"]:System(member, text)
			self:Status(match, member, status)
		end
	end
end

local function point(p): CFrame
	return CFrame.new(p[1], p[2], p[3]) * CFrame.Angles(0, math.rad(p.o or 0), 0)
end

-- A flag pole with a faction-coloured banner; prompt differs by who walks up.
local function buildFlag(self, match, faction: string)
	local flag = match.Flags[faction]
	local template = match.Template
	local base = point(template.flag[faction])
	local model = Instance.new("Model")
	model.Name = faction .. " Flag"
	local pole = Instance.new("Part")
	pole.Name = "Pole"
	pole.Size = Vector3.new(0.4, 9, 0.4)
	pole.Anchored, pole.CanCollide = true, false
	pole.Color = Color3.fromRGB(90, 70, 50)
	pole.CFrame = base * CFrame.new(0, 4.5, 0)
	pole.Parent = model
	local banner = Instance.new("Part")
	banner.Name = "Banner"
	banner.Size = Vector3.new(3, 2.2, 0.2)
	banner.Anchored, banner.CanCollide = true, false
	banner.Color = Color3.fromHex(Config.Factions[faction].Color)
	banner.CFrame = base * CFrame.new(1.6, 7.5, 0)
	banner.Parent = model
	model.PrimaryPart = pole
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Take Flag"
	prompt.ObjectText = model.Name
	prompt.MaxActivationDistance = 8
	prompt.RequiresLineOfSight = false
	prompt.Parent = pole
	prompt.Triggered:Connect(function(player)
		self:Interact(match, faction, player)
	end)
	model.Parent = workspace
	flag.Model, flag.Prompt, flag.Base = model, prompt, base
end

local function moveFlag(flag, cframe: CFrame)
	flag.Model:PivotTo(cframe * CFrame.new(0, 4.5, 0))
end

local function updatePrompt(flag, faction: string)
	flag.Prompt.ActionText = if flag.State == "home" then "Take Flag" elseif flag.State == "dropped" then "Pick up Flag" else ""
	flag.Prompt.Enabled = flag.State ~= "carried"
end

function module:Interact(match, faction: string, player: Player)
	local flag = match.Flags[faction]
	if match.Members[player] == nil or match.Winner then
		return
	end
	local mine = factionOf(player) == faction
	if flag.State == "home" and not mine then
		self:Pickup(match, faction, player)
	elseif flag.State == "dropped" then
		if mine then
			self:Return(match, faction, player)
		else
			self:Pickup(match, faction, player)
		end
	end
end

function module:Pickup(match, faction: string, player: Player)
	local flag = match.Flags[faction]
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	flag.State, flag.Carrier = "carried", player
	flag.DropAt = nil
	updatePrompt(flag, faction)
	for _, part in flag.Model:GetChildren() do
		if part:IsA("BasePart") then
			part.Anchored = false
			part.Massless = true
		end
	end
	flag.Model:PivotTo(root.CFrame * CFrame.new(0, 1, 1.2) * CFrame.Angles(0, 0, math.rad(20)))
	for _, part in flag.Model:GetChildren() do
		if part:IsA("BasePart") then
			local weld = Instance.new("WeldConstraint")
			weld.Part0, weld.Part1 = root, part
			weld.Parent = part
		end
	end
	flag.Model.Parent = character
	player:SetAttribute("FlagCarrier", faction)
	self.includes.Spells["Auras.h"]:RemoveKind(player, "mount")
	self:Broadcast(match, ("%s has picked up the %s flag!"):format(nameOf(player), faction))
end

local function detach(flag)
	for _, part in flag.Model:GetChildren() do
		if part:IsA("BasePart") then
			for _, weld in part:GetChildren() do
				if weld:IsA("WeldConstraint") then
					weld:Destroy()
				end
			end
			part.Anchored = true
		end
	end
	flag.Model.Parent = workspace
end

function module:Drop(match, faction: string, at: CFrame?)
	local flag = match.Flags[faction]
	local carrier = flag.Carrier
	if flag.State ~= "carried" then
		return
	end
	detach(flag)
	flag.State, flag.Carrier = "dropped", nil
	flag.DropAt = os.time()
	local root = carrier and carrier.Character and carrier.Character:FindFirstChild("HumanoidRootPart")
	moveFlag(flag, at or (root and CFrame.new(root.Position)) or flag.Base)
	updatePrompt(flag, faction)
	if carrier then
		carrier:SetAttribute("FlagCarrier", nil)
	end
	self:Broadcast(match, ("The %s flag was dropped%s!"):format(faction, if carrier then " by " .. nameOf(carrier) else ""))
end

function module:Return(match, faction: string, player: Player?)
	local flag = match.Flags[faction]
	if flag.State == "carried" then
		detach(flag)
		if flag.Carrier then
			flag.Carrier:SetAttribute("FlagCarrier", nil)
		end
	end
	flag.State, flag.Carrier, flag.DropAt = "home", nil, nil
	moveFlag(flag, flag.Base)
	updatePrompt(flag, faction)
	self:Broadcast(match, if player then ("%s returned the %s flag!"):format(nameOf(player), faction) else ("The %s flag has returned to its base."):format(faction))
end

function module:Capture(match, player: Player)
	local team = factionOf(player)
	local enemy = other(team)
	match.Scores[team] += 1
	self:Return(match, enemy)
	self:Broadcast(match, ("%s captured the %s flag! %s %d, %s %d."):format(nameOf(player), enemy, "Alliance", match.Scores.Alliance, "Horde", match.Scores.Horde))
	if match.Scores[team] >= Config.Battleground.ScoreToWin then
		self:Finish(match, team)
	end
end

function module:Queue(player: Player, id)
	local template = self:DB():Get("battleground_template", id)
	local Chat = self.includes.Chat["Chat.h"]
	if not template or not template.spawn or not template.flag or not template.spawn.Alliance or not template.spawn.Horde or not template.flag.Alliance or not template.flag.Horde then
		return Chat:System(player, "That battleground is not set up yet.")
	elseif (player:GetAttribute("CharacterLevel") or 1) < (template.minlevel or 1) then
		return Chat:System(player, ("You must be level %d to join %s."):format(template.minlevel, template.name))
	elseif self.information[player] then
		return Chat:System(player, "You are already in a battleground.")
	end
	queue[player] = template.id
	Chat:System(player, ("You are queued for %s."):format(template.name))
	self.includes.Security["Packet.h"]:Send(player, Opcodes.SMSG_BATTLEFIELD_STATUS, { Status = "queued", Name = template.name })
	self:TryStart(template)
end

function module:Leave(player: Player, quiet: boolean?)
	queue[player] = nil
	local match = self.information[player]
	if not match then
		if not quiet then
			self.includes.Security["Packet.h"]:Send(player, Opcodes.SMSG_BATTLEFIELD_STATUS, { Status = "none" })
		end
		return
	end
	for faction, flag in match.Flags do
		if flag.Carrier == player then
			self:Drop(match, faction)
		end
	end
	match.Members[player] = nil
	self.information[player] = nil
	player:SetAttribute("Battleground", nil)
	if player.Parent == Players then
		self.includes.Security["Packet.h"]:Send(player, Opcodes.SMSG_BATTLEFIELD_STATUS, { Status = "none" })
		if match.Return[player] then
			self.includes.Entities["EntityPlayer.h"]:Teleport(player, match.Return[player])
		end
	end
	local alliance, horde = 0, 0
	for member in match.Members do
		if factionOf(member) == "Alliance" then alliance += 1 else horde += 1 end
	end
	if not match.Winner and (alliance == 0 or horde == 0) then
		self:Finish(match, if alliance == 0 then "Horde" else "Alliance")
	end
end

function module:TryStart(template)
	local sides = { Alliance = {}, Horde = {} }
	for player, id in queue do
		if player.Parent == Players and id == template.id then
			table.insert(sides[factionOf(player)], player)
		else
			queue[player] = nil
		end
	end
	if #sides.Alliance < Config.Battleground.MinPerSide or #sides.Horde < Config.Battleground.MinPerSide then
		return
	end
	nextMatch += 1
	local match = { Id = nextMatch, Template = template, Members = {}, Scores = { Alliance = 0, Horde = 0 }, Flags = { Alliance = { State = "home" }, Horde = { State = "home" } }, Return = {}, Winner = nil }
	matches[match.Id] = match
	for _, faction in { "Alliance", "Horde" } do
		buildFlag(self, match, faction)
		for i, player in sides[faction] do
			if i <= Config.Battleground.MaxPerSide then
				queue[player] = nil
				match.Members[player] = true
				self.information[player] = match
				local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
				match.Return[player] = root and root.CFrame or Config.Spawn
				player:SetAttribute("Battleground", template.name)
				self.includes.Entities["EntityPlayer.h"]:Teleport(player, point(template.spawn[faction]) * CFrame.new(0, 3, 0))
			end
		end
	end
	self:Broadcast(match, ("The battle for %s has begun! First to %d captures wins."):format(template.name, Config.Battleground.ScoreToWin))
end

function module:Finish(match, winner: string)
	match.Winner = winner
	local Entities = self.includes.Entities["EntityPlayer.h"]
	self:Broadcast(match, ("The %s wins %s!"):format(winner, match.Template.name), "ended")
	for member in match.Members do
		local entity = Entities:Get(member)
		local char = entity and entity.Active
		if char then
			local honor = if factionOf(member) == winner then Config.Battleground.HonorWin else Config.Battleground.HonorLoss
			char.Honor = (char.Honor or 0) + honor
			member:SetAttribute("Honor", char.Honor)
			self.includes.Chat["Chat.h"]:System(member, ("You receive %d honor."):format(honor))
		end
	end
	task.delay(8, function()
		for _, flag in match.Flags do
			if flag.Model then
				flag.Model:Destroy()
			end
		end
		for member in table.clone(match.Members) do
			self:Leave(member, true)
		end
		matches[match.Id] = nil
	end)
end

-- Death inside a match: no ghost, back to base after a delay.
function module:OnDeath(player: Player): boolean
	local match = self.information[player]
	if not match then
		return false
	end
	for faction, flag in match.Flags do
		if flag.Carrier == player then
			self:Drop(match, faction)
		end
	end
	task.delay(Config.Battleground.RespawnSeconds, function()
		if self.information[player] == match and player.Parent == Players then
			self.includes.Combat["Death.h"]:Resurrect(player, point(match.Template.spawn[factionOf(player)]) * CFrame.new(0, 3, 0))
			local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
			if humanoid then
				humanoid.Health = humanoid.MaxHealth
			end
		end
	end)
	return true
end

-- GM setup
function module:Create(name: string, minlevel: number?)
	return self:DB():Insert("battleground_template", { name = name, minlevel = minlevel or 10, spawn = {}, flag = {} })
end

function module:SetPoint(id, kind: string, faction: string, cframe: CFrame)
	local row = assert(self:DB():Get("battleground_template", id), "no such battleground")
	local points = row[kind] or {}
	local _, yaw = cframe:ToEulerAnglesYXZ()
	points[faction] = { cframe.X, cframe.Y, cframe.Z, o = math.deg(yaw) }
	self:DB():Update("battleground_template", id, { [kind] = points })
end

function module:Start()
	local Packet = self.includes.Security["Packet.h"]
	Packet:On(Opcodes.CMSG_BATTLEMASTER_JOIN, function(player, data)
		if typeof(data) == "table" then
			self:Queue(player, tonumber(data.Id))
		end
	end)
	Packet:On(Opcodes.CMSG_LEAVE_BATTLEFIELD, function(player)
		self:Leave(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		self:Leave(player, true)
	end)
	task.spawn(function()
		while true do
			task.wait(0.5)
			for _, match in matches do
				if match.Winner then
					continue
				end
				for faction, flag in match.Flags do
					if flag.State == "dropped" and os.time() - (flag.DropAt or 0) >= Config.Battleground.FlagReturnSeconds then
						self:Return(match, faction)
					elseif flag.State == "carried" then
						local carrier = flag.Carrier
						local root = carrier and carrier.Character and carrier.Character:FindFirstChild("HumanoidRootPart")
						if not root or carrier.Parent ~= Players then
							self:Drop(match, faction, flag.Model and flag.Model:GetPivot())
						else
							local ownBase = match.Flags[other(faction)]
							if ownBase.State == "home" and (root.Position - ownBase.Base.Position).Magnitude <= Config.Battleground.CaptureRange then
								self:Capture(match, carrier)
							end
						end
					end
				end
			end
		end
	end)
end

return Base(module, {
	{ Path = "Auth/Security", Imports = "Packet.h" },
	{ Path = "Auth/Entities", Imports = "EntityPlayer.h" },
	{ Path = "Auth/Chat", Imports = "Chat.h" },
	{ Path = "World/Combat", Imports = "Death.h" },
	{ Path = "World/Spells", Imports = "Auras.h" },
	{ Path = "World/Database", Imports = "WorldDB.h" },
})
