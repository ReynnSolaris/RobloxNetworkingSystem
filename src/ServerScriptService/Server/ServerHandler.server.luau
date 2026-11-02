local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)

-- Players spawn after they authenticate. Chat delivery is ours too; the project
-- file turns off TextChatService's default channels and commands.
Players.CharacterAutoLoads = false

local ServerModules = ServerStorage:WaitForChild("ServerModules")
local Compiler = require(ServerModules.GlobalModules.System["Compiler.h"])()

-- Mirror the folder tree into tables of module instances, then resolve includes.
local function load(folder: Instance, into)
	for _, child in folder:GetChildren() do
		if child:IsA("Folder") then
			into[child.Name] = {}
			load(child, into[child.Name])
		elseif child:IsA("ModuleScript") then
			into[child.Name] = Compiler:Load(child)
		end
	end
	return into
end

local function resolve(tree)
	for _, value in tree do
		if rawget(value, "includes") ~= nil then
			Compiler:Resolve(value)
		else
			resolve(value)
		end
	end
end

local Auth = load(ServerModules.AuthServer, {})
local World = load(ServerModules.WorldServer, {})
local Global = load(ServerModules.GlobalModules, {})
resolve(Auth)
resolve(World)
resolve(Global)

local Packet = Auth.Security["Packet.h"]
local Session = Auth.Security["Session.h"]
local Entities = Auth.Entities["EntityPlayer.h"]
local Chat = Auth.Chat["Chat.h"]
local Commands = Auth.Security["Commands.h"]
local Zones = World.Zones["Zones.h"]
local Tickets = Auth.Support["Tickets.h"]
local Party = Auth.Social["Party.h"]
local Anticheat = World.Movement["Anticheat.h"]
local Characters = World.Characters["Characters.h"]
local WorldDB = World.Database["WorldDB.h"]
local GameObjects = World.Content["GameObjects.h"]
local Creatures = World.Content["Creatures.h"]
local Bus = Global.System["Global.h"]
local Database = Global.Database["Database.h"]

Bus:Start()
Packet:Start()
Session:Start()
Chat:Start()
Zones:Start()
Tickets:Start()
Commands:Start()
Party:Start()
Anticheat:Start()
Characters:Start()
WorldDB:Start()
GameObjects:Start()
Creatures:Start()
Session:OnAuthed(function(player)
	Characters:Enum(player)
	Commands:SyncState(player)
end)

-- Both loads yield on DataStores. The entity goes first so a session never exists
-- without one, and a player who left mid-load is cleaned up instead of leaking.
local function join(player: Player)
	Entities:Add(player)
	local session = player.Parent == Players and Session:Open(player)
	if not session or player.Parent ~= Players then
		Entities:Remove(player)
		Session:Close(player)
	end
end
Players.PlayerAdded:Connect(join)
for _, player in Players:GetPlayers() do
	join(player)
end
Players.PlayerRemoving:Connect(function(player)
	Entities:Remove(player)
	Session:Close(player)
end)

local function saveAll()
	for _, player in Players:GetPlayers() do
		Entities:Save(player)
	end
	Database:FlushAll()
end
task.spawn(function()
	while true do
		task.wait(Config.AutosaveSeconds)
		saveAll()
	end
end)
game:BindToClose(saveAll)

-- Other server scripts reach the loaded modules through this.
local reference = script.Parent:FindFirstChild("Server_Reference") or Instance.new("BindableFunction")
reference.Name = "Server_Reference"
reference.Parent = script.Parent
reference.OnInvoke = function(entry: string)
	return if entry == "GLOBAL" then Global elseif entry == "WORLD" then World else Auth
end
