return function(Config)
	local Players = game:GetService("Players")
	local RunService = game:GetService("RunService")
	local LocalPlayer = Players.LocalPlayer
	local Notification = Config and Config.Notification

	local AvailableTypes = {"Bag", "Bar", "Bench", "Bike", "Squat machine", "Treadmill"}
	local KeyAliases = {
		W = true,
		A = true,
		S = true,
		D = true
	}
	local MachineDefinitions = {
		["Bag"] = {
			Aliases = {"bag", "punching bag"}
		},
		["Bar"] = {
			Aliases = {"bar", "barbell"}
		},
		["Bench"] = {
			Aliases = {"bench", "bench press"}
		},
		["Bike"] = {
			Aliases = {"bike", "cycling", "cycle"},
			RemotePath = {"TrainingSpots", "Bike", "Radio", "Remote"}
		},
		["Squat machine"] = {
			Aliases = {"squat machine", "squat", "leg press"}
		},
		["Treadmill"] = {
			Aliases = {"treadmill", "running machine"}
		}
	}

	local AutoTrainFeature = {
		Enabled = false,
		SelectedType = "Bike",
		Connection = nil,
		Elapsed = 0,
		LoopInterval = 0.12,
		PromptCooldown = 0.75,
		StartCooldown = 0.35,
		KeyCooldown = 0.08,
		RepeatKeyCooldown = 0.3,
		DesiredStandDistance = 4,
		VerticalOffset = 2.5,
		MaxRemoteStartDistance = 18,
		LastPromptAt = 0,
		LastStartAt = 0,
		LastKeyAt = 0,
		LastKeySignature = nil,
		LastKeySignatureAt = 0,
		CachedPrompt = nil,
		CachedPromptType = nil,
		LastPromptRefreshAt = 0,
		PromptRefreshInterval = 2
	}

	local function trimString(Value)
		if typeof(Value) ~= "string" then
			return nil
		end

		return string.match(Value, "^%s*(.-)%s*$")
	end

	local function normalizeText(Value)
		local Trimmed = trimString(Value)

		if not Trimmed or Trimmed == "" then
			return ""
		end

		return string.lower((string.gsub(Trimmed, "%s+", " ")))
	end

	local function containsAlias(Text, Aliases)
		local Normalized = normalizeText(Text)

		if Normalized == "" then
			return false
		end

		for _, Alias in ipairs(Aliases) do
			if string.find(Normalized, Alias, 1, true) then
				return true
			end
		end

		return false
	end

	local function getMachineDefinition(SelectedType)
		return MachineDefinitions[SelectedType]
	end

	local function getSelectedAliases(SelectedType)
		local Definition = getMachineDefinition(SelectedType)

		if Definition and type(Definition.Aliases) == "table" then
			return Definition.Aliases
		end

		return {normalizeText(SelectedType)}
	end

	local function getCharacter()
		return LocalPlayer.Character
	end

	local function getRootPart()
		local Character = getCharacter()

		if not Character then
			return nil
		end

		return Character:FindFirstChild("HumanoidRootPart")
			or Character:FindFirstChild("UpperTorso")
			or Character:FindFirstChild("Torso")
	end

	local function getPlayerGui()
		return LocalPlayer:FindFirstChildOfClass("PlayerGui")
	end

	local function isVisibleGuiObject(Instance)
		if not Instance or not Instance:IsA("GuiObject") then
			return false
		end

		local Current = Instance

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
		if not Instance or not Instance:IsA("GuiObject") then
			return nil, nil
		end

		local Success, Position, Size = pcall(function()
			return Instance.AbsolutePosition, Instance.AbsoluteSize
		end)

		if not Success or not Position or not Size then
			return nil, nil
		end

		return Position + (Size * 0.5), Size
	end

	local function getScreenCenter()
		local Camera = workspace.CurrentCamera
		local ViewportSize = Camera and Camera.ViewportSize or Vector2.new(1280, 720)

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

		for _, Descendant in ipairs(Entity:GetDescendants()) do
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

		return MainScript:FindFirstChild("Stats") or MainScript:FindFirstChild("Stats", true)
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
		if typeof(Value) == "boolean" then
			return Value
		end

		if typeof(Value) == "number" then
			return Value ~= 0
		end

		if typeof(Value) == "string" then
			local Lower = normalizeText(Value)
			return Lower == "true" or Lower == "yes" or Lower == "active"
		end

		return false
	end

	local function getTrainingState(SelectedType)
		local Stats = findStatsContainer()
		local IsTraining = valueToBool(readStatsValue(Stats, "IsTrainingWithMachine"))
			or valueToBool(readStatsValue(Stats, "Training"))
		local TrainingMachine = tostring(readStatsValue(Stats, "TrainingMachine") or "")
		local IsSelectedMachine = containsAlias(TrainingMachine, getSelectedAliases(SelectedType))

		if not IsTraining and normalizeText(TrainingMachine) ~= "" then
			IsTraining = true
		end

		return {
			IsTraining = IsTraining,
			IsSelectedMachine = IsSelectedMachine,
			TrainingMachine = TrainingMachine
		}
	end

	local function getPromptPart(Prompt)
		if not Prompt or not Prompt.Parent then
			return nil
		end

		local Current = Prompt.Parent

		while Current do
			if Current:IsA("BasePart") then
				return Current
			end

			if Current:IsA("Model") then
				return Current.PrimaryPart or Current:FindFirstChildWhichIsA("BasePart", true)
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
		if not Prompt then
			return ""
		end

		local Parts = {
			Prompt.Name,
			Prompt.ActionText,
			Prompt.ObjectText
		}
		local Parent = Prompt.Parent

		if Parent then
			table.insert(Parts, Parent.Name)

			if Parent.Parent then
				table.insert(Parts, Parent.Parent.Name)
			end
		end

		return normalizeText(table.concat(Parts, " "))
	end

	local function promptMatchesSelectedType(Prompt, SelectedType)
		return containsAlias(getPromptDescription(Prompt), getSelectedAliases(SelectedType))
	end

	local function isPromptValid(Prompt)
		return Prompt and Prompt.Parent and Prompt:IsA("ProximityPrompt")
	end

	local function scanForBestPrompt(SelectedType)
		local RootPart = getRootPart()
		local BestPrompt = nil
		local BestScore = math.huge

		for _, Descendant in ipairs(workspace:GetDescendants()) do
			if Descendant:IsA("ProximityPrompt") and promptMatchesSelectedType(Descendant, SelectedType) then
				local Position = getPromptPosition(Descendant)
				local Distance = Position and RootPart and (RootPart.Position - Position).Magnitude or 999999
				local Score = Distance

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

		if self.CachedPromptType == self.SelectedType
			and isPromptValid(self.CachedPrompt)
			and promptMatchesSelectedType(self.CachedPrompt, self.SelectedType)
			and (Now - self.LastPromptRefreshAt) < self.PromptRefreshInterval then
			return self.CachedPrompt
		end

		self.CachedPrompt = scanForBestPrompt(self.SelectedType)
		self.CachedPromptType = self.SelectedType
		self.LastPromptRefreshAt = Now

		return self.CachedPrompt
	end

	local function moveNearPrompt(Prompt)
		local Character = getCharacter()
		local RootPart = getRootPart()
		local Position, Part = getPromptPosition(Prompt)

		if not Character or not RootPart or not Position or not Part then
			return false
		end

		local LookVector = Part.CFrame.LookVector

		if LookVector.Magnitude < 0.1 then
			LookVector = Vector3.new(0, 0, -1)
		end

		local TargetPosition = Position + (LookVector * -AutoTrainFeature.DesiredStandDistance) + Vector3.new(0, AutoTrainFeature.VerticalOffset, 0)

		return pcall(function()
			Character:PivotTo(CFrame.new(TargetPosition, Position))
		end)
	end

	local function triggerPrompt(Prompt)
		if not isPromptValid(Prompt) then
			return false
		end

		if type(fireproximityprompt) == "function" then
			local Success = pcall(function()
				fireproximityprompt(Prompt, Prompt.HoldDuration)
			end)

			if Success then
				return true
			end

			Success = pcall(function()
				fireproximityprompt(Prompt)
			end)

			if Success then
				return true
			end
		end

		return false
	end

	local function resolvePath(PathParts)
		if type(PathParts) ~= "table" or #PathParts == 0 then
			return nil
		end

		local Current = workspace

		for _, PartName in ipairs(PathParts) do
			if typeof(Current) ~= "Instance" then
				return nil
			end

			Current = Current:FindFirstChild(PartName)

			if not Current then
				return nil
			end
		end

		return Current
	end

	local function getBikeRemote()
		local Definition = getMachineDefinition("Bike")
		local Remote = resolvePath(Definition and Definition.RemotePath)

		if Remote
			and Remote:IsA("RemoteEvent")
			and Remote.Parent then
			return Remote
		end

		return nil
	end

	local function getBikeRemotePosition()
		local Remote = getBikeRemote()

		if not Remote or not Remote.Parent then
			return nil
		end

		local Current = Remote.Parent

		while Current do
			if Current:IsA("BasePart") then
				return Current.Position
			end

			if Current:IsA("Model") then
				local Part = Current.PrimaryPart or Current:FindFirstChildWhichIsA("BasePart", true)

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
			if Payload ~= nil then
				Remote:FireServer(ActionName, Payload)
			else
				Remote:FireServer(ActionName)
			end
		end)
	end

	local function isBikeActionMenuVisible()
		local PlayerGui = getPlayerGui()

		if not PlayerGui then
			return false
		end

		for _, Descendant in ipairs(PlayerGui:GetDescendants()) do
			if isVisibleGuiObject(Descendant) then
				local Text = normalizeText(getInstanceText(Descendant))

				if Text == "start"
					or string.find(Text, "choose an action", 1, true)
					or string.find(Text, "start with macro", 1, true) then
					return true
				end
			end
		end

		return false
	end

	local function getVisibleBikeKeyCandidate()
		local PlayerGui = getPlayerGui()

		if not PlayerGui then
			return nil, nil
		end

		local ScreenCenter, ViewportSize = getScreenCenter()
		local MaxDistance = math.max(ViewportSize.X, ViewportSize.Y) * 0.38
		local BestKey = nil
		local BestSignature = nil
		local BestScore = -math.huge

		for _, Descendant in ipairs(PlayerGui:GetDescendants()) do
			if Descendant:IsA("GuiObject") and isVisibleGuiObject(Descendant) then
				local Text = string.upper(normalizeText(getInstanceText(Descendant)))

				if KeyAliases[Text] then
					local Center, Size = getGuiCenter(Descendant)

					if Center and Size and Size.X >= 18 and Size.Y >= 18 then
						local Distance = (Center - ScreenCenter).Magnitude

						if Distance <= MaxDistance then
							local Score = math.min(Size.X * Size.Y, 5000) + math.max(0, 250 - Distance)
							local Signature = string.format(
								"%s:%d:%d:%d:%d",
								Text,
								math.floor(Center.X + 0.5),
								math.floor(Center.Y + 0.5),
								math.floor(Size.X + 0.5),
								math.floor(Size.Y + 0.5)
							)

							if Score > BestScore then
								BestScore = Score
								BestKey = Text
								BestSignature = Signature
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
		if self.SelectedType ~= "Bike" then
			return false
		end

		if (Now - self.LastKeyAt) < self.KeyCooldown then
			return false
		end

		local Key, Signature = getVisibleBikeKeyCandidate()

		if not Key then
			return false
		end

		if Signature == self.LastKeySignature
			and (Now - self.LastKeySignatureAt) < self.RepeatKeyCooldown then
			return false
		end

		if fireBikeRemote("PressKey", {
			Key = Key
		}) then
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

		return fireBikeRemote("Leave", nil)
	end

	function AutoTrainFeature:Step()
		if not self.Enabled then
			return
		end

		local Now = os.clock()
		local TrainingState = getTrainingState(self.SelectedType)

		if self.SelectedType == "Bike" then
			if self:TryBikePressKey(Now) then
				return
			end

			if not TrainingState.IsTraining and self:TryBikeStart(Now) then
				return
			end
		end

		if TrainingState.IsTraining then
			return
		end

		if (Now - self.LastPromptAt) < self.PromptCooldown then
			return
		end

		local Prompt = self:GetTargetPrompt()

		if not Prompt then
			return
		end

		local RootPart = getRootPart()
		local PromptPosition = getPromptPosition(Prompt)

		if RootPart and PromptPosition then
			local Distance = (RootPart.Position - PromptPosition).Magnitude
			local MaxDistance = math.max((Prompt.MaxActivationDistance or 10) - 1, 3)

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
		return table.clone(AvailableTypes)
	end

	function AutoTrainFeature:GetSelectedType()
		return self.SelectedType
	end

	function AutoTrainFeature:SetSelectedType(Value)
		if not table.find(AvailableTypes, Value) then
			return false
		end

		self.SelectedType = Value
		self.CachedPrompt = nil
		self.CachedPromptType = nil
		self.LastPromptRefreshAt = 0
		self.LastKeySignature = nil
		self.LastKeySignatureAt = 0
		return true
	end

	function AutoTrainFeature:SetEnabled(Value)
		local State = Value and true or false

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
				local Message = self.SelectedType == "Bike"
					and "Enabled (Bike) - direct remote active"
					or string.format("Enabled (%s)", self.SelectedType)

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
