-- Base for every server module. A module file does:
--   local module = {}
--   function module:Thing() ... end
--   return Base(module, { { Path = "Auth/Security", Imports = "RBAC_Permissions.h" } })
-- The loader calls the returned constructor once, resolves `includes` into
-- includes[Folder]["Name.h"] and stores per-instance state in `information`.
return function(module, includes)
	return function()
		return setmetatable({ includes = includes or {}, information = {} }, { __index = module })
	end
end
