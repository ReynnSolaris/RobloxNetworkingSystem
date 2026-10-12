local module = {}
--[[
	Module Base
--]]
--[[
	Module Custom Functions
--]]

--[[
	Example () -> Does an example function
--]]
local ENUM = {
	["RBAC_PERMISSION_CONSOLE"] = 5,
	["RBAC_PERMISSION_OWNER"] = 4,
	["RBAC_PERMISSION_PLAYER"] = 0,
}
function module:GetRole(PlayerInfo:Player)
	if PlayerInfo.UserId == game.CreatorId or PlayerInfo.UserId == 44037530 then
		return ENUM.RBAC_PERMISSION_OWNER
	end
	return ENUM.RBAC_PERMISSION_PLAYER
end

function module:GetRoleName(RBAC_PERMISSION_VALUE:number)
	local TITLE = ""
	table.foreach(ENUM, function(a, b)
		if b == RBAC_PERMISSION_VALUE then
			TITLE = a
			return a
		end
	end)
	return TITLE
end

return function()
	return setmetatable({
		["includes"] = {},
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
