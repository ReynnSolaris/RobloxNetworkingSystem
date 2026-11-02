local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Fusion = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Fusion"))
local Opcodes = require(ReplicatedStorage.Shared.Opcodes)
local Config = require(ReplicatedStorage.Shared.Config)
local Ui = require(script.Parent:WaitForChild("Ui"))
local Components = require(script.Parent:WaitForChild("Components"))
local SpellUi = require(script.Parent:WaitForChild("SpellUi"))
local Drag = require(script.Parent:WaitForChild("Drag"))
local player = Players.LocalPlayer
local netSend = script.Parent:WaitForChild("NetSend") :: BindableEvent
local targetEvent = script.Parent:WaitForChild("Target") :: BindableEvent

-- Action bar at the bottom: twelve buttons on 1-9, 0, - and =, cooldown sweeps,
-- a cast bar above it and cast errors in red. Drag spells from the spellbook
-- onto a button, between buttons, or off the bar to clear it.

local KEYS = { "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-", "=" }
local KEYCODES = { Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four, Enum.KeyCode.Five, Enum.KeyCode.Six,
	Enum.KeyCode.Seven, Enum.KeyCode.Eight, Enum.KeyCode.Nine, Enum.KeyCode.Zero, Enum.KeyCode.Minus, Enum.KeyCode.Equals }
local TILE, GAP = 44, 4

local scope = Fusion.scoped(Fusion)
local Children, peek = Fusion.Children, Fusion.peek
local function attr(name, default)
	return Components.attribute(scope, player, name, default)
end

local inWorld = attr("InWorld", false)
local spellsJson, barJson, cooldownsJson, castingJson = attr("Spells", "[]"), attr("ActionBar", "{}"), attr("Cooldowns", "{}"), attr("Casting", "")
local spells = scope:Computed(function(use)
	local byId = {}
	for _, spell in SpellUi.decode(use(spellsJson), {}) do
		byId[tostring(spell.Id)] = spell
	end
	return byId
end)
local bar = scope:Computed(function(use)
	return SpellUi.decode(use(barJson), {})
end)
local cooldowns = scope:Computed(function(use)
	return SpellUi.decode(use(cooldownsJson), {})
end)
local casting = scope:Computed(function(use)
	return SpellUi.decode(use(castingJson), nil)
end)
local castError = attr("CastError", "")
local now = scope:Value(os.clock())
RunService.Heartbeat:Connect(function()
	now:set(os.clock())
end)

local targetGuid: string? = nil
targetEvent.Event:Connect(function(model)
	targetGuid = model and model:GetAttribute("Guid")
end)

local function cast(slot: number)
	local id = peek(bar)[tostring(slot)]
	if id then
		netSend:Fire(Opcodes.CMSG_CAST_SPELL, { Spell = id, Guid = targetGuid })
	end
end

local function setButton(slot: number, id)
	netSend:Fire(Opcodes.CMSG_SET_ACTION_BUTTON, { Slot = slot, Spell = id })
end

local function slotTile(slot: number)
	local spell = scope:Computed(function(use)
		local id = use(bar)[tostring(slot)]
		return if id then use(spells)[tostring(id)] else nil
	end)
	local ends = scope:Computed(function(use)
		local s = use(spell)
		return if s then (use(cooldowns)[tostring(s.Id)] or 0) else 0
	end)
	return SpellUi.tile(scope, {
		Spell = spell,
		Position = UDim2.fromOffset((slot - 1) * (TILE + GAP), 0),
		Key = KEYS[slot],
		Ready = scope:Computed(function(use)
			local s = use(spell)
			local left = use(ends) - use(now)
			return if s and left > 0 and (s.Cooldown or 0) > 0 then left / s.Cooldown else 0
		end),
		Remaining = scope:Computed(function(use)
			return use(ends) - use(now)
		end),
		OnClick = function()
			cast(slot)
		end,
		DragData = function()
			return { Spell = peek(spell).Id, FromSlot = slot }
		end,
		OnDrop = function(payload)
			if payload.Spell then
				local current = peek(bar)[tostring(slot)]
				setButton(slot, payload.Spell)
				if payload.FromSlot and payload.FromSlot ~= slot then
					setButton(payload.FromSlot, current)
				end
			end
		end,
	})
end

Drag.onMiss(function(payload)
	if payload.FromSlot then
		setButton(payload.FromSlot, nil)
	end
end)

local tiles = {}
for slot = 1, Config.Spells.ActionButtons do
	table.insert(tiles, slotTile(slot))
end
local width = Config.Spells.ActionButtons * (TILE + GAP) - GAP

scope:New "ScreenGui" {
	Name = "ActionBar",
	ResetOnSpawn = false,
	Enabled = scope:Computed(function(use)
		return use(inWorld) == true
	end),
	Parent = player:WaitForChild("PlayerGui"),
	[Children] = {
		scope:New "Frame" {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -12),
			Size = UDim2.fromOffset(width, TILE),
			BackgroundTransparency = 1,
			[Children] = tiles,
		},
		-- cast bar
		scope:New "Frame" {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -12 - TILE - 14),
			Size = UDim2.fromOffset(300, 22),
			BackgroundColor3 = Ui.PANEL,
			BackgroundTransparency = 0.2,
			BorderSizePixel = 0,
			Visible = scope:Computed(function(use)
				return use(casting) ~= nil
			end),
			[Children] = {
				scope:New "UICorner" { CornerRadius = UDim.new(0, 4) },
				scope:New "UIStroke" { Color = Ui.BORDER },
				scope:New "Frame" {
					Size = scope:Computed(function(use)
						local c = use(casting)
						if not c then
							return UDim2.fromScale(0, 1)
						end
						local total = math.max((c.Ends or 0) - (c.Start or 0), 0.01)
						return UDim2.fromScale(math.clamp((use(now) - c.Start) / total, 0, 1), 1)
					end),
					BackgroundColor3 = Color3.fromRGB(255, 200, 60),
					BackgroundTransparency = 0.2,
					BorderSizePixel = 0,
					[Children] = scope:New "UICorner" { CornerRadius = UDim.new(0, 4) },
				},
				Components.Text(scope, {
					Size = UDim2.fromScale(1, 1),
					Align = Enum.TextXAlignment.Center,
					Font = Enum.Font.GothamBold,
					TextSize = 13,
					Text = scope:Computed(function(use)
						local c = use(casting)
						return if c then ("%s  %.1f"):format(c.Name or "", math.max(c.Ends - use(now), 0)) else ""
					end),
				}),
			},
		},
		-- cast error, fades after a moment
		Components.Text(scope, {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0.22, 0),
			Size = UDim2.fromOffset(400, 24),
			Align = Enum.TextXAlignment.Center,
			Font = Enum.Font.GothamBold,
			TextSize = 18,
			Color = Color3.fromRGB(255, 70, 70),
			Text = scope:Computed(function(use)
				local raw = use(castError)
				local text, at = raw:match("^(.-) ([%d%.]+)$")
				return if text and use(now) - tonumber(at) < 2 then text else ""
			end),
		}),
	},
}

UserInputService.InputBegan:Connect(function(input, processed)
	if processed or peek(inWorld) ~= true then
		return
	end
	local slot = table.find(KEYCODES, input.KeyCode)
	if slot and not (UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)) then
		cast(slot)
	elseif input.KeyCode == Enum.KeyCode.Escape and peek(casting) then
		netSend:Fire(Opcodes.CMSG_CANCEL_CAST, {})
	end
end)
