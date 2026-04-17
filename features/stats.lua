return function()
	local Players = game:GetService("Players")
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local LocalPlayer = Players.LocalPlayer

	local StatsFeature = {}
	local PreferredLeftStats = {
		"Style",
		"Agility",
		"Strength",
		"Muscle",
		"Hunger",
		"Starving",
		"Offensive",
		"Durability",
		"RhythmCharge",
		"StaminaInStat",
		"Stamina",
		"MaxStamina",
		"Fat",
		"AttackSpeed",
		"BodySize",
		"DownedHealth",
		"MaxDownedHealth",
		"RecoveryHealth",
		"BodyHeat",
		"Exhaustion"
	}
	local PreferredRightStats = {
		"NoCooldown",
		"BodyFatique",
		"BodyFatigue",
		"Eevee",
		"EeveeDeplete",
		"FirstName",
		"MiddleName",
		"ClanName",
		"NoStaminaCost",
		"UpperMuscle",
		"LowerMuscle",
		"IsTrainingWithMachine",
		"TrainingMachine",
		"Gender",
		"Training",
		"TrainingWithTool",
		"Mode",
		"TotalPower",
		"Adrenaline",
		"Sleeping",
		"NoEeveeDeplete"
	}
	local PreferredLookup = {}

	for _, Name in ipairs(PreferredLeftStats) do
		PreferredLookup[Name] = true
	end

	for _, Name in ipairs(PreferredRightStats) do
		PreferredLookup[Name] = true
	end

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

	local function formatValue(Value)
		local ValueType = typeof(Value)

		if Value == nil then
			return "nil"
		end

		if ValueType == "number" then
			return formatNumber(Value)
		end

		if ValueType == "boolean" then
			return tostring(Value)
		end

		if ValueType == "Vector3" then
			return formatVector(Value)
		end

		if ValueType == "CFrame" then
			return formatVector(Value.Position)
		end

		if ValueType == "Instance" then
			return Value.Name
		end

		if ValueType == "EnumItem" then
			return Value.Name
		end

		return tostring(Value)
	end

	local function recordPreferredValue(Store, Name, Value, Priority)
		local Current = Store[Name]

		if Current and Current.Priority <= Priority then
			return
		end

		Store[Name] = {
			Value = formatValue(Value),
			Priority = Priority
		}
	end

	local function scanPreferredValues(Store, Root, Priority)
		if not Root then
			return
		end

		local function visit(Instance)
			if Instance:IsA("ValueBase") and PreferredLookup[Instance.Name] then
				recordPreferredValue(Store, Instance.Name, Instance.Value, Priority)
			end

			for Name, Value in pairs(Instance:GetAttributes()) do
				if PreferredLookup[Name] then
					recordPreferredValue(Store, Name, Value, Priority)
				end
			end
		end

		visit(Root)

		for _, Descendant in ipairs(Root:GetDescendants()) do
			visit(Descendant)
		end
	end

	local function addPreferredRoots(Store)
		local Character = LocalPlayer.Character
		local CommonFolders = {"Stats", "Data", "Information", "Profile", "PlayerData", "Values"}

		scanPreferredValues(Store, LocalPlayer, 2)
		scanPreferredValues(Store, Character, 2)

		for _, FolderName in ipairs(CommonFolders) do
			scanPreferredValues(Store, LocalPlayer:FindFirstChild(FolderName), 1)

			if Character then
				scanPreferredValues(Store, Character:FindFirstChild(FolderName), 1)
			end
		end

		for _, RootName in ipairs({"PlayerData", "Data", "Stats"}) do
			local Root = ReplicatedStorage:FindFirstChild(RootName)

			if Root then
				scanPreferredValues(Store, Root:FindFirstChild(LocalPlayer.Name), 0)
				scanPreferredValues(Store, Root:FindFirstChild(tostring(LocalPlayer.UserId)), 0)

				local PlayersFolder = Root:FindFirstChild("Players")

				if PlayersFolder then
					scanPreferredValues(Store, PlayersFolder:FindFirstChild(LocalPlayer.Name), 0)
					scanPreferredValues(Store, PlayersFolder:FindFirstChild(tostring(LocalPlayer.UserId)), 0)
				end
			end
		end
	end

	local function buildPreferredPanels()
		local Store = {}
		local LeftLines = {}
		local RightLines = {}
		local FoundCount = 0

		addPreferredRoots(Store)

		for _, Name in ipairs(PreferredLeftStats) do
			local Entry = Store[Name]

			if Entry then
				table.insert(LeftLines, string.format("%s: %s", Name, Entry.Value))
				FoundCount = FoundCount + 1
			end
		end

		for _, Name in ipairs(PreferredRightStats) do
			local Entry = Store[Name]

			if Entry then
				table.insert(RightLines, string.format("%s: %s", Name, Entry.Value))
				FoundCount = FoundCount + 1
			end
		end

		return LeftLines, RightLines, FoundCount
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
		local PreferredLeft, PreferredRight, PreferredCount = buildPreferredPanels()

		if PreferredCount >= 4 then
			return PreferredLeft, PreferredRight
		end

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
