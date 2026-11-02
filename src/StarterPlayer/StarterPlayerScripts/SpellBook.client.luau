local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Fusion = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Fusion"))
local Opcodes = require(ReplicatedStorage.Shared.Opcodes)
local Ui = require(script.Parent:WaitForChild("Ui"))
local Components = require(script.Parent:WaitForChild("Components"))
local SpellUi = require(script.Parent:WaitForChild("SpellUi"))
local Settings = require(script.Parent:WaitForChild("Settings"))
local player = Players.LocalPlayer
local netSend = script.Parent:WaitForChild("NetSend") :: BindableEvent
local targetEvent = script.Parent:WaitForChild("Target") :: BindableEvent

-- Spellbook on P, Blizzlike tabs down the right: General (forms, stances,
-- passives, mounts), one tab per school of your class spells, and Skills with
-- your professions and weapon skills. Click casts, drag puts a spell on the
-- action bar, shift-click links it. The open tab is remembered.

local scope = Fusion.scoped(Fusion)
local Children, peek = Fusion.Children, Fusion.peek

local SCHOOL_NAME = { physical = "Physical", holy = "Holy", fire = "Fire", nature = "Nature", frost = "Frost", shadow = "Shadow", arcane = "Arcane" }
local SCHOOL_ORDER = { "physical", "holy", "fire", "frost", "arcane", "nature", "shadow" }

local open = scope:Value(false)
local tab = scope:Value(Settings.get("spellbook.tab", "General"))
local spellsJson = Components.attribute(scope, player, "Spells", "[]")
local skillsJson = Components.attribute(scope, player, "Skills", "[]")
local spells = scope:Computed(function(use)
	return SpellUi.decode(use(spellsJson), {})
end)

local function isGeneral(spell): boolean
	local aura = spell.Aura
	return spell.Effect == "passive" or (aura ~= nil and (aura.Group or aura.Kind == "form" or aura.Kind == "stealth" or aura.Kind == "mount"))
end

local tabs = scope:Computed(function(use)
	local seen, out = {}, { "General" }
	for _, school in SCHOOL_ORDER do
		for _, spell in use(spells) do
			if not isGeneral(spell) and spell.School == school and not seen[school] then
				seen[school] = true
				table.insert(out, SCHOOL_NAME[school])
			end
		end
	end
	table.insert(out, "Skills")
	return out
end)

local shown = scope:Computed(function(use)
	local which = use(tab)
	local out = {}
	for _, spell in use(spells) do
		local general = isGeneral(spell)
		if (which == "General" and general) or (not general and SCHOOL_NAME[spell.School or ""] == which) then
			table.insert(out, spell)
		end
	end
	table.sort(out, function(a, b)
		local pa, pb = a.Effect == "passive", b.Effect == "passive"
		if pa ~= pb then
			return pb
		end
		return (a.Name or "") < (b.Name or "")
	end)
	return out
end)

local targetGuid: string? = nil
targetEvent.Event:Connect(function(model)
	targetGuid = model and model:GetAttribute("Guid")
end)

local function spellRow(scope, spell, index)
	local state = scope:Value(spell)
	local sub = if spell.Effect == "passive" then "Passive"
		else ("%s%s"):format(if (spell.CastTime or 0) > 0 then ("%.1f sec cast"):format(spell.CastTime) else "Instant", if (spell.Cost or 0) > 0 then ("   %d mana"):format(spell.Cost) else "")
	return scope:New "Frame" {
		Size = UDim2.new(1, -6, 0, 50),
		BackgroundColor3 = Ui.ROW,
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
		LayoutOrder = index,
		[Children] = {
			scope:New "UICorner" { CornerRadius = UDim.new(0, 4) },
			SpellUi.tile(scope, {
				Spell = state,
				Position = UDim2.fromOffset(3, 3),
				Hint = if spell.Effect == "passive" then nil else '<font color="#AAAAAA">Drag to your action bar</font>',
				OnClick = function()
					if spell.Effect ~= "passive" then
						netSend:Fire(Opcodes.CMSG_CAST_SPELL, { Spell = spell.Id, Guid = targetGuid })
					end
				end,
				DragData = if spell.Effect == "passive" then nil else function()
					return { Spell = spell.Id }
				end,
			}),
			Components.Text(scope, { Position = UDim2.fromOffset(56, 6), Size = UDim2.new(1, -62, 0, 20), Text = (spell.Name or "?") .. (if spell.Rank then ('  <font color="#AAAAAA">Rank %d</font>'):format(spell.Rank) else ""), Font = Enum.Font.GothamBold, TextSize = 14, Color = SpellUi.color(spell) }),
			Components.Text(scope, { Position = UDim2.fromOffset(56, 27), Size = UDim2.new(1, -62, 0, 18), TextSize = 12, Color = Ui.DIM, Text = sub }),
		},
	}
