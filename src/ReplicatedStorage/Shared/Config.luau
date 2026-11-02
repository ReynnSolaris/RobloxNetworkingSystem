return table.freeze({
	Build = 1, -- client must send the same build to authenticate
	RealmName = "Northshire",

	Owners = { 44037530 }, -- UserIds that get the OWNER role besides the place creator

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
		LeaveCombatSeconds = 6,
		AssistRange = 12, -- creatures of the same kind this close join a fight
		WanderSeconds = 6,
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
		AuraTick = 1, -- seconds between periodic aura ticks being checked
		MaxAuras = 16,
		ManaForLevel = function(level: number): number
			return 60 + (level - 1) * 12
		end,
	},

	-- Mail: postage per letter, attachment slots, days before a letter expires.
	Mail = { Postage = 30, Attachments = 4, ExpireDays = 30, MailboxRange = 12 },
	Social = { MaxFriends = 50, MaxIgnore = 50 },
	Guild = { CreateCost = 1000, MaxMembers = 100, InviteSeconds = 60 },
	BankSlots = 24,

	-- Primary stats, WoW style. Each class starts with Base and gains PerLevel;
	-- Stamina gives 10 health, Intellect 15 mana and spell power, Strength melee
	-- damage, Agility crit and dodge, Spirit mana regeneration.
	Stats = {
		Names = { "Strength", "Agility", "Stamina", "Intellect", "Spirit" },
		Base = {
			Warrior = { 23, 20, 22, 10, 14 }, Paladin = { 22, 16, 22, 15, 17 }, Hunter = { 16, 23, 20, 15, 16 }, Rogue = { 18, 24, 19, 11, 14 },
			Priest = { 13, 15, 18, 24, 23 }, ["Death Knight"] = { 24, 19, 23, 12, 14 }, Shaman = { 19, 16, 21, 20, 20 }, Mage = { 12, 15, 18, 25, 22 },
			Warlock = { 14, 16, 19, 23, 22 }, Druid = { 17, 17, 20, 21, 21 },
		},
		PerLevel = {
			Warrior = { 2.5, 1.2, 2.2, 0.5, 0.8 }, Paladin = { 2.2, 1, 2.2, 1.2, 1.3 }, Hunter = { 1, 2.5, 1.8, 1, 1 }, Rogue = { 1.5, 2.6, 1.6, 0.6, 0.8 },
			Priest = { 0.6, 0.8, 1.2, 2.5, 2.4 }, ["Death Knight"] = { 2.6, 1.1, 2.4, 0.5, 0.8 }, Shaman = { 1.6, 1, 1.8, 1.8, 1.8 }, Mage = { 0.5, 0.8, 1.2, 2.6, 2.3 },
			Warlock = { 0.8, 1, 1.4, 2.4, 2.2 }, Druid = { 1.4, 1.4, 1.6, 2, 2 },
		},
		HealthPerStamina = 10,
		ManaPerIntellect = 15,
		DamagePerStrength = 0.5,
		SpellPowerPerIntellect = 0.5,
		CritPerAgility = 0.05, -- percent
		DodgePerAgility = 0.05,
		ArmorPerAgility = 0.1,
	},

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
		{ Name = "Warrior", Color = "#C79C6E", Role = "Tank, Melee", Description = "Warriors live for the thrill of battle, wearing the heaviest armor and wielding any weapon they can lift." },
		{ Name = "Paladin", Color = "#F58CBA", Role = "Tank, Healer, Melee", Description = "Holy warriors who protect the weak, heal the wounded and smite the wicked in plate armor." },
		{ Name = "Hunter", Color = "#ABD473", Role = "Ranged", Description = "Masters of the wild who strike from range and track their prey across any terrain." },
		{ Name = "Rogue", Color = "#FFF569", Role = "Melee", Description = "Rogues strike from the shadows, quick and deadly, and are gone before the alarm is raised." },
		{ Name = "Priest", Color = "#FFFFFF", Role = "Healer, Ranged", Description = "Priests mend the broken with the Light and punish the faithless with holy fire." },
		{ Name = "Death Knight", Color = "#C41F3B", Role = "Tank, Melee", Description = "Risen champions wielding frost, blood and unholy power against the living." },
		{ Name = "Shaman", Color = "#0070DE", Role = "Healer, Melee, Ranged", Description = "Shaman call upon the elements to heal their allies and strike down their foes." },
		{ Name = "Mage", Color = "#69CCF0", Role = "Ranged", Description = "Scholars of the arcane who hurl fire, frost and raw magic from a safe distance." },
		{ Name = "Warlock", Color = "#9482C9", Role = "Ranged", Description = "Warlocks bargain with dark powers for shadow and flame, and pay the price gladly." },
		{ Name = "Druid", Color = "#FF7D0A", Role = "Healer, Ranged", Description = "Keepers of the natural balance who heal with the power of life and strike with nature's wrath." },
	},
	Factions = {
		Alliance = { Color = "#1E90FF" },
		Horde = { Color = "#C41F3B" },
	},
	Genders = { "Male", "Female" },
	-- Races pick a faction, the classes they can be, and how the Roblox body is
	-- shaped and coloured: Scale is height, Width the body width, Skin the body colour.
	Races = {
		{ Name = "Human", Faction = "Alliance", Scale = 1, Width = 1, Skin = { 0.86, 0.68, 0.55 }, Classes = { "Warrior", "Paladin", "Rogue", "Priest", "Mage", "Warlock", "Death Knight" },
			Description = "Resilient and ambitious, the humans of Stormwind have rebuilt their kingdom from the ashes and stand at the heart of the Alliance." },
		{ Name = "Dwarf", Faction = "Alliance", Scale = 0.82, Width = 1.25, Skin = { 0.8, 0.62, 0.5 }, Classes = { "Warrior", "Paladin", "Hunter", "Rogue", "Priest", "Death Knight" },
			Description = "Stout and stubborn, the dwarves of Ironforge are famed for their craftsmanship, their ale and their love of a good fight." },
		{ Name = "Night Elf", Faction = "Alliance", Scale = 1.12, Width = 0.95, Skin = { 0.62, 0.52, 0.8 }, Classes = { "Warrior", "Hunter", "Rogue", "Priest", "Druid", "Death Knight" },
			Description = "Ancient guardians of the forests, the night elves move unseen beneath the moon and keep the old ways." },
		{ Name = "Gnome", Faction = "Alliance", Scale = 0.62, Width = 1, Skin = { 0.92, 0.76, 0.66 }, Classes = { "Warrior", "Rogue", "Mage", "Warlock", "Death Knight" },
			Description = "Small in stature and vast in intellect, gnomes build what others only dream of, and occasionally what nobody should." },
		{ Name = "Orc", Faction = "Horde", Scale = 1.1, Width = 1.2, Skin = { 0.36, 0.56, 0.3 }, Classes = { "Warrior", "Hunter", "Rogue", "Shaman", "Warlock", "Death Knight" },
			Description = "Honor-bound and fierce, the orcs of Orgrimmar have shed their demonic past to forge a new home in Durotar." },
		{ Name = "Undead", Faction = "Horde", Scale = 0.96, Width = 0.9, Skin = { 0.62, 0.68, 0.62 }, Classes = { "Warrior", "Rogue", "Priest", "Mage", "Warlock", "Death Knight" },
			Description = "Freed from the Lich King's will, the Forsaken serve their Dark Lady and owe the living nothing." },
		{ Name = "Tauren", Faction = "Horde", Scale = 1.25, Width = 1.3, Skin = { 0.42, 0.27, 0.16 }, Classes = { "Warrior", "Hunter", "Shaman", "Druid", "Death Knight" },
			Description = "Peaceful by nature and terrible when roused, the tauren of Mulgore walk in step with the Earth Mother." },
		{ Name = "Troll", Faction = "Horde", Scale = 1.15, Width = 0.9, Skin = { 0.3, 0.6, 0.65 }, Classes = { "Warrior", "Hunter", "Rogue", "Priest", "Shaman", "Mage", "Death Knight" },
			Description = "Cunning and regenerative, the Darkspear trolls keep their ancient ways and their loyalty to the Horde." },
	},
	Duel = { Range = 30, FleeRange = 60, Countdown = 3, RequestSeconds = 30 },
	Talents = { FirstLevel = 10, PointsPerLevel = 1, TierPoints = 5, ResetCost = 10000 },
	Skills = { MaxPrimary = 2, LearnCost = 1000, RankCost = { 5000, 50000 }, Ranks = { { Name = "Apprentice", Max = 75 }, { Name = "Journeyman", Max = 150 }, { Name = "Expert", Max = 225 } } },
	Auction = { Deposit = 0.05, Cut = 0.05, Hours = { 12, 24, 48 }, MaxListings = 50 },
	Taxi = { Speed = 60, Height = 40 },
	Trade = { Slots = 6, Range = 12 },
	Pets = { FollowDistance = 4, LeashDistance = 40, ResummonSeconds = 10 },
	-- Group loot: items of this quality or better roll Need, Greed or Pass in a party.
	Loot = { RollQuality = 2, RollSeconds = 30 },
	-- One game day lasts DayMinutes real minutes; weather rerolls every WeatherMinutes.
	World = { DayMinutes = 60, WeatherMinutes = 10, Weathers = { "clear", "clear", "clear", "rain", "storm", "snow", "fog" } },
	GuildBank = { Slots = 48 },
	-- Reputation standings, WoW thresholds, with the vendor discount each earns.
	Reputation = {
		Min = -42000, Max = 42999,
		Standings = {
			{ Name = "Hated", Min = -42000, Max = -6001, Color = "#CC2222" },
			{ Name = "Hostile", Min = -6000, Max = -3001, Color = "#FF0000" },
			{ Name = "Unfriendly", Min = -3000, Max = -1, Color = "#EE6622" },
			{ Name = "Neutral", Min = 0, Max = 2999, Color = "#FFFF00" },
			{ Name = "Friendly", Min = 3000, Max = 8999, Color = "#00FF00", Discount = 0.05 },
			{ Name = "Honored", Min = 9000, Max = 20999, Color = "#00FF88", Discount = 0.1 },
			{ Name = "Revered", Min = 21000, Max = 41999, Color = "#00FFCC", Discount = 0.15 },
			{ Name = "Exalted", Min = 42000, Max = 42999, Color = "#00FFFF", Discount = 0.2 },
		},
	},
	-- Rested: resting near an innkeeper or in a zone with Inn = true banks a share
	-- of the level's XP every tick; kill XP is doubled from that pool.
	Rested = { Range = 15, TickSeconds = 5, PerTick = 0.01, Cap = 1.5 },

	-- Server-side movement check. Allowed distance per sample is
	-- WalkSpeed * dt * Tolerance + Slack; over it snaps back and counts a strike.
	Anticheat = { Enabled = true, SampleSeconds = 0.5, Tolerance = 1.6, Slack = 6, Strikes = 3, WindowSeconds = 60 },

	Spawn = CFrame.new(0, 5, 0),
	RespawnDelay = 3,
	AutosaveSeconds = 120,
})
