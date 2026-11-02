-- Wire opcodes. CMSG = client to server, SMSG = server to client.
local Opcodes = {
	CMSG_AUTH_SESSION = 1,
	SMSG_AUTH_RESPONSE = 2,
	CMSG_PING = 3,
	SMSG_PONG = 4,

	SMSG_SPAWN = 10,
	SMSG_DESPAWN = 11,
	SMSG_HEALTH_UPDATE = 12,

	CMSG_MESSAGECHAT = 20,
	SMSG_MESSAGECHAT = 21,
	SMSG_NOTIFICATION = 22,

	SMSG_GM_STATE = 30,

	SMSG_ZONE_UPDATE = 40,

	CMSG_EMOTE = 50,
	SMSG_EMOTE = 51,

	CMSG_TICKET = 60,

	CMSG_PARTY = 70,
	SMSG_PARTY_UPDATE = 71,
	SMSG_PARTY_INVITE = 72,

	CMSG_CHAR_ENUM = 80,
	SMSG_CHAR_ENUM = 81,
	CMSG_CHAR_CREATE = 82,
	CMSG_CHAR_DELETE = 83,
	CMSG_PLAYER_LOGIN = 84,
	CMSG_LOGOUT_REQUEST = 85,
	SMSG_CHAR_RESULT = 86,

	SMSG_XP_GAIN = 90,
	SMSG_LEVELUP = 91,
	SMSG_ITEM_PUSH = 92,
	CMSG_INVENTORY = 93,
	SMSG_INVENTORY = 94,
}

local names = {}
for name, id in Opcodes do
	names[id] = name
end

function Opcodes.Name(id: number): string
	return names[id] or ("UNKNOWN_" .. tostring(id))
end

function Opcodes.IsClient(id: number): boolean
	local name = names[id]
	return name ~= nil and name:sub(1, 4) == "CMSG"
end

return table.freeze(Opcodes)
