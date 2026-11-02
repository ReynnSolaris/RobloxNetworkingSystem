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
local trainerOpen = script.Parent:WaitForChild("TrainerOpen") :: BindableEvent

-- Trainer window from a trainer's Talk prompt: the spells of your class with
-- price and level, green when you can learn them, grey when known. Pick one and
-- Train.

local scope = Fusion.scoped(Fusion)
local Children, peek = Fusion.Children, Fusion.peek

local open = scope:Value(false)
local guid = scope:Value(nil :: string?)
local title = scope:Value("Trainer")
local greeting = scope:Value("")
local spells = scope:Value({})
local picked = scope:Value(nil :: any)
local level = Components.attribute(scope, player, "CharacterLevel", 1)
local money = Components.attribute(scope, player, "Money", 0)

local rows = scope:Computed(function(use)
	local out = {}
	for _, spell in use(spells) do
		local color = if spell.Known then "#808080" elseif use(level) < (spell.ReqLevel or 1) then "#FF4040" elseif use(money) < (spell.Price or 0) then "#FFD100" else "#40FF40"
		table.insert(out, {
			Text = ('<font color="%s">%s</font>'):format(color, spell.Name or "?"),
			Right = if spell.Known then "Known" else ('%s   %s'):format(if (spell.ReqLevel or 1) > 1 then ("Level %d"):format(spell.ReqLevel) else "", Ui.money(spell.Price or 0)),
			Tooltip = SpellUi.tooltip(spell),
			TooltipBorder = SpellUi.color(spell),
			OnClick = function()
				picked:set(spell)
			end,
		})
	end
	return out
end)

Components.Panel(scope, {
	Name = "TrainerFrame",
	Size = UDim2.fromOffset(480, 400),
	Position = UDim2.new(0.5, 40, 0.5, 0),
	Enabled = open,
	Parent = player:WaitForChild("PlayerGui"),
	Title = title,
	[Children] = {
		Components.Text(scope, { Position = UDim2.fromOffset(12, 8), Size = UDim2.new(1, -24, 0, 36), Text = greeting, Wrapped = true, Color = Color3.fromRGB(230, 225, 210) }),
		Components.List(scope, { Size = UDim2.new(1, -24, 1, -100), Position = UDim2.fromOffset(12, 48), Rows = rows }),
		Components.Button(scope, {
			Size = UDim2.fromOffset(140, 32),
			Position = UDim2.new(1, -152, 1, -42),
			Text = "Train",
			Visible = scope:Computed(function(use)
				local s = use(picked)
				return s ~= nil and not s.Known
			end),
			OnClick = function()
				local s = peek(picked)
				if s then
					netSend:Fire(Opcodes.CMSG_TRAINER_BUY_SPELL, { Guid = peek(guid), Spell = s.Id })
				end
			end,
		}),
	},
})

trainerOpen.Event:Connect(function(d)
	guid:set(tostring(d.Guid))
	title:set(d.Name or "Trainer")
	greeting:set(d.Greeting or "What would you like to learn?")
	spells:set(d.Spells or {})
	local current = peek(picked)
	picked:set(nil)
	for _, spell in (d.Spells or {}) do
		if current and spell.Id == current.Id then
			picked:set(spell)
		end
	end
	open:set(true)
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if not processed and input.KeyCode == Enum.KeyCode.Escape then
		open:set(false)
	end
end)
player:GetAttributeChangedSignal("InWorld"):Connect(function()
	if player:GetAttribute("InWorld") ~= true then
		open:set(false)
	end
end)
