local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Opcodes = require(ReplicatedStorage.Shared.Opcodes)
local Config = require(ReplicatedStorage.Shared.Config)
local player = Players.LocalPlayer
local netSend = script.Parent:WaitForChild("NetSend") :: BindableEvent

-- Character select screen. Reads the Characters / InWorld attributes that
-- NetClient keeps, sends CHAR_CREATE / CHAR_DELETE / PLAYER_LOGIN through NetSend.

local GOLD = Color3.fromRGB(255, 210, 100)
local DIM = Color3.fromRGB(170, 170, 180)

local gui = Instance.new("ScreenGui")
gui.Name = "CharacterSelect"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 10

local backdrop = Instance.new("Frame")
backdrop.Size = UDim2.fromScale(1, 1)
backdrop.BackgroundColor3 = Color3.fromRGB(8, 10, 18)
backdrop.BorderSizePixel = 0
backdrop.Parent = gui

local function text(parent, size: UDim2, position: UDim2, label: string, textSize: number, color: Color3): TextLabel
	local l = Instance.new("TextLabel")
	l.Size, l.Position = size, position
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.Garamond
	l.TextSize = textSize
	l.TextColor3 = color
	l.Text = label
	l.Parent = parent
	return l
end

local function button(parent, size: UDim2, position: UDim2, label: string): TextButton
	local b = Instance.new("TextButton")
	b.Size, b.Position = size, position
	b.BackgroundColor3 = Color3.fromRGB(40, 32, 20)
	b.BorderSizePixel = 0
	b.Font = Enum.Font.GothamBold
	b.TextSize = 16
	b.TextColor3 = GOLD
	b.Text = label
	b.AutoButtonColor = true
	Instance.new("UICorner", b).CornerRadius = UDim.new(0, 4)
	local stroke = Instance.new("UIStroke", b)
	stroke.Color = Color3.fromRGB(120, 95, 40)
	b.Parent = parent
	return b
end

text(backdrop, UDim2.new(1, 0, 0, 60), UDim2.new(0, 0, 0.06, 0), "Character Select", 44, GOLD).TextXAlignment = Enum.TextXAlignment.Center

local slots = Instance.new("Frame")
slots.AnchorPoint = Vector2.new(1, 0)
slots.Position = UDim2.new(0.95, 0, 0.18, 0)
slots.Size = UDim2.new(0, 320, 0, 300)
slots.BackgroundTransparency = 1
slots.Parent = backdrop
Instance.new("UIListLayout", slots).Padding = UDim.new(0, 8)

local enter = button(backdrop, UDim2.fromOffset(220, 44), UDim2.new(0.5, -110, 0.82, 0), "Enter World")
local create = button(backdrop, UDim2.fromOffset(160, 36), UDim2.new(0.95, -320, 0.72, 0), "Create New")
local delete = button(backdrop, UDim2.fromOffset(140, 36), UDim2.new(0.95, -140, 0.72, 0), "Delete")
local status = text(backdrop, UDim2.new(0.6, 0, 0, 24), UDim2.new(0.2, 0, 0.9, 0), "", 18, DIM)
status.TextXAlignment = Enum.TextXAlignment.Center

-- create panel
local panel = Instance.new("Frame")
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.5)
panel.Size = UDim2.fromOffset(420, 360)
panel.BackgroundColor3 = Color3.fromRGB(18, 20, 30)
panel.BorderSizePixel = 0
panel.Visible = false
panel.Parent = backdrop
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 6)
text(panel, UDim2.new(1, 0, 0, 40), UDim2.fromOffset(0, 8), "New Character", 30, GOLD).TextXAlignment = Enum.TextXAlignment.Center
local nameBox = Instance.new("TextBox")
nameBox.Size = UDim2.new(1, -40, 0, 36)
nameBox.Position = UDim2.fromOffset(20, 56)
nameBox.BackgroundColor3 = Color3.fromRGB(30, 32, 44)
nameBox.BorderSizePixel = 0
nameBox.Font = Enum.Font.Gotham
nameBox.TextSize = 18
nameBox.TextColor3 = Color3.new(1, 1, 1)
nameBox.PlaceholderText = "Name (2 to 12 letters)"
nameBox.Text = ""
nameBox.ClearTextOnFocus = false
nameBox.Parent = panel
local classes = Instance.new("Frame")
classes.Position = UDim2.fromOffset(20, 104)
classes.Size = UDim2.new(1, -40, 0, 190)
classes.BackgroundTransparency = 1
classes.Parent = panel
local grid = Instance.new("UIGridLayout", classes)
grid.CellSize = UDim2.new(0.5, -4, 0, 34)
grid.CellPadding = UDim2.fromOffset(8, 4)
local chosenClass: string? = nil
local classButtons = {}
for _, class in Config.Classes do
	local b = button(classes, UDim2.new(), UDim2.new(), class.Name)
	b.TextColor3 = Color3.fromHex(class.Color)
	classButtons[class.Name] = b
	b.Activated:Connect(function()
		chosenClass = class.Name
		for name, other in classButtons do
			other.BackgroundColor3 = if name == chosenClass then Color3.fromRGB(70, 55, 25) else Color3.fromRGB(40, 32, 20)
		end
	end)
