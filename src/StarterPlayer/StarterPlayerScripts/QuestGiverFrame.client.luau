local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Fusion = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Fusion"))
local Opcodes = require(ReplicatedStorage.Shared.Opcodes)
local Config = require(ReplicatedStorage.Shared.Config)
local Ui = require(script.Parent:WaitForChild("Ui"))
local Components = require(script.Parent:WaitForChild("Components"))
local player = Players.LocalPlayer
local netSend = script.Parent:WaitForChild("NetSend") :: BindableEvent
local questList = script.Parent:WaitForChild("QuestList") :: BindableEvent
local questDetails = script.Parent:WaitForChild("QuestDetails") :: BindableEvent

-- Questgiver window: the greeting and the quests this NPC has for you; pick one
-- for its details and rewards, then Accept or Complete. Closes with Escape or X.

local scope = Fusion.scoped(Fusion)
local Children, peek = Fusion.Children, Fusion.peek

local open = scope:Value(false)
local guid = scope:Value(nil :: string?)
local title = scope:Value("Questgiver")
local greeting = scope:Value("")
local quests = scope:Value({})
local detail = scope:Value(nil :: any)

local MARK = { available = ('<font color="%s">!</font> '):format(Config.Chat.Colors.QUEST), complete = ('<font color="%s">?</font> '):format(Config.Chat.Colors.QUEST), incomplete = '<font color="#888888">?</font> ' }

local listRows = scope:Computed(function(use)
	local rows = {}
	for _, quest in use(quests) do
		table.insert(rows, { Text = (MARK[quest.Status] or "") .. (quest.Title or "?"), OnClick = function()
			netSend:Fire(Opcodes.CMSG_QUESTGIVER_QUERY_QUEST, { Guid = peek(guid), Quest = quest.Id })
		end })
	end
	return rows
end)

local body = scope:Computed(function(use)
	local d = use(detail)
	if not d then
		return use(greeting)
	end
	local lines = { ('<font size="20" color="%s"><b>%s</b></font>'):format(Config.Chat.Colors.QUEST, d.Title or "?"), "", d.Details or "", "",
		'<font color="#FFD100"><b>Objectives</b></font>', d.Objectives or "", "", '<font color="#FFD100"><b>Rewards</b></font>' }
	if (d.RewardXp or 0) > 0 then table.insert(lines, ("%d experience"):format(d.RewardXp)) end
	if (d.RewardMoney or 0) > 0 then table.insert(lines, ('<font color="#FFD700">%s</font>'):format(Ui.money(d.RewardMoney))) end
	for _, item in (d.RewardItems or {}) do
		table.insert(lines, Ui.itemName(item))
	end
	return table.concat(lines, "\n")
end)

local actionText = scope:Computed(function(use)
	local d = use(detail)
	return if not d then "" elseif d.Status == "available" then "Accept" elseif d.Status == "complete" then "Complete Quest" else "Not yet complete"
end)

Components.Panel(scope, {
	Name = "QuestGiverFrame",
	Size = UDim2.fromOffset(560, 420),
	Position = UDim2.new(0.5, 40, 0.5, 0),
	Enabled = open,
	Parent = player:WaitForChild("PlayerGui"),
	Title = title,
	[Children] = {
		Components.List(scope, { Size = UDim2.new(0, 190, 1, -60), Position = UDim2.fromOffset(12, 10), Rows = listRows }),
		scope:New "TextLabel" {
			Position = UDim2.fromOffset(214, 10),
			Size = UDim2.new(1, -226, 1, -60),
			BackgroundColor3 = Color3.fromRGB(20, 18, 14),
			BackgroundTransparency = 0.3,
			BorderSizePixel = 0,
			Font = Enum.Font.Gotham,
			TextSize = 14,
			TextColor3 = Color3.fromRGB(230, 225, 210),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			TextWrapped = true,
			RichText = true,
			Text = body,
			[Children] = {
				scope:New "UICorner" { CornerRadius = UDim.new(0, 6) },
				scope:New "UIPadding" { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10), PaddingTop = UDim.new(0, 8) },
			},
		},
		Components.Button(scope, {
			Size = UDim2.fromOffset(180, 32),
			Position = UDim2.new(1, -192, 1, -42),
			Text = actionText,
			OnClick = function()
				local d = peek(detail)
				if not d then
					return
				end
				if d.Status == "available" then
					netSend:Fire(Opcodes.CMSG_QUESTGIVER_ACCEPT_QUEST, { Guid = peek(guid), Quest = d.Id })
					open:set(false)
				elseif d.Status == "complete" then
					netSend:Fire(Opcodes.CMSG_QUESTGIVER_COMPLETE_QUEST, { Guid = peek(guid), Quest = d.Id })
				end
			end,
		}),
	},
})

questList.Event:Connect(function(d)
	if not d then
		open:set(false)
		return
	end
	guid:set(tostring(d.Guid))
	title:set(d.Name or "Questgiver")
	greeting:set(d.Greeting or "Greetings, traveler.")
	quests:set(d.Quests or {})
	detail:set(nil)
	open:set(true)
	if #(d.Quests or {}) == 1 then
		netSend:Fire(Opcodes.CMSG_QUESTGIVER_QUERY_QUEST, { Guid = tostring(d.Guid), Quest = d.Quests[1].Id })
	end
end)
questDetails.Event:Connect(function(d)
	detail:set(d)
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
