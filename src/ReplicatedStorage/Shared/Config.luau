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
			XP = "#7070FF",
			LOOT = "#00AA00",
			MONEY = "#FFD700",
			HIT = "#FFFF80",
			HURT = "#FF8080",
			QUEST = "#FFFF00",
			GUILD = "#40FB40",
		},
	},

	BagSlots = 16, -- the backpack
	QuestLogSize = 25,
	BuybackSlots = 12,

	-- Equipment slots, in character sheet order.
	Slots = { "head", "chest", "legs", "feet", "mainhand", "ring", "trinket" },
	VendorRange = 12,

	-- Item quality colours, WoW order: poor, common, uncommon, rare, epic, legendary.
	Quality = { [0] = "#9D9D9D", [1] = "#FFFFFF", [2] = "#1EFF00", [3] = "#0070DD", [4] = "#A335EE", [5] = "#FF8000" },

	Combat = {
		Range = 6, -- studs, melee
		SwingSeconds = 2,
		-- player melee: base plus per level, times 0.8 to 1.2
		Damage = function(level: number): number
			return 5 + level * 2
		end,
		-- kill experience: nothing once the creature is grey (five or more levels below)
		KillXp = function(playerLevel: number, creatureLevel: number): number
			if playerLevel - creatureLevel >= 5 then
				return 0
			end
			return 45 + creatureLevel * 5
		end,
		CorpseSeconds = 60, -- a lootable corpse waits this long; an emptied one clears sooner
		DefaultRespawn = 30,
		ReclaimRange = 25, -- studs from your corpse marker to resurrect
		GhostSpeed = 24,
	},

	-- Spells: twelve action buttons, a shared global cooldown, mana by level
	-- and regeneration as a fraction of max per second.
	Spells = {
		ActionButtons = 12,
		GlobalCooldown = 1.5,
		ManaRegen = 0.02,
		InterruptDistance = 1.5,
		ManaForLevel = function(level: number): number
			return 60 + (level - 1) * 12
		end,
	},

	-- Mail: postage per letter, attachment slots, days before a letter expires.
	Mail = { Postage = 30, Attachments = 4, ExpireDays = 30, MailboxRange = 12 },
	Social = { MaxFriends = 50, MaxIgnore = 50 },
	Guild = { CreateCost = 1000, MaxMembers = 100, InviteSeconds = 60 },
	BankSlots = 24,

	Xp = {
		MaxLevel = 80,
		Explore = 60, -- first visit to a zone, times the character's level
		ForLevel = function(level: number): number
			return math.floor(400 * level * (1 + level * 0.1))
		end,
		HealthForLevel = function(level: number): number
			return 100 + (level - 1) * 10
		end,
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
