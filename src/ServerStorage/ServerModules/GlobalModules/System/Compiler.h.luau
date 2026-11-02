local Base = require(game:GetService("ServerStorage").ServerModules["Template.h"])
local module = {}

local ServerModules = game:GetService("ServerStorage"):WaitForChild("ServerModules")
local Roots = {
	Global = ServerModules:WaitForChild("GlobalModules"),
	Auth = ServerModules:WaitForChild("AuthServer"),
	World = ServerModules:WaitForChild("WorldServer"),
}

local cache: { [ModuleScript]: any } = {}

-- One instance per ModuleScript, so every importer shares the same state.
function module:Load(script: ModuleScript)
	if cache[script] == nil then
		cache[script] = require(script)()
	end
	return cache[script]
end

-- Import("Auth/Security", "RBAC_Permissions.h|Packet.h") -> { ["RBAC_Permissions.h"] = ..., ["Packet.h"] = ... }
function module:Import(path: string, names: string)
	local root, folder = table.unpack(path:split("/"))
	local parent = assert(Roots[root], "unknown root " .. tostring(root)):FindFirstChild(folder)
	assert(parent, ("no folder %s under %s"):format(folder, root))

	local out = {}
	for _, name in names:split("|") do
		local child = parent:FindFirstChild(name)
		assert(child and child:IsA("ModuleScript"), ("no module %s in %s"):format(name, path))
		out[name] = self:Load(child)
	end
	return out
end

-- Replace a module's include declarations with the resolved modules.
function module:Resolve(instance)
	local resolved = {}
	for _, include in instance.includes do
		local folder = include.Path:split("/")[2]
		resolved[folder] = resolved[folder] or {}
		for name, mod in self:Import(include.Path, include.Imports) do
			resolved[folder][name] = mod
		end
	end
	instance.includes = resolved
end

return Base(module)
