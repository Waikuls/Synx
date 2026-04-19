return function(Config)
	local Players = game:GetService("Players")
	local RunService = game:GetService("RunService")
	local LocalPlayer = Players.LocalPlayer
	local Notification = Config and Config.Notification

	local AvailableTypes = {
		"Bag",
		"Bar",
		"Bench",
		"Bike",
		"Squat machine",
		"Treadmill"
	}

	local MachineAliases = {}
	MachineAliases["Bag"] = {"bag", "punching bag"}
	MachineAliases["Bar"] = {"bar", "barbell"}
	MachineAliases["Bench"] = {"bench", "bench press"}
	MachineAliases["Bike"] = {"bike", "cycling", "cycle"}
	MachineAliases["Squat machine"] = {"squat machine", "squat", "leg press"}
	MachineAliases["Treadmill"] = {"treadmill", "running machine"}

	local BikeRemotePath = {"TrainingSpots", "Bike", "Radio", "Remote"}
	local BikeKeys = {"W", "A", "S", "D"}

	local AutoTrainFeature = {}
	AutoTrainFeature.Enabled = false
	AutoTrainFeature.SelectedType = "Bike"
	AutoTrainFeature.Connection = nil
	AutoTrainFeature.Elapsed = 0
	AutoTrainFeature.LoopInterval = 0.12
	AutoTrainFeature.PromptCooldown = 0.75
	AutoTrainFeature.StartCooldown = 0.35
	AutoTrainFeature.KeyCooldown = 0.08
	AutoTrainFeature.RepeatKeyCooldown = 0.3
	AutoTrainFeature.DesiredStandDistance = 4
	AutoTrainFeature.VerticalOffset = 2.5
	AutoTrainFeature.MaxRemoteStartDistance = 18
	AutoTrainFeature.LastPromptAt = 0
	AutoTrainFeature.LastStartAt = 0
	AutoTrainFeature.LastKeyAt = 0
	AutoTrainFeature.LastKeySignature = nil
	AutoTrainFeature.LastKeySignatureAt = 0
	AutoTrainFeature.CachedPrompt = nil
	AutoTrainFeature.CachedPromptType = nil
	AutoTrainFeature.LastPromptRefreshAt = 0
	AutoTrainFeature.PromptRefreshInterval = 2

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

	local function getScreenCenter()
		local Camera = workspace.CurrentCamera
		local ViewportSize = Vector2.new(1280, 720)

		if Camera then
			ViewportSize = Camera.ViewportSize
		end

		return ViewportSize * 0.5, ViewportSize
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
		local Remote = resolvePath(BikeRemotePath)

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

	local function isBikeActionMenuVisible()
		local PlayerGui = getPlayerGui()
		local Descendants

		if not PlayerGui then
			return false
		end

		Descendants = PlayerGui:GetDescendants()

		for Index = 1, #Descendants do
			local Descendant = Descendants[Index]

			if isVisibleGuiObject(Descendant) then
				local Text = normalizeText(getInstanceText(Descendant))

				if Text == "start" then
					return true
				end

				if string.find(Text, "choose an action", 1, true) then
					return true
				end

				if string.find(Text, "start with macro", 1, true) then
					return true
				end
			end
		end

		return false
	end

	local function getVisibleBikeKeyCandidate()
		local PlayerGui = getPlayerGui()
		local Descendants
		local ScreenCenter
		local ViewportSize
		local MaxDistance
		local BestKey = nil
		local BestSignature = nil
		local BestScore = -math.huge

		if not PlayerGui then
			return nil, nil
		end

		ScreenCenter, ViewportSize = getScreenCenter()
		MaxDistance = math.max(ViewportSize.X, ViewportSize.Y) * 0.38
		Descendants = PlayerGui:GetDescendants()

		for Index = 1, #Descendants do
			local Descendant = Descendants[Index]

			if Descendant:IsA("GuiObject") and isVisibleGuiObject(Descendant) then
				local Text = string.upper(normalizeText(getInstanceText(Descendant)))
				local IsKey = false

				for KeyIndex = 1, #BikeKeys do
					if Text == BikeKeys[KeyIndex] then
						IsKey = true
						break
					end
				end

				if IsKey then
					local Center, Size = getGuiCenter(Descendant)

					if Center and Size then
						if Size.X >= 18 and Size.Y >= 18 then
							local Distance = (Center - ScreenCenter).Magnitude

							if Distance <= MaxDistance then
								local Score = math.min(Size.X * Size.Y, 5000)
								Score = Score + math.max(0, 250 - Distance)

								if Score > BestScore then
									BestScore = Score
									BestKey = Text
									BestSignature = Text
								end
							end
						end
					end
				end
			end
		end

		return BestKey, BestSignature
	end

	local function isNearBikeRemote()
		local RootPart = getRootPart()
		local BikePosition = getBikeRemotePosition()

		if not RootPart or not BikePosition then
			return false
		end

		return (RootPart.Position - BikePosition).Magnitude <= AutoTrainFeature.MaxRemoteStartDistance
	end

	function AutoTrainFeature:TryBikeStart(Now)
		if self.SelectedType ~= "Bike" then
			return false
		end

		if (Now - self.LastStartAt) < self.StartCooldown then
			return false
		end

		if not isBikeActionMenuVisible() and not isNearBikeRemote() then
			return false
		end

		if fireBikeRemote("Start", {Macro = false}) then
			self.LastStartAt = Now
			return true
		end

		return false
	end

	function AutoTrainFeature:TryBikePressKey(Now)
		local Key
		local Signature

		if self.SelectedType ~= "Bike" then
			return false
		end

		if (Now - self.LastKeyAt) < self.KeyCooldown then
			return false
		end

		Key, Signature = getVisibleBikeKeyCandidate()

		if not Key then
			return false
		end

		if Signature == self.LastKeySignature then
			if (Now - self.LastKeySignatureAt) < self.RepeatKeyCooldown then
				return false
			end
		end

		if fireBikeRemote("PressKey", {Key = Key}) then
			self.LastKeyAt = Now
			self.LastKeySignature = Signature
			self.LastKeySignatureAt = Now
			return true
		end

		return false
	end

	function AutoTrainFeature:TryBikeLeave()
		if self.SelectedType ~= "Bike" then
			return false
		end

		return fireBikeRemote("Leave")
	end

	function AutoTrainFeature:Step()
		local Now
		local TrainingState
		local Prompt
		local RootPart
		local PromptPosition
		local BikeMenuVisible

		if not self.Enabled then
			return
		end

		Now = os.clock()
		TrainingState = getTrainingState(self.SelectedType)

		if self.SelectedType == "Bike" then
			BikeMenuVisible = isBikeActionMenuVisible()

			if BikeMenuVisible then
				self:TryBikeStart(Now)
				return
			end

			if self:TryBikePressKey(Now) then
				return
			end

			if self:TryBikeStart(Now) then
				return
			end
		end

		if TrainingState.IsTraining then
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
				self.LastKeySignature = nil
				self.LastKeySignatureAt = 0
				return true
			end
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
		self.LastKeySignature = nil
		self.LastKeySignatureAt = 0
		self.CachedPrompt = nil
		self.CachedPromptType = nil
		self.LastPromptRefreshAt = 0

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

				if self.SelectedType == "Bike" then
					Message = "Enabled (Bike) - direct remote active"
				end

				Notification:Notify({
					Title = "Auto Train",
					Content = Message,
					Icon = "check-circle"
				})
			end
		else
			if self.SelectedType == "Bike" then
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
	end

	return AutoTrainFeature
end
