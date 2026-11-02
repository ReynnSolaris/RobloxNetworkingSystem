local Players = game:GetService("Players")
local Config = require(game:GetService("ReplicatedStorage").Shared.Config)
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Fusion = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Fusion"))
local Opcodes = require(ReplicatedStorage.Shared.Opcodes)
local Components = require(script.Parent:WaitForChild("Components"))
local player = Players.LocalPlayer
local mouse = player:GetMouse()
local netSend = script.Parent:WaitForChild("NetSend") :: BindableEvent

-- Target frame beside the player frame. Left-click a creature to target it,
-- right-click (or T, or a second left-click) starts auto-attack on a hostile
-- one, Escape clears. While attacking the frame glows red and a swing bar
-- fills between swings; the "Attacking" attribute comes back from the server.

local scope = Fusion.scoped(Fusion)
local Children, peek = Fusion.Children, Fusion.peek

local RunService = game:GetService("RunService")
local target = scope:Value(nil :: Model?)
local attacking = scope:Value(false)
local serverAttacking = Components.attribute(scope, player, "Attacking", false)
local swingAt = Components.attribute(scope, player, "Swing", 0)
local now = scope:Value(os.clock())
RunService.Heartbeat:Connect(function()
	now:set(os.clock())
end)
local health, maxHealth = scope:Value(0), scope:Value(1)
local duelOpponent = Components.attribute(scope, player, "DuelOpponent", nil)
local myFaction = Components.attribute(scope, player, "CharacterFaction", "Alliance")
local zoneKind = Components.attribute(scope, player, "ZoneKind", nil)
local function playerOf(model: Model?): Player?
	local other = model and Players:GetPlayerFromCharacter(model)
	return if other and other ~= player then other else nil
end
local hostile = scope:Computed(function(use)
	local model = use(target)
	local other = playerOf(model)
	if other then
		if use(duelOpponent) ~= nil and use(duelOpponent) == (other:GetAttribute("CharacterName") or other.Name) then
			return true
		end
		local enemy = other:GetAttribute("CharacterFaction") ~= nil and other:GetAttribute("CharacterFaction") ~= use(myFaction)
		return enemy and (use(zoneKind) == "Contested Territory" or other:GetAttribute("PvpFlag") == true)
	end
	local faction = model and model:GetAttribute("Faction")
	return faction == "hostile" or ((faction == "Alliance" or faction == "Horde") and faction ~= use(myFaction))
end)
local classColor: { [string]: Color3 } = {}
for _, class in Config.Classes do
	classColor[class.Name] = Color3.fromHex(class.Color)
end

local TargetEvent = Instance.new("BindableEvent")
TargetEvent.Name = "Target"
TargetEvent.Parent = script.Parent

local function setAttacking(on: boolean)
	attacking:set(on and peek(hostile))
	netSend:Fire(Opcodes.CMSG_ATTACK, { On = peek(attacking) })
end

local function setTarget(model: Model?)
	target:set(model)
	setAttacking(false)
	local other = playerOf(model)
	netSend:Fire(Opcodes.CMSG_SET_TARGET, { Guid = model and model:GetAttribute("Guid"), Player = other and (other:GetAttribute("CharacterName") or other.Name) })
	player:SetAttribute("TargetName", if other then other:GetAttribute("CharacterName") or other.Name elseif model then model.Name else nil)
	TargetEvent:Fire(model)
end

