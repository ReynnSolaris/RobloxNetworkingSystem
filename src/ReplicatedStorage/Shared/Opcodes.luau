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
