local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Fusion = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Fusion"))
local Opcodes = require(ReplicatedStorage.Shared.Opcodes)
local Config = require(ReplicatedStorage.Shared.Config)
local Ui = require(script.Parent:WaitForChild("Ui"))
local Components = require(script.Parent:WaitForChild("Components"))
local Drag = require(script.Parent:WaitForChild("Drag"))
local player = Players.LocalPlayer
local netSend = script.Parent:WaitForChild("NetSend") :: BindableEvent
local mailOpen = script.Parent:WaitForChild("MailOpen") :: BindableEvent

-- Mailbox window: Inbox lists letters (bold until read) with the body, money and
-- item attachments to take; Send Mail takes a name, subject, body, up to four
-- items dragged from the bag and money, for Config.Mail.Postage.

local scope = Fusion.scoped(Fusion)
local Children, OnEvent, peek = Fusion.Children, Fusion.OnEvent, Fusion.peek

local open = scope:Value(false)
local guid = scope:Value(nil :: string?)
local tab = scope:Value("Inbox")
local picked = scope:Value(nil :: string?)
local attachments = scope:Value({} :: { any })
local mailJson = Components.attribute(scope, player, "Mail", "[]")
local mails = scope:Computed(function(use)
	local ok, list = pcall(HttpService.JSONDecode, HttpService, use(mailJson))
	return if ok and typeof(list) == "table" then list else {}
end)
local current = scope:Computed(function(use)
	for _, mail in use(mails) do
		if mail.Id == use(picked) then
			return mail
		end
	end
	return nil
end)

local function abbreviation(name: string): string
	local letters = {}
	for word in name:gmatch("%S+") do
		table.insert(letters, word:sub(1, 1):upper())
	end
	return table.concat(letters):sub(1, 3)
end

