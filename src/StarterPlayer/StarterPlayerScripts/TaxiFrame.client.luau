local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Fusion = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Fusion"))
local Opcodes = require(ReplicatedStorage.Shared.Opcodes)
local Ui = require(script.Parent:WaitForChild("Ui"))
local Components = require(script.Parent:WaitForChild("Components"))
local player = Players.LocalPlayer
local netSend = script.Parent:WaitForChild("NetSend") :: BindableEvent
local taxiOpen = script.Parent:WaitForChild("TaxiOpen") :: BindableEvent

-- Flight master window: the destinations you know from here, with the fare.
-- Click one to fly. While flying a banner shows the destination.

local scope = Fusion.scoped(Fusion)
local Children, peek = Fusion.Children, Fusion.peek

local open = scope:Value(false)
local guid = scope:Value(nil :: string?)
local here = scope:Value("")
local nodes = scope:Value({})
local money = Components.attribute(scope, player, "Money", 0)
local flying = Components.attribute(scope, player, "Flying", nil)

local rows = scope:Computed(function(use)
	local out = {}
	for _, node in use(nodes) do
		table.insert(out, {
			Text = ('<font color="%s">%s</font>'):format(if use(money) >= (node.Cost or 0) then "#FFFFFF" else "#FF4040", node.Name),
			Right = Ui.money(node.Cost or 0),
			OnClick = function()
				netSend:Fire(Opcodes.CMSG_ACTIVATETAXI, { Guid = peek(guid), Node = node.Id })
				open:set(false)
			end,
		})
	end
	if #out == 0 then
		table.insert(out, { Text = '<font color="#AAAAAA">You know no other flight paths from here.</font>' })
	end
	return out
end)

Components.Panel(scope, {
	Name = "TaxiFrame",
	Size = UDim2.fromOffset(380, 360),
	Position = UDim2.new(0.5, 40, 0.5, 0),
	Enabled = open,
	Parent = player:WaitForChild("PlayerGui"),
	Title = scope:Computed(function(use)
		return "Flight Master, " .. use(here)
	end),
	[Children] = {
		Components.Text(scope, { Position = UDim2.fromOffset(12, 8), Size = UDim2.new(1, -24, 0, 24), Text = "Where would you like to fly?", Color = Color3.fromRGB(230, 225, 210) }),
		Components.List(scope, { Size = UDim2.new(1, -24, 1, -50), Position = UDim2.fromOffset(12, 38), Rows = rows }),
	},
})

scope:New "ScreenGui" {
	Name = "FlightBanner",
	ResetOnSpawn = false,
	Enabled = scope:Computed(function(use)
		return use(flying) ~= nil
	end),
	Parent = player:WaitForChild("PlayerGui"),
	[Children] = Components.Text(scope, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 120),
		Size = UDim2.fromOffset(500, 30),
		Align = Enum.TextXAlignment.Center,
		Font = Enum.Font.Garamond,
		TextSize = 26,
		Color = Ui.GOLD,
		Text = scope:Computed(function(use)
			return if use(flying) then "Flying to " .. tostring(use(flying)) else ""
		end),
	}),
}

taxiOpen.Event:Connect(function(d)
	guid:set(tostring(d.Guid))
	here:set(d.Here or "")
	nodes:set(d.Nodes or {})
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
