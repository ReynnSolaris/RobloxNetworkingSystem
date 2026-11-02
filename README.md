# Roblox Networking System

A WoW 3.3.5a shaped server for Roblox: an auth server that owns sessions, roles and
accounts, a world server that owns character state, and one packet pipe between the
client and both. Started as a "can this be done in Roblox" experiment; this is the
fleshed-out version.

```
client ──(opcode, seq, data)──► ReplicatedStorage.Packets ──► Packet.h
                                                                 │ rate limit, sequence check, guard
                                                                 ▼
                                   Session.h ── auth handshake, state, role
                                   Chat.h ───── channels, filter, .commands
                                   EntityPlayer.h ── spawn, health, teleport, save
```

## Layout

```
src/ReplicatedStorage/Shared/      Opcodes, Config (shared by client and server)
src/ServerScriptService/Server/    ServerHandler: loads modules, wires everything, autosaves
src/ServerStorage/ServerModules/
  Template.h                       base every module is built on
  AuthServer/Security/             Packet, Session, RBAC_Permissions, Commands
  AuthServer/Database/             AuthDatabase (accounts, roles, bans)
  AuthServer/Entities/             EntityPlayer
  AuthServer/Chat/                 Chat, ChatRegistry, ChatFunctions
  AuthServer/Support/              Tickets
  AuthServer/Social/               Party
  WorldServer/Database/            WorldDatabase (the account's characters), WorldDB (TrinityCore-style tables)
  WorldServer/Characters/          Characters (enum, create, delete, login, logout)
  WorldServer/Zones/               Zones (which zone each player stands in), GameEvents (day and night, weather, timed events)
  WorldServer/Movement/            Anticheat (movement validation)
  WorldServer/Content/             Creatures (spawns, AI, spells, waypoints, loot), GameObjects (chests, doors, nodes, mailboxes),
                                   Items (templates, Describe), Vendors, Teleports, Auction (auction house), Taxi (flight paths), Trade,
                                   Pets (tame, summon, follow, attack)
  WorldServer/Combat/              Combat (units, damage, healing, rolls, melee), Loot (loot sources), Death (release, ghosts, corpses, spirit healers),
                                   Duel, Pvp (world PvP, honor)
  WorldServer/Quests/              Quests (templates, questgivers, gossip, objectives, rewards)
  WorldServer/Spells/              Spells (templates, casting, mana, cooldowns, trainers, item use, creature casts, ranks),
                                   Auras (DoTs, HoTs, stat buffs, slows, stuns, mounts), Talents, Skills (professions, crafting, gathering)
  WorldServer/Mail/                Mail (letters with money and items, mailboxes)
  AuthServer/Social/               Party, Social (friends, ignore, who, played, inspect, roll), Guild, Reputation, Achievements
src/ServerStorage/ObjectTemplates/                 models .gobject can place
src/ServerStorage/MountTemplates/                  mount bodies (Pony), see Forms, stances, mounts
src/ServerStorage/FormTemplates/                   shapeshift bodies, same format
  GlobalModules/Database/          Database (DataStore wrapper), DatabaseUUID
  GlobalModules/System/            Compiler (resolves module includes), Global (cross-server bus), Effects (particles)
src/ReplicatedStorage/Assets/Particles/            ParticleEmitters on Roblox's built-in textures
src/StarterPlayer/StarterPlayerScripts/            NetClient (the client half), CharacterSelect, PlayerFrame, TargetFrame,
                                                   ChatFrame, VendorFrame, BagFrame, CharacterSheet, LootFrame, DeathFrame,
                                                   QuestGiverFrame, QuestLogFrame (log on L, ! and ? markers),
                                                   ActionBar (1-9 0 - =, cast bar), SpellBook (P), TrainerFrame, SpellUi,
                                                   MailFrame (mailbox prompt), FriendsFrame (O: friends, ignore, guild), BankFrame,
                                                   BuffFrame (auras and the target's cast), TalentFrame (N), SkillFrame (K, professions
                                                   and the profession trainer), ReputationFrame (U), AchievementFrame (Y, toast),
                                                   AuctionFrame, TaxiFrame, TradeFrame, InspectFrame, PetFrame, RollFrame (Need, Greed, Pass),
                                   GuildBankFrame, Weather (rain, snow, fog over the camera), Flight (flying mount controller),
                                                   Preview (ViewportFrame character previews),
                                                   ZoneBanner, PartyFrame, Drag (drag and drop),
                                                   Ui (theme, tooltip), Components (Fusion panels, lists, buttons)
src/Workspace/Zones/                               demo zone parts
```

## Packets

Everything rides one RemoteEvent as `(opcode, sequence, data)`. The server drops
packets with an unknown opcode, a non-increasing sequence, or that exceed the token
bucket in `Config.RateLimit`. Before the session is authenticated only
`CMSG_AUTH_SESSION` and `CMSG_PING` get through.

