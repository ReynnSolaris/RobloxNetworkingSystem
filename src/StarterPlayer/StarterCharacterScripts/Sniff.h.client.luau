local player = game.Players.LocalPlayer
local savedValues = {}
player.ChildAdded:Connect(function(child)
	if child.Name:match("%-PACKET") then
		child.Name = "EncryptedPacket"
		local random = math.random(1,2e6)
		savedValues[tostring(random)] = child.Value
		child.Value = tostring(random)
		print("Encrypted Locally")
	end
end)