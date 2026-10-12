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
function module:CreateDatabase(DatabaseName:string, PresetData:{})
	self.information["Database"] = game:GetService("DataStoreService"):GetDataStore(DatabaseName)
	local UUID = self.includes.Database["DatabaseUUID.h"]:GenerateUUID(DatabaseName)
	print(("Database [%s] Loaded || UUID: [%s]"):format(DatabaseName, UUID))
end
 
return function()
	return setmetatable({
		["includes"] = {
			{
				["Path"] = "Global/Database",
				["Imports"] = "DatabaseUUID.h"
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
