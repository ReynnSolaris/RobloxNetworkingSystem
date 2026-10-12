local module = {}
--[[
	Module Base
--]]
--[[
	Module Custom Functions
--]]

local StoredPackets = {
	
}

--[[
	createPacket () -> Instituates a Packet Class
--]]

function module:createPacket(PlayerInstance:Instance, PacketIdenitifer:string, PacketData:{}?)
	local Value = Instance.new("StringValue")
	Value.Value = self.includes["Database"]["DatabaseUUID.h"]:GenerateUUID("SECURITY_RBAC_1")
	Value.Name = PacketIdenitifer.."-PACKET"
	Value.Parent = PlayerInstance
	StoredPackets[Value.Value] = {PACKET_OBJ = Value, TYPE = Value.Name, DATA = PacketData}
	print(("PACKET DATA FOR [%s]"):format(Value.Value))
	print(StoredPackets[Value.Value])
end

--[[
	readPacket () -> Reads from Stored Packets and Deletes
--]]

function module:readPacket(PacketUUID:string)
	if StoredPackets[PacketUUID] then
		local static = StoredPackets[PacketUUID]
		static.PACKET_OBJ:Destroy()
		static.PACKET_OBJ = nil
		StoredPackets[PacketUUID] = nil
		return static
	end
	return false
end

return function()
	return setmetatable({
		["includes"] = {
			{
				["Path"] = "Global/Database",
				["Imports"] = "DatabaseUUID.h"
			}		
		},
		["information"] = {}
	}, {
		__index = function(self, index)
			if module[index] ~= nil then
				if typeof(module[index]) == "function" then
					return function(self, ...)
						return module[index](self, ...)
					end
				else
					return module[index]
				end
			end
		end,
	})
end
