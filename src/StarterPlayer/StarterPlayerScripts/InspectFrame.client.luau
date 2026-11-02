local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Fusion = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Fusion"))
local Config = require(ReplicatedStorage.Shared.Config)
local Ui = require(script.Parent:WaitForChild("Ui"))
local Components = require(script.Parent:WaitForChild("Components"))
local player = Players.LocalPlayer
local inspectResult = script.Parent:WaitForChild("InspectResult") :: BindableEvent

-- Inspect window from /inspect: another player's gear as a list with tooltips,
-- their stats and talent spread.

local scope = Fusion.scoped(Fusion)
local Children, peek = Fusion.Children, Fusion.peek

local open = scope:Value(false)
local data = scope:Value({})

local classColor: { [string]: string } = {}
for _, class in Config.Classes do
	classColor[class.Name] = class.Color
end

local rows = scope:Computed(function(use)
	local d = use(data)
	local out = {}
	for _, slotName in Config.Slots do
		local item = d.Equipment and d.Equipment[slotName]
		table.insert(out, {
			Text = ("%s:  %s"):format(slotName:sub(1, 1):upper() .. slotName:sub(2), if item then Ui.itemName(item) else '<font color="#666666">empty</font>'),
			Tooltip = if item then Ui.itemTooltip(item) else nil,
			TooltipBorder = if item then Ui.itemBorder(item) else nil,
			Link = if item then "[" .. (item.Name or "?") .. "]" else nil,
		})
	end
	return out
end)

Components.Panel(scope, {
	Name = "InspectFrame",
	Size = UDim2.fromOffset(380, 420),
	Position = UDim2.new(0.5, -200, 0.5, 0),
	Enabled = open,
	Parent = player:WaitForChild("PlayerGui"),
	Title = scope:Computed(function(use)
		local d = use(data)
		return ('<font color="%s">%s</font>'):format(classColor[d.Class or ""] or "#FFFFFF", d.Name or "Inspect")
	end),
	[Children] = {
		Components.Text(scope, { Position = UDim2.fromOffset(12, 8), Size = UDim2.new(1, -24, 0, 40), TextSize = 13, Color = Ui.DIM, Wrapped = true, Text = scope:Computed(function(use)
			local d = use(data)
			local s = d.Stats or {}
			local talents = {}
			for tab, points in (d.Talents or {}) do
				table.insert(talents, ("%d"):format(points))
			end
			return ("Level %d %s %s%s\nHealth %d   Str %d  Agi %d  Sta %d  Int %d  Spi %d   Honor %d (%d HK)%s"):format(d.Level or 1, d.Race or "", d.Class or "",
				if d.Guild then ("  <%s>"):format(d.Guild) else "", s.Health or 0, s.Strength or 0, s.Agility or 0, s.Stamina or 0, s.Intellect or 0, s.Spirit or 0,
				d.Honor or 0, d.HonorKills or 0, if #talents > 0 then "   Talents " .. table.concat(talents, "/") else "")
		end) }),
		Components.List(scope, { Size = UDim2.new(1, -24, 1, -64), Position = UDim2.fromOffset(12, 54), Rows = rows }),
	},
})

inspectResult.Event:Connect(function(d)
	data:set(d)
	open:set(true)
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if not processed and input.KeyCode == Enum.KeyCode.Escape then
		open:set(false)
	end
end)
player:GetAttributeChangedSignal("InWorld"):Connect(function()
	if player:GetAttribute("InWorld") ~= true then
		open:set(false)
	end
end)
