local Players = game:GetService("Players")
local player = Players.LocalPlayer

-- One UIScale per ScreenGui, from the viewport height: 1080 tall is 1, with a
-- floor and ceiling so phones and 4K screens both read. Tooltips and drag
-- compute from absolute positions and follow along.

local MIN, MAX = 0.65, 1.3
local camera = workspace.CurrentCamera

local function factor(): number
	return math.clamp(camera.ViewportSize.Y / 1080, MIN, MAX)
end

local scales: { UIScale } = {}

-- the drag ghost and the tooltip position themselves in screen pixels
local UNSCALED = { DragGhost = true, Tooltip = true }

local function attach(gui: Instance)
	if not gui:IsA("ScreenGui") or gui:FindFirstChild("UiScale") or UNSCALED[gui.Name] then
		return
	end
	local scale = Instance.new("UIScale")
	scale.Name = "UiScale"
	scale.Scale = factor()
	scale.Parent = gui
	table.insert(scales, scale)
end

local function refresh()
	local f = factor()
	for i = #scales, 1, -1 do
		local scale = scales[i]
		if scale.Parent then
			scale.Scale = f
		else
			table.remove(scales, i)
		end
	end
end

local gui = player:WaitForChild("PlayerGui")
gui.ChildAdded:Connect(attach)
for _, child in gui:GetChildren() do
	attach(child)
end
camera:GetPropertyChangedSignal("ViewportSize"):Connect(refresh)