| Opcode | Direction | Data |
|---|---|---|
| CMSG_AUTH_SESSION | client | `{ Build }` must match `Config.Build` |
| SMSG_AUTH_RESPONSE | server | `{ Ok, SessionId, Role, Level, Reason }` |
| CMSG_PING / SMSG_PONG | both | `{ Time }` echoed back, client stores `Latency` attribute |
| CMSG_CHAR_ENUM / SMSG_CHAR_ENUM | both | `{ Characters = { { Slot, Name, Class, Level } }, Max }` |
| CMSG_CHAR_CREATE | client | `{ Name, Class }` |
| CMSG_CHAR_DELETE | client | `{ Slot }` |
| CMSG_PLAYER_LOGIN | client | `{ Slot }` picks the character; the server then spawns |
| CMSG_LOGOUT_REQUEST | client | back to character select |
| SMSG_CHAR_RESULT | server | `{ Ok, Reason }` for create, delete and login |
| SMSG_XP_GAIN | server | `{ Amount, Reason }` |
| SMSG_LEVELUP | server | `{ Level }` |
| SMSG_ITEM_PUSH | server | `{ Entry, Name, Quality, Count }` |
| CMSG_INVENTORY / SMSG_INVENTORY | both | `{}` in, `{ Items = { { Entry, Name, Quality, Count } }, Money }` out |
| SMSG_MONEY | server | `{ Amount, Total }` in copper |
| CMSG_SET_TARGET | client | `{ Guid }` or `{}` to clear |
| CMSG_ATTACK | client | `{ On }` toggles auto-attack on the target |
| SMSG_COMBAT_LOG | server | `{ Text, Color }` |
| SMSG_PLAY_EFFECT | server | `{ Name, Count, Player | Guid | Position }` particle from Assets/Particles |
| CMSG_LOOT / SMSG_LOOT_RESPONSE | both | `{ Guid }` in, `{ Guid, Name, Items, Money }` out |
| CMSG_AUTOSTORE_LOOT_ITEM / CMSG_LOOT_MONEY / CMSG_LOOT_RELEASE | client | take an item by index, the coins, or close |
| SMSG_LOOT_REMOVED / SMSG_LOOT_RELEASE_RESPONSE | server | `{ Index }` or `{ Money }`; window closed |
| SMSG_DEATH / CMSG_REPOP_REQUEST / CMSG_RECLAIM_CORPSE | both | you died; release spirit; resurrect at your corpse |
| CMSG_QUESTGIVER_HELLO / SMSG_QUESTGIVER_QUEST_LIST | both | `{ Guid }` in; greeting and the quests this NPC has for you |
| CMSG_QUESTGIVER_QUERY_QUEST / SMSG_QUESTGIVER_QUEST_DETAILS | both | one quest's text, objectives and rewards |
| CMSG_QUESTGIVER_ACCEPT_QUEST / CMSG_QUESTGIVER_COMPLETE_QUEST / CMSG_QUESTLOG_REMOVE_QUEST | client | `{ Guid, Quest }` |
| SMSG_QUESTLOG / SMSG_QUESTUPDATE_ADD_KILL / SMSG_QUESTUPDATE_COMPLETE / SMSG_QUESTGIVER_QUEST_COMPLETE | server | log, "X slain: 3/5", "(Complete)", rewards given |
| CMSG_CAST_SPELL / CMSG_CANCEL_CAST | client | `{ Spell, Guid? }`; stop the current cast |
| SMSG_SPELL_START / SMSG_SPELL_GO / SMSG_SPELL_FAILURE / SMSG_SPELL_COOLDOWN | server | cast bar, landed (`Target`, `Amount`), `{ Reason }`, `{ Id, Seconds }` |
| SMSG_INITIAL_SPELLS / SMSG_LEARNED_SPELL / SMSG_ACTION_BUTTONS / CMSG_SET_ACTION_BUTTON | both | known spells, a new one, `{ Buttons = { [slot] = spell } }`, `{ Slot, Spell? }` |
| SMSG_TRAINER_LIST / CMSG_TRAINER_BUY_SPELL | both | trainer's spells with `Price`, `ReqLevel`, `Known`; `{ Guid, Spell }` |
| CMSG_GOSSIP_SELECT_OPTION / CMSG_USE_ITEM / SMSG_BINDPOINTUPDATE | both | gossip option `{ Guid, Option }`; use the item in bag slot `{ Bag }`; new home `{ Name }` |
| CMSG_SEND_MAIL / SMSG_SEND_MAIL_RESULT / SMSG_RECEIVED_MAIL | both | `{ Guid, To, Subject, Body, Money, Items = { bag slots } }`; result; new or unread mail |
| CMSG_GET_MAIL_LIST / SMSG_MAIL_LIST_RESULT / CMSG_MAIL_TAKE_MONEY / CMSG_MAIL_TAKE_ITEM / CMSG_MAIL_DELETE / CMSG_MAIL_MARK_AS_READ | both | inbox for a mailbox guid; actions by letter `Id` |
| CMSG_CONTACT_LIST / SMSG_CONTACT_LIST / CMSG_ADD_FRIEND / CMSG_DEL_FRIEND / CMSG_ADD_IGNORE / CMSG_DEL_IGNORE / SMSG_FRIEND_STATUS | both | friends with online state, ignore names; `{ Name }`; "X has come online" |
| CMSG_WHO / SMSG_WHO / CMSG_PLAYED_TIME / SMSG_PLAYED_TIME | both | who is in the world (`Filter`); seconds played |
| CMSG_GUILD / SMSG_GUILD_ROSTER / SMSG_GUILD_INVITE / SMSG_GUILD_EVENT | both | `{ Action, Target?, Text? }`; roster with ranks and online state; invite; green guild lines |
| SMSG_SHOW_BANK / CMSG_BANK_DEPOSIT / CMSG_BANK_WITHDRAW / CMSG_BANK_SWAP | both | bank stacks; `{ Bag, Bank? }`, `{ Bank, Bag? }`, `{ From, To }` |
| CMSG_DUEL / SMSG_DUEL_REQUESTED / SMSG_DUEL_UPDATE | both | `{ Action = request|accept|decline|cancel, Target? }`; challenge; `{ Opponent? }` |
| CMSG_CANCEL_AURA / CMSG_GAMEOBJ_USE | client | `{ Id }` drops a buff; `{ Guid }` uses a chest, door, node or mailbox |
| CMSG_LEARN_TALENT | client | `{ Id }`; the tree rides the `Talents` attribute |
| CMSG_CRAFT / CMSG_LEARN_SKILL / SMSG_SKILL_TRAINER | both | `{ Recipe, Count }`; `{ Guid, Skill, Action? }`; the profession trainer's list |
| SMSG_ACHIEVEMENT_EARNED | server | `{ Id, Name, Description, Points }` |
| CMSG_AUCTION_LIST_ITEMS / SMSG_AUCTION_LIST_RESULT / CMSG_AUCTION_SELL_ITEM / CMSG_AUCTION_PLACE_BID / CMSG_AUCTION_REMOVE_ITEM / SMSG_AUCTION_COMMAND_RESULT | both | `{ Mode = browse|owner|bidder, Filter }`; `{ Bag, Bid, Buyout, Hours }`; `{ Id, Amount }`; `{ Id }` |
| SMSG_SHOWTAXINODES / CMSG_ACTIVATETAXI / SMSG_TAXI_DONE | both | `{ Guid, Here, Nodes }`; `{ Guid, Node }`; arrival |
| CMSG_INITIATE_TRADE / CMSG_BEGIN_TRADE / CMSG_CANCEL_TRADE / CMSG_SET_TRADE_ITEM / CMSG_SET_TRADE_GOLD / CMSG_ACCEPT_TRADE / SMSG_TRADE_STATUS | both | `{ Target }`; `{ Slot, Bag? }`; `{ Amount }`; `{ Status, Partner, Mine, Theirs }` |
| CMSG_INSPECT / SMSG_INSPECT_RESULT / CMSG_RANDOM_ROLL | both | `{ Name }` in, gear and stats out; `{ Max }` rolls to the party |
| CMSG_PET_ACTION | client | `{ Action = attack|follow|passive|aggressive|defensive|dismiss }` |
| SMSG_LOOT_ROLL_START / CMSG_LOOT_ROLL | both | `{ Id, Item, Seconds }`; `{ Id, Vote = need|greed|pass }` |
| SMSG_WEATHER / SMSG_GAME_EVENT | server | `{ Kind, Intensity }`; `{ Active, Started? }` |
| CMSG_GUILD_BANK / SMSG_GUILD_BANK_LIST | both | `{ Action = open|deposit|withdraw|depositmoney|withdrawmoney, Bag?, Slot?, Amount? }`; the vault |
| SMSG_RESURRECT_REQUEST / CMSG_RESURRECT_RESPONSE | both | `{ From }`; `{ Accept }` |
| CMSG_BATTLEMASTER_JOIN / CMSG_LEAVE_BATTLEFIELD / SMSG_BATTLEFIELD_STATUS | both | `{ Id }`; leave or cancel; `{ Status = queued|active|ended|none, Scores, Flags, Winner }` |
| CMSG_CONVERT_RAID / CMSG_SET_SUBGROUP | client | party to raid; `{ Target, Group }` |
| CMSG_SAVE_SETTINGS / SMSG_SETTINGS | both | `{ Settings }` JSON under 8 KB, per account |
| SMSG_QUESTGIVER_STATUS_MULTIPLE | server | `{ Statuses = { [guid] = available|complete|incomplete|none } }` for the markers |
| SMSG_VENDOR_LIST | server | `{ Guid, Items }` opens the vendor window |
| CMSG_VENDOR_BUY / CMSG_VENDOR_SELL | client | `{ Guid, Entry, Count }` |
| CMSG_EQUIP / CMSG_UNEQUIP | client | `{ Entry }` / `{ Slot }` |
| SMSG_EQUIPMENT | server | `{ Slots, Stats = { Health, Mana, Damage, Armor, SpellPower, Crit, Dodge, Strength, Agility, Stamina, Intellect, Spirit } }` |
| CMSG_BUYBACK_ITEM / SMSG_BUYBACK_LIST | both | `{ Guid, Index }` in, `{ Items }` out |
| CMSG_ITEM_QUERY_SINGLE / SMSG_ITEM_QUERY_SINGLE_RESPONSE | both | `{ Entry }` in, the template's display fields out |
| SMSG_SPAWN | server | `{ Position, Health, MaxHealth }` |
| SMSG_DESPAWN | server | on death, respawn follows after `Config.RespawnDelay` |
| SMSG_HEALTH_UPDATE | server | `{ Health, MaxHealth }` |
| CMSG_MESSAGECHAT | client | `{ Channel, Text, Target }` |
| SMSG_MESSAGECHAT | server | `{ Channel, Sender, Target, Text }` |
| SMSG_NOTIFICATION | server | `{ Text }` from `.announce` |
| SMSG_GM_STATE | server | `{ Name, Gm, Invisible }` how clients draw a GM |
| SMSG_ZONE_UPDATE | server | `{ Name, Pvp, Safe }` or `{}` when leaving all zones |
| CMSG_EMOTE / SMSG_EMOTE | both | `{ Emote }` in, `{ Emote, Sender }` out to SAY range |
| CMSG_TICKET | client | `{ Text }` opens a GM ticket |
| CMSG_PARTY | client | `{ Action, Target }` invite, accept, decline, leave, uninvite, promote |
| SMSG_PARTY_UPDATE | server | `{ Leader, Members }` to every member on change |
| SMSG_PARTY_INVITE | server | `{ From }` |

