local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Fusion = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Fusion"))
local Ui = require(script.Parent:WaitForChild("Ui"))
local Components = require(script.Parent:WaitForChild("Components"))
local SpellUi = require(script.Parent:WaitForChild("SpellUi"))
local player = Players.LocalPlayer
local earned = script.Parent:WaitForChild("AchievementEarned") :: BindableEvent

-- Achievements on Y: categories on the left, achievements on the right, earned
-- ones in gold with their date. Earning one drops a toast from the top.

local scope = Fusion.scoped(Fusion)
local Children, peek = Fusion.Children, Fusion.peek

local open = scope:Value(false)
local category = scope:Value("All")
local achievementsJson = Components.attribute(scope, player, "Achievements", "{}")
local data = scope:Computed(function(use)
	return SpellUi.decode(use(achievementsJson), { Points = 0, List = {} })
end)

local categories = scope:Computed(function(use)
	local seen, out = {}, { "All" }
	for _, a in use(data).List do
		if a.Category and not seen[a.Category] then
			seen[a.Category] = true
			table.insert(out, a.Category)
		end
	end
	return out
end)

local categoryRows = scope:Computed(function(use)
	local rows = {}
	for _, name in use(categories) do
		table.insert(rows, { Text = if use(category) == name then ('<font color="#FFD100">%s</font>'):format(name) else name, OnClick = function()
			category:set(name)
		end })
	end
	return rows
end)

local rows = scope:Computed(function(use)
	local out = {}
	for _, a in use(data).List do
		if use(category) == "All" or a.Category == use(category) then
			table.insert(out, {
				Text = ('<font color="%s">%s</font>'):format(if a.Earned then "#FFD100" else "#AAAAAA", a.Name),
				Right = if a.Earned then os.date("%Y-%m-%d", a.Earned) else ("%d pts"):format(a.Points or 10),
				Tooltip = ('<font size="16" color="%s"><b>%s</b></font>\n<font color="#FFD100">%s</font>\n<font color="#AAAAAA">%d points%s</font>'):format(
					if a.Earned then "#FFD100" else "#FFFFFF", a.Name, a.Description or "", a.Points or 10, if a.Earned then "   Earned " .. os.date("%Y-%m-%d", a.Earned) else ""),
			})
		end
	end
	return out
end)

Components.Panel(scope, {
	Name = "AchievementFrame",
	Size = UDim2.fromOffset(600, 440),
	Position = UDim2.new(0.5, 0, 0.5, 0),
	Enabled = open,
	Parent = player:WaitForChild("PlayerGui"),
	Title = scope:Computed(function(use)
		return ("Achievements  %d points"):format(use(data).Points or 0)
	end),
	[Children] = {
		Components.List(scope, { Size = UDim2.new(0, 160, 1, -20), Position = UDim2.fromOffset(12, 10), Rows = categoryRows }),
		Components.List(scope, { Size = UDim2.new(1, -196, 1, -20), Position = UDim2.fromOffset(184, 10), Rows = rows }),
	},
})

-- toast
local toast = scope:Value(nil :: any)
local toastGui = scope:New "ScreenGui" {
	Name = "AchievementToast",
	ResetOnSpawn = false,
	DisplayOrder = 40,
	Parent = player:WaitForChild("PlayerGui"),
	[Children] = scope:New "Frame" {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = scope:Computed(function(use)
			return if use(toast) then UDim2.new(0.5, 0, 0, 40) else UDim2.new(0.5, 0, 0, -120)
		end),
		Size = UDim2.fromOffset(360, 70),
		BackgroundColor3 = Ui.PANEL,
		BackgroundTransparency = 0.05,
		BorderSizePixel = 0,
		[Children] = {
			scope:New "UICorner" { CornerRadius = UDim.new(0, 8) },
			scope:New "UIStroke" { Color = Ui.GOLD, Thickness = 2 },
			scope:New "UIGradient" { Color = ColorSequence.new(Ui.BAR_TOP, Ui.PANEL), Rotation = 90 },
			Components.Text(scope, { Position = UDim2.fromOffset(14, 8), Size = UDim2.new(1, -28, 0, 20), TextSize = 12, Color = Ui.DIM, Align = Enum.TextXAlignment.Center, Text = "Achievement Earned!" }),
			Components.Text(scope, { Position = UDim2.fromOffset(14, 28), Size = UDim2.new(1, -28, 0, 24), Font = Enum.Font.GothamBold, TextSize = 17, Color = Ui.GOLD, Align = Enum.TextXAlignment.Center, Text = scope:Computed(function(use)
				local t = use(toast)
				return if t then ("%s  (%d)"):format(t.Name or "?", t.Points or 10) else ""
			end) }),
		},
	},
}
local shown = 0
earned.Event:Connect(function(d)
	shown += 1
	local mine = shown
	toast:set(d)
	task.delay(5, function()
		if shown == mine then
			toast:set(nil)
		end
	end)
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed or player:GetAttribute("InWorld") ~= true then
		return
	end
	if input.KeyCode == Enum.KeyCode.Y then
		open:set(not peek(open))
	elseif input.KeyCode == Enum.KeyCode.Escape then
		open:set(false)
	end
end)
player:GetAttributeChangedSignal("InWorld"):Connect(function()
	if player:GetAttribute("InWorld") ~= true then
		open:set(false)
	end
end)
