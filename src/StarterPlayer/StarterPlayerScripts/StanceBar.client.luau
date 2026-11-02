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

-- Stance bar above the action bar: the class's stances, auras, aspects,
-- presences, shapeshift forms and stealth, lit while active, on Ctrl+1 to
-- Ctrl+9. Spells with an aura group or form, or the stealth kind, land here.

local scope = Fusion.scoped(Fusion)
local Children, peek = Fusion.Children, Fusion.peek

local KEYCODES = { Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four, Enum.KeyCode.Five, Enum.KeyCode.Six, Enum.KeyCode.Seven, Enum.KeyCode.Eight, Enum.KeyCode.Nine }
local TILE, GAP = 36, 4
local inWorld = Components.attribute(scope, player, "InWorld", false)
local spellsJson = Components.attribute(scope, player, "Spells", "[]")
local aurasJson = Components.attribute(scope, player, "Auras", "[]")

local stances = scope:Computed(function(use)
	local out = {}
	for _, spell in SpellUi.decode(use(spellsJson), {}) do
		local aura = spell.Aura
		if aura and (aura.Group or aura.Kind == "form" or aura.Kind == "stealth") and aura.Kind ~= "mount" then
			table.insert(out, spell)
		end
	end
	table.sort(out, function(a, b)
		return a.Id < b.Id
	end)
	return out
end)
local active = scope:Computed(function(use)
	local set = {}
	for _, aura in SpellUi.decode(use(aurasJson), {}) do
		set[tostring(aura.Id)] = true
	end
	return set
end)

local function cast(index: number)
	local spell = peek(stances)[index]
	if spell then
		netSend:Fire(Opcodes.CMSG_CAST_SPELL, { Spell = spell.Id })
	end
end

scope:New "ScreenGui" {
	Name = "StanceBar",
	ResetOnSpawn = false,
	Enabled = scope:Computed(function(use)
		return use(inWorld) == true and #use(stances) > 0
	end),
	Parent = player:WaitForChild("PlayerGui"),
	[Children] = scope:New "Frame" {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -12 - 44 - 42),
		Size = scope:Computed(function(use)
			return UDim2.fromOffset(#use(stances) * (TILE + GAP) - GAP, TILE)
		end),
		BackgroundTransparency = 1,
		[Children] = {
			scope:New "UIListLayout" { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, GAP), SortOrder = Enum.SortOrder.LayoutOrder },
			scope:ForPairs(stances, function(use, scope, index, spell)
				local state = scope:Value(spell)
				local on = scope:Computed(function(use2)
					return use2(active)[tostring(spell.Id)] == true
				end)
				return index, scope:New "Frame" {
					LayoutOrder = index,
					Size = UDim2.fromOffset(TILE, TILE),
					BackgroundTransparency = 1,
					[Children] = {
						SpellUi.tile(scope, {
							Spell = state,
							Size = UDim2.fromOffset(TILE, TILE),
							Key = "C" .. index,
							Hint = '<font color="#AAAAAA">Ctrl+' .. index .. "</font>",
							OnClick = function()
								cast(index)
							end,
						}),
						scope:New "UIStroke" {
							Thickness = 3,
							Color = Ui.GOLD,
							Transparency = scope:Computed(function(use2)
								return if use2(on) then 0 else 1
							end),
							ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
						},
					},
				}
			end),
		},
	},
}

UserInputService.InputBegan:Connect(function(input, processed)
	if processed or peek(inWorld) ~= true then
		return
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or UserInputService:IsKeyDown(Enum.KeyCode.RightControl) then
		local index = table.find(KEYCODES, input.KeyCode)
		if index then
			cast(index)
		end
	end
end)
