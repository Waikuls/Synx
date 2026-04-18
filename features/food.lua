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
		EatCooldown = 3,
		EquipDelay = 0.35,
		EquipRetryDelay = 0.12,
		HoldBeforeUseDelay = 0.18,
		ActivationDelay = 0.75,
		InputPressDelay = 0.08,
		MaxEquipAttempts = 3,
		MaxActivationAttempts = 3,
		HungerThreshold = 0.35,
		FallbackThreshold = 25,
		AutoManagedTool = nil,
		HungerSnapshot = nil,
		LastHungerScanAt = 0,
		KnownHotbarOrder = {},
		RemoteCache = {}
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
		"burger",
		"fries",
		"ramen",
		"onigiri",
		"pizza",
		"kebab",
		"food",
		"apple",
		"bread",
		"sandwich",
		"meat",
		"steak",
		"fish",
		"rice",
		"soup",
		"meal",
		"snack"
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
		local Roots = buildScanRoots()
		local BestCandidates = {}

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
			StarvingValue = BestCandidates.starving and BestCandidates.starving.Value or nil,
			PercentValue = BestCandidates.percent and BestCandidates.percent.Value or nil,
			CurrentValue = BestCandidates.current and BestCandidates.current.Value or nil,
			MaxValue = BestCandidates.max and BestCandidates.max.Value or nil,
			HasSignal = next(BestCandidates) ~= nil
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
		local Snapshot = getHungerSnapshot(ForceRefresh)
		local StarvingValue = Snapshot.StarvingValue

		if isHungryFlag(StarvingValue) then
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
		local HasSignal = Snapshot.HasSignal

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
			if NameLower == Alias or ToolTipLower == Alias then
				return Index
			end
		end

		for Index, Alias in ipairs(FoodToolAliases) do
			if string.find(NameLower, Alias, 1, true) or string.find(ToolTipLower, Alias, 1, true) then
				return Index + 50
			end
		end

		if string.find(NameLower, "eat", 1, true) or string.find(ToolTipLower, "eat", 1, true) then
			return 200
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
		local InputRemote = findRemote("Input")

		if not InputRemote or type(KeyName) ~= "string" then
			return false
		end

		return select(1, invokeRemote(InputRemote, {
			KeyInfo = {
				Direction = "None",
				Name = KeyName,
				Airborne = isAirborne()
			},
			IsDown = IsDown and true or false
		}))
	end

	local function selectToolFromHotbar(Tool)
		if not Tool then
			return false
		end

		local UsedRemote = false
		local CustomHotbarRemote = findRemote("CustomHotbar")
		local EquipToolRemote = findRemote("EquipTool")
		local SlotKeyName = getToolSlotKeyName(Tool)

		sendServerInput("RMB", false)

		if CustomHotbarRemote then
			UsedRemote = select(1, invokeRemote(CustomHotbarRemote, Tool)) or UsedRemote
		elseif EquipToolRemote then
			UsedRemote = select(1, invokeRemote(EquipToolRemote, Tool)) or UsedRemote
		end

		if SlotKeyName then
			task.wait(0.05)

			if sendServerInput(SlotKeyName, false) then
				UsedRemote = true
			end
		end

		return UsedRemote
	end

	local function syncHotbarState(Tool)
		local UsedRemote = false
		local CustomHotbarRemote = findRemote("CustomHotbar")
		local RequestRemote = findRemote("Request")
		local Snapshot = buildHotbarSnapshot()
		local SlotKeyName = getToolSlotKeyName(Tool)

		if CustomHotbarRemote then
			UsedRemote = select(1, invokeRemote(CustomHotbarRemote)) or UsedRemote
		end

		if RequestRemote and next(Snapshot) ~= nil then
			UsedRemote = select(1, invokeRemote(RequestRemote, "UpdateHotbars", Snapshot)) or UsedRemote
		end

		if SlotKeyName then
			sendServerInput(SlotKeyName, false)
		end

		return UsedRemote
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

		local LeftSuccess, LeftValue = pcall(function()
			return Left:GetDebugId(0)
		end)
		local RightSuccess, RightValue = pcall(function()
			return Right:GetDebugId(0)
		end)

		if LeftSuccess and RightSuccess then
			return LeftValue == RightValue
		end

		return false
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

			selectToolFromHotbar(Tool)

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
		FoodFeature.StopRequested = false
		FoodFeature.LastEatAt = os.clock()

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

				local UsedRemote = false
				local EquippedNow = equipFoodTool(Tool, Character, Humanoid)

				if EquippedNow then
					task.wait(FoodFeature.HoldBeforeUseDelay)
				end

				if selectToolFromHotbar(Tool) then
					UsedRemote = true
				end

				if sendServerInput("LMB", true) then
					UsedRemote = true
				end

				task.wait(FoodFeature.InputPressDelay)

				if sendServerInput("LMB", false) then
					UsedRemote = true
				end

				if EquippedNow or isToolEquipped(Tool, Character) then
					triggerToolUse(Tool)
				elseif not UsedRemote then
					break
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
				selectToolFromHotbar(PreviouslyEquippedTool)

				if PreviouslyEquippedTool.Parent ~= Character then
					pcall(function()
						Humanoid:EquipTool(PreviouslyEquippedTool)
					end)
				end
			end

			FoodFeature.IsEating = false
			FoodFeature.StopRequested = false
		end)
	end

	function FoodFeature:SetEnabled(Value)
		self.Enabled = Value and true or false
		self.HungerSnapshot = nil
		self.LastHungerScanAt = 0

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
		self.StopRequested = true

		if self.AutoManagedTool then
			unequipFoodTools(self.AutoManagedTool)
		end

		self.AutoManagedTool = nil
		self.HungerSnapshot = nil
		self.LastHungerScanAt = 0
		self.KnownHotbarOrder = {}
		self.RemoteCache = {}

		if self.Connection then
			self.Connection:Disconnect()
			self.Connection = nil
		end
	end

	return FoodFeature
end
