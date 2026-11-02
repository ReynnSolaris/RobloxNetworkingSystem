return table.freeze({
	Build = 1, -- client must send the same build to authenticate
	RealmName = "Northshire",

	Owners = {}, -- UserIds that get the OWNER role besides the place creator

	RateLimit = { PerSecond = 20, Burst = 40 },
	Chat = {
		MaxLength = 255,
		Cooldown = 0.5,
		SayRange = 30,
		YellRange = 100,
		-- Blizzard chat colours
		Colors = {
			SAY = "#FFFFFF",
			YELL = "#FF3F40",
			WHISPER = "#FF80FF",
			WORLD = "#FFC0C0",
			PARTY = "#AAAAFF",
			SYSTEM = "#FFFF00",
			GM = "#00C0FF",
			COMMAND = "#9D9D9D",
			EMOTE = "#FF8040",
		},
	},

	-- /wave etc. Text is shown to players in range, Anim is the R15 emote played.
	Emotes = {
		wave = { Text = "%s waves.", Anim = "wave" },
		dance = { Text = "%s bursts into dance.", Anim = "dance" },
		laugh = { Text = "%s laughs.", Anim = "laugh" },
		cheer = { Text = "%s cheers!", Anim = "cheer" },
		point = { Text = "%s points.", Anim = "point" },
	},

	ZonePollSeconds = 0.5,

	Party = { MaxSize = 5, InviteSeconds = 60 },

	-- Characters per account and the classes they can be, in Blizzard class colours.
	MaxCharacters = 3,
	Classes = {
		{ Name = "Warrior", Color = "#C79C6E" },
		{ Name = "Paladin", Color = "#F58CBA" },
		{ Name = "Hunter", Color = "#ABD473" },
		{ Name = "Rogue", Color = "#FFF569" },
		{ Name = "Priest", Color = "#FFFFFF" },
		{ Name = "Death Knight", Color = "#C41F3B" },
		{ Name = "Shaman", Color = "#0070DE" },
		{ Name = "Mage", Color = "#69CCF0" },
		{ Name = "Warlock", Color = "#9482C9" },
		{ Name = "Druid", Color = "#FF7D0A" },
	},

	-- Server-side movement check. Allowed distance per sample is
	-- WalkSpeed * dt * Tolerance + Slack; over it snaps back and counts a strike.
	Anticheat = { Enabled = true, SampleSeconds = 0.5, Tolerance = 1.6, Slack = 6, Strikes = 3, WindowSeconds = 60 },

	Spawn = CFrame.new(0, 5, 0),
	RespawnDelay = 3,
	AutosaveSeconds = 120,
})