end
local confirm = button(panel, UDim2.fromOffset(160, 36), UDim2.new(0.5, -170, 1, -50), "Create")
local cancel = button(panel, UDim2.fromOffset(160, 36), UDim2.new(0.5, 10, 1, -50), "Back")

-- state
local characters = {}
local selected: number? = nil
local rows = {}

local function refresh()
	for _, r in rows do
		r:Destroy()
	end
	rows = {}
	local max = player:GetAttribute("MaxCharacters") or Config.MaxCharacters
	for slot = 1, max do
		local char = characters[slot]
		local row = button(slots, UDim2.new(1, 0, 0, 56), UDim2.new(), "")
		row.TextXAlignment = Enum.TextXAlignment.Left
		row.Font = Enum.Font.Gotham
		row.TextSize = 18
		row.RichText = true
		if char then
			local color = "#FFFFFF"
			for _, class in Config.Classes do
				if class.Name == char.Class then
					color = class.Color
				end
			end
			row.Text = ('  <font color="%s"><b>%s</b></font>\n  <font color="#AAAAAA">Level %d %s</font>'):format(color, char.Name, char.Level or 1, char.Class)
		else
			row.Text = '  <font color="#666666">Empty slot</font>'
		end
		row.BackgroundColor3 = if slot == selected then Color3.fromRGB(70, 55, 25) else Color3.fromRGB(28, 24, 18)
		row.Activated:Connect(function()
			selected = if char then slot else nil
			refresh()
		end)
		table.insert(rows, row)
	end
	enter.Visible = selected ~= nil
	delete.Visible = selected ~= nil
	create.Visible = #characters < max
end

local function load()
	local ok, list = pcall(HttpService.JSONDecode, HttpService, player:GetAttribute("Characters") or "[]")
	characters = if ok and typeof(list) == "table" then list else {}
	if selected and not characters[selected] then
		selected = nil
	end
	if not selected and characters[1] then
		selected = 1
	end
	refresh()
end

player:GetAttributeChangedSignal("Characters"):Connect(load)
player:GetAttributeChangedSignal("InWorld"):Connect(function()
	gui.Enabled = player:GetAttribute("InWorld") ~= true
	status.Text = ""
end)
player:GetAttributeChangedSignal("CharError"):Connect(function()
	status.Text = player:GetAttribute("CharError") or ""
end)

enter.Activated:Connect(function()
	if selected then
		status.Text = "Entering world..."
		netSend:Fire(Opcodes.CMSG_PLAYER_LOGIN, { Slot = selected })
	end
end)
delete.Activated:Connect(function()
	if selected then
		netSend:Fire(Opcodes.CMSG_CHAR_DELETE, { Slot = selected })
	end
end)
create.Activated:Connect(function()
	nameBox.Text = ""
	chosenClass = nil
	for _, b in classButtons do
		b.BackgroundColor3 = Color3.fromRGB(40, 32, 20)
	end
	panel.Visible = true
end)
cancel.Activated:Connect(function()
	panel.Visible = false
end)
confirm.Activated:Connect(function()
	if not chosenClass then
		status.Text = "Pick a class."
		return
	end
	netSend:Fire(Opcodes.CMSG_CHAR_CREATE, { Name = nameBox.Text, Class = chosenClass })
	panel.Visible = false
end)

gui.Enabled = player:GetAttribute("InWorld") ~= true
gui.Parent = player:WaitForChild("PlayerGui")
load()
