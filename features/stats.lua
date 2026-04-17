return function()
	local Players = game:GetService("Players")
	local LocalPlayer = Players.LocalPlayer

	local StatsFeature = {}

	local function formatNumber(Value)
		if typeof(Value) ~= "number" then
			return tostring(Value)
		end

		if math.abs(Value) >= 1000 then
			return string.format("%.0f", Value)
		end

		return string.format("%.2f", Value)
	end

	local function formatVector(Value)
		return string.format("%s, %s, %s", formatNumber(Value.X), formatNumber(Value.Y), formatNumber(Value.Z))
	end

	local function findScale(Character, Name)
		local Scale = Character and Character:FindFirstChild(Name)

		if Scale and Scale:IsA("NumberValue") then
			return formatNumber(Scale.Value)
		end

		return "N/A"
	end

	local function getToolName(Character)
		if not Character then
			return "None"
		end

		for _, Item in ipairs(Character:GetChildren()) do
			if Item:IsA("Tool") then
				return Item.Name
			end
		end

		return "None"
	end

	local function getLeaderstatsLines()
		local Leaderstats = LocalPlayer:FindFirstChild("leaderstats")
		local Lines = {}

		if not Leaderstats then
			return Lines
		end

		for _, Value in ipairs(Leaderstats:GetChildren()) do
			if Value:IsA("ValueBase") then
				table.insert(Lines, string.format("%s: %s", Value.Name, tostring(Value.Value)))
			end
		end

		return Lines
	end

	function StatsFeature:GetPanels()
		local Character = LocalPlayer.Character
		local Humanoid = Character and Character:FindFirstChildOfClass("Humanoid")
		local RootPart = Character and Character:FindFirstChild("HumanoidRootPart")
		local SpawnLocation = Character and Character:GetPivot().Position or nil
		local LeaderstatsLines = getLeaderstatsLines()

		local LeftLines = {
			string.format("DisplayName: %s", LocalPlayer.DisplayName),
			string.format("Username: %s", LocalPlayer.Name),
			string.format("UserId: %s", LocalPlayer.UserId),
			string.format("Character: %s", Character and "Loaded" or "Missing"),
			string.format("Tool: %s", getToolName(Character)),
		}

		local RightLines = {
			string.format("PlayerCount: %d", #Players:GetPlayers()),
			string.format("Team: %s", LocalPlayer.Team and LocalPlayer.Team.Name or "None"),
		}

		if Humanoid and RootPart then
			local Velocity = RootPart.AssemblyLinearVelocity
			local State = Humanoid:GetState()

			table.insert(LeftLines, string.format("Health: %s/%s", formatNumber(Humanoid.Health), formatNumber(Humanoid.MaxHealth)))
			table.insert(LeftLines, string.format("WalkSpeed: %s", formatNumber(Humanoid.WalkSpeed)))
			table.insert(LeftLines, string.format("JumpPower: %s", formatNumber(Humanoid.JumpPower)))
			table.insert(LeftLines, string.format("HipHeight: %s", formatNumber(Humanoid.HipHeight)))
			table.insert(LeftLines, string.format("RigType: %s", Humanoid.RigType.Name))
			table.insert(LeftLines, string.format("State: %s", State.Name))
			table.insert(LeftLines, string.format("Floor: %s", tostring(Humanoid.FloorMaterial)))
			table.insert(LeftLines, string.format("Alive: %s", tostring(Humanoid.Health > 0)))

			table.insert(RightLines, string.format("Position: %s", formatVector(RootPart.Position)))
			table.insert(RightLines, string.format("Velocity: %s", formatVector(Velocity)))
			table.insert(RightLines, string.format("Speed: %s", formatNumber(Velocity.Magnitude)))
			table.insert(RightLines, string.format("MoveDir: %s", formatNumber(Humanoid.MoveDirection.Magnitude)))
			table.insert(RightLines, string.format("Mass: %s", formatNumber(RootPart.AssemblyMass)))
			table.insert(RightLines, string.format("BodyHeightScale: %s", findScale(Character, "BodyHeightScale")))
			table.insert(RightLines, string.format("BodyWidthScale: %s", findScale(Character, "BodyWidthScale")))
			table.insert(RightLines, string.format("BodyDepthScale: %s", findScale(Character, "BodyDepthScale")))
			table.insert(RightLines, string.format("HeadScale: %s", findScale(Character, "HeadScale")))

			if SpawnLocation then
				table.insert(RightLines, string.format("Pivot: %s", formatVector(SpawnLocation)))
			end
		else
			table.insert(LeftLines, "Humanoid: Missing")
			table.insert(RightLines, "RootPart: Missing")
		end

		for _, Line in ipairs(LeaderstatsLines) do
			table.insert(RightLines, Line)
		end

		return LeftLines, RightLines
	end

	return StatsFeature
end