local rows = scope:Computed(function(use)
	local out = {}
	for _, mail in use(mails) do
		local marks = (if (mail.Money or 0) > 0 then ' <font color="#FFD700">$</font>' else "") .. (if mail.Items and #mail.Items > 0 then ' <font color="#1EFF00">+</font>' else "")
		table.insert(out, {
			Text = (if mail.Read then "" else "<b>") .. (mail.Subject or "(no subject)") .. (if mail.Read then "" else "</b>") .. marks,
			Right = mail.Sender or "?",
			OnClick = function()
				picked:set(mail.Id)
				if not mail.Read then
					netSend:Fire(Opcodes.CMSG_MAIL_MARK_AS_READ, { Id = mail.Id })
				end
			end,
		})
	end
	return out
end)

local function box(props)
	return scope:New "TextBox" {
		Position = props.Position,
		Size = props.Size,
		BackgroundColor3 = Color3.fromRGB(20, 18, 14),
		BackgroundTransparency = 0.2,
		BorderSizePixel = 0,
		Font = Enum.Font.Gotham,
		TextSize = 14,
		TextColor3 = Color3.new(1, 1, 1),
		PlaceholderText = props.Placeholder,
		PlaceholderColor3 = Color3.fromRGB(120, 120, 130),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = if props.Multiline then Enum.TextYAlignment.Top else Enum.TextYAlignment.Center,
		TextWrapped = props.Multiline == true,
		MultiLine = props.Multiline == true,
		ClearTextOnFocus = false,
		Text = "",
		[Children] = { scope:New "UICorner" { CornerRadius = UDim.new(0, 4) }, scope:New "UIPadding" { PaddingLeft = UDim.new(0, 8), PaddingTop = UDim.new(0, 4) } },
	} :: TextBox
end

local toBox = box({ Position = UDim2.fromOffset(12, 10), Size = UDim2.new(0.5, -18, 0, 30), Placeholder = "To" })
local subjectBox = box({ Position = UDim2.new(0.5, 6, 0, 10), Size = UDim2.new(0.5, -18, 0, 30), Placeholder = "Subject" })
local bodyBox = box({ Position = UDim2.fromOffset(12, 48), Size = UDim2.new(1, -24, 0, 150), Placeholder = "Write your letter...", Multiline = true })
local moneyBox = box({ Position = UDim2.fromOffset(12, 268), Size = UDim2.fromOffset(160, 30), Placeholder = "Money (copper)" })

local function attachmentTile(index: number)
	local item = scope:Computed(function(use)
		return use(attachments)[index]
	end)
	local button = scope:New "TextButton" {
		Position = UDim2.fromOffset(12 + (index - 1) * 50, 210),
		Size = UDim2.fromOffset(44, 44),
		AutoButtonColor = false,
		BorderSizePixel = 0,
		BackgroundColor3 = Ui.ROW,
		Font = Enum.Font.GothamBold,
		TextSize = 16,
		TextColor3 = scope:Computed(function(use)
			local s = use(item)
			return if s then Color3.fromHex(Ui.quality(s.Item.Quality)) else Color3.fromRGB(60, 60, 70)
		end),
		Text = scope:Computed(function(use)
			local s = use(item)
			return if s then abbreviation(s.Item.Name or "?") else ""
		end),
		[OnEvent "MouseEnter"] = function()
			local s = peek(item)
			if s then
				Ui.showTip(Ui.itemTooltip(s.Item) .. '\n<font color="#AAAAAA">Click to put back</font>', Ui.itemBorder(s.Item))
			end
		end,
		[OnEvent "MouseLeave"] = Ui.hideTip,
		[OnEvent "Activated"] = function()
			local list = table.clone(peek(attachments))
			table.remove(list, index)
			attachments:set(list)
		end,
		[Children] = { scope:New "UICorner" { CornerRadius = UDim.new(0, 4) }, scope:New "UIStroke" { Color = Color3.fromRGB(45, 45, 55), Thickness = 2 } },
	}
	Drag.target(button, function(payload)
		if payload.Bag and payload.Item then
			local list = table.clone(peek(attachments))
			for _, a in list do
				if a.Bag == payload.Bag then
					return
				end
			end
			if #list < Config.Mail.Attachments then
				table.insert(list, payload)
				attachments:set(list)
			end
		end
	end)
	return button
end

local attachmentTiles = {}
for i = 1, Config.Mail.Attachments do
	table.insert(attachmentTiles, attachmentTile(i))
end

local function itemTile(scope, mail, index, stack)
	return scope:New "TextButton" {
		Position = UDim2.fromOffset((index - 1) * 50, 0),
		Size = UDim2.fromOffset(44, 44),
		AutoButtonColor = false,
		BorderSizePixel = 0,
		BackgroundColor3 = Ui.ROW,
		Font = Enum.Font.GothamBold,
		TextSize = 16,
		TextColor3 = Color3.fromHex(Ui.quality(stack.Quality)),
		Text = abbreviation(stack.Name or "?"),
		[OnEvent "MouseEnter"] = function()
			Ui.showTip(Ui.itemTooltip(stack) .. '\n<font color="#AAAAAA">Click to take</font>', Ui.itemBorder(stack))
		end,
		[OnEvent "MouseLeave"] = Ui.hideTip,
		[OnEvent "Activated"] = function()
			Ui.hideTip()
			netSend:Fire(Opcodes.CMSG_MAIL_TAKE_ITEM, { Id = mail.Id, Index = index, Guid = peek(guid) })
		end,
		[Children] = {
			scope:New "UICorner" { CornerRadius = UDim.new(0, 4) },
			scope:New "UIStroke" { Color = Color3.fromHex(Ui.quality(stack.Quality)), Thickness = 2 },
			scope:New "TextLabel" { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -3, 1, -1), Size = UDim2.fromOffset(24, 14), BackgroundTransparency = 1, Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = Color3.new(1, 1, 1), TextXAlignment = Enum.TextXAlignment.Right, Text = if (stack.Count or 1) > 1 then tostring(stack.Count) else "" },
		},
	}
end

local function tabButton(name: string, x: number)
	return Components.Button(scope, {
		Size = UDim2.fromOffset(110, 26),
		Position = UDim2.fromOffset(x, 8),
		Text = name,
		Active = scope:Computed(function(use)
			return use(tab) == name
		end),
		OnClick = function()
			tab:set(name)
		end,
	})
end

local isInbox = scope:Computed(function(use)
	return use(tab) == "Inbox"
end)
local isSend = scope:Computed(function(use)
	return use(tab) == "Send Mail"
end)

