local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Fusion = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Fusion"))
local Opcodes = require(ReplicatedStorage.Shared.Opcodes)
local Ui = require(script.Parent:WaitForChild("Ui"))
local Components = require(script.Parent:WaitForChild("Components"))
local player = Players.LocalPlayer
local netSend = script.Parent:WaitForChild("NetSend") :: BindableEvent
local rollStart = script.Parent:WaitForChild("RollStart") :: BindableEvent

-- Group loot rolls: a prompt per item with Need, Greed and Pass and a timer bar,
-- stacked at the right of the screen.

local scope = Fusion.scoped(Fusion)
local Children, OnEvent, peek = Fusion.Children, Fusion.OnEvent, Fusion.peek

local rolls = scope:Value({})
local now = scope:Value(os.clock())
RunService.Heartbeat:Connect(function()
	now:set(os.clock())
end)

local function remove(id)
	local list = table.clone(peek(rolls))
	for i, roll in list do
		if roll.Id == id then
			table.remove(list, i)
		end
	end
	rolls:set(list)
end

local function vote(roll, choice: string)
	return function()
		netSend:Fire(Opcodes.CMSG_LOOT_ROLL, { Id = roll.Id, Vote = choice })
		remove(roll.Id)
	end
end

local function prompt(scope, roll)
	local item = roll.Item or {}
	return scope:New "Frame" {
		Size = UDim2.fromOffset(300, 74),
		BackgroundColor3 = Ui.PANEL,
		BackgroundTransparency = 0.05,
		BorderSizePixel = 0,
		[Children] = {
			scope:New "UICorner" { CornerRadius = UDim.new(0, 6) },
			scope:New "UIStroke" { Color = Ui.itemBorder(item) },
			scope:New "TextButton" {
				Position = UDim2.fromOffset(10, 8),
				Size = UDim2.new(1, -20, 0, 20),
				BackgroundTransparency = 1,
				Font = Enum.Font.GothamBold,
				TextSize = 14,
				TextXAlignment = Enum.TextXAlignment.Left,
				RichText = true,
				TextColor3 = Color3.new(1, 1, 1),
				Text = Ui.itemName(item),
				[OnEvent "MouseEnter"] = function()
					Ui.showTip(Ui.itemTooltip(item), Ui.itemBorder(item))
				end,
				[OnEvent "MouseLeave"] = Ui.hideTip,
			},
			Components.Button(scope, { Size = UDim2.fromOffset(84, 26), Position = UDim2.fromOffset(10, 34), Text = "Need", Color = Color3.fromRGB(255, 120, 120), OnClick = vote(roll, "need") }),
			Components.Button(scope, { Size = UDim2.fromOffset(84, 26), Position = UDim2.fromOffset(108, 34), Text = "Greed", Color = Ui.GOLD, OnClick = vote(roll, "greed") }),
			Components.Button(scope, { Size = UDim2.fromOffset(84, 26), Position = UDim2.fromOffset(206, 34), Text = "Pass", Color = Ui.DIM, OnClick = vote(roll, "pass") }),
			scope:New "Frame" {
				AnchorPoint = Vector2.new(0, 1),
				Position = UDim2.new(0, 10, 1, -4),
				Size = scope:Computed(function(use)
					return UDim2.new(math.clamp((roll.Ends - use(now)) / math.max(roll.Seconds, 1), 0, 1), -20, 0, 3)
				end),
				BackgroundColor3 = Ui.GOLD,
				BorderSizePixel = 0,
			},
		},
	}
end

scope:New "ScreenGui" {
	Name = "RollFrame",
	ResetOnSpawn = false,
	DisplayOrder = 25,
	Parent = player:WaitForChild("PlayerGui"),
	[Children] = scope:New "Frame" {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -16, 0.5, -120),
		Size = UDim2.fromOffset(300, 400),
		BackgroundTransparency = 1,
		[Children] = {
			scope:New "UIListLayout" { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder },
			scope:ForPairs(rolls, function(use, scope, index, roll)
				return index, prompt(scope, roll)
			end),
		},
	},
}

rollStart.Event:Connect(function(d)
	local list = table.clone(peek(rolls))
	table.insert(list, { Id = d.Id, Item = d.Item, Seconds = d.Seconds or 30, Ends = os.clock() + (d.Seconds or 30) })
	rolls:set(list)
	task.delay(d.Seconds or 30, function()
		remove(d.Id)
	end)
end)
