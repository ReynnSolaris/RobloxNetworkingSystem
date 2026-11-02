local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local TextChatService = game:GetService("TextChatService")
local Opcodes = require(ReplicatedStorage.Shared.Opcodes)
local Config = require(ReplicatedStorage.Shared.Config)

local player = Players.LocalPlayer
local remote = ReplicatedStorage:WaitForChild("Packets") :: RemoteEvent
local modern = TextChatService.ChatVersion == Enum.ChatVersion.TextChatService
local channel = if modern then TextChatService:WaitForChild("Net", 10) :: TextChannel? else nil

local Colors = Config.Chat.Colors
local myLevel = 0

-- Where the client is in the login sequence; CharacterSelect draws it.
-- connecting, authenticating, authenticated, characters, entering, world, rejected
local function setState(state: string)
	player:SetAttribute("NetState", state)
end
setState("connecting")

local seq = 0
local function send(opcode: number, data: any)
	seq += 1
	remote:FireServer(opcode, seq, data)
end

-- Other local scripts (CharacterSelect) send through here so the sequence stays single.
local netSend = Instance.new("BindableEvent")
netSend.Name = "NetSend"
netSend.Event:Connect(send)
netSend.Parent = script.Parent

local classColor: { [string]: string } = {}
for _, class in Config.Classes do
	classColor[class.Name] = class.Color
end

