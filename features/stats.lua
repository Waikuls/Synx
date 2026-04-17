return function()
	local Players = game:GetService("Players")
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local LocalPlayer = Players.LocalPlayer

	local StatsFeature = {
		TargetPlayerName = LocalPlayer.Name
	}
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
	local HungerCurrentAliases = {
		"Hunger",
		"CurrentHunger",
		"HungerCurrent",
		"Food",
		"CurrentFood",
		"FoodLevel",
		"HungerValue",
		"NeedsHunger",
		"HungerNow"
	}
	local HungerMaxAliases = {
		"MaxHunger",
		"MaximumHunger",
		"HungerMax",
		"MaxFood",
		"MaximumFood",
		"FoodMax",
		"MaxFoodLevel"
	}
	local HungerPercentAliases = {
		"HungerPercent",
		"FoodPercent",
		"HungerRatio"
	}

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

	local function createAliasLookup(Aliases)
		local Lookup = {}

		for _, Name in ipairs(Aliases) do
			Lookup[string.lower(Name)] = true
		end

		return Lookup
	end

	local HungerCurrentAliasLookup = createAliasLookup(HungerCurrentAliases)
	local HungerMaxAliasLookup = createAliasLookup(HungerMaxAliases)
	local HungerPercentAliasLookup = createAliasLookup(HungerPercentAliases)

	local function addPreferredRoots(Store, TargetPlayer)
		local Character = TargetPlayer and TargetPlayer.Character
		local CommonFolders = {"Stats", "Data", "Information", "Profile", "PlayerData", "Values"}

		scanPreferredValues(Store, TargetPlayer, 2)
		scanPreferredValues(Store, Character, 2)

		for _, FolderName in ipairs(CommonFolders) do
			scanPreferredValues(Store, TargetPlayer and TargetPlayer:FindFirstChild(FolderName), 1)

			if Character then
				scanPreferredValues(Store, Character:FindFirstChild(FolderName), 1)
			end
		end

		for _, RootName in ipairs({"PlayerData", "Data", "Stats"}) do
			local Root = ReplicatedStorage:FindFirstChild(RootName)

			if Root then
				scanPreferredValues(Store, Root:FindFirstChild(TargetPlayer.Name), 0)
				scanPreferredValues(Store, Root:FindFirstChild(tostring(TargetPlayer.UserId)), 0)

				local PlayersFolder = Root:FindFirstChild("Players")

				if PlayersFolder then
					scanPreferredValues(Store, PlayersFolder:FindFirstChild(TargetPlayer.Name), 0)
					scanPreferredValues(Store, PlayersFolder:FindFirstChild(tostring(TargetPlayer.UserId)), 0)
				end
			end
		end
	end

	local function findRawStatByAliases(TargetPlayer, AliasesLookup)
		local Character = TargetPlayer and TargetPlayer.Character
		local CommonFolders = {"Stats", "Data", "Information", "Profile", "PlayerData", "Values"}
		local Roots = {}

		local function addRoot(Root)
			if Root then
				table.insert(Roots, Root)
			end
		end

		local function scanRoot(Root)
			if not Root then
				return nil
			end

			local function visit(Instance)
				if Instance:IsA("ValueBase") and AliasesLookup[string.lower(Instance.Name)] then
					return Instance.Value
				end

				for Name, Value in pairs(Instance:GetAttributes()) do
					if AliasesLookup[string.lower(Name)] then
						return Value
					end
				end

				return nil
			end

			local Result = visit(Root)

			if Result ~= nil then
				return Result
			end

			for _, Descendant in ipairs(Root:GetDescendants()) do
				Result = visit(Descendant)

				if Result ~= nil then
					return Result
				end
			end

			return nil
		end

		addRoot(TargetPlayer)
		addRoot(Character)

		for _, FolderName in ipairs(CommonFolders) do
			addRoot(TargetPlayer and TargetPlayer:FindFirstChild(FolderName))

			if Character then
				addRoot(Character:FindFirstChild(FolderName))
			end
		end

		for _, RootName in ipairs({"PlayerData", "Data", "Stats"}) do
			local Root = ReplicatedStorage:FindFirstChild(RootName)

			if Root then
				addRoot(Root:FindFirstChild(TargetPlayer.Name))
				addRoot(Root:FindFirstChild(tostring(TargetPlayer.UserId)))

				local PlayersFolder = Root:FindFirstChild("Players")

				if PlayersFolder then
					addRoot(PlayersFolder:FindFirstChild(TargetPlayer.Name))
					addRoot(PlayersFolder:FindFirstChild(tostring(TargetPlayer.UserId)))
				end
			end
		end

		for _, Root in ipairs(Roots) do
			local Result = scanRoot(Root)

			if Result ~= nil then
				return Result
			end
		end

		return nil
	end

	local function formatHungerLine(TargetPlayer)
		local CurrentHungerRaw = findRawStatByAliases(TargetPlayer, HungerCurrentAliasLookup)
		local MaxHungerRaw = findRawStatByAliases(TargetPlayer, HungerMaxAliasLookup)
		local PercentHungerRaw = findRawStatByAliases(TargetPlayer, HungerPercentAliasLookup)

		if CurrentHungerRaw == nil and PercentHungerRaw == nil then
			return nil
		end

		local Line = nil

		if CurrentHungerRaw ~= nil and MaxHungerRaw ~= nil then
			Line = string.format("Hunger: %s/%s", formatValue(CurrentHungerRaw), formatValue(MaxHungerRaw))
		elseif CurrentHungerRaw ~= nil then
			Line = string.format("Hunger: %s", formatValue(CurrentHungerRaw))
		else
			Line = string.format("Hunger: %s%%", formatValue(PercentHungerRaw))
		end

		if PercentHungerRaw ~= nil then
			local PercentText = formatValue(PercentHungerRaw)

			if typeof(PercentHungerRaw) == "number" then
				local NumericPercent = PercentHungerRaw

				if NumericPercent <= 1 then
					NumericPercent = NumericPercent * 100
				end

				PercentText = string.format("%.0f", NumericPercent)
			end

			if not string.find(Line, "%%", 1, true) then
				Line = string.format("%s (%s%%)", Line, PercentText)
			end
		end

		return Line
	end

	local function ensureHungerLine(TargetPlayer, Lines)
		local ExistingIndex = nil

		for Index, Line in ipairs(Lines) do
			if string.match(Line, "^Hunger:") then
				ExistingIndex = Index
				break
			end
		end

		local HungerLine = formatHungerLine(TargetPlayer)

		if HungerLine then
			if ExistingIndex then
				Lines[ExistingIndex] = HungerLine
			else
				local InsertIndex = math.min(#Lines + 1, 6)

				table.insert(Lines, InsertIndex, HungerLine)
			end
		end
	end

	local function buildPreferredPanels(TargetPlayer)
		local Store = {}
		local LeftLines = {}
		local RightLines = {}
		local FoundCount = 0

		addPreferredRoots(Store, TargetPlayer)

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

	local function getLeaderstatsLines(TargetPlayer)
		local Leaderstats = TargetPlayer and TargetPlayer:FindFirstChild("leaderstats")
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

	local function sortPlayerNames(Names)
		table.sort(Names, function(Left, Right)
			if Left == LocalPlayer.Name then
				return true
			end

			if Right == LocalPlayer.Name then
				return false
			end

			return string.lower(Left) < string.lower(Right)
		end)
	end

	function StatsFeature:GetTargetPlayer()
		local TargetPlayer = self.TargetPlayerName and Players:FindFirstChild(self.TargetPlayerName)

		if TargetPlayer then
			return TargetPlayer
		end

		self.TargetPlayerName = LocalPlayer.Name

		return LocalPlayer
	end

	function StatsFeature:GetTargetPlayerName()
		return self:GetTargetPlayer().Name
	end

	function StatsFeature:SetTargetPlayer(PlayerName)
		if type(PlayerName) == "string" and PlayerName ~= "" then
			local TargetPlayer = Players:FindFirstChild(PlayerName)

			if TargetPlayer then
				self.TargetPlayerName = TargetPlayer.Name

				return TargetPlayer
			end
		end

		self.TargetPlayerName = LocalPlayer.Name

		return LocalPlayer
	end

	function StatsFeature:GetPlayerOptions()
		local PlayerNames = {}

		for _, Player in ipairs(Players:GetPlayers()) do
			table.insert(PlayerNames, Player.Name)
		end

		sortPlayerNames(PlayerNames)

		return PlayerNames
	end

	function StatsFeature:GetPanels()
		local TargetPlayer = self:GetTargetPlayer()
		local PreferredLeft, PreferredRight, PreferredCount = buildPreferredPanels(TargetPlayer)

		if PreferredCount >= 4 then
			ensureHungerLine(TargetPlayer, PreferredLeft)
			return PreferredLeft, PreferredRight
		end

		local Character = TargetPlayer.Character
		local Humanoid = Character and Character:FindFirstChildOfClass("Humanoid")
		local RootPart = Character and Character:FindFirstChild("HumanoidRootPart")
		local SpawnLocation = Character and Character:GetPivot().Position or nil
		local LeaderstatsLines = getLeaderstatsLines(TargetPlayer)

		local LeftLines = {
			string.format("DisplayName: %s", TargetPlayer.DisplayName),
			string.format("Username: %s", TargetPlayer.Name),
			string.format("UserId: %s", TargetPlayer.UserId),
			string.format("Character: %s", Character and "Loaded" or "Missing"),
			string.format("Tool: %s", getToolName(Character)),
		}

		local RightLines = {
			string.format("PlayerCount: %d", #Players:GetPlayers()),
			string.format("Team: %s", TargetPlayer.Team and TargetPlayer.Team.Name or "None"),
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

		ensureHungerLine(TargetPlayer, LeftLines)

		return LeftLines, RightLines
	end

	return StatsFeature
end
