local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Fusion = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Fusion"))
local Ui = require(script.Parent:WaitForChild("Ui"))
local Components = require(script.Parent:WaitForChild("Components"))
local player = Players.LocalPlayer
local chatLine = script.Parent:WaitForChild("ChatLine") :: BindableEvent
local chatSend = script.Parent:WaitForChild("ChatSend") :: BindableEvent
local itemInfo = script.Parent:WaitForChild("ItemInfo") :: BindableFunction

-- Chat window: tabs General, Whispers and Log, rich text lines, our own input
-- box. Shown only in the world; entering clears General and Log, Whispers keep.
-- Hovering a line with item links shows the first item's tooltip; shift-click
-- inserts it into the input.

local TABS = { "General", "Whispers", "Log" }
local MAX_LINES = 150

local scope = Fusion.scoped(Fusion)
local Children, OnEvent, peek = Fusion.Children, Fusion.OnEvent, Fusion.peek

local inWorld = Components.attribute(scope, player, "InWorld", false)
local current = scope:Value("General")
local unread = scope:Value({} :: { [string]: boolean })
local lines: { [string]: any } = {}
local pages: { [string]: ScrollingFrame } = {}
for _, tab in TABS do
	lines[tab] = scope:Value({})
end

local function shiftHeld(): boolean
	return UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
end

local function links(json: string?)
	local ok, list = pcall(HttpService.JSONDecode, HttpService, json or "")
	return if ok and typeof(list) == "table" then list else {}
end

-- tooltip for the first linked item, waiting for the query if it is not cached yet
local function showLinks(json: string)
	local link = links(json)[1]
	if not link then
		return
	end
	local function tip(info)
		Ui.showTip(Ui.itemTooltip(info), Ui.itemBorder(info))
	end
	local info = itemInfo:Invoke(link.Entry)
	if info then
		return tip(info)
	end
	local connection
	connection = player:GetAttributeChangedSignal("ItemQueryTick"):Connect(function()
		local later = itemInfo:Invoke(link.Entry)
		if later then
			connection:Disconnect()
			tip(later)
		end
	end)
end

local input = scope:New "TextBox" {
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(0, 0, 1, 0),
	Size = UDim2.new(1, 0, 0, 30),
	BackgroundColor3 = Color3.fromRGB(8, 8, 14),
	BackgroundTransparency = 0.3,
	BorderSizePixel = 0,
	Font = Enum.Font.Gotham,
	TextSize = 14,
	TextColor3 = Color3.new(1, 1, 1),
	PlaceholderText = "Press / to chat",
	PlaceholderColor3 = Color3.fromRGB(120, 120, 130),
	TextXAlignment = Enum.TextXAlignment.Left,
	ClearTextOnFocus = false,
	Text = "",
	[Children] = {
		scope:New "UICorner" { CornerRadius = UDim.new(0, 6) },
		scope:New "UIPadding" { PaddingLeft = UDim.new(0, 8) },
	},
} :: TextBox

input.FocusLost:Connect(function(enterPressed)
	local text = input.Text:gsub("^//+", "/")
	if enterPressed and #text > 0 then
		chatSend:Fire(text)
	end
	if enterPressed then
		input.Text = ""
	end
end)

local function line(scope, entry)
	local props = {
		Size = UDim2.new(1, -8, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = entry.Order,
		BackgroundTransparency = 1,
		RichText = true,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Font = Enum.Font.Gotham,
		TextSize = 14,
		TextColor3 = Color3.new(1, 1, 1),
		TextStrokeTransparency = 0.6,
		Text = entry.Text,
	}
	if not entry.Links then
		return scope:New "TextLabel"(props)
	end
	props.AutoButtonColor = false
	props[OnEvent "MouseEnter"] = function()
		showLinks(entry.Links)
	end
	props[OnEvent "MouseLeave"] = Ui.hideTip
	props[OnEvent "Activated"] = function()
		local link = links(entry.Links)[1]
		if link and shiftHeld() then
			script.Parent.ChatInsert:Fire("[" .. link.Name .. "]")
		end
	end
	return scope:New "TextButton"(props)
end

local function page(tab: string)
	local frame = scope:New "ScrollingFrame" {
		Size = UDim2.new(1, -8, 1, -8),
		Position = UDim2.fromOffset(4, 4),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Visible = scope:Computed(function(use)
			return use(current) == tab
		end),
		[Children] = {
			scope:New "UIListLayout" { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 2) },
			scope:ForValues(lines[tab], function(use, scope, entry)
				return line(scope, entry)
			end),
		},
	} :: ScrollingFrame
	pages[tab] = frame
	return frame
