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
		ResolveInterval = 1,
		GcResolveInterval = 8,
		LastResolveAt = 0,
		LastGcResolveAt = 0,
		LastWarnAt = 0,
		WarnCooldown = 5,
		LastKnownTargets = {},
		StepBusy = false,
		StepQueued = false,
		Handles = {
			Current = {},
			Max = {},
			Flags = {},
			Guard = {}
		},
		OriginalFlagValues = {},
		OriginalGuardValues = {},
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
			"CanUseStamina",
			"HasStamina",
			"EnoughStamina"
		},
		Guard = {
			"Exhaustion",
			"BodyFatigue",
			"BodyFatique",
			"LowStamina",
			"OutOfStamina",
			"Exhausted",
			"IsExhausted",
			"Tired",
			"IsTired",
			"StaminaLocked",
			"StaminaCost",
			"StaminaDrain",
			"StaminaDeplete",
			"StaminaCooldown"
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
		Guard = createLookup(ExactAliases.Guard)
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

	local function toBoolean(Value)
		if typeof(Value) == "boolean" then
			return Value
		end

		if typeof(Value) == "number" then
			return Value ~= 0
		end

		if typeof(Value) == "string" then
			local Lower = string.lower(Value)

			if Lower == "true" or Lower == "yes" or Lower == "1" then
				return true
			end

			if Lower == "false" or Lower == "no" or Lower == "0" then
				return false
			end
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
		local PlayerGui = LocalPlayer:FindFirstChild("PlayerGui")
		local PlayerScripts = LocalPlayer:FindFirstChild("PlayerScripts")
		local Entity = findEntity()
		local MainScript = findMainScript()
		local Result = Instance == LocalPlayer
			or isInstanceInHierarchy(Instance, Character)
			or isInstanceInHierarchy(Instance, PlayerGui)
			or isInstanceInHierarchy(Instance, PlayerScripts)
			or isInstanceInHierarchy(Instance, Entity)
			or isInstanceInHierarchy(Instance, MainScript)
			or isLocalPlayerFolder(Instance)

		ScopeCache[Instance] = Result

		return Result
	end

	local function buildSearchRoots()
		local Character = LocalPlayer.Character
		local Entity = findEntity()
		local MainScript = findMainScript()
		local Stats = MainScript and MainScript:FindFirstChild("Stats")
		local PlayerGui = LocalPlayer:FindFirstChild("PlayerGui")
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

		addRoot(Stats)
		addRoot(MainScript)
		addRoot(Entity)
		addRoot(LocalPlayer:FindFirstChild("Stats"))
		addRoot(Character and Character:FindFirstChild("Stats"))
		addRoot(LocalPlayer:FindFirstChild("Data"))
		addRoot(Character and Character:FindFirstChild("Data"))
		addRoot(PlayerGui)
		addRoot(PlayerScripts)
		addRoot(Character)
		addRoot(LocalPlayer)

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

	local function containsMax(NameLower)
		return string.find(NameLower, "max", 1, true) ~= nil
			or string.find(NameLower, "maximum", 1, true) ~= nil
	end

	local function containsFlag(NameLower)
		return string.sub(NameLower, 1, 9) == "nostamina"
			or NameLower == "canusestamina"
			or NameLower == "hasstamina"
			or NameLower == "enoughstamina"
	end

	local function containsGuard(NameLower)
		return string.find(NameLower, "fatigue", 1, true) ~= nil
			or string.find(NameLower, "fatique", 1, true) ~= nil
			or string.find(NameLower, "exhaust", 1, true) ~= nil
			or string.find(NameLower, "locked", 1, true) ~= nil
			or string.find(NameLower, "lowstamina", 1, true) ~= nil
			or string.find(NameLower, "outofstamina", 1, true) ~= nil
			or string.find(NameLower, "out_of_stamina", 1, true) ~= nil
			or string.find(NameLower, "cost", 1, true) ~= nil
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

		if not string.find(NameLower, "stamina", 1, true) then
			return nil, NameLower
		end

		if containsFlag(NameLower) then
			return "Flags", NameLower
		end

		if containsMax(NameLower) then
			return "Max", NameLower
		end

		if containsGuard(NameLower) then
			return "Guard", NameLower
		end

		if string.find(NameLower, "regen", 1, true)
			or string.find(NameLower, "recover", 1, true)
			or string.find(NameLower, "rate", 1, true)
			or string.find(NameLower, "delay", 1, true)
			or string.find(NameLower, "percent", 1, true)
			or string.find(NameLower, "ratio", 1, true) then
			return nil, NameLower
		end

		return "Current", NameLower
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

			if Success then
				return Value
			end

			return nil
		end

		if Handle.Kind == "attribute" then
			local Success, Value = pcall(function()
				return Handle.Instance:GetAttribute(Handle.Attribute)
			end)

			if Success then
				return Value
			end

			return nil
		end

		local Success, Value = pcall(function()
			return Handle.Instance.Value
		end)

		if Success then
			return Value
		end

		return nil
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
		table.clear(StaminaFeature.Handles.Guard)
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

	local function scheduleStep()
		if not StaminaFeature.Enabled or StaminaFeature.StepQueued then
			return
		end

		StaminaFeature.StepQueued = true

		task.defer(function()
			StaminaFeature.StepQueued = false

			if StaminaFeature.Enabled then
				StaminaFeature:Step(false)
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

	local function resolveHandles(ForceRefresh)
		local Now = os.clock()

		if not ForceRefresh and (Now - StaminaFeature.LastResolveAt) < StaminaFeature.ResolveInterval then
			return
		end

		clearHandles()

		local EntryMaps = {
			Current = {},
			Max = {},
			Flags = {},
			Guard = {}
		}

		local function recordHandle(GroupName, NameLower, Handle, Value)
			if not GroupName or not isUsefulValue(GroupName, Value) then
				return
			end

			local Key = getHandleKey(Handle)

			if EntryMaps[GroupName][Key] then
				return
			end

			EntryMaps[GroupName][Key] = {
				Key = Key,
				NameLower = NameLower,
				Family = getFamily(NameLower),
				Handle = Handle
			}
		end

		local function visitInstance(Instance)
			if not isLocalRelatedInstance(Instance) then
				return
			end

			if Instance:IsA("ValueBase") then
				local GroupName, NameLower = classifyName(Instance.Name)

				if GroupName then
					recordHandle(GroupName, NameLower, createValueHandle(Instance), Instance.Value)
				end
			end

			for AttributeName, Value in pairs(Instance:GetAttributes()) do
				local GroupName, NameLower = classifyName(AttributeName)

				if GroupName then
					recordHandle(GroupName, NameLower, createAttributeHandle(Instance, AttributeName), Value)
				end
			end
		end

		local function visitTable(TableValue)
			if not tableBelongsToLocalPlayer(TableValue) then
				return
			end

			for Key, Value in pairs(TableValue) do
				if type(Key) == "string" then
					local GroupName, NameLower = classifyName(Key)

					if GroupName then
						recordHandle(GroupName, NameLower, createTableHandle(TableValue, Key), Value)
					end
				end
			end
		end

		for _, Root in ipairs(buildSearchRoots()) do
			visitInstance(Root)

			for _, Descendant in ipairs(Root:GetDescendants()) do
				visitInstance(Descendant)
			end
		end

		if type(getgc) == "function" and (ForceRefresh or (Now - StaminaFeature.LastGcResolveAt) >= StaminaFeature.GcResolveInterval) then
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

		for GroupName, Map in pairs(EntryMaps) do
			for _, Entry in pairs(Map) do
				table.insert(StaminaFeature.Handles[GroupName], Entry)
			end
		end

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

			if Value ~= nil and (Targets[Entry.Family] == nil or Value > Targets[Entry.Family]) then
				Targets[Entry.Family] = Value
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

		mergeTargets(Targets)
	end

	local function getTargetForEntry(Entry)
		local Target = StaminaFeature.LastKnownTargets[Entry.Family]

		if Target == nil then
			Target = StaminaFeature.LastKnownTargets.base
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

	local function rememberOriginalGuards()
		for _, Entry in ipairs(StaminaFeature.Handles.Guard) do
			if StaminaFeature.OriginalGuardValues[Entry.Key] == nil then
				StaminaFeature.OriginalGuardValues[Entry.Key] = readHandle(Entry.Handle)
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

	local function applyGuards()
		rememberOriginalGuards()

		for _, Entry in ipairs(StaminaFeature.Handles.Guard) do
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

	local function restoreOriginalFlags()
		for _, Entry in ipairs(StaminaFeature.Handles.Flags) do
			local OriginalValue = StaminaFeature.OriginalFlagValues[Entry.Key]

			if OriginalValue ~= nil then
				writeHandle(Entry.Handle, OriginalValue)
			end
		end

		table.clear(StaminaFeature.OriginalFlagValues)
	end

	local function restoreOriginalGuards()
		for _, Entry in ipairs(StaminaFeature.Handles.Guard) do
			local OriginalValue = StaminaFeature.OriginalGuardValues[Entry.Key]

			if OriginalValue ~= nil then
				writeHandle(Entry.Handle, OriginalValue)
			end
		end

		table.clear(StaminaFeature.OriginalGuardValues)
	end

	local function hasHandles()
		return #StaminaFeature.Handles.Current > 0
			or #StaminaFeature.Handles.Max > 0
			or #StaminaFeature.Handles.Flags > 0
			or #StaminaFeature.Handles.Guard > 0
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
			GroupName = classifyName(NameLower)
		end

		if GroupName == "Flags" then
			return getTruthyValue(IncomingValue), true
		end

		if GroupName == "Guard" then
			return getZeroLikeValue(IncomingValue), true
		end

		if GroupName ~= "Current" and GroupName ~= "Max" then
			return nil, false
		end

		local Family = getFamily(NameLower)
		local Target = Controller.LastKnownTargets[Family] or Controller.LastKnownTargets.base

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

	function StaminaFeature:Step(ForceRefresh)
		if self.StepBusy then
			return false
		end

		self.StepBusy = true

		local Success, Result = pcall(function()
			resolveHandles(ForceRefresh)

			if not hasHandles() then
				warnMissingHandles()
				return false
			end

			computeTargets()
			applyFlags()
			applyGuards()
			applyMaxHandles()

			return applyCurrentHandles()
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
		self.LastKnownTargets = {}
		self.StepBusy = false
		self.StepQueued = false

		if self.Enabled then
			ensureHookController()
			clearScopeCache()
			resolveHandles(true)
			self:Step(true)

			if not self.HeartbeatConnection then
				self.HeartbeatConnection = RunService.Heartbeat:Connect(function()
					if self.Enabled then
						self:Step(false)
					end
				end)
			end
		else
			restoreOriginalFlags()
			restoreOriginalGuards()

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
		restoreOriginalFlags()
		restoreOriginalGuards()

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
		StaminaFeature.LastKnownTargets = {}
		StaminaFeature.StepBusy = false
		StaminaFeature.StepQueued = false
		table.clear(StaminaFeature.OriginalFlagValues)
		table.clear(StaminaFeature.OriginalGuardValues)
		clearScopeCache()
		clearHandles()

		if StaminaFeature.Enabled then
			scheduleStep()
		end
	end)

	return StaminaFeature
end
