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
function module:Test()
	print(self.includes)
end

return function()
	return setmetatable({
		["includes"] = {
			{
				["Path"] = "Auth/Chat",
				["Imports"] = "ChatRegistry.h|ChatFunctions.h"
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
