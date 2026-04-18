return function()
	local Players = game:GetService("Players")
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local LocalPlayer = Players.LocalPlayer

	local StatsFeature = {
		TargetPlayerName = LocalPlayer.Name,
		HungerSignal = nil,
		LastHungerScanAt = 0,
		HungerRefreshInterval = 1
	}
	local PreferredLeftStats = {
		"Style",
		"Agility",
		"Strength",
		"Muscle",
		"Starving",
		"Hungry",
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

	local function trimString(Value)
		if typeof(Value) ~= "string" then
			return nil
		end

		return string.match(Value, "^%s*(.-)%s*$")
	end

	local function isReadableTextInstance(Instance)
		return Instance
			and (
				Instance:IsA("TextLabel")
				or Instance:IsA("TextButton")
				or Instance:IsA("TextBox")
			)
	end

	local function isVisibleTextInstance(Instance)
		if not Instance or not Instance:IsA("GuiObject") then
			return true
		end

		local Success, Value = pcall(function()
			return Instance.Visible
		end)

		if Success then
			return Value
		end

		return true
	end

	local function isExplicitFalseStatus(TextLower, StatusName)
		return string.match(TextLower, "^" .. StatusName .. "%s*:%s*false") ~= nil
	end

	local function isStatusText(TextLower, StatusName)
		return TextLower == StatusName or string.match(TextLower, "^" .. StatusName .. "%s*[:%-]") ~= nil
	end

	local function classifyHungerText(Text)
		local Trimmed = trimString(Text)

		if not Trimmed or Trimmed == "" then
			return nil, nil
		end

		local Lower = string.lower(Trimmed)

		if isExplicitFalseStatus(Lower, "hungry")
			or isExplicitFalseStatus(Lower, "ishungry")
			or isExplicitFalseStatus(Lower, "starving")
			or isExplicitFalseStatus(Lower, "isstarving")
			or Lower == "not hungry"
			or Lower == "full"
			or Lower == "well fed" then
			return false, Trimmed
		end

		if string.find(Lower, "lack of nutrients", 1, true) then
			return true, Trimmed
		end

		if isStatusText(Lower, "hungry")
			or isStatusText(Lower, "ishungry")
			or isStatusText(Lower, "starving")
			or isStatusText(Lower, "isstarving") then
			return true, Trimmed
		end

		return nil, nil
	end

	local function readLocalHungerTextSignal()
		local Character = LocalPlayer.Character
		local Roots = {
			LocalPlayer:FindFirstChild("PlayerGui"),
			Character
		}
		local NegativeText = nil

		for _, Root in ipairs(Roots) do
			if Root then
				local function visit(Instance)
					if not isReadableTextInstance(Instance) or not isVisibleTextInstance(Instance) then
						return nil
					end

					local Success, Text = pcall(function()
						return Instance.Text
					end)

					if not Success then
						return nil
					end

					local IsHungry, MatchedText = classifyHungerText(Text)

					if IsHungry == true then
						return {
							HasSignal = true,
							IsHungry = true,
							Text = MatchedText
						}
					end

					if IsHungry == false and not NegativeText then
						NegativeText = MatchedText
					end

					return nil
				end

				local Result = visit(Root)

				if Result then
					return Result
				end

				for _, Descendant in ipairs(Root:GetDescendants()) do
					Result = visit(Descendant)

					if Result then
						return Result
					end
				end
			end
		end

		if NegativeText then
			return {
				HasSignal = true,
				IsHungry = false,
				Text = NegativeText
			}
		end

		return {
			HasSignal = false,
			IsHungry = false,
			Text = nil
		}
	end

	local function scanLocalHungerText(ForceRefresh)
		local Now = os.clock()

		if not ForceRefresh
			and StatsFeature.HungerSignal
			and (Now - StatsFeature.LastHungerScanAt) < StatsFeature.HungerRefreshInterval then
			return StatsFeature.HungerSignal
		end

		StatsFeature.HungerSignal = readLocalHungerTextSignal()
		StatsFeature.LastHungerScanAt = Now

		return StatsFeature.HungerSignal
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

	local function buildPreferredPanels(TargetPlayer)
		local Store = {}
		local LeftLines = {}
		local RightLines = {}
		local FoundCount = 0

		addPreferredRoots(Store, TargetPlayer)

		if TargetPlayer == LocalPlayer then
			local HungerSignal = scanLocalHungerText()

			if HungerSignal.HasSignal then
				recordPreferredValue(Store, "Hungry", HungerSignal.IsHungry, -1)
			end
		end

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

		return LeftLines, RightLines
	end

	return StatsFeature
end