Add an opcode in `Shared/Opcodes.luau`, then `Packet:On(opcode, handler)` on the
server and `handlers[opcode]` on the client.

## Modules

A module is a table of methods passed to `Template.h` with the modules it needs:

```lua
local Base = require(game:GetService("ServerStorage").ServerModules["Template.h"])
local module = {}

function module:Thing(player)
	self.includes.Security["Packet.h"]:Send(player, ...)
end

return Base(module, {
	{ Path = "Auth/Security", Imports = "Packet.h|Session.h" },
})
```

`ServerHandler` loads every module once, then `Compiler.h` swaps each `includes`
list for `includes[Folder]["Name.h"]`. One instance per module, so state is shared
wherever it is imported. Per-instance state lives in `self.information`.

## Login sequence

Like 3.3.5a: auth, then character select, then the world. The select screen is up
from the first frame with the realm name and a status line that walks through
connecting, authenticating and retrieving the character list over skeleton slots;
after `SMSG_AUTH_RESPONSE` the client asks for `CHAR_ENUM` and fills it in; an account holds up to
`Config.MaxCharacters` characters, each with a name, one of the ten classes and a
level. `PLAYER_LOGIN` picks one and only then does the server spawn, with the
character's name on the Humanoid and its saved position. `/logout` saves and drops
back to the list. Before entering the world only the character opcodes and ping get
through the session guard, and the client shows no chat or core UI; on spawn the
player frame (portrait, name, level, class, health, latency) appears top-left and
the server greets the character. Character names are what chat, parties and GM commands
show and accept, coloured by class in Blizzard's class colours.

## Roles and commands

`RBAC_Permissions.h` levels: PLAYER 0, MODERATOR 1, GAMEMASTER 2, OWNER 4, CONSOLE 5.
The place creator and `Config.Owners` are OWNER; everyone else is PLAYER unless
`.role` stored an override in the Auth DataStore.

Commands are typed in chat with a leading dot, WoW style. A PLAYER gets
"There is no such command"; `.help` lists what the caller's role can run.

```
MODERATOR   .help [command]  .who  .server info  .zone  .gps  .gm on|off  .gm invis on|off  .gm list
            .ac status | .ac reset <player> | .ac on|off
            .ticket list | view <id> | reply <id> <text> | close <id>
            .freeze <player>  .unfreeze <player>  .mute <player> <minutes> [reason]
            .unmute <player>  .kick <player> [reason]
GAMEMASTER  .buff <all|player> <speed|jump> <multiplier> <seconds>
            .tele <name> | <x> <y> <z> | add <name> | del <name> | list
            .appear <player>  .summon <player>  .reload creature|gameobject
            .gobject add <entry> [yaw] [scale] | delete [guid] | move [guid] | turn [guid] <deg> | near
            .gobject template add <name> <modelid> [size] | template list
            .quest add|complete|remove <id> [player] | .quest template list
            .learn <spell id|all> [player] | .unlearn <spell id> [player]
            .aura <spell id> [player] | .unaura <spell id|all> [player] | .mount [player] | .dismount [player]
            .skill learn|unlearn <name> [player] | .skill set <name> <value> [player] | .skill list
            .talent reset [player] | .talent points [player] | .rep <faction id> <amount> [player] | .rep list
            .achievement add <id> [player] | .achievement list | .honor add <amount> [player]
            .taxi node add <name> [cost] | .taxi path <from> <to> [cost] | .taxi list | .taxi learn all [player]
            .npc wp add [guid] [wait] | .npc wp clear [guid]
            .event list | .event info <id> | .pet <creature entry> [player] | .pet dismiss [player]
            .gm gear | .gm testarea [clear]
            .bg create <name> [minlevel] | .bg spawn <id> Alliance|Horde | .bg flag <id> Alliance|Horde | .bg list | .bg leave [player]
            .npc add <entry> | delete [guid] | move [guid] | kill [guid] | say [guid] <text> | info [guid] | near
            .loot template add <creatureEntry> <itemEntry> <chance> [min] [max] | template list [entry]
            .npc template add <name> [modelid] [subname] | template set <entry> <field> <value> | template list
MODERATOR   .lookup creature|object|tele <name>
            .speed <0.1-10> [player]  .hurt <player> <amount>  .heal [player]
            .kill [player]  .revive [player]  .maxhealth <amount> [player]  .time <0-24>
            .levelup [player] [levels]  .setlevel <level> [player]  .modify xp <amount> [player]
            .additem <entry> [count] [player]  .item template add <name> [quality] [stack] | set <entry> <field> <value> | list
            .vendor add <creatureEntry> <itemEntry> | remove <id> | list [entry]
            .morph <userId> [player]  .demorph [player]  .modify hp|speed|scale <value> [player]
            .ban <player> [reason]  .unban <userId>  .announce <text>
            .save [player]  .saveall
OWNER       .role <player> <PLAYER|MODERATOR|GAMEMASTER|OWNER>
            .db tables | select <table> [limit] | get <table> <key> | set <table> <key> <field> <value> | delete <table> <key>
```