scope:New "ScreenGui" {
	Name = "TargetFrame",
	ResetOnSpawn = false,
	Enabled = scope:Computed(function(use)
		return use(target) ~= nil
	end),
	Parent = player:WaitForChild("PlayerGui"),
	[Children] = {
		scope:New "Frame" {
			Position = UDim2.fromOffset(312, 86),
			Size = UDim2.fromOffset(260, 4),
			BackgroundColor3 = Color3.fromRGB(40, 20, 20),
			BorderSizePixel = 0,
			Visible = scope:Computed(function(use)
				return use(serverAttacking) == true
			end),
			[Children] = scope:New "Frame" {
				Size = scope:Computed(function(use)
					local since = use(now) - (use(swingAt) or 0)
					return UDim2.fromScale(math.clamp(since / Config.Combat.SwingSeconds, 0, 1), 1)
				end),
				BackgroundColor3 = Color3.fromRGB(230, 80, 60),
				BorderSizePixel = 0,
			},
		},
		scope:New "Frame" {
			Position = UDim2.fromOffset(309, 13),
			Size = UDim2.fromOffset(266, 74),
			BackgroundTransparency = 1,
			[Children] = {
				scope:New "UICorner" { CornerRadius = UDim.new(0, 8) },
				scope:New "UIStroke" {
					Thickness = 2,
					Color = Color3.fromRGB(230, 60, 60),
					Transparency = scope:Computed(function(use)
						return if use(serverAttacking) then 0.1 else 1
					end),
				},
			},
		},
		Components.UnitFrame(scope, {
		Position = UDim2.fromOffset(312, 16),
		Size = UDim2.fromOffset(260, 68),
		Title = scope:Computed(function(use)
			local model = use(target)
			local other = playerOf(model)
			return if other then other:GetAttribute("CharacterName") or other.DisplayName elseif model then model.Name else ""
		end),
		TitleColor = scope:Computed(function(use)
			local other = playerOf(use(target))
			if other then
				return classColor[other:GetAttribute("CharacterClass") or ""] or Color3.new(1, 1, 1)
			end
			local rank = use(target) and use(target):GetAttribute("Rank")
			if rank == "boss" or rank == "elite" then
				return Color3.fromRGB(255, 209, 0)
			elseif rank == "rare" then
				return Color3.fromRGB(192, 192, 255)
			end
			return if use(hostile) then Color3.fromRGB(255, 90, 90) else Color3.fromRGB(90, 220, 90)
		end),
		Info = scope:Computed(function(use)
			local model = use(target)
			local other = playerOf(model)
			if other then
				local duel = use(duelOpponent) ~= nil and use(duelOpponent) == (other:GetAttribute("CharacterName") or other.Name)
				return ("Level %d %s %s%s"):format(other:GetAttribute("CharacterLevel") or 1, other:GetAttribute("CharacterRace") or "", other:GetAttribute("CharacterClass") or "", if duel then "  (Duel)" elseif use(hostile) then "  (PvP)" else "")
			end
			if not model then
				return ""
			end
			local rank = model:GetAttribute("Rank")
			local rankText = if rank == "boss" then " Boss" elseif rank == "elite" then " Elite" elseif rank == "rare" then " Rare" else ""
			return ("Level %s%s %s"):format(tostring(model:GetAttribute("Level") or "?"), rankText, if use(hostile) then "Hostile" elseif model:GetAttribute("Faction") == "pet" then "Pet" else "Friendly")
		end),
		Right = scope:Computed(function(use)
			return if use(serverAttacking) then "ATTACKING" else ""
		end),
		Health = health,
		MaxHealth = maxHealth,
		HealthColor = Color3.fromRGB(200, 60, 60),
		}),
	},
}

local function creatureFrom(part: Instance?): Model?
	local creatures = workspace:FindFirstChild("Creatures")
	while part and part ~= workspace do
		if part:IsA("Model") and ((part:GetAttribute("Guid") and part.Parent == creatures) or playerOf(part)) then
			return part
		end
		part = part.Parent
	end
	return nil
end

mouse.Button1Down:Connect(function()
	if player:GetAttribute("InWorld") ~= true then
		return
	end
	local model = creatureFrom(mouse.Target)
	if model and model == peek(target) then
		setAttacking(not peek(attacking))
	elseif model then
		setTarget(model)
	end
end)

-- right-click: target and attack in one, WoW style
mouse.Button2Down:Connect(function()
	if player:GetAttribute("InWorld") ~= true then
		return
	end
	local model = creatureFrom(mouse.Target)
	if model then
		if model ~= peek(target) then
			setTarget(model)
		end
		if peek(hostile) and not peek(attacking) then
			setAttacking(true)
		end
	end
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed or not peek(target) then
		return
	end
	if input.KeyCode == Enum.KeyCode.T then
		setAttacking(not peek(attacking))
	elseif input.KeyCode == Enum.KeyCode.Escape then
		setTarget(nil)
	end
end)

player:GetAttributeChangedSignal("InWorld"):Connect(function()
	if player:GetAttribute("InWorld") ~= true then
		setTarget(nil)
	end
end)

while true do
	task.wait(0.1)
	local model = peek(target)
	if model then
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		if not model.Parent or not humanoid then
			setTarget(nil)
		else
			health:set(humanoid.Health)
			maxHealth:set(humanoid.MaxHealth)
			if humanoid.Health <= 0 and peek(attacking) then
				setAttacking(false)
			end
		end
	end
end
