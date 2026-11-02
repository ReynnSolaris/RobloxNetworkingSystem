local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Fusion = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Fusion"))
local Opcodes = require(ReplicatedStorage.Shared.Opcodes)
local Components = require(script.Parent:WaitForChild("Components"))
local SpellUi = require(script.Parent:WaitForChild("SpellUi"))
local player = Players.LocalPlayer
local netSend = script.Parent:WaitForChild("NetSend") :: BindableEvent
local targetEvent = script.Parent:WaitForChild("Target") :: BindableEvent

-- Spellbook on P: every known spell as a tile with its name. Click casts, drag
-- puts it on the action bar, shift-click links it in chat.

local scope = Fusion.scoped(Fusion)
local Children, peek = Fusion.Children, Fusion.peek

local open = scope:Value(false)
local spellsJson = Components.attribute(scope, player, "Spells", "[]")
local spells = scope:Computed(function(use)
	return SpellUi.decode(use(spellsJson), {})
end)

local targetGuid: string? = nil
targetEvent.Event:Connect(function(model)
	targetGuid = model and model:GetAttribute("Guid")
end)

Components.Panel(scope, {
	Name = "SpellBook",
	Size = UDim2.fromOffset(420, 380),
	Position = UDim2.new(0.5, 200, 0.5, 0),
	Enabled = open,
	Parent = player:WaitForChild("PlayerGui"),
	Title = "Spellbook",
	[Children] = scope:New "ScrollingFrame" {
		Position = UDim2.fromOffset(12, 10),
		Size = UDim2.new(1, -24, 1, -20),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		[Children] = {
			scope:New "UIListLayout" { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder },
			scope:ForPairs(spells, function(use, scope, index, spell)
				local state = scope:Value(spell)
				return index, scope:New "Frame" {
					Size = UDim2.new(1, -6, 0, 48),
					BackgroundTransparency = 1,
					LayoutOrder = index,
					[Children] = {
						SpellUi.tile(scope, {
							Spell = state,
							Position = UDim2.fromOffset(0, 2),
							Hint = '<font color="#AAAAAA">Drag to your action bar</font>',
							OnClick = function()
								netSend:Fire(Opcodes.CMSG_CAST_SPELL, { Spell = spell.Id, Guid = targetGuid })
							end,
							DragData = function()
								return { Spell = spell.Id }
							end,
						}),
						Components.Text(scope, { Position = UDim2.fromOffset(54, 4), Size = UDim2.new(1, -60, 0, 20), Text = spell.Name or "?", Font = Enum.Font.GothamBold, TextSize = 15, Color = SpellUi.color(spell) }),
						Components.Text(scope, { Position = UDim2.fromOffset(54, 24), Size = UDim2.new(1, -60, 0, 18), TextSize = 12, Color = Color3.fromRGB(170, 170, 180),
							Text = ("%s%s"):format(if (spell.CastTime or 0) > 0 then ("%.1f sec cast"):format(spell.CastTime) else "Instant", if (spell.Cost or 0) > 0 then ("   %d mana"):format(spell.Cost) else "") }),
					},
				}
			end),
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
