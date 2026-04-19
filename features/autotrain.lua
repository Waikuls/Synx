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
			Aliases = {"bike", "cycling", "cycle"},
			Remote = {
				Path = {"TrainingSpots", "Bike", "Radio", "Remote"},
				StartAction = "Start",
				StartPayload = {
					Macro = false
				},
				PressAction = "PressKey",
				PressKeyField = "Key",
				LeaveAction = "Leave"
			}
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
		ObservedContext = {
			Name = nil,
			Key = nil,
			StartButton = nil
		},
		RemoteCapture = nil,
		RemoteHookAvailable = false,
		RemoteRecords = {
			Start = {},
			Prompt = {
				W = {},
				A = {},
				S = {},
				D = {}
			},
			GenericPrompt = {}
		},
		RemoteReplayCooldown = 0.08,
		LastRemoteReplayAt = 0,
		LastRemoteNotificationAt = 0,
		LearnedContexts = {}
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

	local function countAliases(Haystack, Aliases)
		if Haystack == "" then
			return 0
		end

		local Count = 0

		for _, Alias in ipairs(Aliases) do
			if string.find(Haystack, Alias, 1, true) then
				Count = Count + 1
			end
		end

		return Count
	end

	local function packArguments(...)
		return table.pack(...)
	end

	local function cloneValue(Value, Depth, Seen)
		Depth = Depth or 0
		Seen = Seen or {}

		if Depth > 6 then
			return Value
		end

		if typeof(Value) ~= "table" then
			return Value
		end

		if Seen[Value] then
			return Seen[Value]
		end

		local Copy = {}
		Seen[Value] = Copy

		for Key, Entry in pairs(Value) do
			Copy[cloneValue(Key, Depth + 1, Seen)] = cloneValue(Entry, Depth + 1, Seen)
		end

		local Metatable = getmetatable(Value)

		if type(Metatable) == "table" then
			setmetatable(Copy, Metatable)
		end

		return Copy
	end

	local function clonePackedArguments(Arguments)
		if type(Arguments) ~= "table" then
			return packArguments()
		end

		local Copy = {
			n = Arguments.n or #Arguments
		}

		for Index = 1, Copy.n do
			Copy[Index] = cloneValue(Arguments[Index])
		end

		return Copy
	end

	local function isRemoteLike(Instance)
		return typeof(Instance) == "Instance"
			and Instance.Parent
			and (
				Instance:IsA("RemoteEvent")
				or Instance:IsA("RemoteFunction")
				or Instance:IsA("UnreliableRemoteEvent")
			)
	end

	local function getInstancePath(Instance)
		if not Instance then
			return "nil"
		end

		local Success, Value = pcall(function()
			return Instance:GetFullName()
		end)

		if Success and type(Value) == "string" and Value ~= "" then
			return Value
		end

		return tostring(Instance)
	end

	local function collectArgumentTokens(Value, Tokens, Depth, Seen)
		Depth = Depth or 0
		Seen = Seen or {}

		if #Tokens >= 12 or Depth > 3 then
			return
		end

		local ValueType = typeof(Value)

		if ValueType == "string" then
			local Normalized = normalizeText(Value)

			if Normalized ~= "" then
				table.insert(Tokens, Normalized)
			end

			return
		end

		if ValueType == "EnumItem" then
			table.insert(Tokens, normalizeText(Value.Name))
			return
		end

		if ValueType == "Instance" then
			table.insert(Tokens, normalizeText(Value.Name))
			return
		end

		if ValueType ~= "table" or Seen[Value] then
			return
		end

		Seen[Value] = true

		for Key, Entry in pairs(Value) do
			collectArgumentTokens(Key, Tokens, Depth + 1, Seen)
			collectArgumentTokens(Entry, Tokens, Depth + 1, Seen)

			if #Tokens >= 12 then
				return
			end
		end
	end

	local function getRemoteCaptureText(Remote, Arguments)
		local Tokens = {
			normalizeText(Remote and Remote.Name or ""),
			normalizeText(getInstancePath(Remote))
		}

		for Index = 1, (Arguments and Arguments.n or 0) do
			collectArgumentTokens(Arguments[Index], Tokens, 0, {})
		end

		return table.concat(Tokens, " ")
	end

	local function inferKeyFromValue(Value, Depth, Seen)
		Depth = Depth or 0
		Seen = Seen or {}

		if Depth > 4 then
			return nil
		end

		local ValueType = typeof(Value)

		if ValueType == "EnumItem" and Value.EnumType == Enum.KeyCode and KeyCodes[Value.Name] then
			return Value.Name
		end

		if ValueType == "string" then
			local Normalized = string.upper(normalizeText(Value))

			if KeyCodes[Normalized] then
				return Normalized
			end

			for Key in pairs(KeyCodes) do
				if string.find(Normalized, "KEYCODE." .. Key, 1, true)
					or string.find(Normalized, " " .. Key .. " ", 1, true)
					or Normalized == ("PRESS" .. Key)
					or Normalized == ("INPUT" .. Key) then
					return Key
				end
			end

			return nil
		end

		if ValueType ~= "table" or Seen[Value] then
			return nil
		end

		Seen[Value] = true

		for Key, Entry in pairs(Value) do
			local FoundKey = inferKeyFromValue(Key, Depth + 1, Seen) or inferKeyFromValue(Entry, Depth + 1, Seen)

			if FoundKey then
				return FoundKey
			end
		end

		return nil
	end

	local function inferKeyFromArguments(Arguments)
		if type(Arguments) ~= "table" then
			return nil
		end

		for Index = 1, (Arguments.n or #Arguments) do
			local FoundKey = inferKeyFromValue(Arguments[Index], 0, {})

			if FoundKey then
				return FoundKey
			end
		end

		return nil
	end

	local function replaceKeyValue(Value, FromKey, ToKey, Depth, Seen)
		Depth = Depth or 0
		Seen = Seen or {}

		if Depth > 6 then
			return Value
		end

		local ValueType = typeof(Value)

		if ValueType == "EnumItem"
			and Value.EnumType == Enum.KeyCode
			and Value.Name == FromKey
			and KeyCodes[ToKey] then
			return KeyCodes[ToKey]
		end

		if ValueType == "string" then
			if Value == FromKey then
				return ToKey
			end

			if string.upper(Value) == FromKey then
				return ToKey
			end

			if string.lower(Value) == string.lower(FromKey) then
				return string.lower(ToKey)
			end

			return Value
		end

		if ValueType ~= "table" or Seen[Value] then
			return Value
		end

		Seen[Value] = true
		local Copy = {}

		for Key, Entry in pairs(Value) do
			Copy[replaceKeyValue(Key, FromKey, ToKey, Depth + 1, Seen)] = replaceKeyValue(Entry, FromKey, ToKey, Depth + 1, Seen)
		end

		return Copy
	end

	local function replacePackedKey(Arguments, FromKey, ToKey)
		if not FromKey or not ToKey or FromKey == ToKey or type(Arguments) ~= "table" then
			return Arguments
		end

		local Copy = {
			n = Arguments.n or #Arguments
		}

		for Index = 1, Copy.n do
			Copy[Index] = replaceKeyValue(Arguments[Index], FromKey, ToKey, 0, {})
		end

		return Copy
	end

	local function getGlobalRemoteCapture()
		local Environment = type(getgenv) == "function" and getgenv() or _G

		if type(Environment.__KELVAutoTrainRemoteCapture) ~= "table" then
			Environment.__KELVAutoTrainRemoteCapture = {
				Installed = false,
				Available = false,
				Consumer = nil,
				Replaying = false,
				ForwardMode = "with_self",
				Version = 2
			}
		end

		local CaptureState = Environment.__KELVAutoTrainRemoteCapture

		if CaptureState.ForwardMode ~= "with_self" and CaptureState.ForwardMode ~= "without_self" then
			CaptureState.ForwardMode = "with_self"
		end

		if type(CaptureState.Version) ~= "number" then
			CaptureState.Version = 0
		end

		return CaptureState
	end

	local function installRemoteCaptureHook()
		local CaptureState = getGlobalRemoteCapture()

		if CaptureState.Installed then
			if CaptureState.Version < 2 then
				CaptureState.Available = false
				CaptureState.Consumer = nil
				CaptureState.RequiresRejoin = true
			end

			return CaptureState
		end

		CaptureState.Installed = true

		if type(hookmetamethod) ~= "function" or type(getnamecallmethod) ~= "function" then
			return CaptureState
		end

		local ClosureFactory = type(newcclosure) == "function" and newcclosure or function(Callback)
			return Callback
		end

		local function forwardNamecall(OriginalNamecall, Self, ...)
			if CaptureState.ForwardMode == "without_self" then
				return OriginalNamecall(...)
			end

			return OriginalNamecall(Self, ...)
		end

		local OriginalNamecall
		local Success = pcall(function()
			OriginalNamecall = hookmetamethod(game, "__namecall", ClosureFactory(function(Self, ...)
				local Method = getnamecallmethod()
				local Consumer = CaptureState.Consumer

				if Consumer
					and not CaptureState.Replaying
					and isRemoteLike(Self)
					and (Method == "FireServer" or Method == "InvokeServer") then
					local ShouldSkip = false

					if type(checkcaller) == "function" then
						local CheckSuccess, Value = pcall(checkcaller)

						if CheckSuccess and Value then
							ShouldSkip = true
						end
					end

					if not ShouldSkip then
						local Arguments = packArguments(...)
						pcall(Consumer, Self, Method, Arguments)
					end
				end

				return forwardNamecall(OriginalNamecall, Self, ...)
			end))
		end)

		CaptureState.Available = Success and type(OriginalNamecall) == "function"
		CaptureState.Version = 2
		CaptureState.RequiresRejoin = false

		if CaptureState.Available then
			local function canForward(Mode)
				CaptureState.ForwardMode = Mode

				return pcall(function()
					return workspace:GetChildren()
				end)
			end

			local ForwardWithSelf = canForward("with_self")
			local ForwardWithoutSelf = canForward("without_self")

			if ForwardWithSelf then
				CaptureState.ForwardMode = "with_self"
			elseif ForwardWithoutSelf then
				CaptureState.ForwardMode = "without_self"
			else
				CaptureState.Available = false
				CaptureState.Consumer = nil
				CaptureState.ForwardMode = "with_self"
			end
		end

		return CaptureState
	end

	local function getSelectedAliases(SelectedType)
		local Definition = MachineDefinitions[SelectedType]

		if Definition and type(Definition.Aliases) == "table" and #Definition.Aliases > 0 then
			return Definition.Aliases
		end

		return {normalizeText(SelectedType)}
	end

	local function getMachineDefinition(SelectedType)
		return MachineDefinitions[SelectedType]
	end

	local function getExplicitRemoteConfig(SelectedType)
		local Definition = getMachineDefinition(SelectedType)

		if type(Definition) ~= "table" or type(Definition.Remote) ~= "table" then
			return nil
		end

		return Definition.Remote
	end

	local function hasExplicitRemoteSupport(SelectedType)
		return getExplicitRemoteConfig(SelectedType) ~= nil
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

	local function isVisibleGuiButton(Instance)
		return Instance
			and Instance:IsA("GuiButton")
			and isGuiVisible(Instance)
	end

	local function findClickableButton(Instance)
		local Current = Instance
		local Depth = 0

		while Current and Depth < 8 do
			if isVisibleGuiButton(Current) then
				return Current
			end

			Current = Current.Parent
			Depth = Depth + 1
		end

		return nil
	end

	local function getButtonLabelText(Button)
		if not isVisibleGuiButton(Button) then
			return nil
		end

		local DirectText = normalizeText(getTextValue(Button))

		if DirectText ~= "" then
			return DirectText
		end

		for _, Descendant in ipairs(Button:GetDescendants()) do
			if isGuiVisible(Descendant) then
				local Text = normalizeText(getTextValue(Descendant))

				if Text ~= "" then
					return Text
				end
			end
		end

		return nil
	end

	local function findVisibleStartButton()
		local PlayerGui = getPlayerGui()
		local BestButton = nil
		local BestScore = math.huge

		if not PlayerGui then
			return nil
		end

		for _, Descendant in ipairs(PlayerGui:GetDescendants()) do
			if isVisibleGuiButton(Descendant) then
				local ButtonText = getButtonLabelText(Descendant)

				if ButtonText == "start" then
					local Center, Size = getGuiCenter(Descendant)
					local Score = 999999

					if Center and Size then
						Score = math.abs(Center.Y) + math.abs(Center.X) - (Size.X * Size.Y * 0.01)
					end

					if Score < BestScore then
						BestScore = Score
						BestButton = Descendant
					end
				end
			end
		end

		return BestButton
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

	local function resolveCandidateButton(Instance)
		local Button = findClickableButton(Instance)

		if Button then
			return Button
		end

		if Instance and Instance:IsA("GuiObject") then
			for _, Descendant in ipairs(Instance:GetDescendants()) do
				Button = findClickableButton(Descendant)

				if Button then
					return Button
				end
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
					local Button = resolveCandidateButton(Descendant)

					if Center and Size and Size.X >= 18 and Size.Y >= 18 then
						local Distance = (Center - ScreenCenter).Magnitude

						if Distance <= MaxDistance then
							local AreaScore = math.min((Size.X * Size.Y) / 40, 300)
							local DistanceScore = math.max(0, 220 - Distance)
							local ButtonBonus = Button and 160 or 0
							local Signature = string.format(
								"%s:%d:%d:%d:%d",
								KeyLabel,
								math.floor(Center.X + 0.5),
								math.floor(Center.Y + 0.5),
								math.floor(Size.X + 0.5),
								math.floor(Size.Y + 0.5)
							)

							if Button then
								Signature = Signature .. ":" .. Button:GetFullName()
							end

							table.insert(Candidates, {
								Key = KeyLabel,
								Button = Button,
								Score = AreaScore + DistanceScore + ButtonBonus,
								Signature = Signature
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

	local function getLikelyVisibleKey(Candidates)
		local BestCandidate = Candidates and Candidates[1]
		local SecondCandidate = Candidates and Candidates[2]

		if BestCandidate
			and (
				not SecondCandidate
				or (BestCandidate.Score - SecondCandidate.Score) >= 18
			) then
			return BestCandidate.Key
		end

		return nil
	end

	function AutoTrainFeature:RefreshObservedContext()
		local StartButton = findVisibleStartButton()

		if StartButton then
			self.ObservedContext = {
				Name = "start",
				Key = nil,
				StartButton = StartButton
			}

			return self.ObservedContext
		end

		local Candidates = collectMinigameCandidates()

		if #Candidates > 0 then
			self.ObservedContext = {
				Name = "prompt",
				Key = getLikelyVisibleKey(Candidates),
				StartButton = nil
			}

			return self.ObservedContext
		end

		local TrainingState = getTrainingState(self.SelectedType)

		if TrainingState.IsTraining then
			self.ObservedContext = {
				Name = "prompt",
				Key = nil,
				StartButton = nil
			}

			return self.ObservedContext
		end

		self.ObservedContext = {
			Name = nil,
			Key = nil,
			StartButton = nil
		}

		return self.ObservedContext
	end

	function AutoTrainFeature:NotifyRemoteLearned(ContextLabel)
		if not Notification then
			return
		end

		local Now = os.clock()

		if self.LearnedContexts[ContextLabel]
			or (Now - self.LastRemoteNotificationAt) < 0.8 then
			return
		end

		self.LearnedContexts[ContextLabel] = true
		self.LastRemoteNotificationAt = Now

		Notification:Notify({
			Title = "Auto Train",
			Content = string.format("Learned remote for %s", ContextLabel),
			Icon = "radio"
		})
	end

	function AutoTrainFeature:BuildRemoteSignature(Remote, Method, Arguments, Key)
		local Tokens = {
			getInstancePath(Remote),
			tostring(Method),
			inferKeyFromArguments(Arguments) or "",
			Key or "",
			getRemoteCaptureText(Remote, Arguments)
		}

		return table.concat(Tokens, "|")
	end

	function AutoTrainFeature:ClassifyCapturedRemote(Remote, Arguments)
		local Context = self.ObservedContext or {}
		local InferredKey = inferKeyFromArguments(Arguments)
		local CaptureText = getRemoteCaptureText(Remote, Arguments)
		local RelevanceScore = 0

		RelevanceScore = RelevanceScore + countAliases(CaptureText, {"train", "training", "workout", "gym", "exercise", "machine", "prompt", "input", "start"})
		RelevanceScore = RelevanceScore + countAliases(CaptureText, getSelectedAliases(self.SelectedType))

		if Context.Name == "start" then
			if string.find(CaptureText, "start", 1, true) or RelevanceScore > 0 then
				return "start", nil
			end

			return nil, nil
		end

		if Context.Name == "prompt" then
			if InferredKey then
				return "prompt", InferredKey
			end

			if Context.Key then
				return "prompt", Context.Key
			end

			if RelevanceScore > 0 then
				return "prompt", nil
			end
		end

		return nil, nil
	end

	function AutoTrainFeature:StoreRemoteRecord(ContextName, Key, Remote, Method, Arguments)
		local TargetList
		local ContextLabel

		if ContextName == "start" then
			TargetList = self.RemoteRecords.Start
			ContextLabel = "Start"
		elseif ContextName == "prompt" and Key and self.RemoteRecords.Prompt[Key] then
			TargetList = self.RemoteRecords.Prompt[Key]
			ContextLabel = "Key " .. Key
		elseif ContextName == "prompt" then
			TargetList = self.RemoteRecords.GenericPrompt
			ContextLabel = "Generic prompt"
		else
			return false
		end

		local Signature = self:BuildRemoteSignature(Remote, Method, Arguments, Key)

		for _, Record in ipairs(TargetList) do
			if Record.Signature == Signature then
				Record.Remote = Remote
				Record.Method = Method
				Record.Args = clonePackedArguments(Arguments)
				Record.Key = Key
				Record.CapturedAt = os.clock()
				Record.Hits = (Record.Hits or 1) + 1
				return false
			end
		end

		table.insert(TargetList, 1, {
			Signature = Signature,
			Remote = Remote,
			Method = Method,
			Args = clonePackedArguments(Arguments),
			Key = Key,
			CapturedAt = os.clock(),
			Hits = 1
		})

		while #TargetList > 6 do
			table.remove(TargetList)
		end

		self:NotifyRemoteLearned(ContextLabel)
		return true
	end

	function AutoTrainFeature:OnRemoteCalled(Remote, Method, Arguments)
		if not self.Enabled then
			return
		end

		local ContextName, Key = self:ClassifyCapturedRemote(Remote, Arguments)

		if not ContextName then
			return
		end

		self:StoreRemoteRecord(ContextName, Key, Remote, Method, Arguments)
	end

	function AutoTrainFeature:RegisterRemoteCapture()
		local CaptureState = installRemoteCaptureHook()

		self.RemoteCapture = CaptureState
		self.RemoteHookAvailable = CaptureState.Available == true

		if self.RemoteHookAvailable then
			CaptureState.Consumer = function(Remote, Method, Arguments)
				self:OnRemoteCalled(Remote, Method, Arguments)
			end
		else
			CaptureState.Consumer = nil
		end
	end

	function AutoTrainFeature:InvokeRecordedRemote(Record, DesiredKey)
		if type(Record) ~= "table" or not isRemoteLike(Record.Remote) then
			return false
		end

		local Arguments = clonePackedArguments(Record.Args)

		if DesiredKey and Record.Key then
			Arguments = replacePackedKey(Arguments, Record.Key, DesiredKey)
		end

		local CaptureState = self.RemoteCapture or getGlobalRemoteCapture()

		CaptureState.Replaying = true

		local Success

		if Record.Method == "InvokeServer" then
			Success = pcall(function()
				Record.Remote:InvokeServer(table.unpack(Arguments, 1, Arguments.n))
			end)
		else
			Success = pcall(function()
				Record.Remote:FireServer(table.unpack(Arguments, 1, Arguments.n))
			end)
		end

		CaptureState.Replaying = false

		if Success then
			self.LastRemoteReplayAt = os.clock()
		end

		return Success
	end

	function AutoTrainFeature:ReplayRemoteList(Records, DesiredKey, Now)
		if type(Records) ~= "table" or #Records == 0 then
			return false
		end

		if (Now or os.clock()) - self.LastRemoteReplayAt < self.RemoteReplayCooldown then
			return false
		end

		for _, Record in ipairs(Records) do
			if self:InvokeRecordedRemote(Record, DesiredKey) then
				return true
			end
		end

		return false
	end

	function AutoTrainFeature:TryReplayStartRemote(Now)
		return self:ReplayRemoteList(self.RemoteRecords.Start, nil, Now)
	end

	function AutoTrainFeature:TryReplayPromptRemote(Key, Now)
		if Key and self:ReplayRemoteList(self.RemoteRecords.Prompt[Key], Key, Now) then
			return true
		end

		return self:ReplayRemoteList(self.RemoteRecords.GenericPrompt, Key, Now)
	end

	local function resolveRemotePath(PathParts)
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

		if isRemoteLike(Current) then
			return Current
		end

		return nil
	end

	local function buildExplicitRemoteArguments(RemoteConfig, ActionName, Key)
		if type(RemoteConfig) ~= "table" or type(ActionName) ~= "string" then
			return nil
		end

		if ActionName == "start" then
			return packArguments(
				RemoteConfig.StartAction or "Start",
				cloneValue(RemoteConfig.StartPayload or {Macro = false})
			)
		end

		if ActionName == "press" and type(Key) == "string" and KeyCodes[Key] then
			local KeyField = RemoteConfig.PressKeyField or "Key"

			return packArguments(
				RemoteConfig.PressAction or "PressKey",
				{
					[KeyField] = Key
				}
			)
		end

		if ActionName == "leave" then
			return packArguments(RemoteConfig.LeaveAction or "Leave")
		end

		return nil
	end

	function AutoTrainFeature:InvokeExplicitRemote(ActionName, Key, Now)
		local RemoteConfig = getExplicitRemoteConfig(self.SelectedType)

		if not RemoteConfig then
			return false
		end

		if (Now or os.clock()) - self.LastRemoteReplayAt < self.RemoteReplayCooldown then
			return false
		end

		local Remote = resolveRemotePath(RemoteConfig.Path)
		local Arguments = buildExplicitRemoteArguments(RemoteConfig, ActionName, Key)

		if not Remote or not Arguments then
			return false
		end

		local Success = pcall(function()
			Remote:FireServer(table.unpack(Arguments, 1, Arguments.n))
		end)

		if Success then
			self.LastRemoteReplayAt = os.clock()
		end

		return Success
	end

	function AutoTrainFeature:TryDirectStartRemote(Now)
		return self:InvokeExplicitRemote("start", nil, Now)
	end

	function AutoTrainFeature:TryDirectPromptRemote(Key, Now)
		if not Key then
			return false
		end

		return self:InvokeExplicitRemote("press", Key, Now)
	end

	function AutoTrainFeature:TryDirectLeaveRemote(Now)
		return self:InvokeExplicitRemote("leave", nil, Now)
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

		if self:TryDirectStartRemote(Now) then
			self.LastButtonClickAt = Now
			self.LastPressedSignature = nil
			return true
		end

		if self:TryReplayStartRemote(Now) then
			self.LastButtonClickAt = Now
			self.LastPressedSignature = nil
			return true
		end

		local StartButton = (self.ObservedContext and self.ObservedContext.StartButton) or findVisibleStartButton()

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
			if self:TryDirectPromptRemote(self.ObservedContext and self.ObservedContext.Key or nil, Now) then
				self.LastPressedSignature = "direct-generic"
				self.LastPressedAt = Now
				return true
			end

			if self:TryReplayPromptRemote(nil, Now) then
				self.LastPressedSignature = "remote-generic"
				self.LastPressedAt = Now
				return true
			end

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
				local Triggered = false

				Triggered = self:TryDirectPromptRemote(BestCandidate.Key, Now)
				Triggered = Triggered or self:TryReplayPromptRemote(BestCandidate.Key, Now)

				if BestCandidate.Button then
					Triggered = Triggered or clickGuiButton(BestCandidate.Button)
				end

				if not Triggered then
					Triggered = sendKeyTap(KeyCodes[BestCandidate.Key])
				end

				if Triggered then
					self.LastPressedSignature = BestCandidate.Signature
					self.LastPressedAt = Now
					return true
				end
			end

			return false
		end

		local UniqueKeys = {}
		local SeenKeys = {}
		local UniqueButtons = {}
		local SeenButtons = {}

		for Index = 1, math.min(#Candidates, 4) do
			local Candidate = Candidates[Index]
			local Key = Candidate.Key

			if not SeenKeys[Key] then
				SeenKeys[Key] = true
				table.insert(UniqueKeys, Key)
			end

			local Button = Candidate.Button

			if Button and not SeenButtons[Button] then
				SeenButtons[Button] = true
				table.insert(UniqueButtons, Button)
			end
		end

		for _, Button in ipairs(UniqueButtons) do
			clickGuiButton(Button)
		end

		if self:TryDirectPromptRemote(getLikelyVisibleKey(Candidates), Now) then
			self.LastPressedSignature = "direct-multi"
			self.LastPressedAt = Now
			return true
		end

		if self:TryReplayPromptRemote(getLikelyVisibleKey(Candidates), Now) then
			self.LastPressedSignature = "remote-multi"
			self.LastPressedAt = Now
			return true
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
		self:RefreshObservedContext()

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

		if self.SelectedType ~= Value then
			self.RemoteRecords = {
				Start = {},
				Prompt = {
					W = {},
					A = {},
					S = {},
					D = {}
				},
				GenericPrompt = {}
			}
			self.LearnedContexts = {}
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
		self.ObservedContext = {
			Name = nil,
			Key = nil,
			StartButton = nil
		}

		if self.Connection then
			self.Connection:Disconnect()
			self.Connection = nil
		end

		if State then
			if hasExplicitRemoteSupport(self.SelectedType) then
				self.RemoteCapture = nil
				self.RemoteHookAvailable = false
			else
				self:RegisterRemoteCapture()
			end

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
				local EnableMessage

				if hasExplicitRemoteSupport(self.SelectedType) then
					EnableMessage = string.format("Enabled (%s) - direct remote active", self.SelectedType)
				elseif self.RemoteCapture and self.RemoteCapture.RequiresRejoin then
					EnableMessage = string.format("Enabled (%s) - rejoin required to clear old remote hook", self.SelectedType)
				elseif self.RemoteHookAvailable then
					EnableMessage = string.format("Enabled (%s) - remote learn active", self.SelectedType)
				else
					EnableMessage = string.format("Enabled (%s) - input fallback only", self.SelectedType)
				end

				Notification:Notify({
					Title = "Auto Train",
					Content = EnableMessage,
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

		if not State then
			local TrainingState = getTrainingState(self.SelectedType)

			if TrainingState.IsTraining and hasExplicitRemoteSupport(self.SelectedType) then
				self:TryDirectLeaveRemote(os.clock())
			end
		end

		return State
	end

	function AutoTrainFeature:Destroy()
		self:SetEnabled(false)
		self.CachedPrompt = nil
		self.CachedPromptType = nil

		if self.RemoteCapture and self.RemoteCapture.Consumer then
			self.RemoteCapture.Consumer = nil
		end
	end

	return AutoTrainFeature
end
