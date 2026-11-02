local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Fusion = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Fusion"))
local Opcodes = require(ReplicatedStorage.Shared.Opcodes)
local Config = require(ReplicatedStorage.Shared.Config)
local Ui = require(script.Parent:WaitForChild("Ui"))
local Components = require(script.Parent:WaitForChild("Components"))
local Preview = require(script.Parent:WaitForChild("Preview"))
local player = Players.LocalPlayer
local netSend = script.Parent:WaitForChild("NetSend") :: BindableEvent

-- Character select and creation. Select shows the account's characters with a
-- turning preview of the chosen one. Create picks faction and race, gender,
-- class (as the race allows), with descriptions, a preview and a random name.

local scope = Fusion.scoped(Fusion)
local Children, peek = Fusion.Children, Fusion.peek
local function attr(name, default)
	return Components.attribute(scope, player, name, default)
end

local STATUS = {
	connecting = "Connecting to realm...",
	authenticating = "Authenticating...",
	authenticated = "Retrieving character list...",
	characters = "",
	entering = "Entering world...",
	rejected = "Connection rejected.",
}

local netState = attr("NetState", "connecting")
local inWorld = attr("InWorld", false)
local charError = attr("CharError", "")
local maxCharacters = attr("MaxCharacters", Config.MaxCharacters)
local charactersJson = attr("Characters", "[]")
local characters = scope:Computed(function(use)
	local ok, list = pcall(HttpService.JSONDecode, HttpService, use(charactersJson))
	return if ok and typeof(list) == "table" then list else {}
end)
local selected = scope:Value(nil :: number?)
local creating = scope:Value(false)
local race = scope:Value("Human")
local class = scope:Value(nil :: string?)
local gender = scope:Value("Male")
local message = scope:Value("")
local ready = scope:Computed(function(use)
	local s = use(netState)
	return s == "characters" or s == "entering"
end)
local selectedChar = scope:Computed(function(use)
	local s = use(selected)
	return s and use(characters)[s] or nil
end)

local breath = scope:Value(0)
local breathing = scope:Tween(breath, TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut))
task.spawn(function()
	while true do
		breath:set(0.6)
		task.wait(0.9)
		breath:set(0)
		task.wait(0.9)
	end
end)

local function classColor(name: string?): string
	local c = Preview.class(name)
	return if c then c.Color else "#FFFFFF"
end
local function factionColor(name: string?): string
	return (Config.Factions[name or ""] or Config.Factions.Alliance).Color
end

