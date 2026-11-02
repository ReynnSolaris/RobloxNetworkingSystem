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
local guildJson = Components.attribute(scope, player, "GuildRoster", "")
local guild = scope:Computed(function(use)
	local ok, value = pcall(HttpService.JSONDecode, HttpService, use(guildJson))
	return if ok and typeof(value) == "table" and value.Name then value else nil
end)
local isGuild = scope:Computed(function(use)
	return use(tab) == "Guild"
end)
local inGuild = scope:Computed(function(use)
	return use(guild) ~= nil
end)
local myRank = scope:Computed(function(use)
	local g = use(guild)
	return if g then g.Rank or 2 else 2
end)
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
	elseif use(tab) == "Ignore" then
		for _, name in (c.Ignore or {}) do
			table.insert(out, { Text = '<font color="#AAAAAA">' .. name .. "</font>", OnClick = function()
				picked:set(name)
			end })
		end
	else
		local g = use(guild)
		for _, member in (g and g.Members or {}) do
			table.insert(out, {
				Text = ('<font color="%s">%s</font> <font color="#AAAAAA">%s</font>'):format(if member.Online then "#40FF40" else "#808080", member.Name or "?", member.RankName or ""),
				Right = if member.Online then ('Level %d <font color="%s">%s</font> - %s'):format(member.Level or 1, classColor[member.Class or ""] or "#FFFFFF", member.Class or "", member.Zone or "Unknown") else "Offline",
				OnClick = function()
					picked:set(member.Name)
				end,
			})
		end
	end
	return out
end)

local function guildAction(action: string, target: string?)
	netSend:Fire(Opcodes.CMSG_GUILD, { Action = action, Target = target })
end

local function smallButton(text, x: number, visible, onClick)
	return Components.Button(scope, {
		Position = UDim2.new(0, x, 1, -80),
		Size = UDim2.fromOffset(100, 28),
		TextSize = 12,
		Text = text,
		Visible = visible,
		OnClick = onClick,
	})
end
local canManage = scope:Computed(function(use)
	return use(isGuild) and use(inGuild) and use(myRank) <= 1 and use(picked) ~= nil
end)
local isLeader = scope:Computed(function(use)
	return use(isGuild) and use(inGuild) and use(myRank) == 0 and use(picked) ~= nil
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
	PlaceholderText = "Name",
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
		tabButton("Guild", 224),
		Components.Text(scope, {
			Position = UDim2.fromOffset(12, 42),
			Size = UDim2.new(1, -24, 0, 36),
			Wrapped = true,
			TextSize = 13,
			Color = Color3.fromRGB(64, 251, 64),
			Visible = isGuild,
			Text = scope:Computed(function(use)
				local g = use(guild)
				return if g then ('<font color="#FFD100"><b>&lt;%s&gt;</b></font>  %s'):format(g.Name, g.Motd or "") else "You are not in a guild. Found one for " .. Ui.money(Config.Guild.CreateCost) .. ", or wait for an invitation."
			end),
		}),
		Components.List(scope, {
			Size = scope:Computed(function(use)
				return if use(isGuild) then UDim2.new(1, -24, 1, -176) else UDim2.new(1, -24, 1, -100)
			end),
			Position = scope:Computed(function(use)
				return if use(isGuild) then UDim2.fromOffset(12, 82) else UDim2.fromOffset(12, 42)
			end),
			Rows = rows,
		}),
		smallButton("Promote", 12, isLeader, function() guildAction("promote", peek(picked)) end),
		smallButton("Demote", 118, isLeader, function() guildAction("demote", peek(picked)) end),
		smallButton("Kick", 224, canManage, function() guildAction("kick", peek(picked)); picked:set(nil) end),
		smallButton("Leave Guild", 330, scope:Computed(function(use) return use(isGuild) and use(inGuild) end), function() guildAction("leave") end),
		nameBox,
		Components.Button(scope, {
			Position = UDim2.new(0, 200, 1, -44),
			Size = UDim2.fromOffset(110, 30),
			Text = scope:Computed(function(use)
				local t = use(tab)
				return if t == "Friends" then "Add Friend" elseif t == "Ignore" then "Ignore" elseif use(inGuild) then "Invite" else "Create Guild"
			end),
			Visible = scope:Computed(function(use)
				return not use(isGuild) or not use(inGuild) or use(myRank) <= 1
			end),
			OnClick = function()
				if #nameBox.Text == 0 then
					return
				end
				local t = peek(tab)
				if t == "Guild" then
					if peek(inGuild) then
						guildAction("invite", nameBox.Text)
					else
						netSend:Fire(Opcodes.CMSG_GUILD, { Action = "create", Text = nameBox.Text })
					end
				else
					netSend:Fire(if t == "Friends" then Opcodes.CMSG_ADD_FRIEND else Opcodes.CMSG_ADD_IGNORE, { Name = nameBox.Text })
				end
				nameBox.Text = ""
			end,
		}),
		Components.Button(scope, {
			Position = UDim2.new(1, -122, 1, -44),
			Size = UDim2.fromOffset(110, 30),
			Text = "Remove",
			Visible = scope:Computed(function(use)
				return use(picked) ~= nil and not use(isGuild)
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