end

local function tabButton(tab: string)
	return Components.Button(scope, {
		Size = UDim2.fromOffset(90, 22),
		LayoutOrder = table.find(TABS, tab),
		Text = tab,
		Active = scope:Computed(function(use)
			return use(current) == tab
		end),
		Color = scope:Computed(function(use)
			if use(current) == tab then
				return Ui.GOLD
			elseif use(unread)[tab] then
				return if tab == "Whispers" then Color3.fromRGB(255, 128, 255) else Color3.fromRGB(255, 220, 120)
			end
			return Color3.fromRGB(200, 200, 210)
		end),
		OnClick = function()
			current:set(tab)
			local u = table.clone(peek(unread))
			u[tab] = nil
			unread:set(u)
		end,
	})
end

local tabs, pagesList = {}, {}
for _, tab in TABS do
	table.insert(tabs, tabButton(tab))
	table.insert(pagesList, page(tab))
end

scope:New "ScreenGui" {
	Name = "ChatFrame",
	ResetOnSpawn = false,
	Enabled = scope:Computed(function(use)
		return use(inWorld) == true
	end),
	Parent = player:WaitForChild("PlayerGui"),
	[Children] = scope:New "Frame" {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 12, 1, -24),
		Size = UDim2.fromOffset(440, 266),
		BackgroundTransparency = 1,
		[Children] = {
			scope:New "Frame" {
				Size = UDim2.new(1, 0, 0, 22),
				BackgroundTransparency = 1,
				[Children] = { scope:New "UIListLayout" { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, tabs },
			},
			scope:New "Frame" {
				Position = UDim2.fromOffset(0, 24),
				Size = UDim2.new(1, 0, 1, -60),
				BackgroundColor3 = Color3.fromRGB(8, 8, 14),
				BackgroundTransparency = 0.45,
				BorderSizePixel = 0,
				[Children] = { scope:New "UICorner" { CornerRadius = UDim.new(0, 6) }, pagesList },
			},
			input,
		},
	},
}

local order = 0
chatLine.Event:Connect(function(tab: string, text: string, linksJson: string?)
	local state = lines[tab]
	if not state then
		return
	end
	order += 1
	local list = table.clone(peek(state))
	table.insert(list, { Order = order, Text = text, Links = linksJson })
	while #list > MAX_LINES do
		table.remove(list, 1)
	end
	state:set(list)
	if tab ~= peek(current) then
		local u = table.clone(peek(unread))
		u[tab] = true
		unread:set(u)
	end
	task.defer(function()
		local frame = pages[tab]
		frame.CanvasPosition = Vector2.new(0, math.max(frame.AbsoluteCanvasSize.Y - frame.AbsoluteWindowSize.Y, 0))
	end)
end)

-- / or Enter focuses the box, Enter sends, Escape drops focus
UserInputService.InputBegan:Connect(function(keyInput, processed)
	if processed or peek(inWorld) ~= true or input:IsFocused() then
		return
	end
	if keyInput.KeyCode == Enum.KeyCode.Slash or keyInput.KeyCode == Enum.KeyCode.Return then
		task.defer(function()
			input:CaptureFocus()
			task.wait()
			input.Text = input.Text:gsub("^/+$", "")
			input.CursorPosition = #input.Text + 1
		end)
	end
end)

-- shift-clicked links from anywhere land here
local chatInsert = Instance.new("BindableEvent")
chatInsert.Name = "ChatInsert"
chatInsert.Event:Connect(function(text: string)
	input.Text = input.Text .. text
	input:CaptureFocus()
	input.CursorPosition = #input.Text + 1
end)
chatInsert.Parent = script.Parent

scope:Observer(inWorld):onChange(function()
	if peek(inWorld) == true then
		lines.General:set({})
		lines.Log:set({})
		current:set("General")
	end
end)