Components.Panel(scope, {
	Name = "MailFrame",
	Size = UDim2.fromOffset(600, 440),
	Position = UDim2.new(0.5, 0, 0.5, 0),
	Enabled = open,
	Parent = player:WaitForChild("PlayerGui"),
	Title = "Mailbox",
	[Children] = {
		tabButton("Inbox", 12),
		tabButton("Send Mail", 128),
		-- inbox
		scope:New "Frame" {
			Position = UDim2.fromOffset(0, 40),
			Size = UDim2.new(1, 0, 1, -40),
			BackgroundTransparency = 1,
			Visible = isInbox,
			[Children] = {
				Components.List(scope, { Size = UDim2.new(0, 250, 1, -20), Position = UDim2.fromOffset(12, 4), Rows = rows }),
				scope:New "Frame" {
					Position = UDim2.fromOffset(274, 4),
					Size = UDim2.new(1, -286, 1, -20),
					BackgroundColor3 = Color3.fromRGB(20, 18, 14),
					BackgroundTransparency = 0.3,
					BorderSizePixel = 0,
					Visible = scope:Computed(function(use)
						return use(current) ~= nil
					end),
					[Children] = {
						scope:New "UICorner" { CornerRadius = UDim.new(0, 6) },
						Components.Text(scope, {
							Position = UDim2.fromOffset(10, 8),
							Size = UDim2.new(1, -20, 1, -120),
							Wrapped = true,
							VAlign = Enum.TextYAlignment.Top,
							Color = Color3.fromRGB(230, 225, 210),
							Text = scope:Computed(function(use)
								local m = use(current)
								return if m then ('<font size="18" color="%s"><b>%s</b></font>\n<font color="#AAAAAA">From %s, %s</font>\n\n%s'):format("#" .. Ui.GOLD:ToHex(), m.Subject or "", m.Sender or "?", os.date("%Y-%m-%d %H:%M", m.Sent or 0), m.Body or "") else ""
							end),
						}),
						scope:New "Frame" {
							Position = UDim2.new(0, 10, 1, -104),
							Size = UDim2.new(1, -20, 0, 44),
							BackgroundTransparency = 1,
							[Children] = scope:ForPairs(scope:Computed(function(use)
								local m = use(current)
								return if m then (m.Items or {}) else {}
							end), function(use, scope, index, stack)
								return index, itemTile(scope, peek(current), index, stack)
							end),
						},
						Components.Button(scope, {
							Position = UDim2.new(0, 10, 1, -50),
							Size = UDim2.fromOffset(150, 30),
							Visible = scope:Computed(function(use)
								local m = use(current)
								return m ~= nil and (m.Money or 0) > 0
							end),
							Text = scope:Computed(function(use)
								local m = use(current)
								return "Take " .. Ui.money(m and m.Money or 0)
							end),
							OnClick = function()
								local m = peek(current)
								if m then
									netSend:Fire(Opcodes.CMSG_MAIL_TAKE_MONEY, { Id = m.Id, Guid = peek(guid) })
								end
							end,
						}),
						Components.Button(scope, {
							Position = UDim2.new(1, -110, 1, -50),
							Size = UDim2.fromOffset(100, 30),
							Text = "Delete",
							OnClick = function()
								local m = peek(current)
								if m then
									netSend:Fire(Opcodes.CMSG_MAIL_DELETE, { Id = m.Id, Guid = peek(guid) })
									picked:set(nil)
								end
							end,
						}),
					},
				},
			},
		},
		-- send
		scope:New "Frame" {
			Position = UDim2.fromOffset(0, 40),
			Size = UDim2.new(1, 0, 1, -40),
			BackgroundTransparency = 1,
			Visible = isSend,
			[Children] = {
				toBox,
				subjectBox,
				bodyBox,
				attachmentTiles,
				Components.Text(scope, { Position = UDim2.fromOffset(12 + Config.Mail.Attachments * 50 + 6, 222), Size = UDim2.fromOffset(200, 20), TextSize = 12, Color = Ui.DIM, Text = "Drag items from your bag" }),
				moneyBox,
				Components.Text(scope, { Position = UDim2.fromOffset(184, 274), Size = UDim2.fromOffset(200, 20), TextSize = 12, Color = Ui.DIM, Text = "Postage: " .. Ui.money(Config.Mail.Postage) }),
				Components.Button(scope, {
					Position = UDim2.new(1, -132, 0, 268),
					Size = UDim2.fromOffset(120, 32),
					Text = "Send",
					OnClick = function()
						local slots = {}
						for _, a in peek(attachments) do
							table.insert(slots, a.Bag)
						end
						netSend:Fire(Opcodes.CMSG_SEND_MAIL, { Guid = peek(guid), To = toBox.Text, Subject = subjectBox.Text, Body = bodyBox.Text, Money = tonumber(moneyBox.Text) or 0, Items = slots })
					end,
				}),
			},
		},
	},
})

mailOpen.Event:Connect(function(id)
	guid:set(tostring(id))
	if not peek(open) then
		tab:set("Inbox")
		picked:set(nil)
	end
	open:set(true)
end)

-- a sent letter clears the form
player:GetAttributeChangedSignal("MailSent"):Connect(function()
	if player:GetAttribute("MailSent") then
		toBox.Text, subjectBox.Text, bodyBox.Text, moneyBox.Text = "", "", "", ""
		attachments:set({})
		tab:set("Inbox")
	end
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
