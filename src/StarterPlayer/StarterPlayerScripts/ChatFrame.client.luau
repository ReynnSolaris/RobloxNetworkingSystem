local Players = game:GetService("Players")
local player = Players.LocalPlayer
local chatLine = script.Parent:WaitForChild("ChatLine") :: BindableEvent

-- Our chat window: tabs General, Whispers and Log, rich text lines, shown only in
-- the world. Entering the world clears General and Log; Whispers keep.

local TABS = { "General", "Whispers", "Log" }
local MAX_LINES = 150

local gui = Instance.new("ScreenGui")
gui.Name = "ChatFrame"
gui.ResetOnSpawn = false
gui.Enabled = false

local root = Instance.new("Frame")
root.AnchorPoint = Vector2.new(0, 1)
root.Position = UDim2.new(0, 12, 1, -64)
root.Size = UDim2.fromOffset(440, 230)
root.BackgroundTransparency = 1
root.Parent = gui

local tabBar = Instance.new("Frame")
tabBar.Size = UDim2.new(1, 0, 0, 22)
tabBar.BackgroundTransparency = 1
tabBar.Parent = root
local tabLayout = Instance.new("UIListLayout", tabBar)
tabLayout.FillDirection = Enum.FillDirection.Horizontal
tabLayout.Padding = UDim.new(0, 4)

local body = Instance.new("Frame")
body.Position = UDim2.fromOffset(0, 24)
body.Size = UDim2.new(1, 0, 1, -24)
body.BackgroundColor3 = Color3.fromRGB(8, 8, 14)
body.BackgroundTransparency = 0.45
body.BorderSizePixel = 0
body.Parent = root
Instance.new("UICorner", body).CornerRadius = UDim.new(0, 6)

local pages: { [string]: ScrollingFrame } = {}
local buttons: { [string]: TextButton } = {}
local current = "General"

local function select(tab: string)
	current = tab
	for name, page in pages do
		page.Visible = name == tab
		buttons[name].BackgroundColor3 = if name == tab then Color3.fromRGB(70, 55, 25) else Color3.fromRGB(30, 28, 24)
		if name == tab then
			buttons[name].TextColor3 = Color3.fromRGB(255, 210, 100)
		end
	end
end

for _, name in TABS do
	local page = Instance.new("ScrollingFrame")
	page.Size = UDim2.new(1, -8, 1, -8)
	page.Position = UDim2.fromOffset(4, 4)
	page.BackgroundTransparency = 1
	page.BorderSizePixel = 0
	page.ScrollBarThickness = 4
	page.CanvasSize = UDim2.new()
	page.AutomaticCanvasSize = Enum.AutomaticSize.Y
	page.ScrollingDirection = Enum.ScrollingDirection.Y
	page.Visible = false
	page.Parent = body
	local layout = Instance.new("UIListLayout", page)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 2)
	pages[name] = page

	local button = Instance.new("TextButton")
	button.Size = UDim2.fromOffset(90, 22)
	button.BackgroundColor3 = Color3.fromRGB(30, 28, 24)
	button.BorderSizePixel = 0
	button.Font = Enum.Font.GothamBold
	button.TextSize = 13
	button.TextColor3 = Color3.fromRGB(200, 200, 210)
	button.Text = name
	button.Parent = tabBar
	Instance.new("UICorner", button).CornerRadius = UDim.new(0, 4)
	buttons[name] = button
	button.Activated:Connect(function()
		select(name)
	end)
end
select("General")

local function clear(tab: string)
	for _, child in pages[tab]:GetChildren() do
		if child:IsA("TextLabel") then
			child:Destroy()
		end
	end
end

local order = 0
local function append(tab: string, text: string)
	local page = pages[tab]
	if not page then
		return
	end
	order += 1
	local label = Instance.new("TextLabel")
	label.LayoutOrder = order
	label.Size = UDim2.new(1, -8, 0, 0)
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.BackgroundTransparency = 1
	label.RichText = true
	label.TextWrapped = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Top
	label.Font = Enum.Font.Gotham
	label.TextSize = 14
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.6
	label.Text = text
	label.Parent = page

	local lines = page:GetChildren()
	if #lines > MAX_LINES + 1 then
		for _, child in lines do
			if child:IsA("TextLabel") then
				child:Destroy()
				break
			end
		end
	end
	task.defer(function()
		page.CanvasPosition = Vector2.new(0, math.max(page.AbsoluteCanvasSize.Y - page.AbsoluteWindowSize.Y, 0))
	end)
	if tab ~= current then
		buttons[tab].TextColor3 = if tab == "Whispers" then Color3.fromRGB(255, 128, 255) else Color3.fromRGB(255, 220, 120)
	end
end

chatLine.Event:Connect(append)

player:GetAttributeChangedSignal("InWorld"):Connect(function()
	local inWorld = player:GetAttribute("InWorld") == true
	gui.Enabled = inWorld
	if inWorld then
		clear("General")
		clear("Log")
		select("General")
	end
end)

gui.Parent = player:WaitForChild("PlayerGui")