-- random names: soft syllables for the Alliance, hard ones for the Horde
local SYLLABLES = {
	Alliance = { { "Al", "Ber", "Cal", "Dor", "El", "Fen", "Gar", "Hal", "Is", "Jor", "Kel", "Lor", "Mer", "Nor", "Or", "Ser", "Tal", "Var", "Wil", "Ys" },
		{ "an", "ric", "wyn", "dor", "en", "is", "mund", "eth", "ion", "wen", "ard", "iel" }, { "a", "ia", "ara", "wyn", "elle", "ina", "eth", "ora", "ise", "ana" } },
	Horde = { { "Gor", "Thr", "Zul", "Mok", "Dra", "Kra", "Ur", "Vol", "Rok", "Sha", "Gru", "Nar", "Mag", "Bro", "Rag", "Kag" },
		{ "gash", "ok", "jin", "ash", "mar", "thar", "uk", "zar", "gul", "tok", "nak", "grim" }, { "a", "ra", "ka", "sha", "ja", "ri", "na", "za", "li", "ma" } },
}
local function randomName(): string
	local set = SYLLABLES[Preview.race(peek(race)).Faction] or SYLLABLES.Alliance
	local tail = if peek(gender) == "Female" then set[3] else set[2]
	local name = set[1][math.random(#set[1])] .. tail[math.random(#tail)]
	if math.random() < 0.3 then
		name = set[1][math.random(#set[1])]:lower() .. name:lower()
		name = name:sub(1, 1):upper() .. name:sub(2)
	end
	return name:sub(1, 12)
end

local slots = scope:Computed(function(use)
	local out = {}
	for slot = 1, use(maxCharacters) do
		table.insert(out, slot)
	end
	return out
end)

local function skeletonRow(scope, slot: number)
	return scope:New "Frame" {
		Size = UDim2.new(1, 0, 0, 56),
		LayoutOrder = slot,
		BackgroundColor3 = Color3.fromRGB(28, 28, 36),
		BorderSizePixel = 0,
		Visible = scope:Computed(function(use)
			return not use(ready)
		end),
		[Children] = {
			scope:New "UICorner" { CornerRadius = UDim.new(0, 4) },
			scope:New "Frame" { Size = UDim2.new(0.5, 0, 0, 10), Position = UDim2.fromOffset(12, 12), BackgroundColor3 = Color3.fromRGB(60, 60, 72), BackgroundTransparency = breathing, BorderSizePixel = 0, [Children] = scope:New "UICorner" { CornerRadius = UDim.new(0, 3) } },
			scope:New "Frame" { Size = UDim2.new(0.35, 0, 0, 10), Position = UDim2.fromOffset(12, 32), BackgroundColor3 = Color3.fromRGB(60, 60, 72), BackgroundTransparency = breathing, BorderSizePixel = 0, [Children] = scope:New "UICorner" { CornerRadius = UDim.new(0, 3) } },
		},
	}
end

local function slotRow(scope, slot: number)
	local char = scope:Computed(function(use)
		return use(characters)[slot]
	end)
	return Components.Button(scope, {
		Size = UDim2.new(1, 0, 0, 56),
		LayoutOrder = slot,
		Font = Enum.Font.Gotham,
		TextSize = 18,
		Align = Enum.TextXAlignment.Left,
		Visible = ready,
		Active = scope:Computed(function(use)
			return use(selected) == slot
		end),
		Text = scope:Computed(function(use)
			local c = use(char)
			return if c then ('  <font color="%s"><b>%s</b></font>\n  <font color="#AAAAAA">Level %d <font color="%s">%s</font> %s</font>'):format(classColor(c.Class), c.Name, c.Level or 1, factionColor(c.Faction), c.Race or "Human", c.Class)
				else '  <font color="#666666">Empty slot</font>'
		end),
		OnClick = function()
			selected:set(if peek(char) then slot else nil)
		end,
	})
end

local function heading(text, y: number, size: number, color, visible)
	return Components.Text(scope, { Size = UDim2.new(1, 0, 0, size + 16), Position = UDim2.new(0, 0, 0.05, y), Text = text, Font = Enum.Font.Garamond, TextSize = size, Color = color, Align = Enum.TextXAlignment.Center, Visible = visible })
end

local function action(text, size: UDim2, position: UDim2, visible, onClick, anchor)
	return Components.Button(scope, { Size = size, Position = position, AnchorPoint = anchor, Text = text, TextSize = 16, Visible = visible, OnClick = onClick })
end

local hasSelection = scope:Computed(function(use)
	return use(selected) ~= nil and use(ready) and not use(creating)
end)
local selecting = scope:Computed(function(use)
	return not use(creating)
end)

-- creator pieces
local function raceButton(r, order: number)
	return Components.Button(scope, {
		Size = UDim2.new(1, 0, 0, 30),
		LayoutOrder = order,
		Text = r.Name,
		Color = Color3.fromHex(factionColor(r.Faction)),
		Active = scope:Computed(function(use)
			return use(race) == r.Name
		end),
		OnClick = function()
			race:set(r.Name)
			if peek(class) and not table.find(r.Classes, peek(class)) then
				class:set(nil)
			end
		end,
	})
end

local raceColumn = {}
local order = 0
for _, faction in { "Alliance", "Horde" } do
	order += 1
	table.insert(raceColumn, Components.Text(scope, { Size = UDim2.new(1, 0, 0, 26), LayoutOrder = order, Text = faction, Font = Enum.Font.Garamond, TextSize = 24, Color = Color3.fromHex(factionColor(faction)), Align = Enum.TextXAlignment.Center }))
	for _, r in Config.Races do
		if r.Faction == faction then
			order += 1
			table.insert(raceColumn, raceButton(r, order))
		end
	end
end

local classColumn = {}
for i, c in Config.Classes do
	local allowed = scope:Computed(function(use)
		return table.find(Preview.race(use(race)).Classes, c.Name) ~= nil
	end)
	table.insert(classColumn, Components.Button(scope, {
		Size = UDim2.new(1, 0, 0, 30),
		LayoutOrder = i,
		Text = c.Name,
		Color = scope:Computed(function(use)
			return if use(allowed) then Color3.fromHex(c.Color) else Color3.fromRGB(90, 90, 100)
		end),
		Active = scope:Computed(function(use)
			return use(class) == c.Name
		end),
		Tooltip = ('<font size="16" color="%s"><b>%s</b></font>\n<font color="#AAAAAA">%s</font>\n%s'):format(c.Color, c.Name, c.Role, c.Description),
		OnClick = function()
			if peek(allowed) then
				class:set(c.Name)
			end
		end,
	}))
end

local genderButtons = {}
for i, g in Config.Genders do
	table.insert(genderButtons, Components.Button(scope, {
		Size = UDim2.fromOffset(100, 28),
		LayoutOrder = i,
		Text = g,
		Active = scope:Computed(function(use)
			return use(gender) == g
		end),
		OnClick = function()
			gender:set(g)
		end,
	}))
end

local nameBox = scope:New "TextBox" {
	Size = UDim2.new(1, -110, 1, 0),
	BackgroundColor3 = Color3.fromRGB(30, 32, 44),
	BorderSizePixel = 0,
	Font = Enum.Font.Gotham,
	TextSize = 18,
	TextColor3 = Color3.new(1, 1, 1),
	PlaceholderText = "Name (2 to 12 letters)",
	PlaceholderColor3 = Color3.fromRGB(120, 120, 130),
	Text = "",
	ClearTextOnFocus = false,
	[Children] = scope:New "UICorner" { CornerRadius = UDim.new(0, 4) },
} :: TextBox

local description = scope:Computed(function(use)
	local r = Preview.race(use(race))
	local c = Preview.class(use(class))
	local text = ('<font size="18" color="%s"><b>%s</b></font>  <font color="#AAAAAA">%s</font>\n%s'):format(factionColor(r.Faction), r.Name, r.Faction, r.Description)
	if c then
		text ..= ('\n\n<font size="18" color="%s"><b>%s</b></font>  <font color="#AAAAAA">%s</font>\n%s'):format(c.Color, c.Name, c.Role, c.Description)
	end
	return text
end)

scope:New "ScreenGui" {
	Name = "CharacterSelect",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	DisplayOrder = 10,
	Enabled = scope:Computed(function(use)
		return use(inWorld) ~= true
	end),
	Parent = player:WaitForChild("PlayerGui"),
	[Children] = scope:New "Frame" {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(8, 10, 18),
		BorderSizePixel = 0,
		[Children] = {
			scope:New "UIGradient" { Color = ColorSequence.new(Color3.fromRGB(14, 18, 34), Color3.fromRGB(6, 6, 12)), Rotation = 90 },
			heading(scope:Computed(function(use)
				return if use(creating) then "Create New Character" else "Character Select"
			end), 0, 44, Ui.GOLD),
			heading("Realm: " .. Config.RealmName, 56, 20, Ui.DIM),

			-- select: preview of the chosen character and the slot list
			Preview.new(scope, {
				Size = UDim2.fromScale(0.32, 0.62),
				Position = UDim2.fromScale(0.1, 0.17),
				Visible = scope:Computed(function(use)
					return use(selecting) and use(selectedChar) ~= nil
				end),
				Race = scope:Computed(function(use)
					local c = use(selectedChar)
					return c and c.Race or "Human"
				end),
				Class = scope:Computed(function(use)
					local c = use(selectedChar)
					return c and c.Class
				end),
			}),
			Components.Text(scope, {
				Size = UDim2.fromScale(0.32, 0.08),
				Position = UDim2.fromScale(0.1, 0.79),
				Align = Enum.TextXAlignment.Center,
				Font = Enum.Font.Garamond,
				TextSize = 26,
				Visible = scope:Computed(function(use)
					return use(selecting) and use(selectedChar) ~= nil
				end),
				Text = scope:Computed(function(use)
					local c = use(selectedChar)
					return if c then ('<font color="%s">%s</font>\n<font size="16" color="#AAAAAA">Level %d %s %s %s</font>'):format(classColor(c.Class), c.Name, c.Level or 1, c.Gender or "", c.Race or "Human", c.Class) else ""
				end),
			}),
			scope:New "Frame" {
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(0.95, 0, 0.18, 0),
				Size = UDim2.fromOffset(340, 300),
				BackgroundTransparency = 1,
				Visible = selecting,
				[Children] = {
					scope:New "UIListLayout" { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder },
					scope:ForValues(slots, function(use, scope, slot)
						return { skeletonRow(scope, slot), slotRow(scope, slot) }
					end),
				},
			},
			action("Enter World", UDim2.fromOffset(220, 44), UDim2.new(0.5, -110, 0.86, 0), hasSelection, function()
				player:SetAttribute("NetState", "entering")
				netSend:Fire(Opcodes.CMSG_PLAYER_LOGIN, { Slot = peek(selected) })
			end),
			action("Create New", UDim2.fromOffset(160, 36), UDim2.new(0.95, -340, 0.72, 0), scope:Computed(function(use)
				return use(selecting) and use(ready) and #use(characters) < use(maxCharacters)
			end), function()
				nameBox.Text = ""
				class:set(nil)
				message:set("")
				creating:set(true)
			end),
			action("Delete", UDim2.fromOffset(140, 36), UDim2.new(0.95, -140, 0.72, 0), hasSelection, function()
				netSend:Fire(Opcodes.CMSG_CHAR_DELETE, { Slot = peek(selected) })
			end),

			-- create: races left, preview and name middle, classes right, text below
			scope:New "Frame" {
				Position = UDim2.fromScale(0.04, 0.17),
				Size = UDim2.fromScale(0.18, 0.6),
				BackgroundTransparency = 1,
				Visible = creating,
				[Children] = { scope:New "UIListLayout" { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, raceColumn },
			},
			Preview.new(scope, {
				Size = UDim2.fromScale(0.34, 0.5),
				Position = UDim2.fromScale(0.33, 0.15),
				Visible = creating,
				Race = race,
				Class = class,
			}),
			scope:New "Frame" {
				Position = UDim2.fromScale(0.33, 0.66),
				Size = UDim2.new(0.34, 0, 0, 28),
				BackgroundTransparency = 1,
				Visible = creating,
				[Children] = { scope:New "UIListLayout" { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, genderButtons },
			},
			scope:New "Frame" {
				Position = UDim2.fromScale(0.33, 0.72),
				Size = UDim2.new(0.34, 0, 0, 36),
				BackgroundTransparency = 1,
				Visible = creating,
				[Children] = {
					nameBox,
					Components.Button(scope, { Size = UDim2.fromOffset(100, 36), Position = UDim2.new(1, -100, 0, 0), Text = "Random", OnClick = function()
						nameBox.Text = randomName()
					end }),
				},
			},
			scope:New "Frame" {
				Position = UDim2.fromScale(0.78, 0.17),
				Size = UDim2.fromScale(0.18, 0.6),
				BackgroundTransparency = 1,
				Visible = creating,
				[Children] = { scope:New "UIListLayout" { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, classColumn },
			},
			Components.Text(scope, {
				Position = UDim2.fromScale(0.04, 0.79),
				Size = UDim2.fromScale(0.62, 0.17),
				Wrapped = true,
				VAlign = Enum.TextYAlignment.Top,
				TextSize = 14,
				Color = Color3.fromRGB(220, 215, 200),
				Visible = creating,
				Text = description,
			}),
			action("Create", UDim2.fromOffset(160, 40), UDim2.new(0.96, 0, 0.9, 0), creating, function()
				if not peek(class) then
					message:set("Pick a class.")
					return
				end
				message:set("")
				netSend:Fire(Opcodes.CMSG_CHAR_CREATE, { Name = nameBox.Text, Class = peek(class), Race = peek(race), Gender = peek(gender) })
			end, Vector2.new(1, 0)),
			action("Back", UDim2.fromOffset(120, 40), UDim2.new(0.96, -172, 0.9, 0), creating, function()
				creating:set(false)
			end, Vector2.new(1, 0)),

			Components.Text(scope, {
				Size = UDim2.new(0.6, 0, 0, 24),
				Position = UDim2.new(0.2, 0, 0.94, 0),
				Font = Enum.Font.Garamond,
				TextSize = 18,
				Align = Enum.TextXAlignment.Center,
				Color = scope:Computed(function(use)
					return if use(netState) == "rejected" or use(message) ~= "" or use(charError) ~= "" then Color3.fromRGB(230, 90, 90) else Ui.DIM
				end),
				Text = scope:Computed(function(use)
					local m = use(message)
					if m ~= "" then
						return m
					end
					local err = use(charError)
					return if err ~= "" then err else STATUS[use(netState)] or ""
				end),
			}),
		},
	},
}

scope:Observer(characters):onBind(function()
	local list = peek(characters)
	local s = peek(selected)
	if s and not list[s] then
		selected:set(nil)
	end
	if not peek(selected) and list[1] then
		selected:set(1)
	end
end)
-- a successful create returns to the list
local lastCount = #peek(characters)
scope:Observer(characters):onChange(function()
	local count = #peek(characters)
	if count > lastCount then
		creating:set(false)
		selected:set(count)
	end
	lastCount = count
end)
scope:Observer(charError):onChange(function()
	message:set("")
end)
