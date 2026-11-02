local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local Debris = game:GetService("Debris")
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

local function display(text: string, tab: string?, links: any?)
	chatLine:Fire(tab or "General", text, if links then HttpService:JSONEncode(links) else nil)
	if not channel then
		print((text:gsub("<[^>]->", "")))
	end
end

-- Item knowledge by entry, filled from SMSG_ITEM_QUERY_SINGLE_RESPONSE; other
-- scripts ask through the ItemInfo function (nil means "asked, wait for ItemQueryTick").
local itemCache: { [number]: any } = {}
local itemInfo = Instance.new("BindableFunction")
itemInfo.Name = "ItemInfo"
itemInfo.OnInvoke = function(entry: number)
	if itemCache[entry] then
		return itemCache[entry]
	end
	send(Opcodes.CMSG_ITEM_QUERY_SINGLE, { Entry = entry })
	return nil
end
itemInfo.Parent = script.Parent

-- [Name] in a message becomes a quality-coloured link when the server resolved it.
local function withLinks(escaped: string, links: any?): string
	if not links then
		return escaped
	end
	for shown, link in links do
		local coloured = tint(Config.Quality[link.Quality or 1] or "#FFFFFF", "[" .. esc(link.Name) .. "]")
		escaped = escaped:gsub("%[" .. esc(shown):gsub("%W", "%%%0") .. "%]", coloured)
	end
	return escaped
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
	local text = withLinks(esc(d.Text or ""), d.Links)
	local color = Colors[d.Channel] or Colors.SAY
	if d.Channel == "YELL" then
		return tint(color, ("%s yells: %s"):format(name, text))
	elseif d.Channel == "WHISPER" then
		if (d.Sender or "") == (player:GetAttribute("CharacterName") or player.DisplayName) then
			return tint(color, ("To %s: %s"):format(esc(d.Target or "?"), text))
		end
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
	player:SetAttribute("Dead", nil)
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
		display(formatChat(d), if d.Channel == "WHISPER" then "Whispers" else "General", d.Links)
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

