-- Fusion components for the windows: Panel (draggable, titled, closable), Button,
-- Row (list entry with optional right text, tooltip, click) and List.
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Fusion = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Fusion"))
local Ui = require(script.Parent:WaitForChild("Ui"))
local Drag = require(script.Parent:WaitForChild("Drag"))

local Children, OnEvent, peek = Fusion.Children, Fusion.OnEvent, Fusion.peek

local Components = {}

function Components.Text(scope, props)
	return scope:New "TextLabel" {
		Size = props.Size,
		Position = props.Position,
		BackgroundTransparency = 1,
		Font = props.Font or Enum.Font.Gotham,
		TextSize = props.TextSize or 14,
		TextColor3 = props.Color or Color3.new(1, 1, 1),
		TextXAlignment = props.Align or Enum.TextXAlignment.Left,
		RichText = true,
		Text = props.Text,
	}
end

function Components.Button(scope, props)
	local hovered = scope:Value(false)
	local button = scope:New "TextButton" {
		Size = props.Size,
		Position = props.Position,
		LayoutOrder = props.LayoutOrder,
		BackgroundColor3 = scope:Computed(function(use)
			return if use(hovered) then Ui.ROW_HOVER else Ui.ROW
		end),
		AutoButtonColor = false,
		BorderSizePixel = 0,
		Font = props.Font or Enum.Font.GothamBold,
		TextSize = props.TextSize or 13,
		TextColor3 = props.Color or Ui.GOLD,
		TextXAlignment = props.Align or Enum.TextXAlignment.Center,
		RichText = true,
		Text = props.Text,
		[OnEvent "MouseEnter"] = function()
			hovered:set(true)
			if props.Tooltip then
				Ui.showTip(props.Tooltip, props.TooltipBorder)
			end
		end,
		[OnEvent "MouseLeave"] = function()
			hovered:set(false)
			Ui.hideTip()
		end,
		[OnEvent "Activated"] = props.OnClick,
		[Children] = {
			scope:New "UICorner" { CornerRadius = UDim.new(0, 4) },
			scope:New "UIStroke" { Color = Ui.BORDER },
			props[Children],
		},
	}
	return button
end

-- A list entry: { Text, Right?, Tooltip?, OnClick?, LayoutOrder }
function Components.Row(scope, props)
	return Components.Button(scope, {
		Size = UDim2.new(1, -6, 0, 30),
		LayoutOrder = props.LayoutOrder,
		Font = Enum.Font.Gotham,
		Align = Enum.TextXAlignment.Left,
		Text = "  " .. props.Text,
		Tooltip = props.Tooltip,
		TooltipBorder = props.TooltipBorder,
		OnClick = props.OnClick,
		[Children] = if props.Right then Components.Text(scope, {
			Size = UDim2.new(0.5, -8, 1, 0),
			Position = UDim2.new(0.5, 0, 0, 0),
			Text = props.Right,
			TextSize = 12,
			Color = Ui.DIM,
			Align = Enum.TextXAlignment.Right,
		}) else nil,
	})
end

-- Scrolling list; Rows is a state object holding an array of row props.
function Components.List(scope, props)
	return scope:New "ScrollingFrame" {
		Size = props.Size,
		Position = props.Position,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		[Children] = {
			scope:New "UIListLayout" { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder },
			scope:ForPairs(props.Rows, function(use, scope, index, row)
				row.LayoutOrder = index
				return index, Components.Row(scope, row)
			end),
		},
	}
end

-- Window with a gradient title bar, drag, close. Enabled is a Value<boolean>.
function Components.Panel(scope, props)
	local position = scope:Value(props.Position or UDim2.fromScale(0.5, 0.5))
	local dragStart, startPos = nil, nil

	UserInputService.InputChanged:Connect(function(input)
		if dragStart and input.UserInputType == Enum.UserInputType.MouseMovement then
			local delta = input.Position - dragStart
			position:set(UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y))
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragStart = nil
		end
	end)

	local gui = scope:New "ScreenGui" {
		Name = props.Name,
		ResetOnSpawn = false,
		DisplayOrder = 20,
		Enabled = props.Enabled,
		Parent = props.Parent,
		[Children] = scope:New "Frame" {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = position,
			Size = props.Size,
			BackgroundColor3 = Ui.PANEL,
			BackgroundTransparency = 0.05,
			BorderSizePixel = 0,
			[Children] = {
				scope:New "UICorner" { CornerRadius = UDim.new(0, 8) },
				scope:New "UIStroke" { Color = Ui.BORDER },
				scope:New "Frame" {
					Name = "Bar",
					Size = UDim2.new(1, 0, 0, 36),
					BackgroundColor3 = Ui.BAR_TOP,
					BorderSizePixel = 0,
					[OnEvent "InputBegan"] = function(input)
						if input.UserInputType == Enum.UserInputType.MouseButton1 then
							dragStart, startPos = input.Position, peek(position)
						end
					end,
					[Children] = {
						scope:New "UICorner" { CornerRadius = UDim.new(0, 8) },
						scope:New "UIGradient" { Color = ColorSequence.new(Ui.BAR_TOP, Ui.BAR_BOTTOM), Rotation = 90 },
						Components.Text(scope, { Size = UDim2.new(1, -60, 1, 0), Position = UDim2.fromOffset(14, 0), Text = props.Title, Font = Enum.Font.Garamond, TextSize = 24, Color = Ui.GOLD }),
						Components.Button(scope, { Size = UDim2.fromOffset(24, 24), Position = UDim2.new(1, -30, 0, 6), Text = "X", OnClick = function()
							props.Enabled:set(false)
						end }),
					},
				},
				scope:New "Frame" {
					Name = "Body",
					Position = UDim2.fromOffset(0, 36),
					Size = UDim2.new(1, 0, 1, -36),
					BackgroundTransparency = 1,
					[Children] = props[Children],
				},
			},
		},
	}
	if props.OnDrop then
		local body = gui:FindFirstChild("Body", true)
		if body then
			Drag.target(body, props.OnDrop)
		end
	end
	return gui
end
-- A Value kept in step with a player attribute.
function Components.attribute(scope, player: Player, name: string, default)
	local value = scope:Value(player:GetAttribute(name) or default)
	player:GetAttributeChangedSignal(name):Connect(function()
		value:set(player:GetAttribute(name) or default)
	end)
	return value
end

return Components
