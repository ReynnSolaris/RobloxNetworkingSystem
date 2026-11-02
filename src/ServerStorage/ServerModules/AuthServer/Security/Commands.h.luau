local Base = require(game:GetService("ServerStorage").ServerModules["Template.h"])
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Opcodes = require(ReplicatedStorage.Shared.Opcodes)
local Config = require(ReplicatedStorage.Shared.Config)
local module = {}

-- WoW-style GM dot commands typed in chat. Levels: 1 MODERATOR, 2 GAMEMASTER, 4 OWNER.
-- A PLAYER typing a dot command gets "There is no such command".

local started = os.time()
local commands = {}

local function add(name: string, level: number, usage: string, run)
	commands[name] = { level = level, usage = usage, run = run }
end

local function findPlayer(name: string?): Player
	assert(name and #name > 0, "no player given")
	local lower = name:lower()
	local prefix = nil
	for _, player in Players:GetPlayers() do
		for _, candidate in { player:GetAttribute("CharacterName") or "", player.Name, player.DisplayName } do
			if candidate:lower() == lower then
				return player
			elseif candidate:lower():sub(1, #lower) == lower then
				prefix = prefix or player
			end
		end
	end
	return prefix or error("no player named " .. name, 0)
end

local function humanoid(player: Player): Humanoid
	local character = assert(player.Character, player.Name .. " has no character")
	return assert(character:FindFirstChildOfClass("Humanoid"), player.Name .. " has no humanoid")
end

local function toggle(word: string?): boolean
	assert(word == "on" or word == "off", "expected on or off")
	return word == "on"
end

local function minutes(seconds: number): string
	return ("%d min"):format(math.ceil(seconds / 60))
end

-- A name that is online here, or a UserId looked up for someone on another server.
local function resolveUserId(name: string?): (number, string)
	assert(name and #name > 0, "no player given")
	local ok, player = pcall(findPlayer, name)
	if ok then
		return player.UserId, player.Name
	end
	local found, id = pcall(Players.GetUserIdFromNameAsync, Players, name)
	assert(found, "no player named " .. name)
	return id, name
end

-- Pick the target: args[i] if given, else the caller.
local function targetOrSelf(args, i: number, caller: Player): Player
	return if args[i] then findPlayer(args[i]) else caller
end

-- info

local ALIASES = { gobj = "gobject", go = "gobject", look = "lookup", tp = "tele", goname = "appear", namego = "summon", ann = "announce", h = "help", die = "kill" }

-- One line per form of a command's usage.
function module:Usage(caller: Player, name: string)
	local command = commands[name]
	if not command then
		return self:Reply(caller, "There is no such command. Try .help")
	end
	self:Reply(caller, "." .. name .. " (" .. self.includes.Security["RBAC_Permissions.h"]:GetRoleName(command.level) .. "):")
	for _, form in command.usage:split(" | ") do
		self:Reply(caller, "  " .. form)
	end
end

add("help", 1, ".help [command]", function(self, caller, args)
	if args[1] then
		return self:Usage(caller, ALIASES[args[1]:lower()] or args[1]:lower())
	end
	local RBAC = self.includes.Security["RBAC_Permissions.h"]
	local role = RBAC:GetRole(caller)
	local lines = {}
	for name, cmd in commands do
		if role >= cmd.level then
			table.insert(lines, "." .. name)
		end
	end
	table.sort(lines)
	self:Reply(caller, ("Commands for %s (.help <command> for forms):"):format(RBAC:GetRoleName(role)))
	self:Reply(caller, "  " .. table.concat(lines, "  "))
end)

add("gps", 1, ".gps", function(self, caller)
	local pivot = assert(caller.Character, "you have no character"):GetPivot()
	local _, yaw = pivot:ToEulerAnglesYXZ()
	local zone = self.includes.Zones["Zones.h"]:Current(caller)
	self:Reply(caller, ("X %.1f Y %.1f Z %.1f, facing %.0f, %s"):format(pivot.X, pivot.Y, pivot.Z, math.deg(yaw), if zone then zone.Name else "no zone"))
end)

add("time", 2, ".time <0-24>", function(self, caller, args)
	game:GetService("Lighting").ClockTime = math.clamp(assert(tonumber(args[1]), "expected an hour"), 0, 24)
end)

add("morph", 2, ".morph <userId> [player]", function(self, caller, args)
	local target = targetOrSelf(args, 2, caller)
	local ok, description = pcall(Players.GetHumanoidDescriptionFromUserId, Players, assert(tonumber(args[1]), "expected a UserId"))
	assert(ok, "no such user")
	humanoid(target):ApplyDescription(description)
end)

add("demorph", 2, ".demorph [player]", function(self, caller, args)
	local target = targetOrSelf(args, 1, caller)
	local ok, description = pcall(Players.GetHumanoidDescriptionFromUserId, Players, target.UserId)
	assert(ok, "could not load the player's look")
	humanoid(target):ApplyDescription(description)
end)

add("modify", 2, ".modify hp <amount> [player] | .modify speed <0.1-10> [player] | .modify scale <0.5-4> [player] | .modify xp <amount> [player]", function(self, caller, args)
	local what, value = args[1], assert(tonumber(args[2]), "expected a number")
	local target = targetOrSelf(args, 3, caller)
	local h = humanoid(target)
	if what == "hp" then
		h.MaxHealth = value
		h.Health = value
	elseif what == "speed" then
		h.WalkSpeed = 16 * math.clamp(value, 0.1, 10)
	elseif what == "xp" then
		self.includes.Entities["EntityPlayer.h"]:GrantXp(target, value, "Granted by " .. caller.Name)
	elseif what == "scale" then
		value = math.clamp(value, 0.5, 4)
		for _, name in { "BodyHeightScale", "BodyWidthScale", "BodyDepthScale", "HeadScale" } do
			local v = h:FindFirstChild(name)
			if v then
				v.Value = value
			end
		end
	else
		error("expected hp, speed, scale or xp", 0)
	end
end)

add("who", 1, ".who", function(self, caller)
	local RBAC = self.includes.Security["RBAC_Permissions.h"]
	local Session = self.includes.Security["Session.h"]
	for _, player in Players:GetPlayers() do
		local session = Session:Get(player)
		self:Reply(caller, ("%s%s (%s) %s%s"):format(player.Name,
			if player:GetAttribute("CharacterName") then " as " .. player:GetAttribute("CharacterName") else "",
			RBAC:GetRoleName(RBAC:GetRole(player)),
			if session and session.Gm then "<GM> " else "", if session and session.Invisible then "[invisible]" else ""))
	end
end)

add("server", 1, ".server info", function(self, caller)
	local up = os.time() - started
	self:Reply(caller, ("Build %d, up %dh %dm, %d players, %d Hz"):format(
		Config.Build, up // 3600, (up % 3600) // 60, #Players:GetPlayers(), math.round(1 / game:GetService("RunService").Heartbeat:Wait())))
end)

add("zone", 1, ".zone | .zone show | .zone hide", function(self, caller, args)
	local Zones = self.includes.Zones["Zones.h"]
	if args[1] == "show" or args[1] == "hide" then
		for _, part in Zones:All() do
			part.Transparency = if args[1] == "show" then 0.85 else 1
		end
		return self:Reply(caller, "Zone bounds " .. (if args[1] == "show" then "shown." else "hidden."))
	end
	local here = Zones:Current(caller)
	self:Reply(caller, "You are in: " .. (if here then here.Name else "no zone"))
	for _, part in Zones:All() do
		self:Reply(caller, ("  %s%s%s"):format(part.Name,
			if part:GetAttribute("Pvp") then " [PvP]" else "", if part:GetAttribute("Safe") then " [Safe]" else ""))
	end
end)

add("ticket", 1, ".ticket list | .ticket view <id> | .ticket reply <id> <text> | .ticket close <id>", function(self, caller, args)
	local Tickets = self.includes.Support["Tickets.h"]
	local sub, id = args[1], tonumber(args[2])
	if sub == "list" then
		local open = Tickets:State().Open
		self:Reply(caller, ("%d open ticket(s)"):format(#open))
		for _, ticket in open do
			self:Reply(caller, ("  #%d %s: %s"):format(ticket.Id, ticket.Name, ticket.Text:sub(1, 60)))
		end
	elseif sub == "view" then
		local ticket = assert(Tickets:Get(assert(id, "expected an id")), "no such ticket")
		self:Reply(caller, ("#%d %s (%d), %s ago: %s"):format(ticket.Id, ticket.Name, ticket.UserId, minutes(os.time() - ticket.At), ticket.Text))
	elseif sub == "reply" then
		self:Reply(caller, Tickets:Reply(assert(id, "expected an id"), table.concat(args, " ", 3)))
	elseif sub == "close" then
		self:Reply(caller, if Tickets:Close(assert(id, "expected an id")) then "Closed." else "No such ticket.")
	else
		error("expected list, view, reply or close", 0)
	end
end)

add("ac", 1, ".ac status | .ac reset <player> | .ac on|off", function(self, caller, args)
	local AC = self.includes.Movement["Anticheat.h"]
	if args[1] == "reset" then
		AC:Reset(findPlayer(args[2]))
		self:Reply(caller, "Strikes cleared.")
	elseif args[1] == "on" or args[1] == "off" then
		AC:SetEnabled(args[1] == "on")
		self:Reply(caller, "Anticheat " .. args[1] .. ".")
	else
		self:Reply(caller, "Anticheat " .. (if AC:Enabled() then "on" else "off"))
		for _, player in Players:GetPlayers() do
			if AC:Strikes(player) > 0 then
				self:Reply(caller, ("  %s: %d strike(s)"):format(player.Name, AC:Strikes(player)))
			end
		end
	end
end)

-- gm mode and visibility

-- The GM Island test area: every creature and object template in rows around the caller.
local function testArea(self, caller: Player, clear: boolean)
	local DB = self.includes.Database["WorldDB.h"]
	local Creatures = self.includes.Content["Creatures.h"]
	local GameObjects = self.includes.Content["GameObjects.h"]
	if clear then
		local n = 0
		for _, row in DB:Select("creature") do
			if row.testarea then Creatures:Delete(row.guid) n += 1 end
		end
		for _, row in DB:Select("gameobject") do
			if row.testarea then GameObjects:Delete(row.guid) n += 1 end
		end
		return n
	end
	local origin = assert(caller.Character, "you have no character"):GetPivot()
	local n = 0
	local creatures = DB:Select("creature_template")
	for i, template in creatures do
		if template.faction ~= "pet" then
			local ground = origin * CFrame.new(-20 + (i - 1) % 10 * 5, 0, -12 - (i - 1) // 10 * 6)
			local row = Creatures:Add(template.entry, ground, caller)
			DB:Update("creature", row.guid, { testarea = true, spawntimesecs = 20 })
			n += 1
		end
	end
	local objects = DB:Select("gameobject_template")
	for i, template in objects do
		local ground = origin * CFrame.new(-20 + (i - 1) % 10 * 5, 0, 12 + (i - 1) // 10 * 6)
		local row = GameObjects:Add(template.entry, ground, 1, caller)
		DB:Update("gameobject", row.guid, { testarea = true, spawntimesecs = 20 })
		n += 1
	end
	return n
end

add("gm", 1, ".gm on|off | .gm invis on|off | .gm list | .gm gear | .gm testarea [clear]", function(self, caller, args)
	local Session = self.includes.Security["Session.h"]
	local session = assert(Session:Get(caller), "no session")
	local sub = args[1]
	if sub == "gear" then
		local Entities = self.includes.Entities["EntityPlayer.h"]
		local Items = self.includes.Content["Items.h"]
		for _, name in { "Gamemaster's Hood", "Gamemaster's Robe", "Gamemaster's Leggings", "Gamemaster's Boots", "Gamemaster's Blade", "Gamemaster's Shield", "Gamemaster's Band", "Gamemaster's Band" } do
			local item = Items:ByName(name)
			if item and Entities:AddItem(caller, item.entry, 1, true) then
				for slot = 1, Entities:BagSize(caller) do
					local stack = Entities:StackAt(caller, slot)
					if stack and stack.entry == item.entry then
						Entities:Equip(caller, slot)
						break
					end
				end
			end
		end
		return self:Reply(caller, "You are wearing the gamemaster's set.")
	elseif sub == "testarea" then
		local n = testArea(self, caller, args[2] == "clear")
		return self:Reply(caller, if args[2] == "clear" then ("Removed %d test spawns."):format(n) else ("Placed %d test spawns around you. .gm testarea clear removes them."):format(n))
	elseif sub == "list" then
		for _, player in Players:GetPlayers() do
			local other = Session:Get(player)
			if other and other.Gm then
				self:Reply(caller, player.Name .. (if other.Invisible then " [invisible]" else ""))
			end
		end
	elseif sub == "invis" then
		session.Invisible = toggle(args[2])
		self:Reply(caller, if session.Invisible then "You are now invisible to players." else "You are now visible.")
	else
		session.Gm = toggle(sub)
		self:Reply(caller, if session.Gm then "GM mode on. Creatures are neutral to you and you see what ghosts see." else "GM mode off. You are a player to the world again.")
	end
	self:BroadcastState(caller)
end)

-- movement

add("tele", 2, ".tele <name> | .tele <x> <y> <z> | .tele add <name> | .tele del <name> | .tele list", function(self, caller, args)
	local Entities = self.includes.Entities["EntityPlayer.h"]
	local Teleports = self.includes.Content["Teleports.h"]
	local sub = args[1]
	if sub == "list" then
		local names = {}
		for _, row in Teleports:All() do
			table.insert(names, row.name)
		end
		for _, part in self.includes.Zones["Zones.h"]:All() do
			table.insert(names, part.Name)
		end
		table.sort(names)
		self:Reply(caller, "Locations: " .. table.concat(names, ", "))
	elseif sub == "add" then
		local name = assert(args[2], "expected a name")
		Teleports:Add(name, assert(caller.Character, "you have no character"):GetPivot(), caller)
		self:Reply(caller, ("Saved %s, all servers."):format(name))
	elseif sub == "del" then
		self:Reply(caller, if Teleports:Remove(assert(args[2], "expected a name")) then "Removed." else "No such location.")
	elseif #args == 3 then
		local x, y, z = tonumber(args[1]), tonumber(args[2]), tonumber(args[3])
		Entities:Teleport(caller, CFrame.new(assert(x), assert(y), assert(z)))
	else
		local at, name = Teleports:Resolve(assert(sub, "expected a location"))
		assert(at, "no location named " .. tostring(sub))
		Entities:Teleport(caller, at)
		self:Reply(caller, "Teleported to " .. name)
	end
end)

add("appear", 2, ".appear <player>", function(self, caller, args)
	local other = findPlayer(args[1])
	self.includes.Entities["EntityPlayer.h"]:Teleport(caller, assert(other.Character, "target has no character"):GetPivot() * CFrame.new(0, 0, 3))
end)

-- A ground spot 4 studs in front of the caller, facing them, turned by `yaw` degrees.
local function placement(self, caller: Player, yaw: number?): CFrame
	local pivot = assert(caller.Character, "you have no character"):GetPivot()
	local ahead = (pivot * CFrame.new(0, 0, -4)).Position
	local ignore = { caller.Character, workspace:FindFirstChild("GameObjects"), workspace:FindFirstChild("Creatures") }
	local y = self.includes.Content["GameObjects.h"].GroundY(ahead, ignore)
	local _, facing = pivot:ToEulerAnglesYXZ()
	return CFrame.new(ahead.X, y, ahead.Z) * CFrame.Angles(0, facing + math.pi + math.rad(yaw or 0), 0)
end

-- Nearest spawn of a kind, or the one with the given guid when args[i] is a number.
local function pick(self, list, caller: Player, args, i: number): (Model, number)
	local module_ = self.includes.Content[list]
	if tonumber(args[i]) and module_:Find(args[i]) then
		return module_:Find(args[i]), i + 1
	end
	local near = module_:Near(assert(caller.Character, "you have no character"):GetPivot().Position, 15)
	return assert(near[1], "nothing within 15 studs; give a guid"), i
end

add("lookup", 1, ".lookup creature|object|item|tele <name>", function(self, caller, args)
	local what, needle = args[1], (table.concat(args, " ", 2)):lower()
	local tableName = ({ creature = "creature_template", object = "gameobject_template", item = "item_template", tele = "game_tele", quest = "quest_template", spell = "spell_template",
		faction = "faction", skill = "skill_line", recipe = "skill_recipe", talent = "talent", achievement = "achievement", taxi = "taxi_nodes" })[what]
	assert(tableName, "expected creature, object, item, quest, spell, tele, faction, skill, recipe, talent, achievement or taxi")
	local DB = self.includes.Database["WorldDB.h"]
	local pk = DB.TABLES[tableName]
	local hits = 0
	for _, row in DB:Select(tableName) do
		if hits < 20 and (needle == "" or tostring(row.name or row.title):lower():find(needle, 1, true)) then
			hits += 1
			self:Reply(caller, ("  %s: %s%s"):format(tostring(row[pk]), tostring(row.name or row.title), if row.subname then " <" .. row.subname .. ">" else ""))
		end
	end
	self:Reply(caller, ("%d match(es)"):format(hits))
end)

add("reload", 2, ".reload creature|gameobject", function(self, caller, args)
	local Content = self.includes.Content
	if args[1] == "creature" then
		Content["Creatures.h"]:Respawn()
	elseif args[1] == "gameobject" then
		Content["GameObjects.h"]:Respawn()
	else
		error("expected creature or gameobject", 0)
	end
	self:Reply(caller, "Reloaded " .. args[1] .. " from the world database.")
end)

add("gobject", 2, ".gobject add <entry> [yaw] [scale] | delete [guid] | move [guid] | turn [guid] <degrees> | near [radius] | template add <name> <modelid> [size] | template list", function(self, caller, args)
	local Objects = self.includes.Content["GameObjects.h"]
	local DB = self.includes.Database["WorldDB.h"]
	local sub = args[1]
	if sub == "template" then
		if args[2] == "add" then
			local row = DB:Insert("gameobject_template", { name = assert(args[3], "expected a name"), modelid = assert(args[4], "expected a modelid"), size = tonumber(args[5]) or 1 })
			self:Reply(caller, ("gameobject_template entry %d: %s"):format(row.entry, row.name))
		else
			for _, row in DB:Select("gameobject_template") do
				self:Reply(caller, ("  %d: %s (%s, size %s)"):format(row.entry, row.name, row.modelid, tostring(row.size or 1)))
			end
		end
	elseif sub == "add" then
		local row = Objects:Add(assert(tonumber(args[2]), "expected an entry"), placement(self, caller, tonumber(args[3])), tonumber(args[4]), caller)
		self:Reply(caller, ("Placed %s, guid %d."):format(Objects:Template(row.id).name, row.guid))
	elseif sub == "delete" then
		local model = pick(self, "GameObjects.h", caller, args, 2)
		Objects:Delete(model:GetAttribute("Guid"))
		self:Reply(caller, "Deleted " .. model.Name .. ".")
	elseif sub == "move" then
		local model = pick(self, "GameObjects.h", caller, args, 2)
		Objects:Move(model:GetAttribute("Guid"), placement(self, caller))
		self:Reply(caller, "Moved.")
	elseif sub == "turn" then
		local model, i = pick(self, "GameObjects.h", caller, args, 2)
		Objects:Turn(model:GetAttribute("Guid"), assert(tonumber(args[i]), "expected degrees"))
		self:Reply(caller, "Turned.")
	else
		local here = assert(caller.Character, "you have no character"):GetPivot().Position
		for _, model in Objects:Near(here, tonumber(args[2]) or 30) do
			self:Reply(caller, ("  guid %s entry %s %s, %.0f studs"):format(model:GetAttribute("Guid"), model:GetAttribute("Entry"), model.Name, (model:GetPivot().Position - here).Magnitude))
		end
	end
end)

add("npc", 2, ".npc add <entry> | delete [guid] | move [guid] | kill [guid] | say [guid] <text> | info [guid] | near [radius] | wp add [guid] [wait] | wp clear [guid] | template add <name> [modelid] [subname] | template set <entry> <field> <value> | template list", function(self, caller, args)
	if args[1] == "wp" then
		local Creatures = self.includes.Content["Creatures.h"]
		local model, nextArg = pick(self, "Creatures.h", caller, args, 3)
		local guid = model:GetAttribute("Guid")
		if args[2] == "add" then
			local n = Creatures:AddWaypoint(guid, assert(caller.Character, "you have no character"):GetPivot().Position, tonumber(args[nextArg]))
			return self:Reply(caller, ("Waypoint %d added to %s."):format(n, model.Name))
		elseif args[2] == "clear" then
			Creatures:ClearWaypoints(guid)
			return self:Reply(caller, "Waypoints cleared.")
		end
		error("expected wp add or wp clear", 0)
	end
	local Creatures = self.includes.Content["Creatures.h"]
	local DB = self.includes.Database["WorldDB.h"]
	local sub = args[1]
	if sub == "template" then
		if args[2] == "add" then
			local row = DB:Insert("creature_template", { name = assert(args[3], "expected a name"), modelid = args[4] or "default", subname = args[5], scale = 1, gossip = "Greetings, traveler." })
			self:Reply(caller, ("creature_template entry %d: %s"):format(row.entry, row.name))
		elseif args[2] == "set" then
			local entry, field = assert(tonumber(args[3]), "expected an entry"), args[4]
			local NUMERIC = { scale = 1, minlevel = 1, maxlevel = 1, health = 1, dmgmin = 1, dmgmax = 1, aggro = 1, speed = 1, mingold = 1, maxgold = 1 }
			local TEXT = { name = 1, subname = 1, modelid = 1, gossip = 1, faction = 1 }
			assert(NUMERIC[field or ""] or TEXT[field or ""], "field is name, subname, modelid, gossip, faction, scale, minlevel, maxlevel, health, dmgmin, dmgmax, aggro, speed, mingold or maxgold")
			local value: any = table.concat(args, " ", 5)
			if NUMERIC[field] then
				value = assert(tonumber(value), "expected a number")
			end
			assert(DB:Update("creature_template", entry, { [field] = value }), "no such entry")
			Creatures:Respawn(entry)
			self:Reply(caller, ("Set %s on entry %d."):format(field, entry))
		else
			for _, row in DB:Select("creature_template") do
				self:Reply(caller, ("  %d: %s%s (%s, x%s)"):format(row.entry, row.name, if row.subname then " <" .. row.subname .. ">" else "", row.modelid or "default", tostring(row.scale or 1)))
			end
		end
	elseif sub == "add" then
		local row = Creatures:Add(assert(tonumber(args[2]), "expected an entry"), placement(self, caller), caller)
		self:Reply(caller, ("Spawned %s, guid %d."):format(Creatures:Template(row.id).name, row.guid))
	elseif sub == "delete" then
		local model = pick(self, "Creatures.h", caller, args, 2)
		Creatures:Delete(model:GetAttribute("Guid"))
		self:Reply(caller, "Deleted " .. model.Name .. ".")
	elseif sub == "move" then
		local model = pick(self, "Creatures.h", caller, args, 2)
		Creatures:Move(model:GetAttribute("Guid"), placement(self, caller))
		self:Reply(caller, "Moved.")
	elseif sub == "say" then
		local model, i = pick(self, "Creatures.h", caller, args, 2)
		Creatures:Say(model, table.concat(args, " ", i))
	elseif sub == "kill" then
		local model = pick(self, "Creatures.h", caller, args, 2)
		local state = Creatures:State(model:GetAttribute("Guid"))
		if state then
			state.LastAttacker = caller
			state.Humanoid.Health = 0
		end
	elseif sub == "info" then
		local model = pick(self, "Creatures.h", caller, args, 2)
		local t = Creatures:Template(model:GetAttribute("Entry")) or {}
		self:Reply(caller, ("guid %s, entry %s: %s <%s>, model %s, scale %s"):format(model:GetAttribute("Guid"), model:GetAttribute("Entry"), tostring(t.name), tostring(t.subname), tostring(t.modelid), tostring(t.scale or 1)))
		self:Reply(caller, "gossip: " .. tostring(t.gossip))
	else
		local here = assert(caller.Character, "you have no character"):GetPivot().Position
		for _, model in Creatures:Near(here, tonumber(args[2]) or 30) do
			self:Reply(caller, ("  guid %s entry %s %s, %.0f studs"):format(model:GetAttribute("Guid"), model:GetAttribute("Entry"), model.Name, (model:GetPivot().Position - here).Magnitude))
		end
	end
end)

add("summon", 2, ".summon <player>", function(self, caller, args)
	local other = findPlayer(args[1])
	local here = assert(caller.Character, "you have no character"):GetPivot() * CFrame.new(0, 0, -3)
	self.includes.Entities["EntityPlayer.h"]:Teleport(other, here)
	self:Reply(other, ("Summoned by %s."):format(caller.Name))
end)

add("speed", 2, ".speed <0.1-10> [player]", function(self, caller, args)
	local mult = assert(tonumber(args[1]), "expected a number")
	humanoid(targetOrSelf(args, 2, caller)).WalkSpeed = 16 * math.clamp(mult, 0.1, 10)
end)

add("freeze", 1, ".freeze <player>", function(self, caller, args)
	local other = findPlayer(args[1])
	humanoid(other).WalkSpeed = 0
	humanoid(other).JumpPower = 0
	self:Reply(other, "You have been frozen.")
end)

add("unfreeze", 1, ".unfreeze <player>", function(self, caller, args)
	local other = findPlayer(args[1])
	humanoid(other).WalkSpeed = 16
	humanoid(other).JumpPower = 50
	self:Reply(other, "You have been unfrozen.")
end)

-- health

add("hurt", 2, ".hurt <player> <amount>", function(self, caller, args)
	self.includes.Entities["EntityPlayer.h"]:Hurt(findPlayer(args[1]), assert(tonumber(args[2]), "expected an amount"))
end)

add("heal", 2, ".heal [player]", function(self, caller, args)
	self.includes.Entities["EntityPlayer.h"]:Heal(targetOrSelf(args, 1, caller))
end)

add("kill", 2, ".kill [player]", function(self, caller, args)
	humanoid(targetOrSelf(args, 1, caller)).Health = 0
end)

add("revive", 2, ".revive [player]", function(self, caller, args)
	local other = targetOrSelf(args, 1, caller)
	local Death = self.includes.Combat["Death.h"]
	if Death:IsDead(other) then
		Death:Resurrect(other, other.Character and other.Character:GetPivot())
	else
		self.includes.Entities["EntityPlayer.h"]:Spawn(other, other.Character and other.Character:GetPivot())
	end
end)

add("quest", 2, ".quest add <id> [player] | .quest complete <id> [player] | .quest remove <id> [player] | .quest template list", function(self, caller, args)
	local Quests = self.includes.Quests["Quests.h"]
	local DB = self.includes.Database["WorldDB.h"]
	if args[1] == "template" then
		for _, row in DB:Select("quest_template") do
			self:Reply(caller, ("  %d: %s (level %d, min %d)"):format(row.id, row.title, row.level or 1, row.minlevel or 1))
		end
		return
	end
	local id = assert(tonumber(args[2]), "expected a quest id")
	local target = targetOrSelf(args, 3, caller)
	local Entities = self.includes.Entities["EntityPlayer.h"]
	local entity = assert(Entities:Get(target), "no entity")
	local c = assert(entity.Active, "not in world")
	c.Quests = c.Quests or {}
	c.Done = c.Done or {}
	assert(Quests:Template(id), "no such quest")
	if args[1] == "add" then
		c.Quests[tostring(id)] = { Status = "active", Kills = {} }
	elseif args[1] == "complete" then
		local template = Quests:Template(id)
		for _, req in (template.req_creature or {}) do
			c.Quests[tostring(id)] = c.Quests[tostring(id)] or { Status = "active", Kills = {} }
			c.Quests[tostring(id)].Kills[tostring(req.entry)] = req.count
		end
	elseif args[1] == "remove" then
		c.Quests[tostring(id)] = nil
		c.Done[tostring(id)] = nil
	else
		error("expected add, complete, remove or template", 0)
	end
	self.includes.Database["WorldDatabase.h"]:Commit(target)
	Quests:Refresh(target, id)
	self:Reply(caller, "Done.")
end)

add("learn", 2, ".learn <spell id|all> [player] | .unlearn <spell id> [player]", function(self, caller, args)
	local Spells = self.includes.Spells["Spells.h"]
	local target = targetOrSelf(args, 2, caller)
	if args[1] == "all" then
		local class = target:GetAttribute("CharacterClass")
		for _, row in self.includes.Database["WorldDB.h"]:Select("spell_template") do
			if not row.npc and row.class == class then
				Spells:Learn(target, row.id, true)
			end
		end
		Spells:SendSpells(target)
	else
		local id = assert(tonumber(args[1]), "expected a spell id or all")
		assert(Spells:Template(id), "no such spell")
		Spells:Learn(target, id)
	end
	self:Reply(caller, "Done.")
end)

add("unlearn", 2, ".unlearn <spell id> [player]", function(self, caller, args)
	local id = assert(tonumber(args[1]), "expected a spell id")
	self.includes.Spells["Spells.h"]:Unlearn(targetOrSelf(args, 2, caller), id)
	self:Reply(caller, "Done.")
end)

add("graveyard", 2, ".graveyard add <name> | .graveyard list", function(self, caller, args)
	local DB = self.includes.Database["WorldDB.h"]
	if args[1] == "add" then
		local row = DB.ToRow(assert(caller.Character, "you have no character"):GetPivot())
		row.name = table.concat(args, " ", 2)
		assert(#row.name > 0, "expected a name")
		row = DB:Insert("game_graveyard", row)
		self:Reply(caller, ("game_graveyard id %d: %s"):format(row.id, row.name))
	else
		for _, row in DB:Select("game_graveyard") do
			self:Reply(caller, ("  %d: %s (%.0f, %.0f, %.0f)"):format(row.id, row.name, row.x, row.y, row.z))
		end
	end
end)

add("levelup", 2, ".levelup [player] [levels]", function(self, caller, args)
	local target = if args[1] and not tonumber(args[1]) then findPlayer(args[1]) else caller
	local levels = tonumber(args[2]) or tonumber(args[1]) or 1
	local Entities = self.includes.Entities["EntityPlayer.h"]
	Entities:SetLevel(target, (target:GetAttribute("CharacterLevel") or 1) + levels)
end)

add("setlevel", 2, ".setlevel <level> [player]", function(self, caller, args)
	self.includes.Entities["EntityPlayer.h"]:SetLevel(targetOrSelf(args, 2, caller), assert(tonumber(args[1]), "expected a level"))
end)

add("additem", 2, ".additem <entry> [count] [player]", function(self, caller, args)
	local entry, count = assert(tonumber(args[1]), "expected an item entry"), tonumber(args[2]) or 1
	local target = targetOrSelf(args, 3, caller)
	assert(self.includes.Entities["EntityPlayer.h"]:AddItem(target, entry, count), "no item_template entry " .. entry)
end)

add("loot", 2, ".loot template add <creatureEntry> <itemEntry> <chance> [min] [max] | .loot template list <creatureEntry>", function(self, caller, args)
	local DB = self.includes.Database["WorldDB.h"]
	if args[1] == "template" and args[2] == "add" then
		local row = DB:Insert("creature_loot_template", {
			entry = assert(tonumber(args[3]), "expected a creature entry"),
			item = assert(tonumber(args[4]), "expected an item entry"),
			chance = math.clamp(assert(tonumber(args[5]), "expected a chance"), 0, 100),
			mincount = tonumber(args[6]) or 1,
			maxcount = tonumber(args[7]) or tonumber(args[6]) or 1,
		})
		self:Reply(caller, ("creature_loot_template id %d added."):format(row.id))
	else
		local entry = tonumber(args[3])
		for _, row in DB:Select("creature_loot_template") do
			if not entry or row.entry == entry then
				local item = DB:Get("item_template", row.item) or {}
				self:Reply(caller, ("  id %d: creature %d drops %s (%d) %s%%, %d-%d"):format(row.id, row.entry, tostring(item.name), row.item, tostring(row.chance), row.mincount or 1, row.maxcount or 1))
			end
		end
	end
end)

add("vendor", 2, ".vendor add <creatureEntry> <itemEntry> | .vendor remove <id> | .vendor list [creatureEntry]", function(self, caller, args)
	local DB = self.includes.Database["WorldDB.h"]
	if args[1] == "add" then
		local row = DB:Insert("npc_vendor", { entry = assert(tonumber(args[2]), "expected a creature entry"), item = assert(tonumber(args[3]), "expected an item entry") })
		self:Reply(caller, ("npc_vendor id %d added."):format(row.id))
	elseif args[1] == "remove" then
		self:Reply(caller, if DB:Delete("npc_vendor", assert(tonumber(args[2]), "expected an id")) then "Removed." else "No such row.")
	else
		local entry = tonumber(args[2])
		for _, row in DB:Select("npc_vendor") do
			if not entry or row.entry == entry then
				local item = DB:Get("item_template", row.item) or {}
				self:Reply(caller, ("  id %d: creature %d sells %s (%d) for %dc"):format(row.id, row.entry, tostring(item.name), row.item, item.buyprice or 0))
			end
		end
	end
end)

add("item", 2, ".item template add <name> [quality 0-5] [stack] | .item template set <entry> <field> <value> | .item template list", function(self, caller, args)
	local DB = self.includes.Database["WorldDB.h"]
	if args[1] == "template" and args[2] == "set" then
		local entry, field = assert(tonumber(args[3]), "expected an entry"), args[4]
		local NUMERIC = { quality = 1, stack = 1, health = 1, damage = 1, armor = 1, buyprice = 1, sellprice = 1, level = 1 }
		local TEXT = { name = 1, class = 1, slot = 1 }
		assert(NUMERIC[field or ""] or TEXT[field or ""], "field is name, class, slot, quality, stack, health, damage, armor, buyprice, sellprice or level")
		local value: any = table.concat(args, " ", 5)
		if NUMERIC[field] then
			value = assert(tonumber(value), "expected a number")
		end
		assert(DB:Update("item_template", entry, { [field] = value }), "no such entry")
		self:Reply(caller, ("Set %s on item %d."):format(field, entry))
	elseif args[1] == "template" and args[2] == "add" then
		local row = DB:Insert("item_template", { name = assert(args[3], "expected a name"), quality = math.clamp(tonumber(args[4]) or 1, 0, 5), stack = tonumber(args[5]) or 1 })
		self:Reply(caller, ("item_template entry %d: %s"):format(row.entry, row.name))
	else
		for _, row in DB:Select("item_template") do
			self:Reply(caller, ("  %d: %s (quality %d, stack %d)"):format(row.entry, row.name, row.quality or 1, row.stack or 1))
		end
	end
end)

add("db", 4, ".db tables | .db select <table> [limit] | .db get <table> <key> | .db set <table> <key> <field> <value> | .db delete <table> <key>", function(self, caller, args)
	local DB = self.includes.Database["WorldDB.h"]
	local sub, tableName = args[1], args[2]
	if sub == "tables" then
		local names = {}
		for name, pk in DB.TABLES do
			table.insert(names, name .. " (" .. pk .. ")")
		end
		table.sort(names)
		self:Reply(caller, table.concat(names, ", "))
		return
	end
	assert(DB.TABLES[tableName or ""], "no such table; .db tables")
	local function show(row)
		local parts = {}
		for field, value in row do
			table.insert(parts, field .. "=" .. tostring(value))
		end
		table.sort(parts)
		self:Reply(caller, "  " .. table.concat(parts, " "))
	end
	if sub == "select" then
		local rows = DB:Select(tableName)
		local limit = tonumber(args[3]) or 10
		self:Reply(caller, ("%s: %d row(s)"):format(tableName, #rows))
		for i = 1, math.min(limit, #rows) do
			show(rows[i])
		end
	elseif sub == "get" then
		show(assert(DB:Get(tableName, args[3]), "no such row"))
	elseif sub == "set" then
		local field, raw = assert(args[4], "expected a field"), table.concat(args, " ", 5)
		local value: any = tonumber(raw) or (if raw == "true" then true elseif raw == "false" then false else raw)
		show(assert(DB:Update(tableName, args[3], { [field] = value }), "no such row"))
	elseif sub == "delete" then
		self:Reply(caller, if DB:Delete(tableName, args[3]) then "Deleted." else "No such row.")
	else
		error("expected tables, select, get, set or delete", 0)
	end
end)

add("maxhealth", 2, ".maxhealth <amount> [player]", function(self, caller, args)
	local h = humanoid(targetOrSelf(args, 2, caller))
	h.MaxHealth = assert(tonumber(args[1]), "expected an amount")
	h.Health = h.MaxHealth
end)

-- discipline

add("mute", 1, ".mute <player> <minutes> [reason]", function(self, caller, args)
	local other = findPlayer(args[1])
	local until_ = os.time() + assert(tonumber(args[2]), "expected minutes") * 60
	local session = self.includes.Security["Session.h"]:Get(other)
	if session then
		session.MutedUntil = until_
	end
	self.includes.Database["AuthDatabase.h"]:Edit(other.UserId, function(account)
		account.MutedUntil = until_
	end)
	self:Reply(other, ("You have been muted for %s. %s"):format(minutes(until_ - os.time()), table.concat(args, " ", 3)))
	self:Reply(caller, other.Name .. " muted.")
end)

add("unmute", 1, ".unmute <player>", function(self, caller, args)
	local other = findPlayer(args[1])
	local session = self.includes.Security["Session.h"]:Get(other)
	if session then
		session.MutedUntil = 0
	end
	self.includes.Database["AuthDatabase.h"]:Edit(other.UserId, function(account)
		account.MutedUntil = nil
	end)
	self:Reply(other, "You have been unmuted.")
end)

add("kick", 1, ".kick <player> [reason]", function(self, caller, args)
	local userId, name = resolveUserId(args[1])
	local reason = table.concat(args, " ", 2)
	local online = Players:GetPlayerByUserId(userId)
	if online then
		online:Kick(reason)
	end
	self.includes.System["Global.h"]:Publish("KICK", { UserId = userId, Reason = reason })
	self:Reply(caller, ("Kicked %s everywhere."):format(name))
end)

add("ban", 2, ".ban <player> [reason]", function(self, caller, args)
	local userId, name = resolveUserId(args[1])
	local reason = table.concat(args, " ", 2)
	self.includes.Database["AuthDatabase.h"]:Ban(userId, reason, caller)
	self.includes.System["Global.h"]:Publish("KICK", { UserId = userId, Reason = "Banned: " .. reason })
	self:Reply(caller, ("Banned %s everywhere."):format(name))
end)

add("buff", 2, ".buff <all|player> <speed|jump> <multiplier> <seconds>", function(self, caller, args)
	local effect, mult, seconds = args[2], tonumber(args[3]), tonumber(args[4])
	assert(self.includes.Entities["EntityPlayer.h"].BUFFS[effect or ""], "effect is speed or jump")
	assert(mult and seconds, "expected a multiplier and seconds")
	local target = if args[1] == "all" then "all" else findPlayer(args[1]).Name
	self:ApplyBuff(target, effect, mult, seconds)
	self.includes.System["Global.h"]:Publish("BUFF", { Target = target, Effect = effect, Mult = mult, Seconds = seconds })
	self:Reply(caller, ("%s x%s on %s for %ds, all servers."):format(effect, mult, target, seconds))
end)

add("unban", 2, ".unban <userId>", function(self, caller, args)
	self.includes.Database["AuthDatabase.h"]:Unban(assert(tonumber(args[1]), "expected a UserId"))
	self:Reply(caller, "Unbanned " .. args[1])
end)

add("role", 4, ".role <player> <PLAYER|MODERATOR|GAMEMASTER|OWNER>", function(self, caller, args)
	local RBAC = self.includes.Security["RBAC_Permissions.h"]
	local other = findPlayer(args[1])
	local level = assert(RBAC:Parse(args[2] or ""), "unknown role")
	self.includes.Database["AuthDatabase.h"]:SetRole(other.UserId, level)
	local session = self.includes.Security["Session.h"]:Get(other)
	if session then
		session.Role = level
	end
	self:Reply(caller, ("%s is now %s"):format(other.Name, RBAC:GetRoleName(level)))
end)

-- world

add("announce", 2, ".announce <text>", function(self, caller, args)
	local text = table.concat(args, " ")
	self.includes.Security["Packet.h"]:Broadcast(Opcodes.SMSG_NOTIFICATION, { Text = text })
	self.includes.System["Global.h"]:Publish("ANNOUNCE", { Text = text })
end)

add("save", 2, ".save [player]", function(self, caller, args)
	self.includes.Entities["EntityPlayer.h"]:Save(targetOrSelf(args, 1, caller))
	self.includes.Database["Database.h"]:FlushAll()
	self:Reply(caller, "Saved.")
end)

add("saveall", 2, ".saveall", function(self, caller)
	for _, player in Players:GetPlayers() do
		self.includes.Entities["EntityPlayer.h"]:Save(player)
	end
	self.includes.Database["Database.h"]:FlushAll()
	self:Reply(caller, "All players saved.")
end)

-- plumbing

function module:ApplyBuff(target: string, effect: string, mult: number, seconds: number)
	local Entities = self.includes.Entities["EntityPlayer.h"]
	for _, player in Players:GetPlayers() do
		if target == "all" or player.Name == target then
			if Entities:Buff(player, effect, mult, seconds) then
				self:Reply(player, ("%s %s x%s for %ds."):format(if mult >= 1 then "Buff:" else "Debuff:", effect, mult, seconds))
			end
		end
	end
end

-- Reactions to the other servers.
function module:Start()
	local Global = self.includes.System["Global.h"]
	Global:On("ANNOUNCE", function(data)
		self.includes.Security["Packet.h"]:Broadcast(Opcodes.SMSG_NOTIFICATION, { Text = tostring(data.Text) })
	end)
	Global:On("KICK", function(data)
		local online = Players:GetPlayerByUserId(tonumber(data.UserId) or 0)
		if online then
			online:Kick(tostring(data.Reason or ""))
		end
	end)
	Global:On("BUFF", function(data)
		self:ApplyBuff(tostring(data.Target), tostring(data.Effect), tonumber(data.Mult) or 1, tonumber(data.Seconds) or 0)
	end)
end

add("aura", 2, ".aura <spell id> [player] | .unaura <spell id|all> [player]", function(self, caller, args)
	local Spells = self.includes.Spells["Spells.h"]
	local target = targetOrSelf(args, 2, caller)
	local spell = assert(Spells:Template(assert(tonumber(args[1]), "expected a spell id")), "no such spell")
	assert(spell.aura, "that spell has no aura")
	self.includes.Spells["Auras.h"]:Apply(caller, target, spell, Spells:Amount(spell, target:GetAttribute("CharacterLevel") or 1, caller))
	self:Reply(caller, "Done.")
end)

add("unaura", 2, ".unaura <spell id|all> [player]", function(self, caller, args)
	local target = targetOrSelf(args, 2, caller)
	if args[1] == "all" then
		self.includes.Spells["Auras.h"]:Clear(target)
	else
		self.includes.Spells["Auras.h"]:Remove(target, assert(tonumber(args[1]), "expected a spell id or all"))
	end
	self:Reply(caller, "Done.")
end)

add("skill", 2, ".skill learn <name> [player] | .skill set <name> <value> [player] | .skill unlearn <name> [player] | .skill list", function(self, caller, args)
	local Skills = self.includes.Spells["Skills.h"]
	local sub = args[1]
	if sub == "list" then
		for _, line in self.includes.Database["WorldDB.h"]:Select("skill_line") do
			self:Reply(caller, ("  %s (%s)"):format(line.name, line.kind))
		end
		return
	end
	local name = assert(args[2], "expected a skill name")
	if sub == "learn" then
		Skills:Learn(targetOrSelf(args, 3, caller), name, true)
	elseif sub == "unlearn" then
		Skills:Unlearn(targetOrSelf(args, 3, caller), name)
	elseif sub == "set" then
		local target = targetOrSelf(args, 4, caller)
		local line = assert(Skills:ByName(name), "no such skill")
		local entity = self.includes.Entities["EntityPlayer.h"]:Get(target)
		local skill = entity and entity.Active and entity.Active.Skills and entity.Active.Skills[tostring(line.id)]
		assert(skill, "they do not know that skill")
		skill.Value = math.clamp(assert(tonumber(args[3]), "expected a value"), 1, skill.Max)
		Skills:Sync(target)
	else
		error("expected learn, set, unlearn or list", 0)
	end
	self:Reply(caller, "Done.")
end)

add("talent", 2, ".talent reset [player] | .talent points <n> [player]", function(self, caller, args)
	local Talents = self.includes.Spells["Talents.h"]
	if args[1] == "reset" then
		local target = targetOrSelf(args, 2, caller)
		local entity = self.includes.Entities["EntityPlayer.h"]:Get(target)
		if entity and entity.Active then
			entity.Active.Talents = {}
			self.includes.Entities["EntityPlayer.h"]:ApplyStats(target)
			Talents:Sync(target)
		end
	elseif args[1] == "points" then
		local target = targetOrSelf(args, 3, caller)
		self:Reply(caller, ("%d point(s) free"):format(Talents:Points(target)))
		return
	else
		error("expected reset or points", 0)
	end
	self:Reply(caller, "Done.")
end)

add("rep", 2, ".rep <faction id> <amount> [player] | .rep list [player]", function(self, caller, args)
	local Reputation = self.includes.Social["Reputation.h"]
	if args[1] == "list" then
		for _, row in Reputation:List(targetOrSelf(args, 2, caller)) do
			self:Reply(caller, ("  %s: %s (%d) %s"):format(tostring(row.Id), row.Name, row.Value, row.Standing))
		end
		return
	end
	Reputation:Modify(targetOrSelf(args, 3, caller), assert(tonumber(args[1]), "expected a faction id"), assert(tonumber(args[2]), "expected an amount"))
	self:Reply(caller, "Done.")
end)

add("achievement", 2, ".achievement add <id> [player] | .achievement list", function(self, caller, args)
	local Achievements = self.includes.Social["Achievements.h"]
	if args[1] == "list" then
		for _, row in self.includes.Database["WorldDB.h"]:Select("achievement") do
			self:Reply(caller, ("  %s: %s"):format(tostring(row.id), row.name))
		end
		return
	elseif args[1] == "add" then
		local row = assert(self.includes.Database["WorldDB.h"]:Get("achievement", tonumber(args[2]) or 0), "no such achievement")
		Achievements:Award(targetOrSelf(args, 3, caller), row)
	else
		error("expected add or list", 0)
	end
	self:Reply(caller, "Done.")
end)

add("taxi", 2, ".taxi node add <name> [cost] | .taxi path <from id> <to id> [cost] | .taxi list | .taxi learn all [player]", function(self, caller, args)
	local Taxi = self.includes.Content["Taxi.h"]
	if args[1] == "node" and args[2] == "add" then
		local name = assert(args[3], "expected a name")
		local node = Taxi:AddNode(name, assert(caller.Character, "you have no character"):GetPivot().Position, tonumber(args[4]))
		self:Reply(caller, ("Node %s %s added here."):format(tostring(node.id), name))
	elseif args[1] == "path" then
		Taxi:Connect(assert(tonumber(args[2]), "expected a node id"), assert(tonumber(args[3]), "expected a node id"), tonumber(args[4]))
		self:Reply(caller, "Path added both ways.")
	elseif args[1] == "list" then
		for _, node in self.includes.Database["WorldDB.h"]:Select("taxi_nodes") do
			self:Reply(caller, ("  %s: %s (%.0f %.0f %.0f)"):format(tostring(node.id), node.name, node.x, node.y, node.z))
		end
	elseif args[1] == "learn" then
		local target = targetOrSelf(args, 3, caller)
		for _, node in self.includes.Database["WorldDB.h"]:Select("taxi_nodes") do
			Taxi:Discover(target, node)
		end
		self:Reply(caller, "Done.")
	else
		error("expected node add, path, list or learn", 0)
	end
end)

add("mount", 2, ".mount [player] | .dismount [player]", function(self, caller, args)
	local target = targetOrSelf(args, 1, caller)
	local spell = assert(self.includes.Spells["Spells.h"]:ByName("Summon Brown Horse"), "no mount spell")
	self.includes.Spells["Auras.h"]:Apply(target, target, spell, 0)
	self:Reply(caller, "Done.")
end)

add("dismount", 2, ".dismount [player]", function(self, caller, args)
	self.includes.Spells["Auras.h"]:RemoveKind(targetOrSelf(args, 1, caller), "mount")
	self:Reply(caller, "Done.")
end)

add("event", 2, ".event list | .event info <id>", function(self, caller, args)
	local GameEvents = self.includes.Zones["GameEvents.h"]
	if args[1] == "list" then
		for _, event in self.includes.Database["WorldDB.h"]:Select("game_event") do
			self:Reply(caller, ("  %s: %s %s"):format(tostring(event.id), event.name, if GameEvents:IsActive(event) then "(active)" else ""))
		end
	elseif args[1] == "info" then
		local event = assert(self.includes.Database["WorldDB.h"]:Get("game_event", tonumber(args[2]) or 0), "no such event")
		self:Reply(caller, ("%s: %s. Every %d min for %d min, xp x%s. %s"):format(event.name, event.description or "", event.occurrence or 0, event.length or 0, tostring(event.xp_mult or 1), if GameEvents:IsActive(event) then "Active now." else "Not active."))
	else
		error("expected list or info", 0)
	end
end)

add("pet", 2, ".pet <creature entry> [player] | .pet dismiss [player]", function(self, caller, args)
	local Pets = self.includes.Content["Pets.h"]
	if args[1] == "dismiss" then
		Pets:Dismiss(targetOrSelf(args, 2, caller))
	else
		local entry = assert(tonumber(args[1]), "expected a creature entry or dismiss")
		assert(self.includes.Content["Creatures.h"]:Template(entry), "no such creature")
		assert(Pets:Summon(targetOrSelf(args, 2, caller), entry), "could not summon")
	end
	self:Reply(caller, "Done.")
end)

add("bg", 2, ".bg create <name> [minlevel] | .bg spawn <id> Alliance|Horde | .bg flag <id> Alliance|Horde | .bg list | .bg leave [player]", function(self, caller, args)
	local Battleground = self.includes.Combat["Battleground.h"]
	local sub = args[1]
	if sub == "create" then
		local row = Battleground:Create(assert(args[2], "expected a name"), tonumber(args[3]))
		self:Reply(caller, ("Battleground %s created with id %s. Set both spawns and both flags."):format(row.name, tostring(row.id)))
	elseif sub == "spawn" or sub == "flag" then
		local faction = args[3]
		assert(faction == "Alliance" or faction == "Horde", "expected Alliance or Horde")
		Battleground:SetPoint(assert(tonumber(args[2]), "expected a battleground id"), sub, faction, assert(caller.Character, "you have no character"):GetPivot())
		self:Reply(caller, ("%s %s set here."):format(faction, sub))
	elseif sub == "list" then
		for _, row in self.includes.Database["WorldDB.h"]:Select("battleground_template") do
			local ready = row.spawn and row.flag and row.spawn.Alliance and row.spawn.Horde and row.flag.Alliance and row.flag.Horde
			self:Reply(caller, ("  %s: %s (level %d) %s"):format(tostring(row.id), row.name, row.minlevel or 1, if ready then "ready" else "incomplete"))
		end
	elseif sub == "leave" then
		Battleground:Leave(targetOrSelf(args, 2, caller))
		self:Reply(caller, "Done.")
	else
		error("expected create, spawn, flag, list or leave", 0)
	end
end)

add("honor", 2, ".honor add <amount> [player]", function(self, caller, args)
	assert(args[1] == "add", "expected add")
	local target = targetOrSelf(args, 3, caller)
	local entity = self.includes.Entities["EntityPlayer.h"]:Get(target)
	local char = assert(entity and entity.Active, "no character")
	char.Honor = (char.Honor or 0) + assert(tonumber(args[2]), "expected an amount")
	target:SetAttribute("Honor", char.Honor)
	self:Reply(caller, "Done.")
end)

function module:Reply(player: Player, text: string)
	self.includes.Chat["Chat.h"]:System(player, text)
end

-- Tell every client how to draw this GM (tag, visibility).
function module:BroadcastState(player: Player)
	local session = self.includes.Security["Session.h"]:Get(player)
	if session then
		self.includes.Security["Packet.h"]:Broadcast(Opcodes.SMSG_GM_STATE,
			{ Name = player.Name, Gm = session.Gm, Invisible = session.Invisible })
	end
end

-- Bring a newcomer up to date on every GM that is tagged or hidden.
function module:SyncState(player: Player)
	local Session = self.includes.Security["Session.h"]
	for _, other in Players:GetPlayers() do
		local session = Session:Get(other)
		if session and (session.Gm or session.Invisible) then
			self.includes.Security["Packet.h"]:Send(player, Opcodes.SMSG_GM_STATE,
				{ Name = other.Name, Gm = session.Gm, Invisible = session.Invisible })
		end
	end
end

-- line is the chat message without its leading dot.
function module:Run(caller: Player, line: string)
	local RBAC = self.includes.Security["RBAC_Permissions.h"]
	if RBAC:GetRole(caller) < RBAC.ROLES.MODERATOR then
		return self:Reply(caller, "There is no such command")
	end
	local args = line:split(" ")
	local name = table.remove(args, 1):lower()
	name = ALIASES[name] or name
	local command = commands[name]
	if not command then
		return self:Reply(caller, "There is no such command. Try .help")
	end
	if args[1] == "help" then
		return self:Usage(caller, name)
	end
	if not RBAC:HasLevel(caller, command.level) then
		return self:Reply(caller, "You do not have permission for ." .. name)
	end
	local ok, err = pcall(command.run, self, caller, args)
	if not ok then
		self:Reply(caller, ("%s\nUsage: %s"):format((tostring(err):gsub("^.-:%d+: ", "")), command.usage))
	end
end

return Base(module, {
	{ Path = "Auth/Security", Imports = "RBAC_Permissions.h|Session.h|Packet.h" },
	{ Path = "Auth/Entities", Imports = "EntityPlayer.h" },
	{ Path = "Auth/Database", Imports = "AuthDatabase.h" },
	{ Path = "Auth/Chat", Imports = "Chat.h" },
	{ Path = "Auth/Support", Imports = "Tickets.h" },
	{ Path = "World/Zones", Imports = "Zones.h|GameEvents.h" },
	{ Path = "World/Movement", Imports = "Anticheat.h" },
	{ Path = "World/Combat", Imports = "Death.h|Battleground.h" },
	{ Path = "World/Quests", Imports = "Quests.h" },
	{ Path = "World/Spells", Imports = "Spells.h|Auras.h|Skills.h|Talents.h" },
	{ Path = "Auth/Social", Imports = "Reputation.h|Achievements.h" },
	{ Path = "World/Content", Imports = "Teleports.h|GameObjects.h|Creatures.h|Taxi.h|Pets.h" },
	{ Path = "World/Database", Imports = "WorldDB.h|WorldDatabase.h" },
	{ Path = "Global/Database", Imports = "Database.h" },
	{ Path = "Global/System", Imports = "Global.h" },
})