-- Bag contents land on attributes for the character sheet and vendor window;
-- the chat listing only prints when the player asked with /inv.
handlers[Opcodes.SMSG_INVENTORY] = function(d)
	local items = d.Items or {}
	player:SetAttribute("Inventory", HttpService:JSONEncode(items))
	player:SetAttribute("BagSlots", d.Bags or Config.BagSlots)
	if d.Announce then
		system(("Inventory, %d stack(s), %s:"):format(#items, money(d.Money or 0)))
		for _, item in items do
			display("  " .. qualityName(item.Name, item.Quality) .. tint(Colors.SAY, " x" .. tostring(item.Count)))
		end
	end
end

handlers[Opcodes.SMSG_EQUIPMENT] = function(d)
	player:SetAttribute("Equipment", HttpService:JSONEncode(d.Slots or {}))
	player:SetAttribute("Stats", HttpService:JSONEncode(d.Stats or {}))
end

-- Vendor windows open on an event so talking to the same vendor twice works.
local vendorOpen = Instance.new("BindableEvent")
vendorOpen.Name = "VendorOpen"
vendorOpen.Parent = script.Parent

handlers[Opcodes.SMSG_VENDOR_LIST] = function(d)
	player:SetAttribute("Vendor", HttpService:JSONEncode(d.Items or {}))
	player:SetAttribute("VendorGuid", tostring(d.Guid))
	vendorOpen:Fire(tostring(d.Guid))
end

-- One-shot particle effects from ReplicatedStorage/Assets/Particles on a player,
-- a creature (by guid) or a position.
local function effectTarget(d): BasePart?
	if d.Player then
		local other = Players:FindFirstChild(d.Player)
		return other and other.Character and other.Character:FindFirstChild("HumanoidRootPart")
	elseif d.Guid then
		local creatures = workspace:FindFirstChild("Creatures")
		for _, child in (creatures and creatures:GetChildren() or {}) do
			if child:GetAttribute("Guid") == d.Guid then
				return child:FindFirstChild("HumanoidRootPart")
			end
		end
	elseif d.Position then
		local part = Instance.new("Part")
		part.Anchored, part.CanCollide, part.Transparency = true, false, 1
		part.Size = Vector3.new(1, 1, 1)
		part.Position = Vector3.new(table.unpack(d.Position))
		part.Parent = workspace
		Debris:AddItem(part, 4)
		return part
	end
	return nil
end

handlers[Opcodes.SMSG_PLAY_EFFECT] = function(d)
	local folder = ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("Particles")
	local source = folder and folder:FindFirstChild(tostring(d.Name))
	local target = effectTarget(d)
	if source and target then
		local emitter = source:Clone()
		emitter.Enabled = false
		emitter.Parent = target
		emitter:Emit(d.Count or 12)
		Debris:AddItem(emitter, 4)
	end
end

-- Loot window state lives on attributes; LootOpen fires when a corpse is opened.
local lootOpen = Instance.new("BindableEvent")
lootOpen.Name = "LootOpen"
lootOpen.Parent = script.Parent
local lootItems = {}

local function pushLoot()
	player:SetAttribute("Loot", HttpService:JSONEncode(lootItems))
end

handlers[Opcodes.SMSG_LOOT_RESPONSE] = function(d)
	lootItems = { Guid = d.Guid, Name = d.Name, Items = d.Items or {}, Money = d.Money or 0 }
	pushLoot()
	lootOpen:Fire()
end

handlers[Opcodes.SMSG_LOOT_REMOVED] = function(d)
	if d.Money then
		lootItems.Money = 0
	elseif d.Index and lootItems.Items then
		lootItems.Items[d.Index] = nil
	end
	pushLoot()
end

handlers[Opcodes.SMSG_LOOT_RELEASE_RESPONSE] = function()
	lootItems = {}
	player:SetAttribute("Loot", nil)
end

handlers[Opcodes.SMSG_DEATH] = function()
	player:SetAttribute("Dead", true)
end

-- Quests: the log and questgiver statuses live on attributes; the questgiver
-- window opens on events carrying the packets.
local questList = Instance.new("BindableEvent")
questList.Name = "QuestList"
questList.Parent = script.Parent
local questDetails = Instance.new("BindableEvent")
questDetails.Name = "QuestDetails"
questDetails.Parent = script.Parent

handlers[Opcodes.SMSG_QUESTGIVER_QUEST_LIST] = function(d)
	questList:Fire(d)
end

handlers[Opcodes.SMSG_QUESTGIVER_QUEST_DETAILS] = function(d)
	questDetails:Fire(d)
end

handlers[Opcodes.SMSG_QUESTLOG] = function(d)
	player:SetAttribute("QuestLog", HttpService:JSONEncode(d.Quests or {}))
end

handlers[Opcodes.SMSG_QUESTGIVER_STATUS_MULTIPLE] = function(d)
	player:SetAttribute("QuestgiverStatus", HttpService:JSONEncode(d.Statuses or {}))
end

handlers[Opcodes.SMSG_QUESTUPDATE_ADD_KILL] = function(d)
	notice(tint(Colors.QUEST, esc(("%s slain: %d/%d"):format(d.Name or "?", d.Have or 0, d.Need or 0))))
end

handlers[Opcodes.SMSG_QUESTUPDATE_COMPLETE] = function(d)
	notice(tint(Colors.QUEST, esc((d.Title or "Quest") .. " (Complete)")))
end

-- Spells: known list, action bar, cooldowns and the current cast ride on
-- attributes; the trainer window opens on an event.
local trainerOpen = Instance.new("BindableEvent")
trainerOpen.Name = "TrainerOpen"
trainerOpen.Parent = script.Parent
local cooldowns: { [string]: number } = {}

handlers[Opcodes.SMSG_INITIAL_SPELLS] = function(d)
	player:SetAttribute("Spells", HttpService:JSONEncode(d.Spells or {}))
end

handlers[Opcodes.SMSG_ACTION_BUTTONS] = function(d)
	player:SetAttribute("ActionBar", HttpService:JSONEncode(d.Buttons or {}))
end

handlers[Opcodes.SMSG_LEARNED_SPELL] = function(d)
	notice(tint(Colors.SYSTEM, esc("You have learned a new spell: " .. (d.Name or "?"))))
end

handlers[Opcodes.SMSG_SPELL_START] = function(d)
	player:SetAttribute("Casting", HttpService:JSONEncode({ Id = d.Id, Name = d.Name, Start = os.clock(), Ends = os.clock() + (d.CastTime or 0) }))
end

handlers[Opcodes.SMSG_SPELL_GO] = function()
	player:SetAttribute("Casting", nil)
end

handlers[Opcodes.SMSG_SPELL_FAILURE] = function(d)
	player:SetAttribute("Casting", nil)
	player:SetAttribute("CastError", (d.Reason or "Interrupted.") .. " " .. os.clock())
	display(tint(Colors.YELL, esc(d.Reason or "Interrupted.")), "Log")
end

handlers[Opcodes.SMSG_SPELL_COOLDOWN] = function(d)
	cooldowns[tostring(d.Id)] = os.clock() + (d.Seconds or 0)
	player:SetAttribute("Cooldowns", HttpService:JSONEncode(cooldowns))
end

handlers[Opcodes.SMSG_TRAINER_LIST] = function(d)
	trainerOpen:Fire(d)
end

-- Mail and social
local mailOpen = Instance.new("BindableEvent")
mailOpen.Name = "MailOpen"
mailOpen.Parent = script.Parent

handlers[Opcodes.SMSG_MAIL_LIST_RESULT] = function(d)
	player:SetAttribute("Mail", HttpService:JSONEncode(d.Mails or {}))
	if d.Guid then
		mailOpen:Fire(d.Guid)
	end
end

handlers[Opcodes.SMSG_RECEIVED_MAIL] = function(d)
	if d.Unread then
		notice(tint(Colors.SYSTEM, ("You have %d unread letter%s."):format(d.Unread, if d.Unread == 1 then "" else "s")))
	else
		notice(tint(Colors.SYSTEM, esc(("You have new mail from %s."):format(d.From or "?"))))
	end
end

handlers[Opcodes.SMSG_SEND_MAIL_RESULT] = function(d)
	player:SetAttribute("MailSent", if d.Ok then os.clock() else nil)
end

handlers[Opcodes.SMSG_CONTACT_LIST] = function(d)
	player:SetAttribute("Contacts", HttpService:JSONEncode({ Friends = d.Friends or {}, Ignore = d.Ignore or {} }))
end

handlers[Opcodes.SMSG_FRIEND_STATUS] = function(d)
	notice(tint(Colors.SYSTEM, esc(("%s has %s."):format(d.Name or "?", if d.Online then "come online" else "gone offline"))))
end

handlers[Opcodes.SMSG_WHO] = function(d)
	local list = d.Players or {}
	display(tint(Colors.SYSTEM, ("%d player%s total"):format(#list, if #list == 1 then "" else "s")))
	for _, p in list do
		display(tint(Colors.SYSTEM, esc(("%s: Level %d %s - %s"):format(p.Name or "?", p.Level or 1, p.Class or "", p.Zone or "Unknown"))))
	end
end

local function duration(seconds: number): string
	local d, h, m = seconds // 86400, (seconds % 86400) // 3600, (seconds % 3600) // 60
	return ("%d days, %d hours, %d minutes"):format(d, h, m)
end

handlers[Opcodes.SMSG_PLAYED_TIME] = function(d)
	display(tint(Colors.SYSTEM, "Total time played: " .. duration(d.Total or 0)))
	display(tint(Colors.SYSTEM, "Time played this session: " .. duration(d.Session or 0)))
end

handlers[Opcodes.SMSG_BINDPOINTUPDATE] = function(d)
	notice(tint(Colors.SYSTEM, esc(("Your home is now %s."):format(d.Name or "here"))))
end

handlers[Opcodes.SMSG_QUESTGIVER_QUEST_COMPLETE] = function(d)
	notice(tint(Colors.QUEST, esc("Quest completed: " .. (d.Title or "?"))))
	questList:Fire(nil)
end

handlers[Opcodes.SMSG_BUYBACK_LIST] = function(d)
	player:SetAttribute("Buyback", HttpService:JSONEncode(d.Items or {}))
end

handlers[Opcodes.SMSG_ITEM_QUERY_SINGLE_RESPONSE] = function(d)
	if d.Entry then
		itemCache[d.Entry] = d
		player:SetAttribute("ItemQueryTick", (player:GetAttribute("ItemQueryTick") or 0) + 1)
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
	elseif prefix == "friend" or prefix == "unfriend" or prefix == "removefriend" or prefix == "ignore" or prefix == "unignore" then
		return { Kind = "SOCIAL", Action = prefix, Target = rest:match("^(%S+)") }
	elseif prefix == "who" then
		return { Kind = "WHO", Filter = rest }
	elseif prefix == "played" then
		return { Kind = "PLAYED" }
	elseif prefix == "friends" or prefix == "social" then
		return { Kind = "FRIENDS" }
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
	elseif p.Kind == "SOCIAL" then
		local opcode = ({ friend = Opcodes.CMSG_ADD_FRIEND, unfriend = Opcodes.CMSG_DEL_FRIEND, removefriend = Opcodes.CMSG_DEL_FRIEND, ignore = Opcodes.CMSG_ADD_IGNORE, unignore = Opcodes.CMSG_DEL_IGNORE })[p.Action]
		send(opcode, { Name = p.Target })
	elseif p.Kind == "WHO" then
		send(Opcodes.CMSG_WHO, { Filter = p.Filter })
	elseif p.Kind == "PLAYED" then
		send(Opcodes.CMSG_PLAYED_TIME, {})
	elseif p.Kind == "FRIENDS" then
		player:SetAttribute("ToggleFriends", os.clock())
	else
		send(Opcodes.CMSG_MESSAGECHAT, { Channel = p.Channel, Text = p.Body, Target = p.Target })
	end
end

-- Chat lines come back from the server; only commands and slash actions echo locally.
local function echo(p)
	if p.Kind ~= "CHAT" or p.Command then
		display(tint(Colors.COMMAND, "&gt; " .. esc(p.Raw or "")), "General")
	end
end

-- ChatFrame owns the input box: ChatSend(text) sends through the TextChannel so
-- filtering still applies (or straight to the server on legacy chat).
local chatSend = Instance.new("BindableEvent")
chatSend.Name = "ChatSend"
chatSend.Event:Connect(function(text: string)
	if channel then
		channel:SendAsync(text)
	else
		local p = parse(text)
		p.Raw = text
		echo(p)
		dispatch(p)
	end
end)
chatSend.Parent = script.Parent

if modern then
	local inputBar = TextChatService:FindFirstChildOfClass("ChatInputBarConfiguration")
	if inputBar and channel then
		inputBar.TargetTextChannel = channel
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
