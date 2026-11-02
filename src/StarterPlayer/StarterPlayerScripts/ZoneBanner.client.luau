local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local player = Players.LocalPlayer

-- WoW-style zone banner: big name, small subtitle, fades in and out when the
-- "Zone" attribute changes (set by NetClient from SMSG_ZONE_UPDATE).

local gui = Instance.new("ScreenGui")
gui.Name = "ZoneBanner"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true

local function label(size: number, y: number, color: Color3): TextLabel
	local l = Instance.new("TextLabel")
	l.AnchorPoint = Vector2.new(0.5, 0)
	l.Position = UDim2.fromScale(0.5, y)
	l.Size = UDim2.fromScale(0.8, size)
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.Garamond
	l.TextScaled = true
	l.TextColor3 = color
	l.TextStrokeColor3 = Color3.new(0, 0, 0)
	l.TextStrokeTransparency = 1
	l.TextTransparency = 1
	l.Parent = gui
	return l
end

local title = label(0.09, 0.14, Color3.fromRGB(255, 220, 120))
local subtitle = label(0.04, 0.235, Color3.fromRGB(230, 230, 230))
gui.Parent = player:WaitForChild("PlayerGui")

local fadeIn = TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local fadeOut = TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local showing = 0

local function fade(l: TextLabel, info: TweenInfo, transparency: number)
	TweenService:Create(l, info, { TextTransparency = transparency, TextStrokeTransparency = 0.4 + transparency * 0.6 }):Play()
end

player:GetAttributeChangedSignal("Zone"):Connect(function()
	local name = player:GetAttribute("Zone")
	if not name then
		return
	end
	showing += 1
	local token = showing
	title.Text = name
	subtitle.Text = player:GetAttribute("ZoneKind") or ""
	fade(title, fadeIn, 0)
	fade(subtitle, fadeIn, 0)
	task.delay(3, function()
		if token == showing then
			fade(title, fadeOut, 1)
			fade(subtitle, fadeOut, 1)
		end
	end)
end)
