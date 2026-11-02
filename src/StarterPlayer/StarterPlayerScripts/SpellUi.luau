-- Spell helpers shared by the action bar, spellbook and trainer: tooltip text
-- and the square tile with icon letters, keybind, cooldown sweep and drag.
local HttpService = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Fusion = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Fusion"))
local Ui = require(script.Parent:WaitForChild("Ui"))
local Drag = require(script.Parent:WaitForChild("Drag"))

local Children, OnEvent, peek = Fusion.Children, Fusion.OnEvent, Fusion.peek

local SpellUi = {}

SpellUi.SCHOOL = { physical = "#FFFFFF", holy = "#FFE680", fire = "#FF8000", nature = "#4DFF4D", frost = "#80FFFF", shadow = "#9482C9", arcane = "#FF80FF" }

function SpellUi.decode(json: string?, default)
	local ok, value = pcall(HttpService.JSONDecode, HttpService, json or "")
	return if ok and typeof(value) == "table" then value else default
end

function SpellUi.color(spell): Color3
	return Color3.fromHex(SpellUi.SCHOOL[spell and spell.School or "physical"] or "#FFFFFF")
end

function SpellUi.duration(seconds: number): string
	if seconds >= 3600 then
		return ("%d hour%s"):format(seconds // 3600, if seconds >= 7200 then "s" else "")
	elseif seconds >= 60 then
		return ("%d min"):format(seconds // 60)
	end
	return ("%d sec"):format(seconds)
end

-- Tooltip for an aura on a unit frame.
function SpellUi.auraTooltip(aura, left: number): string
	local lines = { ('<font size="16" color="%s"><b>%s</b></font>'):format(if aura.Harmful then "#FF5A5A" else "#FFFFFF", aura.Name or "?") }
	if aura.Description then
		table.insert(lines, ('<font color="#FFD100">%s</font>'):format(aura.Description))
	end
	table.insert(lines, ('<font color="#FFFFFF">%s remaining</font>'):format(SpellUi.duration(math.ceil(left))))
	if not aura.Harmful then
		table.insert(lines, '<font color="#AAAAAA">Right-click to cancel</font>')
	end
	return table.concat(lines, "\n")
end

function SpellUi.tooltip(spell, extra: string?): string
	local lines = { ('<font size="17" color="#FFFFFF"><b>%s</b></font>%s'):format(spell.Name or "?", if spell.Rank then ('   <font color="#AAAAAA">Rank %d</font>'):format(spell.Rank) else "") }
	local cost = if (spell.Cost or 0) > 0 then ("%d Mana"):format(spell.Cost) else nil
	local range = if (spell.Range or 0) > 0 then ("%d yd range"):format(spell.Range) else nil
	if cost or range then
		table.insert(lines, ('<font color="#FFFFFF">%s</font>%s'):format(cost or "", if cost and range then ("   " .. range) else (range or "")))
	end
	local cast = if (spell.CastTime or 0) > 0 then ("%.1f sec cast"):format(spell.CastTime) else "Instant"
	table.insert(lines, ('<font color="#FFFFFF">%s</font>%s'):format(cast, if (spell.Cooldown or 0) > 0 then ("   %d sec cooldown"):format(spell.Cooldown) else ""))
	if spell.Class then
		table.insert(lines, ('<font color="#AAAAAA">%s</font>'):format(spell.Class))
	end
	local text = spell.Description or ""
	local aura = spell.Aura
	if spell.Effect == "damage" then
		text ..= (" Deals about %d %s damage."):format(spell.Amount or 0, spell.School or "")
	elseif spell.Effect == "heal" then
		text ..= (" Heals for about %d."):format(spell.Amount or 0)
	elseif aura and aura.Kind == "periodic" then
		text ..= (" %s %d %severy %d sec for %d sec."):format(if aura.Harmful then "Deals" else "Heals", spell.Amount or 0, if aura.Harmful then (spell.School or "") .. " damage " else "", aura.Interval or 3, aura.Duration or 0)
	elseif aura and aura.Kind == "stat" then
		text ..= (" +%d %s for %s."):format(spell.Amount or 0, aura.Stat or "", SpellUi.duration(aura.Duration or 0))
	elseif aura and aura.Kind == "stun" then
		text ..= (" Lasts %d sec."):format(aura.Duration or 0)
	elseif aura and (aura.Kind == "speed" or aura.Kind == "mount") then
		text ..= (" %d%% movement speed for %s."):format(math.round(((aura.Mult or 1) - 1) * 100), SpellUi.duration(aura.Duration or 0))
	end
	table.insert(lines, ('<font color="#FFD100">%s</font>'):format(text))
	if extra then
		table.insert(lines, extra)
	end
	return table.concat(lines, "\n")
end

local function shiftHeld(): boolean
	return UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
end

-- props: Spell (state, may be nil), Size, Position, LayoutOrder, Key (string),
-- Ready (state fraction 0..1 left on cooldown), Remaining (state seconds),
-- OnClick, DragData (function -> payload), OnDrop (payload)
function SpellUi.tile(scope, props)
	local hovered = scope:Value(false)
	local button = scope:New "TextButton" {
		Size = props.Size or UDim2.fromOffset(44, 44),
		Position = props.Position,
		LayoutOrder = props.LayoutOrder,
		AutoButtonColor = false,
		BorderSizePixel = 0,
		BackgroundColor3 = scope:Computed(function(use)
			return if use(hovered) then Ui.ROW_HOVER else Ui.ROW
		end),
		Font = Enum.Font.GothamBold,
		TextSize = 16,
		TextColor3 = scope:Computed(function(use)
			local s = use(props.Spell)
			return if s then SpellUi.color(s) else Color3.fromRGB(60, 60, 70)
		end),
		Text = scope:Computed(function(use)
			local s = use(props.Spell)
			return if s then s.Icon or (s.Name or "?"):sub(1, 2):upper() else ""
		end),
		[OnEvent "MouseEnter"] = function()
			hovered:set(true)
			local s = peek(props.Spell)
			if s and not Drag.active() then
				Ui.showTip(SpellUi.tooltip(s, props.Hint), SpellUi.color(s))
			end
		end,
		[OnEvent "MouseLeave"] = function()
			hovered:set(false)
			Ui.hideTip()
		end,
		[OnEvent "MouseButton1Down"] = function()
			local s = peek(props.Spell)
			if s and shiftHeld() then
				local insert = script.Parent:FindFirstChild("ChatInsert")
				if insert then
					insert:Fire("[" .. (s.Name or "?") .. "]")
				end
			elseif s and props.DragData then
				Ui.hideTip()
				Drag.begin(props.DragData(), s.Icon or "?", SpellUi.color(s))
			end
		end,
		[OnEvent "Activated"] = function()
			if props.OnClick and peek(props.Spell) and not shiftHeld() then
				props.OnClick()
			end
		end,
		[Children] = {
			scope:New "UICorner" { CornerRadius = UDim.new(0, 4) },
			scope:New "UIStroke" {
				Thickness = 2,
				Color = scope:Computed(function(use)
					local s = use(props.Spell)
					return if s then SpellUi.color(s) else Color3.fromRGB(45, 45, 55)
				end),
			},
			if props.Key then scope:New "TextLabel" {
				Position = UDim2.fromOffset(3, 1),
				Size = UDim2.fromOffset(20, 12),
				BackgroundTransparency = 1,
				Font = Enum.Font.Gotham,
				TextSize = 10,
				TextColor3 = Color3.fromRGB(200, 200, 210),
				TextXAlignment = Enum.TextXAlignment.Left,
				Text = props.Key,
			} else nil,
			if props.Ready then scope:New "Frame" {
				AnchorPoint = Vector2.new(0, 1),
				Position = UDim2.fromScale(0, 1),
				Size = scope:Computed(function(use)
					return UDim2.fromScale(1, math.clamp(use(props.Ready), 0, 1))
				end),
				BackgroundColor3 = Color3.new(0, 0, 0),
				BackgroundTransparency = 0.45,
				BorderSizePixel = 0,
				[Children] = scope:New "UICorner" { CornerRadius = UDim.new(0, 4) },
			} else nil,
			if props.Remaining then scope:New "TextLabel" {
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				Font = Enum.Font.GothamBlack,
				TextSize = 16,
				TextColor3 = Color3.new(1, 1, 1),
				TextStrokeTransparency = 0.3,
				Text = scope:Computed(function(use)
					local left = use(props.Remaining)
					return if left > 0 then tostring(math.ceil(left)) else ""
				end),
			} else nil,
		},
	}
	if props.OnDrop then
		Drag.target(button, props.OnDrop)
	end
	return button
end

return SpellUi
