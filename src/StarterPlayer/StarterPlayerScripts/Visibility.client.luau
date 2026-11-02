local Players = game:GetService("Players")
local player = Players.LocalPlayer

-- What this client may see. Creatures with GhostOnly (spirit healers) are
-- drawn only while you are a ghost or in GM mode; otherwise they are
-- transparent, untouchable and nameless, like a player would expect.

local function canSee(): boolean
	return player:GetAttribute("Ghost") == true or player:GetAttribute("GmMode") == true
end

local function apply(model: Model)
	local hidden = model:GetAttribute("GhostOnly") == true and not canSee()
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") or part:IsA("Decal") then
			part.LocalTransparencyModifier = if hidden then 1 else 0
		elseif part:IsA("ProximityPrompt") then
			part.Enabled = not hidden
		end
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = if hidden then Enum.HumanoidDisplayDistanceType.None else Enum.HumanoidDisplayDistanceType.Viewer
	end
end

local function refresh()
	local creatures = workspace:FindFirstChild("Creatures")
	for _, model in (creatures and creatures:GetChildren() or {}) do
		if model:IsA("Model") and model:GetAttribute("GhostOnly") then
			apply(model)
		end
	end
end

local creatures = workspace:WaitForChild("Creatures", 30)
if creatures then
	creatures.ChildAdded:Connect(function(model)
		task.defer(function()
			if model:IsA("Model") then
				apply(model)
			end
		end)
	end)
end
player:GetAttributeChangedSignal("Ghost"):Connect(refresh)
player:GetAttributeChangedSignal("GmMode"):Connect(refresh)
refresh()
