-- Drag and drop between windows. begin() lifts a payload with a ghost tile that
-- follows the mouse; targets register a GuiObject and get the payload on drop.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local player = Players.LocalPlayer

local Drag = {}

local payload = nil
local targets: { { Gui: GuiObject, OnDrop: (any) -> () } } = {}

local gui = Instance.new("ScreenGui")
gui.Name = "DragGhost"
gui.ResetOnSpawn = false
gui.DisplayOrder = 60
local ghost = Instance.new("TextLabel")
ghost.AnchorPoint = Vector2.new(0.5, 0.5)
ghost.Size = UDim2.fromOffset(50, 50)
ghost.BackgroundColor3 = Color3.fromRGB(28, 26, 34)
ghost.BackgroundTransparency = 0.15
ghost.BorderSizePixel = 0
ghost.Font = Enum.Font.GothamBold
ghost.TextSize = 18
ghost.Visible = false
ghost.Parent = gui
Instance.new("UICorner", ghost).CornerRadius = UDim.new(0, 4)
local stroke = Instance.new("UIStroke", ghost)
stroke.Thickness = 2
gui.Parent = player:WaitForChild("PlayerGui")

function Drag.begin(data, label: string, color: Color3)
	payload = data
	ghost.Text = label
	ghost.TextColor3 = color
	stroke.Color = color
	local m = UserInputService:GetMouseLocation()
	ghost.Position = UDim2.fromOffset(m.X, m.Y)
	ghost.Visible = true
end

function Drag.active()
	return payload
end

function Drag.target(target: GuiObject, onDrop: (any) -> ())
	table.insert(targets, { Gui = target, OnDrop = onDrop })
	target.Destroying:Connect(function()
		for i, t in targets do
			if t.Gui == target then
				table.remove(targets, i)
				break
			end
		end
	end)
end

local function under(position: Vector2): GuiObject?
	-- last registered wins, so tiles beat the windows they sit in
	for i = #targets, 1, -1 do
		local g = targets[i].Gui
		if g.Visible and g:IsDescendantOf(player.PlayerGui) then
			local p, s = g.AbsolutePosition, g.AbsoluteSize
			if position.X >= p.X and position.X <= p.X + s.X and position.Y >= p.Y and position.Y <= p.Y + s.Y then
				local ancestorsVisible = true
				local a = g.Parent
				while a and a:IsA("GuiObject") do
					if not a.Visible then
						ancestorsVisible = false
					end
					a = a.Parent
				end
				local screen = g:FindFirstAncestorOfClass("ScreenGui")
				if ancestorsVisible and screen and screen.Enabled then
					return targets[i]
				end
			end
		end
	end
	return nil
end

RunService.RenderStepped:Connect(function()
	if payload then
		local m = UserInputService:GetMouseLocation()
		ghost.Position = UDim2.fromOffset(m.X, m.Y)
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 or not payload then
		return
	end
	local data = payload
	payload = nil
	ghost.Visible = false
	local target = under(UserInputService:GetMouseLocation())
	if target then
		target.OnDrop(data)
	end
end)

return Drag
