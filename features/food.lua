return function(Config)
	local Players = game:GetService("Players")
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local RunService = game:GetService("RunService")
	local LocalPlayer = Players.LocalPlayer
	local Notification = Config.Notification

	local FoodFeature = {
		Enabled = false,
		Connection = nil,
		Elapsed = 0,
		IsEating = false,
		StopRequested = false,
		LastEatAt = 0,
		LastMissingFoodAt = 0,
		ScanInterval = 0.5,
		HungerRefreshInterval = 1,
		MissingFoodRetryDelay = 2,
		EatCooldown = 3,
		EquipDelay = 0.35,
		EquipRetryDelay = 0.12,
		HoldBeforeUseDelay = 0.18,
		ActivationDelay = 0.75,
		InputPressDelay = 0.08,
		MaxEquipAttempts = 3,
		MaxActivationAttempts = 3,
		DirectHungerThreshold = 15,
		HungerThreshold = 0.15,
		FallbackThreshold = 15,
		NoFoodAction = "Do nothing",
		AutoManagedTool = nil,
		HungerSnapshot = nil,
		LastHungerScanAt = 0,
		HungerValueObject = nil,
		KnownHotbarOrder = {},
		RemoteCache = {}
	}
	local ToolIdentityCache = setmetatable({}, {__mode = "k"})
	local NextToolIdentity = 0

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
		"ramen",
		"onigiri",
		"taco",
		"hotdog",
		"cola",
		"donut",
		"chocolate croissant",
		"caramel milkshake",
		"burger",
		"fries",
		"pizza",
		"kebab"
	}
	local SupplementBlacklist = {
		"whey protein",
		"whey",
		"fat burner",
		"muscle burner",
		"protein shake",
		"supplement"
	}
	local SlotKeyNames = {
		"One",
		"Two",
		"Three",
		"Four",
		"Five",
		"Six",
		"Seven",
		"Eight",
		"Nine",
		"Zero"
	}
	local SlotNameLookup = {
		one = 1,
		two = 2,
		three = 3,
		four = 4,
		five = 5,
		six = 6,
		seven = 7,
		eight = 8,
		nine = 9,
		zero = 10
	}
	local ToolSlotAttributeAliases = {
		"Slot",
		"Index",
		"HotbarSlot",
		"ToolSlot",
		"Number",
		"Keybind"
	}
	local SlotKeyCodes = {
		One = Enum.KeyCode.One,
		Two = Enum.KeyCode.Two,
		Three = Enum.KeyCode.Three,
		Four = Enum.KeyCode.Four,
		Five = Enum.KeyCode.Five,
		Six = Enum.KeyCode.Six,
		Seven = Enum.KeyCode.Seven,
		Eight = Enum.KeyCode.Eight,
		Nine = Enum.KeyCode.Nine,
		Zero = Enum.KeyCode.Zero
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

	local function trimString(Value)
		if typeof(Value) ~= "string" then
			return nil
		end

		return string.match(Value, "^%s*(.-)%s*$")
	end

	local function parseRatio(Value)
		if typeof(Value) ~= "string" then
			return nil, nil
		end

		local Left, Right = string.match(Value, "([%-%d%.]+)%s*/%s*([%-%d%.]+)")

		if not Left or not Right then
			return nil, nil
		end

		return tonumber(Left), tonumber(Right)
	end

	local function parseLooseNumber(Value)
		local NumberValue = toNumber(Value)

		if NumberValue ~= nil then
			return NumberValue
		end

		if typeof(Value) ~= "string" then
			return nil
		end

		local Trimmed = trimString(Value)

		if not Trimmed or Trimmed == "" then
			return nil
		end

		local RatioLeft = select(1, parseRatio(Trimmed))

		if RatioLeft ~= nil then
			return RatioLeft
		end

		local NumberText = string.match(Trimmed, "[%-%d%.]+")

		if NumberText then
			return tonumber(NumberText)
		end

		return nil
	end

	local function parsePercentValue(Value)
		if typeof(Value) == "number" then
			if Value <= 1 then
				return Value * 100
			end

			return Value
		end

		if typeof(Value) ~= "string" then
			return nil
		end

		local Trimmed = trimString(Value)

		if not Trimmed or Trimmed == "" then
			return nil
		end

		local RatioCurrent, RatioMax = parseRatio(Trimmed)

		if RatioCurrent and RatioMax and RatioMax > 0 then
			return (RatioCurrent / RatioMax) * 100
		end

		local NumberText = string.match(Trimmed, "[%-%d%.]+")
		local NumberValue = NumberText and tonumber(NumberText) or nil

		if NumberValue == nil then
			return nil
		end

		if NumberValue <= 1 and not string.find(Trimmed, "%", 1, true) then
			return NumberValue * 100
		end

		return NumberValue
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

	local function getInstanceText(Instance)
		if not isReadableTextInstance(Instance) or not isVisibleTextInstance(Instance) then
			return nil
		end

		local Success, Value = pcall(function()
			return Instance.Text
		end)

		if not Success or typeof(Value) ~= "string" then
			return nil
		end

		return trimString(Value)
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
			return nil
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

		return nil
	end

	local function scanHungerTextSignal()
		local Character = LocalPlayer.Character
		local Roots = {
			LocalPlayer:FindFirstChild("PlayerGui"),
			Character
		}
		local NegativeText = nil

		for _, Root in ipairs(Roots) do
			if Root then
				local function visit(Instance)
					local Text = getInstanceText(Instance)

					if not Text then
						return nil
					end

					local IsHungry, MatchedText = classifyHungerText(Text)

					if IsHungry == true then
						return {
							HasSignal = true,
							ShouldEat = true,
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

		return {
			HasSignal = NegativeText ~= nil,
			ShouldEat = false,
			Text = NegativeText
		}
	end

	local function toSlotIndex(Value)
		local NumberValue = toNumber(Value)

		if NumberValue then
			NumberValue = math.floor(NumberValue)

			if NumberValue >= 1 and NumberValue <= #SlotKeyNames then
				return NumberValue
			end
		end

		if typeof(Value) == "string" then
			return SlotNameLookup[string.lower(Value)]
		end

		return nil
	end

	local function isNumericValueObject(Instance)
		return Instance
			and Instance:IsA("ValueBase")
			and typeof(Instance.Value) == "number"
	end

	local function getWorkspaceEntity()
		local Entities = workspace:FindFirstChild("Entities")

		if not Entities then
			return nil
		end

		return Entities:FindFirstChild(LocalPlayer.Name)
	end

	local function findMainScriptRoot()
		local Entity = getWorkspaceEntity()

		if not Entity then
			return nil
		end

		local MainScript = Entity:FindFirstChild("MainScript")

		if MainScript then
			return MainScript
		end

		for _, Descendant in ipairs(Entity:GetDescendants()) do
			if Descendant.Name == "MainScript" then
				return Descendant
			end
		end

		return nil
	end

	local function findDirectHungerValueObject()
		local Cached = FoodFeature.HungerValueObject

		if isNumericValueObject(Cached) and Cached.Parent then
			return Cached
		end

		local MainScript = findMainScriptRoot()

		if not MainScript then
			FoodFeature.HungerValueObject = nil
			return nil
		end

		local Stats = MainScript:FindFirstChild("Stats")
		local HungerValue = Stats and Stats:FindFirstChild("Hunger")

		if isNumericValueObject(HungerValue) then
			FoodFeature.HungerValueObject = HungerValue
			return HungerValue
		end

		for _, Descendant in ipairs(MainScript:GetDescendants()) do
			if Descendant.Name == "Hunger" and isNumericValueObject(Descendant) then
				FoodFeature.HungerValueObject = Descendant
				return Descendant
			end
		end

		FoodFeature.HungerValueObject = nil

		return nil
	end

	local function getDirectHungerValue()
		local HungerValueObject = findDirectHungerValueObject()

		if not HungerValueObject then
			return nil
		end

		return HungerValueObject.Value
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
			local Root = ReplicatedStorage:FindFirstChild(RootName)

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

	local function getPartialHungerRank(Kind, NameLower)
		if Kind == "starving" then
			if string.find(NameLower, "starv", 1, true) then
				return 100
			end

			if NameLower == "hungry" or NameLower == "ishungry" then
				return 101
			end

			return nil
		end

		if Kind == "percent" then
			local HasFoodName = string.find(NameLower, "hunger", 1, true) or string.find(NameLower, "food", 1, true)
			local HasPercentName = string.find(NameLower, "percent", 1, true) or string.find(NameLower, "ratio", 1, true)

			if HasFoodName and HasPercentName then
				return 100
			end

			return nil
		end

		if Kind == "current" then
			local HasFoodName = string.find(NameLower, "hunger", 1, true) or string.find(NameLower, "food", 1, true)
			local IsMax = string.find(NameLower, "max", 1, true)
			local IsPercent = string.find(NameLower, "percent", 1, true) or string.find(NameLower, "ratio", 1, true)

			if HasFoodName and not IsMax and not IsPercent then
				return 100
			end

			return nil
		end

		if Kind == "max" then
			local HasFoodName = string.find(NameLower, "hunger", 1, true) or string.find(NameLower, "food", 1, true)

			if HasFoodName and string.find(NameLower, "max", 1, true) then
				return 100
			end
		end

		return nil
	end

	local function getHungerAliasRank(Kind, NameLower)
		local Ranking = Kind == "starving" and StarvingRanking
			or Kind == "percent" and HungerPercentRanking
			or Kind == "current" and HungerCurrentRanking
			or HungerMaxRanking
		local AliasRank = Ranking[NameLower]

		if AliasRank ~= nil then
			return AliasRank
		end

		return getPartialHungerRank(Kind, NameLower)
	end

	local function isBetterHungerCandidate(NewCandidate, CurrentCandidate)
		if not CurrentCandidate then
			return true
		end

		if NewCandidate.AliasRank ~= CurrentCandidate.AliasRank then
			return NewCandidate.AliasRank < CurrentCandidate.AliasRank
		end

		if NewCandidate.Priority ~= CurrentCandidate.Priority then
			return NewCandidate.Priority < CurrentCandidate.Priority
		end

		if NewCandidate.TypeScore ~= CurrentCandidate.TypeScore then
			return NewCandidate.TypeScore < CurrentCandidate.TypeScore
		end

		return NewCandidate.Name < CurrentCandidate.Name
	end

	local function scanHungerSnapshot()
		local DirectHungerValue = getDirectHungerValue()

		if DirectHungerValue ~= nil then
			return {
				DirectHungerValue = DirectHungerValue,
				StarvingValue = nil,
				PercentValue = nil,
				CurrentValue = DirectHungerValue,
				MaxValue = 100,
				TextSignal = {
					HasSignal = false,
					ShouldEat = false,
					Text = nil
				},
				HasSignal = true
			}
		end

		local Roots = buildScanRoots()
		local BestCandidates = {}
		local TextSignal = scanHungerTextSignal()

		local function recordCandidate(Kind, Name, Value, Priority)
			local NameLower = string.lower(Name)
			local AliasRank = getHungerAliasRank(Kind, NameLower)

			if AliasRank == nil then
				return
			end

			local Candidate = {
				Value = Value,
				Priority = Priority,
				AliasRank = AliasRank,
				TypeScore = getValueTypeScore(Value),
				Name = NameLower
			}

			if isBetterHungerCandidate(Candidate, BestCandidates[Kind]) then
				BestCandidates[Kind] = Candidate
			end
		end

		local function recordAllKinds(Name, Value, Priority)
			recordCandidate("starving", Name, Value, Priority)
			recordCandidate("percent", Name, Value, Priority)
			recordCandidate("current", Name, Value, Priority)
			recordCandidate("max", Name, Value, Priority)
		end

		for _, RootInfo in ipairs(Roots) do
			local Root = RootInfo.Root
			local Priority = RootInfo.Priority

			local function visit(Instance)
				if Instance:IsA("ValueBase") then
					recordAllKinds(Instance.Name, Instance.Value, Priority)
				end

				for Name, Value in pairs(Instance:GetAttributes()) do
					recordAllKinds(Name, Value, Priority)
				end
			end

			visit(Root)

			for _, Descendant in ipairs(Root:GetDescendants()) do
				visit(Descendant)
			end
		end

		return {
			DirectHungerValue = DirectHungerValue,
			StarvingValue = BestCandidates.starving and BestCandidates.starving.Value or nil,
			PercentValue = BestCandidates.percent and BestCandidates.percent.Value or nil,
			CurrentValue = BestCandidates.current and BestCandidates.current.Value or nil,
			MaxValue = BestCandidates.max and BestCandidates.max.Value or nil,
			TextSignal = TextSignal,
			HasSignal = DirectHungerValue ~= nil or next(BestCandidates) ~= nil or TextSignal.HasSignal
		}
	end

	local function getHungerSnapshot(ForceRefresh)
		local Now = os.clock()

		if not ForceRefresh
			and FoodFeature.HungerSnapshot
			and (Now - FoodFeature.LastHungerScanAt) < FoodFeature.HungerRefreshInterval then
			return FoodFeature.HungerSnapshot
		end

		FoodFeature.HungerSnapshot = scanHungerSnapshot()
		FoodFeature.LastHungerScanAt = Now

		return FoodFeature.HungerSnapshot
	end

	local function isHungryFlag(Value)
		if typeof(Value) == "boolean" then
			return Value
		end

		if typeof(Value) == "number" then
			return Value > 0
		end

		if typeof(Value) == "string" then
			local Lower = string.lower(trimString(Value) or Value)

			if Lower == "true" or Lower == "yes" or Lower == "hungry" or Lower == "starving" then
				return true
			end

			if Lower == "false" or Lower == "no" or Lower == "full" then
				return false
			end

			local NumberValue = parseLooseNumber(Lower)

			if NumberValue ~= nil then
				return NumberValue > 0
			end
		end

		return false
	end

	local function getHungerState(ForceRefresh)
		local DirectHungerValue = parseLooseNumber(getDirectHungerValue())

		if DirectHungerValue ~= nil then
			return {
				HasSignal = true,
				ShouldEat = DirectHungerValue <= FoodFeature.DirectHungerThreshold,
				CurrentValue = DirectHungerValue
			}
		end

		local Snapshot = getHungerSnapshot(ForceRefresh)
		DirectHungerValue = parseLooseNumber(Snapshot.DirectHungerValue)
		local StarvingValue = Snapshot.StarvingValue
		local TextSignal = Snapshot.TextSignal

		if DirectHungerValue ~= nil then
			return {
				HasSignal = true,
				ShouldEat = DirectHungerValue <= FoodFeature.DirectHungerThreshold,
				CurrentValue = DirectHungerValue
			}
		end

		if isHungryFlag(StarvingValue) then
			return {
				HasSignal = true,
				ShouldEat = true
			}
		end

		if TextSignal and TextSignal.ShouldEat then
			return {
				HasSignal = true,
				ShouldEat = true
			}
		end

		local PercentValue = Snapshot.PercentValue
		local CurrentValue = Snapshot.CurrentValue
		local MaxValue = Snapshot.MaxValue

		local PercentNumber = parsePercentValue(PercentValue)
		local CurrentNumber = parseLooseNumber(CurrentValue)
		local MaxNumber = parseLooseNumber(MaxValue)
		local RatioCurrent, RatioMax = parseRatio(CurrentValue)
		local HasSignal = Snapshot.HasSignal or (TextSignal and TextSignal.HasSignal) or false

		if (CurrentNumber == nil or MaxNumber == nil) and RatioCurrent and RatioMax then
			CurrentNumber = RatioCurrent
			MaxNumber = RatioMax
			HasSignal = true
		end

		if PercentNumber ~= nil then
			return {
				HasSignal = true,
				ShouldEat = PercentNumber <= (FoodFeature.HungerThreshold * 100)
			}
		end

		if CurrentNumber ~= nil and MaxNumber ~= nil and MaxNumber > 0 then
			return {
				HasSignal = true,
				ShouldEat = (CurrentNumber / MaxNumber) <= FoodFeature.HungerThreshold
			}
		end

		if CurrentNumber ~= nil then
			return {
				HasSignal = true,
				ShouldEat = CurrentNumber <= FoodFeature.FallbackThreshold
			}
		end

		return {
			HasSignal = HasSignal,
			ShouldEat = false
		}
	end

	local function shouldEat()
		return getHungerState().ShouldEat
	end

	function FoodFeature:SetEatThreshold(Value)
		local NumberValue = tonumber(Value)

		if NumberValue == nil then
			return false
		end

		NumberValue = math.clamp(math.floor(NumberValue + 0.5), 0, 80)

		self.DirectHungerThreshold = NumberValue
		self.FallbackThreshold = NumberValue
		self.HungerThreshold = NumberValue / 100
		self.HungerSnapshot = nil
		self.LastHungerScanAt = 0
		self.Elapsed = self.ScanInterval

		return true
	end

	function FoodFeature:GetEatThreshold()
		return self.DirectHungerThreshold
	end

	function FoodFeature:SetNoFoodAction(Value)
		if Value ~= "Do nothing" and Value ~= "Kick" then
			return false
		end

		self.NoFoodAction = Value

		return true
	end

	function FoodFeature:GetNoFoodAction()
		return self.NoFoodAction
	end

	local function getToolScore(Tool)
		if not Tool or not Tool:IsA("Tool") then
			return nil
		end

		local NameLower = string.lower(Tool.Name)
		local Ok, Tip = pcall(function() return Tool.ToolTip end)
		local ToolTipLower = string.lower((Ok and type(Tip) == "string" and Tip) or "")

		for _, Supplement in ipairs(SupplementBlacklist) do
			if string.find(NameLower, Supplement, 1, true) or string.find(ToolTipLower, Supplement, 1, true) then
				return nil
			end
		end

		for Index, Alias in ipairs(FoodToolAliases) do
			if NameLower == Alias or ToolTipLower == Alias then
				return Index
			end
		end

		for Index, Alias in ipairs(FoodToolAliases) do
			if string.find(NameLower, Alias, 1, true) or string.find(ToolTipLower, Alias, 1, true) then
				return Index + 50
			end
		end

		return nil
	end

	local getCharacterHumanoid

	local function isRemoteLike(Instance)
		return Instance
			and Instance.Parent
			and (
				Instance:IsA("RemoteEvent")
				or Instance:IsA("RemoteFunction")
				or Instance:IsA("UnreliableRemoteEvent")
			)
	end

	local function findRemote(RemoteName)
		local Cached = FoodFeature.RemoteCache[RemoteName]

		if isRemoteLike(Cached) then
			return Cached
		end

		local SearchRoots = {
			ReplicatedStorage,
			LocalPlayer,
			LocalPlayer:FindFirstChild("PlayerGui"),
			workspace
		}

		for _, Root in ipairs(SearchRoots) do
			if Root then
				local Found = Root:FindFirstChild(RemoteName, true)

				if isRemoteLike(Found) then
					FoodFeature.RemoteCache[RemoteName] = Found
					return Found
				end
			end
		end

		local Found = game:FindFirstChild(RemoteName, true)

		if isRemoteLike(Found) then
			FoodFeature.RemoteCache[RemoteName] = Found
			return Found
		end

		return nil
	end

	local function invokeRemote(Remote, ...)
		if not isRemoteLike(Remote) then
			return false, nil
		end

		local Arguments = table.pack(...)

		if Remote:IsA("RemoteFunction") then
			return pcall(function()
				return Remote:InvokeServer(table.unpack(Arguments, 1, Arguments.n))
			end)
		end

		return pcall(function()
			Remote:FireServer(table.unpack(Arguments, 1, Arguments.n))
		end)
	end

	local function getVirtualInputManager()
		local Success, VirtualInputManager = pcall(game.GetService, game, "VirtualInputManager")

		if Success and VirtualInputManager then
			return VirtualInputManager
		end

		return nil
	end

	local function sendKeyTap(KeyCode)
		if KeyCode == nil then
			return false
		end

		local VirtualInputManager = getVirtualInputManager()

		if not VirtualInputManager then
			return false
		end

		local Success = pcall(function()
			VirtualInputManager:SendKeyEvent(true, KeyCode, false, game)
			task.wait(0.03)
			VirtualInputManager:SendKeyEvent(false, KeyCode, false, game)
		end)

		return Success
	end

	local function sendMouseButton(ButtonIndex, IsDown)
		local VirtualInputManager = getVirtualInputManager()

		if not VirtualInputManager then
			return false
		end

		local Camera = workspace.CurrentCamera
		local ViewportSize = Camera and Camera.ViewportSize or Vector2.new(1280, 720)
		local CenterX = math.floor(ViewportSize.X * 0.5)
		local CenterY = math.floor(ViewportSize.Y * 0.5)

		local Success = pcall(function()
			VirtualInputManager:SendMouseButtonEvent(CenterX, CenterY, ButtonIndex, IsDown and true or false, game, 0)
		end)

		return Success
	end

	local function collectInventoryTools()
		local Character = LocalPlayer.Character
		local Backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
		local Tools = {}
		local Seen = {}

		local function collect(Container)
			if not Container then
				return
			end

			for _, Item in ipairs(Container:GetChildren()) do
				if Item:IsA("Tool") and not Seen[Item] then
					Seen[Item] = true
					table.insert(Tools, Item)
				end
			end
		end

		collect(Backpack)
		collect(Character)

		return Tools, Seen
	end

	local function refreshKnownHotbarOrder()
		local CurrentTools, Seen = collectInventoryTools()
		local OrderedTools = {}
		local Used = {}

		for _, Tool in ipairs(FoodFeature.KnownHotbarOrder) do
			if Tool and Tool.Parent and Seen[Tool] and not Used[Tool] then
				Used[Tool] = true
				table.insert(OrderedTools, Tool)
			end
		end

		for _, Tool in ipairs(CurrentTools) do
			if not Used[Tool] then
				Used[Tool] = true
				table.insert(OrderedTools, Tool)
			end
		end

		FoodFeature.KnownHotbarOrder = OrderedTools

		return OrderedTools
	end

	local function buildHotbarSnapshot()
		local Snapshot = {}

		for Index, Tool in ipairs(refreshKnownHotbarOrder()) do
			if Tool and Tool.Parent then
				Snapshot[Index] = Tool.Name
			end
		end

		return Snapshot
	end

	local function findToolSlotIndex(Tool)
		if not Tool then
			return nil
		end

		for _, AttributeName in ipairs(ToolSlotAttributeAliases) do
			local SlotIndex = toSlotIndex(Tool:GetAttribute(AttributeName))

			if SlotIndex then
				return SlotIndex
			end

			local ChildValue = Tool:FindFirstChild(AttributeName)

			if ChildValue and ChildValue:IsA("ValueBase") then
				SlotIndex = toSlotIndex(ChildValue.Value)

				if SlotIndex then
					return SlotIndex
				end
			end
		end

		for Index, Entry in ipairs(refreshKnownHotbarOrder()) do
			if Entry == Tool then
				return Index
			end
		end

		for Index, Entry in ipairs(FoodFeature.KnownHotbarOrder) do
			if Entry and Entry.Name == Tool.Name then
				return Index
			end
		end

		return nil
	end

	local function getToolSlotKeyName(Tool)
		local SlotIndex = findToolSlotIndex(Tool)

		if not SlotIndex then
			return nil
		end

		return SlotKeyNames[SlotIndex]
	end

	local function isAirborne()
		local _, Humanoid = getCharacterHumanoid()

		if not Humanoid then
			return false
		end

		local State = Humanoid:GetState()

		return State == Enum.HumanoidStateType.Freefall
			or State == Enum.HumanoidStateType.FallingDown
			or State == Enum.HumanoidStateType.Jumping
	end

	local function sendServerInput(KeyName, IsDown)
		if type(KeyName) ~= "string" then
			return false
		end

		if KeyName == "LMB" then
			return sendMouseButton(0, IsDown)
		end

		if KeyName == "RMB" then
			return sendMouseButton(1, IsDown)
		end

		if IsDown then
			return false
		end

		return sendKeyTap(SlotKeyCodes[KeyName])
	end

	local function selectToolFromHotbar(Tool)
		if not Tool then
			return false
		end

		local SlotKeyName = getToolSlotKeyName(Tool)

		sendServerInput("RMB", false)

		if SlotKeyName then
			task.wait(0.05)

			return sendServerInput(SlotKeyName, false)
		end

		return false
	end

	local function syncHotbarState(Tool)
		local SlotKeyName = getToolSlotKeyName(Tool)

		if SlotKeyName then
			return sendServerInput(SlotKeyName, false)
		end

		return false
	end

	local function triggerMouseClick()
		if type(mouse1click) == "function" then
			pcall(mouse1click)
			return true
		end

		if type(mouse1press) == "function" and type(mouse1release) == "function" then
			pcall(mouse1press)
			task.wait(0.05)
			pcall(mouse1release)
			return true
		end

		local Success, VirtualInputManager = pcall(game.GetService, game, "VirtualInputManager")

		if Success and VirtualInputManager then
			local Camera = workspace.CurrentCamera
			local ViewportSize = Camera and Camera.ViewportSize or Vector2.new(1280, 720)
			local CenterX = math.floor(ViewportSize.X * 0.5)
			local CenterY = math.floor(ViewportSize.Y * 0.5)

			pcall(function()
				VirtualInputManager:SendMouseButtonEvent(CenterX, CenterY, 0, true, game, 0)
				task.wait(0.05)
				VirtualInputManager:SendMouseButtonEvent(CenterX, CenterY, 0, false, game, 0)
			end)

			return true
		end

		return false
	end

	local function triggerToolUse(Tool)
		local Triggered = false

		pcall(function()
			Tool:Activate()
			Triggered = true
		end)

		if type(firesignal) == "function" then
			pcall(function()
				firesignal(Tool.Activated)
				Triggered = true
			end)
		end

		if Tool.ManualActivationOnly == false or Tool.ManualActivationOnly == nil then
			if triggerMouseClick() then
				Triggered = true
			end
		else
			triggerMouseClick()
		end

		return Triggered
	end

	local function isFoodTool(Tool)
		return getToolScore(Tool) ~= nil
	end

	function getCharacterHumanoid()
		local Character = LocalPlayer.Character

		if not Character then
			return nil, nil
		end

		return Character, Character:FindFirstChildOfClass("Humanoid")
	end

	local function getEquippedTool(Character)
		if not Character then
			return nil
		end

		for _, Item in ipairs(Character:GetChildren()) do
			if Item:IsA("Tool") then
				return Item
			end
		end

		return nil
	end

	local function getToolIdentity(Tool)
		if not Tool or not Tool:IsA("Tool") then
			return nil
		end

		local Cached = ToolIdentityCache[Tool]

		if Cached then
			return Cached
		end

		NextToolIdentity = NextToolIdentity + 1

		local Prefix = "Tool:" .. Tool.Name
		local Success, Value = pcall(function()
			return Tool:GetFullName()
		end)

		if Success and Value then
			Prefix = Value
		end

		local Identity = string.format("%s#%d", Prefix, NextToolIdentity)
		ToolIdentityCache[Tool] = Identity

		return Identity
	end

	local function isSameTool(Left, Right)
		if Left == Right then
			return true
		end

		if not Left or not Right then
			return false
		end

		if not Left:IsA("Tool") or not Right:IsA("Tool") then
			return false
		end

		local LeftIdentity = getToolIdentity(Left)
		local RightIdentity = getToolIdentity(Right)

		if LeftIdentity and RightIdentity and LeftIdentity == RightIdentity then
			return true
		end

		local LeftSlot = findToolSlotIndex(Left)
		local RightSlot = findToolSlotIndex(Right)

		return LeftSlot ~= nil
			and RightSlot ~= nil
			and LeftSlot == RightSlot
			and Left.Name == Right.Name
	end

	local function isToolEquipped(Tool, Character)
		if not Tool or not Character then
			return false
		end

		if Tool.Parent == Character then
			return true
		end

		return isSameTool(Tool, getEquippedTool(Character))
	end

	local function waitForToolEquipped(Tool, Character, Timeout)
		local StartedAt = os.clock()
		local MaximumWait = Timeout or FoodFeature.EquipDelay

		repeat
			if isToolEquipped(Tool, Character) then
				return true
			end

			task.wait(0.05)
		until (os.clock() - StartedAt) >= MaximumWait

		return isToolEquipped(Tool, Character)
	end

	local function equipFoodTool(Tool, Character, Humanoid)
		if not Tool or not Character or not Humanoid then
			return false
		end

		if isToolEquipped(Tool, Character) then
			return true
		end

		for _ = 1, FoodFeature.MaxEquipAttempts do
			pcall(function()
				Humanoid:EquipTool(Tool)
			end)

			if Tool.Parent ~= Character then
				pcall(function()
					Tool.Parent = Character
				end)
			end

			if waitForToolEquipped(Tool, Character, FoodFeature.EquipDelay) then
				return true
			end

			task.wait(FoodFeature.EquipRetryDelay)
		end

		return isToolEquipped(Tool, Character)
	end

	local function findFoodTool()
		local Character = LocalPlayer.Character
		local Backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
		local BestTool = nil
		local BestScore = math.huge

		refreshKnownHotbarOrder()

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

	local function getEquippedFoodTool(Character)
		if not Character then
			return nil
		end

		for _, Item in ipairs(Character:GetChildren()) do
			if Item:IsA("Tool") and isFoodTool(Item) then
				return Item
			end
		end

		return nil
	end

	local function unequipFoodTools(Tool)
		local Character, Humanoid = getCharacterHumanoid()
		local Backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
		local ManagedTool = Tool or FoodFeature.AutoManagedTool

		if not Character or not Humanoid then
			return
		end

		if not ManagedTool then
			return
		end

		local EquippedFoodTool = getEquippedFoodTool(Character)

		if not EquippedFoodTool then
			syncHotbarState(ManagedTool)

			if FoodFeature.AutoManagedTool and isSameTool(FoodFeature.AutoManagedTool, ManagedTool) then
				FoodFeature.AutoManagedTool = nil
			end

			return
		end

		if not isSameTool(EquippedFoodTool, ManagedTool) then
			return
		end

		Humanoid:UnequipTools()

		if Backpack then
			for _, Item in ipairs(Character:GetChildren()) do
				if Item:IsA("Tool") and isSameTool(Item, ManagedTool) then
					Item.Parent = Backpack
				end
			end
		end

		syncHotbarState(ManagedTool)

		if FoodFeature.AutoManagedTool and isSameTool(FoodFeature.AutoManagedTool, ManagedTool) then
			FoodFeature.AutoManagedTool = nil
		end
	end

	local function handleMissingFood()
		local Now = os.clock()

		if Now - FoodFeature.LastMissingFoodAt < FoodFeature.MissingFoodRetryDelay then
			return
		end

		FoodFeature.LastMissingFoodAt = Now

		if FoodFeature.NoFoodAction == "Kick" then
			FoodFeature.Enabled = false
			FoodFeature.StopRequested = true

			task.defer(function()
				LocalPlayer:Kick("Auto eat: no food found in your backpack.")
			end)

			return
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
		FoodFeature.StopRequested = false

		task.spawn(function()
			local PreviouslyEquippedTool = getEquippedTool(Character)
			local WasAlreadyHoldingFood = isToolEquipped(Tool, Character)
			local ShouldManageTool = not WasAlreadyHoldingFood

			if isFoodTool(PreviouslyEquippedTool) then
				PreviouslyEquippedTool = nil
			end

			if FoodFeature.AutoManagedTool and isSameTool(FoodFeature.AutoManagedTool, Tool) then
				ShouldManageTool = true
			end

			if ShouldManageTool then
				FoodFeature.AutoManagedTool = Tool
			end

			local EquippedFood = equipFoodTool(Tool, Character, Humanoid)

			if EquippedFood then
				pcall(function()
					if Tool.Enabled ~= nil then
						Tool.Enabled = true
					end
				end)

				task.wait(FoodFeature.HoldBeforeUseDelay)
			end

			for _ = 1, FoodFeature.MaxActivationAttempts do
				if FoodFeature.StopRequested then
					break
				end

				if not Tool.Parent then
					break
				end

				local Equipped = equipFoodTool(Tool, Character, Humanoid)

				if not Equipped then
					task.wait(FoodFeature.EquipDelay)
					Equipped = isToolEquipped(Tool, Character)
				end

				if Equipped then
					task.wait(FoodFeature.HoldBeforeUseDelay)
					triggerToolUse(Tool)
				end

				task.wait(FoodFeature.ActivationDelay)

				local HungerState = getHungerState(true)

				if HungerState.HasSignal and not HungerState.ShouldEat then
					break
				end
			end

			unequipFoodTools(ShouldManageTool and Tool or nil)

			if FoodFeature.AutoManagedTool and isSameTool(FoodFeature.AutoManagedTool, Tool) then
				FoodFeature.AutoManagedTool = nil
			end

			if PreviouslyEquippedTool and PreviouslyEquippedTool.Parent then
				pcall(function()
					Humanoid:EquipTool(PreviouslyEquippedTool)
				end)
			end

			FoodFeature.IsEating = false
			FoodFeature.StopRequested = false
			FoodFeature.LastEatAt = os.clock()
		end)
	end

	function FoodFeature:ShouldEat()
		return shouldEat()
	end

	function FoodFeature:SetEnabled(Value)
		self.Enabled = Value and true or false
		self.HungerSnapshot = nil
		self.LastHungerScanAt = 0
		self.LastMissingFoodAt = 0

		if self.Enabled then
			self.StopRequested = false
			self.Elapsed = self.ScanInterval
		else
			self.StopRequested = true
		end

		if not self.Enabled then
			if self.AutoManagedTool and not self.IsEating then
				unequipFoodTools(self.AutoManagedTool)
			end
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

				local HungerState = getHungerState()

				if not HungerState.HasSignal then
					return
				end

				if not HungerState.ShouldEat then
					return
				end

				if self.LastMissingFoodAt > 0 and (os.clock() - self.LastMissingFoodAt) < self.MissingFoodRetryDelay then
					return
				end

				local Tool = findFoodTool()

				if not Tool then
					handleMissingFood()
					return
				end

				self.LastMissingFoodAt = 0

				consumeFood(Tool)
			end)
		end

		return true
	end

	function FoodFeature:Destroy()
		self.Enabled = false
		self.IsEating = false
		self.StopRequested = true

		if self.AutoManagedTool then
			unequipFoodTools(self.AutoManagedTool)
		end

		self.AutoManagedTool = nil
		self.HungerSnapshot = nil
		self.LastHungerScanAt = 0
		self.HungerValueObject = nil
		self.KnownHotbarOrder = {}
		self.RemoteCache = {}

		if self.Connection then
			self.Connection:Disconnect()
			self.Connection = nil
		end
	end

	return FoodFeature
end
