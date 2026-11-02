local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Fusion = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Fusion"))
local Opcodes = require(ReplicatedStorage.Shared.Opcodes)
local Config = require(ReplicatedStorage.Shared.Config)
local Ui = require(script.Parent:WaitForChild("Ui"))
local Components = require(script.Parent:WaitForChild("Components"))
local player = Players.LocalPlayer
local netSend = script.Parent:WaitForChild("NetSend") :: BindableEvent

-- Quest log on L: active quests with objective progress; right-click abandons.
-- Questgiver markers (! and ?) over creatures are drawn here too.

local scope = Fusion.scoped(Fusion)
local Children, peek = Fusion.Children, Fusion.peek

local open = scope:Value(false)
local log = Components.attribute(scope, player, "QuestLog", "[]")
local statuses = Components.attribute(scope, player, "QuestgiverStatus", "{}")

local function decode(json: string, default)
	local ok, value = pcall(HttpService.JSONDecode, HttpService, json)
	return if ok and typeof(value) == "table" then value else default
end

local rows = scope:Computed(function(use)
	local out = {}
	for _, quest in decode(use(log), {}) do
		local progress = {}
		for _, line in (quest.Progress or {}) do
			table.insert(progress, ("%s: %d/%d"):format(line.Text, line.Have, line.Need))
		end
		table.insert(out, {
			Text = ('<font color="%s">[%d] %s</font>%s'):format(Config.Chat.Colors.QUEST, quest.Level or 1, quest.Title or "?", if quest.Complete then ' <font color="#808080">(Complete)</font>' else ""),
			Right = table.concat(progress, "  "),
			Tooltip = (quest.Objectives or "") .. "\n\n" .. table.concat(progress, "\n") .. '\n<font color="#AAAAAA">Right-click to abandon</font>',
		})
	end
	return out
end)

Components.Panel(scope, {
	Name = "QuestLogFrame",
	Size = UDim2.fromOffset(520, 360),
	Position = UDim2.new(0.5, 0, 0.5, -20),
	Enabled = open,
	Parent = player:WaitForChild("PlayerGui"),
	Title = scope:Computed(function(use)
		return ("Quest Log (%d/%d)"):format(#decode(use(log), {}), Config.QuestLogSize)
	end),
	[Children] = {
		Components.List(scope, { Size = UDim2.new(1, -24, 1, -20), Position = UDim2.fromOffset(12, 10), Rows = rows }),
	},
})

-- right-click abandon: the list rows are buttons; find them by text order
local gui = player.PlayerGui:WaitForChild("QuestLogFrame")
gui.DescendantAdded:Connect(function(child)
	if child:IsA("TextButton") and child.Parent and child.Parent:IsA("ScrollingFrame") then
		child.MouseButton2Click:Connect(function()
			local quests = decode(player:GetAttribute("QuestLog") or "[]", {})
			local quest = quests[child.LayoutOrder]
			if quest then
				netSend:Fire(Opcodes.CMSG_QUESTLOG_REMOVE_QUEST, { Quest = quest.Id })
			end
		end)
	end
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed or player:GetAttribute("InWorld") ~= true then
		return
	end
	if input.KeyCode == Enum.KeyCode.L then
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

-- markers over questgivers
local markers: { [string]: BillboardGui } = {}
local function marker(model: Model, text: string, color: Color3)
	local root = model:FindFirstChild("Head") or model:FindFirstChild("HumanoidRootPart")
	if not root then
		return nil
	end
	local gui2 = Instance.new("BillboardGui")
	gui2.Name = "QuestMarker"
	gui2.Size = UDim2.fromOffset(40, 60)
	gui2.StudsOffset = Vector3.new(0, 3, 0)
	gui2.AlwaysOnTop = true
	gui2.MaxDistance = 80
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = color
	label.TextStrokeTransparency = 0.3
	label.Text = text
	label.Parent = gui2
	gui2.Parent = root
	return gui2
end

local function refreshMarkers()
	for _, m in markers do
		m:Destroy()
	end
	markers = {}
	local creatures = workspace:FindFirstChild("Creatures")
	if not creatures then
		return
	end
	local map = decode(player:GetAttribute("QuestgiverStatus") or "{}", {})
	for _, model in creatures:GetChildren() do
		local status = map[model:GetAttribute("Guid") or ""]
		if status == "available" then
			markers[model:GetAttribute("Guid")] = marker(model, "!", Color3.fromRGB(255, 220, 0))
		elseif status == "complete" then
			markers[model:GetAttribute("Guid")] = marker(model, "?", Color3.fromRGB(255, 220, 0))
		elseif status == "incomplete" then
			markers[model:GetAttribute("Guid")] = marker(model, "?", Color3.fromRGB(140, 140, 140))
		end
	end
end
player:GetAttributeChangedSignal("QuestgiverStatus"):Connect(refreshMarkers)
task.spawn(function()
	local creatures = workspace:WaitForChild("Creatures", 30)
	if creatures then
		creatures.ChildAdded:Connect(function()
			task.wait(0.5)
			refreshMarkers()
		end)
	end
	refreshMarkers()
end)
