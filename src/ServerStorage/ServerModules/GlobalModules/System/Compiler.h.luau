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
local ServerModules = game:GetService("ServerStorage"):WaitForChild("ServerModules")
function module:Import(ModuleScript:std, ImportName:std, Path:std)
	local Paths = {
		["Global"] = ServerModules:WaitForChild("GlobalModules"),
		["Auth"] = ServerModules:WaitForChild("AuthServer"),
		["World"] = ServerModules:WaitForChild("WorldServer")
	}
	local args = Path:split("/")
	local ToImport = {}
	local importString = ImportName:split("|")
	table.foreach(Paths[args[1]]:GetDescendants(), function(a, b)
		if b.Parent.Name == args[2] then
			table.foreach(importString, function(c, d)
				if b.Name == d then
					ToImport[#ToImport+1] = b
					return
				end
			end)
		end
	end)
	local ImportFinale = {}
	for _, x in next, ToImport do
		ImportFinale[tostring(x)] = require(x)()
	end
	return ImportFinale
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
