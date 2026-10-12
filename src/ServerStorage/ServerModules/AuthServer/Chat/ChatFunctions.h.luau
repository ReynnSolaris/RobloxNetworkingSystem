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
function module:Example(std:Example_Variable)
	
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
