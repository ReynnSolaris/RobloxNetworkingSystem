local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Fusion = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Fusion"))
local Opcodes = require(ReplicatedStorage.Shared.Opcodes)
local Ui = require(script.Parent:WaitForChild("Ui"))
local Components = require(script.Parent:WaitForChild("Components"))
local SpellUi = require(script.Parent:WaitForChild("SpellUi"))
local player = Players.LocalPlayer
local netSend = script.Parent:WaitForChild("NetSend") :: BindableEvent
local targetEvent = script.Parent:WaitForChild("Target") :: BindableEvent

-- Buffs and debuffs. Your own auras sit under the player frame, the target's
-- under the target frame, each a tile with a timer; the target's cast bar sits
-- beneath them. Auras ride the "Auras" attribute of the Player or creature Model.

local scope = Fusion.scoped(Fusion)
local Children, OnEvent, peek = Fusion.Children, Fusion.OnEvent, Fusion.peek

local TILE, GAP = 30, 4
local inWorld = Components.attribute(scope, player, "InWorld", false)
local now = scope:Value(os.clock())
RunService.Heartbeat:Connect(function()
	now:set(os.clock())
end)

-- Reads an "Auras" attribute as a list with absolute end times. The raw JSON
-- is compared so the list only changes when the server changed it.
local function reader()
	local list = scope:Value({})
	local last = nil
	return list, function(instance: Instance?)
		local raw = instance and instance:GetAttribute("Auras") or nil
		if raw == last then
			return
		end
		last = raw
		local auras = SpellUi.decode(raw, {})
		local stamp = os.clock()
		for _, aura in auras do
			aura.Ends = if (aura.Left or 0) < 0 then math.huge else stamp + (aura.Left or 0)
		end
		list:set(auras)
	end
end

local function tile(scope, aura, cancellable: boolean)
	local color = if aura.Harmful then Color3.fromRGB(200, 50, 50) else SpellUi.color({ School = aura.School })
	return scope:New "TextButton" {
		Size = UDim2.fromOffset(TILE, TILE),
		AutoButtonColor = false,
		BorderSizePixel = 0,
		BackgroundColor3 = Ui.ROW,
		Font = Enum.Font.GothamBold,
		TextSize = 11,
		TextColor3 = color,
		Text = aura.Icon or (aura.Name or "?"):sub(1, 2):upper(),
		[OnEvent "MouseEnter"] = function()
			Ui.showTip(SpellUi.auraTooltip(aura, aura.Ends - os.clock()), color)
		end,
		[OnEvent "MouseLeave"] = Ui.hideTip,
		[OnEvent "MouseButton2Click"] = function()
			if cancellable and not aura.Harmful then
				netSend:Fire(Opcodes.CMSG_CANCEL_AURA, { Id = aura.Id })
			end
		end,
		[Children] = {
			scope:New "UICorner" { CornerRadius = UDim.new(0, 3) },
			scope:New "UIStroke" { Color = color, Thickness = 1.5 },
			scope:New "TextLabel" {
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.new(0.5, 0, 1, 1),
				Size = UDim2.fromOffset(TILE + 10, 12),
				BackgroundTransparency = 1,
				Font = Enum.Font.Gotham,
				TextSize = 10,
				TextColor3 = Color3.fromRGB(220, 220, 230),
				Text = scope:Computed(function(use)
					local left = aura.Ends - use(now)
					return if left == math.huge then "" elseif left >= 3600 then ("%dh"):format(left // 3600) elseif left >= 60 then ("%dm"):format(left // 60) elseif left > 0 then ("%d"):format(math.ceil(left)) else ""
				end),
			},
			if aura.Stacks and aura.Stacks > 1 then scope:New "TextLabel" {
				AnchorPoint = Vector2.new(1, 1),
				Position = UDim2.new(1, -1, 1, 0),
				Size = UDim2.fromOffset(14, 12),
				BackgroundTransparency = 1,
				Font = Enum.Font.GothamBold,
				TextSize = 10,
				TextColor3 = Color3.new(1, 1, 1),
				Text = tostring(aura.Stacks),
			} else nil,
		},
	}
end

local function row(scope, list, position: UDim2, cancellable: boolean)
	return scope:New "Frame" {
		Position = position,
		Size = UDim2.fromOffset(TILE * 8 + GAP * 7, TILE + 14),
		BackgroundTransparency = 1,
		[Children] = {
			scope:New "UIListLayout" { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, GAP), SortOrder = Enum.SortOrder.LayoutOrder },
			scope:ForPairs(list, function(use, scope, index, aura)
				return index, tile(scope, aura, cancellable)
			end),
		},
	}
end

local mine, readMine = reader()
local targetAuras, readTarget = reader()
local targetCasting = scope:Value(nil :: string?)
local target: Instance? = nil
local targetModel: Model? = nil

targetEvent.Event:Connect(function(model)
	local other = model and Players:GetPlayerFromCharacter(model)
	target = other or model
	targetModel = if model and not other then model else nil
	readTarget(target)
end)

player:GetAttributeChangedSignal("Auras"):Connect(function()
	readMine(player)
end)
readMine(player)
task.spawn(function()
	while true do
		task.wait(0.2)
		readTarget(target)
		local casting = targetModel and targetModel:GetAttribute("Casting") or nil
		if peek(targetCasting) ~= casting then
			targetCasting:set(casting)
		end
	end
end)

scope:New "ScreenGui" {
	Name = "BuffFrame",
	ResetOnSpawn = false,
	Enabled = scope:Computed(function(use)
		return use(inWorld) == true
	end),
	Parent = player:WaitForChild("PlayerGui"),
	[Children] = {
		row(scope, mine, UDim2.fromOffset(16, 102), true),
		row(scope, targetAuras, UDim2.fromOffset(312, 90), false),
		scope:New "Frame" {
			Position = UDim2.fromOffset(312, 138),
			Size = UDim2.fromOffset(260, 16),
			BackgroundColor3 = Ui.PANEL,
			BackgroundTransparency = 0.2,
			BorderSizePixel = 0,
			Visible = scope:Computed(function(use)
				return use(targetCasting) ~= nil
			end),
			[Children] = {
				scope:New "UICorner" { CornerRadius = UDim.new(0, 3) },
				scope:New "UIStroke" { Color = Color3.fromRGB(200, 60, 60) },
				Components.Text(scope, { Size = UDim2.fromScale(1, 1), Align = Enum.TextXAlignment.Center, TextSize = 11, Font = Enum.Font.GothamBold, Text = scope:Computed(function(use)
					return "Casting " .. (use(targetCasting) or "")
				end) }),
			},
		},
	},
}
