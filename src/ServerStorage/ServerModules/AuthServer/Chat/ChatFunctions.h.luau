local Base = require(game:GetService("ServerStorage").ServerModules["Template.h"])
local Players = game:GetService("Players")
local TextService = game:GetService("TextService")
local module = {}

function module:Filter(sender: Player, text: string): string
	local ok, result = pcall(function()
		return TextService:FilterStringAsync(text, sender.UserId):GetNonChatStringForBroadcastAsync()
	end)
	return if ok then result else string.rep("#", #text)
end

function module:Recipients(channel, sender: Player, targetName: string?): { Player }
	if channel.Target then
		local target = targetName and Players:FindFirstChild(targetName)
		return if target then { target } else {}
	end
	if channel.Party then
		return self.includes.Social["Party.h"]:MembersOf(sender)
	end
	if not channel.Range then
		return Players:GetPlayers()
	end
	local origin = sender.Character and sender.Character:GetPivot().Position
	if not origin then
		return { sender }
	end
	local out = {}
	for _, player in Players:GetPlayers() do
		local character = player.Character
		if character and (character:GetPivot().Position - origin).Magnitude <= channel.Range then
			table.insert(out, player)
		end
	end
	return out
end

return Base(module, {
	{ Path = "Auth/Social", Imports = "Party.h" },
})
