local Base = require(game:GetService("ServerStorage").ServerModules["Template.h"])
local DataStoreService = game:GetService("DataStoreService")
local module = {}

local RETRIES = 3
local online = true

-- Retries with backoff. After a hard failure the whole service goes memory-only
-- instead of stalling every join. "Not allowed" (Studio without API access) is
-- final on the first try.
local function attempt(fn)
	if not online then
		return false, "offline"
	end
	local ok, result
	for i = 1, RETRIES do
		ok, result = pcall(fn)
		if ok then
			return true, result
		end
		if tostring(result):find("not allowed") then
			break
		end
		if i < RETRIES then
			task.wait(i)
		end
	end
	warn("[Database] going memory-only:", result)
	online = false
	return false, result
end

-- Open("Auth") -> store with Get/Set/Update/Flush. Values are cached per key;
-- Set only touches the cache, Flush (or FlushAll) writes to the DataStore.
-- If DataStores are unavailable (Studio without API access) it runs in memory.
function module:Open(name: string)
	if self.information[name] then
		return self.information[name]
	end

	local ok, dataStore = pcall(DataStoreService.GetDataStore, DataStoreService, name)
	if not ok then
		online = false
	end
	local cache, dirty, writing = {}, {}, {}
	local store = {}

	function store.Get(_, key: string, default: any)
		if cache[key] == nil and online then
			local got, value = attempt(function()
				return dataStore:GetAsync(key)
			end)
			if got and value ~= nil then
				cache[key] = value
			end
		end
		if cache[key] == nil and default ~= nil then
			cache[key] = default
		end
		return cache[key]
	end

	function store.Set(_, key: string, value: any)
		cache[key] = value
		dirty[key] = true
	end

	function store.Update(_, key: string, fn: (any) -> any)
		store:Set(key, fn(store:Get(key)))
	end

	-- PlayerRemoving and BindToClose both flush at shutdown; one write per key.
	function store.Flush(_, key: string)
		if not dirty[key] or not online or writing[key] then
			return not dirty[key]
		end
		writing[key] = true
		local saved = attempt(function()
			dataStore:SetAsync(key, cache[key])
		end)
		writing[key] = nil
		if saved then
			dirty[key] = nil
		end
		return saved
	end

	-- Read-modify-write against the live store (UpdateAsync), for records every
	-- server edits. Falls back to the cache when offline.
	function store.Transform(_, key: string, fn: (any) -> any)
		if online then
			local ok, result = attempt(function()
				return dataStore:UpdateAsync(key, fn)
			end)
			if ok then
				cache[key] = result
				dirty[key] = nil
				return result
			end
		end
		cache[key] = fn(cache[key])
		return cache[key]
	end

	-- Drop the cached copy so the next Get reads the live value. In memory-only
	-- mode the cache is the only copy, so it stays.
	function store.Refresh(_, key: string)
		if online and not dirty[key] then
			cache[key] = nil
		end
	end

	function store.FlushAll(_)
		for key in dirty do
			store:Flush(key)
		end
	end

	function store.Forget(_, key: string)
		store:Flush(key)
		cache[key] = nil
	end

	self.information[name] = store
	return store
end

function module:FlushAll()
	for _, store in self.information do
		store:FlushAll()
	end
end

return Base(module)
