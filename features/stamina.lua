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
			"CanUseStamina",
			"HasStamina",
			"EnoughStamina",
			"CanDash",
			"CanSprint",
			"CanRun",
			"CanAttack"
		},
		Spend = {
			"StaminaCost",
			"StaminaDrain",
			"StaminaDeplete",
			"StaminaCooldown",
			"LowStamina",
			"OutOfStamina",
			"StaminaLocked",
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
		StepInterval = 0.1,
		ResolveInterval = 2.5,
		GcResolveInterval = 15,
		LastResolveAt = 0,
		LastGcResolveAt = 0,
		LastStepAt = 0,
		LastWarnAt = 0,
		WarnCooldown = 5,
		LastKnownTargets = {},
		StepBusy = false,
		StepQueued = false,
		GcResolveQueued = false,
		DropEventCount = 0,
		DropThreshold = 1,
		DropEventLimit = 3,
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

	local function shouldBootstrapLogicHandle(GroupName, Handle, Confidence, SourceKind)
		if GroupName ~= "Current" and GroupName ~= "Max" then
			return false
		end

		if SourceKind == "env" or SourceKind == "script-env" then
			return true
		end

		return (Confidence or 0) >= 105 and isMainScriptLogicHandle(Handle)
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

	local function promoteCandidate(Candidate, Category, Score, Reason)
		Candidate.Category = Category
		Candidate.Promoted = true
		Candidate.Score = math.max(Candidate.Score or 0, Score or 0)
		Candidate.PromotionReason = Reason or Candidate.PromotionReason
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
				PreviousValue = nil,
				LastChangeTime = 0,
				LastObservedAt = Now,
				ObservationHits = 0,
				CaptureHits = 0,
				Active = true,
				PromotionReason = nil
			}

			if ExactAlias and shouldBootstrapLogicHandle(GroupName, Handle, Confidence, SourceKind) then
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

		if ExactAlias and shouldBootstrapLogicHandle(GroupName, Handle, Candidate.Confidence, Candidate.SourceKind) then
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
			return "0"
		end

		return 0
	end

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
		recordCaptureCandidateValue(Candidate, Value, Source)

		if Source == "external_write"
			and (Candidate.Group == "Flags" or Candidate.Group == "Spend")
			and Candidate.ExactAlias then
			promoteCandidate(Candidate, initialCategoryForGroup(Candidate.Group), 6, "runtime_external_write")
		elseif Source == "external_write"
			and (Candidate.Group == "Current" or Candidate.Group == "Max")
			and Candidate.ExternalWriteCount >= 2 then
			promoteCandidate(Candidate, "logic-local", 6 + Candidate.ExternalWriteCount, "runtime_external_write")
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

	local function warnMissingHandles()
		if not Notification then
			return
		end

		local Now = os.clock()

		if (Now - StaminaFeature.LastWarnAt) < StaminaFeature.WarnCooldown then
			return
		end

		StaminaFeature.LastWarnAt = Now

		Notification:Notify({
			Title = "FATALITY",
			Content = "Inf stamina could not find logic stamina handles yet.",
			Icon = "alert-circle"
		})
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

	local function isLogicLocalCandidate(Candidate)
		return Candidate
			and Candidate.Promoted
			and Candidate.Category == "logic-local"
	end

	local function isFlagCandidate(Candidate)
		return Candidate
			and Candidate.Promoted
			and Candidate.Category == "flags"
	end

	local function isSpendCandidate(Candidate)
		return Candidate
			and Candidate.Promoted
			and Candidate.Category == "spend"
	end

	local function isDisplayCandidate(Candidate)
		return Candidate
			and (
				Candidate.Category == "display"
				or Candidate.Promoted == false
			)
	end

	local function hasPrimaryHandles()
		return #StaminaFeature.Handles.Current > 0 or #StaminaFeature.Handles.Max > 0
	end

	local function hasHandles()
		return #StaminaFeature.Handles.Current > 0
			or #StaminaFeature.Handles.Max > 0
			or #StaminaFeature.Handles.Flags > 0
			or #StaminaFeature.Handles.Spend > 0
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
			getCandidateDisplayName(Candidate),
			Candidate.Category,
			Candidate.Score or 0,
			Observation.TotalChanges or 0,
			Observation.ExternalWrites or 0,
			formatNumber(Observation.DeltaMagnitude or 0)
		)
	end

	local function finalizeCaptureSession()
		local Session = StaminaFeature.CaptureSession

		if not Session or Session.State == "completed" then
			return
		end

		local ProfileFamily = getProfileFamily(Session.Profile)
		local PromotedLogic = {}
		local DisplaySuspects = {}
		local RemoteSuspects = {}
		local LogicLocalCount = 0

		for _, Candidate in ipairs(StaminaFeature.CandidateOrder) do
			local Observation = Session.Observations[Candidate.RegistryKey]

			if Observation then
				local Score = (Candidate.Confidence or 0) / 35

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

				if ProfileFamily ~= nil and Candidate.Family == ProfileFamily then
					Score = Score + 2
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

				if Candidate.Group == "Flags" then
					if Score >= 4 then
						promoteCandidate(Candidate, "flags", Score, "capture_flags")
						table.insert(PromotedLogic, {
							Candidate = Candidate,
							Observation = Observation
						})
						LogicLocalCount = LogicLocalCount + 1
					end
				elseif Candidate.Group == "Spend" then
					if Score >= 4 then
						promoteCandidate(Candidate, "spend", Score, "capture_spend")
						table.insert(PromotedLogic, {
							Candidate = Candidate,
							Observation = Observation
						})
						LogicLocalCount = LogicLocalCount + 1
					end
				elseif Score >= 6 or (Observation.ExternalWrites or 0) >= 2 then
					promoteCandidate(Candidate, "logic-local", Score, "capture_logic")
					table.insert(PromotedLogic, {
						Candidate = Candidate,
						Observation = Observation
					})
					LogicLocalCount = LogicLocalCount + 1
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

		for _, Candidate in ipairs(StaminaFeature.RemoteCandidateOrder) do
			local Observation = Session.RemoteObservations[Candidate.RegistryKey]

			if Observation then
				Candidate.Score = math.max(Candidate.Score or 0, Observation.Count * 2)

				if LogicLocalCount == 0 and Session.ActionValid and Observation.Count >= 2 then
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
			string.format("LastProfile: %s", Session.Profile),
			string.format("ActionValid: %s", tostring(Session.ActionValid)),
			string.format("MaxSpeed: %s", formatNumber(Session.MaxSpeed or 0)),
			string.format("PromotedLogic: %d", LogicLocalCount),
			string.format("RemoteCalls: %d", Session.RemoteCallCount or 0)
		}

		if #PromotedLogic > 0 then
			table.insert(Lines, "TopPromoted:")

			for Index = 1, math.min(#PromotedLogic, 4) do
				table.insert(Lines, buildSummaryLine(PromotedLogic[Index].Candidate, PromotedLogic[Index].Observation))
			end
		end

		if #DisplaySuspects > 0 then
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

	local function resetCaptureState()
		clearCaptureSessionState()

		for _, Candidate in ipairs(StaminaFeature.RemoteCandidateOrder) do
			Candidate.Promoted = false
			Candidate.CaptureHits = 0
			Candidate.Score = 0
		end

		for _, Candidate in ipairs(StaminaFeature.CandidateOrder) do
			Candidate.Score = 0
			Candidate.CaptureHits = 0

			if Candidate.Group == "Flags" then
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

	local function scheduleGcResolve()
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

	local function scheduleStep()
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

		local function attach(Entry)
			if not Entry or Connected[Entry.Key] then
				return
			end

			if Entry.Handle.Kind == "value" then
				local Success, Connection = pcall(function()
					return Entry.Handle.Instance:GetPropertyChangedSignal("Value"):Connect(scheduleStep)
				end)

				if Success and Connection then
					table.insert(StaminaFeature.HandleSignals, Connection)
					Connected[Entry.Key] = true
				end

				return
			end

			if Entry.Handle.Kind == "attribute" then
				local Success, Connection = pcall(function()
					return Entry.Handle.Instance:GetAttributeChangedSignal(Entry.Handle.Attribute):Connect(scheduleStep)
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

		local function recordHandle(GroupName, Name, NameLower, Handle, Value, Confidence, SourceKind)
			if not GroupName or not isUsefulValue(GroupName, Value) then
				return
			end

			local IsExactAlias = Lookups[GroupName] and Lookups[GroupName][NameLower] == true or false

			if SourceKind == "table"
				and string.find(NameLower, "stamina", 1, true) == nil
				and not IsExactAlias then
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

		local function visitEnvTable(TableValue, Confidence, Depth, Visited)
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
						local GroupName, NameLower = classifyName(Key)

						if GroupName then
							recordHandle(GroupName, Key, NameLower, createTableHandle(TableValue, Key), Value, Confidence, "env")
						end

						if type(Value) == "table"
							and shouldRecurseEnvTable(Key, Value, Depth) then
							visitEnvTable(Value, math.max((Confidence or 0) - 8, 80), Depth + 1, Visited)
						end
					elseif type(Value) == "table"
						and Depth == 0
						and shouldRecurseEnvTable(nil, Value, Depth) then
						visitEnvTable(Value, math.max((Confidence or 0) - 8, 80), Depth + 1, Visited)
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
					visitEnvTable(EnvironmentTable, Confidence or 135, 0, {})
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

		local function visitRoots(Roots)
			for _, Root in ipairs(Roots) do
				visitInstance(Root)

				for _, Descendant in ipairs(Root:GetDescendants()) do
					visitInstance(Descendant)
				end
			end
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

		visitRoots(buildSearchRoots(false))

		if ForceRefresh and not hasRecordedPrimary() then
			visitRoots(buildSearchRoots(true))
		end

		if ForceRefresh or not hasRecordedPrimary() or StaminaFeature.DebugEnabled then
			visitScriptEnvironments()
		end

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

	local function mergeTargets(NewTargets)
		local Merged = {}

		for Family, Value in pairs(StaminaFeature.LastKnownTargets) do
			Merged[Family] = Value
		end

		for Family, Value in pairs(NewTargets) do
			if Value ~= nil then
				local PreviousValue = Merged[Family]

				if typeof(Value) == "number" and typeof(PreviousValue) == "number" then
					if Value > PreviousValue then
						Merged[Family] = Value
					end
				else
					Merged[Family] = Value
				end
			end
		end

		StaminaFeature.LastKnownTargets = Merged
	end

	local function computeTargets()
		local Targets = {}

		local function considerEntry(Entry)
			local Value = toNumber(readEntryValue(Entry))

			if Value ~= nil then
				local Current = Targets[Entry.Family]

				if Current == nil or Value > Current then
					Targets[Entry.Family] = Value
				end
			end
		end

		for _, Entry in ipairs(StaminaFeature.Handles.Max) do
			if isLogicLocalCandidate(Entry.Candidate) then
				considerEntry(Entry)
			end
		end

		for _, Entry in ipairs(StaminaFeature.Handles.Current) do
			if isLogicLocalCandidate(Entry.Candidate) then
				considerEntry(Entry)
			end
		end

		for _, Entry in ipairs(StaminaFeature.Handles.Max) do
			if Targets[Entry.Family] == nil then
				considerEntry(Entry)
			end
		end

		for _, Entry in ipairs(StaminaFeature.Handles.Current) do
			if Targets[Entry.Family] == nil then
				considerEntry(Entry)
			end
		end

		if Targets.base == nil then
			for _, Family in ipairs({"dash", "sprint", "run", "combat", "attack"}) do
				local Value = Targets[Family]

				if Value ~= nil and (Targets.base == nil or Value > Targets.base) then
					Targets.base = Value
				end
			end
		end

		if Targets.base ~= nil then
			for _, Family in ipairs({"dash", "sprint", "run", "combat", "attack"}) do
				if Targets[Family] == nil then
					Targets[Family] = Targets.base
				end
			end
		end

		mergeTargets(Targets)
	end

	local function getTargetForEntry(Entry)
		local Targets = StaminaFeature.LastKnownTargets
		local Target = Targets[Entry.Family]

		if Target == nil and Entry.Family ~= "base" then
			Target = Targets.base
		end

		if Target == nil then
			Target = toNumber(readEntryValue(Entry))
		end

		return Target
	end

	local function rememberOriginalFlags()
		for _, Entry in ipairs(StaminaFeature.Handles.Flags) do
			if isFlagCandidate(Entry.Candidate)
				and StaminaFeature.OriginalFlagValues[Entry.Key] == nil then
				StaminaFeature.OriginalFlagValues[Entry.Key] = readEntryValue(Entry)
			end
		end
	end

	local function rememberOriginalSpends()
		for _, Entry in ipairs(StaminaFeature.Handles.Spend) do
			if isSpendCandidate(Entry.Candidate)
				and StaminaFeature.OriginalSpendValues[Entry.Key] == nil then
				StaminaFeature.OriginalSpendValues[Entry.Key] = readEntryValue(Entry)
			end
		end
	end

	local function applyFlags()
		rememberOriginalFlags()

		for _, Entry in ipairs(StaminaFeature.Handles.Flags) do
			if isFlagCandidate(Entry.Candidate) then
				local CurrentValue = readEntryValue(Entry)
				local DesiredValue = getTruthyValue(CurrentValue)

				if CurrentValue ~= DesiredValue then
					writeEntryValue(Entry, DesiredValue)
				end
			end
		end
	end

	local function applySpend()
		rememberOriginalSpends()

		for _, Entry in ipairs(StaminaFeature.Handles.Spend) do
			if isSpendCandidate(Entry.Candidate) then
				local CurrentValue = readEntryValue(Entry)
				local DesiredValue = getZeroLikeValue(CurrentValue)

				if CurrentValue ~= DesiredValue then
					writeEntryValue(Entry, DesiredValue)
				end
			end
		end
	end

	local function applyMaxHandles()
		for _, Entry in ipairs(StaminaFeature.Handles.Max) do
			local Target = getTargetForEntry(Entry)
			local CurrentValue = toNumber(readEntryValue(Entry))

			if Target ~= nil
				and isLogicLocalCandidate(Entry.Candidate)
				and (CurrentValue == nil or math.abs(CurrentValue - Target) > 0.001) then
				writeEntryValue(Entry, Target)
			end
		end

		for _, Entry in ipairs(StaminaFeature.Handles.Max) do
			local Target = getTargetForEntry(Entry)
			local CurrentValue = toNumber(readEntryValue(Entry))

			if Target ~= nil
				and isDisplayCandidate(Entry.Candidate)
				and (CurrentValue == nil or math.abs(CurrentValue - Target) > 0.001) then
				writeEntryValue(Entry, Target)
			end
		end
	end

	local function applyCurrentHandles()
		local AppliedLogic = false
		local AppliedDisplay = false

		for _, Entry in ipairs(StaminaFeature.Handles.Current) do
			local Target = getTargetForEntry(Entry)
			local CurrentValue = toNumber(readEntryValue(Entry))

			if Target ~= nil
				and isLogicLocalCandidate(Entry.Candidate)
				and (CurrentValue == nil or math.abs(CurrentValue - Target) > 0.001) then
				writeEntryValue(Entry, Target)
			end

			if Target ~= nil and isLogicLocalCandidate(Entry.Candidate) then
				AppliedLogic = true
			end
		end

		for _, Entry in ipairs(StaminaFeature.Handles.Current) do
			local Target = getTargetForEntry(Entry)
			local CurrentValue = toNumber(readEntryValue(Entry))

			if Target ~= nil
				and isDisplayCandidate(Entry.Candidate)
				and (CurrentValue == nil or math.abs(CurrentValue - Target) > 0.001) then
				writeEntryValue(Entry, Target)
			end

			if Target ~= nil and isDisplayCandidate(Entry.Candidate) then
				AppliedDisplay = true
			end
		end

		return AppliedLogic, AppliedDisplay
	end

	local function shouldQueueGcResolve()
		if not hasPrimaryHandles() or #StaminaFeature.Handles.Current == 0 then
			StaminaFeature.DropEventCount = StaminaFeature.DropEventCount + 1
			return StaminaFeature.DropEventCount >= StaminaFeature.DropEventLimit
		end

		local HasPromotedLogic = false
		local HasDrop = false

		for _, Entry in ipairs(StaminaFeature.Handles.Current) do
			local Target = getTargetForEntry(Entry)
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

	local function getInterceptTarget(Candidate, IncomingValue)
		if not Candidate then
			return nil, false
		end

		if Candidate.Group == "Flags" and isFlagCandidate(Candidate) then
			return getTruthyValue(IncomingValue), true
		end

		if Candidate.Group == "Spend" and isSpendCandidate(Candidate) then
			return getZeroLikeValue(IncomingValue), true
		end

		if Candidate.Group ~= "Current" and Candidate.Group ~= "Max" then
			return nil, false
		end

		if not isLogicLocalCandidate(Candidate) then
			return nil, false
		end

		local Targets = StaminaFeature.LastKnownTargets
		local Target = Targets[Candidate.Family]

		if Target == nil and Candidate.Family ~= "base" then
			Target = Targets.base
		end

		if Target == nil then
			Target = toNumber(IncomingValue)
		end

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
					and isLocalRelatedInstance(Self) then
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

					if Method == "SetAttribute"
						and typeof(Self) == "Instance"
						and isLocalRelatedInstance(Self) then
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
					elseif (Method == "FireServer" or Method == "InvokeServer")
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
		syncHookController()
		disconnectHeartbeatIfIdle()
	end

	function StaminaFeature:GetDebugLines()
		if not self.DebugEnabled then
			return {}
		end

		local Lines = {
			string.format("DebugEnabled: %s", tostring(self.DebugEnabled)),
			string.format("Profile: %s", self.DebugProfile),
			string.format("PromotedLocal: %d", countPromotedLocalCandidates()),
			string.format("PromotedRemote: %d", countPromotedRemoteCandidates()),
			string.format(
				"Handles: C=%d M=%d F=%d S=%d",
				#self.Handles.Current,
				#self.Handles.Max,
				#self.Handles.Flags,
				#self.Handles.Spend
			)
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
					warnMissingHandles()
				end

				return false
			end

			computeTargets()

			if not self.Enabled then
				return true
			end

			applyFlags()
			applySpend()
			applyMaxHandles()
			local AppliedLogic, AppliedDisplay = applyCurrentHandles()

			if shouldQueueGcResolve() then
				self.DropEventCount = 0
				scheduleGcResolve()

				if self.DebugEnabled
					and (not self.CaptureSession or self.CaptureSession.State == "completed") then
					self:StartDebugCapture(self.DebugProfile)
				end
			end

			if not AppliedLogic then
				warnMissingHandles()
			end

			return AppliedLogic or AppliedDisplay
		end)

		self.StepBusy = false

		if Success then
			return Result
		end

		return false
	end

	function StaminaFeature:SetEnabled(Value)
		self.Enabled = Value and true or false
		self.LastResolveAt = 0
		self.LastGcResolveAt = 0
		self.LastStepAt = 0
		self.LastKnownTargets = {}
		self.StepBusy = false
		self.StepQueued = false
		self.GcResolveQueued = false
		self.DropEventCount = 0

		if self.Enabled then
			clearScopeCache()
			clearHandles()
			syncHookController()
			installHooks()
			ensureHeartbeatConnection()
			self:Step(true, false)

			if not hasPrimaryHandles() or #self.Handles.Current == 0 then
				scheduleGcResolve()
			end
		else
			restoreOriginalFlags()
			restoreOriginalSpends()
			resetCaptureState()

			clearHandleSignals()
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
		restoreOriginalFlags()
		restoreOriginalSpends()
		resetCaptureState()

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
		clearScopeCache()
		clearHandles()
		clearRuntimeCandidates()
	end

	StaminaFeature.CharacterAddedConnection = LocalPlayer.CharacterAdded:Connect(function()
		StaminaFeature.LastResolveAt = 0
		StaminaFeature.LastGcResolveAt = 0
		StaminaFeature.LastStepAt = 0
		StaminaFeature.LastKnownTargets = {}
		StaminaFeature.StepBusy = false
		StaminaFeature.StepQueued = false
		StaminaFeature.GcResolveQueued = false
		StaminaFeature.DropEventCount = 0
		table.clear(StaminaFeature.OriginalFlagValues)
		table.clear(StaminaFeature.OriginalSpendValues)
		resetCaptureState()
		clearScopeCache()
		clearHandles()
		clearRuntimeCandidates()
		syncHookController()

		if shouldRunRuntime() then
			scheduleStep()
			scheduleGcResolve()
		end
	end)

	return StaminaFeature
end
