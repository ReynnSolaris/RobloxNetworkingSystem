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
local skillTrainerOpen = script.Parent:WaitForChild("SkillTrainerOpen") :: BindableEvent

-- Professions on K: your skills with their bars on the left, the picked skill's
-- recipes on the right with reagents (red when short) and a Create button.
-- The profession trainer window lists every skill to learn or rank up.

local scope = Fusion.scoped(Fusion)
local Children, peek = Fusion.Children, Fusion.peek

local DIFFICULTY = { orange = "#FF8040", yellow = "#FFFF00", green = "#40FF40", grey = "#808080" }

local open = scope:Value(false)
local picked = scope:Value(nil :: number?)
local recipe = scope:Value(nil :: any)
local skillsJson = Components.attribute(scope, player, "Skills", "[]")
local skills = scope:Computed(function(use)
	return SpellUi.decode(use(skillsJson), {})
end)
local current = scope:Computed(function(use)
	for _, skill in use(skills) do
		if skill.Id == use(picked) then
			return skill
		end
	end
	return use(skills)[1]
end)

local skillRows = scope:Computed(function(use)
	local rows = {}
	for _, skill in use(skills) do
		table.insert(rows, {
			Text = ('%s  <font color="#AAAAAA">%d / %d</font>'):format(skill.Name, skill.Value, skill.Max),
			Tooltip = ('<font size="16" color="#FFFFFF"><b>%s</b></font>\n<font color="#FFD100">%s</font>'):format(skill.Name, skill.Description or ""),
			OnClick = function()
				picked:set(skill.Id)
				recipe:set(nil)
			end,
		})
	end
	return rows
end)

local recipeRows = scope:Computed(function(use)
	local rows = {}
	local skill = use(current)
	for _, r in (skill and skill.Recipes or {}) do
		table.insert(rows, {
			Text = ('<font color="%s">%s</font>'):format(DIFFICULTY[r.Difficulty] or "#FFFFFF", r.Name),
			Tooltip = Ui.itemTooltip(r.Result),
			TooltipBorder = Ui.itemBorder(r.Result),
			Link = "[" .. (r.Result.Name or "?") .. "]",
			OnClick = function()
				recipe:set(r)
			end,
		})
	end
	return rows
end)

local detail = scope:Computed(function(use)
	local r = use(recipe)
	if not r then
		local skill = use(current)
		return if skill then ('<font size="18" color="#FFFFFF"><b>%s</b></font>\n<font color="#FFD100">%s</font>\n\nPick a recipe.'):format(skill.Name, skill.Description or "") else "You know no professions. Visit a profession trainer."
	end
	local lines = { ('<font size="18" color="%s"><b>%s</b></font>'):format(Ui.quality(r.Result.Quality), r.Name), "", '<font color="#FFD100"><b>Reagents</b></font>' }
	for _, reagent in r.Reagents do
		table.insert(lines, ('<font color="%s">%s (%d/%d)</font>'):format(if reagent.Have >= reagent.Count then "#FFFFFF" else "#FF4040", reagent.Name, reagent.Have, reagent.Count))
	end
	table.insert(lines, "")
	table.insert(lines, ('<font color="#AAAAAA">Requires %s (%d)</font>'):format(use(current) and use(current).Name or "", r.ReqSkill or 1))
	return table.concat(lines, "\n")
end)

Components.Panel(scope, {
	Name = "SkillFrame",
	Size = UDim2.fromOffset(620, 440),
	Position = UDim2.new(0.5, 0, 0.5, 0),
	Enabled = open,
	Parent = player:WaitForChild("PlayerGui"),
	Title = "Professions",
	[Children] = {
		Components.List(scope, { Size = UDim2.new(0, 190, 1, -20), Position = UDim2.fromOffset(12, 10), Rows = skillRows }),
		Components.List(scope, { Size = UDim2.new(0, 190, 1, -20), Position = UDim2.fromOffset(210, 10), Rows = recipeRows }),
		scope:New "TextLabel" {
			Position = UDim2.fromOffset(408, 10),
			Size = UDim2.new(1, -420, 1, -64),
			BackgroundColor3 = Color3.fromRGB(20, 18, 14),
			BackgroundTransparency = 0.3,
			BorderSizePixel = 0,
			Font = Enum.Font.Gotham,
			TextSize = 13,
			TextColor3 = Color3.fromRGB(230, 225, 210),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			TextWrapped = true,
			RichText = true,
			Text = detail,
			[Children] = { scope:New "UICorner" { CornerRadius = UDim.new(0, 6) }, scope:New "UIPadding" { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10), PaddingTop = UDim.new(0, 8) } },
		},
		Components.Button(scope, {
			Size = UDim2.fromOffset(96, 30),
			Position = UDim2.new(1, -220, 1, -44),
			Text = "Create",
			Visible = scope:Computed(function(use)
				return use(recipe) ~= nil
			end),
			OnClick = function()
				local r = peek(recipe)
				if r then
					netSend:Fire(Opcodes.CMSG_CRAFT, { Recipe = r.Id, Count = 1 })
				end
			end,
		}),
		Components.Button(scope, {
			Size = UDim2.fromOffset(96, 30),
			Position = UDim2.new(1, -116, 1, -44),
			Text = "Create All",
			Visible = scope:Computed(function(use)
				return use(recipe) ~= nil
			end),
			OnClick = function()
				local r = peek(recipe)
				if r then
					netSend:Fire(Opcodes.CMSG_CRAFT, { Recipe = r.Id, Count = 20 })
				end
			end,
		}),
	},
})