end

local skillRows = scope:Computed(function(use)
	local out = {}
	for _, skill in SpellUi.decode(use(skillsJson), {}) do
		table.insert(out, { Text = ('%s  <font color="#AAAAAA">%s</font>'):format(skill.Name, skill.Kind or ""), Right = ("%d / %d"):format(skill.Value or 0, skill.Max or 0),
			Tooltip = ('<font size="16" color="#FFFFFF"><b>%s</b></font>\n<font color="#FFD100">%s</font>\n<font color="#AAAAAA">Open the profession window on K to craft</font>'):format(skill.Name, skill.Description or "") })
	end
	for _, spell in use(spells) do
		if spell.Effect == "passive" then
			table.insert(out, { Text = spell.Name, Right = "Known", Tooltip = SpellUi.tooltip(spell), TooltipBorder = SpellUi.color(spell) })
		end
	end
	if #out == 0 then
		table.insert(out, { Text = '<font color="#AAAAAA">No skills yet. Visit a profession or riding trainer.</font>' })
	end
	return out
end)

Components.Panel(scope, {
	Name = "SpellBook",
	Size = UDim2.fromOffset(520, 440),
	Position = UDim2.new(0.5, 200, 0.5, 0),
	Enabled = open,
	Parent = player:WaitForChild("PlayerGui"),
	Title = "Spellbook & Abilities",
	[Children] = {
		-- pages
		scope:New "ScrollingFrame" {
			Position = UDim2.fromOffset(12, 10),
			Size = UDim2.new(1, -140, 1, -20),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ScrollBarThickness = 4,
			CanvasSize = UDim2.new(),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			Visible = scope:Computed(function(use)
				return use(tab) ~= "Skills"
			end),
			[Children] = {
				scope:New "UIListLayout" { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder },
				scope:ForPairs(shown, function(use, scope, index, spell)
					return index, spellRow(scope, spell, index)
				end),
			},
		},
		scope:New "Frame" {
			Position = UDim2.fromOffset(12, 10),
			Size = UDim2.new(1, -140, 1, -20),
			BackgroundTransparency = 1,
			Visible = scope:Computed(function(use)
				return use(tab) == "Skills"
			end),
			[Children] = Components.List(scope, { Size = UDim2.fromScale(1, 1), Rows = skillRows }),
		},
		-- tabs down the right
		scope:New "Frame" {
			Position = UDim2.new(1, -120, 0, 10),
			Size = UDim2.new(0, 108, 1, -20),
			BackgroundTransparency = 1,
			[Children] = {
				scope:New "UIListLayout" { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder },
				scope:ForPairs(tabs, function(use, scope, index, name)
					return index, Components.Button(scope, {
						Size = UDim2.new(1, 0, 0, 30),
						LayoutOrder = index,
						Text = name,
						TextSize = 12,
						Active = scope:Computed(function(use2)
							return use2(tab) == name
						end),
						OnClick = function()
							tab:set(name)
							Settings.set("spellbook.tab", name)
						end,
					})
				end),
			},
		},
	},
})

UserInputService.InputBegan:Connect(function(input, processed)
	if processed or player:GetAttribute("InWorld") ~= true then
		return
	end
	if input.KeyCode == Enum.KeyCode.P then
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