`.help <command>` or `.<command> help` prints a command's forms. Aliases: `.gobj`,
`.go`, `.look`, `.tp`, `.goname`, `.namego`, `.ann`, `.h`, `.die`.

`.gm on` puts a blue `<GM>` tag on the GM's chat. `.gm invis on` fades the GM to 60%
for staff and hides them completely, nametag included, from players; it is purely
visual (`LocalTransparencyModifier` on each client), collisions are unchanged.

## Chat

Channels: SAY (30 studs), YELL (100), WORLD, WHISPER, PARTY, SYSTEM. On the client,
`/y`, `/w Name`, `/world` and `/p` pick the channel; anything else is SAY. Messages go through
`TextService` filtering and are delivered by packet, then drawn as rich text in
Blizzard's colours and phrasing: white `Reynn says:`, red `Reynn yells:`, pink
`Reynn whispers:` / `To Reynn:`, channel-pink `[World] [Reynn]:`, yellow system
lines. Colours live in `Config.Chat.Colors`. The sender's own line is the chat box's
echo, restyled through `OnIncomingMessage`; the server never sends it back. Roblox's own delivery is turned
off: the project file sets `CreateDefaultTextChannels` and `CreateDefaultCommands`
to false on TextChatService (they are not scriptable), and the "Net" channel the
chat box types into has `ShouldDeliverCallback` returning false.

## Zones, emotes, tickets

A zone is any Part tagged `Zone` (CollectionService), fully invisible and
non-colliding in play; `.zone show` outlines them for a moment. Its name is the
zone name; attributes `Pvp` and `Safe` describe it. The world server polls players every
`Config.ZonePollSeconds` and sends `SMSG_ZONE_UPDATE` on change; the client sets the
`Zone` and `ZoneKind` attributes on the Player and `ZoneBanner` fades the name in
like the WoW zone text. Two demo zones ship under `src/Workspace/Zones`.

`/wave`, `/dance`, `/laugh`, `/cheer`, `/point` play the R15 emote and tell everyone
in SAY range in orange. The table is `Config.Emotes`.

`/ticket <text>` opens a GM ticket (one open per player). Staff on every server get
a yellow notice; `.ticket` lists, views, replies to and closes them. Tickets live in
one `Tickets` DataStore record edited with `UpdateAsync`, so servers never overwrite
each other, and replies reach the player on whichever server they are on.

## Parties

WoW groups, up to `Config.Party.MaxSize`: `/invite Name`, `/accept`, `/decline`,
`/leave`, `/uninvite Name`, `/promote Name`. The leader passes on when the leader
leaves; a party of one disbands. `/p text` is the PARTY channel in light blue.
`PartyFrame` lists members on the left with health bars read from their replicated
characters, so the frame costs no packets.

## Anticheat

Every `Config.Anticheat.SampleSeconds` the server compares how far each character
moved horizontally with `WalkSpeed * dt * Tolerance + Slack`. Over the limit snaps
the player back to the last good position and counts a strike; strikes decay after
`WindowSeconds`; at `Strikes` every online GM gets a yellow alert. Server-side moves
(`.tele`, `.summon`, spawns) call `Anticheat:Allow` first so they never trip it, and
GM mode is exempt. `.ac` shows strikes, resets a player, or toggles the check.

## World database

`WorldDB.h` is the TrinityCore world database on a DataStore. Each table is one
record edited with `UpdateAsync` and every write goes out on the bus, so a GM
placing something on one server sees it appear on all of them. Tables and keys:

| Table | Key | Columns |
|---|---|---|
| creature_template | entry | name, subname, modelid, scale, gossip, faction, minlevel, maxlevel, health, dmgmin, dmgmax, aggro, speed, mingold, maxgold, spells, wander, rank, script, beast, repair, faction_id, rep_kill, rep_ally, innkeeper, banker, trainer_skill, flightmaster, auctioneer |
| creature | guid | id (entry), x, y, z, o, spawntimesecs, waypoints, event, by |
| creature_loot_template / gameobject_loot_template | id | entry, item, chance, mincount, maxcount |
| gameobject_template | entry | name, modelid, size, type (mailbox, chest, door, node, auctioneer), skill, reqskill, mingold, maxgold |
| gameobject | guid | id (entry), x, y, z, o, scale, spawntimesecs, by |
| game_tele | id | name, x, y, z, o |
| game_graveyard | id | name, x, y, z, o |
| quest_template | id | title, details, objectives, minlevel, level, reward_xp, reward_money, reward_items, req_creature, req_item, class, race, prevquest, reward_rep |
| creature_queststarter / creature_questender | id | entry (creature), quest |
| spell_template | id | name, rank, description, class, school, effect (damage, heal, aura, hearth), base, per_level, cost, cast_time, cooldown, range, target (enemy, friend, self), aura = { kind, stat, mult, interval, duration, harmful }, icon, npc |
| playercreateinfo_spell | id | class, spell |
| npc_trainer | id | entry (creature), spell, cost, reqlevel |
| faction | id | name, team, description, base = { Alliance, Horde } |
| talent | id | class, tab, tier, col, name, description, max_rank, mod = { kind, stat or school, value } |
| skill_line | id | name, kind (primary, secondary), description |
| skill_recipe | id | skill, name, result, count, reagents, reqskill |
| achievement | id | name, description, category, points, criteria = { type, value, name } |
| auctionhouse | id | item, count, owner, ownerId, bid, buyout, bidder, bidderId, expires, deposit |
| taxi_nodes / taxi_path | id | name, x, y, z, cost / from, to, cost, points |
| game_event | id | name, description, start, length (min), occurrence (min), xp_mult |
| battleground_template | id | name, minlevel, spawn = { Alliance, Horde }, flag = { Alliance, Horde } |

