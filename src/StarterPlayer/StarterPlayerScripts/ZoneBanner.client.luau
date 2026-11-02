local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Fusion = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Fusion"))
local Components = require(script.Parent:WaitForChild("Components"))
local player = Players.LocalPlayer

-- Zone banner: big name and subtitle that fade in when the Zone attribute
-- changes and out three seconds later. Level-ups use the same banner.

local scope = Fusion.scoped(Fusion)
local Children = Fusion.Children

local title, subtitle = scope:Value(""), scope:Value("")
local hidden = scope:Value(1)
local info = scope:Value(TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out))
local alpha = scope:Tween(hidden, info)
local stroke = scope:Computed(function(use)
	return 0.4 + use(alpha) * 0.6
end)

local function line(size: number, y: number, text, color: Color3)
	return scope:New "TextLabel" {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, y),
		Size = UDim2.fromScale(0.8, size),
		BackgroundTransparency = 1,
		Font = Enum.Font.Garamond,
		TextScaled = true,
		TextColor3 = color,
		TextStrokeColor3 = Color3.new(0, 0, 0),
		TextStrokeTransparency = stroke,
		TextTransparency = alpha,
		Text = text,
	}
end

scope:New "ScreenGui" {
	Name = "ZoneBanner",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	Parent = player:WaitForChild("PlayerGui"),
	[Children] = {
		line(0.09, 0.14, title, Color3.fromRGB(255, 220, 120)),
		line(0.04, 0.235, subtitle, Color3.fromRGB(230, 230, 230)),
	},
}

local showing = 0
local function show(main: string, sub: string)
	showing += 1
	local token = showing
	title:set(main)
	subtitle:set(sub)
	info:set(TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out))
	hidden:set(0)
	task.delay(3, function()
		if token == showing then
			info:set(TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In))
			hidden:set(1)
		end
	end)
end

player:GetAttributeChangedSignal("Zone"):Connect(function()
	local name = player:GetAttribute("Zone")
	if name then
		show(name, player:GetAttribute("ZoneKind") or "")
	end
end)
player:GetAttributeChangedSignal("EventBanner"):Connect(function()
	local raw = player:GetAttribute("EventBanner")
	local name = raw and raw:match("^(.-) [%d%.]+$")
	if name then
		show(name, "has begun")
	end
end)
player:GetAttributeChangedSignal("LevelUp"):Connect(function()
	local level = player:GetAttribute("LevelUp")
	if level then
		show(("Level %d"):format(level), "You have reached a new level!")
	end
end)
