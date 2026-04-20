return function(Config)
	local Players = game:GetService("Players")
	local RunService = game:GetService("RunService")
	local CoreGui = game:GetService("CoreGui")
	local LocalPlayer = Players.LocalPlayer
	local Notification = Config and Config.Notification
	local Webhook = Config and Config.Webhook
	local FoodFeature = Config and Config.FoodFeature
	local WheyFeature = Config and Config.WheyFeature

	local AvailableTypes = {
		"Attack speed",
		"Bar",
		"Bench",
		"Bike",
		"Squat machine",
		"Strength",
		"Treadmill"
	}

	local MachineAliases = {}
	MachineAliases["Bag"] = {"bag", "punching bag"}
	MachineAliases["Strength"] = {"strength", "punching bag", "boxing bag"}
	MachineAliases["Attack speed"] = {"attack speed", "speed bag", "speed ball"}
	MachineAliases["Bar"] = {"bar", "barbell", "pullup", "pull up", "pull-up"}
	MachineAliases["Bench"] = {"bench", "bench press"}
	MachineAliases["Bike"] = {"bike", "cycling", "cycle"}
	MachineAliases["Squat machine"] = {"squat machine", "squat", "leg press"}
	MachineAliases["Treadmill"] = {"treadmill", "running machine"}

	local RemoteMachineTypes = {Bike = true, Treadmill = true, Bar = true, Bench = true, ["Squat machine"] = true}
	local MachineRemotePaths = {
		Bike = {"TrainingSpots", "Bike", "Radio", "Remote"},
		Treadmill = {"TrainingSpots", "Treadmill", "Radio", "Remote"},
		Bar = {"TrainingSpots", "PullUp", "Radio", "Remote"},
		Bench = {"TrainingSpots", "Bench", "Radio", "Remote"},
		["Squat machine"] = {"TrainingSpots", "Squat", "Radio", "Remote"},
	}

	local function isRemoteMachine(Type)
		return RemoteMachineTypes[Type] == true
	end

	local BikeRemotePath = {"TrainingSpots", "Bike", "Radio", "Remote"}
	local BikeKeys = {"W", "A", "S", "D"}
	local BikeKeyCodes = {
		W = Enum.KeyCode.W,
		A = Enum.KeyCode.A,
		S = Enum.KeyCode.S,
		D = Enum.KeyCode.D
	}
	local BikeVirtualKeys = {
		W = 0x57,
		A = 0x41,
		S = 0x53,
		D = 0x44
	}

	local AutoTrainFeature = {}
	AutoTrainFeature.Enabled = false
	AutoTrainFeature.SelectedType = "Bike"
	AutoTrainFeature.Connection = nil
	AutoTrainFeature.Elapsed = 0
	AutoTrainFeature.LoopInterval = 0.15
	AutoTrainFeature.PromptCooldown = 0.75
	AutoTrainFeature.StartCooldown = 0.35
	AutoTrainFeature.KeyCooldown = 0.08
	AutoTrainFeature.RepeatKeyCooldown = 0.3
	AutoTrainFeature.BlindBikeKeyCooldown = 0.2
	AutoTrainFeature.BikeUiRefreshCooldown = 0.25
	AutoTrainFeature.BikeAssumeActiveDuration = 12
	AutoTrainFeature.DebugNotifyCooldown = 1
	AutoTrainFeature.DesiredStandDistance = 4
	AutoTrainFeature.VerticalOffset = 2.5
	AutoTrainFeature.MaxRemoteStartDistance = 18
	AutoTrainFeature.LastPromptAt = 0
	AutoTrainFeature.LastStartAt = 0
	AutoTrainFeature.LastKeyAt = 0
	AutoTrainFeature.LastBlindBikeKeyAt = 0
	AutoTrainFeature.LastKeySignature = nil
	AutoTrainFeature.LastKeySignatureAt = 0
	AutoTrainFeature.CachedPrompt = nil
	AutoTrainFeature.CachedPromptType = nil
	AutoTrainFeature.LastPromptRefreshAt = 0
	AutoTrainFeature.PromptRefreshInterval = 2
	AutoTrainFeature.LastBikeUiRefreshAt = 0
	AutoTrainFeature.CachedBikeActionMenuVisible = false
	AutoTrainFeature.CachedBikeStartButton = nil
	AutoTrainFeature.CachedBikeKey = nil
	AutoTrainFeature.CachedBikeKeySignature = nil
	AutoTrainFeature.BlindBikeKeyIndex = 0
	AutoTrainFeature.BikeActiveUntil = 0
	AutoTrainFeature.BikeRideStartedAt = 0
	AutoTrainFeature.MaxBikeRideDuration = 65
	AutoTrainFeature.LastProximityTriggerAt = 0
	AutoTrainFeature.LastUiKeyAt = 0
	AutoTrainFeature.StaminaThreshold = 3
	AutoTrainFeature.ContinueLevel = "mid"
	AutoTrainFeature.StaminaPaused = false
	AutoTrainFeature.MaxFatigueAction = "Do nothing"
	AutoTrainFeature.FatigueNotified = false
	AutoTrainFeature.BedRecoveryNotified = false
	AutoTrainFeature.EatingBreak = false
	AutoTrainFeature.EatingBreakDismounted = false
	AutoTrainFeature.LastRideEndAt = 0
	AutoTrainFeature.StrengthGlovesActive = false
	AutoTrainFeature.StrengthPunchIndex = 0
	AutoTrainFeature.LastStrengthPunchAt = 0
	AutoTrainFeature.LastStrengthEquipAt = 0
	AutoTrainFeature.LastStrengthHitAt = 0
	AutoTrainFeature.StrengthPunchCooldown = 0.35
	AutoTrainFeature.StrengthEquipCooldown = 2.0
	AutoTrainFeature.StrengthSessionTimeout = 8
	AutoTrainFeature.LastDebugNotifyAt = 0
	AutoTrainFeature.LastDebugMessage = ""

	local function trimString(Value)
		if typeof(Value) ~= "string" then
			return nil
		end

		return string.match(Value, "^%s*(.-)%s*$")
	end

	local function normalizeText(Value)
		local Trimmed = trimString(Value)

		if not Trimmed then
			return ""
		end

		if Trimmed == "" then
			return ""
		end

		return string.lower(string.gsub(Trimmed, "%s+", " "))
	end

	local function copyArray(Source)
		local Result = {}

		if type(Source) ~= "table" then
			return Result
		end

		for Index = 1, #Source do
			Result[Index] = Source[Index]
		end

		return Result
	end

	local function squashText(Value)
		local Normalized = normalizeText(Value)

		if Normalized == "" then
			return ""
		end

		return string.upper(string.gsub(Normalized, "[^%w]", ""))
	end

	local function debugBike(Message, ForceNotify)
		local Now = os.clock()

		warn("[KELV][AutoTrain][Bike] " .. tostring(Message))

		if not Notification then
			return
		end

		if not ForceNotify then
			if Message == AutoTrainFeature.LastDebugMessage then
				if (Now - AutoTrainFeature.LastDebugNotifyAt) < AutoTrainFeature.DebugNotifyCooldown then
					return
				end
			end
		end

		AutoTrainFeature.LastDebugNotifyAt = Now
		AutoTrainFeature.LastDebugMessage = tostring(Message)

		pcall(function()
			Notification:Notify({
				Title = "Auto Train Debug",
				Content = tostring(Message),
				Icon = "clipboard"
			})
		end)
	end

	local function getAliases(SelectedType)
		local Aliases = MachineAliases[SelectedType]

		if type(Aliases) == "table" then
			return Aliases
		end

		return {normalizeText(SelectedType)}
	end

	local function containsAlias(Text, Aliases)
		local Normalized = normalizeText(Text)

		if Normalized == "" then
			return false
		end

		for Index = 1, #Aliases do
			if string.find(Normalized, Aliases[Index], 1, true) then
				return true
			end
		end

		return false
	end

	local function getCharacter()
		return LocalPlayer.Character
	end

	local function getHumanoid()
		local Character = getCharacter()

		if not Character then
			return nil
		end

		return Character:FindFirstChildOfClass("Humanoid")
	end

	local function getRootPart()
		local Character = getCharacter()

		if not Character then
			return nil
		end

		local RootPart = Character:FindFirstChild("HumanoidRootPart")

		if RootPart then
			return RootPart
		end

		RootPart = Character:FindFirstChild("UpperTorso")

		if RootPart then
			return RootPart
		end

		return Character:FindFirstChild("Torso")
	end

	local function getPlayerGui()
		return LocalPlayer:FindFirstChildOfClass("PlayerGui")
	end

	local function getGuiContainers(IncludeCoreGui)
		local Containers = {}
		local PlayerGui = getPlayerGui()

		if PlayerGui then
			table.insert(Containers, PlayerGui)
		end

		if IncludeCoreGui and CoreGui then
			table.insert(Containers, CoreGui)
		end

		return Containers
	end

	local function isVisibleGuiObject(Instance)
		local Current = Instance

		if not Current then
			return false
		end

		if not Current:IsA("GuiObject") then
			return false
		end

		while Current and Current ~= game do
			if Current:IsA("GuiObject") then
				local Success, Visible = pcall(function()
					return Current.Visible
				end)

				if Success and not Visible then
					return false
				end
			end

			Current = Current.Parent
		end

		return true
	end

	local function getInstanceText(Instance)
		if not Instance then
			return nil
		end

		if Instance:IsA("TextLabel") or Instance:IsA("TextButton") or Instance:IsA("TextBox") then
			local Success, Text = pcall(function()
				return Instance.Text
			end)

			if Success then
				return trimString(Text)
			end
		end

		return nil
	end

	local function getGuiCenter(Instance)
		if not Instance then
			return nil, nil
		end

		if not Instance:IsA("GuiObject") then
			return nil, nil
		end

		local Success, Position, Size = pcall(function()
			return Instance.AbsolutePosition, Instance.AbsoluteSize
		end)

		if not Success then
			return nil, nil
		end

		if not Position or not Size then
			return nil, nil
		end

		return Position + (Size * 0.5), Size
	end

	local function getGuiButtonFromInstance(Instance)
		local Current = Instance

		while Current and Current ~= game do
			if Current:IsA("GuiButton") then
				return Current
			end

			Current = Current.Parent
		end

		return nil
	end

	local function getScreenCenter()
		local Camera = workspace.CurrentCamera
		local ViewportSize = Vector2.new(1280, 720)

		if Camera then
			ViewportSize = Camera.ViewportSize
		end

		return ViewportSize * 0.5, ViewportSize
	end

	local function getVirtualInputManager()
		local Success, VirtualInputManager = pcall(game.GetService, game, "VirtualInputManager")

		if Success and VirtualInputManager then
			return VirtualInputManager
		end

		return nil
	end

	local function clickGuiButton(Button)
		local Triggered = false

		if not Button then
			return false
		end

		if not Button:IsA("GuiButton") then
			return false
		end

		if not isVisibleGuiObject(Button) then
			return false
		end

		if type(firesignal) == "function" then
			pcall(function()
				firesignal(Button.MouseButton1Down)
				Triggered = true
			end)

			pcall(function()
				firesignal(Button.MouseButton1Up)
				Triggered = true
			end)

			pcall(function()
				firesignal(Button.MouseButton1Click)
				Triggered = true
			end)

			pcall(function()
				firesignal(Button.Activated)
				Triggered = true
			end)
		end

		pcall(function()
			Button:Activate()
			Triggered = true
		end)

		if not Triggered then
			local Center, Size = getGuiCenter(Button)
			local VirtualInputManager = getVirtualInputManager()

			if VirtualInputManager and Center and Size then
				pcall(function()
					VirtualInputManager:SendMouseButtonEvent(math.floor(Center.X), math.floor(Center.Y), 0, true, game, 0)
					task.wait(0.03)
					VirtualInputManager:SendMouseButtonEvent(math.floor(Center.X), math.floor(Center.Y), 0, false, game, 0)
					Triggered = true
				end)
			end
		end

		return Triggered
	end

	local function sendBikePhysicalKey(Key)
		local KeyCode = BikeKeyCodes[Key]
		local VirtualKey = BikeVirtualKeys[Key]
		local VirtualInputManager = nil
		local Triggered = false

		if not KeyCode then
			return false
		end

		-- VirtualInputManager injects into Roblox's input pipeline directly,
		-- so it works even when the window is minimized or unfocused.
		VirtualInputManager = getVirtualInputManager()

		if VirtualInputManager then
			pcall(function()
				VirtualInputManager:SendKeyEvent(true, KeyCode, false, game)
				task.wait(0.03)
				VirtualInputManager:SendKeyEvent(false, KeyCode, false, game)
				Triggered = true
			end)
		end

		if type(keypress) == "function" and type(keyrelease) == "function" and VirtualKey then
			pcall(function()
				keypress(VirtualKey)
				task.wait(0.03)
				keyrelease(VirtualKey)
				Triggered = true
			end)
		elseif type(keytap) == "function" then
			pcall(function()
				keytap(string.lower(Key))
				Triggered = true
			end)

			if not Triggered then
				pcall(function()
					keytap(Key)
					Triggered = true
				end)
			end
		end

		return Triggered
	end

	local function findEntityMainScript()
		local Entities = workspace:FindFirstChild("Entities")

		if not Entities then
			return nil
		end

		local Entity = Entities:FindFirstChild(LocalPlayer.Name)

		if not Entity then
			return nil
		end

		local MainScript = Entity:FindFirstChild("MainScript")

		if MainScript then
			return MainScript
		end

		local Descendants = Entity:GetDescendants()

		for Index = 1, #Descendants do
			local Descendant = Descendants[Index]

			if Descendant.Name == "MainScript" then
				return Descendant
			end
		end

		return nil
	end

	local function findStatsContainer()
		local MainScript = findEntityMainScript()

		if not MainScript then
			return nil
		end

		local Stats = MainScript:FindFirstChild("Stats")

		if Stats then
			return Stats
		end

		return MainScript:FindFirstChild("Stats", true)
	end

	local function readStatsValue(Stats, Name)
		if not Stats then
			return nil
		end

		local Child = Stats:FindFirstChild(Name)

		if Child and Child:IsA("ValueBase") then
			return Child.Value
		end

		local Attribute = Stats:GetAttribute(Name)

		if Attribute ~= nil then
			return Attribute
		end

		local Descendant = Stats:FindFirstChild(Name, true)

		if Descendant and Descendant:IsA("ValueBase") then
			return Descendant.Value
		end

		return nil
	end

	local StaminaCache = {Value = 100, At = 0}

	local function getStaminaPercent()
		local Now = os.clock()

		if (Now - StaminaCache.At) < 0.5 then
			return StaminaCache.Value
		end

		local Stats = findStatsContainer()
		local Percent = 100

		if Stats then
			local Stamina = readStatsValue(Stats, "Stamina") or readStatsValue(Stats, "StaminaInStat")
			local MaxStamina = readStatsValue(Stats, "MaxStamina")

			if type(Stamina) == "number" and type(MaxStamina) == "number" and MaxStamina > 0 then
				Percent = (Stamina / MaxStamina) * 100
			end
		end

		StaminaCache.Value = Percent
		StaminaCache.At = Now
		return Percent
	end

	local BodyFatigueCache = {Value = 0, At = 0}

	local function getBodyFatigue()
		local Now = os.clock()

		if (Now - BodyFatigueCache.At) < 0.5 then
			return BodyFatigueCache.Value
		end

		local Stats = findStatsContainer()
		local Value = 0

		if Stats then
			local Raw = readStatsValue(Stats, "BodyFatigue") or readStatsValue(Stats, "BodyFatique")

			if type(Raw) == "number" then
				Value = Raw
			end
		end

		BodyFatigueCache.Value = Value
		BodyFatigueCache.At = Now
		return Value
	end

	local function valueToBool(Value)
		local ValueType = typeof(Value)

		if ValueType == "boolean" then
			return Value
		end

		if ValueType == "number" then
			return Value ~= 0
		end

		if ValueType == "string" then
			local Lower = normalizeText(Value)

			if Lower == "true" then
				return true
			end

			if Lower == "yes" then
				return true
			end

			if Lower == "active" then
				return true
			end
		end

		return false
	end

	local function getTrainingState(SelectedType)
		local Stats = findStatsContainer()
		local IsTraining = false
		local TrainingMachine = tostring(readStatsValue(Stats, "TrainingMachine") or "")
		local Aliases = getAliases(SelectedType)

		if valueToBool(readStatsValue(Stats, "IsTrainingWithMachine")) then
			IsTraining = true
		end

		if valueToBool(readStatsValue(Stats, "Training")) then
			IsTraining = true
		end

		if not IsTraining and normalizeText(TrainingMachine) ~= "" then
			IsTraining = true
		end

		return {
			IsTraining = IsTraining,
			IsSelectedMachine = containsAlias(TrainingMachine, Aliases),
			TrainingMachine = TrainingMachine
		}
	end

	local function getPromptPart(Prompt)
		local Current

		if not Prompt then
			return nil
		end

		Current = Prompt.Parent

		while Current do
			if Current:IsA("BasePart") then
				return Current
			end

			if Current:IsA("Model") then
				local Part = Current.PrimaryPart

				if Part then
					return Part
				end

				return Current:FindFirstChildWhichIsA("BasePart", true)
			end

			Current = Current.Parent
		end

		return nil
	end

	local function getPromptPosition(Prompt)
		local Part = getPromptPart(Prompt)

		if not Part then
			return nil, nil
		end

		return Part.Position, Part
	end

	local function getPromptDescription(Prompt)
		local Parts = {}
		local Parent

		if not Prompt then
			return ""
		end

		table.insert(Parts, Prompt.Name or "")
		table.insert(Parts, Prompt.ActionText or "")
		table.insert(Parts, Prompt.ObjectText or "")

		Parent = Prompt.Parent

		if Parent then
			table.insert(Parts, Parent.Name or "")

			if Parent.Parent then
				table.insert(Parts, Parent.Parent.Name or "")
			end
		end

		return normalizeText(table.concat(Parts, " "))
	end

	local function promptMatchesSelectedType(Prompt, SelectedType)
		return containsAlias(getPromptDescription(Prompt), getAliases(SelectedType))
	end

	local function isPromptValid(Prompt)
		if not Prompt then
			return false
		end

		if not Prompt.Parent then
			return false
		end

		return Prompt:IsA("ProximityPrompt")
	end

	local function scanForBestPrompt(SelectedType)
		local RootPart = getRootPart()
		local Descendants = workspace:GetDescendants()
		local BestPrompt = nil
		local BestScore = math.huge

		for Index = 1, #Descendants do
			local Descendant = Descendants[Index]

			if Descendant:IsA("ProximityPrompt") and promptMatchesSelectedType(Descendant, SelectedType) then
				local Position = getPromptPosition(Descendant)
				local Score = 999999

				if RootPart and Position then
					Score = (RootPart.Position - Position).Magnitude
				end

				if not Descendant.Enabled then
					Score = Score + 5000
				end

				if Score < BestScore then
					BestScore = Score
					BestPrompt = Descendant
				end
			end
		end

		return BestPrompt
	end

	function AutoTrainFeature:GetTargetPrompt()
		local Now = os.clock()

		if self.CachedPromptType == self.SelectedType then
			if isPromptValid(self.CachedPrompt) then
				if promptMatchesSelectedType(self.CachedPrompt, self.SelectedType) then
					if (Now - self.LastPromptRefreshAt) < self.PromptRefreshInterval then
						return self.CachedPrompt
					end
				end
			end
		end

		self.CachedPrompt = scanForBestPrompt(self.SelectedType)
		self.CachedPromptType = self.SelectedType
		self.LastPromptRefreshAt = Now

		return self.CachedPrompt
	end

	local function moveNearPrompt(Prompt)
		local Character = getCharacter()
		local Position, Part = getPromptPosition(Prompt)
		local LookVector
		local TargetPosition

		if not Character then
			return false
		end

		if not Position or not Part then
			return false
		end

		LookVector = Part.CFrame.LookVector

		if LookVector.Magnitude < 0.1 then
			LookVector = Vector3.new(0, 0, -1)
		end

		TargetPosition = Position + (LookVector * -AutoTrainFeature.DesiredStandDistance)
		TargetPosition = TargetPosition + Vector3.new(0, AutoTrainFeature.VerticalOffset, 0)

		return pcall(function()
			Character:PivotTo(CFrame.new(TargetPosition, Position))
		end)
	end

	local function triggerPrompt(Prompt)
		if not isPromptValid(Prompt) then
			return false
		end

		if type(fireproximityprompt) ~= "function" then
			return false
		end

		local Success = pcall(function()
			fireproximityprompt(Prompt, Prompt.HoldDuration)
		end)

		if Success then
			return true
		end

		return pcall(function()
			fireproximityprompt(Prompt)
		end)
	end

	local function resolvePath(PathParts)
		local Current = workspace

		if type(PathParts) ~= "table" then
			return nil
		end

		for Index = 1, #PathParts do
			if typeof(Current) ~= "Instance" then
				return nil
			end

			Current = Current:FindFirstChild(PathParts[Index])

			if not Current then
				return nil
			end
		end

		return Current
	end

	local function getBikeRemote()
		local Path = MachineRemotePaths[AutoTrainFeature.SelectedType] or BikeRemotePath
		local Remote = resolvePath(Path)

		if not Remote then
			return nil
		end

		if not Remote:IsA("RemoteEvent") then
			return nil
		end

		if not Remote.Parent then
			return nil
		end

		return Remote
	end

	local function getBikeRemotePosition()
		local Remote = getBikeRemote()
		local Current

		if not Remote then
			return nil
		end

		Current = Remote.Parent

		while Current do
			if Current:IsA("BasePart") then
				return Current.Position
			end

			if Current:IsA("Model") then
				local Part = Current.PrimaryPart

				if Part then
					return Part.Position
				end

				Part = Current:FindFirstChildWhichIsA("BasePart", true)

				if Part then
					return Part.Position
				end
			end

			Current = Current.Parent
		end

		return nil
	end

	local function fireBikeRemote(ActionName, Payload)
		local Remote = getBikeRemote()

		if not Remote then
			return false
		end

		return pcall(function()
			if Payload == nil then
				Remote:FireServer(ActionName)
			else
				Remote:FireServer(ActionName, Payload)
			end
		end)
	end

	local function extractBikeKeyFromInstance(Instance)
		local Candidates = {}
		local Parent = nil

		if not Instance then
			return nil
		end

		table.insert(Candidates, getInstanceText(Instance))
		table.insert(Candidates, Instance.Name)

		Parent = Instance.Parent

		if Parent then
			table.insert(Candidates, Parent.Name)

			if Parent.Parent then
				table.insert(Candidates, Parent.Parent.Name)
			end
		end

		for CandidateIndex = 1, #Candidates do
			local Squashed = squashText(Candidates[CandidateIndex])

			if Squashed ~= "" then
				for KeyIndex = 1, #BikeKeys do
					local Key = BikeKeys[KeyIndex]

					if Squashed == Key
						or Squashed == ("KEY" .. Key)
						or Squashed == ("PRESS" .. Key)
						or Squashed == ("INPUT" .. Key)
						or Squashed == ("BUTTON" .. Key)
						or string.find(Squashed, "KEY" .. Key, 1, true)
						or string.find(Squashed, "PRESS" .. Key, 1, true) then
						return Key
					end
				end
			end
		end

		return nil
	end

	local function refreshBikeUiState(ForceRefresh)
		local Now = os.clock()
		local Containers
		local ScreenCenter
		local ViewportSize
		local StartMaxDistance
		local KeyMaxDistance
		local BestStartButton = nil
		local BestStartScore = -math.huge
		local BestKey = nil
		local BestKeySignature = nil
		local BestKeyScore = -math.huge
		local ActionMenuVisible = false

		if not ForceRefresh then
			if (Now - AutoTrainFeature.LastBikeUiRefreshAt) < AutoTrainFeature.BikeUiRefreshCooldown then
				return
			end
		end

		Containers = getGuiContainers(false)
		ScreenCenter, ViewportSize = getScreenCenter()
		StartMaxDistance = math.max(ViewportSize.X, ViewportSize.Y) * 0.42
		KeyMaxDistance = math.max(ViewportSize.X, ViewportSize.Y) * 0.38

		for ContainerIndex = 1, #Containers do
			local Descendants = Containers[ContainerIndex]:GetDescendants()

			for Index = 1, #Descendants do
				local Descendant = Descendants[Index]

				if Descendant:IsA("GuiObject") and isVisibleGuiObject(Descendant) then
					local Text = normalizeText(getInstanceText(Descendant))

					if Text == "start"
						or string.find(Text, "choose an action", 1, true)
						or string.find(Text, "start with macro", 1, true) then
						ActionMenuVisible = true
					end

					if Text == "start" then
						local Button = getGuiButtonFromInstance(Descendant)

						if Button and isVisibleGuiObject(Button) then
							local Center, Size = getGuiCenter(Button)

							if Center and Size and Size.X >= 80 and Size.Y >= 20 then
								local Distance = (Center - ScreenCenter).Magnitude

								if Distance <= StartMaxDistance then
									local Score = math.min(Size.X * Size.Y, 20000)
									Score = Score + math.max(0, 450 - Distance)

									if Score > BestStartScore then
										BestStartScore = Score
										BestStartButton = Button
									end
								end
							end
						end
					end

					do
						local KeyText = extractBikeKeyFromInstance(Descendant)

						if KeyText then
							local Center, Size = getGuiCenter(Descendant)

							if Center and Size and Size.X >= 18 and Size.Y >= 18 then
								local Distance = (Center - ScreenCenter).Magnitude

								if Distance <= KeyMaxDistance then
									local Score = math.min(Size.X * Size.Y, 5000)
									Score = Score + math.max(0, 250 - Distance)

									if Score > BestKeyScore then
										BestKeyScore = Score
										BestKey = KeyText
										BestKeySignature = KeyText
									end
								end
							end
						end
					end
				end
			end
		end

		AutoTrainFeature.LastBikeUiRefreshAt = Now
		AutoTrainFeature.CachedBikeActionMenuVisible = ActionMenuVisible
		AutoTrainFeature.CachedBikeStartButton = BestStartButton
		AutoTrainFeature.CachedBikeKey = BestKey
		AutoTrainFeature.CachedBikeKeySignature = BestKeySignature
	end

	local function isBikeActionMenuVisible(ForceRefresh)
		refreshBikeUiState(ForceRefresh)
		return AutoTrainFeature.CachedBikeActionMenuVisible and true or false
	end

	local function findVisibleBikeStartButton(ForceRefresh)
		refreshBikeUiState(ForceRefresh)
		return AutoTrainFeature.CachedBikeStartButton
	end

	local function getVisibleBikeKeyCandidate(ForceRefresh)
		refreshBikeUiState(ForceRefresh)
		return AutoTrainFeature.CachedBikeKey, AutoTrainFeature.CachedBikeKeySignature
	end

	local function isNearBikeRemote()
		local RootPart = getRootPart()
		local BikePosition = getBikeRemotePosition()

		if not RootPart or not BikePosition then
			return false
		end

		return (RootPart.Position - BikePosition).Magnitude <= AutoTrainFeature.MaxRemoteStartDistance
	end

	local function isBikeSeatPart(SeatPart)
		local Current = SeatPart

		while Current do
			for Type in pairs(RemoteMachineTypes) do
				if containsAlias(Current.Name, MachineAliases[Type] or {}) then
					return true
				end
			end

			Current = Current.Parent
		end

		return false
	end

	local function isBikeRideActive(Now)
		local Humanoid = getHumanoid()
		local SeatPart = nil

		if AutoTrainFeature.BikeActiveUntil > Now then
			if AutoTrainFeature.BikeRideStartedAt > 0 and (Now - AutoTrainFeature.BikeRideStartedAt) > AutoTrainFeature.MaxBikeRideDuration then
				AutoTrainFeature.BikeActiveUntil = 0
				AutoTrainFeature.BikeRideStartedAt = 0
				AutoTrainFeature.LastRideEndAt = Now
				return false
			end
			return true
		end

		if not Humanoid then
			return false
		end

		SeatPart = Humanoid.SeatPart

		if SeatPart and isBikeSeatPart(SeatPart) then
			return true
		end

		if Humanoid.Sit and isNearBikeRemote() then
			return true
		end

		return false
	end

	function AutoTrainFeature:TryBikeStart(Now)
		local StartButton = nil
		local Triggered = false
		local TriggerSource = nil

		if not isRemoteMachine(self.SelectedType) then
			return false
		end

		if (Now - self.LastStartAt) < self.StartCooldown then
			return false
		end

		local RecentTrigger = (Now - self.LastProximityTriggerAt) < 8
		if not isBikeActionMenuVisible() and not (isNearBikeRemote() and RecentTrigger) then
			return false
		end

		StartButton = findVisibleBikeStartButton()

		if StartButton then
			if clickGuiButton(StartButton) then
				Triggered = true
				TriggerSource = "button"
			end
		end

		if fireBikeRemote("Start", {Macro = false}) then
			Triggered = true
			if TriggerSource then
				TriggerSource = TriggerSource .. "+remote"
			else
				TriggerSource = "remote"
			end
		end

		if Triggered then
			self.LastStartAt = Now
			self.BikeActiveUntil = Now + self.BikeAssumeActiveDuration
			self.BikeRideStartedAt = Now
			self.LastUiKeyAt = Now
			self.LastBikeUiRefreshAt = 0
			debugBike("Bike start sent via " .. tostring(TriggerSource), true)
			return true
		end

		debugBike("Bike start failed: no button/remote response", false)

		return false
	end

	function AutoTrainFeature:TryBikePressKey(Now)
		local Key
		local Signature
		local BlindKey = nil
		local Triggered = false

		if not isRemoteMachine(self.SelectedType) then
			return false
		end

		if (Now - self.LastKeyAt) < self.KeyCooldown then
			return false
		end

		if self.StaminaThreshold > 0 then
			local StaminaPct = getStaminaPercent()

			if StaminaPct <= self.StaminaThreshold then
				self.StaminaPaused = true
			end

			if self.StaminaPaused then
				local ResumeAt = self:GetContinueThreshold()

				if StaminaPct >= ResumeAt then
					self.StaminaPaused = false
				else
					return false
				end
			end
		end

		Key, Signature = getVisibleBikeKeyCandidate(false)

		if Key then
			self.LastUiKeyAt = Now

			if Signature == self.LastKeySignature then
				if (Now - self.LastKeySignatureAt) < self.RepeatKeyCooldown then
					return false
				end
			end

			if fireBikeRemote("PressKey", {Key = Key}) then
				Triggered = true
			end

			if sendBikePhysicalKey(Key) then
				Triggered = true
			end

			if Triggered then
				self.LastKeyAt = Now
				self.LastKeySignature = Signature
				self.LastKeySignatureAt = Now
				self.BikeActiveUntil = Now + self.BikeAssumeActiveDuration
				self.LastBikeUiRefreshAt = 0
				debugBike("Bike key from UI: " .. tostring(Key), false)
				return true
			end
		end

		if (Now - self.LastUiKeyAt) < 4.0 then
			return false
		end

		if (Now - self.LastBlindBikeKeyAt) < self.BlindBikeKeyCooldown then
			return false
		end

		self.BlindBikeKeyIndex = self.BlindBikeKeyIndex + 1

		if self.BlindBikeKeyIndex > #BikeKeys then
			self.BlindBikeKeyIndex = 1
		end

		BlindKey = BikeKeys[self.BlindBikeKeyIndex]

		Triggered = false

		if fireBikeRemote("PressKey", {Key = BlindKey}) then
			Triggered = true
		end

		if sendBikePhysicalKey(BlindKey) then
			Triggered = true
		end

		if Triggered then
			self.LastKeyAt = Now
			self.LastBlindBikeKeyAt = Now
			self.LastKeySignature = "blind:" .. BlindKey
			self.LastKeySignatureAt = Now
			self.BikeActiveUntil = Now + self.BikeAssumeActiveDuration
			self.LastBikeUiRefreshAt = 0
			debugBike("Bike blind key: " .. tostring(BlindKey), false)
			return true
		end

		debugBike("Bike key send failed", false)

		return false
	end

	local LeavePromptCache = {Prompt = nil, At = 0}

	local function findLeavePrompt()
		local Now = os.clock()

		if LeavePromptCache.Prompt
			and LeavePromptCache.Prompt.Parent
			and (Now - LeavePromptCache.At) < 5 then
			return LeavePromptCache.Prompt
		end

		local RootPart = getRootPart()
		local Best = nil
		local BestDist = math.huge

		for _, Desc in ipairs(workspace:GetDescendants()) do
			if Desc:IsA("ProximityPrompt") then
				local ActionLower = string.lower(Desc.ActionText or "")
				local ObjectLower = string.lower(Desc.ObjectText or "")

				if string.find(ActionLower, "leave", 1, true) or string.find(ObjectLower, "leave", 1, true) then
					local Dist = 999

					if RootPart and Desc.Parent then
						local Part = Desc.Parent
						local Ok, Pos = pcall(function()
							return Part:IsA("BasePart") and Part.Position
								or Part:FindFirstChildOfClass("BasePart") and Part:FindFirstChildOfClass("BasePart").Position
								or nil
						end)

						if Ok and Pos then
							Dist = (RootPart.Position - Pos).Magnitude
						end
					end

					if Dist < BestDist then
						BestDist = Dist
						Best = Desc
					end
				end
			end
		end

		LeavePromptCache.Prompt = Best
		LeavePromptCache.At = Now

		return Best
	end

	local function getInputRemote()
		local Character = getCharacter()
		if not Character then return nil end
		local MainScript = Character:FindFirstChild("MainScript")
		if not MainScript then return nil end
		local Remote = MainScript:FindFirstChild("Input")
		if not Remote or not Remote:IsA("RemoteEvent") then return nil end
		return Remote
	end

	local function fireInputKey(KeyName, IsDown)
		local Remote = getInputRemote()
		if not Remote then return false end
		return pcall(function()
			Remote:FireServer({
				KeyInfo = {Direction = "None", Name = KeyName, Airborne = false},
				IsDown = IsDown
			})
		end)
	end

	local StrengthBagRemoteCache = {Remote = nil, At = 0}

	local function findNearestStrengthBagRemote()
		local Now = os.clock()
		if StrengthBagRemoteCache.Remote
			and StrengthBagRemoteCache.Remote.Parent
			and (Now - StrengthBagRemoteCache.At) < 3 then
			return StrengthBagRemoteCache.Remote
		end

		-- Find root model of nearest bag via its proximity prompt
		local Prompt = AutoTrainFeature:GetTargetPrompt()
		local BagRoot = Prompt and Prompt.Parent
		while BagRoot and BagRoot ~= workspace do
			if BagRoot:IsA("Model") then break end
			BagRoot = BagRoot.Parent
		end

		local Remote = nil

		if BagRoot and BagRoot ~= workspace then
			for _, Desc in ipairs(BagRoot:GetDescendants()) do
				if Desc:IsA("RemoteEvent") and Desc.Name == "RemoteEvent" then
					Remote = Desc
					break
				end
			end
		end

		-- Fallback: scan all workspace for the nearest bag remote by distance
		if not Remote then
			local RootPart = getRootPart()
			local Aliases = MachineAliases["Strength"] or {}
			local BestDist = math.huge

			for _, Desc in ipairs(workspace:GetDescendants()) do
				if Desc:IsA("RemoteEvent") and Desc.Name == "RemoteEvent" then
					local Current = Desc.Parent
					local IsBag = false
					local Pos = nil

					for _ = 1, 8 do
						if not Current or Current == workspace then break end
						if containsAlias(Current.Name, Aliases) then IsBag = true end
						if not Pos then
							if Current:IsA("BasePart") then
								Pos = Current.Position
							elseif Current:IsA("Model") then
								local Part = Current.PrimaryPart or Current:FindFirstChildWhichIsA("BasePart")
								if Part then Pos = Part.Position end
							end
						end
						Current = Current.Parent
					end

					if IsBag then
						local Dist = (RootPart and Pos) and (RootPart.Position - Pos).Magnitude or 999
						if Dist < BestDist then
							BestDist = Dist
							Remote = Desc
						end
					end
				end
			end
		end

		StrengthBagRemoteCache.Remote = Remote
		StrengthBagRemoteCache.At = Now
		return Remote
	end

	local function fireStrengthBagRemote()
		local Remote = findNearestStrengthBagRemote()
		if not Remote then return false end
		return pcall(function()
			Remote:FireServer("str")
		end)
	end

	function AutoTrainFeature:StepStrength(Now)
		if self.EatingBreak then
			self.StrengthGlovesActive = false
			return
		end

		if FoodFeature and FoodFeature.Enabled and FoodFeature:ShouldEat() then
			self.StrengthGlovesActive = false
			return
		end

		-- Session timeout: re-equip if no hit for too long
		if self.StrengthGlovesActive and (Now - self.LastStrengthHitAt) > self.StrengthSessionTimeout then
			self.StrengthGlovesActive = false
		end

		if not self.StrengthGlovesActive then
			-- Try proximity prompt first to get near the bag
			if (Now - self.LastPromptAt) >= self.PromptCooldown then
				local Prompt = self:GetTargetPrompt()
				if Prompt then
					local RootPart = getRootPart()
					local PromptPos = getPromptPosition(Prompt)
					if RootPart and PromptPos then
						local Dist = (RootPart.Position - PromptPos).Magnitude
						local MaxDist = math.max((Prompt.MaxActivationDistance or 10) - 1, 3)
						if Dist > MaxDist then
							if moveNearPrompt(Prompt) then
								self.LastPromptAt = Now
							end
							return
						end
					end
				end
			end

			-- Press E to equip gloves
			if (Now - self.LastStrengthEquipAt) < self.StrengthEquipCooldown then return end
			self.LastStrengthEquipAt = Now

			task.spawn(function()
				fireInputKey("E", true)
				task.wait(0.05)
				fireInputKey("E", false)
			end)

			self.StrengthGlovesActive = true
			self.StrengthPunchIndex = 0
			self.LastStrengthHitAt = Now
			return
		end

		if self.StaminaThreshold > 0 then
			StaminaCache.At = 0
			local StaminaPct = getStaminaPercent()
			if StaminaPct <= self.StaminaThreshold then
				self.StaminaPaused = true
			end
			if self.StaminaPaused then
				if StaminaPct >= self:GetContinueThreshold() then
					self.StaminaPaused = false
				else
					self.LastStrengthHitAt = Now
					return
				end
			end
		end

		if (Now - self.LastStrengthPunchAt) < self.StrengthPunchCooldown then return end
		self.LastStrengthPunchAt = Now

		self.StrengthPunchIndex = (self.StrengthPunchIndex % 5) + 1
		local KeyName = self.StrengthPunchIndex <= 4 and "LMB" or "RMB"

		task.spawn(function()
			fireInputKey(KeyName, true)
			task.wait(0.05)
			fireInputKey(KeyName, false)
		end)

		fireStrengthBagRemote()
		self.LastStrengthHitAt = Now

		if WheyFeature and WheyFeature.Enabled and WheyFeature:ShouldConsume() then
			local FoodBusy = FoodFeature and FoodFeature.IsEating
			WheyFeature:TryConsume(FoodBusy)
		end
	end

	local function findVisibleBikeLeaveButton()
		local Containers = getGuiContainers(false)
		local ScreenCenter, ViewportSize = getScreenCenter()
		local MaxDistance = math.max(ViewportSize.X, ViewportSize.Y) * 0.55
		local BestButton = nil
		local BestScore = -math.huge

		for _, Container in ipairs(Containers) do
			for _, Descendant in ipairs(Container:GetDescendants()) do
				if Descendant:IsA("GuiObject") and isVisibleGuiObject(Descendant) then
					local Text = normalizeText(getInstanceText(Descendant))

					if string.find(Text, "leave", 1, true) then
						local Button = getGuiButtonFromInstance(Descendant)

						if Button and isVisibleGuiObject(Button) then
							local Center, Size = getGuiCenter(Button)

							if Center and Size and Size.X >= 50 and Size.Y >= 16 then
								local Distance = (Center - ScreenCenter).Magnitude

								if Distance <= MaxDistance then
									local Score = math.min(Size.X * Size.Y, 20000) + math.max(0, 450 - Distance)

									if Score > BestScore then
										BestScore = Score
										BestButton = Button
									end
								end
							end
						end
					end
				end
			end
		end

		return BestButton
	end

	function AutoTrainFeature:TryBikeLeave()
		if not isRemoteMachine(self.SelectedType) then
			return false
		end

		LeavePromptCache.At = 0

		fireBikeRemote("Leave")

		local LeaveButton = findVisibleBikeLeaveButton()
		if LeaveButton then
			clickGuiButton(LeaveButton)
		end

		local LeavePrompt = findLeavePrompt()
		if LeavePrompt then
			triggerPrompt(LeavePrompt)
		end

		return true
	end


	function AutoTrainFeature:Step()
		local Now
		local TrainingState
		local Prompt
		local RootPart
		local PromptPosition
		local BikeMenuVisible
		local BikeRideActive

		if not self.Enabled then
			return
		end

		local CurrentBodyFatigue = getBodyFatigue()

		if CurrentBodyFatigue >= 100 then
			if not self.FatigueNotified and Webhook and Webhook:IsConfigured() then
				self.FatigueNotified = true
				Webhook:Send(string.format(
					"[KELV] %s — Body Fatigue is full (100%%). Auto train stopped.",
					LocalPlayer.Name
				))
			end

			if self.MaxFatigueAction == "Kick" then
				pcall(function()
					LocalPlayer:Kick()
				end)
			end

			return
		else
			if CurrentBodyFatigue < 90 then
				self.FatigueNotified = false
			end
		end

		Now = os.clock()

		if FoodFeature and FoodFeature.Enabled then
			local IsHungry = FoodFeature:ShouldEat()

			if IsHungry and not self.EatingBreak then
				self.EatingBreak = true
				self.EatingBreakDismounted = false
				self.LastLeaveAttemptAt = 0
				LeavePromptCache.At = 0
				self.StrengthGlovesActive = false

				if Notification then
					Notification:Notify({
						Title = "Auto Eat",
						Content = "Hungry — leaving machine",
						Icon = "alert-circle"
					})
				end
			end

			if self.EatingBreak then
				if not IsHungry and not FoodFeature.IsEating then
					self.EatingBreak = false
					self.LastRideEndAt = Now
					StrengthBagRemoteCache.At = 0

					if Notification then
						Notification:Notify({
							Title = "Auto Eat",
							Content = "Done eating — re-entering machine",
							Icon = "check-circle"
						})
					end
				else
					if isRemoteMachine(self.SelectedType) then
						self.BikeActiveUntil = 0
						self.BikeRideStartedAt = 0
						self.LastRideEndAt = Now

						if (Now - (self.LastLeaveAttemptAt or 0)) > 1.5 then
							self.LastLeaveAttemptAt = Now
							self:TryBikeLeave()
						end
					end
					return
				end
			end
		end

		if self.SelectedType == "Strength" then
			self:StepStrength(Now)
			return
		end

		TrainingState = getTrainingState(self.SelectedType)

		if isRemoteMachine(self.SelectedType) then
			if self.BikeRideStartedAt > 0 and (Now - self.BikeRideStartedAt) > 5 then
				if not TrainingState.IsTraining then
					self.BikeActiveUntil = 0
					self.BikeRideStartedAt = 0
					self.LastRideEndAt = Now
				end
			end

			refreshBikeUiState(false)
			BikeMenuVisible = self.CachedBikeActionMenuVisible

			if BikeMenuVisible then
				self:TryBikeStart(Now)
				return
			end

			BikeRideActive = isBikeRideActive(Now)

			if BikeRideActive then
				self:TryBikePressKey(Now)
				return
			end

			if (Now - self.LastRideEndAt) < 1.0 then
				return
			end

			if WheyFeature and WheyFeature.Enabled and WheyFeature:ShouldConsume() then
				local FoodBusy = FoodFeature and FoodFeature.IsEating
				WheyFeature:TryConsume(FoodBusy)
				return
			end

			if self:TryBikeStart(Now) then
				return
			end
		end

		if not isRemoteMachine(self.SelectedType) and TrainingState.IsTraining then
			return
		end

		if (Now - self.LastPromptAt) < self.PromptCooldown then
			return
		end

		Prompt = self:GetTargetPrompt()

		if not Prompt then
			return
		end

		RootPart = getRootPart()
		PromptPosition = getPromptPosition(Prompt)

		if RootPart and PromptPosition then
			local Distance = (RootPart.Position - PromptPosition).Magnitude
			local MaxDistance = Prompt.MaxActivationDistance or 10

			MaxDistance = math.max(MaxDistance - 1, 3)

			if Distance > MaxDistance then
				if moveNearPrompt(Prompt) then
					self.LastPromptAt = Now
				end

				return
			end
		end

		if triggerPrompt(Prompt) then
			self.LastPromptAt = Now
			self.LastProximityTriggerAt = Now
		else
			self.CachedPrompt = nil
			self.CachedPromptType = nil
		end
	end

	function AutoTrainFeature:GetAvailableTypes()
		return copyArray(AvailableTypes)
	end

	function AutoTrainFeature:GetSelectedType()
		return self.SelectedType
	end

	function AutoTrainFeature:SetSelectedType(Value)
		for Index = 1, #AvailableTypes do
			if AvailableTypes[Index] == Value then
				self.SelectedType = Value
				self.CachedPrompt = nil
				self.CachedPromptType = nil
				self.LastPromptRefreshAt = 0
				self.LastBlindBikeKeyAt = 0
				self.LastKeySignature = nil
				self.LastKeySignatureAt = 0
				self.LastBikeUiRefreshAt = 0
				self.CachedBikeActionMenuVisible = false
				self.CachedBikeStartButton = nil
				self.CachedBikeKey = nil
				self.CachedBikeKeySignature = nil
				self.BlindBikeKeyIndex = 0
				self.BikeActiveUntil = 0
				self.BikeRideStartedAt = 0
				self.LastProximityTriggerAt = 0
				self.LastUiKeyAt = 0
				self.StaminaPaused = false
				self.LastRideEndAt = 0
				self.LastDebugNotifyAt = 0
				self.LastDebugMessage = ""
				self.StrengthGlovesActive = false
				self.StrengthPunchIndex = 0
				self.LastStrengthPunchAt = 0
				self.LastStrengthEquipAt = 0
				self.LastStrengthHitAt = 0
				return true
			end
		end

		return false
	end

	function AutoTrainFeature:GetStaminaThreshold()
		return self.StaminaThreshold
	end

	function AutoTrainFeature:SetStaminaThreshold(Value)
		if type(Value) == "number" and Value >= 0 and Value <= 100 then
			self.StaminaThreshold = Value
			return true
		end
		return false
	end

	function AutoTrainFeature:GetContinueThreshold()
		if self.ContinueLevel == "low" then
			return 30
		elseif self.ContinueLevel == "high" then
			return 80
		end
		return 50
	end

	function AutoTrainFeature:GetContinueLevel()
		return self.ContinueLevel
	end

	function AutoTrainFeature:SetContinueLevel(Value)
		if Value == "low" or Value == "mid" or Value == "high" then
			self.ContinueLevel = Value
			return true
		end
		return false
	end

	function AutoTrainFeature:GetMaxFatigueAction()
		return self.MaxFatigueAction
	end

	function AutoTrainFeature:SetMaxFatigueAction(Value)
		if Value == "Do nothing" or Value == "Kick" then
			self.MaxFatigueAction = Value
			return true
		end
		return false
	end

	function AutoTrainFeature:SetEnabled(Value)
		local State = false

		if Value then
			State = true
		end

		if self.Enabled == State then
			return State
		end

		self.Enabled = State
		self.LastPromptAt = 0
		self.LastStartAt = 0
		self.LastKeyAt = 0
		self.LastBlindBikeKeyAt = 0
		self.LastKeySignature = nil
		self.LastKeySignatureAt = 0
		self.CachedPrompt = nil
		self.CachedPromptType = nil
		self.LastPromptRefreshAt = 0
		self.LastBikeUiRefreshAt = 0
		self.CachedBikeActionMenuVisible = false
		self.CachedBikeStartButton = nil
		self.CachedBikeKey = nil
		self.CachedBikeKeySignature = nil
		self.BlindBikeKeyIndex = 0
		self.BikeActiveUntil = 0
		self.BikeRideStartedAt = 0
		self.LastProximityTriggerAt = 0
		self.LastUiKeyAt = 0
		self.StaminaPaused = false
		self.LastRideEndAt = 0
		self.LastDebugNotifyAt = 0
		self.LastDebugMessage = ""
		self.StrengthGlovesActive = false
		self.StrengthPunchIndex = 0
		self.LastStrengthPunchAt = 0
		self.LastStrengthEquipAt = 0
		self.LastStrengthHitAt = 0

		if self.Connection then
			self.Connection:Disconnect()
			self.Connection = nil
		end

		if State then
			self.Elapsed = self.LoopInterval
			self.Connection = RunService.Heartbeat:Connect(function(DeltaTime)
				self.Elapsed = self.Elapsed + DeltaTime

				if self.Elapsed < self.LoopInterval then
					return
				end

				self.Elapsed = 0
				self:Step()
			end)

			if Notification then
				local Message = "Enabled (" .. tostring(self.SelectedType) .. ")"

				if isRemoteMachine(self.SelectedType) then
					Message = "Enabled (" .. tostring(self.SelectedType) .. ") - direct remote active"
				end

				Notification:Notify({
					Title = "Auto Train",
					Content = Message,
					Icon = "check-circle"
				})
			end

			if isRemoteMachine(self.SelectedType) then
				debugBike(tostring(self.SelectedType) .. " debug active", true)
			end
		else
			if isRemoteMachine(self.SelectedType) then
				self:TryBikeLeave()
			end

			if Notification then
				Notification:Notify({
					Title = "Auto Train",
					Content = "Disabled",
					Icon = "x-circle"
				})
			end
		end

		return State
	end

	function AutoTrainFeature:Destroy()
		self:SetEnabled(false)
		self.CachedPrompt = nil
		self.CachedPromptType = nil

		if self.FatigueMonitorConnection then
			self.FatigueMonitorConnection:Disconnect()
			self.FatigueMonitorConnection = nil
		end
	end

	do
		local FatigueMonitorInterval = 2
		local FatigueMonitorLast = 0

		AutoTrainFeature.FatigueMonitorConnection = RunService.Heartbeat:Connect(function()
			if not Webhook or not Webhook:IsConfigured() then
				return
			end

			local Now = os.clock()

			if (Now - FatigueMonitorLast) < FatigueMonitorInterval then
				return
			end

			FatigueMonitorLast = Now

			local Fatigue = getBodyFatigue()

			if Fatigue <= 0 then
				if not AutoTrainFeature.BedRecoveryNotified then
					AutoTrainFeature.BedRecoveryNotified = true
					Webhook:Send(string.format(
						"[KELV] %s — Body Fatigue recovered to 0%%! Ready to train.",
						LocalPlayer.Name
					), true)
				end
			else
				if Fatigue > 10 then
					AutoTrainFeature.BedRecoveryNotified = false
				end
			end
		end)
	end

	return AutoTrainFeature
end
