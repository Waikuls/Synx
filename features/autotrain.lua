return function(Config)
	local Players = game:GetService("Players")
	local RunService = game:GetService("RunService")
	local LocalPlayer = Players.LocalPlayer
	local Notification = Config and Config.Notification

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
			Aliases = {"bike", "cycling", "cycle"}
		},
		["Squat machine"] = {
			Aliases = {"squat machine", "squat", "leg press"}
		},
		["Treadmill"] = {
			Aliases = {"treadmill", "running machine"}
		}
	}
	local AvailableTypes = {"Bag", "Bar", "Bench", "Bike", "Squat machine", "Treadmill"}
	local KeyCodes = {
		W = Enum.KeyCode.W,
		A = Enum.KeyCode.A,
		S = Enum.KeyCode.S,
		D = Enum.KeyCode.D
	}
	local DigitVirtualKeys = {
		Zero = 0x30,
		One = 0x31,
		Two = 0x32,
		Three = 0x33,
		Four = 0x34,
		Five = 0x35,
		Six = 0x36,
		Seven = 0x37,
		Eight = 0x38,
		Nine = 0x39
	}
	local SpecialVirtualKeys = {
		Space = 0x20,
		Return = 0x0D,
		Backspace = 0x08,
		Tab = 0x09,
		LeftShift = 0xA0,
		RightShift = 0xA1,
		LeftControl = 0xA2,
		RightControl = 0xA3,
		LeftAlt = 0xA4,
		RightAlt = 0xA5
	}
	local BlindMashOrder = {"W", "A", "S", "D"}

	local AutoTrainFeature = {
		Enabled = false,
		SelectedType = "Bike",
		Connection = nil,
		Elapsed = 0,
		LoopInterval = 0.12,
		LastInteractionAt = 0,
		LastTeleportAt = 0,
		LastButtonClickAt = 0,
		LastPromptRefreshAt = 0,
		LastPressedSignature = nil,
		LastPressedAt = 0,
		LastBlindMashAt = 0,
		CachedPrompt = nil,
		CachedPromptType = nil,
		PromptRefreshInterval = 2,
		InteractionCooldown = 0.75,
		TeleportCooldown = 0.5,
		ButtonCooldown = 0.45,
		KeyCooldown = 0.08,
		RepeatPromptCooldown = 0.28,
		BlindMashCooldown = 0.55,
		DesiredStandDistance = 4,
		VerticalOffset = 2.5,
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

	local function containsAlias(Haystack, Aliases)
		if Haystack == "" then
			return false
		end

		for _, Alias in ipairs(Aliases) do
			if string.find(Haystack, Alias, 1, true) then
				return true
			end
		end

		return false
	end

	local function getSelectedAliases(SelectedType)
		local Definition = MachineDefinitions[SelectedType]

		if Definition and type(Definition.Aliases) == "table" and #Definition.Aliases > 0 then
			return Definition.Aliases
		end

		return {normalizeText(SelectedType)}
	end

	local function getPlayerGui()
		return LocalPlayer:FindFirstChildOfClass("PlayerGui")
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

		return Character:FindFirstChild("HumanoidRootPart")
			or Character:FindFirstChild("Torso")
			or Character:FindFirstChild("UpperTorso")
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

		local DirectChild = Stats:FindFirstChild(Name)

		if DirectChild and DirectChild:IsA("ValueBase") then
			return DirectChild.Value
		end

		local AttributeValue = Stats:GetAttribute(Name)

		if AttributeValue ~= nil then
			return AttributeValue
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

			if Lower == "true" or Lower == "yes" or Lower == "active" then
				return true
			end

			if Lower == "false" or Lower == "no" or Lower == "inactive" or Lower == "" then
				return false
			end
		end

		return false
	end

	local function valueToText(Value)
		if Value == nil then
			return ""
		end

		if typeof(Value) == "Instance" then
			return Value.Name
		end

		return tostring(Value)
	end

	local function getTrainingState(SelectedType)
		local Stats = findStatsContainer()
		local RawIsTrainingWithMachine = readStatsValue(Stats, "IsTrainingWithMachine")
		local RawTrainingFlag = readStatsValue(Stats, "Training")
		local IsTrainingWithMachine = valueToBool(RawIsTrainingWithMachine)
		local TrainingFlag = valueToBool(RawTrainingFlag)
		local TrainingMachine = valueToText(readStatsValue(Stats, "TrainingMachine"))
		local MachineText = normalizeText(TrainingMachine)
		local HasExplicitTrainingFlag = RawIsTrainingWithMachine ~= nil or RawTrainingFlag ~= nil
		local IsTraining = IsTrainingWithMachine or TrainingFlag
		local IsSelectedMachine = false

		if not HasExplicitTrainingFlag and MachineText ~= "" then
			IsTraining = true
		end

		if MachineText ~= "" then
			IsSelectedMachine = containsAlias(MachineText, getSelectedAliases(SelectedType))
		end

		return {
			IsTraining = IsTraining,
			IsTrainingWithMachine = IsTrainingWithMachine,
			TrainingMachine = TrainingMachine,
			IsSelectedMachine = IsSelectedMachine
		}
	end

	local function getVirtualInputManager()
		local Success, VirtualInputManager = pcall(game.GetService, game, "VirtualInputManager")

		if Success and VirtualInputManager then
			return VirtualInputManager
		end

		return nil
	end

	local function getVirtualKeyCode(KeyCode)
		if typeof(KeyCode) ~= "EnumItem" then
			return nil
		end

		local Name = KeyCode.Name

		if #Name == 1 then
			local Byte = string.byte(Name)

			if Byte and ((Byte >= 48 and Byte <= 57) or (Byte >= 65 and Byte <= 90)) then
				return Byte
			end
		end

		if DigitVirtualKeys[Name] then
			return DigitVirtualKeys[Name]
		end

		if SpecialVirtualKeys[Name] then
			return SpecialVirtualKeys[Name]
		end

		return nil
	end

	local function sendExecutorKeyTap(KeyCode)
		local VirtualKey = getVirtualKeyCode(KeyCode)

		if not VirtualKey then
			return false
		end

		if type(keypress) == "function" and type(keyrelease) == "function" then
			local Success = pcall(function()
				keypress(VirtualKey)
				task.wait(0.025)
				keyrelease(VirtualKey)
			end)

			if Success then
				return true
			end
		end

		if type(keytap) == "function" then
			local Success = pcall(function()
				keytap(VirtualKey)
			end)

			if Success then
				return true
			end

			Success = pcall(function()
				keytap(KeyCode.Name)
			end)

			if Success then
				return true
			end
		end

		return false
	end

	local function sendKeyTap(KeyCode)
		if not KeyCode then
			return false
		end

		if sendExecutorKeyTap(KeyCode) then
			return true
		end

		local VirtualInputManager = getVirtualInputManager()

		if not VirtualInputManager then
			return false
		end

		local Success = pcall(function()
			VirtualInputManager:SendKeyEvent(true, KeyCode, false, game)
			task.wait(0.025)
			VirtualInputManager:SendKeyEvent(false, KeyCode, false, game)
		end)

		return Success
	end

	local function isGuiVisible(Instance)
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

	local function getTextValue(Instance)
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

	local function findVisibleStartButton()
		local PlayerGui = getPlayerGui()

		if not PlayerGui then
			return nil
		end

		for _, Descendant in ipairs(PlayerGui:GetDescendants()) do
			if Descendant:IsA("TextButton") and isGuiVisible(Descendant) then
				if normalizeText(getTextValue(Descendant)) == "start" then
					return Descendant
				end
			end
		end

		return nil
	end

	local function clickGuiButton(Button)
		if not Button or not Button:IsA("GuiButton") then
			return false
		end

		local Clicked = false

		pcall(function()
			Button:Activate()
			Clicked = true
		end)

		if type(firesignal) == "function" then
			pcall(function()
				firesignal(Button.MouseButton1Down)
				Clicked = true
			end)

			pcall(function()
				firesignal(Button.MouseButton1Up)
				Clicked = true
			end)

			pcall(function()
				firesignal(Button.MouseButton1Click)
				Clicked = true
			end)

			pcall(function()
				firesignal(Button.Activated)
				Clicked = true
			end)
		end

		if Clicked then
			return true
		end

		local Center = getGuiCenter(Button)
		local VirtualInputManager = getVirtualInputManager()

		if Center and VirtualInputManager then
			pcall(function()
				VirtualInputManager:SendMouseButtonEvent(Center.X, Center.Y, 0, true, game, 0)
				VirtualInputManager:SendMouseButtonEvent(Center.X, Center.Y, 0, false, game, 0)
				Clicked = true
			end)
		end

		return Clicked
	end

	local function extractKeyLabel(Instance)
		local Text = getTextValue(Instance)
		local NormalizedText = string.upper(normalizeText(Text))

		if KeyCodes[NormalizedText] then
			return NormalizedText
		end

		if Instance:IsA("GuiObject") then
			local NameText = string.upper(normalizeText(Instance.Name))

			if KeyCodes[NameText] then
				return NameText
			end
		end

		return nil
	end

	local function collectMinigameCandidates()
		local PlayerGui = getPlayerGui()

		if not PlayerGui then
			return {}
		end

		local ScreenCenter, ViewportSize = getScreenCenter()
		local MaxDistance = math.max(ViewportSize.X, ViewportSize.Y) * 0.38
		local Candidates = {}

		for _, Descendant in ipairs(PlayerGui:GetDescendants()) do
			if Descendant:IsA("GuiObject") and isGuiVisible(Descendant) then
				local KeyLabel = extractKeyLabel(Descendant)

				if KeyLabel then
					local Center, Size = getGuiCenter(Descendant)

					if Center and Size and Size.X >= 18 and Size.Y >= 18 then
						local Distance = (Center - ScreenCenter).Magnitude

						if Distance <= MaxDistance then
							local AreaScore = math.min((Size.X * Size.Y) / 40, 300)
							local DistanceScore = math.max(0, 220 - Distance)

							table.insert(Candidates, {
								Key = KeyLabel,
								Score = AreaScore + DistanceScore,
								Signature = string.format(
									"%s:%d:%d:%d:%d",
									KeyLabel,
									math.floor(Center.X + 0.5),
									math.floor(Center.Y + 0.5),
									math.floor(Size.X + 0.5),
									math.floor(Size.Y + 0.5)
								)
							})
						end
					end
				end
			end
		end

		table.sort(Candidates, function(Left, Right)
			return Left.Score > Right.Score
		end)

		return Candidates
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
			return nil
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

	local function getPromptActivationDistance(Prompt)
		if not Prompt then
			return 10
		end

		local Distance = Prompt.MaxActivationDistance

		if typeof(Distance) == "number" and Distance > 0 then
			return Distance
		end

		return 10
	end

	local function moveNearPrompt(Prompt)
		local Character = getCharacter()
		local RootPart = getRootPart()
		local Humanoid = getHumanoid()
		local Position, Part = getPromptPosition(Prompt)

		if not Character or not RootPart or not Humanoid or not Position or not Part then
			return false
		end

		local LookVector = Part.CFrame.LookVector

		if LookVector.Magnitude < 0.1 then
			LookVector = Vector3.new(0, 0, -1)
		end

		local TargetPosition = Position + (LookVector * -AutoTrainFeature.DesiredStandDistance) + Vector3.new(0, AutoTrainFeature.VerticalOffset, 0)
		local TargetCFrame = CFrame.new(TargetPosition, Position)

		pcall(function()
			Character:PivotTo(TargetCFrame)
		end)

		return true
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

		local KeyCode = Prompt.KeyboardKeyCode

		if KeyCode == Enum.KeyCode.Unknown then
			KeyCode = Enum.KeyCode.E
		end

		return sendKeyTap(KeyCode)
	end

	local function tapKeySequence(Keys)
		task.spawn(function()
			for _, Key in ipairs(Keys) do
				sendKeyTap(KeyCodes[Key])
				task.wait(0.03)
			end
		end)
	end

	function AutoTrainFeature:HandleActionMenu(Now)
		if Now - self.LastButtonClickAt < self.ButtonCooldown then
			return false
		end

		local StartButton = findVisibleStartButton()

		if not StartButton then
			return false
		end

		if clickGuiButton(StartButton) then
			self.LastButtonClickAt = Now
			self.LastPressedSignature = nil
			return true
		end

		return false
	end

	function AutoTrainFeature:HandleMinigame(Now)
		if Now - self.LastPressedAt < self.KeyCooldown then
			return false
		end

		local Candidates = collectMinigameCandidates()

		if #Candidates == 0 then
			if Now - self.LastBlindMashAt >= self.BlindMashCooldown then
				self.LastBlindMashAt = Now
				tapKeySequence(BlindMashOrder)
				return true
			end

			return false
		end

		local BestCandidate = Candidates[1]
		local SecondCandidate = Candidates[2]

		if BestCandidate
			and (
				not SecondCandidate
				or (BestCandidate.Score - SecondCandidate.Score) >= 18
			) then
			if BestCandidate.Signature ~= self.LastPressedSignature
				or (Now - self.LastPressedAt) >= self.RepeatPromptCooldown then
				if sendKeyTap(KeyCodes[BestCandidate.Key]) then
					self.LastPressedSignature = BestCandidate.Signature
					self.LastPressedAt = Now
					return true
				end
			end

			return false
		end

		local UniqueKeys = {}
		local SeenKeys = {}

		for Index = 1, math.min(#Candidates, 4) do
			local Key = Candidates[Index].Key

			if not SeenKeys[Key] then
				SeenKeys[Key] = true
				table.insert(UniqueKeys, Key)
			end
		end

		if #UniqueKeys > 0 then
			tapKeySequence(UniqueKeys)
			self.LastPressedSignature = table.concat(UniqueKeys, ",")
			self.LastPressedAt = Now
			return true
		end

		return false
	end

	function AutoTrainFeature:Step()
		if not self.Enabled then
			return
		end

		local Now = os.clock()

		if self:HandleActionMenu(Now) then
			return
		end

		local TrainingState = getTrainingState(self.SelectedType)

		if TrainingState.IsTraining then
			self:HandleMinigame(Now)
			return
		end

		if Now - self.LastInteractionAt < self.InteractionCooldown then
			return
		end

		local Prompt = self:GetTargetPrompt()

		if not Prompt then
			return
		end

		local RootPart = getRootPart()
		local Position = getPromptPosition(Prompt)

		if RootPart and Position then
			local Distance = (RootPart.Position - Position).Magnitude
			local ActivationDistance = math.max(getPromptActivationDistance(Prompt) - 1, 3)

			if Distance > ActivationDistance then
				if Now - self.LastTeleportAt >= self.TeleportCooldown and moveNearPrompt(Prompt) then
					self.LastTeleportAt = Now
					self.LastInteractionAt = Now
				end

				return
			end
		end

		if triggerPrompt(Prompt) then
			self.LastInteractionAt = Now
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
		self.LastPressedSignature = nil
		self.LastPressedAt = 0

		return true
	end

	function AutoTrainFeature:SetEnabled(Value)
		local State = Value and true or false

		if self.Enabled == State then
			return State
		end

		self.Enabled = State
		self.LastInteractionAt = 0
		self.LastTeleportAt = 0
		self.LastButtonClickAt = 0
		self.LastPromptRefreshAt = 0
		self.CachedPrompt = nil
		self.CachedPromptType = nil
		self.LastPressedSignature = nil
		self.LastPressedAt = 0
		self.LastBlindMashAt = 0

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
				Notification:Notify({
					Title = "Auto Train",
					Content = string.format("Enabled (%s)", self.SelectedType),
					Icon = "check-circle"
				})
			end
		elseif Notification then
			Notification:Notify({
				Title = "Auto Train",
				Content = "Disabled",
				Icon = "x-circle"
			})
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
