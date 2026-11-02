local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Fusion = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Fusion"))
local Opcodes = require(ReplicatedStorage.Shared.Opcodes)
local Config = require(ReplicatedStorage.Shared.Config)
local Ui = require(script.Parent:WaitForChild("Ui"))
local Components = require(script.Parent:WaitForChild("Components"))
local player = Players.LocalPlayer
local netSend = script.Parent:WaitForChild("NetSend") :: BindableEvent

-- Character select. Follows the NetState / Characters / InWorld attributes that
-- NetClient keeps; skeleton slots breathe until the list arrives.

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
local chosenClass = scope:Value(nil :: string?)
local message = scope:Value("")
local ready = scope:Computed(function(use)
	local s = use(netState)
	return s == "characters" or s == "entering"
end)

-- breathing skeleton bars
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
	for _, class in Config.Classes do
		if class.Name == name then
			return class.Color
		end
	end
	return "#FFFFFF"
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
			return if c then ('  <font color="%s"><b>%s</b></font>\n  <font color="#AAAAAA">Level %d %s</font>'):format(classColor(c.Class), c.Name, c.Level or 1, c.Class)
				else '  <font color="#666666">Empty slot</font>'
		end),
		OnClick = function()
			selected:set(if peek(char) then slot else nil)
		end,
	})
end

local function heading(text, y: number, size: number, color: Color3)
	return Components.Text(scope, { Size = UDim2.new(1, 0, 0, size + 16), Position = UDim2.new(0, 0, 0.06, y), Text = text, Font = Enum.Font.Garamond, TextSize = size, Color = color, Align = Enum.TextXAlignment.Center })
end

local function action(text, size: UDim2, position: UDim2, visible, onClick)
	return Components.Button(scope, { Size = size, Position = position, Text = text, TextSize = 16, Visible = visible, OnClick = onClick })
end

local hasSelection = scope:Computed(function(use)
	return use(selected) ~= nil and use(ready)
end)

local classButtons = {}
for _, class in Config.Classes do
	table.insert(classButtons, Components.Button(scope, {
		Text = class.Name,
		Color = Color3.fromHex(class.Color),
		Active = scope:Computed(function(use)
			return use(chosenClass) == class.Name
		end),
		OnClick = function()
			chosenClass:set(class.Name)
		end,
	}))
end

local nameBox = scope:New "TextBox" {
	Size = UDim2.new(1, -40, 0, 36),
	Position = UDim2.fromOffset(20, 56),
	BackgroundColor3 = Color3.fromRGB(30, 32, 44),
	BorderSizePixel = 0,
	Font = Enum.Font.Gotham,
	TextSize = 18,
	TextColor3 = Color3.new(1, 1, 1),
	PlaceholderText = "Name (2 to 12 letters)",
	Text = "",
	ClearTextOnFocus = false,
} :: TextBox

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
			heading("Character Select", 0, 44, Ui.GOLD),
			heading("Realm: " .. Config.RealmName, 56, 20, Ui.DIM),
			scope:New "Frame" {
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(0.95, 0, 0.18, 0),
				Size = UDim2.fromOffset(320, 300),
				BackgroundTransparency = 1,
				[Children] = {
					scope:New "UIListLayout" { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder },
					scope:ForValues(slots, function(use, scope, slot)
						return { skeletonRow(scope, slot), slotRow(scope, slot) }
					end),
				},
			},
			action("Enter World", UDim2.fromOffset(220, 44), UDim2.new(0.5, -110, 0.82, 0), hasSelection, function()
				player:SetAttribute("NetState", "entering")
				netSend:Fire(Opcodes.CMSG_PLAYER_LOGIN, { Slot = peek(selected) })
			end),
			action("Create New", UDim2.fromOffset(160, 36), UDim2.new(0.95, -320, 0.72, 0), scope:Computed(function(use)
				return use(ready) and #use(characters) < use(maxCharacters)
			end), function()
				nameBox.Text = ""
				chosenClass:set(nil)
				creating:set(true)
			end),
			action("Delete", UDim2.fromOffset(140, 36), UDim2.new(0.95, -140, 0.72, 0), hasSelection, function()
				netSend:Fire(Opcodes.CMSG_CHAR_DELETE, { Slot = peek(selected) })
			end),
			Components.Text(scope, {
				Size = UDim2.new(0.6, 0, 0, 24),
				Position = UDim2.new(0.2, 0, 0.9, 0),
				Font = Enum.Font.Garamond,
				TextSize = 18,
				Align = Enum.TextXAlignment.Center,
				Color = scope:Computed(function(use)
					return if use(netState) == "rejected" then Color3.fromRGB(230, 90, 90) else Ui.DIM
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
			scope:New "Frame" {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromOffset(420, 360),
				BackgroundColor3 = Color3.fromRGB(18, 20, 30),
				BorderSizePixel = 0,
				Visible = creating,
				[Children] = {
					scope:New "UICorner" { CornerRadius = UDim.new(0, 6) },
					Components.Text(scope, { Size = UDim2.new(1, 0, 0, 40), Position = UDim2.fromOffset(0, 8), Text = "New Character", Font = Enum.Font.Garamond, TextSize = 30, Color = Ui.GOLD, Align = Enum.TextXAlignment.Center }),
					nameBox,
					scope:New "Frame" {
						Position = UDim2.fromOffset(20, 104),
						Size = UDim2.new(1, -40, 0, 190),
						BackgroundTransparency = 1,
						[Children] = { scope:New "UIGridLayout" { CellSize = UDim2.new(0.5, -4, 0, 34), CellPadding = UDim2.fromOffset(8, 4) }, classButtons },
					},
					action("Create", UDim2.fromOffset(160, 36), UDim2.new(0.5, -170, 1, -50), nil, function()
						if not peek(chosenClass) then
							message:set("Pick a class.")
							return
						end
						message:set("")
						netSend:Fire(Opcodes.CMSG_CHAR_CREATE, { Name = nameBox.Text, Class = peek(chosenClass) })
						creating:set(false)
					end),
					action("Back", UDim2.fromOffset(160, 36), UDim2.new(0.5, 10, 1, -50), nil, function()
						creating:set(false)
					end),
				},
			},
		},
	},
}

-- keep the selection on a real character; default to the first
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
scope:Observer(charError):onChange(function()
	message:set("")
end)
