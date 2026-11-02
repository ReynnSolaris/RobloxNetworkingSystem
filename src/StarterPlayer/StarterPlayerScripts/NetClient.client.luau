local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")
local Opcodes = require(ReplicatedStorage.Shared.Opcodes)
local Config = require(ReplicatedStorage.Shared.Config)

local player = Players.LocalPlayer
local remote = ReplicatedStorage:WaitForChild("Packets") :: RemoteEvent
local modern = TextChatService.ChatVersion == Enum.ChatVersion.TextChatService
local channel = if modern then TextChatService:WaitForChild("Net") :: TextChannel else nil

local seq = 0
local function send(opcode: number, data: any)
	seq += 1
	remote:FireServer(opcode, seq, data)
end

local function display(text: string)
	if channel then
		channel:DisplaySystemMessage(text)
	else
		print(text)
	end
end

local handlers = {}
local authed = false

handlers[Opcodes.SMSG_AUTH_RESPONSE] = function(d)
	authed = true
	display(if d.Ok then "Connected as " .. d.Role else "Rejected: " .. tostring(d.Reason))
end

handlers[Opcodes.SMSG_PONG] = function(d)
	if d.Time then
		player:SetAttribute("Latency", math.round((os.clock() - d.Time) * 1000))
	end
end

handlers[Opcodes.SMSG_SPAWN] = function(d)
	player:SetAttribute("Health", d.Health)
	player:SetAttribute("MaxHealth", d.MaxHealth)
end

handlers[Opcodes.SMSG_DESPAWN] = function()
	player:SetAttribute("Health", 0)
end

handlers[Opcodes.SMSG_HEALTH_UPDATE] = function(d)
	player:SetAttribute("Health", d.Health)
	player:SetAttribute("MaxHealth", d.MaxHealth)
end

handlers[Opcodes.SMSG_MESSAGECHAT] = function(d)
	if d.Channel == "SYSTEM" then
		display(d.Text)
	elseif d.Channel == "WHISPER" then
		local mine = d.Sender == player.Name
		display(("%s %s: %s"):format(if mine then "To" else "From", if mine then d.Target else d.Sender, d.Text))
	else
		display(("[%s] %s: %s"):format(d.Channel, d.Sender, d.Text))
	end
end

handlers[Opcodes.SMSG_NOTIFICATION] = function(d)
	display("[Server] " .. d.Text)
end

remote.OnClientEvent:Connect(function(opcode, _seq, data)
	local handler = handlers[opcode]
	if handler then
		handler(data or {})
	end
end)

-- "/y text" yells, "/w Name text" whispers, "/world text" goes to everyone, anything else is SAY.
local function parse(text: string)
	local prefix, rest = text:match("^/(%w+)%s+(.*)$")
	if prefix == "y" or prefix == "yell" then
		return "YELL", rest
	elseif prefix == "world" or prefix == "g" then
		return "WORLD", rest
	elseif prefix == "w" or prefix == "whisper" then
		local target, body = rest:match("^(%S+)%s+(.*)$")
		return "WHISPER", body or "", target
	end
	return "SAY", text
end

local function chat(text: string)
	local name, body, target = parse(text)
	send(Opcodes.CMSG_MESSAGECHAT, { Channel = name, Text = body, Target = target })
end

if modern then
	local inputBar = TextChatService:FindFirstChildOfClass("ChatInputBarConfiguration")
	if inputBar then
		inputBar.TargetTextChannel = channel
	end
	TextChatService.SendingMessage:Connect(function(message)
		chat(message.Text)
	end)
else
	player.Chatted:Connect(chat)
end

-- The server opens the session after a DataStore read, so keep knocking until it answers.
while not authed do
	send(Opcodes.CMSG_AUTH_SESSION, { Build = Config.Build })
	task.wait(2)
end
while true do
	task.wait(10)
	send(Opcodes.CMSG_PING, { Time = os.clock() })
end
