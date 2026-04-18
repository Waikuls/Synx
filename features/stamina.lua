return function(Config)
	local Players = game:GetService("Players")
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local RunService = game:GetService("RunService")
	local LocalPlayer = Players.LocalPlayer
	local Notification = Config and Config.Notification

	local StaminaFeature = {
		Enabled = false,
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
		HookControllerId = nil
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
			"AttackStamina"
		},
		Max = {
			"MaxStamina",
			"MaximumStamina",
			"StaminaMax",
			"MaxDashStamina",
			"MaxSprintStamina",
			"MaxRunStamina",
			"MaxAttackStamina"
		},
		Flags = {
			"NoStaminaCost",
			"CanUseStamina",
			"HasStamina",
			"EnoughStamina"
		},
		Spend = {
			"StaminaCost",
			"StaminaDrain",
			"StaminaDeplete",
			"StaminaCooldown",
			"DashCost",
			"SprintCost",
			"RunCost",
			"AttackCost",
			"DashCooldown",
			"SprintCooldown",
			"RunCooldown",
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

		local Success, Value = pcall(function()
			return Instance:GetDebugId(0)
		end)

		if Success and Value then
			return Value
		end

		return tostring(Instance)
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
		if GroupName == "Flags" then
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

	local function disconnectHandleSignals()
		for _, Connection in ipairs(StaminaFeature.HandleSignals) do
			Connection:Disconnect()
		end

		table.clear(StaminaFeature.HandleSignals)
	end

	local function clearHandles()
		disconnectHandleSignals()
		table.clear(StaminaFeature.Handles.Current)
		table.clear(StaminaFeature.Handles.Max)
		table.clear(StaminaFeature.Handles.Flags)
		table.clear(StaminaFeature.Handles.Spend)
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
			Content = "Inf stamina could not find stamina handles yet.",
			Icon = "alert-circle"
		})
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

	local function scheduleGcResolve()
		if not StaminaFeature.Enabled
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

			if StaminaFeature.Enabled then
				StaminaFeature:Step(true, true)
			end
		end)
	end

	local function scheduleStep()
		if not StaminaFeature.Enabled or StaminaFeature.StepQueued then
			return
		end

		StaminaFeature.StepQueued = true

		task.defer(function()
			StaminaFeature.StepQueued = false

			if StaminaFeature.Enabled then
				StaminaFeature:Step(false, false)
			end
		end)
	end

	local function connectHandleSignals()
		disconnectHandleSignals()

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

		local EntryMaps = {
			Current = {},
			Max = {},
			Flags = {},
			Spend = {}
		}

		local function hasRecordedPrimary()
			return next(EntryMaps.Current) ~= nil or next(EntryMaps.Max) ~= nil
		end

		local function recordHandle(GroupName, NameLower, Handle, Value, Confidence, SourceKind)
			if not GroupName or not isUsefulValue(GroupName, Value) then
				return
			end

			if SourceKind == "table" and string.find(NameLower, "stamina", 1, true) == nil then
				return
			end

			if GroupName == "Spend"
				and string.find(NameLower, "stamina", 1, true) == nil
				and (Confidence or 0) < 60 then
				return
			end

			local Key = getHandleKey(Handle)
			local Existing = EntryMaps[GroupName][Key]

			if Existing and Existing.Confidence >= (Confidence or 0) then
				return
			end

			EntryMaps[GroupName][Key] = {
				Key = Key,
				NameLower = NameLower,
				Family = getFamily(NameLower),
				Handle = Handle,
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
					recordHandle(GroupName, NameLower, createValueHandle(Instance), Instance.Value, Confidence, "instance")
				end
			end

			for AttributeName, Value in pairs(Instance:GetAttributes()) do
				local GroupName, NameLower = classifyName(AttributeName)

				if GroupName then
					recordHandle(GroupName, NameLower, createAttributeHandle(Instance, AttributeName), Value, Confidence, "instance")
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
							recordHandle(GroupName, NameLower, createTableHandle(TableValue, Key), Value, 15, "table")
						end
					end
				end
			end)

			if not Success then
				return
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
			local HasStrongInstance = false

			for _, Entry in pairs(EntryMaps[GroupName]) do
				table.insert(Entries, Entry)

				if Entry.SourceKind ~= "table" and Entry.Confidence >= 60 then
					HasStrongInstance = true
				end
			end

			table.sort(Entries, function(Left, Right)
				if Left.Confidence ~= Right.Confidence then
					return Left.Confidence > Right.Confidence
				end

				return Left.NameLower < Right.NameLower
			end)

			for _, Entry in ipairs(Entries) do
				if not HasStrongInstance or Entry.SourceKind ~= "table" then
					table.insert(StaminaFeature.Handles[GroupName], Entry)
				end
			end
		end

		visitRoots(buildSearchRoots(false))

		if ForceRefresh and not hasRecordedPrimary() then
			visitRoots(buildSearchRoots(true))
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

		for _, Entry in ipairs(StaminaFeature.Handles.Max) do
			local Value = toNumber(readHandle(Entry.Handle))

			if Value ~= nil then
				local Current = Targets[Entry.Family]

				if Current == nil or Value > Current then
					Targets[Entry.Family] = Value
				end
			end
		end

		for _, Entry in ipairs(StaminaFeature.Handles.Current) do
			local Value = toNumber(readHandle(Entry.Handle))

			if Value ~= nil then
				local Current = Targets[Entry.Family]

				if Current == nil or Value > Current then
					Targets[Entry.Family] = Value
				end
			end
		end

		if Targets.base == nil then
			for _, Family in ipairs({"dash", "sprint", "run", "attack"}) do
				local Value = Targets[Family]

				if Value ~= nil and (Targets.base == nil or Value > Targets.base) then
					Targets.base = Value
				end
			end
		end

		if Targets.base ~= nil then
			for _, Family in ipairs({"dash", "sprint", "run", "attack"}) do
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
			Target = toNumber(readHandle(Entry.Handle))
		end

		return Target
	end

	local function rememberOriginalFlags()
		for _, Entry in ipairs(StaminaFeature.Handles.Flags) do
			if StaminaFeature.OriginalFlagValues[Entry.Key] == nil then
				StaminaFeature.OriginalFlagValues[Entry.Key] = readHandle(Entry.Handle)
			end
		end
	end

	local function rememberOriginalSpends()
		for _, Entry in ipairs(StaminaFeature.Handles.Spend) do
			if StaminaFeature.OriginalSpendValues[Entry.Key] == nil then
				StaminaFeature.OriginalSpendValues[Entry.Key] = readHandle(Entry.Handle)
			end
		end
	end

	local function applyFlags()
		rememberOriginalFlags()

		for _, Entry in ipairs(StaminaFeature.Handles.Flags) do
			local CurrentValue = readHandle(Entry.Handle)
			local DesiredValue = getTruthyValue(CurrentValue)

			if CurrentValue ~= DesiredValue then
				writeHandle(Entry.Handle, DesiredValue)
			end
		end
	end

	local function applySpend()
		rememberOriginalSpends()

		for _, Entry in ipairs(StaminaFeature.Handles.Spend) do
			local CurrentValue = readHandle(Entry.Handle)
			local DesiredValue = getZeroLikeValue(CurrentValue)

			if CurrentValue ~= DesiredValue then
				writeHandle(Entry.Handle, DesiredValue)
			end
		end
	end

	local function applyMaxHandles()
		for _, Entry in ipairs(StaminaFeature.Handles.Max) do
			local Target = getTargetForEntry(Entry)
			local CurrentValue = toNumber(readHandle(Entry.Handle))

			if Target ~= nil and (CurrentValue == nil or math.abs(CurrentValue - Target) > 0.001) then
				writeHandle(Entry.Handle, Target)
			end
		end
	end

	local function applyCurrentHandles()
		local Applied = false

		for _, Entry in ipairs(StaminaFeature.Handles.Current) do
			local Target = getTargetForEntry(Entry)
			local CurrentValue = toNumber(readHandle(Entry.Handle))

			if Target ~= nil and (CurrentValue == nil or math.abs(CurrentValue - Target) > 0.001) then
				writeHandle(Entry.Handle, Target)
			end

			if Target ~= nil then
				Applied = true
			end
		end

		return Applied
	end

	local function shouldQueueGcResolve()
		if not hasPrimaryHandles() or #StaminaFeature.Handles.Current == 0 then
			StaminaFeature.DropEventCount = StaminaFeature.DropEventCount + 1
			return StaminaFeature.DropEventCount >= StaminaFeature.DropEventLimit
		end

		local HasDrop = false

		for _, Entry in ipairs(StaminaFeature.Handles.Current) do
			local Target = getTargetForEntry(Entry)
			local CurrentValue = toNumber(readHandle(Entry.Handle))

			if Target ~= nil and CurrentValue ~= nil and CurrentValue < (Target - StaminaFeature.DropThreshold) then
				HasDrop = true
				break
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
				writeHandle(Entry.Handle, OriginalValue)
			end
		end

		table.clear(StaminaFeature.OriginalFlagValues)
	end

	local function restoreOriginalSpends()
		for _, Entry in ipairs(StaminaFeature.Handles.Spend) do
			local OriginalValue = StaminaFeature.OriginalSpendValues[Entry.Key]

			if OriginalValue ~= nil then
				writeHandle(Entry.Handle, OriginalValue)
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

	local function getEnabledController()
		if not HookState then
			return nil
		end

		for _, Controller in pairs(HookState.Controllers) do
			if type(Controller) == "table" and Controller.Enabled then
				return Controller
			end
		end

		return nil
	end

	local function getInterceptTarget(NameLower, IncomingValue)
		local Controller = getEnabledController()

		if not Controller then
			return nil, false
		end

		local GroupName = nil

		for Group, Lookup in pairs(Lookups) do
			if Lookup[NameLower] then
				GroupName = Group
				break
			end
		end

		if not GroupName then
			GroupName = select(1, classifyName(NameLower))
		end

		if GroupName == "Flags" then
			return getTruthyValue(IncomingValue), true
		end

		if GroupName == "Spend" then
			return getZeroLikeValue(IncomingValue), true
		end

		if GroupName ~= "Current" and GroupName ~= "Max" then
			return nil, false
		end

		local Family = getFamily(NameLower)
		local Targets = Controller.LastKnownTargets
		local Target = Targets[Family]

		if Target == nil and Family ~= "base" then
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

	local function installHooks()
		HookState = getHookState()

		if HookState then
			HookState.ResolveIntercept = getInterceptTarget
			HookState.IsLocalRelatedInstance = isLocalRelatedInstance
		end

		if not HookState or HookState.Installed or type(hookmetamethod) ~= "function" then
			return
		end

		local Wrap = type(newcclosure) == "function" and newcclosure or function(Callback)
			return Callback
		end

		local OriginalNewIndex
		local SuccessNewIndex = pcall(function()
			OriginalNewIndex = hookmetamethod(game, "__newindex", Wrap(function(Self, Key, Value)
				local ScopeCheck = HookState and HookState.IsLocalRelatedInstance
				local ResolveIntercept = HookState and HookState.ResolveIntercept

				if Key == "Value"
					and typeof(Self) == "Instance"
					and Self:IsA("ValueBase")
					and type(ScopeCheck) == "function"
					and ScopeCheck(Self)
					and type(ResolveIntercept) == "function" then
					local Replacement, ShouldReplace = ResolveIntercept(string.lower(Self.Name), Value)

					if ShouldReplace then
						if typeof(Replacement) == "number" and Self:IsA("IntValue") then
							Replacement = math.floor(Replacement + 0.5)
						end

						return OriginalNewIndex(Self, Key, Replacement)
					end
				end

				return OriginalNewIndex(Self, Key, Value)
			end))
		end)

		local OriginalNamecall
		local SuccessNamecall = pcall(function()
			OriginalNamecall = hookmetamethod(game, "__namecall", Wrap(function(Self, ...)
				local Method = type(getnamecallmethod) == "function" and getnamecallmethod() or nil
				local ScopeCheck = HookState and HookState.IsLocalRelatedInstance
				local ResolveIntercept = HookState and HookState.ResolveIntercept

				if Method == "SetAttribute"
					and typeof(Self) == "Instance"
					and type(ScopeCheck) == "function"
					and ScopeCheck(Self)
					and type(ResolveIntercept) == "function" then
					local Arguments = table.pack(...)
					local AttributeName = Arguments[1]

					if type(AttributeName) == "string" then
						local Replacement, ShouldReplace = ResolveIntercept(string.lower(AttributeName), Arguments[2])

						if ShouldReplace then
							Arguments[2] = Replacement
							return OriginalNamecall(Self, table.unpack(Arguments, 1, Arguments.n))
						end
					end
				end

				return OriginalNamecall(Self, ...)
			end))
		end)

		HookState.Installed = SuccessNewIndex or SuccessNamecall
	end

	local function ensureHookController()
		HookState = getHookState()

		if not HookState then
			return
		end

		if not StaminaFeature.HookControllerId then
			HookState.NextId = (HookState.NextId or 0) + 1
			StaminaFeature.HookControllerId = HookState.NextId
		end

		HookState.Controllers[StaminaFeature.HookControllerId] = StaminaFeature
		installHooks()
	end

	function StaminaFeature:Step(ForceRefresh, IncludeGc)
		if self.StepBusy then
			return false
		end

		self.StepBusy = true
		self.LastStepAt = os.clock()

		local Success, Result = pcall(function()
			resolveHandles(ForceRefresh, IncludeGc == true)

			if not hasHandles() then
				scheduleGcResolve()
				warnMissingHandles()
				return false
			end

			computeTargets()
			applyFlags()
			applySpend()
			applyMaxHandles()
			local Applied = applyCurrentHandles()

			if shouldQueueGcResolve() then
				self.DropEventCount = 0
				scheduleGcResolve()
			end

			if not Applied and #self.Handles.Current == 0 then
				warnMissingHandles()
			end

			return Applied or #self.Handles.Flags > 0 or #self.Handles.Spend > 0
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
			ensureHookController()
			clearScopeCache()
			clearHandles()
			self:Step(true, false)

			if not self.HeartbeatConnection then
				self.HeartbeatConnection = RunService.Heartbeat:Connect(function()
					if self.Enabled and (os.clock() - self.LastStepAt) >= self.StepInterval then
						self:Step(false, false)
					end
				end)
			end

			if not hasPrimaryHandles() or #self.Handles.Current == 0 then
				scheduleGcResolve()
			end
		else
			restoreOriginalFlags()
			restoreOriginalSpends()

			if self.HeartbeatConnection then
				self.HeartbeatConnection:Disconnect()
				self.HeartbeatConnection = nil
			end

			disconnectHandleSignals()
		end

		return true
	end

	function StaminaFeature:Destroy()
		self.Enabled = false
		self.StepBusy = false
		self.StepQueued = false
		self.GcResolveQueued = false
		self.DropEventCount = 0
		restoreOriginalFlags()
		restoreOriginalSpends()

		if self.HeartbeatConnection then
			self.HeartbeatConnection:Disconnect()
			self.HeartbeatConnection = nil
		end

		if self.CharacterAddedConnection then
			self.CharacterAddedConnection:Disconnect()
			self.CharacterAddedConnection = nil
		end

		if HookState and self.HookControllerId then
			HookState.Controllers[self.HookControllerId] = nil
			self.HookControllerId = nil
		end

		self.LastResolveAt = 0
		self.LastGcResolveAt = 0
		self.LastKnownTargets = {}
		clearHandles()
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
		clearScopeCache()
		clearHandles()

		if StaminaFeature.Enabled then
			scheduleStep()
			scheduleGcResolve()
		end
	end)

	return StaminaFeature
end
