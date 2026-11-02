return table.freeze({
	Build = 1, -- client must send the same build to authenticate

	Owners = {}, -- UserIds that get the OWNER role besides the place creator

	RateLimit = { PerSecond = 20, Burst = 40 },
	Chat = { MaxLength = 255, Cooldown = 0.5, SayRange = 30, YellRange = 100 },

	Spawn = CFrame.new(0, 5, 0),
	RespawnDelay = 3,
	AutosaveSeconds = 120,
})