-- Rich text helpers. User text is escaped before it goes inside a tag.
local function esc(text: string): string
	return (text:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

local function tint(hex: string, text: string): string
	return ('<font color="%s">%s</font>'):format(hex, text)
end

-- Lines go to ChatFrame (tabs: General, Whispers, Log) through this event.
local chatLine = Instance.new("BindableEvent")
chatLine.Name = "ChatLine"
chatLine.Parent = script.Parent

local function display(text: string, tab: string?)
	chatLine:Fire(tab or "General", text)
	if not channel then
		print((text:gsub("<[^>]->", "")))
	end
end

local function system(text: string)
	display(tint(Colors.SYSTEM, esc(text)))
end

-- Notifications land in General and the Log.
local function notice(text: string)
	display(text, "General")
	display(text, "Log")
end

local function qualityName(name: string, quality: number): string
	return tint(Config.Quality[quality] or Config.Quality[1], "[" .. esc(name) .. "]")
end

-- Blizzard phrasing: "Reynn says: hi", "Reynn yells: hi", "Reynn whispers: hi", "[World] [Reynn]: hi"
local function formatChat(d): string
	local sender = esc(d.Sender or "?")
	if d.Class and classColor[d.Class] then
		sender = tint(classColor[d.Class], sender)
	end
	local name = (if d.Gm then tint(Colors.GM, "&lt;GM&gt;") .. " " else "") .. sender
	local text = esc(d.Text or "")
	local color = Colors[d.Channel] or Colors.SAY
	if d.Channel == "YELL" then
		return tint(color, ("%s yells: %s"):format(name, text))
	elseif d.Channel == "WHISPER" then
		return tint(color, ("%s whispers: %s"):format(name, text))
	elseif d.Channel == "WORLD" then
		return tint(color, ("[World] [%s]: %s"):format(name, text))
	elseif d.Channel == "PARTY" then
		return tint(color, ("[Party] [%s]: %s"):format(name, text))
	end
	return tint(color, ("%s says: %s"):format(name, text))
end

local handlers = {}
local authed = false

handlers[Opcodes.SMSG_AUTH_RESPONSE] = function(d)
	authed = true
	myLevel = d.Level or 0
	system(if d.Ok then "Connected as " .. d.Role else "Rejected: " .. tostring(d.Reason))
	if d.Ok then
		setState("authenticated")
		send(Opcodes.CMSG_CHAR_ENUM, {})
	else
		setState("rejected")
	end
end

-- Character select talks through attributes: Characters (JSON list), InWorld.
handlers[Opcodes.SMSG_CHAR_ENUM] = function(d)
	player:SetAttribute("Characters", HttpService:JSONEncode(d.Characters or {}))
	player:SetAttribute("MaxCharacters", d.Max or Config.MaxCharacters)
	player:SetAttribute("InWorld", false)
	setState("characters")
end

handlers[Opcodes.SMSG_CHAR_RESULT] = function(d)
	if not d.Ok then
		player:SetAttribute("CharError", tostring(d.Reason))
		system(tostring(d.Reason))
	end
end

handlers[Opcodes.SMSG_PONG] = function(d)
	if d.Time then
		player:SetAttribute("Latency", math.round((os.clock() - d.Time) * 1000))
	end
end

handlers[Opcodes.SMSG_SPAWN] = function(d)
	player:SetAttribute("Health", d.Health)
	player:SetAttribute("MaxHealth", d.MaxHealth)
	player:SetAttribute("InWorld", true)
	setState("world")
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
		display(formatChat(d), if d.Channel == "WHISPER" then "Whispers" else "General")
	end
end

handlers[Opcodes.SMSG_NOTIFICATION] = function(d)
	notice(tint(Colors.SYSTEM, "[Server] " .. esc(tostring(d.Text))))
end

handlers[Opcodes.SMSG_XP_GAIN] = function(d)
	local text = ("You gain %d experience."):format(d.Amount or 0)
	if d.Reason then
		text = ("%s: %d experience gained."):format(d.Reason, d.Amount or 0)
	end
	notice(tint(Colors.XP, esc(text)))
end

handlers[Opcodes.SMSG_LEVELUP] = function(d)
	notice(tint(Colors.SYSTEM, ("You have reached level %d!"):format(d.Level or 1)))
	player:SetAttribute("LevelUp", d.Level)
end

handlers[Opcodes.SMSG_ITEM_PUSH] = function(d)
	local count = if (d.Count or 1) > 1 then "x" .. d.Count else ""
	notice(tint(Colors.LOOT, "You receive item: ") .. qualityName(d.Name or "?", d.Quality or 1) .. tint(Colors.LOOT, count .. "."))
end

-- Copper to "1g 23s 45c".
local function money(copper: number): string
	local g, s_, c = copper // 10000, (copper % 10000) // 100, copper % 100
	local parts = {}
	if g > 0 then table.insert(parts, g .. "g") end
	if s_ > 0 then table.insert(parts, s_ .. "s") end
	if c > 0 or #parts == 0 then table.insert(parts, c .. "c") end
	return table.concat(parts, " ")
end

handlers[Opcodes.SMSG_MONEY] = function(d)
	local amount = d.Amount or 0
	notice(tint(Colors.MONEY, if amount >= 0 then "You loot " .. money(amount) .. "." else "You lose " .. money(-amount) .. "."))
end

handlers[Opcodes.SMSG_COMBAT_LOG] = function(d)
	display(tint(d.Color or Colors.HIT, esc(tostring(d.Text))), "Log")
end

handlers[Opcodes.SMSG_INVENTORY] = function(d)
	local items = d.Items or {}
	system(("Inventory, %d stack(s), %s:"):format(#items, money(d.Money or 0)))
	for _, item in items do
		display("  " .. qualityName(item.Name, item.Quality) .. tint(Colors.SAY, " x" .. tostring(item.Count)))
	end
end

-- Zone changes land on attributes; ZoneBanner draws them.
handlers[Opcodes.SMSG_ZONE_UPDATE] = function(d)
	player:SetAttribute("Zone", d.Name)
	player:SetAttribute("ZoneKind", if d.Name == nil then nil elseif d.Safe then "Sanctuary" elseif d.Pvp then "Contested Territory" else "Friendly Territory")
end

handlers[Opcodes.SMSG_EMOTE] = function(d)
	local emote = Config.Emotes[d.Emote]
	if emote then
		display(tint(Colors.EMOTE, emote.Text:format(esc(d.Sender or "?"))))
	end
end

-- Party membership lands on attributes; PartyFrame draws it.
handlers[Opcodes.SMSG_PARTY_UPDATE] = function(d)
	local members = d.Members or {}
	player:SetAttribute("PartyMembers", if #members > 0 then table.concat(members, ",") else nil)
	player:SetAttribute("PartyLeader", if #members > 0 then d.Leader else nil)
end

handlers[Opcodes.SMSG_PARTY_INVITE] = function(d)
	system(("%s invites you to a group. /accept or /decline"):format(tostring(d.From)))
end

local function playEmote(name: string)
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		pcall(humanoid.PlayEmote, humanoid, name)
	end
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

-- What a typed line means. "/y text" yells, "/w Name text" whispers, "/world text"
-- goes to everyone, "/wave" emotes, "/ticket text" opens a GM ticket, ".x" is a
-- command, anything else is SAY.
local function parse(text: string)
	local prefix, rest = text:match("^/(%w+)%s*(.*)$")
	if prefix and Config.Emotes[prefix:lower()] then
		return { Kind = "EMOTE", Emote = prefix:lower() }
	elseif prefix == "ticket" then
		return { Kind = "TICKET", Body = rest }
	elseif prefix == "logout" or prefix == "camp" then
		return { Kind = "LOGOUT" }
	elseif prefix == "inv" or prefix == "inventory" or prefix == "bags" then
		return { Kind = "INVENTORY" }
	elseif prefix == "invite" or prefix == "uninvite" or prefix == "promote" then
		return { Kind = "PARTY", Action = prefix, Target = rest:match("^(%S+)") }
	elseif prefix == "accept" or prefix == "decline" or prefix == "leave" then
		return { Kind = "PARTY", Action = prefix }
	elseif prefix == "p" or prefix == "party" then
		return { Kind = "CHAT", Channel = "PARTY", Body = rest }
	elseif prefix == "y" or prefix == "yell" then
		return { Kind = "CHAT", Channel = "YELL", Body = rest }
	elseif prefix == "world" or prefix == "g" then
		return { Kind = "CHAT", Channel = "WORLD", Body = rest }
	elseif prefix == "w" or prefix == "whisper" then
		local target, body = rest:match("^(%S+)%s+(.*)$")
		return { Kind = "CHAT", Channel = "WHISPER", Body = body or "", Target = target }
	end
	return { Kind = "CHAT", Channel = "SAY", Body = text, Command = text:sub(1, 1) == "." }
end

local function dispatch(p)
	if p.Kind == "EMOTE" then
		playEmote(Config.Emotes[p.Emote].Anim)
		send(Opcodes.CMSG_EMOTE, { Emote = p.Emote })
	elseif p.Kind == "TICKET" then
		send(Opcodes.CMSG_TICKET, { Text = p.Body })
	elseif p.Kind == "PARTY" then
		send(Opcodes.CMSG_PARTY, { Action = p.Action, Target = p.Target })
	elseif p.Kind == "LOGOUT" then
		send(Opcodes.CMSG_LOGOUT_REQUEST, {})
	elseif p.Kind == "INVENTORY" then
		send(Opcodes.CMSG_INVENTORY, {})
	else
		send(Opcodes.CMSG_MESSAGECHAT, { Channel = p.Channel, Text = p.Body, Target = p.Target })
	end
end

if modern then
	local inputBar = TextChatService:FindFirstChildOfClass("ChatInputBarConfiguration")
	if inputBar and channel then
		inputBar.TargetTextChannel = channel
	end

	-- Roblox's chat window is off; our own line is drawn here when the box sends.
	local function echo(p)
		local me = gmState[player.Name]
		local myName = esc(player:GetAttribute("CharacterName") or player.DisplayName)
		local myClass = player:GetAttribute("CharacterClass")
		if myClass and classColor[myClass] then
			myName = tint(classColor[myClass], myName)
		end
		local who = (if me and me.Gm then tint(Colors.GM, "&lt;GM&gt;") .. " " else "") .. myName
		local body = esc(p.Body or "")
		if p.Kind == "EMOTE" then
			display(tint(Colors.EMOTE, Config.Emotes[p.Emote].Text:format(myName)))
		elseif p.Kind ~= "CHAT" or p.Command then
			display(tint(Colors.COMMAND, "&gt; " .. esc(p.Raw or "")), "General")
		elseif p.Channel == "WHISPER" then
			display(tint(Colors.WHISPER, ("To %s: %s"):format(esc(p.Target or "?"), body)), "Whispers")
		elseif p.Channel == "YELL" then
			display(tint(Colors.YELL, ("%s yells: %s"):format(who, body)))
		elseif p.Channel == "WORLD" then
			display(tint(Colors.WORLD, ("[World] [%s]: %s"):format(who, body)))
		elseif p.Channel == "PARTY" then
			display(tint(Colors.PARTY, ("[Party] [%s]: %s"):format(who, body)))
		else
			display(tint(Colors.SAY, ("%s says: %s"):format(who, body)))
		end
	end

	TextChatService.SendingMessage:Connect(function(message)
		local p = parse(message.Text)
		p.Raw = message.Text
		echo(p)
		dispatch(p)
	end)
else
	player.Chatted:Connect(function(text)
		dispatch(parse(text))
	end)
end

-- The server opens the session after a DataStore read, so keep knocking until it answers.
setState("authenticating")
while not authed do
	send(Opcodes.CMSG_AUTH_SESSION, { Build = Config.Build })
	task.wait(0.5)
end
while true do
	task.wait(10)
	send(Opcodes.CMSG_PING, { Time = os.clock() })
end
