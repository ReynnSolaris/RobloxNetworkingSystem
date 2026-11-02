local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Opcodes = require(ReplicatedStorage.Shared.Opcodes)
local Config = require(ReplicatedStorage.Shared.Config)
local player = Players.LocalPlayer
local mouse = player:GetMouse()
local netSend = script.Parent:WaitForChild("NetSend") :: BindableEvent

-- WoW target frame. Click a creature to target it, T (or click it again) toggles
-- auto-attack on a hostile one, Escape clears. Health is read from the model.

local gui = Instance.new("ScreenGui")
gui.Name = "TargetFrame"
gui.ResetOnSpawn = false
gui.Enabled = false

local frame = Instance.new("Frame")
frame.Position = UDim2.fromOffset(312, 16)
frame.Size = UDim2.fromOffset(260, 68)
frame.BackgroundColor3 = Color3.fromRGB(16, 16, 24)
frame.BackgroundTransparency = 0.2
frame.BorderSizePixel = 0
frame.Parent = gui
Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 6)
local stroke = Instance.new("UIStroke", frame)
stroke.Color = Color3.fromRGB(120, 95, 40)

local function label(y: number, size: number, bold: boolean): TextLabel
	local l = Instance.new("TextLabel")
	l.Position = UDim2.fromOffset(10, y)
	l.Size = UDim2.new(1, -20, 0, size + 4)
	l.BackgroundTransparency = 1
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Font = if bold then Enum.Font.GothamBold else Enum.Font.Gotham
	l.TextSize = size
	l.TextColor3 = Color3.new(1, 1, 1)
	l.Parent = frame
	return l
end
local nameLabel = label(8, 16, true)
local infoLabel = label(27, 12, false)
infoLabel.TextColor3 = Color3.fromRGB(190, 190, 200)
local attackLabel = label(27, 12, true)
attackLabel.TextXAlignment = Enum.TextXAlignment.Right
attackLabel.TextColor3 = Color3.fromRGB(255, 90, 90)
attackLabel.Text = ""

local back = Instance.new("Frame")
back.Position = UDim2.fromOffset(10, 46)
back.Size = UDim2.new(1, -20, 0, 14)
back.BackgroundColor3 = Color3.fromRGB(50, 16, 16)
back.BorderSizePixel = 0
back.Parent = frame
Instance.new("UICorner", back).CornerRadius = UDim.new(0, 3)
local bar = Instance.new("Frame")
bar.Size = UDim2.fromScale(1, 1)
bar.BackgroundColor3 = Color3.fromRGB(200, 60, 60)
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
gui.Parent = player:WaitForChild("PlayerGui")

local target: Model? = nil
local attacking = false

local function setAttacking(on: boolean)
	attacking = on and target ~= nil and target:GetAttribute("Faction") == "hostile"
	attackLabel.Text = if attacking then "ATTACKING" else ""
	netSend:Fire(Opcodes.CMSG_ATTACK, { On = attacking })
end

local function setTarget(model: Model?)
	target = model
	setAttacking(false)
	gui.Enabled = model ~= nil
	netSend:Fire(Opcodes.CMSG_SET_TARGET, { Guid = model and model:GetAttribute("Guid") })
end

local function creatureFrom(part: Instance?): Model?
	local creatures = workspace:FindFirstChild("Creatures")
	while part and part ~= workspace do
		if part:IsA("Model") and part:GetAttribute("Guid") and part.Parent == creatures then
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
	if model and model == target then
		setAttacking(not attacking)
	elseif model then
		setTarget(model)
	end
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	if input.KeyCode == Enum.KeyCode.T and target then
		setAttacking(not attacking)
	elseif input.KeyCode == Enum.KeyCode.Escape and target then
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
	if target then
		local humanoid = target:FindFirstChildOfClass("Humanoid")
		if not target.Parent or not humanoid then
			setTarget(nil)
		else
			local hostile = target:GetAttribute("Faction") == "hostile"
			nameLabel.Text = target.Name
			nameLabel.TextColor3 = if hostile then Color3.fromRGB(255, 90, 90) else Color3.fromRGB(90, 220, 90)
			infoLabel.Text = ("Level %s %s"):format(tostring(target:GetAttribute("Level") or "?"), if hostile then "Hostile" else "Friendly")
			local hp, max = humanoid.Health, math.max(humanoid.MaxHealth, 1)
			bar.Size = UDim2.fromScale(math.clamp(hp / max, 0, 1), 1)
			healthText.Text = ("%d / %d"):format(hp, max)
			if hp <= 0 and attacking then
				setAttacking(false)
			end
		end
	end
end
