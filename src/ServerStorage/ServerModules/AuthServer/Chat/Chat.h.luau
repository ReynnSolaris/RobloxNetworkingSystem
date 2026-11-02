local Base = require(game:GetService("ServerStorage").ServerModules["Template.h"])
local Players = game:GetService("Players")
local TextChatService = game:GetService("TextChatService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Opcodes = require(ReplicatedStorage.Shared.Opcodes)
local Config = require(ReplicatedStorage.Shared.Config)
local module = {}

-- Chat runs over packets, not Roblox's own delivery. The "Net" TextChannel exists
-- only so the chat box has somewhere to type; ShouldDeliverCallback blocks it.

function module:System(player: Player, text: string)
	self.includes.Security["Packet.h"]:Send(player, Opcodes.SMSG_MESSAGECHAT, { Channel = "SYSTEM", Text = text })
end

function module:Start()
	local Packet = self.includes.Security["Packet.h"]
	local Registry = self.includes.Chat["ChatRegistry.h"]
	local Functions = self.includes.Chat["ChatFunctions.h"]

	if TextChatService.ChatVersion == Enum.ChatVersion.TextChatService then
		local channel = Instance.new("TextChannel")
		channel.Name = "Net"
		channel.ShouldDeliverCallback = function()
			return false
		end
		channel.Parent = TextChatService
		Players.PlayerAdded:Connect(function(player)
			channel:AddUserAsync(player.UserId)
		end)
		for _, player in Players:GetPlayers() do
			channel:AddUserAsync(player.UserId)
		end
	end

	Packet:On(Opcodes.CMSG_MESSAGECHAT, function(player, data)
		if typeof(data) ~= "table" or typeof(data.Text) ~= "string" then
			return
		end
		local text = data.Text:sub(1, Config.Chat.MaxLength)
		if #text == 0 then
			return
		end
		if text:sub(1, 1) == "." then
			return self.includes.Security["Commands.h"]:Run(player, text:sub(2))
		end

		local session = self.includes.Security["Session.h"]:Get(player)
		if session and session.MutedUntil > os.time() then
			return self:System(player, ("You are muted for another %d min."):format(math.ceil((session.MutedUntil - os.time()) / 60)))
		end

		local now = os.clock()
		if (self.information[player] or 0) + Config.Chat.Cooldown > now then
			return
		end
		self.information[player] = now

		local name = if typeof(data.Channel) == "string" then data.Channel:upper() else "SAY"
		local channel = Registry:Get(name)
		if not channel or channel.ServerOnly then
			return
		end
		local packet = {
			Channel = name,
			Sender = player.DisplayName,
			Gm = session ~= nil and session.Gm,
			Target = if channel.Target then data.Target else nil,
			Text = Functions:Filter(player, text),
		}
		local recipients = Functions:Recipients(channel, player, data.Target)
		if channel.Target and #recipients == 0 then
			return self:System(player, "No player named " .. tostring(data.Target))
		end
		if channel.Party and #recipients == 0 then
			return self:System(player, "You are not in a party.")
		end
		-- The sender already sees their own line as the chat box echo.
		for _, recipient in recipients do
			if recipient ~= player then
				Packet:Send(recipient, Opcodes.SMSG_MESSAGECHAT, packet)
			end
		end
	end)

	-- /wave and friends: text to everyone in SAY range except the sender, whose
	-- own client plays the animation and shows the echo.
	Packet:On(Opcodes.CMSG_EMOTE, function(player, data)
		local emote = typeof(data) == "table" and typeof(data.Emote) == "string" and Config.Emotes[data.Emote]
		if not emote then
			return
		end
		local packet = { Emote = data.Emote, Sender = player.DisplayName }
		for _, recipient in Functions:Recipients(Registry:Get("SAY"), player) do
			if recipient ~= player then
				Packet:Send(recipient, Opcodes.SMSG_EMOTE, packet)
			end
		end
	end)

	Packet:On(Opcodes.CMSG_TICKET, function(player, data)
		if typeof(data) == "table" and typeof(data.Text) == "string" and #data.Text > 0 then
			local text = Functions:Filter(player, data.Text:sub(1, Config.Chat.MaxLength))
			self:System(player, self.includes.Support["Tickets.h"]:Open(player, text))
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		self.information[player] = nil
	end)
end

return Base(module, {
	{ Path = "Auth/Chat", Imports = "ChatRegistry.h|ChatFunctions.h" },
	{ Path = "Auth/Security", Imports = "Packet.h|Commands.h|Session.h" },
	{ Path = "Auth/Support", Imports = "Tickets.h" },
})
