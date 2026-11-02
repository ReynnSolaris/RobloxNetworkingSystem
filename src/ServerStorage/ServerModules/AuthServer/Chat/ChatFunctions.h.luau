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

local function gather(self, channel, sender: Player, targetName: string?): { Player }
	if channel.Target then
		local target = self.includes.Entities["EntityPlayer.h"]:FindByName(targetName)
		return if target then { target } else {}
	end
	if channel.Party then
		if channel.Raid and not self.includes.Social["Party.h"]:IsRaid(sender) then
			return {}
		end
		return self.includes.Social["Party.h"]:MembersOf(sender)
	end
	if channel.Guild then
		return self.includes.Social["Guild.h"]:Online(sender)
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

-- Players ignoring the sender never receive from them.
function module:Recipients(channel, sender: Player, targetName: string?): { Player }
	local Social = self.includes.Social["Social.h"]
	local out = {}
	for _, player in gather(self, channel, sender, targetName) do
		if player == sender or not Social:IsIgnoring(player, sender) then
			table.insert(out, player)
		end
	end
	return out
end

return Base(module, {
	{ Path = "Auth/Social", Imports = "Party.h|Social.h|Guild.h" },
	{ Path = "Auth/Entities", Imports = "EntityPlayer.h" },
})
