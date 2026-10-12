local module = {}
--[[
	Module Base
--]]
--[[
	Module Custom Functions
--]]

--[[
	NewPlayerInstance() -> Creates a new static player instance.
--]]

function module:NewPlayerInstance(PlayerInstance:std)
	local _pN = tostring(PlayerInstance)
	if self["information"][_pN] then
		return false, self["information"][_pN]
	end
	self["information"][_pN] = {
		["Instance"] = PlayerInstance,
		["Character"] = nil
	}
	return true, self["information"][_pN]
end

--[[
	GetPlayer () -> Returns Player and sub-player information
--]]
function module:GetPlayer(PlayerName:std)
	if self["information"][PlayerName] then
		return true, self["information"][PlayerName]
	end
	return false
end

--[[
	GetPlayerInfo () -> Returns player information
--]]
function module:GetPlayerInfo(PlayerName:std) 
	local player = game.Players[tostring(PlayerName)]
	local got, inst = self:GetPlayer(tostring(player))
	local RBAC = self.includes.Security["RBAC_Permissions.h"]
	if got then
		return {
			["Name"] = PlayerName,
			["UserId"] = player.UserId,
			["Character"] = inst.Character,
			["RBAC"] = RBAC:GetRole(player)
		}
	end
	return {}
end

--[[
	SpawnPlayer () -> Spawns player at a given x cframe
--]]
function module:SpawnPlayer(PlayerInstance:std, CFrameLocation:CFrame)
	PlayerInstance:LoadCharacter()
	local CharacterInstance = PlayerInstance.Character
	CharacterInstance:SetPrimaryPartCFrame(CFrameLocation)
	local got, inst = self:GetPlayer(tostring(PlayerInstance))
	if got then
		inst.Character = CharacterInstance
	end
	return true
end

--[[
	Hurt () -> Do Damage to a player with extra tags.
--]]
function module:Hurt(PlayerName:string, Damage:number)
	local got, inst = self:GetPlayer(PlayerName)
	if got then
		local humanoid = inst.Character:FindFirstChild("Humanoid")
		if humanoid then
			humanoid:TakeDamage(Damage)
		end
	end
	return got
end
--[[
	GiveHat () -> Gives a hat based on RBX Catalog ID
--]]
function module:GiveHat(PlayerName:string, AssetId:number)
	local hat = game:GetService("InsertService"):LoadAsset(AssetId):GetChildren()[1]
	local got, inst = self:GetPlayer(PlayerName)
	if got then
		hat.Parent = inst.Character
	end
	return got
end

return function()
	return setmetatable({
		["includes"] = {
			{
				["Path"] = "Auth/Chat",
				["Imports"] = "Chat.h"
			}	,
			{
				["Path"] = "Auth/Security",
				["Imports"] = "RBAC_Permissions.h"
			}	
		},
		["information"] = {}
	}, {
		__index = function(self, index)
			if module[index] ~= nil then
				if typeof(module[index]) == "function" then
					return function(self, ...)
						return module[index](self, ...)
					end
				else
					return module[index]
				end
			end
		end,
	})
end
