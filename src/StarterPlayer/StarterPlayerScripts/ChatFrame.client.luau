local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")
local player = Players.LocalPlayer
local chatLine = script.Parent:WaitForChild("ChatLine") :: BindableEvent
local chatSend = script.Parent:WaitForChild("ChatSend") :: BindableEvent
local itemInfo = script.Parent:WaitForChild("ItemInfo") :: BindableFunction
local Ui = require(script.Parent:WaitForChild("Ui"))

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
root.Position = UDim2.new(0, 12, 1, -24)
root.Size = UDim2.fromOffset(440, 266)
root.BackgroundTransparency = 1
root.Parent = gui

-- our input box; / or Enter focuses it, Enter sends, Escape drops focus
local input = Instance.new("TextBox")
input.AnchorPoint = Vector2.new(0, 1)
input.Position = UDim2.new(0, 0, 1, 0)
input.Size = UDim2.new(1, 0, 0, 30)
input.BackgroundColor3 = Color3.fromRGB(8, 8, 14)
input.BackgroundTransparency = 0.3
input.BorderSizePixel = 0
input.Font = Enum.Font.Gotham
input.TextSize = 14
input.TextColor3 = Color3.new(1, 1, 1)
input.PlaceholderText = "Press / to chat"
input.PlaceholderColor3 = Color3.fromRGB(120, 120, 130)
input.TextXAlignment = Enum.TextXAlignment.Left
input.ClearTextOnFocus = false
input.Text = ""
input.Parent = root
Instance.new("UICorner", input).CornerRadius = UDim.new(0, 6)
Instance.new("UIPadding", input).PaddingLeft = UDim.new(0, 8)

input.FocusLost:Connect(function(enterPressed)
	if enterPressed and #input.Text > 0 then
		chatSend:Fire(input.Text)
		input.Text = ""
	end
end)
UserInputService.InputBegan:Connect(function(keyInput, processed)
	if processed or not gui.Enabled or input:IsFocused() then
		return
	end
	if keyInput.KeyCode == Enum.KeyCode.Slash then
		task.defer(function()
			input:CaptureFocus()
			if input.Text == "/" then
				input.Text = ""
			end
			input.Text = "/"
			input.CursorPosition = 2
		end)
	elseif keyInput.KeyCode == Enum.KeyCode.Return then
		task.defer(input.CaptureFocus, input)
	end
end)

-- shift-clicked bag items land here as [Name]
local chatInsert = Instance.new("BindableEvent")
chatInsert.Name = "ChatInsert"
chatInsert.Event:Connect(function(text: string)
	input.Text = input.Text .. text
	input:CaptureFocus()
	input.CursorPosition = #input.Text + 1
end)
chatInsert.Parent = script.Parent

local tabBar = Instance.new("Frame")
tabBar.Size = UDim2.new(1, 0, 0, 22)
tabBar.BackgroundTransparency = 1
tabBar.Parent = root
local tabLayout = Instance.new("UIListLayout", tabBar)
tabLayout.FillDirection = Enum.FillDirection.Horizontal
tabLayout.Padding = UDim.new(0, 4)

local body = Instance.new("Frame")
body.Position = UDim2.fromOffset(0, 24)
body.Size = UDim2.new(1, 0, 1, -60)
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
		if child:IsA("TextLabel") or child:IsA("TextButton") then
			child:Destroy()
		end
	end
end

-- Click a line that carries item links to see the first item's tooltip.
local function showLinks(linksJson: string)
	local ok, links = pcall(HttpService.JSONDecode, HttpService, linksJson)
	if not ok then
		return
	end
	for _, link in links do
		local info = itemInfo:Invoke(link.Entry)
		if info then
			Ui.showTip(Ui.itemTooltip(info, if info.Price then Ui.money(info.Price) else nil))
		else
			local connection
			connection = player:GetAttributeChangedSignal("ItemQueryTick"):Connect(function()
				local later = itemInfo:Invoke(link.Entry)
				if later then
					connection:Disconnect()
					Ui.showTip(Ui.itemTooltip(later, if later.Price then Ui.money(later.Price) else nil))
				end
			end)
		end
		return
	end
end

local order = 0
local function append(tab: string, text: string, linksJson: string?)
	local page = pages[tab]
	if not page then
		return
	end
	order += 1
	local label = Instance.new(if linksJson then "TextButton" else "TextLabel")
	if linksJson then
		label.AutoButtonColor = false
		label.Activated:Connect(function()
			showLinks(linksJson)
		end)
		label.MouseLeave:Connect(Ui.hideTip)
	end
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
			if child:IsA("TextLabel") or child:IsA("TextButton") then
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
