local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")
local Opcodes = require(ReplicatedStorage.Shared.Opcodes)
local Config = require(ReplicatedStorage.Shared.Config)

local player = Players.LocalPlayer
local remote = ReplicatedStorage:WaitForChild("Packets") :: RemoteEvent
local modern = TextChatService.ChatVersion == Enum.ChatVersion.TextChatService
local channel = if modern then TextChatService:WaitForChild("Net", 10) :: TextChannel? else nil

local Colors = Config.Chat.Colors
local myLevel = 0

local seq = 0
local function send(opcode: number, data: any)
	seq += 1
	remote:FireServer(opcode, seq, data)
end

-- Rich text helpers. User text is escaped before it goes inside a tag.
local function esc(text: string): string
	return (text:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

local function tint(hex: string, text: string): string
	return ('<font color="%s">%s</font>'):format(hex, text)
end

local function display(text: string)
	if channel then
		channel:DisplaySystemMessage(text)
	else
		print((text:gsub("<[^>]->", "")))
	end
end

local function system(text: string)
	display(tint(Colors.SYSTEM, esc(text)))
end

-- Blizzard phrasing: "Reynn says: hi", "Reynn yells: hi", "Reynn whispers: hi", "[World] [Reynn]: hi"
local function chatLine(d): string
	local name = (if d.Gm then tint(Colors.GM, "&lt;GM&gt;") .. " " else "") .. esc(d.Sender or "?")
	local text = esc(d.Text or "")
	local color = Colors[d.Channel] or Colors.SAY
	if d.Channel == "YELL" then
		return tint(color, ("%s yells: %s"):format(name, text))
	elseif d.Channel == "WHISPER" then
		return tint(color, ("%s whispers: %s"):format(name, text))
	elseif d.Channel == "WORLD" then
		return tint(color, ("[World] [%s]: %s"):format(name, text))
	end
	return tint(color, ("%s says: %s"):format(name, text))
end

local handlers = {}
local authed = false

handlers[Opcodes.SMSG_AUTH_RESPONSE] = function(d)
	authed = true
	myLevel = d.Level or 0
	system(if d.Ok then "Connected as " .. d.Role else "Rejected: " .. tostring(d.Reason))
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
		system(d.Text or "")
	else
		display(chatLine(d))
	end
end

handlers[Opcodes.SMSG_NOTIFICATION] = function(d)
	system("[Server] " .. tostring(d.Text))
end

-- GM visibility. Staff see hidden GMs faded; players see nothing, not even a nametag.
local gmState: { [string]: { Gm: boolean, Invisible: boolean } } = {}

local function applyVisibility(character: Model, hidden: boolean)
	local fade = if not hidden then 0 elseif myLevel >= 1 then 0.6 else 1
	for _, part in character:GetDescendants() do
		if part:IsA("BasePart") or part:IsA("Decal") then
			part.LocalTransparencyModifier = fade
		end
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = if hidden and myLevel < 1
			then Enum.HumanoidDisplayDistanceType.None
			else Enum.HumanoidDisplayDistanceType.Viewer
	end
end

handlers[Opcodes.SMSG_GM_STATE] = function(d)
	gmState[d.Name] = { Gm = d.Gm == true, Invisible = d.Invisible == true }
	local other = Players:FindFirstChild(d.Name)
	if other and other.Character then
		applyVisibility(other.Character, d.Invisible == true)
	end
end

local function watch(other: Player)
	other.CharacterAdded:Connect(function(character)
		local state = gmState[other.Name]
		if state and state.Invisible then
			task.wait(0.5)
			applyVisibility(character, true)
		end
	end)
end
Players.PlayerAdded:Connect(watch)
for _, other in Players:GetPlayers() do
	watch(other)
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
	if inputBar and channel then
		inputBar.TargetTextChannel = channel
	end

	-- The chat box echoes what you typed, and that echo is your own line: the
	-- server never sends you a copy. OnIncomingMessage runs first, so it parses
	-- the raw text, restyles the echo, and leaves the raw body for SendingMessage.
	local pending = nil

	TextChatService.OnIncomingMessage = function(message)
		if not (message.TextSource and message.TextSource.UserId == player.UserId) then
			return nil
		end
		local raw = message.Text
		local name, body, target = parse(raw)
		pending = { Channel = name, Body = body, Target = target }

		local me = gmState[player.Name]
		local who = (if me and me.Gm then tint(Colors.GM, "&lt;GM&gt;") .. " " else "") .. esc(player.DisplayName)
		local color, prefix
		if raw:sub(1, 1) == "." then
			color, prefix = Colors.COMMAND, ">"
		elseif name == "WHISPER" then
			color, prefix = Colors.WHISPER, ("To %s:"):format(esc(target or "?"))
		elseif name == "YELL" then
			color, prefix = Colors.YELL, who .. " yells:"
		elseif name == "WORLD" then
			color, prefix = Colors.WORLD, ("[World] [%s]:"):format(who)
		else
			color, prefix = Colors.SAY, who .. " says:"
		end
		local props = Instance.new("TextChatMessageProperties")
		props.PrefixText = tint(color, prefix)
		props.Text = tint(color, esc(body))
		return props
	end

	TextChatService.SendingMessage:Connect(function(message)
		local p = pending
		pending = nil
		if p then
			send(Opcodes.CMSG_MESSAGECHAT, { Channel = p.Channel, Text = p.Body, Target = p.Target })
		else
			chat(message.Text)
		end
	end)
else
	player.Chatted:Connect(chat)
end

-- The server opens the session after a DataStore read, so keep knocking until it answers.
while not authed do
	send(Opcodes.CMSG_AUTH_SESSION, { Build = Config.Build })
	task.wait(0.5)
end
while true do
	task.wait(10)
	send(Opcodes.CMSG_PING, { Time = os.clock() })
end
