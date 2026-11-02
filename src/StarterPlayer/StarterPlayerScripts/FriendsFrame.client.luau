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
local chatInsert = script.Parent:WaitForChild("ChatInsert") :: BindableEvent

-- Social window on O: Friends with online status, level, class and zone, and the
-- Ignore list. Click a friend to whisper, pick one and Remove, type a name to add.

local scope = Fusion.scoped(Fusion)
local Children, peek = Fusion.Children, Fusion.peek

local open = scope:Value(false)
local tab = scope:Value("Friends")
local picked = scope:Value(nil :: string?)
local contactsJson = Components.attribute(scope, player, "Contacts", "{}")
local contacts = scope:Computed(function(use)
	local ok, value = pcall(HttpService.JSONDecode, HttpService, use(contactsJson))
	return if ok and typeof(value) == "table" then value else {}
end)

local classColor: { [string]: string } = {}
for _, class in Config.Classes do
	classColor[class.Name] = class.Color
end

local rows = scope:Computed(function(use)
	local out = {}
	local c = use(contacts)
	if use(tab) == "Friends" then
		for _, friend in (c.Friends or {}) do
			table.insert(out, {
				Text = ('<font color="%s">%s</font>'):format(if friend.Online then "#40FF40" else "#808080", friend.Name or "?"),
				Right = if friend.Online then ('Level %d <font color="%s">%s</font> - %s'):format(friend.Level or 1, classColor[friend.Class or ""] or "#FFFFFF", friend.Class or "", friend.Zone or "Unknown") else "Offline",
				Tooltip = if friend.Online then "Click to whisper" else nil,
				OnClick = function()
					picked:set(friend.Name)
					if friend.Online then
						chatInsert:Fire("/w " .. friend.Name .. " ")
					end
				end,
			})
		end
	else
		for _, name in (c.Ignore or {}) do
			table.insert(out, { Text = '<font color="#AAAAAA">' .. name .. "</font>", OnClick = function()
				picked:set(name)
			end })
		end
	end
	return out
end)

local nameBox = scope:New "TextBox" {
	Position = UDim2.new(0, 12, 1, -44),
	Size = UDim2.fromOffset(180, 30),
	BackgroundColor3 = Color3.fromRGB(20, 18, 14),
	BackgroundTransparency = 0.2,
	BorderSizePixel = 0,
	Font = Enum.Font.Gotham,
	TextSize = 14,
	TextColor3 = Color3.new(1, 1, 1),
	PlaceholderText = "Character name",
	PlaceholderColor3 = Color3.fromRGB(120, 120, 130),
	TextXAlignment = Enum.TextXAlignment.Left,
	ClearTextOnFocus = false,
	Text = "",
	[Children] = { scope:New "UICorner" { CornerRadius = UDim.new(0, 4) }, scope:New "UIPadding" { PaddingLeft = UDim.new(0, 8) } },
} :: TextBox

local function tabButton(name: string, x: number)
	return Components.Button(scope, {
		Size = UDim2.fromOffset(100, 26),
		Position = UDim2.fromOffset(x, 8),
		Text = name,
		Active = scope:Computed(function(use)
			return use(tab) == name
		end),
		OnClick = function()
			tab:set(name)
			picked:set(nil)
		end,
	})
end

Components.Panel(scope, {
	Name = "FriendsFrame",
	Size = UDim2.fromOffset(460, 400),
	Position = UDim2.new(0.5, -260, 0.5, 0),
	Enabled = open,
	Parent = player:WaitForChild("PlayerGui"),
	Title = "Social",
	[Children] = {
		tabButton("Friends", 12),
		tabButton("Ignore", 118),
		Components.List(scope, { Size = UDim2.new(1, -24, 1, -100), Position = UDim2.fromOffset(12, 42), Rows = rows }),
		nameBox,
		Components.Button(scope, {
			Position = UDim2.new(0, 200, 1, -44),
			Size = UDim2.fromOffset(110, 30),
			Text = scope:Computed(function(use)
				return if use(tab) == "Friends" then "Add Friend" else "Ignore"
			end),
			OnClick = function()
				if #nameBox.Text > 0 then
					netSend:Fire(if peek(tab) == "Friends" then Opcodes.CMSG_ADD_FRIEND else Opcodes.CMSG_ADD_IGNORE, { Name = nameBox.Text })
					nameBox.Text = ""
				end
			end,
		}),
		Components.Button(scope, {
			Position = UDim2.new(1, -122, 1, -44),
			Size = UDim2.fromOffset(110, 30),
			Text = "Remove",
			Visible = scope:Computed(function(use)
				return use(picked) ~= nil
			end),
			OnClick = function()
				local name = peek(picked)
				if name then
					netSend:Fire(if peek(tab) == "Friends" then Opcodes.CMSG_DEL_FRIEND else Opcodes.CMSG_DEL_IGNORE, { Name = name })
					picked:set(nil)
				end
			end,
		}),
	},
})

local function toggle()
	open:set(not peek(open))
	if peek(open) then
		netSend:Fire(Opcodes.CMSG_CONTACT_LIST, {})
	end
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed or player:GetAttribute("InWorld") ~= true then
		return
	end
	if input.KeyCode == Enum.KeyCode.O then
		toggle()
	elseif input.KeyCode == Enum.KeyCode.Escape then
		open:set(false)
	end
end)
player:GetAttributeChangedSignal("ToggleFriends"):Connect(toggle)
player:GetAttributeChangedSignal("InWorld"):Connect(function()
	if player:GetAttribute("InWorld") ~= true then
		open:set(false)
	end
end)
