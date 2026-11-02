local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Fusion = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Fusion"))
local Components = require(script.Parent:WaitForChild("Components"))
local player = Players.LocalPlayer

-- Party frame on the left: one unit frame per member, leader starred. Members
-- come from the PartyMembers / PartyLeader attributes; health is read from the
-- replicated characters.

local scope = Fusion.scoped(Fusion)
local Children = Fusion.Children

local HttpService = game:GetService("HttpService")
local membersText = Components.attribute(scope, player, "PartyMembers", "")
local leader = Components.attribute(scope, player, "PartyLeader", "")
local raid = Components.attribute(scope, player, "PartyRaid", false)
local groupsJson = Components.attribute(scope, player, "PartyGroups", "{}")
local groups = scope:Computed(function(use)
	local ok, value = pcall(HttpService.JSONDecode, HttpService, use(groupsJson) or "{}")
	return if ok and typeof(value) == "table" then value else {}
end)
-- a raid lists members by subgroup in compact rows; a party keeps unit frames
local members = scope:Computed(function(use)
	local text = use(membersText)
	local list = if text ~= "" then text:split(",") else {}
	if use(raid) then
		local g = use(groups)
		table.sort(list, function(a, b)
			return (g[a] or 1) < (g[b] or 1) or ((g[a] or 1) == (g[b] or 1) and a < b)
		end)
	end
	return list
end)

-- per-member health states, kept while the member is listed
local stats: { [string]: { Health: any, Max: any, Name: any } } = {}
local function statsOf(name: string)
	stats[name] = stats[name] or { Health = scope:Value(0), Max = scope:Value(100), Name = scope:Value(name) }
	return stats[name]
end

scope:New "ScreenGui" {
	Name = "PartyFrame",
	ResetOnSpawn = false,
	Parent = player:WaitForChild("PlayerGui"),
	[Children] = scope:New "Frame" {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 12, 0.5, -60),
		Size = UDim2.fromOffset(200, 300),
		BackgroundTransparency = 1,
		[Children] = {
			scope:New "UIListLayout" { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder },
			scope:ForPairs(members, function(use, scope, index, name)
				local s = statsOf(name)
				if use(raid) then
					return index, scope:New "Frame" {
						LayoutOrder = index,
						Size = UDim2.new(1, 0, 0, 22),
						BackgroundColor3 = Color3.fromRGB(16, 16, 24),
						BackgroundTransparency = 0.2,
						BorderSizePixel = 0,
						[Children] = {
							scope:New "UICorner" { CornerRadius = UDim.new(0, 4) },
							Components.Bar(scope, { Position = UDim2.fromOffset(2, 2), Size = UDim2.new(1, -4, 1, -4), Value = s.Health, Max = s.Max, Text = false, Color = Color3.fromRGB(50, 150, 70) }),
							Components.Text(scope, { Position = UDim2.fromOffset(6, 0), Size = UDim2.new(1, -12, 1, 0), TextSize = 11, Font = Enum.Font.GothamBold, Text = scope:Computed(function(use2)
								return ("G%d  %s%s"):format(use2(groups)[name] or 1, if use2(leader) == name then "★ " else "", use2(s.Name))
							end) }),
						},
					}
				end
				return index, Components.UnitFrame(scope, {
					LayoutOrder = index,
					Size = UDim2.new(1, 0, 0, 68),
					Title = scope:Computed(function(use)
						return (if use(leader) == name then "★ " else "") .. use(s.Name)
					end),
					Info = scope:Computed(function(use)
						local other = Players:FindFirstChild(name)
						return if other then ("Level %d %s"):format(other:GetAttribute("CharacterLevel") or 1, other:GetAttribute("CharacterClass") or "") else "Offline"
					end),
					Health = s.Health,
					MaxHealth = s.Max,
					HealthColor = scope:Computed(function(use)
						return if use(s.Health) > 0 then Color3.fromRGB(60, 200, 80) else Color3.fromRGB(120, 120, 120)
					end),
				})
			end),
		},
	},
}

while true do
	task.wait(0.25)
	for _, name in Fusion.peek(members) do
		local s = statsOf(name)
		local other = Players:FindFirstChild(name)
		local humanoid = other and other.Character and other.Character:FindFirstChildOfClass("Humanoid")
		s.Health:set(if humanoid then humanoid.Health else 0)
		s.Max:set(if humanoid then humanoid.MaxHealth else 100)
		s.Name:set(if other then other:GetAttribute("CharacterName") or other.DisplayName else name)
	end
end
