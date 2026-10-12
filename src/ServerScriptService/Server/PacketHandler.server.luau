local getReference = script.Parent:WaitForChild("Server_Reference")
game.Players.PlayerAdded:Connect(function(Player)
	Player.ChildAdded:Connect(function(child)
		if child.Name:match("%-PACKET") then
			local ref = getReference:Invoke("AUTH")
			local packetService = ref["Security"]["Packet.h"]
			print(packetService)
			print(packetService.readPacket(child.Value))
		end
	end)
end)