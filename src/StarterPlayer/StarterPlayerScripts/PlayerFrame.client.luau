local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")
local TextChatService = game:GetService("TextChatService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local player = Players.LocalPlayer

-- Nothing of the game UI exists until a character is in the world: chat, core
-- GUI and this WoW-style player frame all follow the InWorld attribute.

local classColor: { [string]: Color3 } = {}
for _, class in Config.Classes do
	classColor[class.Name] = Color3.fromHex(class.Color)
end

local gui = Instance.new("ScreenGui")
gui.Name = "PlayerFrame"
gui.ResetOnSpawn = false
gui.Enabled = false

local frame = Instance.new("Frame")
frame.Position = UDim2.fromOffset(16, 16)
frame.Size = UDim2.fromOffset(280, 68)
frame.BackgroundColor3 = Color3.fromRGB(16, 16, 24)
frame.BackgroundTransparency = 0.2
frame.BorderSizePixel = 0
frame.Parent = gui
Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 6)
local stroke = Instance.new("UIStroke", frame)
stroke.Color = Color3.fromRGB(120, 95, 40)

local portrait = Instance.new("TextLabel")
portrait.Size = UDim2.fromOffset(52, 52)
portrait.Position = UDim2.fromOffset(8, 8)
portrait.BackgroundColor3 = Color3.fromRGB(60, 60, 70)
portrait.BorderSizePixel = 0
portrait.Font = Enum.Font.Garamond
portrait.TextSize = 34
portrait.TextColor3 = Color3.fromRGB(10, 10, 14)
portrait.Text = "?"
portrait.Parent = frame
Instance.new("UICorner", portrait).CornerRadius = UDim.new(0, 4)

local function label(y: number, size: number, color: Color3): TextLabel
	local l = Instance.new("TextLabel")
	l.Position = UDim2.fromOffset(68, y)
	l.Size = UDim2.new(1, -76, 0, size + 4)
	l.BackgroundTransparency = 1
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Font = Enum.Font.GothamBold
	l.TextSize = size
	l.TextColor3 = color
	l.Parent = frame
	return l
end

local nameLabel = label(8, 16, Color3.new(1, 1, 1))
local infoLabel = label(27, 12, Color3.fromRGB(190, 190, 200))
infoLabel.Font = Enum.Font.Gotham

local back = Instance.new("Frame")
back.Position = UDim2.fromOffset(68, 46)
back.Size = UDim2.new(1, -76, 0, 14)
back.BackgroundColor3 = Color3.fromRGB(50, 16, 16)
back.BorderSizePixel = 0
back.Parent = frame
Instance.new("UICorner", back).CornerRadius = UDim.new(0, 3)
local bar = Instance.new("Frame")
bar.Size = UDim2.fromScale(1, 1)
bar.BackgroundColor3 = Color3.fromRGB(60, 200, 80)
bar.BorderSizePixel = 0
bar.Parent = back
Instance.new("UICorner", bar).CornerRadius = UDim.new(0, 3)
local healthText = Instance.new("TextLabel")
healthText.Size = UDim2.fromScale(1, 1)
healthText.BackgroundTransparency = 1
healthText.Font = Enum.Font.GothamBold
healthText.TextSize = 11
healthText.TextColor3 = Color3.new(1, 1, 1)
healthText.Parent = back

local latency = Instance.new("TextLabel")
latency.AnchorPoint = Vector2.new(1, 0)
latency.Position = UDim2.new(1, -8, 0, 6)
latency.Size = UDim2.fromOffset(60, 14)
latency.BackgroundTransparency = 1
latency.TextXAlignment = Enum.TextXAlignment.Right
latency.Font = Enum.Font.Gotham
latency.TextSize = 11
latency.TextColor3 = Color3.fromRGB(140, 140, 150)
latency.Parent = frame

gui.Parent = player:WaitForChild("PlayerGui")

local function setCoreUi(on: boolean)
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, on)
	end)
	local window = TextChatService:FindFirstChildOfClass("ChatWindowConfiguration")
	local inputBar = TextChatService:FindFirstChildOfClass("ChatInputBarConfiguration")
	if window then
		window.Enabled = on
	end
	if inputBar then
		inputBar.Enabled = on
	end
end

local function refresh()
	local inWorld = player:GetAttribute("InWorld") == true
	gui.Enabled = inWorld
	setCoreUi(inWorld)
	local name = player:GetAttribute("CharacterName") or player.DisplayName
	local class = player:GetAttribute("CharacterClass")
	local color = class and classColor[class] or Color3.fromRGB(200, 200, 200)
	nameLabel.Text = name
	nameLabel.TextColor3 = color
	portrait.Text = name:sub(1, 1):upper()
	portrait.BackgroundColor3 = color
	infoLabel.Text = ("Level %d %s"):format(player:GetAttribute("CharacterLevel") or 1, class or "")
end

local function health()
	local hp = player:GetAttribute("Health") or 0
	local max = math.max(player:GetAttribute("MaxHealth") or 100, 1)
	bar.Size = UDim2.fromScale(math.clamp(hp / max, 0, 1), 1)
	bar.BackgroundColor3 = if hp > 0 then Color3.fromRGB(60, 200, 80) else Color3.fromRGB(120, 120, 120)
	healthText.Text = ("%d / %d"):format(hp, max)
	local ms = player:GetAttribute("Latency")
	latency.Text = if ms then ms .. " ms" else ""
end

for _, attribute in { "InWorld", "CharacterName", "CharacterClass", "CharacterLevel" } do
	player:GetAttributeChangedSignal(attribute):Connect(refresh)
end
for _, attribute in { "Health", "MaxHealth", "Latency" } do
	player:GetAttributeChangedSignal(attribute):Connect(health)
end
refresh()
health()
