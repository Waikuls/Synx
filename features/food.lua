return function(Config)
	local Players = game:GetService("Players")
	local RunService = game:GetService("RunService")
	local LocalPlayer = Players.LocalPlayer
	local Notification = Config.Notification

	local FoodFeature = {
		Enabled = false,
		Connection = nil,
		Elapsed = 0,
		IsEating = false,
		LastEatAt = 0,
		LastMissingFoodAt = 0,
		ScanInterval = 0.5,
		EatCooldown = 3,
		EquipDelay = 0.35,
		ActivationDelay = 0.75,
		MaxActivationAttempts = 3,
		HungerThreshold = 0.35,
		FallbackThreshold = 25
	}

	local HungerCurrentAliases = {
		"CurrentHunger",
		"HungerCurrent",
		"HungerValue",
		"CurrentHungerValue",
		"HungerNow",
		"CurrentFood",
		"FoodLevel",
		"FoodValue",
		"NeedsHunger",
		"Food",
		"Hunger"
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
	local StarvingAliases = {
		"Starving",
		"IsStarving",
		"Hungry",
		"IsHungry"
	}
	local FoodToolAliases = {
		"food",
		"apple",
		"bread",
		"burger",
		"sandwich",
		"pizza",
		"meat",
		"steak",
		"fish",
		"rice",
		"soup",
		"meal",
		"snack"
	}

	local function createAliasRanking(Aliases)
		local Ranking = {}

		for Index, Name in ipairs(Aliases) do
			Ranking[string.lower(Name)] = Index
		end

		return Ranking
	end

	local HungerCurrentRanking = createAliasRanking(HungerCurrentAliases)
	local HungerMaxRanking = createAliasRanking(HungerMaxAliases)
	local HungerPercentRanking = createAliasRanking(HungerPercentAliases)
	local StarvingRanking = createAliasRanking(StarvingAliases)

	local function toNumber(Value)
		if typeof(Value) == "number" then
			return Value
		end

		if typeof(Value) == "string" then
			return tonumber(Value)
		end

		return nil
	end

	local function buildScanRoots()
		local Character = LocalPlayer.Character
		local Roots = {}
		local CommonFolders = {"Stats", "Data", "Information", "Profile", "PlayerData", "Values"}

		local function addRoot(Root, Priority)
			if Root then
				table.insert(Roots, {
					Root = Root,
					Priority = Priority
				})
			end
		end

		addRoot(LocalPlayer, 2)
		addRoot(Character, 2)

		for _, FolderName in ipairs(CommonFolders) do
			addRoot(LocalPlayer:FindFirstChild(FolderName), 1)

			if Character then
				addRoot(Character:FindFirstChild(FolderName), 1)
			end
		end

		for _, RootName in ipairs({"PlayerData", "Data", "Stats"}) do
			local Root = game:GetService("ReplicatedStorage"):FindFirstChild(RootName)

			if Root then
				addRoot(Root:FindFirstChild(LocalPlayer.Name), 0)
				addRoot(Root:FindFirstChild(tostring(LocalPlayer.UserId)), 0)

				local PlayersFolder = Root:FindFirstChild("Players")

				if PlayersFolder then
					addRoot(PlayersFolder:FindFirstChild(LocalPlayer.Name), 0)
					addRoot(PlayersFolder:FindFirstChild(tostring(LocalPlayer.UserId)), 0)
				end
			end
		end

		return Roots
	end

	local function getValueTypeScore(Value)
		local ValueType = typeof(Value)

		if ValueType == "number" then
			return 0
		end

		if ValueType == "string" then
			return 1
		end

		if ValueType == "boolean" then
			return 2
		end

		return 3
	end

	local function findBestValue(AliasRanking, Options)
		local Candidates = {}
		local Roots = buildScanRoots()

		local function getPartialRank(NameLower)
			if not Options or not Options.PartialMatcher then
				return nil
			end

			return Options.PartialMatcher(NameLower)
		end

		local function recordCandidate(Name, Value, Priority)
			local NameLower = string.lower(Name)
			local AliasRank = AliasRanking[NameLower]

			if AliasRank == nil then
				AliasRank = getPartialRank(NameLower)
			end

			if AliasRank == nil then
				return
			end

			table.insert(Candidates, {
				Value = Value,
				Priority = Priority,
				AliasRank = AliasRank,
				TypeScore = getValueTypeScore(Value),
				Name = NameLower
			})
		end

		for _, RootInfo in ipairs(Roots) do
			local Root = RootInfo.Root
			local Priority = RootInfo.Priority

			local function visit(Instance)
				if Instance:IsA("ValueBase") then
					recordCandidate(Instance.Name, Instance.Value, Priority)
				end

				for Name, Value in pairs(Instance:GetAttributes()) do
					recordCandidate(Name, Value, Priority)
				end
			end

			visit(Root)

			for _, Descendant in ipairs(Root:GetDescendants()) do
				visit(Descendant)
			end
		end

		table.sort(Candidates, function(Left, Right)
			if Left.AliasRank ~= Right.AliasRank then
				return Left.AliasRank < Right.AliasRank
			end

			if Left.Priority ~= Right.Priority then
				return Left.Priority < Right.Priority
			end

			if Left.TypeScore ~= Right.TypeScore then
				return Left.TypeScore < Right.TypeScore
			end

			return Left.Name < Right.Name
		end)

		return Candidates[1] and Candidates[1].Value or nil
	end

	local function isHungryFlag(Value)
		if typeof(Value) == "boolean" then
			return Value
		end

		if typeof(Value) == "string" then
			local Lower = string.lower(Value)

			if Lower == "true" then
				return true
			end

			if Lower == "false" then
				return false
			end
		end

		return false
	end

	local function shouldEat()
		local StarvingValue = findBestValue(StarvingRanking, {
			PartialMatcher = function(NameLower)
				if string.find(NameLower, "starv", 1, true) then
					return 100
				end

				if NameLower == "hungry" or NameLower == "ishungry" then
					return 101
				end

				return nil
			end
		})

		if isHungryFlag(StarvingValue) then
			return true
		end

		local PercentValue = findBestValue(HungerPercentRanking, {
			PartialMatcher = function(NameLower)
				local HasFoodName = string.find(NameLower, "hunger", 1, true) or string.find(NameLower, "food", 1, true)
				local HasPercentName = string.find(NameLower, "percent", 1, true) or string.find(NameLower, "ratio", 1, true)

				if HasFoodName and HasPercentName then
					return 100
				end

				return nil
			end
		})
		local CurrentValue = findBestValue(HungerCurrentRanking, {
			PartialMatcher = function(NameLower)
				local HasFoodName = string.find(NameLower, "hunger", 1, true) or string.find(NameLower, "food", 1, true)
				local IsMax = string.find(NameLower, "max", 1, true)
				local IsPercent = string.find(NameLower, "percent", 1, true) or string.find(NameLower, "ratio", 1, true)

				if HasFoodName and not IsMax and not IsPercent then
					return 100
				end

				return nil
			end
		})
		local MaxValue = findBestValue(HungerMaxRanking, {
			PartialMatcher = function(NameLower)
				local HasFoodName = string.find(NameLower, "hunger", 1, true) or string.find(NameLower, "food", 1, true)

				if HasFoodName and string.find(NameLower, "max", 1, true) then
					return 100
				end

				return nil
			end
		})

		local PercentNumber = toNumber(PercentValue)

		if PercentNumber then
			if PercentNumber <= 1 then
				PercentNumber = PercentNumber * 100
			end

			return PercentNumber <= 35
		end

		local CurrentNumber = toNumber(CurrentValue)
		local MaxNumber = toNumber(MaxValue)

		if CurrentNumber and MaxNumber and MaxNumber > 0 then
			return (CurrentNumber / MaxNumber) <= FoodFeature.HungerThreshold
		end

		if CurrentNumber then
			return CurrentNumber <= FoodFeature.FallbackThreshold
		end

		return false
	end

	local function getToolScore(Tool)
		if not Tool or not Tool:IsA("Tool") then
			return nil
		end

		if Tool:GetAttribute("Food") == true or Tool:GetAttribute("Consumable") == true then
			return 0
		end

		local NameLower = string.lower(Tool.Name)
		local ToolTipLower = string.lower(Tool.ToolTip or "")

		for Index, Alias in ipairs(FoodToolAliases) do
			if string.find(NameLower, Alias, 1, true) or string.find(ToolTipLower, Alias, 1, true) then
				return Index
			end
		end

		if string.find(NameLower, "eat", 1, true) or string.find(ToolTipLower, "eat", 1, true) then
			return 200
		end

		return nil
	end

	local function isFoodTool(Tool)
		return getToolScore(Tool) ~= nil
	end

	local function getCharacterHumanoid()
		local Character = LocalPlayer.Character

		if not Character then
			return nil, nil
		end

		return Character, Character:FindFirstChildOfClass("Humanoid")
	end

	local function findFoodTool()
		local Character = LocalPlayer.Character
		local Backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
		local BestTool = nil
		local BestScore = math.huge

		local function consider(Container)
			if not Container then
				return
			end

			for _, Item in ipairs(Container:GetChildren()) do
				local Score = getToolScore(Item)

				if Score and Score < BestScore then
					BestTool = Item
					BestScore = Score
				end
			end
		end

		consider(Character)
		consider(Backpack)

		return BestTool
	end

	local function unequipFoodTools()
		local Character, Humanoid = getCharacterHumanoid()
		local Backpack = LocalPlayer:FindFirstChildOfClass("Backpack")

		if not Character or not Humanoid then
			return
		end

		local HasEquippedFood = false

		for _, Item in ipairs(Character:GetChildren()) do
			if Item:IsA("Tool") and isFoodTool(Item) then
				HasEquippedFood = true
				break
			end
		end

		if not HasEquippedFood then
			return
		end

		Humanoid:UnequipTools()

		if Backpack then
			for _, Item in ipairs(Character:GetChildren()) do
				if Item:IsA("Tool") and isFoodTool(Item) then
					Item.Parent = Backpack
				end
			end
		end
	end

	local function notifyMissingFood()
		local Now = os.clock()

		if Now - FoodFeature.LastMissingFoodAt < 10 then
			return
		end

		FoodFeature.LastMissingFoodAt = Now

		if Notification then
			Notification:Notify({
				Title = "Food",
				Content = "No food found in your backpack.",
				Duration = 4,
				Icon = "info"
			})
		end
	end

	local function consumeFood(Tool)
		if FoodFeature.IsEating or not Tool then
			return
		end

		local Character, Humanoid = getCharacterHumanoid()

		if not Character or not Humanoid then
			return
		end

		FoodFeature.IsEating = true
		FoodFeature.LastEatAt = os.clock()

		task.spawn(function()
			if Tool.Parent ~= Character then
				Humanoid:EquipTool(Tool)
				task.wait(FoodFeature.EquipDelay)
			end

			if Tool.Parent == Character then
				pcall(function()
					if Tool.Enabled ~= nil then
						Tool.Enabled = true
					end
				end)
			end

			for _ = 1, FoodFeature.MaxActivationAttempts do
				if Tool.Parent ~= Character then
					break
				end

				pcall(function()
					Tool:Activate()
				end)

				task.wait(FoodFeature.ActivationDelay)

				if not shouldEat() then
					break
				end
			end

			unequipFoodTools()

			FoodFeature.IsEating = false
		end)
	end

	function FoodFeature:SetEnabled(Value)
		self.Enabled = Value and true or false

		if not self.Enabled then
			unequipFoodTools()
		end

		if not self.Connection then
			self.Connection = RunService.Heartbeat:Connect(function(DeltaTime)
				self.Elapsed = self.Elapsed + DeltaTime

				if self.Elapsed < self.ScanInterval then
					return
				end

				self.Elapsed = 0

				if not self.Enabled or self.IsEating then
					return
				end

				if os.clock() - self.LastEatAt < self.EatCooldown then
					return
				end

				if not shouldEat() then
					unequipFoodTools()
					return
				end

				local Tool = findFoodTool()

				if not Tool then
					notifyMissingFood()
					return
				end

				consumeFood(Tool)
			end)
		end

		return true
	end

	function FoodFeature:Destroy()
		self.Enabled = false
		self.IsEating = false
		unequipFoodTools()

		if self.Connection then
			self.Connection:Disconnect()
			self.Connection = nil
		end
	end

	return FoodFeature
end
