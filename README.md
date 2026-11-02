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
  WorldServer/Zones/               Zones (which zone each player stands in)
  WorldServer/Movement/            Anticheat (movement validation)
  WorldServer/Content/             Creatures (spawns, AI, loot), GameObjects, Items, Vendors, Teleports
  WorldServer/Combat/              Combat (player melee, combat log)
src/ServerStorage/ObjectTemplates/                 models .gobject can place
  GlobalModules/Database/          Database (DataStore wrapper), DatabaseUUID
  GlobalModules/System/            Compiler (resolves module includes), Global (cross-server bus)
src/StarterPlayer/StarterPlayerScripts/            NetClient (the client half), CharacterSelect, PlayerFrame, TargetFrame,
                                                   ChatFrame, VendorFrame, BagFrame, CharacterSheet, ZoneBanner, PartyFrame,
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
| SMSG_VENDOR_LIST | server | `{ Guid, Items }` opens the vendor window |
| CMSG_VENDOR_BUY / CMSG_VENDOR_SELL | client | `{ Guid, Entry, Count }` |
| CMSG_EQUIP / CMSG_UNEQUIP | client | `{ Entry }` / `{ Slot }` |
| SMSG_EQUIPMENT | server | `{ Slots, Stats = { Health, Damage, Armor } }` |
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
| creature_template | entry | name, subname, modelid, scale, gossip, faction, minlevel, maxlevel, health, dmgmin, dmgmax, aggro, speed, mingold, maxgold |
| creature | guid | id (entry), x, y, z, o, spawntimesecs, by |
| creature_loot_template | id | entry (creature), item, chance, mincount, maxcount |
| gameobject_template | entry | name, modelid, size |
| gameobject | guid | id (entry), x, y, z, o, scale, by |
| game_tele | id | name, x, y, z, o |
| item_template | entry | name, quality 0-5, stack, class, slot, health, damage, armor, buyprice, sellprice, level |
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

On death the killer gets `Config.Combat.KillXp` (nothing for grey creatures),
each `creature_loot_template` row for the entry rolls its chance and pushes its
item, and copper between `mingold` and `maxgold` drops. The corpse clears after a
few seconds and the spawn comes back after `spawntimesecs` (default 30). Two hostile
templates seed: Kobold Vermin and Young Wolf, with loot rows.

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