-- keep the picked recipe fresh as reagent counts change
scope:Observer(skills):onChange(function()
	local r = peek(recipe)
	local skill = peek(current)
	if r and skill then
		for _, fresh in skill.Recipes do
			if fresh.Id == r.Id then
				recipe:set(fresh)
			end
		end
	end
end)

-- profession trainer
local trainerOpen = scope:Value(false)
local trainerGuid = scope:Value(nil :: string?)
local trainerTitle = scope:Value("Profession Trainer")
local trainerGreeting = scope:Value("")
local trainerSkills = scope:Value({})
local money = Components.attribute(scope, player, "Money", 0)

local trainerRows = scope:Computed(function(use)
	local rows = {}
	for _, skill in use(trainerSkills) do
		local right
		if skill.Known and skill.NextRank then
			right = ("%d/%d   %s to %s"):format(skill.Value, skill.Max, Ui.money(skill.Price or 0), skill.NextRank)
		elseif skill.Known then
			right = ("%d/%d   Mastered"):format(skill.Value, skill.Max)
		else
			right = Ui.money(skill.Price or 0)
		end
		table.insert(rows, {
			Text = ('<font color="%s">%s</font>  <font color="#AAAAAA">%s</font>'):format(if skill.Known then "#80FF80" elseif use(money) < (skill.Price or 0) then "#FFD100" else "#FFFFFF", skill.Name, skill.Kind),
			Right = right,
			Tooltip = ('<font size="16" color="#FFFFFF"><b>%s</b></font>\n<font color="#FFD100">%s</font>\n<font color="#AAAAAA">%s</font>'):format(skill.Name, skill.Description or "",
				if skill.Known and skill.NextRank then "Click to train the next rank" elseif skill.Known then "Shift-click to unlearn" else "Click to learn"),
			OnClick = function()
				netSend:Fire(Opcodes.CMSG_LEARN_SKILL, { Guid = peek(trainerGuid), Skill = skill.Name,
					Action = if skill.Known and (UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)) then "unlearn" else nil })
			end,
		})
	end
	return rows
end)

Components.Panel(scope, {
	Name = "SkillTrainerFrame",
	Size = UDim2.fromOffset(500, 380),
	Position = UDim2.new(0.5, 40, 0.5, 0),
	Enabled = trainerOpen,
	Parent = player:WaitForChild("PlayerGui"),
	Title = trainerTitle,
	[Children] = {
		Components.Text(scope, { Position = UDim2.fromOffset(12, 8), Size = UDim2.new(1, -24, 0, 36), Text = trainerGreeting, Wrapped = true, Color = Color3.fromRGB(230, 225, 210) }),
		Components.List(scope, { Size = UDim2.new(1, -24, 1, -60), Position = UDim2.fromOffset(12, 48), Rows = trainerRows }),
	},
})

skillTrainerOpen.Event:Connect(function(d)
	trainerGuid:set(tostring(d.Guid))
	trainerTitle:set(d.Name or "Profession Trainer")
	trainerGreeting:set(d.Greeting or "What would you like to learn?")
	trainerSkills:set(d.Skills or {})
	trainerOpen:set(true)
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed or player:GetAttribute("InWorld") ~= true then
		return
	end
	if input.KeyCode == Enum.KeyCode.K then
		open:set(not peek(open))
	elseif input.KeyCode == Enum.KeyCode.Escape then
		open:set(false)
		trainerOpen:set(false)
	end
end)
player:GetAttributeChangedSignal("InWorld"):Connect(function()
	if player:GetAttribute("InWorld") ~= true then
		open:set(false)
		trainerOpen:set(false)
	end
end)
