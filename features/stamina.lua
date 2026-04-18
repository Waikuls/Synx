return function(Config)
	local Players = game:GetService("Players")
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local RunService = game:GetService("RunService")
	local LocalPlayer = Players.LocalPlayer
	local Notification = Config and Config.Notification

	local StaminaFeature = {
		Enabled = false,
		Connection = nil,
		CharacterAddedConnection = nil,
		ResolveInterval = 1,
		LastResolveAt = 0,
		LastKnownMax = nil,
		LastWarnAt = 0,
		WarnCooldown = 5,
		StepBusy = false,
		Handles = {
			Current = {},
			Max = {},
			Flags = {},
			Guard = {}
		},
		EntryIndex = {},
		PreviousValues = {},
		TrackedKeys = {},
		OriginalFlagValues = {}
	}

	local CoreAliases = {
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
			"NoStaminaCost"
		},
		Guard = {
			"Exhaustion",
			"BodyFatigue",
			"BodyFatique"
		}
	}
	local CandidateAliases = {
		Current = {
			"Eevee",
			"Energy",
			"CurrentEnergy",
			"DashEnergy",
			"SprintEnergy",
			"CombatEnergy"
		},
		Max = {
			"MaxEnergy",
			"MaximumEnergy",
			"EnergyMax",
			"MaxEevee",
			"MaximumEevee",
			"EeveeMax",
			"MaxDashEnergy",
			"MaxSprintEnergy",
			"MaxCombatEnergy"
		},
		Flags = {
			"NoEeveeDeplete",
			"CanUseStamina",
			"HasStamina",
			"EnoughStamina",
			"HasEevee",
			"EnoughEnergy"
		},
		Guard = {
			"EeveeDeplete",
			"LowStamina",
			"OutOfStamina",
			"Exhausted",
			"IsExhausted",
			"Tired",
			"IsTired",
			"StaminaLocked"
		}
	}

	local function createLookup(Aliases)
		local Lookup = {}

		for _, Name in ipairs(Aliases) do
			Lookup[string.lower(Name)] = true
		end

		return Lookup
	end

	local CoreLookup = {
		Current = createLookup(CoreAliases.Current),
		Max = createLookup(CoreAliases.Max),
		Flags = createLookup(CoreAliases.Flags),
		Guard = createLookup(CoreAliases.Guard)
	}
	local CandidateLookup = {
		Current = createLookup(CandidateAliases.Current),
		Max = createLookup(CandidateAliases.Max),
		Flags = createLookup(CandidateAliases.Flags),
		Guard = createLookup(CandidateAliases.Guard)
	}

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
			return pcall(function()
				Handle.Instance:SetAttribute(Handle.Attribute, Value)
			end)
		end

		if typeof(Value) == "number" and Handle.Instance:IsA("IntValue") then
			Value = math.floor(Value + 0.5)
		end

		return pcall(function()
			Handle.Instance.Value = Value
		end)
	end

	local function getResourceFamily(NameLower)
		if string.find(NameLower, "eevee", 1, true) or string.find(NameLower, "energy", 1, true) then
			return "energy"
		end

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

		return "stamina"
	end

	local function classifyName(Name)
		local Lower = string.lower(Name)
		local HasStamina = string.find(Lower, "stamina", 1, true) ~= nil
		local HasEnergy = string.find(Lower, "energy", 1, true) ~= nil or string.find(Lower, "eevee", 1, true) ~= nil
		local HasMax = string.find(Lower, "max", 1, true) ~= nil or string.find(Lower, "maximum", 1, true) ~= nil
		local HasCost = string.find(Lower, "cost", 1, true) ~= nil
		local HasDrain = string.find(Lower, "drain", 1, true) ~= nil
		local HasDeplete = string.find(Lower, "deplete", 1, true) ~= nil
		local HasCooldown = string.find(Lower, "cooldown", 1, true) ~= nil
		local HasDelay = string.find(Lower, "delay", 1, true) ~= nil
		local HasPercent = string.find(Lower, "percent", 1, true) ~= nil or string.find(Lower, "ratio", 1, true) ~= nil

		for GroupName, Lookup in pairs(CoreLookup) do
			if Lookup[Lower] then
				return GroupName, "core", Lower
			end
		end

		for GroupName, Lookup in pairs(CandidateLookup) do
			if Lookup[Lower] then
				return GroupName, "candidate", Lower
			end
		end

		if (HasStamina or HasEnergy) and HasMax then
			return "Max", "candidate", Lower
		end

		if (HasStamina or HasEnergy)
			and not HasMax
			and not HasCost
			and not HasDrain
			and not HasDeplete
			and not HasCooldown
			and not HasDelay
			and not HasPercent
			and not string.find(Lower, "regen", 1, true)
			and not string.find(Lower, "recover", 1, true) then
			return "Current", "candidate", Lower
		end

		if string.find(Lower, "fatigue", 1, true)
			or string.find(Lower, "fatique", 1, true)
			or string.find(Lower, "exhaust", 1, true)
			or string.find(Lower, "outofstamina", 1, true)
			or string.find(Lower, "out_of_stamina", 1, true)
			or string.find(Lower, "lowstamina", 1, true)
			or string.find(Lower, "tired", 1, true)
			or string.find(Lower, "staminalocked", 1, true) then
			return "Guard", "candidate", Lower
		end

		return nil, nil, Lower
	end

	local function isUsefulValue(GroupName, Value)
		if GroupName == "Flags" then
			local ValueType = typeof(Value)
			return ValueType == "boolean" or ValueType == "number" or ValueType == "string"
		end

		return toNumber(Value) ~= nil
	end

	local function clearHandles()
		table.clear(StaminaFeature.Handles.Current)
		table.clear(StaminaFeature.Handles.Max)
		table.clear(StaminaFeature.Handles.Flags)
		table.clear(StaminaFeature.Handles.Guard)
		table.clear(StaminaFeature.EntryIndex)
	end

	local function resetTracking()
		table.clear(StaminaFeature.PreviousValues)
		table.clear(StaminaFeature.TrackedKeys)
	end

	local function isEntryStillValid(Entry)
		return Entry and isHandleValid(Entry.Handle)
	end

	local function resolveHandles(ForceRefresh)
		local Now = os.clock()

		if not ForceRefresh and (Now - StaminaFeature.LastResolveAt) < StaminaFeature.ResolveInterval then
			local HasInvalid = false

			for _, Group in pairs(StaminaFeature.Handles) do
				for _, Entry in ipairs(Group) do
					if not isEntryStillValid(Entry) then
						HasInvalid = true
						break
					end
				end

				if HasInvalid then
					break
				end
			end

			if not HasInvalid then
				return
			end
		end

		clearHandles()

		local EntryMaps = {
			Current = {},
			Max = {},
			Flags = {},
			Guard = {}
		}

		local function recordHandle(GroupName, Source, NameLower, Handle, Value)
			if not GroupName or not isUsefulValue(GroupName, Value) then
				return
			end

			local Key = getHandleKey(Handle)
			local Existing = EntryMaps[GroupName][Key]

			if Existing and Existing.Source == "core" then
				return
			end

			if Existing and Existing.Source == Source then
				return
			end

			local Entry = {
				Key = Key,
				Handle = Handle,
				NameLower = NameLower,
				Source = Source,
				Group = GroupName
			}

			EntryMaps[GroupName][Key] = Entry
			StaminaFeature.EntryIndex[Key] = Entry
		end

		local function visitInstance(Instance)
			if Instance:IsA("ValueBase") then
				local GroupName, Source, NameLower = classifyName(Instance.Name)

				if GroupName then
					recordHandle(GroupName, Source, NameLower, createValueHandle(Instance), Instance.Value)
				end
			end

			for Name, Value in pairs(Instance:GetAttributes()) do
				local GroupName, Source, NameLower = classifyName(Name)

				if GroupName then
					recordHandle(GroupName, Source, NameLower, createAttributeHandle(Instance, Name), Value)
				end
			end
		end

		local function visitTable(TableValue)
			for Key, Value in pairs(TableValue) do
				if type(Key) == "string" then
					local GroupName, Source, NameLower = classifyName(Key)

					if GroupName then
						recordHandle(GroupName, Source, NameLower, createTableHandle(TableValue, Key), Value)
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

		if type(getgc) == "function" then
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
		end

		for GroupName, Map in pairs(EntryMaps) do
			for _, Entry in pairs(Map) do
				table.insert(StaminaFeature.Handles[GroupName], Entry)
			end
		end

		StaminaFeature.LastResolveAt = Now
	end

	local function updateTrackedKeys()
		for _, Group in pairs(StaminaFeature.Handles) do
			for _, Entry in ipairs(Group) do
				local Key = Entry.Key
				local CurrentValue = readHandle(Entry.Handle)
				local PreviousValue = StaminaFeature.PreviousValues[Key]

				if Entry.Source == "candidate" and PreviousValue ~= nil then
					if Entry.Group == "Current" or Entry.Group == "Max" then
						local PreviousNumber = toNumber(PreviousValue)
						local CurrentNumber = toNumber(CurrentValue)

						if PreviousNumber ~= nil and CurrentNumber ~= nil and CurrentNumber < (PreviousNumber - 0.001) then
							StaminaFeature.TrackedKeys[Key] = true
						end
					elseif Entry.Group == "Guard" then
						local PreviousNumber = toNumber(PreviousValue)
						local CurrentNumber = toNumber(CurrentValue)
						local PreviousBool = toBoolean(PreviousValue)
						local CurrentBool = toBoolean(CurrentValue)

						if PreviousNumber ~= nil and CurrentNumber ~= nil and CurrentNumber > (PreviousNumber + 0.001) then
							StaminaFeature.TrackedKeys[Key] = true
						elseif PreviousBool ~= nil and CurrentBool == true and PreviousBool ~= true then
							StaminaFeature.TrackedKeys[Key] = true
						end
					elseif Entry.Group == "Flags" then
						local PreviousBool = toBoolean(PreviousValue)
						local CurrentBool = toBoolean(CurrentValue)

						if PreviousBool ~= nil and CurrentBool ~= nil then
							if string.sub(Entry.NameLower, 1, 2) == "no" then
								if CurrentBool == false and PreviousBool ~= false then
									StaminaFeature.TrackedKeys[Key] = true
								end
							elseif CurrentBool == false and PreviousBool ~= false then
								StaminaFeature.TrackedKeys[Key] = true
							end
						end
					end
				end

				StaminaFeature.PreviousValues[Key] = CurrentValue
			end
		end
	end

	local function buildTrackedFamilies()
		local Families = {}

		for Key in pairs(StaminaFeature.TrackedKeys) do
			local Entry = StaminaFeature.EntryIndex[Key]

			if Entry and Entry.Group ~= "Flags" then
				Families[getResourceFamily(Entry.NameLower)] = true
			end
		end

		return Families
	end

	local function isEntryActive(Entry, TrackedFamilies)
		if not Entry then
			return false
		end

		if Entry.Source == "core" then
			return true
		end

		if StaminaFeature.TrackedKeys[Entry.Key] then
			return true
		end

		if Entry.Group == "Flags" then
			return TrackedFamilies[getResourceFamily(Entry.NameLower)] == true
		end

		return false
	end

	local function rememberOriginalFlagValues(TrackedFamilies)
		for _, Entry in ipairs(StaminaFeature.Handles.Flags) do
			if isEntryActive(Entry, TrackedFamilies) then
				local Key = Entry.Key

				if StaminaFeature.OriginalFlagValues[Key] == nil then
					StaminaFeature.OriginalFlagValues[Key] = readHandle(Entry.Handle)
				end
			end
		end
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

	local function computeTargetMax(TrackedFamilies)
		local Highest = StaminaFeature.LastKnownMax

		for _, Entry in ipairs(StaminaFeature.Handles.Max) do
			if isEntryActive(Entry, TrackedFamilies) then
				local Value = toNumber(readHandle(Entry.Handle))

				if Value ~= nil and (Highest == nil or Value > Highest) then
					Highest = Value
				end
			end
		end

		for _, Entry in ipairs(StaminaFeature.Handles.Current) do
			if isEntryActive(Entry, TrackedFamilies) then
				local Value = toNumber(readHandle(Entry.Handle))

				if Value ~= nil and (Highest == nil or Value > Highest) then
					Highest = Value
				end
			end
		end

		StaminaFeature.LastKnownMax = Highest

		return Highest
	end

	local function applyFlagHandles(TrackedFamilies)
		rememberOriginalFlagValues(TrackedFamilies)

		for _, Entry in ipairs(StaminaFeature.Handles.Flags) do
			if isEntryActive(Entry, TrackedFamilies) then
				local CurrentValue = readHandle(Entry.Handle)
				local DesiredValue = getTruthyValue(CurrentValue)

				if CurrentValue ~= DesiredValue then
					writeHandle(Entry.Handle, DesiredValue)
				end
			end
		end
	end

	local function applyGuardHandles(TrackedFamilies)
		for _, Entry in ipairs(StaminaFeature.Handles.Guard) do
			if isEntryActive(Entry, TrackedFamilies) then
				local CurrentValue = readHandle(Entry.Handle)
				local DesiredValue = getZeroLikeValue(CurrentValue)

				if CurrentValue ~= DesiredValue then
					writeHandle(Entry.Handle, DesiredValue)
				end
			end
		end
	end

	local function applyMaxHandles(TargetMax, TrackedFamilies)
		if TargetMax == nil then
			return
		end

		for _, Entry in ipairs(StaminaFeature.Handles.Max) do
			if isEntryActive(Entry, TrackedFamilies) then
				local CurrentValue = toNumber(readHandle(Entry.Handle))

				if CurrentValue == nil or math.abs(CurrentValue - TargetMax) > 0.001 then
					writeHandle(Entry.Handle, TargetMax)
				end
			end
		end
	end

	local function applyCurrentHandles(TargetMax, TrackedFamilies)
		if TargetMax == nil then
			return false
		end

		local Applied = false

		for _, Entry in ipairs(StaminaFeature.Handles.Current) do
			if isEntryActive(Entry, TrackedFamilies) then
				local CurrentValue = toNumber(readHandle(Entry.Handle))

				if CurrentValue == nil or math.abs(CurrentValue - TargetMax) > 0.001 then
					writeHandle(Entry.Handle, TargetMax)
				end

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
			Content = "Inf stamina could not find stamina values yet.",
			Icon = "alert-circle"
		})
	end

	local function step()
		if StaminaFeature.StepBusy then
			return false
		end

		StaminaFeature.StepBusy = true

		local Success, Result = pcall(function()
			resolveHandles(false)
			updateTrackedKeys()

			local TrackedFamilies = buildTrackedFamilies()
			local TargetMax = computeTargetMax(TrackedFamilies)
			local HasCoreCurrent = false
			local HasTrackedCurrent = false
			local HasActiveSupport = false

			for _, Entry in ipairs(StaminaFeature.Handles.Current) do
				if Entry.Source == "core" then
					HasCoreCurrent = true
					break
				end
			end

			for _, Entry in ipairs(StaminaFeature.Handles.Current) do
				if Entry.Source == "candidate" and isEntryActive(Entry, TrackedFamilies) then
					HasTrackedCurrent = true
					break
				end
			end

			for _, Entry in ipairs(StaminaFeature.Handles.Flags) do
				if isEntryActive(Entry, TrackedFamilies) then
					HasActiveSupport = true
					break
				end
			end

			if not HasActiveSupport then
				for _, Entry in ipairs(StaminaFeature.Handles.Guard) do
					if isEntryActive(Entry, TrackedFamilies) then
						HasActiveSupport = true
						break
					end
				end
			end

			if not HasCoreCurrent and not HasTrackedCurrent and not HasActiveSupport then
				warnMissingHandles()
				return false
			end

			applyFlagHandles(TrackedFamilies)
			applyGuardHandles(TrackedFamilies)
			applyMaxHandles(TargetMax, TrackedFamilies)

			if HasCoreCurrent or HasTrackedCurrent then
				return applyCurrentHandles(TargetMax, TrackedFamilies)
			end

			return HasActiveSupport
		end)

		StaminaFeature.StepBusy = false

		if Success then
			return Result
		end

		return false
	end

	function StaminaFeature:SetEnabled(Value)
		self.Enabled = Value and true or false
		self.LastResolveAt = 0
		self.LastKnownMax = nil
		self.StepBusy = false

		if self.Enabled then
			resetTracking()
			step()

			if not self.Connection then
				self.Connection = RunService.Heartbeat:Connect(function()
					if self.Enabled then
						step()
					end
				end)
			end
		else
			restoreOriginalFlags()
			resetTracking()

			if self.Connection then
				self.Connection:Disconnect()
				self.Connection = nil
			end
		end

		return true
	end

	function StaminaFeature:Destroy()
		self.Enabled = false
		self.StepBusy = false
		restoreOriginalFlags()

		if self.Connection then
			self.Connection:Disconnect()
			self.Connection = nil
		end

		if self.CharacterAddedConnection then
			self.CharacterAddedConnection:Disconnect()
			self.CharacterAddedConnection = nil
		end

		self.LastResolveAt = 0
		self.LastKnownMax = nil
		clearHandles()
		resetTracking()
	end

	StaminaFeature.CharacterAddedConnection = LocalPlayer.CharacterAdded:Connect(function()
		StaminaFeature.LastResolveAt = 0
		StaminaFeature.LastKnownMax = nil
		StaminaFeature.StepBusy = false
		clearHandles()
		resetTracking()
	end)

	return StaminaFeature
end
