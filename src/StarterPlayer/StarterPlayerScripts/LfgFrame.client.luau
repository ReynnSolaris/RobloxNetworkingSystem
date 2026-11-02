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

-- Dungeon finder on I: pick a dungeon and a role, join the queue; the status
-- shows how many of each role wait. The server forms the group and ports it.

local scope = Fusion.scoped(Fusion)
local Children, peek = Fusion.Children, Fusion.peek

local open = scope:Value(false)
local role = scope:Value("dps")
local picked = scope:Value(nil :: number?)
local lfgJson = Components.attribute(scope, player, "Lfg", "{}")
local status = scope:Computed(function(use)
	return SpellUi.decode(use(lfgJson), {})
end)
local dungeonsJson = Components.attribute(scope, player, "LfgDungeons", "[]")
local dungeons = scope:Computed(function(use)
	return SpellUi.decode(use(dungeonsJson), {})
end)

local rows = scope:Computed(function(use)
	local out = {}
	for _, d in use(dungeons) do
		table.insert(out, {
			Text = ('<font color="%s">%s</font>'):format(if not d.Ready then "#808080" elseif d.Eligible then "#FFFFFF" else "#FF4040", d.Name),
			Right = ("Level %d-%d%s"):format(d.MinLevel or 1, d.MaxLevel or 80, if d.Ready then "" else "  (no entrance)"),
			OnClick = function()
				picked:set(d.Id)
			end,
		})
	end
	return out
end)

local function roleButton(name: string, label: string, x: number)
	return Components.Button(scope, { Size = UDim2.fromOffset(100, 28), Position = UDim2.fromOffset(x, 0), Text = label, Active = scope:Computed(function(use)
		return use(role) == name
	end), OnClick = function()
		role:set(name)
	end })
end

Components.Panel(scope, {
	Name = "LfgFrame",
	Size = UDim2.fromOffset(420, 400),
	Position = UDim2.new(0.5, -120, 0.5, 0),
	Enabled = open,
	Parent = player:WaitForChild("PlayerGui"),
	Title = "Dungeon Finder",
	[Children] = {
		Components.List(scope, { Size = UDim2.new(1, -24, 0, 200), Position = UDim2.fromOffset(12, 10), Rows = rows }),
		scope:New "Frame" {
			Position = UDim2.fromOffset(12, 220),
			Size = UDim2.new(1, -24, 0, 28),
			BackgroundTransparency = 1,
			[Children] = { roleButton("tank", "Tank", 0), roleButton("healer", "Healer", 106), roleButton("dps", "Damage", 212) },
		},
		Components.Text(scope, { Position = UDim2.fromOffset(12, 258), Size = UDim2.new(1, -24, 0, 60), Wrapped = true, TextSize = 13, Color = Ui.PARCHMENT, Text = scope:Computed(function(use)
			local s = use(status)
			if s.Status == "queued" then
				local h, n = s.Have or {}, s.Need or {}
				return ("In the queue for %s as %s.\nTanks %d/%d   Healers %d/%d   Damage %d/%d"):format(s.Dungeon or "?", s.Role or "", h.tank or 0, n.tank or 1, h.healer or 0, n.healer or 1, h.dps or 0, n.dps or 3)
			end
			local id = use(picked)
			for _, d in use(dungeons) do
				if d.Id == id then
					return ("Selected: %s"):format(d.Name)
				end
			end
			return "Pick a dungeon and a role."
		end) }),
		Components.Button(scope, { Size = UDim2.fromOffset(140, 32), Position = UDim2.new(1, -152, 1, -42), Text = scope:Computed(function(use)
			return if use(status).Status == "queued" then "Leave Queue" else "Find Group"
		end), OnClick = function()
			if peek(status).Status == "queued" then
				netSend:Fire(Opcodes.CMSG_LFG_LEAVE, {})
			elseif peek(picked) then
				netSend:Fire(Opcodes.CMSG_LFG_JOIN, { Dungeon = peek(picked), Role = peek(role) })
			end
		end }),
	},
})

UserInputService.InputBegan:Connect(function(input, processed)
	if processed or player:GetAttribute("InWorld") ~= true then
		return
	end
	if input.KeyCode == Enum.KeyCode.I then
		open:set(not peek(open))
		if peek(open) then
			netSend:Fire(Opcodes.CMSG_LFG_JOIN, { List = true })
		end
	elseif input.KeyCode == Enum.KeyCode.Escape then
		open:set(false)
	end
end)
player:GetAttributeChangedSignal("ToggleLfg"):Connect(function()
	open:set(not peek(open))
	if peek(open) then
		netSend:Fire(Opcodes.CMSG_LFG_JOIN, { List = true })
	end
end)
player:GetAttributeChangedSignal("InWorld"):Connect(function()
	if player:GetAttribute("InWorld") ~= true then
		open:set(false)
	end
end)
