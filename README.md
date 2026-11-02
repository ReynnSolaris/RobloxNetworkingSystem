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
  WorldServer/Database/            WorldDatabase (position, health)
  GlobalModules/Database/          Database (DataStore wrapper), DatabaseUUID
  GlobalModules/System/            Compiler (resolves module includes)
src/StarterPlayer/StarterPlayerScripts/NetClient   the client half
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

Commands are typed in chat with a leading dot, WoW style:

```
.help                                   .who
.hurt <player> <amount>                 .heal [player]
.tele <x> <y> <z> | .tele <player>      .announce <text>
.kick <player> [reason]                 .ban <player> [reason]      .unban <userId>
.role <player> <PLAYER|MODERATOR|GAMEMASTER|OWNER>
```

## Chat

Channels: SAY (30 studs), YELL (100), WORLD, WHISPER, SYSTEM. On the client, `/y`,
`/w Name`, and `/world` pick the channel; anything else is SAY. Messages go through
`TextService` filtering and are delivered by packet. Roblox's own delivery is turned
off: the project file sets `CreateDefaultTextChannels` and `CreateDefaultCommands`
to false on TextChatService (they are not scriptable), and the "Net" channel the
chat box types into has `ShouldDeliverCallback` returning false.

## Saving

`Database.h` wraps DataStores with a per-key cache, retries, and a memory-only
fallback when the API is unreachable (Studio without API access). Accounts and
character state write when the player leaves, every `Config.AutosaveSeconds`, and on
shutdown.

## Run

Needs [Rojo](https://rojo.space). `rojo serve` and connect from Studio, or
`rojo build -o place.rbxl`. Players spawn only after the client authenticates;
`Players.CharacterAutoLoads` is off.
