local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")
local TextChatService = game:GetService("TextChatService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Fusion = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Fusion"))
local Config = require(ReplicatedStorage.Shared.Config)
local Components = require(script.Parent:WaitForChild("Components"))
local player = Players.LocalPlayer

-- Player frame top-left: portrait, name in class colour, level, health, XP and
-- latency. Nothing of the game UI exists until InWorld; the Roblox core GUI and
-- chat are switched off with it (ChatFrame draws chat).

local scope = Fusion.scoped(Fusion)
local Children = Fusion.Children
local function attr(name, default)
	return Components.attribute(scope, player, name, default)
end

local classColor: { [string]: Color3 } = {}
for _, class in Config.Classes do
	classColor[class.Name] = Color3.fromHex(class.Color)
end

local inWorld = attr("InWorld", false)
local name = attr("CharacterName", player.DisplayName)
local class = attr("CharacterClass", "")
local level = attr("CharacterLevel", 1)
local health, maxHealth = attr("Health", 0), attr("MaxHealth", 100)
local latency = attr("Latency", nil)
local resting = attr("Resting", false)
local pvp = attr("PvpFlag", false)
local race = attr("CharacterRace", "")
local color = scope:Computed(function(use)
	return classColor[use(class)] or Color3.fromRGB(200, 200, 200)
end)

scope:New "ScreenGui" {
	Name = "PlayerFrame",
	ResetOnSpawn = false,
	Enabled = scope:Computed(function(use)
		return use(inWorld) == true
	end),
	Parent = player:WaitForChild("PlayerGui"),
	[Children] = Components.UnitFrame(scope, {
		Position = UDim2.fromOffset(16, 16),
		Size = UDim2.fromOffset(280, 80),
		Power = attr("Mana", 0),
		MaxPower = attr("MaxMana", 1),
		Portrait = scope:Computed(function(use)
			return tostring(use(name)):sub(1, 1):upper()
		end),
		PortraitColor = color,
		Title = name,
		TitleColor = color,
		Info = scope:Computed(function(use)
			return ("Level %d %s %s"):format(use(level), use(race) or "", use(class) or "")
		end),
		Corner = scope:Computed(function(use)
			local ms = use(latency)
			return (if use(pvp) then '<font color="#FF4040">PvP</font>  ' else "") .. (if use(resting) then '<font color="#7070FF">zzz</font>  ' else "") .. (if ms then ms .. " ms" else "")
		end),
		Health = health,
		MaxHealth = maxHealth,
		HealthColor = scope:Computed(function(use)
			return if (use(health) or 0) > 0 then Color3.fromRGB(60, 200, 80) else Color3.fromRGB(120, 120, 120)
		end),
		Xp = attr("CharacterXp", 0),
		XpMax = attr("CharacterXpNext", 1),
	}),
}

local function setCoreUi(on: boolean)
	pcall(StarterGui.SetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.All, on)
	for _, class in { "ChatWindowConfiguration", "ChatInputBarConfiguration" } do
		local config = TextChatService:FindFirstChildOfClass(class)
		if config then
			config.Enabled = false
		end
	end
end
scope:Observer(inWorld):onBind(function()
	setCoreUi(Fusion.peek(inWorld) == true)
end)
