local ServerBase = script.Parent

local SS = game:GetService("ServerStorage")
local ServerModules = SS:WaitForChild("ServerModules")
local AuthServer, WorldServer, GlobalModules = ServerModules:WaitForChild("AuthServer"), ServerModules:WaitForChild("WorldServer"), ServerModules:WaitForChild("GlobalModules")

local AuthServerModules = {}
local WorldServerModules = {}
local GlobalServerModules = {}

local loadDependencies = function()
	local function Search(folder, last)
		for _,x in next, folder:GetChildren() do
			if not x:IsA'Folder' then
				if x:IsA'ModuleScript' then
					last[tostring(x)] = require(x)()
				else
					last[tostring(x)] = x.Value
				end
			else
				last[tostring(x)] = {}
				Search(x, last[tostring(x)])
			end
		end
	end
	print("================ LOADING AUTH SERVER ================")
	--[[
		Handle the auth-server (authentication service mod 1.0)
	--]]
	Search(AuthServer, AuthServerModules)
	print(AuthServerModules)
	print("================ LOADED AUTH SERVER ================")
	
	print("================ LOADING WORLD SERVER ================")
	--[[
		Handle the auth-server (authentication service mod 1.0)
	--]]
	Search(WorldServer, WorldServerModules)
	print(WorldServerModules)
	print("================ LOADED WORLD SERVER ================")
	
	print("================ LOADING GLOBAL MODULES ================")
	--[[
		Handle the auth-server (authentication service mod 1.0)
	--]]
	Search(GlobalModules, GlobalServerModules)
	print(GlobalServerModules)
	print("================ LOADED GLOBAL MODULES ================")
	--[[
		Handle the imports of the module scripts within the modules.
	--]]
	print("================ COMPILING IMPORTS ================")
	local CompilerService = GlobalServerModules["System"]["Compiler.h"]
	local function Import(mod)
		local StoredImports = {}
		for z, x in next, mod do
			if tostring(x) ~= "Compiler.h" then
				if x["includes"] ~= nil then
					if #x.includes ~= 0 then
						for _, import in next, x.includes do
							StoredImports[import.Path:split("/")[2]] = CompilerService:Import(x, import.Imports, import.Path)
							print(("Imported [%s] for [%s]"):format(import.Imports, tostring(z)))
						end
						x.includes = StoredImports
					end
				else
					Import(x)
				end
			end
		end
	end
	Import(AuthServerModules)
	Import(WorldServerModules)
	Import(GlobalServerModules)
	print("================ IMPORTS COMPILED ================")
end


loadDependencies()
local EntityPlayer = AuthServerModules["Entities"]["EntityPlayer.h"]

local DatabaseTest = GlobalServerModules["Database"]["Database.h"]:CreateDatabase("Debunked.")
--local Imported = CompilerService:Import(EntityPlayer, "Database.h|DatabaseUUID.h", "Global/Database")
--AuthServerModules["Chat"]["Chat.h"]:Test()
local Security = AuthServerModules["Security"]
local RBAC = Security["RBAC_Permissions.h"]
game.Players.PlayerAdded:Connect(function(Player)
	EntityPlayer:NewPlayerInstance(Player)
	Player.CharacterAdded:Connect(function(Character)
		Character:WaitForChild("Humanoid").Died:connect(function()
			wait(3)
			EntityPlayer:SpawnPlayer(Player, CFrame.new(0, 5, 0))
			Security["Packet.h"]:createPacket(Player, "SPAWN_EVENT", {
				["CFrame"] = CFrame.new(0, 5, 0),
				["PacketType"] = "Server",
			})
		end)
	end)
	EntityPlayer:SpawnPlayer(Player, CFrame.new(0, 5, 0))
	--wait(1)
	--EntityPlayer:Hurt(Player.Name, 25)
	Security["Packet.h"]:createPacket(Player, "SPAWN_EVENT", {
		["CFrame"] = CFrame.new(0, 5, 0),
		["PacketType"] = "Server",
	})
	local PlayerRBAC = EntityPlayer:GetPlayerInfo(Player.Name).RBAC
	if RBAC:GetRoleName(PlayerRBAC) == "RBAC_PERMISSION_OWNER" then
		EntityPlayer:GiveHat(Player.Name, 21070012)
	end
	
end)

ServerBase:WaitForChild("Server_Reference").OnInvoke = function(Entry:string)
	if Entry == "GLOBAL" then
		return GlobalServerModules
	elseif Entry == "WORLD" then
		return WorldServerModules
	else
		return AuthServerModules
	end
end