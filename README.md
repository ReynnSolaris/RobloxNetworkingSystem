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
  WorldServer/Database/            WorldDatabase (position, health)
  WorldServer/Zones/               Zones (which zone each player stands in)
  GlobalModules/Database/          Database (DataStore wrapper), DatabaseUUID
  GlobalModules/System/            Compiler (resolves module includes), Global (cross-server bus)
src/StarterPlayer/StarterPlayerScripts/            NetClient (the client half), ZoneBanner
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
| SMSG_AUTH_RESPONSE | server | `{ Ok, SessionId, Role, Reason }` |
| CMSG_PING / SMSG_PONG | both | `{ Time }` echoed back, client stores `Latency` attribute |
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

## Roles and commands

`RBAC_Permissions.h` levels: PLAYER 0, MODERATOR 1, GAMEMASTER 2, OWNER 4, CONSOLE 5.
The place creator and `Config.Owners` are OWNER; everyone else is PLAYER unless
`.role` stored an override in the Auth DataStore.

Commands are typed in chat with a leading dot, WoW style. A PLAYER gets
"There is no such command"; `.help` lists what the caller's role can run.

```
MODERATOR   .help  .who  .server info  .zone  .gm on|off  .gm invis on|off  .gm list
            .ticket list | view <id> | reply <id> <text> | close <id>
            .freeze <player>  .unfreeze <player>  .mute <player> <minutes> [reason]
            .unmute <player>  .kick <player> [reason]
GAMEMASTER  .buff <all|player> <speed|jump> <multiplier> <seconds>
            .tele <x> <y> <z> | .tele <player>  .appear <player>  .summon <player>
            .speed <0.1-10> [player]  .hurt <player> <amount>  .heal [player]
            .kill [player]  .revive [player]  .maxhealth <amount> [player]
            .ban <player> [reason]  .unban <userId>  .announce <text>
            .save [player]  .saveall
OWNER       .role <player> <PLAYER|MODERATOR|GAMEMASTER|OWNER>
```

`.gm on` puts a blue `<GM>` tag on the GM's chat. `.gm invis on` fades the GM to 60%
for staff and hides them completely, nametag included, from players; it is purely
visual (`LocalTransparencyModifier` on each client), collisions are unchanged.

## Chat

Channels: SAY (30 studs), YELL (100), WORLD, WHISPER, SYSTEM. On the client, `/y`,
`/w Name`, and `/world` pick the channel; anything else is SAY. Messages go through
`TextService` filtering and are delivered by packet, then drawn as rich text in
Blizzard's colours and phrasing: white `Reynn says:`, red `Reynn yells:`, pink
`Reynn whispers:` / `To Reynn:`, channel-pink `[World] [Reynn]:`, yellow system
lines. Colours live in `Config.Chat.Colors`. The sender's own line is the chat box's
echo, restyled through `OnIncomingMessage`; the server never sends it back. Roblox's own delivery is turned
off: the project file sets `CreateDefaultTextChannels` and `CreateDefaultCommands`
to false on TextChatService (they are not scriptable), and the "Net" channel the
chat box types into has `ShouldDeliverCallback` returning false.

## Zones, emotes, tickets

A zone is any Part tagged `Zone` (CollectionService). Its name is the zone name;
attributes `Pvp` and `Safe` describe it. The world server polls players every
`Config.ZonePollSeconds` and sends `SMSG_ZONE_UPDATE` on change; the client sets the
`Zone` and `ZoneKind` attributes on the Player and `ZoneBanner` fades the name in
like the WoW zone text. Two demo zones ship under `src/Workspace/Zones`.

`/wave`, `/dance`, `/laugh`, `/cheer`, `/point` play the R15 emote and tell everyone
in SAY range in orange. The table is `Config.Emotes`.

`/ticket <text>` opens a GM ticket (one open per player). Staff on every server get
a yellow notice; `.ticket` lists, views, replies to and closes them. Tickets live in
one `Tickets` DataStore record edited with `UpdateAsync`, so servers never overwrite
each other, and replies reach the player on whichever server they are on.

## Cross-server

`Global.h` is a bus on one MessagingService topic. A command does its local work,
then publishes; every other server reacts and the origin ignores its own message.
`.announce`, `.kick`, `.ban` and `.buff` are global this way, and `.kick`/`.ban`
accept the name of someone who is not on this server (looked up to a UserId).
`.buff all speed 2 60` doubles everyone's WalkSpeed for a minute on every server;
a multiplier under 1 is a debuff. Without MessagingService (Studio without API
access) it logs once and runs single-server.

## Saving

`Database.h` wraps DataStores with a per-key cache, retries, and a memory-only
fallback when the API is unreachable (Studio without API access). Accounts and
character state write when the player leaves, every `Config.AutosaveSeconds`, and on
shutdown.

## Run

Needs [Rojo](https://rojo.space). `rojo serve` and connect from Studio, or
`rojo build -o place.rbxl`. Players spawn only after the client authenticates;
`Players.CharacterAutoLoads` is off.
