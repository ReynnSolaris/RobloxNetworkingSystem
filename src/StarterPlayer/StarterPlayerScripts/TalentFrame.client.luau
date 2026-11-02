local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Fusion = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Fusion"))
local Opcodes = require(ReplicatedStorage.Shared.Opcodes)
local Ui = require(script.Parent:WaitForChild("Ui"))
local Components = require(script.Parent:WaitForChild("Components"))
local SpellUi = require(script.Parent:WaitForChild("SpellUi"))
local player = Players.LocalPlayer
local netSend = script.Parent:WaitForChild("NetSend") :: BindableEvent

-- Talents on N: three tabs, five tiers each. Click a talent to spend a point;
-- greyed tiers need points in the tiers below. The "Talents" attribute carries
-- { Points, Tabs, Talents }.

local scope = Fusion.scoped(Fusion)
local Children, OnEvent, peek = Fusion.Children, Fusion.OnEvent, Fusion.peek

local open = scope:Value(false)
local tab = scope:Value(1)
local talentsJson = Components.attribute(scope, player, "Talents", "{}")
local data = scope:Computed(function(use)
	return SpellUi.decode(use(talentsJson), { Points = 0, Tabs = {}, Talents = {} })
end)

local TILE = 48

local function talentTile(scope, talent)
	local hovered = scope:Value(false)
	local maxed = talent.Rank >= talent.MaxRank
	local color = if maxed then Ui.GOLD elseif talent.Open then Color3.fromRGB(80, 220, 80) else Color3.fromRGB(90, 90, 100)
	return scope:New "TextButton" {
		Size = UDim2.fromOffset(TILE, TILE),
		Position = UDim2.new(0.5, -TILE / 2, 0, 16 + (talent.Tier - 1) * (TILE + 22)),
		AutoButtonColor = false,
		BorderSizePixel = 0,
		BackgroundColor3 = scope:Computed(function(use)
			return if use(hovered) then Ui.ROW_HOVER else Ui.ROW
		end),
		Font = Enum.Font.GothamBold,
		TextSize = 14,
		TextColor3 = color,
		Text = (talent.Name or "?"):sub(1, 2):upper(),
		[OnEvent "MouseEnter"] = function()
			hovered:set(true)
			Ui.showTip(('<font size="16" color="#FFFFFF"><b>%s</b></font>\n<font color="#FFFFFF">Rank %d/%d</font>\n<font color="#FFD100">%s</font>%s'):format(
				talent.Name, talent.Rank, talent.MaxRank, talent.Description or "",
				if not talent.Open then ('\n<font color="#FF4040">Requires %d points in this tree</font>'):format((talent.Tier - 1) * 5) elseif not maxed then '\n<font color="#AAAAAA">Click to learn</font>' else ""), color)
		end,
		[OnEvent "MouseLeave"] = function()
			hovered:set(false)
			Ui.hideTip()
		end,
		[OnEvent "Activated"] = function()
			if talent.Open and not maxed then
				netSend:Fire(Opcodes.CMSG_LEARN_TALENT, { Id = talent.Id })
			end
		end,
		[Children] = {
			scope:New "UICorner" { CornerRadius = UDim.new(0, 4) },
			scope:New "UIStroke" { Color = color, Thickness = 2 },
			scope:New "TextLabel" {
				AnchorPoint = Vector2.new(1, 1),
				Position = UDim2.new(1, -2, 1, -1),
				Size = UDim2.fromOffset(28, 14),
				BackgroundTransparency = 1,
				Font = Enum.Font.GothamBold,
				TextSize = 11,
				TextColor3 = color,
				TextXAlignment = Enum.TextXAlignment.Right,
				Text = ("%d/%d"):format(talent.Rank, talent.MaxRank),
			},
			scope:New "TextLabel" {
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.new(0.5, 0, 1, 2),
				Size = UDim2.fromOffset(150, 16),
				BackgroundTransparency = 1,
				Font = Enum.Font.Gotham,
				TextSize = 11,
				TextColor3 = Color3.fromRGB(210, 210, 220),
				Text = talent.Name or "?",
			},
		},
	}
end

local tabs = scope:Computed(function(use, scope)
	local out = {}
	for i, name in (use(data).Tabs or {}) do
		local spent = 0
		for _, t in (use(data).Talents or {}) do
			if t.Tab == i then
				spent += t.Rank
			end
		end
		table.insert(out, Components.Button(scope, {
			Size = UDim2.fromOffset(130, 28),
			Position = UDim2.fromOffset(12 + (i - 1) * 136, 8),
			Text = ("%s (%d)"):format(name, spent),
			Active = scope:Computed(function(use2)
				return use2(tab) == i
			end),
			OnClick = function()
				tab:set(i)
			end,
		}))
	end
	return out
end)

local tiles = scope:Computed(function(use, scope)
	local out = {}
	for _, talent in (use(data).Talents or {}) do
		if talent.Tab == use(tab) then
			table.insert(out, talentTile(scope, talent))
		end
	end
	return out
end)

Components.Panel(scope, {
	Name = "TalentFrame",
	Size = UDim2.fromOffset(430, 480),
	Position = UDim2.new(0.5, 220, 0.5, 0),
	Enabled = open,
	Parent = player:WaitForChild("PlayerGui"),
	Title = "Talents",
	[Children] = {
		tabs,
		scope:New "Frame" {
			Position = UDim2.fromOffset(12, 44),
			Size = UDim2.new(1, -24, 1, -84),
			BackgroundColor3 = Color3.fromRGB(20, 18, 14),
			BackgroundTransparency = 0.3,
			BorderSizePixel = 0,
			[Children] = { scope:New "UICorner" { CornerRadius = UDim.new(0, 6) }, tiles },
		},
		Components.Text(scope, { Size = UDim2.new(1, -24, 0, 24), Position = UDim2.new(0, 12, 1, -32), Color = Ui.GOLD, Font = Enum.Font.GothamBold, Align = Enum.TextXAlignment.Center, Text = scope:Computed(function(use)
			local p = use(data).Points or 0
			return if p > 0 then ("%d unspent talent point%s"):format(p, if p == 1 then "" else "s") else "No unspent talent points"
		end) }),
	},
})

UserInputService.InputBegan:Connect(function(input, processed)
	if processed or player:GetAttribute("InWorld") ~= true then
		return
	end
	if input.KeyCode == Enum.KeyCode.N then
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
