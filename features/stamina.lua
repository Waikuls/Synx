return function(Config)
	local Players = game:GetService("Players")
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local RunService = game:GetService("RunService")
	local LocalPlayer = Players.LocalPlayer
	local Notification = Config and Config.Notification

	local CaptureProfiles = {
		Free = {
			BaselineDuration = 0.75,
			ActiveDuration = 5.5
		},
		Run = {
			BaselineDuration = 0.75,
			ActiveDuration = 6
		},
		Dash = {
			BaselineDuration = 0.6,
			ActiveDuration = 5.5
		},
		Attack = {
			BaselineDuration = 0.6,
			ActiveDuration = 5.5
		}
	}

	local ExactAliases = {
		Current = {
			"Stamina",
			"StaminaInStat",
			"CurrentStamina",
			"StaminaValue",
			"Eevee",
			"BodyFatigue",
			"BodyFatique",
			"DashStamina",
			"SprintStamina",
			"RunStamina",
			"CombatStamina",
			"AttackStamina"
		},
		Max = {
			"MaxStamina",
			"MaximumStamina",
			"StaminaMax",
			"MaxDashStamina",
			"MaxSprintStamina",
			"MaxRunStamina",
			"MaxCombatStamina",
			"MaxAttackStamina"
		},
		Flags = {
			"NoStaminaCost",
			"NoCooldown",
			"NoEeveeDeplete",
			"CanUseStamina",
			"HasStamina",
			"EnoughStamina",
			"CanDash",
			"CanSprint",
			"CanRun",
			"CanAttack",
			"Sleeping"
		},
		Spend = {
			"StaminaCost",
			"StaminaDrain",
			"StaminaDeplete",
			"StaminaCooldown",
			"LowStamina",
			"OutOfStamina",
			"StaminaLocked",
			"Exhaustion",
			"Exhausted",
			"Fatigue",
			"Fatigued",
			"Breath",
			"OutOfBreath",
			"BreathLocked",
			"ExhaustionLevel",
			"FatigueLevel",
			"EeveeDeplete",
			"DashCost",
			"SprintCost",
			"RunCost",
			"CombatCost",
			"AttackCost",
			"DashCooldown",
			"SprintCooldown",
			"RunCooldown",
			"CombatCooldown",
			"AttackCooldown"
		}
	}

	local function createLookup(Aliases)
		local Lookup = {}

		for _, Name in ipairs(Aliases) do
			Lookup[string.lower(Name)] = true
		end

		return Lookup
	end

	local Lookups = {
		Current = createLookup(ExactAliases.Current),
		Max = createLookup(ExactAliases.Max),
		Flags = createLookup(ExactAliases.Flags),
		Spend = createLookup(ExactAliases.Spend)
	}

	local ScopeCache = setmetatable({}, {__mode = "k"})
	local InstanceKeyCache = setmetatable({}, {__mode = "k"})
	local NextInstanceKeyId = 0

	local StaminaFeature = {
		Enabled = false,
		DebugEnabled = false,
		DebugProfile = "Run",
		HeartbeatConnection = nil,
		CharacterAddedConnection = nil,
		HandleSignals = {},
		StepInterval = 0.03,
		ResolveInterval = 2.5,
		GcResolveInterval = 15,
		LastResolveAt = 0,
		LastGcResolveAt = 0,
		LastStepAt = 0,
		LastWarnAt = 0,
		WarnCooldown = 5,
		LastDebugNotifyAt = 0,
		DebugNotifyCooldown = 8,
		LastFailureCaptureAt = 0,
		FailureCaptureCooldown = 8,
		AutoFailureCapture = true,
		LastRecoveryAt = 0,
		RecoveryCooldown = 4,
		LastKnownTargets = {},
		LastKnownMaxTargets = {},
		LastFailureReason = "idle",
		LastSupportIssue = "",
		LastStatusSummary = {},
		LastActionProfile = "Free",
		LastEffectiveLogicAt = 0,
		VerificationState = "idle",
		LastStatusConsoleLine = "",
		StepBusy = false,
		StepQueued = false,
		GcResolveQueued = false,
		DropEventCount = 0,
		DropThreshold = 1,
		DropEventLimit = 3,
		LastStepErrorAt = 0,
		StepErrorCooldown = 2,
		DirectStatsHighWater = {},
		Handles = {
			Current = {},
			Max = {},
			Flags = {},
			Spend = {}
		},
		OriginalFlagValues = {},
		OriginalSpendValues = {},
		HookControllerId = nil,
		RemoteBlockingEnabled = false,
		NamecallHookEnabled = false,
		AttributeNamecallHookEnabled = false,
		RemoteNamecallHookEnabled = false,
		CandidateRegistry = {},
		CandidateOrder = {},
		RemoteCandidates = {},
		RemoteCandidateOrder = {},
		CaptureSession = nil,
		LastCaptureSummary = {}
	}

	local function clearScopeCache()
		for Key in pairs(ScopeCache) do
			ScopeCache[Key] = nil
		end
	end

	local function toNumber(Value)
		if typeof(Value) == "number" then
			return Value
		end

		if typeof(Value) == "string" then
			return tonumber(Value)
		end

		return nil
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

	local function summarizeValue(Value)
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

		if ValueType == "Instance" then
			return Value.Name
		end

		local Result = tostring(Value)

		if #Result > 42 then
			return string.sub(Result, 1, 39) .. "..."
		end

		return Result
	end

	local function valuesEquivalent(Left, Right)
		if Left == Right then
			return true
		end

		if typeof(Left) == "number" and typeof(Right) == "number" then
			return math.abs(Left - Right) <= 0.001
		end

		return tostring(Left) == tostring(Right)
	end

	local function isLocalPlayerFolder(Instance)
		local Current = Instance

		while Current do
			if Current == LocalPlayer then
				return true
			end

			local Name = Current.Name

			if Name == LocalPlayer.Name or Name == tostring(LocalPlayer.UserId) then
				return true
			end

			Current = Current.Parent
		end

		return false
	end

	local function findEntity()
		local Entities = workspace:FindFirstChild("Entities")

		if not Entities then
			return nil
		end

		return Entities:FindFirstChild(LocalPlayer.Name)
	end

	local function findMainScript()
		local Entity = findEntity()

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

	local function isInstanceInHierarchy(Instance, Root)
		if not Instance or not Root then
			return false
		end

		if Instance == Root then
			return true
		end

		return Instance:IsDescendantOf(Root)
	end

	local function isLocalRelatedInstance(Instance)
		if not Instance then
			return false
		end

		local Cached = ScopeCache[Instance]

		if Cached ~= nil then
			return Cached
		end

		local Character = LocalPlayer.Character
		local PlayerScripts = LocalPlayer:FindFirstChild("PlayerScripts")
		local Entity = findEntity()
		local MainScript = findMainScript()
		local Result = Instance == LocalPlayer
			or isInstanceInHierarchy(Instance, Character)
			or isInstanceInHierarchy(Instance, PlayerScripts)
			or isInstanceInHierarchy(Instance, Entity)
			or isInstanceInHierarchy(Instance, MainScript)
			or isLocalPlayerFolder(Instance)

		ScopeCache[Instance] = Result

		return Result
	end

	local function isPlayerGuiRelatedInstance(Instance)
		if not Instance then
			return false
		end

		local PlayerGui = LocalPlayer:FindFirstChild("PlayerGui")

		return isInstanceInHierarchy(Instance, PlayerGui)
	end

	local function shouldHookInstance(Instance)
		return isLocalRelatedInstance(Instance)
			and not isPlayerGuiRelatedInstance(Instance)
	end

	local function buildSearchRoots(IncludeBroadRoots)
		local Character = LocalPlayer.Character
		local Entity = findEntity()
		local MainScript = findMainScript()
		local MainScriptStats = MainScript and MainScript:FindFirstChild("Stats")
		local PlayerScripts = LocalPlayer:FindFirstChild("PlayerScripts")
		local Roots = {}
		local Seen = {}

		local function addRoot(Root)
			if not Root or Seen[Root] then
				return
			end

			Seen[Root] = true
			table.insert(Roots, Root)
		end

		addRoot(MainScriptStats)
		addRoot(MainScript)
		addRoot(Entity)
		addRoot(LocalPlayer:FindFirstChild("Stats"))
		addRoot(Character and Character:FindFirstChild("Stats"))
		addRoot(LocalPlayer:FindFirstChild("Data"))
		addRoot(Character and Character:FindFirstChild("Data"))

		for _, RootName in ipairs({"PlayerData", "Data", "Stats"}) do
			local Root = ReplicatedStorage:FindFirstChild(RootName)

			if Root then
				addRoot(Root:FindFirstChild(LocalPlayer.Name))
				addRoot(Root:FindFirstChild(tostring(LocalPlayer.UserId)))

				local PlayersFolder = Root:FindFirstChild("Players")

				if PlayersFolder then
					addRoot(PlayersFolder:FindFirstChild(LocalPlayer.Name))
					addRoot(PlayersFolder:FindFirstChild(tostring(LocalPlayer.UserId)))
				end
			end
		end

		if IncludeBroadRoots then
			addRoot(PlayerScripts)
			addRoot(Character)
			addRoot(LocalPlayer)
		end

		return Roots
	end

	local function getFamily(NameLower)
		if string.find(NameLower, "dash", 1, true) then
			return "dash"
		end

		if string.find(NameLower, "sprint", 1, true) then
			return "sprint"
		end

		if string.find(NameLower, "run", 1, true) then
			return "run"
		end

		if string.find(NameLower, "combat", 1, true) then
			return "combat"
		end

		if string.find(NameLower, "attack", 1, true) then
			return "attack"
		end

		return "base"
	end

	local function containsFlag(NameLower)
		return string.sub(NameLower, 1, 2) == "no"
			or string.sub(NameLower, 1, 3) == "can"
			or string.sub(NameLower, 1, 3) == "has"
			or string.sub(NameLower, 1, 6) == "enough"
	end

	local function containsSpend(NameLower)
		return string.find(NameLower, "cost", 1, true) ~= nil
			or string.find(NameLower, "drain", 1, true) ~= nil
			or string.find(NameLower, "deplete", 1, true) ~= nil
			or string.find(NameLower, "cooldown", 1, true) ~= nil
			or string.find(NameLower, "exhaust", 1, true) ~= nil
			or string.find(NameLower, "fatigue", 1, true) ~= nil
			or string.find(NameLower, "breath", 1, true) ~= nil
			or string.find(NameLower, "locked", 1, true) ~= nil
	end

	local function classifyName(Name)
		if typeof(Name) ~= "string" or Name == "" then
			return nil, nil
		end

		local NameLower = string.lower(Name)

		for GroupName, Lookup in pairs(Lookups) do
			if Lookup[NameLower] then
				return GroupName, NameLower
			end
		end

		if string.find(NameLower, "stamina", 1, true) == nil then
			return nil, NameLower
		end

		if containsFlag(NameLower) then
			return "Flags", NameLower
		end

		if containsSpend(NameLower) then
			return "Spend", NameLower
		end

		if string.find(NameLower, "max", 1, true) ~= nil
			or string.find(NameLower, "maximum", 1, true) ~= nil then
			return "Max", NameLower
		end

		if string.find(NameLower, "regen", 1, true) == nil
			and string.find(NameLower, "recover", 1, true) == nil
			and string.find(NameLower, "rate", 1, true) == nil
			and string.find(NameLower, "delay", 1, true) == nil
			and string.find(NameLower, "percent", 1, true) == nil
			and string.find(NameLower, "ratio", 1, true) == nil then
			return "Current", NameLower
		end

		return nil, NameLower
	end

	local function createValueHandle(Instance)
		return {
			Kind = "value",
			Instance = Instance
		}
	end

	local function createAttributeHandle(Instance, AttributeName)
		return {
			Kind = "attribute",
			Instance = Instance,
			Attribute = AttributeName
		}
	end

	local function createTableHandle(TableValue, FieldName)
		return {
			Kind = "table",
			Table = TableValue,
			Field = FieldName
		}
	end

	local function createUpvalueHandle(FunctionValue, UpvalueIndex, UpvalueName)
		return {
			Kind = "upvalue",
			Function = FunctionValue,
			UpvalueIndex = UpvalueIndex,
			UpvalueName = UpvalueName
		}
	end

	local function readFunctionUpvalue(FunctionValue, UpvalueIndex)
		if type(FunctionValue) ~= "function" or type(UpvalueIndex) ~= "number" then
			return nil
		end

		if type(debug) == "table" and type(debug.getupvalue) == "function" then
			local Success, Name, Value = pcall(debug.getupvalue, FunctionValue, UpvalueIndex)

			if Success and Name ~= nil then
				return Value, Name
			end
		end

		if type(getupvalue) == "function" then
			local Success, Name, Value = pcall(getupvalue, FunctionValue, UpvalueIndex)

			if Success and Name ~= nil then
				return Value, Name
			end
		end

		return nil
	end

	local function writeFunctionUpvalue(FunctionValue, UpvalueIndex, Value)
		if type(FunctionValue) ~= "function" or type(UpvalueIndex) ~= "number" then
			return false
		end

		if type(debug) == "table" and type(debug.setupvalue) == "function" then
			local Success, Result = pcall(debug.setupvalue, FunctionValue, UpvalueIndex, Value)

			if Success and Result ~= nil then
				return true
			end
		end

		if type(setupvalue) == "function" then
			local Success, Result = pcall(setupvalue, FunctionValue, UpvalueIndex, Value)

			if Success and Result ~= nil then
				return true
			end
		end

		return false
	end

	local function getFunctionInfo(FunctionValue)
		if type(FunctionValue) ~= "function" then
			return nil
		end

		if type(debug) == "table" and type(debug.getinfo) == "function" then
			local Success, Info = pcall(debug.getinfo, FunctionValue, "sln")

			if Success and type(Info) == "table" then
				return Info
			end
		end

		if type(getinfo) == "function" then
			local Success, Info = pcall(getinfo, FunctionValue, "sln")

			if Success and type(Info) == "table" then
				return Info
			end
		end

		return nil
	end

	local function getInstanceKey(Instance)
		if not Instance then
			return "nil"
		end

		local Cached = InstanceKeyCache[Instance]

		if Cached then
			return Cached
		end

		NextInstanceKeyId = NextInstanceKeyId + 1

		local Prefix = Instance.ClassName .. ":" .. Instance.Name
		local Success, Value = pcall(function()
			return Instance:GetFullName()
		end)

		if Success and Value then
			Prefix = Value
		end

		local Key = string.format("%s#%d", Prefix, NextInstanceKeyId)
		InstanceKeyCache[Instance] = Key

		return Key
	end

	local function getHandleKey(Handle)
		if not Handle then
			return "nil"
		end

		if Handle.Kind == "table" then
			return tostring(Handle.Table) .. "@" .. tostring(Handle.Field)
		end

		if Handle.Kind == "upvalue" then
			return tostring(Handle.Function) .. "@uv:" .. tostring(Handle.UpvalueIndex) .. ":" .. tostring(Handle.UpvalueName)
		end

		if not Handle.Instance then
			return "nil"
		end

		if Handle.Kind == "attribute" then
			return getInstanceKey(Handle.Instance) .. "@" .. tostring(Handle.Attribute)
		end

		return getInstanceKey(Handle.Instance)
	end

	local function isHandleValid(Handle)
		if not Handle then
			return false
		end

		if Handle.Kind == "table" then
			return type(Handle.Table) == "table" and Handle.Field ~= nil
		end

		if Handle.Kind == "upvalue" then
			return type(Handle.Function) == "function" and type(Handle.UpvalueIndex) == "number"
		end

		if not Handle.Instance then
			return false
		end

		if Handle.Instance == LocalPlayer then
			return true
		end

		return Handle.Instance.Parent ~= nil
	end

	local function readHandle(Handle)
		if not isHandleValid(Handle) then
			return nil
		end

		if Handle.Kind == "table" then
			local Success, Value = pcall(function()
				return Handle.Table[Handle.Field]
			end)

			return Success and Value or nil
		end

		if Handle.Kind == "upvalue" then
			return select(1, readFunctionUpvalue(Handle.Function, Handle.UpvalueIndex))
		end

		if Handle.Kind == "attribute" then
			local Success, Value = pcall(function()
				return Handle.Instance:GetAttribute(Handle.Attribute)
			end)

			return Success and Value or nil
		end

		local Success, Value = pcall(function()
			return Handle.Instance.Value
		end)

		return Success and Value or nil
	end

	local function coerceLike(Template, Value)
		if typeof(Value) == "number" then
			if typeof(Template) == "string" then
				return tostring(Value)
			end

			return Value
		end

		if typeof(Value) == "boolean" then
			if typeof(Template) == "number" then
				return Value and 1 or 0
			end

			if typeof(Template) == "string" then
				return Value and "true" or "false"
			end

			return Value
		end

		return Value
	end

	local function writeHandle(Handle, Value)
		if not isHandleValid(Handle) then
			return false
		end

		if Handle.Kind == "table" then
			return pcall(function()
				Handle.Table[Handle.Field] = Value
			end)
		end

		if Handle.Kind == "upvalue" then
			local CurrentValue = readHandle(Handle)

			return writeFunctionUpvalue(Handle.Function, Handle.UpvalueIndex, coerceLike(CurrentValue, Value))
		end

		if Handle.Kind == "attribute" then
			local CurrentValue = readHandle(Handle)

			return pcall(function()
				Handle.Instance:SetAttribute(Handle.Attribute, coerceLike(CurrentValue, Value))
			end)
		end

		local CurrentValue = readHandle(Handle)

		if typeof(Value) == "number" and Handle.Instance:IsA("IntValue") then
			Value = math.floor(Value + 0.5)
		else
			Value = coerceLike(CurrentValue, Value)
		end

		return pcall(function()
			Handle.Instance.Value = Value
		end)
	end

	local function isUsefulValue(GroupName, Value)
		if GroupName == "Flags" or GroupName == "Spend" then
			local ValueType = typeof(Value)

			return ValueType == "boolean" or ValueType == "number" or ValueType == "string"
		end

		return toNumber(Value) ~= nil
	end

	local function tableBelongsToLocalPlayer(TableValue)
		local KnownInstanceKeys = {
			"Player",
			"Character",
			"Entity",
			"Owner",
			"OwnerPlayer",
			"TargetPlayer",
			"LocalPlayer"
		}
		local KnownNameKeys = {
			"Name",
			"PlayerName",
			"OwnerName",
			"TargetName"
		}
		local KnownUserIdKeys = {
			"UserId",
			"PlayerUserId",
			"OwnerUserId",
			"TargetUserId"
		}

		for _, Key in ipairs(KnownInstanceKeys) do
			local Value = rawget(TableValue, Key)

			if typeof(Value) == "Instance" and isLocalRelatedInstance(Value) then
				return true
			end
		end

		for _, Key in ipairs(KnownNameKeys) do
			local Value = rawget(TableValue, Key)

			if type(Value) == "string" and Value == LocalPlayer.Name then
				return true
			end
		end

		for _, Key in ipairs(KnownUserIdKeys) do
			local Value = rawget(TableValue, Key)

			if type(Value) == "number" and Value == LocalPlayer.UserId then
				return true
			end

			if type(Value) == "string" and Value == tostring(LocalPlayer.UserId) then
				return true
			end
		end

		local Scanned = 0

		for _, Value in pairs(TableValue) do
			Scanned = Scanned + 1

			if typeof(Value) == "Instance" and isLocalRelatedInstance(Value) then
				return true
			end

			if type(Value) == "string" and Value == LocalPlayer.Name then
				return true
			end

			if type(Value) == "number" and Value == LocalPlayer.UserId then
				return true
			end

			if Scanned >= 24 then
				break
			end
		end

		return false
	end

	local function getInstanceConfidence(Instance)
		local Character = LocalPlayer.Character
		local Entity = findEntity()
		local MainScript = findMainScript()
		local MainScriptStats = MainScript and MainScript:FindFirstChild("Stats")
		local PlayerStats = LocalPlayer:FindFirstChild("Stats")
		local CharacterStats = Character and Character:FindFirstChild("Stats")
		local PlayerData = LocalPlayer:FindFirstChild("Data")
		local CharacterData = Character and Character:FindFirstChild("Data")

		if isInstanceInHierarchy(Instance, MainScriptStats) then
			return 120
		end

		if isInstanceInHierarchy(Instance, MainScript) then
			return 110
		end

		if isInstanceInHierarchy(Instance, PlayerStats)
			or isInstanceInHierarchy(Instance, CharacterStats) then
			return 100
		end

		if isInstanceInHierarchy(Instance, PlayerData)
			or isInstanceInHierarchy(Instance, CharacterData) then
			return 95
		end

		if isInstanceInHierarchy(Instance, Entity) then
			return 85
		end

		if isInstanceInHierarchy(Instance, Character) then
			return 70
		end

		if isInstanceInHierarchy(Instance, LocalPlayer) then
			return 60
		end

		return 40
	end

	local function isMainScriptStatsHandle(Handle)
		if not Handle or not Handle.Instance then
			return false
		end

		local MainScript = findMainScript()
		local MainScriptStats = MainScript and MainScript:FindFirstChild("Stats")

		return isInstanceInHierarchy(Handle.Instance, MainScriptStats)
	end

	local function isMainScriptLogicHandle(Handle)
		if not Handle or not Handle.Instance then
			return false
		end

		local MainScript = findMainScript()

		if not MainScript or not isInstanceInHierarchy(Handle.Instance, MainScript) then
			return false
		end

		return not isMainScriptStatsHandle(Handle)
	end

	local function isInterestingLogicName(NameLower)
		if type(NameLower) ~= "string" or NameLower == "" then
			return false
		end

		return string.find(NameLower, "stamina", 1, true) ~= nil
			or string.find(NameLower, "exhaust", 1, true) ~= nil
			or string.find(NameLower, "fatigue", 1, true) ~= nil
			or string.find(NameLower, "breath", 1, true) ~= nil
			or string.find(NameLower, "tired", 1, true) ~= nil
			or string.find(NameLower, "winded", 1, true) ~= nil
			or string.find(NameLower, "dash", 1, true) ~= nil
			or string.find(NameLower, "sprint", 1, true) ~= nil
			or string.find(NameLower, "run", 1, true) ~= nil
			or string.find(NameLower, "attack", 1, true) ~= nil
			or string.find(NameLower, "combat", 1, true) ~= nil
			or string.find(NameLower, "cooldown", 1, true) ~= nil
			or string.find(NameLower, "cost", 1, true) ~= nil
			or string.find(NameLower, "locked", 1, true) ~= nil
			or string.find(NameLower, "input", 1, true) ~= nil
	end

	local function isInterestingFunctionSourceText(TextLower)
		if type(TextLower) ~= "string" or TextLower == "" then
			return false
		end

		return string.find(TextLower, "mainscript", 1, true) ~= nil
			or string.find(TextLower, "crninput", 1, true) ~= nil
			or isInterestingLogicName(TextLower)
	end

	local function getFunctionScanConfidence(FunctionValue)
		local Info = getFunctionInfo(FunctionValue)
		local NameLower = ""
		local SourceLower = ""
		local ShortSourceLower = ""

		if Info then
			NameLower = string.lower(tostring(Info.name or ""))
			SourceLower = string.lower(tostring(Info.source or ""))
			ShortSourceLower = string.lower(tostring(Info.short_src or ""))
		end

		local Combined = table.concat({
			NameLower,
			SourceLower,
			ShortSourceLower
		}, " ")
		local PlayerNameLower = string.lower(LocalPlayer.Name)

		if string.find(Combined, "crninput", 1, true) ~= nil then
			return 165
		end

		if string.find(Combined, "mainscript", 1, true) ~= nil
			and string.find(Combined, PlayerNameLower, 1, true) ~= nil then
			return 155
		end

		if string.find(Combined, "mainscript", 1, true) ~= nil then
			return 145
		end

		if isInterestingFunctionSourceText(Combined) then
			return 125
		end

		return 0
	end

	local function shouldBootstrapLogicHandle(GroupName, Handle, Confidence, SourceKind, ExactAlias, NameLower)
		if GroupName ~= "Current" and GroupName ~= "Max" then
			return false
		end

		local ConfidenceValue = Confidence or 0
		local HiddenLogicName = type(NameLower) == "string"
			and (
				string.find(NameLower, "stamina", 1, true) ~= nil
				or string.find(NameLower, "exhaust", 1, true) ~= nil
				or string.find(NameLower, "fatigue", 1, true) ~= nil
				or string.find(NameLower, "breath", 1, true) ~= nil
				or string.find(NameLower, "tired", 1, true) ~= nil
				or string.find(NameLower, "winded", 1, true) ~= nil
			)

		if SourceKind ~= "instance" then
			if SourceKind == "upvalue" then
				if ExactAlias == true or HiddenLogicName then
					return ConfidenceValue >= 145
				end

				return ConfidenceValue >= 165
			end

			if SourceKind == "table" or SourceKind == "env" then
				if ExactAlias == true or HiddenLogicName then
					return ConfidenceValue >= 150
				end

				return ConfidenceValue >= 170
			end

			return false
		end

		return ConfidenceValue >= 105 and isMainScriptLogicHandle(Handle)
	end

	local function getRemoteDisplayName(Remote)
		local Success, Value = pcall(function()
			return Remote:GetFullName()
		end)

		if Success and Value then
			return Value
		end

		return Remote.Name
	end

	local function summarizeArguments(Arguments)
		local Parts = {}
		local Count = math.min(Arguments.n or #Arguments, 3)

		for Index = 1, Count do
			table.insert(Parts, summarizeValue(Arguments[Index]))
		end

		if (Arguments.n or #Arguments) > Count then
			table.insert(Parts, "...")
		end

		return table.concat(Parts, ", ")
	end

	local function initialCategoryForGroup(GroupName)
		if GroupName == "Flags" then
			return "flags"
		end

		if GroupName == "Spend" then
			return "spend"
		end

		return "display"
	end

	local function getCandidateRegistryKey(GroupName, Handle)
		return "local:" .. GroupName .. ":" .. getHandleKey(Handle)
	end

	local function getRemoteRegistryKey(Remote, Method)
		return "remote:" .. tostring(Method) .. ":" .. getInstanceKey(Remote)
	end

	local function clearCandidateActivity()
		for _, Candidate in pairs(StaminaFeature.CandidateRegistry) do
			Candidate.Active = false
		end
	end

	local function clearHandleSignals()
		for _, Connection in ipairs(StaminaFeature.HandleSignals) do
			Connection:Disconnect()
		end

		table.clear(StaminaFeature.HandleSignals)
	end

	local function clearHandles()
		clearHandleSignals()
		table.clear(StaminaFeature.Handles.Current)
		table.clear(StaminaFeature.Handles.Max)
		table.clear(StaminaFeature.Handles.Flags)
		table.clear(StaminaFeature.Handles.Spend)
	end

	local function clearRuntimeCandidates()
		table.clear(StaminaFeature.CandidateRegistry)
		table.clear(StaminaFeature.CandidateOrder)
		table.clear(StaminaFeature.RemoteCandidates)
		table.clear(StaminaFeature.RemoteCandidateOrder)
	end

	local function getCandidateDisplayName(Candidate)
		return Candidate.DisplayName or Candidate.Name or Candidate.NameLower or Candidate.RegistryKey
	end

	local function getCompactParentPath(Instance, Depth)
		if not Instance then
			return ""
		end

		local Parts = {}
		local Current = Instance.Parent
		local Limit = math.max(1, Depth or 1)

		while Current and #Parts < Limit do
			table.insert(Parts, 1, Current.Name)
			Current = Current.Parent
		end

		return table.concat(Parts, "/")
	end

	local function getCandidateLocationSuffix(Candidate)
		local Handle = Candidate and Candidate.Handle

		if not Handle then
			return ""
		end

		if Handle.Kind == "attribute" and Handle.Instance then
			local ParentPath = getCompactParentPath(Handle.Instance, 2)
			local ScopeName = ParentPath ~= ""
				and string.format("%s/%s", ParentPath, Handle.Instance.Name)
				or Handle.Instance.Name

			return string.format("@%s.%s", ScopeName, tostring(Handle.Attribute))
		end

		if Handle.Kind == "value" and Handle.Instance then
			local ParentPath = getCompactParentPath(Handle.Instance, 2)

			if ParentPath ~= "" then
				return "@" .. ParentPath
			end

			return ""
		end

		if Handle.Kind == "upvalue" then
			return string.format("@uv:%s", tostring(Handle.UpvalueName or Handle.UpvalueIndex or "?"))
		end

		if Handle.Kind == "table" then
			return string.format("@tbl:%s", tostring(Handle.Field or "?"))
		end

		return ""
	end

	local function getCandidateConsoleLabel(Candidate)
		if not Candidate then
			return "none"
		end

		return string.format("%s%s", getCandidateDisplayName(Candidate), getCandidateLocationSuffix(Candidate))
	end

	local function isStaminaDisplayName(NameLower)
		if type(NameLower) ~= "string" or NameLower == "" then
			return false
		end

		return string.find(NameLower, "stamina", 1, true) ~= nil
			or string.find(NameLower, "eevee", 1, true) ~= nil
			or string.find(NameLower, "exhaust", 1, true) ~= nil
			or string.find(NameLower, "endurance", 1, true) ~= nil
			or string.find(NameLower, "fatigue", 1, true) ~= nil
			or string.find(NameLower, "breath", 1, true) ~= nil
	end

	local function isStrongMainScriptStatsPrimaryAlias(Candidate)
		if not Candidate
			or Candidate.SourceKind ~= "instance"
			or not Candidate.ExactAlias
			or not isMainScriptStatsHandle(Candidate.Handle)
			or (Candidate.Group ~= "Current" and Candidate.Group ~= "Max") then
			return false
		end

		local NameLower = Candidate.NameLower or ""

		return NameLower == "stamina"
			or NameLower == "staminainstat"
			or NameLower == "eevee"
			or NameLower == "bodyfatigue"
			or NameLower == "bodyfatique"
			or NameLower == "currentstamina"
			or NameLower == "staminavalue"
			or NameLower == "maxstamina"
			or NameLower == "maximumstamina"
			or NameLower == "staminamax"
	end

	local function getHandleScopeInstance(Handle)
		if not Handle or not Handle.Instance then
			return nil
		end

		if Handle.Kind == "attribute" then
			return Handle.Instance
		end

		return Handle.Instance.Parent
	end

	local function handlesShareScope(LeftHandle, RightHandle)
		local LeftScope = getHandleScopeInstance(LeftHandle)
		local RightScope = getHandleScopeInstance(RightHandle)

		return LeftScope ~= nil
			and LeftScope == RightScope
	end

	local function promoteCandidate(Candidate, Category, Score, Reason)
		Candidate.Category = Category
		Candidate.Promoted = true
		Candidate.Score = math.max(Candidate.Score or 0, Score or 0)
		Candidate.PromotionReason = Reason or Candidate.PromotionReason
		Candidate.LastFailureReason = nil
	end

	local function normalizeCandidate(Candidate)
		if Candidate.Group == "Flags" then
			Candidate.Category = "flags"
		elseif Candidate.Group == "Spend" then
			Candidate.Category = "spend"
		else
			Candidate.Category = "display"
		end

		Candidate.Promoted = false
		Candidate.PromotionReason = nil
	end

	local function upsertLocalCandidate(GroupName, Name, NameLower, Handle, InitialValue, Confidence, SourceKind)
		local RegistryKey = getCandidateRegistryKey(GroupName, Handle)
		local Candidate = StaminaFeature.CandidateRegistry[RegistryKey]
		local ExactAlias = Lookups[GroupName] and Lookups[GroupName][NameLower] == true or false
		local Now = os.clock()

		if not Candidate then
			Candidate = {
				RegistryKey = RegistryKey,
				Group = GroupName,
				Name = Name,
				NameLower = NameLower,
				DisplayName = Name,
				Handle = Handle,
				HandleKey = getHandleKey(Handle),
				Family = getFamily(NameLower),
				SourceKind = SourceKind or "instance",
				Confidence = Confidence or 0,
				ExactAlias = ExactAlias,
				Category = initialCategoryForGroup(GroupName),
				Promoted = false,
				Score = 0,
				ChangeCount = 0,
				LocalWriteCount = 0,
				ExternalWriteCount = 0,
				LastWriteResult = nil,
				LastValue = InitialValue,
				BestObservedNumber = toNumber(InitialValue),
				PreviousValue = nil,
				LastChangeTime = 0,
				LastObservedAt = Now,
				ObservationHits = 0,
				CaptureHits = 0,
				Active = true,
				PromotionReason = nil,
				FailedVerificationCount = 0,
				BootstrapBlocked = false,
				RuntimePinned = false,
				LastFailureReason = nil
			}

			if ExactAlias
				and not Candidate.BootstrapBlocked
				and shouldBootstrapLogicHandle(GroupName, Handle, Confidence, SourceKind, ExactAlias, NameLower) then
				promoteCandidate(Candidate, "logic-local", 7, "exact_logic_bootstrap")
			elseif GroupName == "Flags" and ExactAlias and (Confidence or 0) >= 85 then
				promoteCandidate(Candidate, "flags", 5, "exact_flag_bootstrap")
			elseif GroupName == "Spend" and ExactAlias and (Confidence or 0) >= 85 then
				promoteCandidate(Candidate, "spend", 5, "exact_spend_bootstrap")
			end

			StaminaFeature.CandidateRegistry[RegistryKey] = Candidate
			table.insert(StaminaFeature.CandidateOrder, Candidate)
		end

		Candidate.Group = GroupName
		Candidate.Name = Name
		Candidate.NameLower = NameLower
		Candidate.DisplayName = Name
		Candidate.Handle = Handle
		Candidate.HandleKey = getHandleKey(Handle)
		Candidate.Family = getFamily(NameLower)
		Candidate.SourceKind = SourceKind or Candidate.SourceKind
		Candidate.Confidence = math.max(Candidate.Confidence or 0, Confidence or 0)
		Candidate.ExactAlias = ExactAlias
		Candidate.Active = true
		Candidate.LastObservedAt = Now

		if ExactAlias
			and not Candidate.BootstrapBlocked
			and shouldBootstrapLogicHandle(GroupName, Handle, Candidate.Confidence, Candidate.SourceKind, ExactAlias, NameLower) then
			promoteCandidate(Candidate, "logic-local", 7, "exact_logic_bootstrap")
		end

		if Candidate.LastValue == nil and InitialValue ~= nil then
			Candidate.LastValue = InitialValue
		end

		return Candidate
	end

	local function upsertRemoteCandidate(Remote, Method, Arguments)
		local RegistryKey = getRemoteRegistryKey(Remote, Method)
		local Candidate = StaminaFeature.RemoteCandidates[RegistryKey]

		if not Candidate then
			Candidate = {
				RegistryKey = RegistryKey,
				Name = getRemoteDisplayName(Remote),
				Method = Method,
				Remote = Remote,
				Category = "logic-remote",
				Promoted = false,
				Count = 0,
				CaptureHits = 0,
				Score = 0,
				LastCallTime = 0,
				LastArgsSummary = "",
				BlockedCount = 0
			}

			StaminaFeature.RemoteCandidates[RegistryKey] = Candidate
			table.insert(StaminaFeature.RemoteCandidateOrder, Candidate)
		end

		Candidate.Count = Candidate.Count + 1
		Candidate.LastCallTime = os.clock()
		Candidate.LastArgsSummary = summarizeArguments(Arguments)

		return Candidate
	end

	local function getTruthyValue(Value)
		local ValueType = typeof(Value)

		if ValueType == "boolean" then
			return true
		end

		if ValueType == "number" then
			return 1
		end

		if ValueType == "string" then
			local Normalized = string.lower(Value)

			if tonumber(Value) ~= nil then
				return "1"
			end

			if Normalized == "false" or Normalized == "true" then
				return "true"
			end

			return "true"
		end

		return true
	end

	local function getZeroLikeValue(Value)
		local ValueType = typeof(Value)

		if ValueType == "boolean" then
			return false
		end

		if ValueType == "number" then
			return 0
		end

		if ValueType == "string" then
			local Normalized = string.lower(Value)

			if tonumber(Value) ~= nil then
				return "0"
			end

			if Normalized == "false" or Normalized == "true" then
				return "false"
			end

			return "0"
		end

		return 0
	end

	local function supportsScopedStringSupportRewrite(GroupName, Candidate)
		if not Candidate
			or Candidate.SourceKind ~= "instance"
			or not Candidate.Handle
			or not isMainScriptStatsHandle(Candidate.Handle) then
			return false
		end

		local NameLower = Candidate.NameLower or ""

		if GroupName == "Flags" then
			return Candidate.ExactAlias == true
				or string.find(NameLower, "stamina", 1, true) ~= nil
				or string.find(NameLower, "sprint", 1, true) ~= nil
				or string.find(NameLower, "run", 1, true) ~= nil
				or string.find(NameLower, "dash", 1, true) ~= nil
				or string.find(NameLower, "attack", 1, true) ~= nil
		end

		if GroupName == "Spend" then
			return Candidate.ExactAlias == true
				or string.find(NameLower, "stamina", 1, true) ~= nil
				or string.find(NameLower, "deplete", 1, true) ~= nil
				or string.find(NameLower, "cost", 1, true) ~= nil
				or string.find(NameLower, "cooldown", 1, true) ~= nil
				or string.find(NameLower, "exhaust", 1, true) ~= nil
				or string.find(NameLower, "eevee", 1, true) ~= nil
		end

		return false
	end

	local function supportsSafeRuntimeRewrite(GroupName, Value, Candidate)
		local ValueType = typeof(Value)

		if GroupName == "Flags" then
			if ValueType == "string" then
				return supportsScopedStringSupportRewrite(GroupName, Candidate)
			end

			return ValueType == "boolean" or ValueType == "number"
		end

		if GroupName == "Spend" then
			if ValueType == "string" then
				return supportsScopedStringSupportRewrite(GroupName, Candidate)
			end

			return ValueType == "boolean" or ValueType == "number"
		end

		if GroupName == "Current" or GroupName == "Max" then
			return ValueType == "number"
		end

		return false
	end

	local DirectStatsFlagTruthLookup = createLookup({
		"NoStaminaCost",
		"NoCooldown",
		"NoEeveeDeplete",
		"CanUseStamina",
		"HasStamina",
		"EnoughStamina",
		"CanDash",
		"CanSprint",
		"CanRun",
		"CanAttack"
	})

	local DirectStatsFlagFalseLookup = createLookup({
		"Sleeping"
	})

	local DirectStatsSpendZeroLookup = createLookup({
		"Exhaustion",
		"Exhausted",
		"Fatigue",
		"Fatigued",
		"Breath",
		"OutOfBreath",
		"BreathLocked",
		"ExhaustionLevel",
		"FatigueLevel",
		"EeveeDeplete"
	})

	local DirectStatsFillToMaxLookup = createLookup({
		"DownedHealth",
		"RecoveryHealth"
	})

	local DirectStatsHighWaterLookup = createLookup({
		"Eevee",
		"BodyFatigue",
		"BodyFatique",
		"DownedHealth",
		"RecoveryHealth"
	})

	local function getCharacterMetrics()
		local Character = LocalPlayer.Character
		local Humanoid = Character and Character:FindFirstChildOfClass("Humanoid")
		local RootPart = Character and Character:FindFirstChild("HumanoidRootPart")
		local ToolEquipped = false

		if Character then
			for _, Item in ipairs(Character:GetChildren()) do
				if Item:IsA("Tool") then
					ToolEquipped = true
					break
				end
			end
		end

		return {
			Character = Character,
			Humanoid = Humanoid,
			RootPart = RootPart,
			MoveMagnitude = Humanoid and Humanoid.MoveDirection.Magnitude or 0,
			WalkSpeed = Humanoid and Humanoid.WalkSpeed or 0,
			VelocityMagnitude = RootPart and RootPart.AssemblyLinearVelocity.Magnitude or 0,
			ToolEquipped = ToolEquipped
		}
	end

	local function getProfileConfig(Profile)
		return CaptureProfiles[Profile] or CaptureProfiles.Run
	end

	local function getProfileFamily(Profile)
		if Profile == "Run" then
			return "run"
		end

		if Profile == "Dash" then
			return "dash"
		end

		if Profile == "Attack" then
			return "attack"
		end

		return nil
	end

	local function createCaptureSession(Profile)
		local SelectedProfile = CaptureProfiles[Profile] and Profile or "Run"
		local ProfileConfig = getProfileConfig(SelectedProfile)
		local Now = os.clock()

		return {
			Profile = SelectedProfile,
			State = "baseline",
			StartedAt = Now,
			BaselineEndsAt = Now + ProfileConfig.BaselineDuration,
			EndsAt = Now + ProfileConfig.BaselineDuration + ProfileConfig.ActiveDuration,
			Observations = {},
			RemoteObservations = {},
			ActionValid = SelectedProfile == "Free",
			MaxSpeed = 0,
			MaxMoveMagnitude = 0,
			ToolSeen = false,
			RemoteCallCount = 0,
			AttackSignalCount = 0
		}
	end

	local function recordCaptureCandidateValue(Candidate, Value, Source)
		local Session = StaminaFeature.CaptureSession

		if not Session or Session.State == "completed" then
			return
		end

		local Observation = Session.Observations[Candidate.RegistryKey]
		local NumberValue = toNumber(Value)

		if not Observation then
			Observation = {
				Name = getCandidateDisplayName(Candidate),
				Group = Candidate.Group,
				Category = Candidate.Category,
				Family = Candidate.Family,
				Confidence = Candidate.Confidence,
				SourceKind = Candidate.SourceKind,
				BaselineValue = Value,
				LastValue = Value,
				MinValue = NumberValue,
				MaxValue = NumberValue,
				TotalChanges = 0,
				LocalWrites = 0,
				ExternalWrites = 0,
				DeltaMagnitude = 0
			}

			Session.Observations[Candidate.RegistryKey] = Observation
		end

		if Session.State == "baseline" then
			Observation.BaselineValue = Value
			Observation.LastValue = Value

			if NumberValue ~= nil then
				Observation.MinValue = NumberValue
				Observation.MaxValue = NumberValue
			end

			return
		end

		if not valuesEquivalent(Value, Observation.LastValue) then
			Observation.TotalChanges = Observation.TotalChanges + 1
		end

		if Source == "local_write" then
			Observation.LocalWrites = Observation.LocalWrites + 1
		elseif Source == "external_write" then
			Observation.ExternalWrites = Observation.ExternalWrites + 1
		end

		if NumberValue ~= nil then
			if Observation.MinValue == nil or NumberValue < Observation.MinValue then
				Observation.MinValue = NumberValue
			end

			if Observation.MaxValue == nil or NumberValue > Observation.MaxValue then
				Observation.MaxValue = NumberValue
			end

			local BaselineNumber = toNumber(Observation.BaselineValue)

			if BaselineNumber ~= nil then
				local DeltaMagnitude = math.abs(NumberValue - BaselineNumber)

				if DeltaMagnitude > Observation.DeltaMagnitude then
					Observation.DeltaMagnitude = DeltaMagnitude
				end
			end
		end

		if Session.Profile == "Attack" and Candidate.Family == "attack" then
			Session.AttackSignalCount = Session.AttackSignalCount + 1
		end

		Observation.LastValue = Value
	end

	local function recordCaptureRemoteValue(RemoteCandidate)
		local Session = StaminaFeature.CaptureSession

		if not Session or Session.State ~= "active" then
			return
		end

		local Observation = Session.RemoteObservations[RemoteCandidate.RegistryKey]

		if not Observation then
			Observation = {
				Name = RemoteCandidate.Name,
				Method = RemoteCandidate.Method,
				Count = 0,
				LastArgsSummary = ""
			}

			Session.RemoteObservations[RemoteCandidate.RegistryKey] = Observation
		end

		Observation.Count = Observation.Count + 1
		Observation.LastArgsSummary = RemoteCandidate.LastArgsSummary
		Session.RemoteCallCount = Session.RemoteCallCount + 1
	end

	local function observeCandidateValue(Candidate, Value, Source)
		if not Candidate then
			return Value
		end

		local Now = os.clock()
		local NumberValue = toNumber(Value)

		if Candidate.LastValue == nil and Value ~= nil then
			Candidate.LastValue = Value
		end

		if not valuesEquivalent(Value, Candidate.LastValue) then
			Candidate.PreviousValue = Candidate.LastValue
			Candidate.LastValue = Value
			Candidate.LastChangeTime = Now
			Candidate.ChangeCount = Candidate.ChangeCount + 1
		end

		if Source == "local_write" then
			Candidate.LocalWriteCount = Candidate.LocalWriteCount + 1
		elseif Source == "external_write" then
			Candidate.ExternalWriteCount = Candidate.ExternalWriteCount + 1
		end

		Candidate.ObservationHits = Candidate.ObservationHits + 1
		Candidate.LastObservedAt = Now

		if NumberValue ~= nil then
			local BestObservedNumber = Candidate.BestObservedNumber

			if BestObservedNumber == nil or NumberValue > BestObservedNumber then
				Candidate.BestObservedNumber = NumberValue
			end
		end

		recordCaptureCandidateValue(Candidate, Value, Source)

		if Source == "external_write"
			and (Candidate.Group == "Flags" or Candidate.Group == "Spend")
			and Candidate.ExactAlias then
			promoteCandidate(Candidate, initialCategoryForGroup(Candidate.Group), 6, "runtime_external_write")
		elseif Source == "external_write"
			and (Candidate.Group == "Current" or Candidate.Group == "Max")
			and Candidate.SourceKind == "instance"
			and not Candidate.BootstrapBlocked
			and Candidate.ExternalWriteCount >= 2 then
			if isStrongMainScriptStatsPrimaryAlias(Candidate) then
				Candidate.RuntimePinned = true
				promoteCandidate(Candidate, "logic-local", 7 + Candidate.ExternalWriteCount, "runtime_stats_external_write")
			elseif not isMainScriptStatsHandle(Candidate.Handle) then
				promoteCandidate(Candidate, "logic-local", 6 + Candidate.ExternalWriteCount, "runtime_external_write")
			end
		end

		return Value
	end

	local function readEntryValue(Entry)
		local Value = readHandle(Entry.Handle)

		if Entry.Candidate then
			observeCandidateValue(Entry.Candidate, Value, "read")
		end

		return Value
	end

	local function writeEntryValue(Entry, Value)
		local Success = writeHandle(Entry.Handle, Value)

		if Entry.Candidate then
			Entry.Candidate.LastWriteResult = Success

			if Success then
				observeCandidateValue(Entry.Candidate, Value, "local_write")
			end
		end

		return Success
	end

	local function countPromotedLocalCandidates()
		local Count = 0

		for _, Candidate in ipairs(StaminaFeature.CandidateOrder) do
			if Candidate.Promoted then
				Count = Count + 1
			end
		end

		return Count
	end

	local function countPromotedRemoteCandidates()
		local Count = 0

		for _, Candidate in ipairs(StaminaFeature.RemoteCandidateOrder) do
			if Candidate.Promoted then
				Count = Count + 1
			end
		end

		return Count
	end

	local isLogicLocalCandidate
	local isFlagCandidate
	local isSpendCandidate
	local isDisplayCandidate
	local isRuntimeFlagCandidate
	local isRuntimeSpendCandidate
	local inferContextGroup

	local function countLogicPrimaryEntries()
		local CurrentCount = 0
		local MaxCount = 0

		for _, Entry in ipairs(StaminaFeature.Handles.Current) do
			if isLogicLocalCandidate(Entry.Candidate) then
				CurrentCount = CurrentCount + 1
			end
		end

		for _, Entry in ipairs(StaminaFeature.Handles.Max) do
			if isLogicLocalCandidate(Entry.Candidate) then
				MaxCount = MaxCount + 1
			end
		end

		return CurrentCount, MaxCount
	end

	local function getDiagnosticSnapshot()
		local LogicCurrentCount, LogicMaxCount = countLogicPrimaryEntries()
		local DisplayCurrentCount = 0
		local DisplayMaxCount = 0

		for _, Entry in ipairs(StaminaFeature.Handles.Current) do
			if isDisplayCandidate(Entry.Candidate) then
				DisplayCurrentCount = DisplayCurrentCount + 1
			end
		end

		for _, Entry in ipairs(StaminaFeature.Handles.Max) do
			if isDisplayCandidate(Entry.Candidate) then
				DisplayMaxCount = DisplayMaxCount + 1
			end
		end

		return {
			HandleCurrentCount = #StaminaFeature.Handles.Current,
			HandleMaxCount = #StaminaFeature.Handles.Max,
			HandleFlagCount = #StaminaFeature.Handles.Flags,
			HandleSpendCount = #StaminaFeature.Handles.Spend,
			LogicCurrentCount = LogicCurrentCount,
			LogicMaxCount = LogicMaxCount,
			DisplayCurrentCount = DisplayCurrentCount,
			DisplayMaxCount = DisplayMaxCount
		}
	end

	local function getLastCaptureLabel()
		local Session = StaminaFeature.CaptureSession

		if Session and Session.State ~= "completed" then
			return string.format("%s (%s)", tostring(Session.State), tostring(Session.Profile))
		end

		if #StaminaFeature.LastCaptureSummary > 0 then
			return tostring(StaminaFeature.LastCaptureSummary[1])
		end

		return "none"
	end

	local function buildStatusLines()
		local Snapshot = getDiagnosticSnapshot()

		return {
			string.format("State: %s", tostring(StaminaFeature.VerificationState or "idle")),
			string.format("FailureReason: %s", tostring(StaminaFeature.LastFailureReason or "none")),
			string.format("Profile: %s", tostring(StaminaFeature.LastActionProfile or "Free")),
			string.format("LogicHandles: C=%d M=%d", Snapshot.LogicCurrentCount, Snapshot.LogicMaxCount),
			string.format("DisplayHandles: C=%d M=%d", Snapshot.DisplayCurrentCount, Snapshot.DisplayMaxCount),
			string.format("LastCapture: %s", getLastCaptureLabel())
		}
	end

	local function buildStatusConsoleLine()
		local Snapshot = getDiagnosticSnapshot()
		local function getHandleCandidateLabel(GroupName, Predicate)
			local Group = StaminaFeature.Handles[GroupName]

			if type(Group) ~= "table" or type(Predicate) ~= "function" then
				return "none"
			end

			local BestCandidate = nil

			for _, Entry in ipairs(Group) do
				if Predicate(Entry.Candidate) then
					local Candidate = Entry.Candidate

					if BestCandidate == nil
						or (Candidate.Score or 0) > (BestCandidate.Score or 0)
						or (
							(Candidate.Score or 0) == (BestCandidate.Score or 0)
							and (Candidate.Confidence or 0) > (BestCandidate.Confidence or 0)
						) then
						BestCandidate = Candidate
					end
				end
			end

			if not BestCandidate then
				return "none"
			end

			return string.format(
				"%s[%s/%s]",
				getCandidateConsoleLabel(BestCandidate),
				tostring(BestCandidate.Category or "unknown"),
				tostring(BestCandidate.SourceKind or "unknown")
			)
		end
		local PrimaryLabel = getHandleCandidateLabel("Current", isLogicLocalCandidate)
		local FlagLabel = getHandleCandidateLabel("Flags", isRuntimeFlagCandidate)
		local SpendLabel = getHandleCandidateLabel("Spend", isRuntimeSpendCandidate)

		local BaseLine = string.format(
			"State=%s Reason=%s Profile=%s Logic C=%d M=%d Display C=%d M=%d Handles C=%d M=%d F=%d S=%d Primary=%s Flag=%s Spend=%s",
			tostring(StaminaFeature.VerificationState or "idle"),
			tostring(StaminaFeature.LastFailureReason or "none"),
			tostring(StaminaFeature.LastActionProfile or "Free"),
			Snapshot.LogicCurrentCount,
			Snapshot.LogicMaxCount,
			Snapshot.DisplayCurrentCount,
			Snapshot.DisplayMaxCount,
			Snapshot.HandleCurrentCount,
			Snapshot.HandleMaxCount,
			Snapshot.HandleFlagCount,
			Snapshot.HandleSpendCount,
			PrimaryLabel,
			FlagLabel,
			SpendLabel
		)

		if type(StaminaFeature.LastSupportIssue) == "string"
			and StaminaFeature.LastSupportIssue ~= "" then
			return BaseLine .. " SupportIssue=" .. StaminaFeature.LastSupportIssue
		end

		return BaseLine
	end

	local function refreshStatusSummary()
		StaminaFeature.LastStatusSummary = buildStatusLines()
	end

	local function buildDiagnosticHeadline(HeaderText)
		local Snapshot = getDiagnosticSnapshot()

		return string.format(
			"%s Logic C=%d M=%d | Handles C=%d M=%d F=%d S=%d",
			tostring(HeaderText or "Stamina diagnostics."),
			Snapshot.LogicCurrentCount,
			Snapshot.LogicMaxCount,
			Snapshot.HandleCurrentCount,
			Snapshot.HandleMaxCount,
			Snapshot.HandleFlagCount,
			Snapshot.HandleSpendCount
		)
	end

	local function buildDiagnosticLines(MaxSummaryLines)
		local Snapshot = getDiagnosticSnapshot()
		local Lines = {
			string.format(
				"Handles C=%d M=%d F=%d S=%d",
				Snapshot.HandleCurrentCount,
				Snapshot.HandleMaxCount,
				Snapshot.HandleFlagCount,
				Snapshot.HandleSpendCount
			),
			string.format("Logic C=%d M=%d", Snapshot.LogicCurrentCount, Snapshot.LogicMaxCount)
		}
		local Session = StaminaFeature.CaptureSession

		if Session then
			table.insert(Lines, string.format("Capture %s (%s)", tostring(Session.State), tostring(Session.Profile)))
		else
			table.insert(Lines, "Capture idle")
		end

		if #StaminaFeature.LastCaptureSummary > 0 then
			local Limit = math.max(0, MaxSummaryLines or 0)
			local Added = 0

			for _, Line in ipairs(StaminaFeature.LastCaptureSummary) do
				if type(Line) == "string" and Line ~= "" then
					table.insert(Lines, Line)
					Added = Added + 1

					if Added >= Limit then
						break
					end
				end
			end
		end

		return Lines
	end

	local function emitDiagnosticConsole(Lines)
		if type(Lines) ~= "table" or #Lines == 0 then
			return
		end

		local ConsoleLine = table.concat(Lines, " | ")

		if ConsoleLine ~= "" then
			warn("[Fatality][Stamina] " .. ConsoleLine)
		end
	end

	local function emitStatusConsole()
		local ConsoleLine = buildStatusConsoleLine()

		if ConsoleLine ~= "" and ConsoleLine ~= StaminaFeature.LastStatusConsoleLine then
			StaminaFeature.LastStatusConsoleLine = ConsoleLine
			warn("[Fatality][Stamina] " .. ConsoleLine)
		end
	end

	local function setVerificationState(State, Reason, Profile)
		local NormalizedState = State or "idle"
		local NormalizedReason = Reason or "none"
		local NormalizedProfile = Profile or StaminaFeature.LastActionProfile or "Free"
		local StateChanged = StaminaFeature.VerificationState ~= NormalizedState
			or StaminaFeature.LastFailureReason ~= NormalizedReason
			or StaminaFeature.LastActionProfile ~= NormalizedProfile

		StaminaFeature.VerificationState = NormalizedState
		StaminaFeature.LastFailureReason = NormalizedReason
		StaminaFeature.LastActionProfile = NormalizedProfile
		refreshStatusSummary()

		if StateChanged or StaminaFeature.LastSupportIssue ~= "" then
			emitStatusConsole()
		end
	end

	local scheduleGcResolve
	local scheduleStep

	local function notifyDiagnosticSummary(HeaderText, MaxSummaryLines, IconName)
		local Now = os.clock()

		if (Now - StaminaFeature.LastDebugNotifyAt) < StaminaFeature.DebugNotifyCooldown then
			return
		end

		StaminaFeature.LastDebugNotifyAt = Now
		local ContentLines = {
			buildDiagnosticHeadline(HeaderText or "Stamina diagnostics.")
		}

		for _, Line in ipairs(buildDiagnosticLines(MaxSummaryLines)) do
			table.insert(ContentLines, Line)
		end

		emitDiagnosticConsole(ContentLines)

		if Notification then
			Notification:Notify({
				Title = "FATALITY",
				Content = table.concat(ContentLines, "\n"),
				Icon = IconName or "info"
			})
		end
	end

	local function requestFailureCapture(Profile)
		if not StaminaFeature.Enabled
			or StaminaFeature.AutoFailureCapture ~= true then
			return false
		end

		local Session = StaminaFeature.CaptureSession

		if Session and Session.State ~= "completed" then
			return false
		end

		local Now = os.clock()

		if (Now - StaminaFeature.LastFailureCaptureAt) < StaminaFeature.FailureCaptureCooldown then
			return false
		end

		StaminaFeature.LastFailureCaptureAt = Now

		local Success = pcall(function()
			StaminaFeature:StartDebugCapture(Profile or StaminaFeature.DebugProfile)
		end)

		return Success
	end

	local function warnMissingHandles()
		local Now = os.clock()

		if (Now - StaminaFeature.LastWarnAt) < StaminaFeature.WarnCooldown then
			return
		end

		StaminaFeature.LastWarnAt = Now
		local CaptureStarted = requestFailureCapture(
			StaminaFeature.LastActionProfile ~= "Free" and StaminaFeature.LastActionProfile or StaminaFeature.DebugProfile
		)
		local ContentLines = {
			buildDiagnosticHeadline("Inf stamina could not find logic stamina handles yet.")
		}

		if CaptureStarted then
			table.insert(ContentLines, "Auto capture started.")
		end

		for _, Line in ipairs(buildDiagnosticLines(2)) do
			table.insert(ContentLines, Line)
		end

		emitDiagnosticConsole(ContentLines)

		if Notification then
			Notification:Notify({
				Title = "FATALITY",
				Content = table.concat(ContentLines, "\n"),
				Icon = "alert-circle"
			})
		end
	end

	local function shouldRunRuntime()
		return StaminaFeature.Enabled
			or StaminaFeature.DebugEnabled
			or (StaminaFeature.CaptureSession and StaminaFeature.CaptureSession.State ~= "completed")
	end

	local function ensureHeartbeatConnection()
		if StaminaFeature.HeartbeatConnection then
			return
		end

		StaminaFeature.HeartbeatConnection = RunService.Heartbeat:Connect(function()
			if shouldRunRuntime()
				and (os.clock() - StaminaFeature.LastStepAt) >= StaminaFeature.StepInterval then
				StaminaFeature:Step(false, false)
			end
		end)
	end

	local function disconnectHeartbeatIfIdle()
		if not shouldRunRuntime() and StaminaFeature.HeartbeatConnection then
			StaminaFeature.HeartbeatConnection:Disconnect()
			StaminaFeature.HeartbeatConnection = nil
		end
	end

	isLogicLocalCandidate = function(Candidate)
		return Candidate
			and Candidate.Promoted
			and Candidate.Category == "logic-local"
	end

	isFlagCandidate = function(Candidate)
		return Candidate
			and Candidate.Promoted
			and Candidate.Category == "flags"
	end

	isSpendCandidate = function(Candidate)
		return Candidate
			and Candidate.Promoted
			and Candidate.Category == "spend"
	end

	isDisplayCandidate = function(Candidate)
		return Candidate
			and (
				Candidate.Category == "display"
				or Candidate.Promoted == false
			)
	end

	isRuntimeFlagCandidate = function(Candidate)
		if not isFlagCandidate(Candidate) then
			return false
		end

		local NameLower = Candidate.NameLower or ""

		if NameLower == "nocooldown" then
			return false
		end

		return NameLower == "nostaminacost"
			or NameLower == "canusestamina"
			or NameLower == "hasstamina"
			or NameLower == "enoughstamina"
			or NameLower == "candash"
			or NameLower == "cansprint"
			or NameLower == "canrun"
			or NameLower == "canattack"
			or string.find(NameLower, "stamina", 1, true) ~= nil
	end

	local function hasStrongPrimarySiblingHandle(Candidate)
		if not Candidate or not Candidate.Handle then
			return false
		end

		for _, GroupName in ipairs({"Current", "Max"}) do
			for _, Entry in ipairs(StaminaFeature.Handles[GroupName]) do
				local PrimaryCandidate = Entry.Candidate

				if PrimaryCandidate
					and PrimaryCandidate ~= Candidate
					and isLogicLocalCandidate(PrimaryCandidate)
					and isStrongMainScriptStatsPrimaryAlias(PrimaryCandidate)
					and handlesShareScope(Candidate.Handle, PrimaryCandidate.Handle) then
					return true
				end
			end
		end

		return false
	end

	local function getRuntimeSupportPriority(Candidate, GroupName)
		if not Candidate then
			return nil
		end

		local NameLower = Candidate.NameLower or ""
		local Score = 0

		if NameLower == "issprinting" or NameLower == "offensive" then
			return nil
		end

		if Candidate.ExactAlias == true then
			Score = Score + 4
		end

		if Candidate.SourceKind == "instance"
			and isMainScriptStatsHandle(Candidate.Handle) then
			Score = Score + 3
		end

		if hasStrongPrimarySiblingHandle(Candidate) then
			Score = Score + 6
		end

		if GroupName == "Flags" then
			if NameLower == "nostaminacost" then
				Score = Score + 8
			elseif NameLower == "cansprint"
				or NameLower == "canrun"
				or NameLower == "candash"
				or NameLower == "canattack" then
				Score = Score + 2
			elseif string.find(NameLower, "stamina", 1, true) ~= nil then
				Score = Score + 3
			end
		elseif GroupName == "Spend" then
			if NameLower == "exhaustion"
				or NameLower == "exhausted"
				or NameLower == "fatigue"
				or NameLower == "fatigued"
				or NameLower == "breath"
				or NameLower == "outofbreath" then
				Score = Score + 9
			end

			if string.find(NameLower, "eevee", 1, true) ~= nil then
				Score = Score + 5
			end

			if string.find(NameLower, "deplete", 1, true) ~= nil
				or string.find(NameLower, "cost", 1, true) ~= nil
				or string.find(NameLower, "exhaust", 1, true) ~= nil then
				Score = Score + 3
			elseif string.find(NameLower, "stamina", 1, true) ~= nil then
				Score = Score + 2
			end
		end

		return Score > 0 and Score or nil
	end

	local function collectPreferredSupportEntries(GroupName, Predicate)
		local Group = StaminaFeature.Handles[GroupName]

		if type(Group) ~= "table" or type(Predicate) ~= "function" then
			return {}
		end

		if GroupName == "Flags" or GroupName == "Spend" then
			local ScopedEntries = {}

			for _, Entry in ipairs(Group) do
				local Candidate = Entry.Candidate

				if Predicate(Candidate) and hasStrongPrimarySiblingHandle(Candidate) then
					local Score = getRuntimeSupportPriority(Candidate, GroupName)

					if Score ~= nil then
						table.insert(ScopedEntries, {
							Entry = Entry,
							Score = Score
						})
					end
				end
			end

			if #ScopedEntries > 0 then
				table.sort(ScopedEntries, function(Left, Right)
					if Left.Score ~= Right.Score then
						return Left.Score > Right.Score
					end

					local LeftName = Left.Entry
						and Left.Entry.Candidate
						and (Left.Entry.Candidate.NameLower or "")
						or ""
					local RightName = Right.Entry
						and Right.Entry.Candidate
						and (Right.Entry.Candidate.NameLower or "")
						or ""

					return LeftName < RightName
				end)

				local Entries = {}
				local BestScore = ScopedEntries[1].Score
				local ScoreFloor = math.max(1, BestScore - 8)

				for _, Item in ipairs(ScopedEntries) do
					local Candidate = Item.Entry.Candidate
					local NameLower = Candidate and Candidate.NameLower or ""
					local IsKeyScopedName

					if GroupName == "Flags" then
						IsKeyScopedName = NameLower == "nostaminacost"
							or NameLower == "canusestamina"
							or NameLower == "hasstamina"
							or NameLower == "enoughstamina"
							or NameLower == "cansprint"
							or NameLower == "canrun"
							or NameLower == "candash"
							or NameLower == "canattack"
							or string.find(NameLower, "stamina", 1, true) ~= nil
					else
						IsKeyScopedName = string.find(NameLower, "exhaust", 1, true) ~= nil
							or string.find(NameLower, "fatigue", 1, true) ~= nil
							or string.find(NameLower, "breath", 1, true) ~= nil
							or string.find(NameLower, "eevee", 1, true) ~= nil
							or string.find(NameLower, "deplete", 1, true) ~= nil
					end

					if Item.Score >= ScoreFloor
						or (Candidate and Candidate.ExactAlias == true)
						or IsKeyScopedName then
						table.insert(Entries, Item.Entry)
					end
				end

				if #Entries > 0 then
					return Entries
				end
			end
		end

		local Entries = {}
		local BestScore = nil

		for _, Entry in ipairs(Group) do
			if Predicate(Entry.Candidate) then
				local Score = getRuntimeSupportPriority(Entry.Candidate, GroupName)

				if Score ~= nil then
					if BestScore == nil or Score > BestScore then
						BestScore = Score
						Entries = {Entry}
					elseif Score == BestScore then
						table.insert(Entries, Entry)
					end
				end
			end
		end

		if #Entries > 0 then
			return Entries
		end

		for _, Entry in ipairs(Group) do
			if Predicate(Entry.Candidate) then
				table.insert(Entries, Entry)
			end
		end

		return Entries
	end

	local function getPreferredRuntimeFlagEntries()
		return collectPreferredSupportEntries("Flags", isRuntimeFlagCandidate)
	end

	local function getPreferredRuntimeSpendEntries()
		return collectPreferredSupportEntries("Spend", isRuntimeSpendCandidate)
	end

	local function setSupportIssue(GroupName, Entry, ObservedValue, DesiredValue, Context)
		local Label = Entry and Entry.Candidate and getCandidateConsoleLabel(Entry.Candidate) or "none"

		StaminaFeature.LastSupportIssue = string.format(
			"%s:%s obs=%s want=%s ctx=%s",
			tostring(GroupName or "?"),
			Label,
			summarizeValue(ObservedValue),
			summarizeValue(DesiredValue),
			tostring(Context or "none")
		)
	end

	local function clearSupportIssue()
		StaminaFeature.LastSupportIssue = ""
	end

	isRuntimeSpendCandidate = function(Candidate)
		if not isSpendCandidate(Candidate) then
			return false
		end

		local NameLower = Candidate.NameLower or ""

		if string.find(NameLower, "eevee", 1, true) ~= nil then
			return hasStrongPrimarySiblingHandle(Candidate)
		end

		return Candidate.ExactAlias == true
			or string.find(NameLower, "stamina", 1, true) ~= nil
			or string.find(NameLower, "sprint", 1, true) ~= nil
			or string.find(NameLower, "run", 1, true) ~= nil
			or string.find(NameLower, "dash", 1, true) ~= nil
			or string.find(NameLower, "attack", 1, true) ~= nil
			or string.find(NameLower, "combat", 1, true) ~= nil
			or string.find(NameLower, "exhaust", 1, true) ~= nil
			or string.find(NameLower, "fatigue", 1, true) ~= nil
			or string.find(NameLower, "breath", 1, true) ~= nil
	end

	local function shouldMirrorDisplayCandidate(Candidate)
		if not isDisplayCandidate(Candidate) then
			return false
		end

		local NameLower = Candidate.NameLower or ""

		return (Candidate.ExactAlias == true and (Candidate.Group == "Current" or Candidate.Group == "Max"))
			or isStaminaDisplayName(NameLower)
	end

	local function hasPrimaryHandles()
		return #StaminaFeature.Handles.Current > 0 or #StaminaFeature.Handles.Max > 0
	end

	local function hasLogicPrimaryHandles()
		for _, Entry in ipairs(StaminaFeature.Handles.Current) do
			if isLogicLocalCandidate(Entry.Candidate) then
				return true
			end
		end

		for _, Entry in ipairs(StaminaFeature.Handles.Max) do
			if isLogicLocalCandidate(Entry.Candidate) then
				return true
			end
		end

		return false
	end

	local function hasSupportHandles()
		return #getPreferredRuntimeFlagEntries() > 0
			or #getPreferredRuntimeSpendEntries() > 0
	end

	local function hasHandles()
		return #StaminaFeature.Handles.Current > 0
			or #StaminaFeature.Handles.Max > 0
			or #StaminaFeature.Handles.Flags > 0
			or #StaminaFeature.Handles.Spend > 0
	end

	local function inferRuntimeProfile(Metrics)
		local Session = StaminaFeature.CaptureSession

		if Session and Session.State ~= "completed" and Session.ActionValid and CaptureProfiles[Session.Profile] then
			return Session.Profile
		end

		if Metrics and Metrics.VelocityMagnitude > math.max((Metrics.WalkSpeed or 0) * 1.6, 20) then
			return "Dash"
		end

		if Metrics and (
			Metrics.MoveMagnitude > 0.35
			or Metrics.VelocityMagnitude > math.max((Metrics.WalkSpeed or 0) * 0.65, 7)
		) then
			return "Run"
		end

		return "Free"
	end

	local function hasRecentExternalPressure()
		local RecentCutoff = os.clock() - 1.25

		for _, Group in ipairs({"Current", "Max", "Flags", "Spend"}) do
			for _, Entry in ipairs(StaminaFeature.Handles[Group]) do
				local Candidate = Entry.Candidate

				if Candidate
					and Candidate.ExternalWriteCount > 0
					and (Candidate.LastChangeTime or 0) >= RecentCutoff then
					return true
				end
			end
		end

		return false
	end

	local function noteVerifiedLogic()
		StaminaFeature.LastEffectiveLogicAt = os.clock()

		for _, Group in ipairs({"Current", "Max"}) do
			for _, Entry in ipairs(StaminaFeature.Handles[Group]) do
				local Candidate = Entry.Candidate

				if isLogicLocalCandidate(Candidate) then
					Candidate.FailedVerificationCount = 0
					Candidate.LastFailureReason = nil
				end
			end
		end
	end

	local function demoteIneffectiveLogicCandidates(Reason)
		local Demoted = 0

		for _, Group in ipairs({"Current", "Max"}) do
			for _, Entry in ipairs(StaminaFeature.Handles[Group]) do
				local Candidate = Entry.Candidate

				if isLogicLocalCandidate(Candidate) then
					Candidate.FailedVerificationCount = (Candidate.FailedVerificationCount or 0) + 1
					Candidate.LastFailureReason = Reason

					local FailureLimit = Candidate.SourceKind == "instance" and 3 or 2

					if Candidate.RuntimePinned == true
						and isStrongMainScriptStatsPrimaryAlias(Candidate) then
						FailureLimit = math.max(FailureLimit, 6)
					end

					if Candidate.FailedVerificationCount >= FailureLimit then
						Candidate.BootstrapBlocked = true
						normalizeCandidate(Candidate)
						Demoted = Demoted + 1
					end
				end
			end
		end

		return Demoted
	end

	local function requestFailureRecovery(Profile)
		if not StaminaFeature.Enabled then
			return false
		end

		local Now = os.clock()

		if (Now - StaminaFeature.LastRecoveryAt) < StaminaFeature.RecoveryCooldown then
			return false
		end

		StaminaFeature.LastRecoveryAt = Now
		StaminaFeature.LastResolveAt = 0
		StaminaFeature.LastGcResolveAt = 0
		StaminaFeature.DropEventCount = 0

		if CaptureProfiles[Profile] then
			StaminaFeature.DebugProfile = Profile
		end

		requestFailureCapture(Profile)
		scheduleGcResolve()
		scheduleStep()

		return true
	end

	local function refreshCaptureWindow(Session)
		if not Session then
			return
		end

		for _, Candidate in ipairs(StaminaFeature.CandidateOrder) do
			if Candidate.Active and Candidate.Handle then
				local Value = readHandle(Candidate.Handle)

				recordCaptureCandidateValue(Candidate, Value, "read")
			end
		end
	end

	local function buildSummaryLine(Candidate, Observation)
		return string.format(
			"%s [%s] score=%.1f chg=%d ext=%d delta=%s",
			getCandidateConsoleLabel(Candidate),
			Candidate.Category,
			Candidate.Score or 0,
			Observation.TotalChanges or 0,
			Observation.ExternalWrites or 0,
			formatNumber(Observation.DeltaMagnitude or 0)
		)
	end

	local function getCandidateSummaryLabel(Candidate)
		if not Candidate then
			return "none"
		end

		return string.format(
			"%s [%s/%s]",
			getCandidateConsoleLabel(Candidate),
			tostring(Candidate.Category or "unknown"),
			tostring(Candidate.SourceKind or "unknown")
		)
	end

	local function finalizeCaptureSession()
		local Session = StaminaFeature.CaptureSession

		if not Session or Session.State == "completed" then
			return
		end

		local function isSupportedMainScriptStatsPrimary(Candidate, Observation)
			if not Candidate
				or not Observation
				or Candidate.SourceKind ~= "instance"
				or not Candidate.ExactAlias
				or not isMainScriptStatsHandle(Candidate.Handle)
				or (Candidate.Group ~= "Current" and Candidate.Group ~= "Max") then
				return false
			end

			if not isStrongMainScriptStatsPrimaryAlias(Candidate) then
				return false
			end

			local HasStrongMovement = (Observation.TotalChanges or 0) >= 8
				or (Observation.DeltaMagnitude or 0) >= 10
				or (Candidate.Score or 0) >= 8

			if not HasStrongMovement then
				return false
			end

			local HasStrongRuntimeSignal = Candidate.RuntimePinned == true
				or (Observation.ExternalWrites or 0) >= 2
				or (Candidate.ExternalWriteCount or 0) >= 4

			if HasStrongRuntimeSignal then
				return true
			end

			if Session.ActionValid ~= true then
				return false
			end

			local SupportWeight = 0

			for _, Sibling in ipairs(StaminaFeature.CandidateOrder) do
				if Sibling ~= Candidate
					and handlesShareScope(Candidate.Handle, Sibling.Handle) then
					local SiblingObservation = Session.Observations[Sibling.RegistryKey]

					if SiblingObservation then
						if Sibling.Group == "Spend" then
							if Sibling.ExactAlias
								or containsSpend(Sibling.NameLower or "")
								or (SiblingObservation.TotalChanges or 0) >= 1
								or (SiblingObservation.DeltaMagnitude or 0) > 0.25 then
								SupportWeight = SupportWeight + 2
							end
						elseif Sibling.Group == "Flags" then
							if Sibling.ExactAlias or (SiblingObservation.TotalChanges or 0) >= 1 then
								SupportWeight = SupportWeight + 1
							end
						elseif Candidate.Group == "Max"
							and Sibling.Group == "Current"
							and Sibling.ExactAlias
							and (
								(SiblingObservation.TotalChanges or 0) >= 4
								or (SiblingObservation.DeltaMagnitude or 0) >= 5
							) then
							SupportWeight = SupportWeight + 2
						elseif Candidate.Group == "Current"
							and Sibling.Group == "Max"
							and Sibling.ExactAlias then
							SupportWeight = SupportWeight + 1
						end
					end
				end
			end

			return SupportWeight >= 2
		end

		local ProfileFamily = getProfileFamily(Session.Profile)
		local Snapshot = getDiagnosticSnapshot()
		local PromotedLogic = {}
		local DisplaySuspects = {}
		local HiddenPrimarySuspects = {}
		local RemoteSuspects = {}
		local PrimaryLogicCount = 0
		local SupportLogicCount = 0

		for _, Candidate in ipairs(StaminaFeature.CandidateOrder) do
			local Observation = Session.Observations[Candidate.RegistryKey]

			if Observation then
				local Score = (Candidate.Confidence or 0) / 35
				local BlockPrimaryPromotion = Candidate.SourceKind == "instance"
					and isMainScriptStatsHandle(Candidate.Handle)
				local AllowBlockedPrimaryPromotion = BlockPrimaryPromotion
					and isSupportedMainScriptStatsPrimary(Candidate, Observation)

				if Candidate.Group == "Flags" then
					Score = Score + 3
				elseif Candidate.Group == "Spend" then
					Score = Score + 4
				end

				Score = Score + math.min(Observation.TotalChanges or 0, 4)
				Score = Score + math.min((Observation.ExternalWrites or 0) * 2, 6)

				if (Observation.DeltaMagnitude or 0) > 0.5 then
					Score = Score + 2
				end

				if Candidate.SourceKind == "table" then
					Score = Score + 1
				end

				local IsHiddenLocalPrimary = (Candidate.Group == "Current" or Candidate.Group == "Max")
					and Candidate.SourceKind ~= "instance"
					and (Candidate.Confidence or 0) >= 145
					and (
						(Observation.TotalChanges or 0) >= 2
						or (Observation.DeltaMagnitude or 0) >= 1
					)

				if ProfileFamily ~= nil and Candidate.Family == ProfileFamily then
					Score = Score + 2
				end

				if IsHiddenLocalPrimary then
					Score = Score + 2

					if Candidate.SourceKind == "upvalue" then
						Score = Score + 2
					elseif Candidate.SourceKind == "env" or Candidate.SourceKind == "table" then
						Score = Score + 1
					end

					if isInterestingLogicName(Candidate.NameLower or "") then
						Score = Score + 2
					end
				end

				if (Candidate.Group == "Current" or Candidate.Group == "Max")
					and (
						Candidate.NameLower == "stamina"
						or Candidate.NameLower == "staminainstat"
						or Candidate.NameLower == "maxstamina"
					)
					and (Observation.ExternalWrites or 0) == 0
					and (Observation.TotalChanges or 0) <= 1 then
					Score = Score - 4
				end

				Candidate.Score = math.max(Candidate.Score or 0, Score)

				if IsHiddenLocalPrimary then
					table.insert(HiddenPrimarySuspects, {
						Candidate = Candidate,
						Observation = Observation,
						Score = Score
					})
				end

				if Candidate.Group == "Flags" then
					if Score >= 4 then
						promoteCandidate(Candidate, "flags", Score, "capture_flags")
						table.insert(PromotedLogic, {
							Candidate = Candidate,
							Observation = Observation
						})
						SupportLogicCount = SupportLogicCount + 1
					end
				elseif Candidate.Group == "Spend" then
					if Score >= 4 then
						promoteCandidate(Candidate, "spend", Score, "capture_spend")
						table.insert(PromotedLogic, {
							Candidate = Candidate,
							Observation = Observation
						})
						SupportLogicCount = SupportLogicCount + 1
					end
				elseif (not BlockPrimaryPromotion or AllowBlockedPrimaryPromotion)
					and (
						Score >= 6
						or (Observation.ExternalWrites or 0) >= 2
						or AllowBlockedPrimaryPromotion
					) then
					promoteCandidate(
						Candidate,
						"logic-local",
						Score + (AllowBlockedPrimaryPromotion and 1.5 or 0),
						AllowBlockedPrimaryPromotion and "capture_stats_logic" or "capture_logic"
					)
					table.insert(PromotedLogic, {
						Candidate = Candidate,
						Observation = Observation
					})
					PrimaryLogicCount = PrimaryLogicCount + 1
				else
					normalizeCandidate(Candidate)

					if Score >= 1 then
						table.insert(DisplaySuspects, {
							Candidate = Candidate,
							Observation = Observation
						})
					end
				end
			end
		end

		table.sort(PromotedLogic, function(Left, Right)
			return (Left.Candidate.Score or 0) > (Right.Candidate.Score or 0)
		end)

		table.sort(DisplaySuspects, function(Left, Right)
			return (Left.Candidate.Score or 0) > (Right.Candidate.Score or 0)
		end)

		table.sort(HiddenPrimarySuspects, function(Left, Right)
			if (Left.Score or 0) ~= (Right.Score or 0) then
				return (Left.Score or 0) > (Right.Score or 0)
			end

			return (Left.Candidate.Confidence or 0) > (Right.Candidate.Confidence or 0)
		end)

		if Session.ActionValid
			and (Snapshot.DisplayCurrentCount or 0) >= 20
			and #HiddenPrimarySuspects > 0 then
			local PromotedHidden = 0

			for _, Entry in ipairs(HiddenPrimarySuspects) do
				local Candidate = Entry.Candidate

				if Candidate.Category ~= "logic-local" then
					promoteCandidate(Candidate, "logic-local", (Entry.Score or 0) + 3, "capture_hidden_logic")
					table.insert(PromotedLogic, {
						Candidate = Candidate,
						Observation = Entry.Observation
					})
					PrimaryLogicCount = PrimaryLogicCount + 1
					PromotedHidden = PromotedHidden + 1
				end

				if PromotedHidden >= 2 then
					break
				end
			end

			table.sort(PromotedLogic, function(Left, Right)
				return (Left.Candidate.Score or 0) > (Right.Candidate.Score or 0)
			end)
		end

		local PrimaryCandidate = nil
		local FlagCandidate = nil
		local SpendCandidate = nil

		for _, Entry in ipairs(PromotedLogic) do
			local Candidate = Entry.Candidate

			if not PrimaryCandidate and Candidate.Category == "logic-local" then
				PrimaryCandidate = Candidate
			end

			if not FlagCandidate and Candidate.Category == "flags" then
				FlagCandidate = Candidate
			end

			if not SpendCandidate and Candidate.Category == "spend" then
				SpendCandidate = Candidate
			end
		end

		for _, Candidate in ipairs(StaminaFeature.RemoteCandidateOrder) do
			local Observation = Session.RemoteObservations[Candidate.RegistryKey]

			if Observation then
				Candidate.Score = math.max(Candidate.Score or 0, Observation.Count * 2)

				if PrimaryLogicCount == 0 and Session.ActionValid and Observation.Count >= 2 then
					Candidate.CaptureHits = (Candidate.CaptureHits or 0) + 1

					if Candidate.CaptureHits >= 2 then
						Candidate.Promoted = true
					end
				end

				table.insert(RemoteSuspects, {
					Candidate = Candidate,
					Observation = Observation
				})
			end
		end

		table.sort(RemoteSuspects, function(Left, Right)
			return (Left.Observation.Count or 0) > (Right.Observation.Count or 0)
		end)

		local Lines = {
			string.format("PrimaryCandidate: %s", getCandidateSummaryLabel(PrimaryCandidate)),
			string.format("FlagCandidate: %s", getCandidateSummaryLabel(FlagCandidate))
		}

		if not PrimaryCandidate and #DisplaySuspects > 0 then
			for Index = 1, math.min(#DisplaySuspects, 2) do
				table.insert(
					Lines,
					string.format(
						"DisplayCandidate%d: %s",
						Index,
						buildSummaryLine(DisplaySuspects[Index].Candidate, DisplaySuspects[Index].Observation)
					)
				)
			end
		end

		table.insert(Lines, string.format("SpendCandidate: %s", getCandidateSummaryLabel(SpendCandidate)))
		table.insert(Lines, string.format("RemoteCalls: %d", Session.RemoteCallCount or 0))

		if #RemoteSuspects > 0 then
			local Observation = RemoteSuspects[1].Observation
			local Candidate = RemoteSuspects[1].Candidate

			table.insert(Lines, string.format(
				"RemoteCandidate1: %s [%s] count=%d args=%s",
				Candidate.Name,
				Candidate.Method,
				Observation.Count or 0,
				Observation.LastArgsSummary or ""
			))
		end

		table.insert(Lines, string.format("LastProfile: %s", Session.Profile))
		table.insert(Lines, string.format("ActionValid: %s", tostring(Session.ActionValid)))
		table.insert(Lines, string.format("MaxSpeed: %s", formatNumber(Session.MaxSpeed or 0)))
		table.insert(Lines, string.format("PromotedPrimary: %d", PrimaryLogicCount))
		table.insert(Lines, string.format("PromotedSupport: %d", SupportLogicCount))

		if #PromotedLogic > 0 then
			table.insert(Lines, "TopPromoted:")

			for Index = 1, math.min(#PromotedLogic, 4) do
				table.insert(Lines, buildSummaryLine(PromotedLogic[Index].Candidate, PromotedLogic[Index].Observation))
			end
		end

		if PrimaryCandidate and #DisplaySuspects > 0 then
			table.insert(Lines, "DisplaySuspects:")

			for Index = 1, math.min(#DisplaySuspects, 3) do
				table.insert(Lines, buildSummaryLine(DisplaySuspects[Index].Candidate, DisplaySuspects[Index].Observation))
			end
		end

		if #RemoteSuspects > 0 then
			table.insert(Lines, "RemoteSuspects:")

			for Index = 1, math.min(#RemoteSuspects, 3) do
				local Observation = RemoteSuspects[Index].Observation
				local Candidate = RemoteSuspects[Index].Candidate

				table.insert(Lines, string.format(
					"%s [%s] count=%d args=%s",
					Candidate.Name,
					Candidate.Method,
					Observation.Count or 0,
					Observation.LastArgsSummary or ""
				))
			end
		end

		StaminaFeature.LastCaptureSummary = Lines
		Session.State = "completed"

		if PrimaryLogicCount > 0 and Session.ActionValid then
			noteVerifiedLogic()
		end

		refreshStatusSummary()

		if StaminaFeature.Enabled then
			if PrimaryLogicCount > 0 then
				notifyDiagnosticSummary("Stamina capture found logic candidates.", 4, "search")
			elseif SupportLogicCount > 0 then
				notifyDiagnosticSummary("Stamina capture found control candidates only.", 4, "search")
			else
				notifyDiagnosticSummary("Stamina capture still found no logic handles.", 4, "alert-circle")
			end
		end
	end

	local function advanceCaptureSession()
		local Session = StaminaFeature.CaptureSession

		if not Session or Session.State == "completed" then
			return
		end

		local Now = os.clock()
		local Metrics = getCharacterMetrics()

		if Metrics.VelocityMagnitude > (Session.MaxSpeed or 0) then
			Session.MaxSpeed = Metrics.VelocityMagnitude
		end

		if Metrics.MoveMagnitude > (Session.MaxMoveMagnitude or 0) then
			Session.MaxMoveMagnitude = Metrics.MoveMagnitude
		end

		if Metrics.ToolEquipped then
			Session.ToolSeen = true
		end

		if Session.Profile == "Free" then
			Session.ActionValid = true
		elseif Session.Profile == "Run" then
			if Metrics.MoveMagnitude > 0.35
				or Metrics.VelocityMagnitude > math.max(Metrics.WalkSpeed * 0.65, 7) then
				Session.ActionValid = true
			end
		elseif Session.Profile == "Dash" then
			if Metrics.VelocityMagnitude > math.max(Metrics.WalkSpeed * 1.6, 20) then
				Session.ActionValid = true
			end
		elseif Session.Profile == "Attack" then
			if Metrics.ToolEquipped
				or (Session.AttackSignalCount or 0) > 0
				or (Session.RemoteCallCount or 0) > 0 then
				Session.ActionValid = true
			end
		end

		if Session.State == "baseline" and Now >= Session.BaselineEndsAt then
			Session.State = "active"
			refreshCaptureWindow(Session)
		elseif Session.State == "active" and Now >= Session.EndsAt then
			finalizeCaptureSession()
		end
	end

	local function clearCaptureSessionState()
		StaminaFeature.CaptureSession = nil
		table.clear(StaminaFeature.LastCaptureSummary)
	end

	local function resetCaptureState(PreservePromotedLogic)
		clearCaptureSessionState()
		StaminaFeature.LastFailureCaptureAt = 0
		StaminaFeature.LastRecoveryAt = 0

		for _, Candidate in ipairs(StaminaFeature.RemoteCandidateOrder) do
			Candidate.Promoted = false
			Candidate.CaptureHits = 0
			Candidate.Score = 0
		end

		for _, Candidate in ipairs(StaminaFeature.CandidateOrder) do
			Candidate.Score = 0
			Candidate.CaptureHits = 0
			Candidate.FailedVerificationCount = 0
			Candidate.BootstrapBlocked = false
			Candidate.LastFailureReason = nil

			if PreservePromotedLogic
				and Candidate.Group ~= "Flags"
				and Candidate.Group ~= "Spend"
				and Candidate.Category == "logic-local"
				and Candidate.Promoted then
				promoteCandidate(Candidate, "logic-local", 6, Candidate.PromotionReason or "preserved_logic")
			elseif Candidate.Group == "Flags" then
				if Candidate.ExactAlias and Candidate.Confidence >= 85 then
					promoteCandidate(Candidate, "flags", 5, "exact_flag_bootstrap")
				else
					normalizeCandidate(Candidate)
				end
			elseif Candidate.Group == "Spend" then
				if Candidate.ExactAlias and Candidate.Confidence >= 85 then
					promoteCandidate(Candidate, "spend", 5, "exact_spend_bootstrap")
				else
					normalizeCandidate(Candidate)
				end
			else
				normalizeCandidate(Candidate)
			end
		end
	end

	scheduleGcResolve = function()
		if not shouldRunRuntime()
			or StaminaFeature.GcResolveQueued
			or type(getgc) ~= "function" then
			return
		end

		local Now = os.clock()

		if (Now - StaminaFeature.LastGcResolveAt) < StaminaFeature.GcResolveInterval then
			return
		end

		StaminaFeature.GcResolveQueued = true

		task.delay(0.6, function()
			StaminaFeature.GcResolveQueued = false

			if shouldRunRuntime() then
				StaminaFeature:Step(true, true)
			end
		end)
	end

	scheduleStep = function()
		if not shouldRunRuntime() or StaminaFeature.StepQueued then
			return
		end

		StaminaFeature.StepQueued = true

		task.defer(function()
			StaminaFeature.StepQueued = false

			if shouldRunRuntime() then
				StaminaFeature:Step(false, false)
			end
		end)
	end

	local function connectHandleSignals()
		clearHandleSignals()

		local Connected = {}
		local function onTrackedHandleChanged()
			if not shouldRunRuntime() then
				return
			end

			if StaminaFeature.Enabled and not StaminaFeature.StepBusy then
				StaminaFeature:Step(false, false)
				return
			end

			scheduleStep()
		end

		local function attach(Entry)
			if not Entry or Connected[Entry.Key] then
				return
			end

			if Entry.Handle.Kind == "value" then
				local Success, Connection = pcall(function()
					return Entry.Handle.Instance:GetPropertyChangedSignal("Value"):Connect(onTrackedHandleChanged)
				end)

				if Success and Connection then
					table.insert(StaminaFeature.HandleSignals, Connection)
					Connected[Entry.Key] = true
				end

				return
			end

			if Entry.Handle.Kind == "attribute" then
				local Success, Connection = pcall(function()
					return Entry.Handle.Instance:GetAttributeChangedSignal(Entry.Handle.Attribute):Connect(onTrackedHandleChanged)
				end)

				if Success and Connection then
					table.insert(StaminaFeature.HandleSignals, Connection)
					Connected[Entry.Key] = true
				end
			end
		end

		for _, Group in pairs(StaminaFeature.Handles) do
			for _, Entry in ipairs(Group) do
				attach(Entry)
			end
		end
	end

	local function resolveHandles(ForceRefresh, IncludeGc)
		local Now = os.clock()

		if not ForceRefresh and (Now - StaminaFeature.LastResolveAt) < StaminaFeature.ResolveInterval then
			return
		end

		clearHandles()
		clearCandidateActivity()

		local EntryMaps = {
			Current = {},
			Max = {},
			Flags = {},
			Spend = {}
		}

		local function hasRecordedPrimary()
			return next(EntryMaps.Current) ~= nil or next(EntryMaps.Max) ~= nil
		end

		local function hasRecordedLogicPrimary()
			for _, Entry in pairs(EntryMaps.Current) do
				if isLogicLocalCandidate(Entry.Candidate) then
					return true
				end
			end

			for _, Entry in pairs(EntryMaps.Max) do
				if isLogicLocalCandidate(Entry.Candidate) then
					return true
				end
			end

			return false
		end

		local function recordHandle(GroupName, Name, NameLower, Handle, Value, Confidence, SourceKind)
			if not GroupName or not isUsefulValue(GroupName, Value) then
				return
			end

			local IsExactAlias = Lookups[GroupName] and Lookups[GroupName][NameLower] == true or false
			local AllowHiddenTablePrimary = SourceKind == "table"
				and (GroupName == "Current" or GroupName == "Max")
				and (Confidence or 0) >= 110

			if SourceKind == "table"
				and string.find(NameLower, "stamina", 1, true) == nil
				and not IsExactAlias
				and not AllowHiddenTablePrimary then
				return
			end

			if GroupName == "Spend"
				and string.find(NameLower, "stamina", 1, true) == nil
				and not IsExactAlias
				and (Confidence or 0) < 60 then
				return
			end

			local Key = getHandleKey(Handle)
			local Existing = EntryMaps[GroupName][Key]

			if Existing and Existing.Confidence >= (Confidence or 0) then
				return
			end

			local Candidate = upsertLocalCandidate(GroupName, Name, NameLower, Handle, Value, Confidence, SourceKind)

			EntryMaps[GroupName][Key] = {
				Key = Key,
				Name = Name,
				NameLower = NameLower,
				Family = getFamily(NameLower),
				Handle = Handle,
				Candidate = Candidate,
				Confidence = Confidence or 0,
				SourceKind = SourceKind or "instance"
			}
		end

		local function visitInstance(Instance)
			if not isLocalRelatedInstance(Instance) then
				return
			end

			local Confidence = getInstanceConfidence(Instance)

			if Instance:IsA("ValueBase") then
				local GroupName, NameLower = classifyName(Instance.Name)

				if GroupName then
					recordHandle(GroupName, Instance.Name, NameLower, createValueHandle(Instance), Instance.Value, Confidence, "instance")
				end
			end

			for AttributeName, Value in pairs(Instance:GetAttributes()) do
				local GroupName, NameLower = classifyName(AttributeName)

				if GroupName then
					recordHandle(GroupName, AttributeName, NameLower, createAttributeHandle(Instance, AttributeName), Value, Confidence, "instance")
				end
			end
		end

		local function visitTable(TableValue)
			if not tableBelongsToLocalPlayer(TableValue) then
				return
			end

			local Success = pcall(function()
				for Key, Value in pairs(TableValue) do
					if type(Key) == "string" then
						local GroupName, NameLower = classifyName(Key)

						if GroupName then
							recordHandle(GroupName, Key, NameLower, createTableHandle(TableValue, Key), Value, 15, "table")
						end
					end
				end
			end)

			if not Success then
				return
			end
		end

		local function shouldRecurseEnvTable(KeyName, TableValue, Depth)
			if type(TableValue) ~= "table" or Depth >= 2 then
				return false
			end

			if tableBelongsToLocalPlayer(TableValue) then
				return true
			end

			if type(KeyName) == "string" and isInterestingLogicName(string.lower(KeyName)) then
				return true
			end

			local Hits = 0
			local Scanned = 0
			local Success = pcall(function()
				for InnerKey in pairs(TableValue) do
					Scanned = Scanned + 1

					if type(InnerKey) == "string" then
						local InnerKeyLower = string.lower(InnerKey)
						local GroupName = classifyName(InnerKey)

						if GroupName ~= nil or isInterestingLogicName(InnerKeyLower) then
							Hits = Hits + 1
						end
					end

					if Scanned >= 24 then
						break
					end
				end
			end)

			return Success and Hits > 0
		end

		local function appendScopeText(BaseScopeTextLower, ExtraText)
			local Base = type(BaseScopeTextLower) == "string" and BaseScopeTextLower or ""
			local Extra = type(ExtraText) == "string" and string.lower(ExtraText) or ""

			if Base == "" then
				return Extra
			end

			if Extra == "" then
				return Base
			end

			return Base .. " " .. Extra
		end

		local function visitEnvTable(TableValue, Confidence, Depth, Visited, ScopeTextLower)
			if type(TableValue) ~= "table" then
				return
			end

			Visited = Visited or {}

			if Visited[TableValue] then
				return
			end

			Visited[TableValue] = true

			local Scanned = 0
			local Success = pcall(function()
				for Key, Value in pairs(TableValue) do
					Scanned = Scanned + 1

					if type(Key) == "string" then
						local GroupName, NameLower = inferContextGroup(Key, Value, ScopeTextLower)

						if GroupName then
							recordHandle(GroupName, Key, NameLower, createTableHandle(TableValue, Key), Value, Confidence, "env")
						end

						if type(Value) == "table"
							and shouldRecurseEnvTable(Key, Value, Depth) then
							visitEnvTable(
								Value,
								math.max((Confidence or 0) - 8, 80),
								Depth + 1,
								Visited,
								appendScopeText(ScopeTextLower, Key)
							)
						end
					elseif type(Value) == "table"
						and Depth == 0
						and shouldRecurseEnvTable(nil, Value, Depth) then
						visitEnvTable(
							Value,
							math.max((Confidence or 0) - 8, 80),
							Depth + 1,
							Visited,
							ScopeTextLower
						)
					end

					if Scanned >= 64 then
						break
					end
				end
			end)

			if not Success then
				return
			end
		end

		local function visitScriptEnvironments()
			if type(getsenv) ~= "function" then
				return
			end

			local MainScript = findMainScript()

			if not MainScript then
				return
			end

			local Seen = {}

			local function tryVisitScript(ScriptInstance, Confidence)
				if not ScriptInstance or Seen[ScriptInstance] then
					return
				end

				Seen[ScriptInstance] = true

				local Success, EnvironmentTable = pcall(getsenv, ScriptInstance)

				if Success and type(EnvironmentTable) == "table" then
					visitEnvTable(
						EnvironmentTable,
						Confidence or 135,
						0,
						{},
						string.lower(table.concat({
							tostring(ScriptInstance.Name or ""),
							tostring(ScriptInstance.Parent and ScriptInstance.Parent.Name or ""),
							tostring(MainScript and MainScript.Name or "")
						}, " "))
					)
				end
			end

			tryVisitScript(MainScript, 140)

			for _, Descendant in ipairs(MainScript:GetDescendants()) do
				local IsScript = Descendant:IsA("LocalScript")
					or Descendant:IsA("ModuleScript")
					or Descendant:IsA("Script")

				if IsScript then
					local NameLower = string.lower(Descendant.Name)
					local Confidence = 130

					if Descendant.Name == "CRnInput" then
						Confidence = 155
					elseif isInterestingLogicName(NameLower) then
						Confidence = 145
					end

					tryVisitScript(Descendant, Confidence)
				end
			end
		end

		local function enumerateFunctionUpvalues(FunctionValue)
			local Entries = {}

			if type(FunctionValue) ~= "function" then
				return Entries
			end

			if type(debug) == "table" and type(debug.getupvalue) == "function" then
				for Index = 1, 64 do
					local Success, Name, Value = pcall(debug.getupvalue, FunctionValue, Index)

					if not Success or Name == nil then
						break
					end

					table.insert(Entries, {
						Index = Index,
						Name = type(Name) == "string" and Name or tostring(Name),
						Value = Value
					})
				end

				if #Entries > 0 then
					return Entries
				end
			end

			if type(getupvalues) == "function" then
				local Success, Upvalues = pcall(getupvalues, FunctionValue)

				if Success and type(Upvalues) == "table" then
					for Index, Value in pairs(Upvalues) do
						table.insert(Entries, {
							Index = type(Index) == "number" and Index or (#Entries + 1),
							Name = tostring(Index),
							Value = Value
						})
					end
				end
			end

			return Entries
		end

		local function visitFunctionUpvalues(FunctionValue, Confidence, VisitedTables)
			local Upvalues = enumerateFunctionUpvalues(FunctionValue)
			local Info = getFunctionInfo(FunctionValue)
			local FunctionScopeTextLower = string.lower(table.concat({
				tostring(Info and Info.name or ""),
				tostring(Info and Info.source or ""),
				tostring(Info and Info.short_src or "")
			}, " "))

			for _, Upvalue in ipairs(Upvalues) do
				local UpvalueName = Upvalue.Name
				local UpvalueValue = Upvalue.Value
				local GroupName, NameLower = inferContextGroup(UpvalueName, UpvalueValue, FunctionScopeTextLower)

				if GroupName then
					recordHandle(
						GroupName,
						UpvalueName,
						NameLower,
						createUpvalueHandle(FunctionValue, Upvalue.Index, UpvalueName),
						UpvalueValue,
						Confidence,
						"upvalue"
					)
				end

				if type(UpvalueValue) == "table"
					and (
						tableBelongsToLocalPlayer(UpvalueValue)
						or isInterestingLogicName(string.lower(tostring(UpvalueName)))
					) then
					visitEnvTable(
						UpvalueValue,
						math.max((Confidence or 0) - 6, 90),
						0,
						VisitedTables,
						appendScopeText(FunctionScopeTextLower, tostring(UpvalueName or ""))
					)
				end
			end
		end

		local function visitGcFunctions()
			if type(getgc) ~= "function" then
				return
			end

			local Success, Objects = pcall(function()
				return getgc(true)
			end)

			if not Success or type(Objects) ~= "table" then
				Success, Objects = pcall(getgc)
			end

			if not Success or type(Objects) ~= "table" then
				return
			end

			local VisitedFunctions = {}
			local VisitedTables = {}

			for _, Object in ipairs(Objects) do
				if type(Object) == "function" and not VisitedFunctions[Object] then
					VisitedFunctions[Object] = true

					if type(isexecutorclosure) ~= "function" or not isexecutorclosure(Object) then
						local Confidence = getFunctionScanConfidence(Object)

						if Confidence > 0 then
							visitFunctionUpvalues(Object, Confidence, VisitedTables)
						end
					end
				end
			end
		end

		local function visitRoots(Roots)
			for _, Root in ipairs(Roots) do
				visitInstance(Root)

				for _, Descendant in ipairs(Root:GetDescendants()) do
					visitInstance(Descendant)
				end
			end
		end

		inferContextGroup = function(Name, Value, ScopeTextLower)
			local GroupName, NameLower = classifyName(Name)

			if GroupName then
				return GroupName, NameLower
			end

			if type(Name) ~= "string" or Name == "" then
				return nil, nil
			end

			NameLower = string.lower(Name)

			if string.find(NameLower, "health", 1, true) ~= nil
				or string.find(NameLower, "adrenaline", 1, true) ~= nil
				or string.find(NameLower, "mana", 1, true) ~= nil
				or string.find(NameLower, "energy", 1, true) ~= nil
				or string.find(NameLower, "shield", 1, true) ~= nil
				or string.find(NameLower, "hunger", 1, true) ~= nil
				or string.find(NameLower, "thirst", 1, true) ~= nil
				or string.find(NameLower, "walk", 1, true) ~= nil
				or string.find(NameLower, "speed", 1, true) ~= nil
				or string.find(NameLower, "jump", 1, true) ~= nil
				or string.find(NameLower, "ping", 1, true) ~= nil then
				return nil, NameLower
			end

			local NumericValue = toNumber(Value)
			local ValueType = typeof(Value)

			if NumericValue == nil and ValueType ~= "boolean" then
				return nil, NameLower
			end

			if type(ScopeTextLower) ~= "string"
				or ScopeTextLower == ""
				or (
					not isInterestingLogicName(ScopeTextLower)
					and string.find(ScopeTextLower, "cooldown", 1, true) == nil
					and string.find(ScopeTextLower, "cost", 1, true) == nil
				) then
				return nil, NameLower
			end

			if ValueType == "boolean" then
				return "Flags", NameLower
			end

			if string.find(NameLower, "max", 1, true) ~= nil
				or string.find(NameLower, "limit", 1, true) ~= nil
				or string.find(NameLower, "cap", 1, true) ~= nil then
				return "Max", NameLower
			end

			if containsSpend(NameLower) then
				return "Spend", NameLower
			end

			if string.find(NameLower, "timer", 1, true) ~= nil
				or string.find(NameLower, "delay", 1, true) ~= nil
				or string.find(NameLower, "cool", 1, true) ~= nil then
				return "Spend", NameLower
			end

			if NumericValue ~= nil and isStaminaDisplayName(NameLower) then
				return "Current", NameLower
			end

			if NumericValue ~= nil
				and (
					string.find(ScopeTextLower, "nostaminacost", 1, true) ~= nil
					or string.find(ScopeTextLower, "eevee", 1, true) ~= nil
					or string.find(ScopeTextLower, "deplete", 1, true) ~= nil
					or string.find(ScopeTextLower, "exhaust", 1, true) ~= nil
					or string.find(ScopeTextLower, "fatigue", 1, true) ~= nil
					or string.find(ScopeTextLower, "breath", 1, true) ~= nil
					or string.find(ScopeTextLower, "tired", 1, true) ~= nil
					or string.find(ScopeTextLower, "winded", 1, true) ~= nil
					or string.find(ScopeTextLower, "stamina", 1, true) ~= nil
				)
				and string.find(NameLower, "max", 1, true) == nil
				and string.find(NameLower, "limit", 1, true) == nil
				and string.find(NameLower, "cap", 1, true) == nil
				and string.find(NameLower, "regen", 1, true) == nil
				and string.find(NameLower, "recover", 1, true) == nil
				and string.find(NameLower, "rate", 1, true) == nil
				and string.find(NameLower, "delay", 1, true) == nil
				and string.find(NameLower, "percent", 1, true) == nil
				and string.find(NameLower, "ratio", 1, true) == nil
				and string.find(NameLower, "cool", 1, true) == nil
				and not containsSpend(NameLower) then
				return "Current", NameLower
			end

			return nil, NameLower
		end

		local function visitSupportContexts()
			local QueuedScopes = {}
			local ScopeQueue = {}
			local QueuedTables = {}
			local TableQueue = {}

			local function queueScope(Scope, AnchorNameLower, Depth)
				if not Scope or not isLocalRelatedInstance(Scope) then
					return
				end

				local ExistingDepth = QueuedScopes[Scope]

				if ExistingDepth ~= nil and ExistingDepth <= Depth then
					return
				end

				QueuedScopes[Scope] = Depth
				table.insert(ScopeQueue, {
					Scope = Scope,
					AnchorNameLower = AnchorNameLower,
					Depth = Depth
				})
			end

			local function queueTableScope(TableValue, AnchorNameLower, Depth, SourceKind)
				if type(TableValue) ~= "table" then
					return
				end

				local ExistingDepth = QueuedTables[TableValue]

				if ExistingDepth ~= nil and ExistingDepth <= Depth then
					return
				end

				QueuedTables[TableValue] = Depth
				table.insert(TableQueue, {
					Table = TableValue,
					AnchorNameLower = AnchorNameLower,
					Depth = Depth,
					SourceKind = SourceKind or "table"
				})
			end

			for _, GroupName in ipairs({"Flags", "Spend"}) do
				for _, Entry in pairs(EntryMaps[GroupName]) do
					local Candidate = Entry.Candidate
					local Handle = Candidate and Candidate.Handle
					local AnchorInstance = Handle and Handle.Instance
					local AnchorTable = Handle and Handle.Table

					if Candidate
						and Candidate.ExactAlias then
						local AnchorNameLower = Candidate.NameLower or Entry.NameLower

						if Candidate.SourceKind == "instance" and AnchorInstance then
							queueScope(AnchorInstance, AnchorNameLower, 0)
							queueScope(AnchorInstance.Parent, AnchorNameLower, 1)
							queueScope(AnchorInstance.Parent and AnchorInstance.Parent.Parent, AnchorNameLower, 2)
						elseif (Candidate.SourceKind == "table" or Candidate.SourceKind == "env")
							and AnchorTable then
							queueTableScope(AnchorTable, AnchorNameLower, 0, Candidate.SourceKind)
						end
					end
				end
			end

			local function visitContextItem(Name, Handle, Value, Confidence, ScopeTextLower)
				local GroupName, NameLower = inferContextGroup(Name, Value, ScopeTextLower)

				if GroupName then
					recordHandle(GroupName, Name, NameLower, Handle, Value, Confidence, "instance")
				end
			end

			local function visitContextScope(Scope, AnchorNameLower, Depth)
				local ScopeTextLower = string.lower(table.concat({
					AnchorNameLower or "",
					Scope.Name,
					Scope.Parent and Scope.Parent.Name or ""
				}, " "))
				local Confidence = math.max(55, (getInstanceConfidence(Scope) or 55) - (Depth * 10))

				if Scope:IsA("ValueBase") then
					visitContextItem(Scope.Name, createValueHandle(Scope), Scope.Value, Confidence + 8, ScopeTextLower)
				end

				for AttributeName, Value in pairs(Scope:GetAttributes()) do
					visitContextItem(
						AttributeName,
						createAttributeHandle(Scope, AttributeName),
						Value,
						Confidence + 6,
						ScopeTextLower
					)
				end

				local ChildCount = 0

				for _, Child in ipairs(Scope:GetChildren()) do
					ChildCount = ChildCount + 1

					if ChildCount > 24 then
						break
					end

					if Child:IsA("ValueBase") then
						visitContextItem(
							Child.Name,
							createValueHandle(Child),
							Child.Value,
							Confidence + 10,
							ScopeTextLower
						)
					end

					for AttributeName, Value in pairs(Child:GetAttributes()) do
						visitContextItem(
							AttributeName,
							createAttributeHandle(Child, AttributeName),
							Value,
							Confidence + 8,
							ScopeTextLower
						)
					end
				end
			end

			local function visitTableContextScope(TableValue, AnchorNameLower, Depth, SourceKind)
				local ScopeTextLower = string.lower(table.concat({
					AnchorNameLower or "",
					tostring(SourceKind or "table")
				}, " "))
				local Confidence = math.max(70, 118 - (Depth * 10))
				local VisitedChildren = 0

				pcall(function()
					for Key, Value in pairs(TableValue) do
						VisitedChildren = VisitedChildren + 1

						if type(Key) == "string" then
							local GroupName, NameLower = inferContextGroup(Key, Value, ScopeTextLower)

							if GroupName then
								recordHandle(
									GroupName,
									Key,
									NameLower,
									createTableHandle(TableValue, Key),
									Value,
									Confidence,
									SourceKind or "table"
								)
							end

							if type(Value) == "table"
								and Depth < 1
								and shouldRecurseEnvTable(Key, Value, Depth) then
								queueTableScope(Value, AnchorNameLower or NameLower or string.lower(Key), Depth + 1, SourceKind or "table")
							end
						end

						if VisitedChildren >= 32 then
							break
						end
					end
				end)
			end

			for _, Item in ipairs(ScopeQueue) do
				visitContextScope(Item.Scope, Item.AnchorNameLower, Item.Depth)
			end

			for _, Item in ipairs(TableQueue) do
				visitTableContextScope(Item.Table, Item.AnchorNameLower, Item.Depth, Item.SourceKind)
			end
		end

		local function shouldRefreshSupportSearch()
			if not StaminaFeature.Enabled then
				return false
			end

			for _, Candidate in ipairs(StaminaFeature.CandidateOrder) do
				if Candidate.Promoted
					and (
						Candidate.Category == "flags"
						or Candidate.Category == "spend"
					) then
					return true
				end

				if Candidate.RuntimePinned == true
					and isStrongMainScriptStatsPrimaryAlias(Candidate) then
					return true
				end
			end

			return false
		end

		local function finalizeGroup(GroupName)
			local Entries = {}

			for _, Entry in pairs(EntryMaps[GroupName]) do
				table.insert(Entries, Entry)
			end

			table.sort(Entries, function(Left, Right)
				if Left.Confidence ~= Right.Confidence then
					return Left.Confidence > Right.Confidence
				end

				return Left.NameLower < Right.NameLower
			end)

			for _, Entry in ipairs(Entries) do
				table.insert(StaminaFeature.Handles[GroupName], Entry)
			end
		end

		local function bootstrapSupportedStatsPrimaries()
			local function hasScopeSupport(Candidate)
				for _, GroupName in ipairs({"Max", "Flags", "Spend"}) do
					for _, Entry in pairs(EntryMaps[GroupName]) do
						local Sibling = Entry.Candidate

						if Sibling
							and Sibling ~= Candidate
							and handlesShareScope(Candidate.Handle, Sibling.Handle)
							and (
								Sibling.ExactAlias
								or GroupName == "Max"
							) then
							return true
						end
					end
				end

				return false
			end

			for _, GroupName in ipairs({"Current", "Max"}) do
				for _, Entry in pairs(EntryMaps[GroupName]) do
					local Candidate = Entry.Candidate

					if Candidate
						and not Candidate.BootstrapBlocked
						and isStrongMainScriptStatsPrimaryAlias(Candidate)
						and hasScopeSupport(Candidate) then
						Candidate.RuntimePinned = true
						promoteCandidate(Candidate, "logic-local", 8, "stats_scope_bootstrap")
					end
				end
			end
		end

		local function bootstrapHiddenRuntimePrimaries()
			local HiddenCandidates = {}

			for _, GroupName in ipairs({"Current", "Max"}) do
				for _, Entry in pairs(EntryMaps[GroupName]) do
					local Candidate = Entry.Candidate
					local NameLower = Candidate and Candidate.NameLower or ""
					local Confidence = Candidate and Candidate.Confidence or 0
					local ChangeCount = Candidate and Candidate.ChangeCount or 0
					local ObservationHits = Candidate and Candidate.ObservationHits or 0
					local ExternalWriteCount = Candidate and Candidate.ExternalWriteCount or 0
					local HasHiddenNameSignal = string.find(NameLower, "stamina", 1, true) ~= nil
						or string.find(NameLower, "exhaust", 1, true) ~= nil
						or string.find(NameLower, "fatigue", 1, true) ~= nil
						or string.find(NameLower, "breath", 1, true) ~= nil
						or string.find(NameLower, "tired", 1, true) ~= nil
						or string.find(NameLower, "winded", 1, true) ~= nil

					if Candidate
						and not Candidate.BootstrapBlocked
						and Candidate.SourceKind ~= "instance"
						and (
							HasHiddenNameSignal
							or Candidate.ExactAlias == true
							or Confidence >= 155
						)
						and (
							ChangeCount >= 2
							or ObservationHits >= 6
							or ExternalWriteCount >= 1
						) then
						local Score = 10
							+ math.min(ChangeCount, 4)
							+ math.min(math.floor(ObservationHits / 3), 4)
							+ math.min(ExternalWriteCount * 2, 4)

						if Candidate.SourceKind == "upvalue" then
							Score = Score + 3
						elseif Candidate.SourceKind == "env" or Candidate.SourceKind == "table" then
							Score = Score + 2
						end

						if HasHiddenNameSignal then
							Score = Score + 2
						end

						table.insert(HiddenCandidates, {
							Candidate = Candidate,
							Score = Score
						})
					end
				end
			end

			table.sort(HiddenCandidates, function(Left, Right)
				if Left.Score ~= Right.Score then
					return Left.Score > Right.Score
				end

				return (Left.Candidate.Confidence or 0) > (Right.Candidate.Confidence or 0)
			end)

			for Index = 1, math.min(#HiddenCandidates, 2) do
				local Item = HiddenCandidates[Index]

				promoteCandidate(Item.Candidate, "logic-local", Item.Score, "runtime_hidden_logic")
			end
		end

		visitRoots(buildSearchRoots(false))

		if ForceRefresh and not hasRecordedPrimary() then
			visitRoots(buildSearchRoots(true))
		end

		local RefreshSupportSearch = shouldRefreshSupportSearch()

		if ForceRefresh
			or not hasRecordedPrimary()
			or StaminaFeature.DebugEnabled
			or RefreshSupportSearch then
			visitScriptEnvironments()
		end

		if not hasRecordedLogicPrimary() or RefreshSupportSearch then
			visitSupportContexts()
		end

		if IncludeGc or ((ForceRefresh or StaminaFeature.DebugEnabled) and not hasRecordedLogicPrimary()) then
			visitGcFunctions()
		end

		bootstrapSupportedStatsPrimaries()
		bootstrapHiddenRuntimePrimaries()

		if IncludeGc
			and type(getgc) == "function"
			and (ForceRefresh or (Now - StaminaFeature.LastGcResolveAt) >= StaminaFeature.GcResolveInterval) then
			local Success, Objects = pcall(function()
				return getgc(true)
			end)

			if not Success or type(Objects) ~= "table" then
				Success, Objects = pcall(getgc)
			end

			if Success and type(Objects) == "table" then
				for _, Object in ipairs(Objects) do
					if type(Object) == "table" then
						visitTable(Object)
					end
				end
			end

			StaminaFeature.LastGcResolveAt = Now
		end

		finalizeGroup("Current")
		finalizeGroup("Max")
		finalizeGroup("Flags")
		finalizeGroup("Spend")
		connectHandleSignals()

		StaminaFeature.LastResolveAt = Now
	end

	local function mergeTargets(NewCurrentTargets, NewMaxTargets)
		local MergedCurrent = {}
		local MergedMax = {}

		for Family, Value in pairs(StaminaFeature.LastKnownTargets) do
			MergedCurrent[Family] = Value
		end

		for Family, Value in pairs(StaminaFeature.LastKnownMaxTargets) do
			MergedMax[Family] = Value
		end

		for Family, Value in pairs(NewCurrentTargets) do
			if Value ~= nil then
				local PreviousValue = MergedCurrent[Family]

				if typeof(Value) == "number" and typeof(PreviousValue) == "number" then
					if Value > PreviousValue then
						MergedCurrent[Family] = Value
					end
				elseif PreviousValue == nil then
					MergedCurrent[Family] = Value
				end
			end
		end

		for Family, Value in pairs(NewMaxTargets) do
			if Value ~= nil then
				local PreviousValue = MergedMax[Family]

				if typeof(Value) == "number" and typeof(PreviousValue) == "number" then
					if Value > PreviousValue then
						MergedMax[Family] = Value
					end
				else
					MergedMax[Family] = Value
				end
			end
		end

		StaminaFeature.LastKnownTargets = MergedCurrent
		StaminaFeature.LastKnownMaxTargets = MergedMax
	end

	local function computeTargets()
		local CurrentTargets = {}
		local MaxTargets = {}

		local function considerEntry(Entry)
			local Value = toNumber(readEntryValue(Entry))

			if Value ~= nil then
				local Current = CurrentTargets[Entry.Family]

				if Current == nil or Value > Current then
					CurrentTargets[Entry.Family] = Value
				end
			end
		end

		local function considerMaxEntry(Entry)
			local Value = toNumber(readEntryValue(Entry))

			if Value ~= nil then
				local Current = MaxTargets[Entry.Family]

				if Current == nil or Value > Current then
					MaxTargets[Entry.Family] = Value
				end
			end
		end

		for _, Entry in ipairs(StaminaFeature.Handles.Current) do
			if isLogicLocalCandidate(Entry.Candidate) then
				considerEntry(Entry)
			end
		end

		for _, Entry in ipairs(StaminaFeature.Handles.Max) do
			if isLogicLocalCandidate(Entry.Candidate) then
				considerMaxEntry(Entry)
			end
		end

		for _, Entry in ipairs(StaminaFeature.Handles.Current) do
			if CurrentTargets[Entry.Family] == nil then
				considerEntry(Entry)
			end
		end

		for _, Entry in ipairs(StaminaFeature.Handles.Max) do
			if MaxTargets[Entry.Family] == nil then
				considerMaxEntry(Entry)
			end
		end

		if CurrentTargets.base == nil then
			for _, Family in ipairs({"dash", "sprint", "run", "combat", "attack"}) do
				local Value = CurrentTargets[Family]

				if Value ~= nil and (CurrentTargets.base == nil or Value > CurrentTargets.base) then
					CurrentTargets.base = Value
				end
			end
		end

		if CurrentTargets.base ~= nil then
			for _, Family in ipairs({"dash", "sprint", "run", "combat", "attack"}) do
				if CurrentTargets[Family] == nil then
					CurrentTargets[Family] = CurrentTargets.base
				end
			end
		end

		if MaxTargets.base == nil then
			for _, Family in ipairs({"dash", "sprint", "run", "combat", "attack"}) do
				local Value = MaxTargets[Family]

				if Value ~= nil and (MaxTargets.base == nil or Value > MaxTargets.base) then
					MaxTargets.base = Value
				end
			end
		end

		if MaxTargets.base ~= nil then
			for _, Family in ipairs({"dash", "sprint", "run", "combat", "attack"}) do
				if MaxTargets[Family] == nil then
					MaxTargets[Family] = MaxTargets.base
				end
			end
		end

		mergeTargets(CurrentTargets, MaxTargets)
	end

	local getStoredTarget

	local function getPreferredCandidateTarget(Candidate, GroupName, Family, FallbackValue)
		local Target = getStoredTarget(GroupName, Family, FallbackValue)

		if Candidate
			and isStrongMainScriptStatsPrimaryAlias(Candidate) then
			local BestObservedNumber = Candidate.BestObservedNumber

			if GroupName == "Current" then
				if typeof(Target) == "number" and typeof(BestObservedNumber) == "number" then
					return math.max(Target, BestObservedNumber)
				end

				return Target or BestObservedNumber or toNumber(FallbackValue)
			end

			if GroupName == "Max" then
				return Target or BestObservedNumber or toNumber(FallbackValue)
			end
		end

		return Target
	end

	local function getCurrentTargetForEntry(Entry)
		return getPreferredCandidateTarget(Entry.Candidate, "Current", Entry.Family, readEntryValue(Entry))
	end

	local function getMaxTargetForEntry(Entry)
		return getPreferredCandidateTarget(Entry.Candidate, "Max", Entry.Family, readEntryValue(Entry))
	end

	local function rememberOriginalFlags()
		for _, Entry in ipairs(getPreferredRuntimeFlagEntries()) do
			if StaminaFeature.OriginalFlagValues[Entry.Key] == nil then
				StaminaFeature.OriginalFlagValues[Entry.Key] = readEntryValue(Entry)
			end
		end
	end

	local function rememberOriginalSpends()
		for _, Entry in ipairs(getPreferredRuntimeSpendEntries()) do
			if StaminaFeature.OriginalSpendValues[Entry.Key] == nil then
				StaminaFeature.OriginalSpendValues[Entry.Key] = readEntryValue(Entry)
			end
		end
	end

	local function applyFlags()
		rememberOriginalFlags()

		for _, Entry in ipairs(getPreferredRuntimeFlagEntries()) do
			local CurrentValue = readEntryValue(Entry)
			local CanRewrite = supportsSafeRuntimeRewrite("Flags", CurrentValue, Entry.Candidate)
			local DesiredValue = CurrentValue ~= nil and getTruthyValue(CurrentValue) or nil

			if CanRewrite
				and DesiredValue ~= nil
				and not valuesEquivalent(CurrentValue, DesiredValue) then
				local WriteSuccess = writeEntryValue(Entry, DesiredValue)
				local ReadBackValue = readEntryValue(Entry)

				if not WriteSuccess then
					setSupportIssue("flag", Entry, CurrentValue, DesiredValue, "write_failed")
				elseif not valuesEquivalent(ReadBackValue, DesiredValue) then
					setSupportIssue("flag", Entry, ReadBackValue, DesiredValue, "write_reverted")
				end
			end
		end
	end

	local function applySpend()
		rememberOriginalSpends()

		for _, Entry in ipairs(getPreferredRuntimeSpendEntries()) do
			local CurrentValue = readEntryValue(Entry)
			local CanRewrite = supportsSafeRuntimeRewrite("Spend", CurrentValue, Entry.Candidate)
			local DesiredValue = CurrentValue ~= nil and getZeroLikeValue(CurrentValue) or nil

			if CanRewrite
				and DesiredValue ~= nil
				and not valuesEquivalent(CurrentValue, DesiredValue) then
				local WriteSuccess = writeEntryValue(Entry, DesiredValue)
				local ReadBackValue = readEntryValue(Entry)

				if not WriteSuccess then
					setSupportIssue("spend", Entry, CurrentValue, DesiredValue, "write_failed")
				elseif not valuesEquivalent(ReadBackValue, DesiredValue) then
					setSupportIssue("spend", Entry, ReadBackValue, DesiredValue, "write_reverted")
				end
			end
		end
	end

	local function applyDirectStatsOverrides()
		local MainScript = findMainScript()
		local Stats = MainScript and MainScript:FindFirstChild("Stats")

		if not Stats then
			return
		end

		local NamedValues = {}

		local function captureNamedValue(Name, Value)
			if type(Name) == "string" and Value ~= nil then
				local NameLower = string.lower(Name)
				NamedValues[NameLower] = Value

				if DirectStatsHighWaterLookup[NameLower] then
					local NumericValue = toNumber(Value)
					local Existing = toNumber(StaminaFeature.DirectStatsHighWater[NameLower])

					if NumericValue ~= nil and (Existing == nil or NumericValue > Existing) then
						StaminaFeature.DirectStatsHighWater[NameLower] = NumericValue
					end
				end
			end
		end

		local function applyOverride(Name, Handle, Value)
			if type(Name) ~= "string" or not Handle then
				return
			end

			local NameLower = string.lower(Name)
			local DesiredValue = nil

			if DirectStatsFlagTruthLookup[NameLower] then
				DesiredValue = getTruthyValue(Value)
			elseif DirectStatsFlagFalseLookup[NameLower] then
				DesiredValue = getZeroLikeValue(Value)
			elseif DirectStatsSpendZeroLookup[NameLower] then
				DesiredValue = getZeroLikeValue(Value)
			elseif DirectStatsFillToMaxLookup[NameLower] then
				local MaxValue = NamedValues.maxdownedhealth
				local NumericMax = toNumber(MaxValue)

				if NumericMax ~= nil then
					DesiredValue = coerceLike(Value, NumericMax)
				end
			elseif DirectStatsHighWaterLookup[NameLower] then
				local HighWater = toNumber(StaminaFeature.DirectStatsHighWater[NameLower])

				if HighWater ~= nil then
					DesiredValue = coerceLike(Value, HighWater)
				end
			end

			if DesiredValue == nil or valuesEquivalent(Value, DesiredValue) then
				return
			end

			writeHandle(Handle, DesiredValue)
		end

		local function collectInstanceValues(Instance)
			if not Instance then
				return
			end

			if Instance:IsA("ValueBase") then
				captureNamedValue(Instance.Name, Instance.Value)
			end

			for AttributeName, Value in pairs(Instance:GetAttributes()) do
				captureNamedValue(AttributeName, Value)
			end
		end

		local function visitInstance(Instance)
			if not Instance then
				return
			end

			if Instance:IsA("ValueBase") then
				applyOverride(Instance.Name, createValueHandle(Instance), Instance.Value)
			end

			for AttributeName, Value in pairs(Instance:GetAttributes()) do
				applyOverride(AttributeName, createAttributeHandle(Instance, AttributeName), Value)
			end
		end

		collectInstanceValues(Stats)

		local VisitedChildren = 0

		for _, Descendant in ipairs(Stats:GetDescendants()) do
			VisitedChildren = VisitedChildren + 1

			if VisitedChildren > 48 then
				break
			end

			collectInstanceValues(Descendant)
		end

		visitInstance(Stats)
		VisitedChildren = 0

		for _, Descendant in ipairs(Stats:GetDescendants()) do
			VisitedChildren = VisitedChildren + 1

			if VisitedChildren > 48 then
				break
			end

			visitInstance(Descendant)
		end
	end

	local function applyMaxHandles()
		local AllowDisplayMirror = hasLogicPrimaryHandles()

		for _, Entry in ipairs(StaminaFeature.Handles.Max) do
			local Target = getMaxTargetForEntry(Entry)
			local RawValue = readEntryValue(Entry)
			local CurrentValue = toNumber(RawValue)
			local CanRewrite = supportsSafeRuntimeRewrite("Max", RawValue, Entry.Candidate)

			if Target ~= nil
				and CanRewrite
				and isLogicLocalCandidate(Entry.Candidate)
				and (CurrentValue == nil or math.abs(CurrentValue - Target) > 0.001) then
				writeEntryValue(Entry, Target)
			end
		end

		if not AllowDisplayMirror then
			return
		end

		for _, Entry in ipairs(StaminaFeature.Handles.Max) do
			local Target = getMaxTargetForEntry(Entry)
			local RawValue = readEntryValue(Entry)
			local CurrentValue = toNumber(RawValue)
			local CanRewrite = supportsSafeRuntimeRewrite("Max", RawValue, Entry.Candidate)

			if Target ~= nil
				and CanRewrite
				and shouldMirrorDisplayCandidate(Entry.Candidate)
				and (CurrentValue == nil or math.abs(CurrentValue - Target) > 0.001) then
				writeEntryValue(Entry, Target)
			end
		end
	end

	local function applyCurrentHandles()
		local AppliedLogic = false
		local AppliedDisplay = false

		for _, Entry in ipairs(StaminaFeature.Handles.Current) do
			local Target = getCurrentTargetForEntry(Entry)
			local RawValue = readEntryValue(Entry)
			local CurrentValue = toNumber(RawValue)
			local CanRewrite = supportsSafeRuntimeRewrite("Current", RawValue, Entry.Candidate)

			if Target ~= nil
				and CanRewrite
				and isLogicLocalCandidate(Entry.Candidate)
				and (CurrentValue == nil or math.abs(CurrentValue - Target) > 0.001) then
				writeEntryValue(Entry, Target)
			end

			if Target ~= nil and isLogicLocalCandidate(Entry.Candidate) then
				AppliedLogic = true
			end
		end

		if not hasLogicPrimaryHandles() then
			return AppliedLogic, false
		end

		for _, Entry in ipairs(StaminaFeature.Handles.Current) do
			local Target = getCurrentTargetForEntry(Entry)
			local RawValue = readEntryValue(Entry)
			local CurrentValue = toNumber(RawValue)
			local CanRewrite = supportsSafeRuntimeRewrite("Current", RawValue, Entry.Candidate)

			if Target ~= nil
				and CanRewrite
				and shouldMirrorDisplayCandidate(Entry.Candidate)
				and (CurrentValue == nil or math.abs(CurrentValue - Target) > 0.001) then
				writeEntryValue(Entry, Target)
			end

			if Target ~= nil and shouldMirrorDisplayCandidate(Entry.Candidate) then
				AppliedDisplay = true
			end
		end

		return AppliedLogic, AppliedDisplay
	end

	local function evaluateRuntimeVerification(AppliedLogic, AppliedDisplay)
		local Metrics = getCharacterMetrics()
		local Profile = inferRuntimeProfile(Metrics)
		local RecentExternalPressure = hasRecentExternalPressure()
		local ActionPressure = Profile ~= "Free" or RecentExternalPressure
		local DropDetected = false
		local FailureReason = nil
		local SupportHandles = hasSupportHandles()
		local PreferredFlagEntries = getPreferredRuntimeFlagEntries()
		local PreferredSpendEntries = getPreferredRuntimeSpendEntries()

		if Profile == "Free" and Metrics.ToolEquipped and RecentExternalPressure then
			Profile = "Attack"
			ActionPressure = true
		end

		StaminaFeature.LastActionProfile = Profile

		if not hasHandles() then
			return "searching", "no_handles", Profile, true
		end

		if not hasPrimaryHandles() or #StaminaFeature.Handles.Current == 0 then
			return "searching", "missing_primary_handles", Profile, true
		end

		if not hasLogicPrimaryHandles() then
			if SupportHandles then
				if ActionPressure then
					for _, Entry in ipairs(PreferredFlagEntries) do
						local CurrentValue = readEntryValue(Entry)
						local DesiredValue = CurrentValue ~= nil and getTruthyValue(CurrentValue) or nil

						if DesiredValue ~= nil and not valuesEquivalent(CurrentValue, DesiredValue) then
							setSupportIssue("flag", Entry, CurrentValue, DesiredValue, "verify")
							FailureReason = string.lower(Profile) .. "_flag_blocked"
							break
						end
					end

					if not FailureReason then
						for _, Entry in ipairs(PreferredSpendEntries) do
							local CurrentValue = readEntryValue(Entry)
							local DesiredValue = CurrentValue ~= nil and getZeroLikeValue(CurrentValue) or nil

							if DesiredValue ~= nil and not valuesEquivalent(CurrentValue, DesiredValue) then
								setSupportIssue("spend", Entry, CurrentValue, DesiredValue, "verify")
								FailureReason = string.lower(Profile) .. "_spend_locked"
								break
							end
						end
					end
				end

				if FailureReason then
					return "logic_unverified", FailureReason, Profile, true
				end

				if ActionPressure then
					return "verified", string.lower(Profile) .. "_support_only", Profile, false
				end

				return "logic_unverified", "support_handles_waiting", Profile, false
			end

			if AppliedDisplay or getDiagnosticSnapshot().DisplayCurrentCount > 0 or getDiagnosticSnapshot().DisplayMaxCount > 0 then
				return "display_only", "display_handles_only", Profile, true
			end

			return "searching", "no_logic_handles", Profile, true
		end

		if not AppliedLogic then
			return "logic_unverified", "logic_not_applied", Profile, true
		end

		for _, Entry in ipairs(StaminaFeature.Handles.Current) do
			if isLogicLocalCandidate(Entry.Candidate) then
				local Target = getCurrentTargetForEntry(Entry)
				local CurrentValue = toNumber(readEntryValue(Entry))

				if Target ~= nil
					and CurrentValue ~= nil
					and CurrentValue < (Target - StaminaFeature.DropThreshold) then
					DropDetected = true
					break
				end
			end
		end

		if ActionPressure then
			for _, Entry in ipairs(PreferredFlagEntries) do
				local CurrentValue = readEntryValue(Entry)
				local DesiredValue = CurrentValue ~= nil and getTruthyValue(CurrentValue) or nil

				if DesiredValue ~= nil and not valuesEquivalent(CurrentValue, DesiredValue) then
					setSupportIssue("flag", Entry, CurrentValue, DesiredValue, "verify")
					FailureReason = string.lower(Profile) .. "_flag_blocked"
					break
				end
			end

			if not FailureReason then
				for _, Entry in ipairs(PreferredSpendEntries) do
					local CurrentValue = readEntryValue(Entry)
					local DesiredValue = CurrentValue ~= nil and getZeroLikeValue(CurrentValue) or nil

					if DesiredValue ~= nil and not valuesEquivalent(CurrentValue, DesiredValue) then
						setSupportIssue("spend", Entry, CurrentValue, DesiredValue, "verify")
						FailureReason = string.lower(Profile) .. "_spend_locked"
						break
					end
				end
			end
		end

		if ActionPressure and DropDetected then
			return "logic_ineffective", string.lower(Profile) .. "_still_drains", Profile, true
		end

		if ActionPressure then
			if FailureReason then
				return "logic_unverified", FailureReason, Profile, true
			end

			noteVerifiedLogic()
			return "verified", string.lower(Profile) .. "_stable", Profile, false
		end

		if StaminaFeature.LastEffectiveLogicAt > 0
			and (os.clock() - StaminaFeature.LastEffectiveLogicAt) <= 6 then
			return "verified", "holding", Profile, false
		end

		return "logic_unverified", "awaiting_action", Profile, false
	end

	local function shouldQueueGcResolve()
		if not hasLogicPrimaryHandles() then
			StaminaFeature.DropEventCount = StaminaFeature.DropEventCount + 1
			return StaminaFeature.DropEventCount >= StaminaFeature.DropEventLimit
		end

		if not hasPrimaryHandles() or #StaminaFeature.Handles.Current == 0 then
			StaminaFeature.DropEventCount = StaminaFeature.DropEventCount + 1
			return StaminaFeature.DropEventCount >= StaminaFeature.DropEventLimit
		end

		local HasPromotedLogic = false
		local HasDrop = false

		for _, Entry in ipairs(StaminaFeature.Handles.Current) do
			local Target = getCurrentTargetForEntry(Entry)
			local CurrentValue = toNumber(readEntryValue(Entry))

			if isLogicLocalCandidate(Entry.Candidate) then
				HasPromotedLogic = true
			end

			if Target ~= nil
				and CurrentValue ~= nil
				and CurrentValue < (Target - StaminaFeature.DropThreshold) then
				if isLogicLocalCandidate(Entry.Candidate) or not HasPromotedLogic then
					HasDrop = true
					break
				end
			end
		end

		if HasDrop then
			StaminaFeature.DropEventCount = StaminaFeature.DropEventCount + 1
		else
			StaminaFeature.DropEventCount = 0
		end

		return StaminaFeature.DropEventCount >= StaminaFeature.DropEventLimit
	end

	local function restoreOriginalFlags()
		for _, Entry in ipairs(StaminaFeature.Handles.Flags) do
			local OriginalValue = StaminaFeature.OriginalFlagValues[Entry.Key]

			if OriginalValue ~= nil then
				writeEntryValue(Entry, OriginalValue)
			end
		end

		table.clear(StaminaFeature.OriginalFlagValues)
	end

	local function restoreOriginalSpends()
		for _, Entry in ipairs(StaminaFeature.Handles.Spend) do
			local OriginalValue = StaminaFeature.OriginalSpendValues[Entry.Key]

			if OriginalValue ~= nil then
				writeEntryValue(Entry, OriginalValue)
			end
		end

		table.clear(StaminaFeature.OriginalSpendValues)
	end

	local HookState

	local function getHookState()
		if type(getgenv) ~= "function" then
			return nil
		end

		local Environment = getgenv()
		local State = Environment.__FatalityInfStaminaHook

		if type(State) ~= "table" then
			State = {
				Controllers = {},
				NextId = 0,
				Installed = false
			}
			Environment.__FatalityInfStaminaHook = State
		end

		return State
	end

	local function controllerNeedsHooks(Controller)
		return type(Controller) == "table"
			and (
				Controller.Enabled
				or Controller.DebugEnabled
				or (Controller.CaptureSession and Controller.CaptureSession.State ~= "completed")
			)
	end

	local function getActiveController()
		if not HookState then
			return nil
		end

		for _, Controller in pairs(HookState.Controllers) do
			if controllerNeedsHooks(Controller) then
				return Controller
			end
		end

		return nil
	end

	local function syncHookController()
		HookState = getHookState()

		if not HookState then
			return
		end

		if controllerNeedsHooks(StaminaFeature) then
			if not StaminaFeature.HookControllerId then
				HookState.NextId = (HookState.NextId or 0) + 1
				StaminaFeature.HookControllerId = HookState.NextId
			end

			HookState.Controllers[StaminaFeature.HookControllerId] = StaminaFeature
		elseif StaminaFeature.HookControllerId then
			HookState.Controllers[StaminaFeature.HookControllerId] = nil
		end
	end

	getStoredTarget = function(GroupName, Family, FallbackValue)
		local ResolvedFamily = Family or "base"
		local CurrentTargets = StaminaFeature.LastKnownTargets
		local MaxTargets = StaminaFeature.LastKnownMaxTargets

		local function readFamilyTarget(Targets)
			if type(Targets) ~= "table" then
				return nil
			end

			local Value = Targets[ResolvedFamily]

			if Value == nil and ResolvedFamily ~= "base" then
				Value = Targets.base
			end

			return Value
		end

		if GroupName == "Current" then
			-- Keep stamina refilling to the best known max instead of
			-- freezing at whatever value it had when the feature was enabled.
			return readFamilyTarget(MaxTargets)
				or readFamilyTarget(CurrentTargets)
				or toNumber(FallbackValue)
		end

		if GroupName == "Max" then
			return readFamilyTarget(MaxTargets) or toNumber(FallbackValue)
		end

		return readFamilyTarget(CurrentTargets) or toNumber(FallbackValue)
	end

	local function getInterceptTarget(Candidate, IncomingValue)
		if not Candidate then
			return nil, false
		end

		if Candidate.Group == "Flags" and isRuntimeFlagCandidate(Candidate) then
			return getTruthyValue(IncomingValue), true
		end

		if Candidate.Group == "Spend" and isRuntimeSpendCandidate(Candidate) then
			return getZeroLikeValue(IncomingValue), true
		end

		if Candidate.Group ~= "Current" and Candidate.Group ~= "Max" then
			return nil, false
		end

		if not isLogicLocalCandidate(Candidate) then
			return nil, false
		end

		local Target = getPreferredCandidateTarget(Candidate, Candidate.Group, Candidate.Family, IncomingValue)

		if Target == nil then
			return nil, false
		end

		return coerceLike(IncomingValue, Target), true
	end

	local function inspectIncomingLocalChange(GroupName, Name, NameLower, Handle, IncomingValue, Confidence, SourceKind)
		local Controller = getActiveController()

		if not Controller or not GroupName then
			return nil, false
		end

		local Candidate = upsertLocalCandidate(GroupName, Name, NameLower, Handle, IncomingValue, Confidence, SourceKind)

		observeCandidateValue(Candidate, IncomingValue, "external_write")

		if not Controller.Enabled then
			return nil, false
		end

		if not supportsSafeRuntimeRewrite(GroupName, IncomingValue, Candidate) then
			return nil, false
		end

		return getInterceptTarget(Candidate, IncomingValue)
	end

	local function shouldBlockRemote(RemoteCandidate)
		return StaminaFeature.Enabled
			and StaminaFeature.RemoteBlockingEnabled == true
			and RemoteCandidate
			and RemoteCandidate.Promoted
	end

	local function installHooks()
		HookState = getHookState()

		if not HookState or HookState.Installed or type(hookmetamethod) ~= "function" then
			return
		end

		local Wrap = type(newcclosure) == "function" and newcclosure or function(Callback)
			return Callback
		end

		local OriginalNewIndex
		local SuccessNewIndex = pcall(function()
			OriginalNewIndex = hookmetamethod(game, "__newindex", Wrap(function(Self, Key, Value)
				if Key == "Value"
					and typeof(Self) == "Instance"
					and Self:IsA("ValueBase")
					and shouldHookInstance(Self) then
					local GroupName, NameLower = classifyName(Self.Name)

					if GroupName then
						local Replacement, ShouldReplace = inspectIncomingLocalChange(
							GroupName,
							Self.Name,
							NameLower,
							createValueHandle(Self),
							Value,
							getInstanceConfidence(Self),
							"instance"
						)

						if ShouldReplace then
							if typeof(Replacement) == "number" and Self:IsA("IntValue") then
								Replacement = math.floor(Replacement + 0.5)
							end

							return OriginalNewIndex(Self, Key, Replacement)
						end
					end
				end

				return OriginalNewIndex(Self, Key, Value)
			end))
		end)

		local SuccessNamecall = false

		if StaminaFeature.NamecallHookEnabled == true then
			local OriginalNamecall
			SuccessNamecall = pcall(function()
				OriginalNamecall = hookmetamethod(game, "__namecall", Wrap(function(Self, ...)
					local Method = type(getnamecallmethod) == "function" and getnamecallmethod() or nil

					if StaminaFeature.AttributeNamecallHookEnabled == true
						and Method == "SetAttribute"
						and typeof(Self) == "Instance"
						and shouldHookInstance(Self) then
						local Arguments = table.pack(...)
						local AttributeName = Arguments[1]

						if type(AttributeName) == "string" then
							local GroupName, NameLower = classifyName(AttributeName)

							if GroupName then
								local Replacement, ShouldReplace = inspectIncomingLocalChange(
									GroupName,
									AttributeName,
									NameLower,
									createAttributeHandle(Self, AttributeName),
									Arguments[2],
									getInstanceConfidence(Self),
									"instance"
								)

								if ShouldReplace then
									Arguments[2] = Replacement
									return OriginalNamecall(Self, table.unpack(Arguments, 1, Arguments.n))
								end
							end
						end
					elseif StaminaFeature.RemoteNamecallHookEnabled == true
						and (Method == "FireServer" or Method == "InvokeServer")
						and typeof(Self) == "Instance"
						and (Self:IsA("RemoteEvent") or Self:IsA("RemoteFunction")) then
						local Controller = getActiveController()

						if Controller then
							local Arguments = table.pack(...)
							local RemoteCandidate = upsertRemoteCandidate(Self, Method, Arguments)

							recordCaptureRemoteValue(RemoteCandidate)

							if shouldBlockRemote(RemoteCandidate) then
								RemoteCandidate.BlockedCount = RemoteCandidate.BlockedCount + 1
								return nil
							end
						end
					end

					return OriginalNamecall(Self, ...)
				end))
			end)
		end

		HookState.Installed = SuccessNewIndex or SuccessNamecall
	end

	function StaminaFeature:SetDebugEnabled(Value)
		self.DebugEnabled = Value and true or false

		if not self.DebugEnabled then
			clearCaptureSessionState()
			refreshStatusSummary()
		end

		syncHookController()
		installHooks()
		ensureHeartbeatConnection()
		disconnectHeartbeatIfIdle()
	end

	function StaminaFeature:IsDebugEnabled()
		return self.DebugEnabled
	end

	function StaminaFeature:GetDebugProfile()
		return self.DebugProfile
	end

	function StaminaFeature:SetDebugProfile(Profile)
		if CaptureProfiles[Profile] then
			self.DebugProfile = Profile
		end
	end

	function StaminaFeature:StartDebugCapture(Profile)
		self:SetDebugProfile(Profile or self.DebugProfile)

		if not self.DebugEnabled then
			self:SetDebugEnabled(true)
		end

		table.clear(self.LastCaptureSummary)
		self.CaptureSession = createCaptureSession(self.DebugProfile)
		syncHookController()
		installHooks()
		ensureHeartbeatConnection()
		refreshCaptureWindow(self.CaptureSession)
		scheduleStep()

		return true
	end

	function StaminaFeature:ClearDebugCapture()
		clearCaptureSessionState()
		refreshStatusSummary()
		syncHookController()
		disconnectHeartbeatIfIdle()
	end

	function StaminaFeature:GetStatusLines()
		refreshStatusSummary()

		local Lines = {}

		for _, Line in ipairs(self.LastStatusSummary) do
			table.insert(Lines, Line)
		end

		return Lines
	end

	function StaminaFeature:GetDebugLines()
		if not self.DebugEnabled then
			return {}
		end

		local LogicCurrentCount, LogicMaxCount = countLogicPrimaryEntries()

		local Lines = {
			string.format("DebugEnabled: %s", tostring(self.DebugEnabled)),
			string.format("State: %s", tostring(self.VerificationState or "idle")),
			string.format("FailureReason: %s", tostring(self.LastFailureReason or "none")),
			string.format("Profile: %s", self.DebugProfile),
			string.format("ActionProfile: %s", tostring(self.LastActionProfile or "Free")),
			string.format("PromotedLocal: %d", countPromotedLocalCandidates()),
			string.format("PromotedRemote: %d", countPromotedRemoteCandidates()),
			string.format(
				"Handles: C=%d M=%d F=%d S=%d",
				#self.Handles.Current,
				#self.Handles.Max,
				#self.Handles.Flags,
				#self.Handles.Spend
			),
			string.format("LogicHandles: C=%d M=%d", LogicCurrentCount, LogicMaxCount)
		}

		local Session = self.CaptureSession

		if Session then
			table.insert(Lines, string.format("CaptureState: %s", Session.State))
			table.insert(Lines, string.format("ActionValid: %s", tostring(Session.ActionValid)))
			table.insert(Lines, string.format("CaptureSpeed: %s", formatNumber(Session.MaxSpeed or 0)))
		else
			table.insert(Lines, "CaptureState: idle")
		end

		for _, Line in ipairs(self.LastCaptureSummary) do
			table.insert(Lines, Line)
		end

		return Lines
	end

	function StaminaFeature:Step(ForceRefresh, IncludeGc)
		if self.StepBusy then
			return false
		end

		self.StepBusy = true
		self.LastStepAt = os.clock()

		local Success, Result = pcall(function()
			resolveHandles(ForceRefresh, IncludeGc == true)
			advanceCaptureSession()

			if not hasHandles() then
				if shouldRunRuntime() then
					scheduleGcResolve()
				end

				if self.Enabled then
					setVerificationState("searching", "no_handles", self.LastActionProfile)
					requestFailureRecovery(self.LastActionProfile ~= "Free" and self.LastActionProfile or self.DebugProfile)
					warnMissingHandles()
				else
					setVerificationState("idle", "disabled", self.LastActionProfile)
				end

				return false
			end

			computeTargets()

			if not self.Enabled then
				setVerificationState("idle", "disabled", self.LastActionProfile)
				return true
			end

			clearSupportIssue()
			applyFlags()
			applySpend()
			applyDirectStatsOverrides()
			applyMaxHandles()
			local AppliedLogic, AppliedDisplay = applyCurrentHandles()
			local VerificationState, FailureReason, ActionProfile, ShouldRecover = evaluateRuntimeVerification(AppliedLogic, AppliedDisplay)

			setVerificationState(VerificationState, FailureReason, ActionProfile)

			if VerificationState == "logic_ineffective"
				and type(FailureReason) == "string"
				and string.find(FailureReason, "_still_drains", 1, true) ~= nil then
				demoteIneffectiveLogicCandidates(FailureReason)
			end

			if shouldQueueGcResolve() then
				self.DropEventCount = 0
				scheduleGcResolve()

				if self.DebugEnabled
					and (not self.CaptureSession or self.CaptureSession.State == "completed") then
					self:StartDebugCapture(self.DebugProfile)
				end
			end

			if ShouldRecover then
				requestFailureRecovery(ActionProfile ~= "Free" and ActionProfile or self.DebugProfile)
			end

			if VerificationState == "searching" or VerificationState == "display_only" then
				warnMissingHandles()
			end

			return VerificationState == "verified" or AppliedLogic or AppliedDisplay
		end)

		self.StepBusy = false

		if Success then
			return Result
		end

		local Now = os.clock()

		if (Now - (self.LastStepErrorAt or 0)) >= (self.StepErrorCooldown or 2) then
			self.LastStepErrorAt = Now
			warn("[Fatality][Stamina] Step failed: " .. tostring(Result))
		end

		return false
	end

	function StaminaFeature:SetEnabled(Value)
		self.Enabled = Value and true or false
		self.LastResolveAt = 0
		self.LastGcResolveAt = 0
		self.LastStepAt = 0
		self.LastKnownTargets = {}
		self.LastKnownMaxTargets = {}
		self.StepBusy = false
		self.StepQueued = false
		self.GcResolveQueued = false
		self.DropEventCount = 0
		table.clear(self.DirectStatsHighWater)
		self.LastSupportIssue = ""
		self.LastRecoveryAt = 0
		self.LastEffectiveLogicAt = 0
		self.LastStepErrorAt = 0

		if self.Enabled then
			clearScopeCache()
			clearHandles()
			syncHookController()
			installHooks()
			ensureHeartbeatConnection()
			setVerificationState("searching", "initializing", self.LastActionProfile)
			self:Step(true, false)

			if not hasLogicPrimaryHandles() or not hasPrimaryHandles() or #self.Handles.Current == 0 then
				scheduleGcResolve()
			end
		else
			restoreOriginalFlags()
			restoreOriginalSpends()
			resetCaptureState(true)

			clearHandleSignals()
			setVerificationState("idle", "disabled", "Free")
			syncHookController()
			disconnectHeartbeatIfIdle()
		end

		return true
	end

	function StaminaFeature:Destroy()
		self.Enabled = false
		self.DebugEnabled = false
		self.StepBusy = false
		self.StepQueued = false
		self.GcResolveQueued = false
		self.DropEventCount = 0
		table.clear(self.DirectStatsHighWater)
		self.LastSupportIssue = ""
		self.LastRecoveryAt = 0
		self.LastEffectiveLogicAt = 0
		self.LastStepErrorAt = 0
		restoreOriginalFlags()
		restoreOriginalSpends()
		resetCaptureState(false)

		if self.HeartbeatConnection then
			self.HeartbeatConnection:Disconnect()
			self.HeartbeatConnection = nil
		end

		if self.CharacterAddedConnection then
			self.CharacterAddedConnection:Disconnect()
			self.CharacterAddedConnection = nil
		end

		HookState = getHookState()

		if HookState and self.HookControllerId then
			HookState.Controllers[self.HookControllerId] = nil
			self.HookControllerId = nil
		end

		self.LastResolveAt = 0
		self.LastGcResolveAt = 0
		self.LastKnownTargets = {}
		self.LastKnownMaxTargets = {}
		setVerificationState("idle", "destroyed", "Free")
		clearScopeCache()
		clearHandles()
		clearRuntimeCandidates()
	end

	StaminaFeature.CharacterAddedConnection = LocalPlayer.CharacterAdded:Connect(function()
		StaminaFeature.LastResolveAt = 0
		StaminaFeature.LastGcResolveAt = 0
		StaminaFeature.LastStepAt = 0
		StaminaFeature.LastKnownTargets = {}
		StaminaFeature.LastKnownMaxTargets = {}
		StaminaFeature.StepBusy = false
		StaminaFeature.StepQueued = false
		StaminaFeature.GcResolveQueued = false
		StaminaFeature.DropEventCount = 0
		table.clear(StaminaFeature.DirectStatsHighWater)
		StaminaFeature.LastSupportIssue = ""
		StaminaFeature.LastRecoveryAt = 0
		StaminaFeature.LastEffectiveLogicAt = 0
		StaminaFeature.LastStepErrorAt = 0
		table.clear(StaminaFeature.OriginalFlagValues)
		table.clear(StaminaFeature.OriginalSpendValues)
		resetCaptureState(false)
		clearScopeCache()
		clearHandles()
		clearRuntimeCandidates()
		syncHookController()
		setVerificationState(StaminaFeature.Enabled and "searching" or "idle", StaminaFeature.Enabled and "character_reset" or "disabled", "Free")

		if shouldRunRuntime() then
			scheduleStep()
			scheduleGcResolve()
		end
	end)

	return StaminaFeature
end
