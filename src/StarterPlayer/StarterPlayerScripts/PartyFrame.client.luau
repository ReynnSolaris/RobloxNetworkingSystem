local Players = game:GetService("Players")
local player = Players.LocalPlayer

-- Party frame on the left: one row per member with a health bar. Membership
-- comes from the PartyMembers / PartyLeader attributes (set by NetClient);
-- health is read from the replicated characters.

local gui = Instance.new("ScreenGui")
gui.Name = "PartyFrame"
gui.ResetOnSpawn = false
local list = Instance.new("Frame")
list.AnchorPoint = Vector2.new(0, 0.5)
list.Position = UDim2.new(0, 12, 0.5, -60)
list.Size = UDim2.fromOffset(180, 200)
list.BackgroundTransparency = 1
list.Parent = gui
local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 6)
layout.Parent = list
gui.Parent = player:WaitForChild("PlayerGui")

local rows: { [string]: Frame } = {}

local function row(name: string): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.Size = UDim2.new(1, 0, 0, 34)
	frame.BackgroundColor3 = Color3.fromRGB(20, 20, 28)
	frame.BackgroundTransparency = 0.25
	frame.BorderSizePixel = 0
	Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 4)

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.new(1, -8, 0, 18)
	label.Position = UDim2.fromOffset(6, 1)
	label.BackgroundTransparency = 1
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Font = Enum.Font.GothamMedium
	label.TextSize = 13
	label.TextColor3 = Color3.fromRGB(230, 230, 240)
	label.Parent = frame

	local back = Instance.new("Frame")
	back.Name = "Back"
	back.Size = UDim2.new(1, -12, 0, 8)
	back.Position = UDim2.fromOffset(6, 22)
	back.BackgroundColor3 = Color3.fromRGB(60, 20, 20)
	back.BorderSizePixel = 0
	back.Parent = frame
	local bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.Size = UDim2.fromScale(1, 1)
	bar.BackgroundColor3 = Color3.fromRGB(60, 200, 80)
	bar.BorderSizePixel = 0
	bar.Parent = back

	frame.Parent = list
	return frame
end

local function rebuild()
	for _, frame in rows do
		frame:Destroy()
	end
	rows = {}
	local members = player:GetAttribute("PartyMembers")
	if not members then
		return
	end
	for _, name in members:split(",") do
		rows[name] = row(name)
	end
end

player:GetAttributeChangedSignal("PartyMembers"):Connect(rebuild)
player:GetAttributeChangedSignal("PartyLeader"):Connect(rebuild)
rebuild()

while true do
	task.wait(0.25)
	local leader = player:GetAttribute("PartyLeader")
	for name, frame in rows do
		local other = Players:FindFirstChild(name)
		local humanoid = other and other.Character and other.Character:FindFirstChildOfClass("Humanoid")
		local health, max = if humanoid then humanoid.Health else 0, if humanoid then humanoid.MaxHealth else 100
		frame.Label.Text = (if name == leader then "★ " else "") .. (if other then other.DisplayName else name)
		frame.Back.Bar.Size = UDim2.fromScale(math.clamp(health / math.max(max, 1), 0, 1), 1)
		frame.Back.Bar.BackgroundColor3 = if health > 0 then Color3.fromRGB(60, 200, 80) else Color3.fromRGB(120, 120, 120)
	end
end
