-- Drag and drop between windows. begin() lifts a payload with a ghost tile that
-- follows the mouse; targets register a GuiObject and get the payload on drop.
local Players = game:GetService("Players")
local GuiService = game:GetService("GuiService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local player = Players.LocalPlayer

local Drag = {}

local payload = nil
local targets: { { Gui: GuiObject, OnDrop: (any) -> () } } = {}
local misses: { (any) -> () } = {}

local gui = Instance.new("ScreenGui")
gui.Name = "DragGhost"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true -- mouse coordinates include the top bar inset
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

-- Called with the payload when a drag ends over no target (WoW drops it).
function Drag.onMiss(handler: (any) -> ())
	table.insert(misses, handler)
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

local function under(mouse: Vector2): GuiObject?
	-- Mouse coordinates include the top bar inset; AbsolutePosition does not
	-- unless the ScreenGui ignores the inset.
	local inset = GuiService:GetGuiInset()
	-- last registered wins, so tiles beat the windows they sit in
	for i = #targets, 1, -1 do
		local g = targets[i].Gui
		if g.Visible and g:IsDescendantOf(player.PlayerGui) then
			local screen = g:FindFirstAncestorOfClass("ScreenGui")
			local position = if screen and screen.IgnoreGuiInset then mouse else mouse - inset
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
	else
		for _, handler in misses do
			handler(data)
		end
	end
end)

return Drag