Outside the world tables, the World store also keeps `names` (character name to
account, for mail and friends), `mail:<name>` (a character's letters),
`guild:<id>` (a guild with its members and ranks) and `guildnames`.
| item_template | entry | name, quality 0-5, stack, class, slot, health, damage, armor, strength, agility, stamina, intellect, spirit, spellpower, buyprice, sellprice, level, use, consumable, flavor, bind, container |
| npc_vendor | id | entry (creature), item |

Templates are the assets, spawns reference them by entry, like TC. A creature's
`modelid` is `default`, `user:<UserId>` (that account's look) or `model:<Name>` for a
rig under `ServerStorage/CreatureModels`. An object's `modelid` is a Model name under
`ServerStorage/ObjectTemplates` (crate, barrel, campfire, stone ship and seed the
table on first run) or `asset:<id>`. Spawns sit flush on the ground, facing the GM
who placed them, and keep a yaw. Creatures stand anchored with a Talk prompt that
says the template's `gossip`. Three creature templates seed the table.

Commands follow TC: `.lookup creature guard`, `.npc add 2`, `.npc template set 2
gossip Halt!`, `.gobject add 3 45`, `.gobject turn 90`, `.reload creature`. Where a
command takes `[guid]`, leaving it out picks the nearest spawn within 15 studs.
Change a template and every spawn of it respawns, on every server.

## Cross-server

`Global.h` is a bus on one MessagingService topic. A command does its local work,
then publishes; every other server reacts and the origin ignores its own message.
`.announce`, `.kick`, `.ban` and `.buff` are global this way, and `.kick`/`.ban`
accept the name of someone who is not on this server (looked up to a UserId).
`.buff all speed 2 60` doubles everyone's WalkSpeed for a minute on every server;
a multiplier under 1 is a debuff. Without MessagingService (Studio without API
access) it logs once and runs single-server.

## Chat window, experience, items

`ChatFrame` replaces Roblox's chat window and input bar with its own: three tabs
(General, Whispers, Log) and a box that `/` or Enter focuses. Lines still go out
through the TextChannel, so Roblox filtering applies, and every line is drawn from
the server's packet, the sender's own included. Entering the world clears General
and Log; Whispers keep. A hidden tab lights up when it gets a line, pink for whispers.

Characters have a level (cap `Config.Xp.MaxLevel`, 80) and experience on a TC-shaped
curve in `Config.Xp.ForLevel`; max health follows level. Gains print in XP blue,
level-ups in yellow with a banner, and the player frame has an XP bar. The first
visit to a zone pays exploration experience, remembered per character.

`item_template` rows have a WoW quality (0 poor to 5 legendary, coloured to match)
and a stack size. A character's inventory is a list of stacks; `.additem` pushes one
and prints "You receive item: [Name]x5." in loot green; `/inv` lists them. `.db`
reads and edits any world table directly; a write respawns what depends on it, on
every server.

## Combat

A `creature_template` with `faction = hostile` spawns unanchored with a level rolled
between `minlevel` and `maxlevel`, health scaled by level, and a brain that ticks
four times a second: pick the nearest living player inside `aggro`, chase, swing for
`dmgmin` to `dmgmax` every two seconds in melee range, leash home past 60 studs and
regenerate there. Click a creature to target it (the frame right of yours reads its
replicated Humanoid), press T or click again to auto-attack; the server swings on
its own timer with `Config.Combat.Damage(level)` and logs every hit to the Log tab.

On death the killer gets `Config.Combat.KillXp` (nothing for grey creatures) and
the corpse rolls its `creature_loot_template` rows and copper onto itself. A corpse
with loot sparkles and carries a Loot prompt; the killer or their party opens the
loot window and takes items one by one, the coins, or Loot All. An emptied corpse
clears in a couple of seconds, a full one after `Config.Combat.CorpseSeconds`; the
spawn returns after `spawntimesecs` (default 30). Two hostile templates seed:
Kobold Vermin and Young Wolf, with loot rows.

When a player dies the server offers Release Spirit. Releasing spawns the character
as a ghost (translucent, faster, cannot attack or be attacked) at the nearest
`game_graveyard` row and leaves a corpse marker where they fell; the Resurrect
prompt on the marker, within `ReclaimRange`, brings them back at half health.
`.revive` resurrects anywhere. `.graveyard add <name>` saves where you stand.

`Effects.h` plays particles from `ReplicatedStorage/Assets/Particles` for everyone
(`SMSG_PLAY_EFFECT`) or attaches one to a part: hits, level-ups, heals, deaths,
resurrection, and the loot sparkle. The emitters use Roblox's built-in particle
textures, so there is nothing to download; drop more `.model.json` emitters in the
folder and call them by name.

## Vendors and gear

The backpack has `Config.BagSlots` slots (16, like WoW's); a stack merges into its
kind first and then takes the first free slot, and a full bag says so. **B** opens
it as a grid of quality-bordered tiles with stack counts and tooltips. Drag a stack
onto another slot to move or swap it (`CMSG_SWAP_INV_ITEM`, partial stacks merge),
onto an equipment slot on the character sheet to equip it, onto a vendor window to
sell it; drag an equipped slot back into the bag to unequip. Right-click is the
shortcut for equip and sell; Shift-click puts `[Item Name]` into the chat box.
`Drag.luau` carries the payload and a ghost tile between windows.

A creature with `npc_vendor` rows opens a vendor window when talked to, and the
backpack with it: goods on the left with prices in copper, buyback on the right
holding the last `Config.BuybackSlots` stacks you sold this session at the price
you got. Sell prices are a quarter of the buy price unless `sellprice` is set.
Buying checks range, stock and money. General Goods seeds with the starter set.

Whispers, invites and GM targets accept the character name as well as the account
or display name. Type `[Linen Cloth]` in chat and the server resolves it against `item_template`;
everyone sees it in the item's quality colour, and clicking the line shows the
tooltip, fetched through `CMSG_ITEM_QUERY_SINGLE` and cached, like the real client.

The vendor window and character sheet are built with
[Fusion](https://elttob.uk/Fusion/) through `Components.luau`: draggable titled
panels, hover rows with tooltips, lists bound to the Inventory, Equipment, Stats and
Money attributes so they redraw themselves.

Items with a `slot` are gear (one per slot, the old one goes back to the bag,
`level` is enforced). **C** opens the character sheet: the worn slots as tiles with
the stats above them. Tooltips follow WoW's layout, name sized and coloured by
quality with a matching border, requirement in red when you are too low. Stats recompute on every change: max health is the level's
health plus gear `health`, melee adds gear `damage`, and gear `armor` comes off every
creature hit. Equipment and the bag live on the character record.

## Quests

TC's quest tables on the world database. A creature with `creature_queststarter` or
`creature_questender` rows is a questgiver: its Talk prompt opens the questgiver
window with the greeting and the quests it has for you, marked `!` for available,
`?` for ready to turn in, grey `?` for in progress; the same marks float over the
NPC in the world. Pick a quest for its text, objectives and rewards, then Accept or
Complete. Objectives are kill counts (`req_creature`, credited to the killer and
party members within 100 studs, "Kobold Vermin slain: 3/5") and items to bring
(`req_item`, counted from the bag). Completing removes the items and pays
`reward_xp`, `reward_money` and `reward_items`. The quest log on **L** holds up to
`Config.QuestLogSize`; right-click abandons. Two quests seed on the Town Guard and
the Innkeeper.

## Spells

`spell_template` holds the spells: school (physical, holy, fire, nature, frost,
shadow, arcane), effect (`damage` on a hostile target, `heal` on yourself, `buff`
through the entity buffs), amount as `base + per_level`, mana cost, cast time,
cooldown and range. Every class starts with the spells in `playercreateinfo_spell`
and buys the rest from a creature with `npc_trainer` rows (the seeded Class
Trainer; place one with `.npc add`). Mana is `Config.Spells.ManaForLevel` and
regenerates `ManaRegen` of max per second; the player frame shows it under
health.

The action bar has twelve buttons on 1-9, 0, - and =. Learning a spell drops it
on the first free button; drag from the spellbook (**P**) to place, between buttons
to swap, off the bar to clear. A cast shows a cast bar and breaks if you move more
than `InterruptDistance` studs; Escape cancels. Cooldowns sweep over the button
with the seconds left, and there is a 1.5 second global cooldown. Failures
("Out of range.", "Not enough mana.") flash in red and go to the Log tab. Spell
hits play the school's particle from `Assets/Particles`.

## Gossip, mail, social

Talking to a creature opens a gossip window when it has quests or more than one
role: its quests, "I seek training.", "Let me browse your goods." and, for an
innkeeper (`creature_template.innkeeper`), "Make this inn your home.". A
single-purpose NPC skips the window. Binding sets `Home` on the character; the
Hearthstone item casts the Hearthstone spell (10 second cast, 60 second cooldown)
back to it. Items carry a spell through `item_template.use` (the spell's name,
resolved to `spell`), shown as a green "Use:" line and cast with right-click;
`consumable` items are used up, like Tough Jerky.

Mail follows TC's mail table: a mailbox game object (`gameobject_template.type ==
"mailbox"`, place one with `.gobject add`) opens the inbox. Letters have a subject,
body, money and up to four items dragged from the bag, cost `Config.Mail.Postage`
plus the money sent, reach offline characters through the `names` index, announce
themselves when the recipient is online and expire after thirty days. Take the
money and items before deleting.

Friends and ignore lists live on the character. `/friend`, `/unfriend`, `/ignore`,
`/unignore`, the Social window on **O** (click an online friend to whisper), and
"X has come online" lines. Ignored players cannot whisper, invite or be heard.
`/who [text]` lists everyone in the world with level, class and zone; `/played`
reports time on the character.

## Guilds and bank

Guilds follow TC's guild and guild_member: founding costs `Config.Guild.CreateCost`,
ranks are Guild Master, Officer and Member, officers invite and kick, the master
promotes, demotes, hands over leadership and disbands. Guild chat is `/g`
(`/world` or `/1` for the realm channel), the MOTD shows on login, and joins,
leaves, kicks and promotions announce in guild green. The Guild tab of the Social
window on **O** has the roster, MOTD and buttons; the commands are `/gcreate <name>`,
`/ginvite`, `/gaccept`, `/gdecline`, `/gkick`, `/gpromote`, `/gdemote`, `/gleader`,
`/gmotd <text>`, `/gleave`, `/gdisband`, `/groster`. Players show their guild in
the mouseover tooltip.

A creature with `creature_template.banker` (the seeded Banker) offers "I would
like to check my deposit box." and opens the bank: `Config.BankSlots` slots on
the character's `Bank`. Drag from the bag to deposit, onto the bag to withdraw,
between bank slots to move; right-click withdraws.

## Characters, duels, rest

Character creation picks a faction and race (four Alliance, four Horde, in
`Config.Races` with the classes each allows, like WoW's race and class table),
gender, class, and a name, with a random name button and descriptions for the
race and class. A turning preview shows the result; the same race scale and skin
and class tunic are applied to the Roblox body on spawn through the Humanoid scale
values and part colours. Character select shows the chosen character the same way.

`/duel <name>` (or with a player targeted) challenges; `/duel accept` starts a
three second countdown, then melee and damage spells land on the opponent until
one would drop below 1 health, which ends the duel with "X has defeated Y in a
duel." heard in yell range. Nobody dies; walking `Config.Duel.FleeRange` studs
from the flag, logging out or dying to something else forfeits. Click a player to
target them; the target frame shows "(Duel)" while they are your opponent.

Standing near an innkeeper or in a zone with `Inn = true` is resting: "zzz" on
the player frame and rested XP banking at `Config.Rested.PerTick` of the level
every tick, up to one and a half levels. Kill XP is doubled from that pool, shown
as "(+N exp Rested bonus)".

## Stats, auras, talents

Each class has base primary stats and per-level growth in `Config.Stats`, WoW
style: Stamina is health, Intellect mana and spell power, Strength melee damage,
Agility crit, dodge and armor, Spirit mana regeneration. Equipment adds stats,
auras and talents modify them, and `EntityPlayer:ApplyStats` folds it all into
the numbers combat reads. Attacks roll miss, dodge, crit or hit.

Every spell and ability goes through `Combat:Damage` and `Combat:Heal`, which
take any unit (a player or a creature state), so DoTs, creature spells, duels and
world PvP all log and aggro the same way. A spell with an `aura` block applies a
timed effect: periodic damage or healing, a stat bonus, a slow, a stun, a mount.
Each class has a DoT or HoT, a stat buff or a slow, and most a stun. Auras ride
the unit's `Auras` attribute; the buff frame draws yours under the player frame
and the target's under the target frame, with a right-click to cancel. Creatures
cast too: `creature_template.spells` names the spells their brains use, and they
patrol `creature.waypoints` (`.npc wp add`), wander `wander` studs around home,
and call nearby creatures of their kind for help when attacked.

Talents open on N from level 10: three trees a class laid out as a scrolling
grid of three columns, five tiers with two talents each but the last (the
tab's Training, Focus, Mastery and Expertise beside the named talent)
that raise a stat by percent, a school's damage, or crit and dodge. Points come
one a level; a tier opens with five points in the tree below. The class trainer
unlearns them for a gold, doubling each time.

## Professions, reputation, achievements

Professions (K) are skill lines: Mining, Herbalism, Blacksmithing, Alchemy and the
secondary Cooking and First Aid, two primaries at most. A profession trainer
(`trainer_skill`) teaches them and raises the cap from Apprentice 75 to Journeyman
150 and Expert 225. Recipes unlock by skill; crafting consumes reagents and skills
up orange, yellow, green, grey. Veins and herbs are gameobjects of type `node`
with a `Skill` and `ReqSkill`; gathering rolls `gameobject_loot_template`. Chests
work the same without a skill and doors swing on their hinge; all of them
respawn after `spawntimesecs`.

Reputation (U) follows TC's faction table and standings, Hated to Exalted. A
creature's `faction_id` loses standing when killed and `rep_ally` gains it, quests
can give `reward_rep`, and vendors of a faction discount by standing.
Achievements (Y) check level, kills, quests, zones discovered, money looted,
duels, honorable kills, skills and standing; earning one toasts and tells the
guild and anyone nearby.

## Auction house, flight paths, trade, PvP

An auctioneer creature or gameobject opens the auction house: browse with
search, bid or buy out, see your bids and auctions, and sell by dragging a bag
item in with a starting bid, buyout and 12, 24 or 48 hours. Deposits, outbids,
wins and expiries all settle through the mail, with the house's cut.

Flight masters (`flightmaster`) sit at `taxi_nodes`; talking to one learns its
node, and `taxi_path` rows connect nodes (`.taxi node add`, `.taxi path`). Flying
anchors the character and tweens it along the path, high up, for the fare.
Mounts are items whose spell applies a `mount` aura that lasts until cancelled
or until any damage lands: a horse is drawn under the character and movement is
faster. A mount with `fly = true` (Gryphon Reins) sets `MountFlying`. On the ground
you walk as usual; Space takes off and the client's flight controller carries
you where the camera looks, WASD along the camera, Space to rise, Shift to
descend, hovering when idle; holding Shift near the ground lands. The
anticheat allows flight speed.

`/trade <name>` opens a six slot trade window on both sides once accepted; both
must accept after any change. `/inspect` shows another player's gear, stats and
talent spread; `/roll` rolls to the party or those nearby.

In a zone with `Pvp = true`, players of the other faction are attackable, which
flags you (red PvP on the player frame) for five minutes. A kill of someone within
five levels is an honorable kill worth honor, both kept on the character sheet.

## Raids and battlegrounds

`/raid` converts a party into a raid of up to `Config.Party.RaidSize` in eight
subgroups (`/setgroup <name> <n>`), with `/ra` for raid chat and a compact raid
frame. A battlemaster creature (`battlemaster`) lists the battlegrounds a GM has
set up with `.bg create`, `.bg spawn` and `.bg flag` for each faction: queue,
and once `MinPerSide` of each faction wait, the match starts. Everyone ports to
their base, a flag pole stands at each flag point, taking the enemy flag carries
it on your back (and dismounts you), returning your own dropped flag or
carrying theirs to your base while yours is home scores, and a dropped flag
returns by itself after a while. First to `ScoreToWin` ends it, honor is paid,
and everyone ports back. Inside a match the other faction is always attackable
and dying respawns you at your base after a countdown instead of releasing.

## Threat, ranks, bosses, durability, bags

Creatures keep a threat table like TC: damage adds its amount for the attacker,
healing adds half to every creature fighting the healed unit, and taunts
(Warrior, Paladin, Druid, Death Knight) jump to the top. The target is whoever
leads by `Config.Combat.ThreatSwitch`; with nobody left the creature evades to
full health. Everyone on the table shares the kill. `creature_template.rank`
is normal, elite, rare or boss and scales health, damage and experience; the
tooltip and target frame show it in gold or silver. A boss `script` lists
events (`at` combat, health with a value, timer with every, death; `action` say,
yell, cast, summon with a creature and count, enrage) that fire once per fight.
Goldtooth seeds one: he yells, calls kobolds at 75%, throws Fire Blasts on a
timer and enrages at 30%; his adds vanish when he dies or resets.

Armor and weapons have durability (`Config.Durability`): hits taken chip it,
death takes a tenth, a broken item gives no stats, and any vendor with `repair`
offers "Repair all my items" in gossip for a price by level and quality. Bags
are items with `container` slots that go in the four bag slots on the
character sheet and grow the backpack; a bag must be empty to come off.

## Pets, group loot, events, guild vault, resurrection

Hunters cast Tame Beast on a beast (`creature_template.beast`) of their level or
lower; it becomes the character's pet, called back with Call Pet and sent away
with Dismiss Pet. Warlocks summon an Imp. A pet is a creature state with an
owner and no database row: it follows, attacks what you attack or what attacks
you, obeys /petattack, /petfollow, /petpassive and /petaggressive or the pet
frame's buttons, leashes back when far, and needs ten seconds to recover after
dying. Creatures fight pets back and pets' kills credit the owner.

In a party, looting an item of uncommon quality or better starts a Need, Greed or
Pass roll among the members nearby. Everyone sees the choices and the rolls,
Need beats Greed, the winner gets the item (by mail when their bags are full),
and an all-pass puts it back on the corpse.

The real clock drives the world: a game day lasts `Config.World.DayMinutes`,
weather rerolls every `WeatherMinutes` (clear, rain, storm, snow, fog, drawn over
the camera with fog and dimmer light), and `game_event` rows start and end on a
schedule, announcing themselves, spawning the creatures and objects whose spawn
row names them in `event`, and multiplying kill experience by `xp_mult`.

Guilds have a vault at any banker: shared slots and money, members deposit,
officers withdraw. Priests, paladins, shaman and druids learn a resurrection
spell; cast on a dead player's target within range of their corpse or ghost, it
offers, and accepting brings them back at the corpse with half health.

## Tooltips

One tooltip serves everything. It does not follow the mouse: beside the element
it describes, or in the bottom right corner for creatures and players in the
world (name in faction or class colour, subname, level, guild). Items use the WoW
order: name in quality colour, binding, slot and type, armor, green stats, level
requirement in red when too low, Use line, max stack, sell price in coin colours.
Spells show cost and range, cast time and cooldown, rank, class, description and
what the aura does. Items list primary stats and spell power.

## Forms, stances, mounts you can build

Druids shapeshift: Bear Form (armor and Stamina), Cat Form (Agility and
speed), Travel Form (speed), and the talent forms Moonkin and Tree of Life;
Shaman have Ghost Wolf, Priests Shadowform, Rogues Stealth (slow, creatures
notice you only within six studs, any attack or damage breaks it). A form
hides the body and stands a form body in its place, one form at a time, casting
the form again shifts back, mounting ends it. Warriors have Battle, Defensive
and Berserker Stance, Paladins Devotion and Retribution Aura, Hunters Aspect
of the Hawk and Cheetah, Death Knights Blood, Frost and Unholy Presence: each
group is exclusive and lasts until swapped. All of these are `aura` kinds
(`form`, `stealth`, `stats` with a `group`) with `stats` scaled per point and
an optional speed `mult`.

Mounts and forms are bodies attached to the character. The built-in horse,
gryphon and the form bodies live in EntityPlayer; to make your own, put a
Model in `ServerStorage/MountTemplates` (or `FormTemplates`) whose parts sit
around the origin as the rider's HumanoidRootPart. Part attributes: `Parent`
(the part to hang on, default Body), `Motor` ("leg" or "wing") with `Side`,
`Phase` and `Pivot` (hinge offset) for the parts clients animate. Name the
template in the mount spell's `aura.model`; the Pony template and Pony Reins
show the whole chain. Legs swing with speed, wings glide and flap.

Casting respects the form, TC's stance masks: a spell lists the `forms` it
may be cast in ("none" is the caster form), everything else is "You can't do
that while shapeshifted". Bears have Maul, Swipe and Growl, cats Claw, Rake and
Ferocious Bite, moonkin Wrath, Starfire and Moonfire, trees the heals, and
Shadowform allows the shadow spells. A stance bar above the action bar holds
the stances, auras, aspects, presences, forms and Stealth on Ctrl+1 to Ctrl+9,
lit while active. Riding is a skill: the Riding Trainer teaches Apprentice
Riding (ground mounts, level 20) and Expert Riding (flying, level 60), and a
mount spell names the skill it needs in `aura.riding`.

Spells share a global cooldown (`Config.Spells.GlobalCooldown`) and shifting
forms, stances and stealth on or off respects it and their own cooldown; a
spell with `nogcd` (stances, presences, aspects, potions, on-use trinkets)
sits off the global cooldown and says so in its tooltip. Tooltips colour what
you lack red: an item type your class cannot use, a form you are not in, a
riding skill you have not trained. Trinkets carry `proc = { spell, chance }`
for "Chance on hit" effects (Flickering Candle, Bandit's Insignia, from
Goldtooth) or a `use` spell used by right-clicking the worn trinket (Vial of
Vigor, Swiftness Charm). Every window scales with the viewport height.

## Blizzlike UI, spellbook tabs, bars per form, saved settings

The shared components follow Blizzard's palette: near-black blue panels with a
gradient, antique gold trim, parchment titles, dark red buttons with gold text,
plain dark rows in lists; every window scales with the viewport. The spellbook
has tabs down the right: General (forms, stances, passives, mounts), one per
school of your class spells, and Skills with professions and passives. Action
bars swap with the form or stance like WoW (`ActionBars[key]` on the character,
the key being the form, the active stance or presence, else "none"), a form
ability learned lands on that form's bar, and only real actions auto-fill a
bar: no passives, procs, forms or stances. Window positions and the spellbook
tab are saved per account (CMSG_SAVE_SETTINGS, back as SMSG_SETTINGS on login).

## Factions, guards, equip rules, spirit healers, GM tools

Hostility is TC's: `creature_template.faction` is `hostile` (everyone), an
`Alliance` or `Horde` team (friendly to its own, attackable by the other, and
with `guard = true` it fights the enemy faction on sight), or, with a
`faction_id`, whatever the player's standing says (Unfriendly or worse is
hostile). Town Guards and Orgrimmar Grunts seed as elite guards. In GM mode
every creature is neutral to you and the world treats you as a player again
when it is off.

Equipping follows class proficiencies (`Config.Classes[].Weapons` and `Armor`
by item `subclass` and `armor` type): a weapon in the off hand needs the Dual
Wield passive (Rogues and Death Knights start with it, Warriors, Hunters and
Shaman train it), a two-hander sends the off hand back to the bag unless you
know Titan's Grip, and shields count as a weapon type. Passives show as such
in the spellbook and cannot be cast.

Spirit healers stand at every graveyard, seen only by ghosts and GMs; a ghost
asks one to return them to life for a quarter of their durability and, from
level 10, ten minutes of Resurrection Sickness. `.gm gear` dresses you in the
gamemaster's set; `.gm testarea` lines up every creature and object template
around you (on GM Island, say) and `.gm testarea clear` removes them.

## Paper doll, tooltips, starter sets

The character sheet is WoW's paper doll: head, neck, shoulders, back, chest,
wrist, hands and waist down the left, legs, feet, two rings and two trinkets
down the right, main and off hand beneath, a turning preview of the character
in the middle and Attributes, Melee and Spell, Defense and Honor blocks below
with the total item score. Rings and trinkets fill the first empty slot of
their pair. Bags live in the backpack window: four slots along the bottom,
drop a bag on one to wear it, right-click to take it off.

Item tooltips show an Item Score (`Config.ItemScore` weights by stat times a
quality factor), redraw when the item under the mouse changes, and while
Shift (first slot) or Alt (second of a pair) is held show "Currently Equipped"
beside them with green and red stat differences and the score change.

New characters start as in Wrath: a set by class (recruit's, squire's,
trapper's, thug's, neophyte's, Acherus knight's, primitive, apprentice's,
acolyte's, novice's) with the class's weapon, food by race, and a Hearthstone
and Linen Bag for everyone (`Config.StarterGear`). The last talent of every
tree teaches a signature spell (Mortal Strike, Holy Shock, Arcane Power and so
on) that trainers never sell and a talent reset takes back. Quests may require
a class, a race or a previous quest: each class has a trainer quest for a
Trainee's weapon, and "Goldtooth's Candles" follows "Vermin Problem".

Mounts carry a saddle and sit the rider; horse legs swing with its speed,
gryphon wings glide on the ground and flap in the air.

## Swings, casts, attacking

Combat state replicates through attributes so every client can animate it:
`Swing` stamps each melee swing (players, creatures, pets), `CastingSpell` on a
player and `Casting` on a creature hold a casting pose, `SpellGo` plays the
release. Roblox's own R15 slash, point and lunge animations are used. Right-
click a creature to target and attack it in one; the target frame glows red
with a swing bar while `Attacking` is set by the server, the player frame
shows "In Combat" with a red portrait, and the log says when you begin and
stop attacking. New characters log in wearing the recruit's set with a sword,
food, a Hearthstone and a Linen Bag (`Config.StarterGear`).

## Corpses

Nothing breaks apart on death. Creatures and players keep their joints, and the
body is laid on its back, anchored and passable, with an invisible Hitbox part
the size of the corpse carrying the Loot or Resurrect prompt and the sparkle. A
player's corpse is a clone of their body made as the ghost spawns, so the stone
marker only appears when there was no body to clone.

## Saving

`Database.h` wraps DataStores with a per-key cache, retries, and a memory-only
fallback when the API is unreachable (Studio without API access). Accounts and
character state write when the player leaves, every `Config.AutosaveSeconds`, and on
shutdown.

## Run

Needs [Rojo](https://rojo.space) and [Wally](https://wally.run). `wally install`
pulls Fusion into `Packages/` (git-ignored, synced to ReplicatedStorage.Packages),
then `rojo serve` and connect from Studio, or `rojo build -o place.rbxl`. Players spawn only after the client authenticates;
`Players.CharacterAutoLoads` is off.
