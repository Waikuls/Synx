return function(Config)
	local Players = game:GetService("Players")
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local RunService = game:GetService("RunService")
	local LocalPlayer = Players.LocalPlayer
	local Notification = Config and Config.Notification

	local StaminaFeature = {
		Enabled = false,
		Connections = {},
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
		OriginalFlagValues = {}
	}

	local CurrentAliases = {
		"Stamina",
		"StaminaInStat",
		"CurrentStamina",
		"StaminaValue",
		"Eevee",
		"Energy",
		"CurrentEnergy",
		"Adrenaline",
		"DashStamina",
		"SprintStamina",
		"RunStamina",
		"AttackStamina",
		"CombatStamina",
		"DashEnergy",
		"SprintEnergy",
		"CombatEnergy"
	}
	local MaxAliases = {
		"MaxStamina",
		"MaximumStamina",
		"StaminaMax",
		"MaxEnergy",
		"MaximumEnergy",
		"EnergyMax",
		"MaxEevee",
		"MaximumEevee",
		"EeveeMax",
		"MaxDashStamina",
		"MaxSprintStamina",
		"MaxRunStamina",
		"MaxCombatStamina",
		"MaxDashEnergy",
		"MaxSprintEnergy",
		"MaxCombatEnergy"
	}
	local FlagAliases = {
		"NoStaminaCost",
		"NoEeveeDeplete",
		"NoCooldown",
		"NoDashCooldown",
		"NoSprintCooldown",
		"NoDashCost",
		"NoSprintCost",
		"NoAttackCost",
		"CanDash",
		"CanSprint",
		"CanRun",
		"CanAttack",
		"CanUseStamina",
		"HasStamina",
		"HasEevee",
		"EnoughStamina",
		"EnoughEnergy"
	}
	local GuardAliases = {
		"Exhaustion",
		"BodyFatigue",
		"BodyFatique",
		"EeveeDeplete",
		"StaminaDrain",
		"StaminaCost",
		"DashCost",
		"SprintCost",
		"AttackCost",
		"DashCooldown",
		"SprintCooldown",
		"AttackCooldown",
		"Exhausted",
		"IsExhausted",
		"Tired",
		"IsTired",
		"LowStamina",
		"OutOfStamina",
		"StaminaLocked",
		"DashDisabled",
		"SprintDisabled",
		"AttackDisabled",
		"CannotDash",
		"CannotSprint",
		"CannotAttack"
	}

	local function createAliasLookup(Aliases)
		local Lookup = {}

		for _, Name in ipairs(Aliases) do
			Lookup[string.lower(Name)] = true
		end

		return Lookup
	end

	local CurrentLookup = createAliasLookup(CurrentAliases)
	local MaxLookup = createAliasLookup(MaxAliases)
	local FlagLookup = createAliasLookup(FlagAliases)
	local GuardLookup = createAliasLookup(GuardAliases)

	local function toNumber(Value)
		if typeof(Value) == "number" then
			return Value
		end

		if typeof(Value) == "string" then
			return tonumber(Value)
		end

		return nil
	end

	local function findMainScript()
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

	local function findEntity()
		local Entities = workspace:FindFirstChild("Entities")

		if not Entities then
			return nil
		end

		return Entities:FindFirstChild(LocalPlayer.Name)
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

	local function classifyName(Name)
		local Lower = string.lower(Name)
		local HasStaminaName = string.find(Lower, "stamina", 1, true) ~= nil
		local HasEnergyName = string.find(Lower, "energy", 1, true) ~= nil
			or string.find(Lower, "eevee", 1, true) ~= nil
			or string.find(Lower, "adrenaline", 1, true) ~= nil
		local HasDashName = string.find(Lower, "dash", 1, true) ~= nil
		local HasSprintName = string.find(Lower, "sprint", 1, true) ~= nil
		local HasRunName = string.find(Lower, "run", 1, true) ~= nil
		local HasAttackName = string.find(Lower, "attack", 1, true) ~= nil
		local HasActionName = HasStaminaName or HasEnergyName or HasDashName or HasSprintName or HasRunName or HasAttackName
		local HasResourceName = HasStaminaName or HasEnergyName
		local HasMaxName = string.find(Lower, "max", 1, true) ~= nil or string.find(Lower, "maximum", 1, true) ~= nil
		local HasCostName = string.find(Lower, "cost", 1, true) ~= nil
		local HasDrainName = string.find(Lower, "drain", 1, true) ~= nil
		local HasDepleteName = string.find(Lower, "deplete", 1, true) ~= nil
		local HasCooldownName = string.find(Lower, "cooldown", 1, true) ~= nil
		local HasDelayName = string.find(Lower, "delay", 1, true) ~= nil
		local HasPercentName = string.find(Lower, "percent", 1, true) ~= nil or string.find(Lower, "ratio", 1, true) ~= nil
		local StartsWithNo = string.sub(Lower, 1, 2) == "no"
		local StartsWithCan = string.sub(Lower, 1, 3) == "can"
		local StartsWithHas = string.sub(Lower, 1, 3) == "has"
		local StartsWithEnough = string.sub(Lower, 1, 6) == "enough"
		local HasDisabledName = string.find(Lower, "disabled", 1, true) ~= nil
		local HasLockedName = string.find(Lower, "locked", 1, true) ~= nil
		local HasTiredName = string.find(Lower, "tired", 1, true) ~= nil
		local HasOutName = string.find(Lower, "outof", 1, true) ~= nil or string.find(Lower, "out_of", 1, true) ~= nil

		if FlagLookup[Lower]
			or (StartsWithNo and (HasActionName or HasCooldownName or HasCostName or HasDepleteName or HasDrainName))
			or ((StartsWithCan or StartsWithHas or StartsWithEnough) and (HasActionName or HasResourceName)) then
			return "Flags"
		end

		if GuardLookup[Lower]
			or string.find(Lower, "fatigue", 1, true)
			or string.find(Lower, "fatique", 1, true)
			or string.find(Lower, "exhaust", 1, true)
			or HasTiredName
			or HasLockedName
			or HasDisabledName
			or HasOutName
			or (HasActionName and (HasCostName or HasDrainName or HasDepleteName or HasCooldownName)) then
			return "Guard"
		end

		if MaxLookup[Lower] or (HasResourceName and HasMaxName) then
			return "Max"
		end

		if CurrentLookup[Lower] then
			return "Current"
		end

		if HasResourceName
			and not HasMaxName
			and not HasCostName
			and not HasDrainName
			and not HasDepleteName
			and not HasCooldownName
			and not HasDelayName
			and not HasPercentName
			and not string.find(Lower, "regen", 1, true)
			and not string.find(Lower, "recover", 1, true) then
			return "Current"
		end

		return nil
	end

	local function isUsefulHandleValue(GroupName, Value)
		if GroupName == "Flags" then
			local ValueType = typeof(Value)

			return ValueType == "boolean" or ValueType == "number" or ValueType == "string"
		end

		if GroupName == "Guard" or GroupName == "Current" or GroupName == "Max" then
			return toNumber(Value) ~= nil
		end

		return false
	end

	local function clearHandles()
		table.clear(StaminaFeature.Handles.Current)
		table.clear(StaminaFeature.Handles.Max)
		table.clear(StaminaFeature.Handles.Flags)
		table.clear(StaminaFeature.Handles.Guard)
	end

	local function disconnectConnections()
		for _, Connection in ipairs(StaminaFeature.Connections) do
			Connection:Disconnect()
		end

		table.clear(StaminaFeature.Connections)
	end

	local function resolveHandles(ForceRefresh)
		local Now = os.clock()

		if not ForceRefresh and (Now - StaminaFeature.LastResolveAt) < StaminaFeature.ResolveInterval then
			local HasInvalidHandle = false

			for _, Group in pairs(StaminaFeature.Handles) do
				for _, Handle in ipairs(Group) do
					if not isHandleValid(Handle) then
						HasInvalidHandle = true
						break
					end
				end

				if HasInvalidHandle then
					break
				end
			end

			if not HasInvalidHandle then
				return
			end
		end

		clearHandles()

		local SeenHandles = {
			Current = {},
			Max = {},
			Flags = {},
			Guard = {}
		}

		local function recordHandle(GroupName, Handle, Value)
			if not isUsefulHandleValue(GroupName, Value) then
				return
			end

			local Key = getHandleKey(Handle)

			if SeenHandles[GroupName][Key] then
				return
			end

			SeenHandles[GroupName][Key] = true
			table.insert(StaminaFeature.Handles[GroupName], Handle)
		end

		local function visit(Instance)
			if Instance:IsA("ValueBase") then
				local GroupName = classifyName(Instance.Name)

				if GroupName then
					recordHandle(GroupName, createValueHandle(Instance), Instance.Value)
				end
			end

			for Name, Value in pairs(Instance:GetAttributes()) do
				local GroupName = classifyName(Name)

				if GroupName then
					recordHandle(GroupName, createAttributeHandle(Instance, Name), Value)
				end
			end
		end

		local function scanGcTables()
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

			for _, Object in ipairs(Objects) do
				if type(Object) == "table" then
					for Key, Value in pairs(Object) do
						if type(Key) == "string" then
							local GroupName = classifyName(Key)

							if GroupName then
								recordHandle(GroupName, createTableHandle(Object, Key), Value)
							end
						end
					end
				end
			end
		end

		for _, Root in ipairs(buildSearchRoots()) do
			visit(Root)

			for _, Descendant in ipairs(Root:GetDescendants()) do
				visit(Descendant)
			end
		end

		scanGcTables()

		StaminaFeature.LastResolveAt = Now
	end

	local function rememberOriginalFlagValues()
		for _, Handle in ipairs(StaminaFeature.Handles.Flags) do
			local Key = getHandleKey(Handle)

			if StaminaFeature.OriginalFlagValues[Key] == nil then
				StaminaFeature.OriginalFlagValues[Key] = readHandle(Handle)
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

	local function computeTargetMax()
		local Highest = StaminaFeature.LastKnownMax

		for _, Handle in ipairs(StaminaFeature.Handles.Max) do
			local Value = toNumber(readHandle(Handle))

			if Value ~= nil and (Highest == nil or Value > Highest) then
				Highest = Value
			end
		end

		for _, Handle in ipairs(StaminaFeature.Handles.Current) do
			local Value = toNumber(readHandle(Handle))

			if Value ~= nil and (Highest == nil or Value > Highest) then
				Highest = Value
			end
		end

		StaminaFeature.LastKnownMax = Highest

		return Highest
	end

	local function applyFlagHandles()
		rememberOriginalFlagValues()

		for _, Handle in ipairs(StaminaFeature.Handles.Flags) do
			local CurrentValue = readHandle(Handle)
			local DesiredValue = getTruthyValue(CurrentValue)

			if CurrentValue ~= DesiredValue then
				writeHandle(Handle, DesiredValue)
			end
		end
	end

	local function applyGuardHandles()
		for _, Handle in ipairs(StaminaFeature.Handles.Guard) do
			local CurrentValue = readHandle(Handle)
			local DesiredValue = getZeroLikeValue(CurrentValue)

			if CurrentValue ~= DesiredValue then
				writeHandle(Handle, DesiredValue)
			end
		end
	end

	local function applyMaxHandles(TargetMax)
		if TargetMax == nil then
			return
		end

		for _, Handle in ipairs(StaminaFeature.Handles.Max) do
			local CurrentValue = toNumber(readHandle(Handle))

			if CurrentValue == nil or math.abs(CurrentValue - TargetMax) > 0.001 then
				writeHandle(Handle, TargetMax)
			end
		end
	end

	local function applyCurrentHandles(TargetMax)
		if TargetMax == nil then
			return false
		end

		local Applied = false

		for _, Handle in ipairs(StaminaFeature.Handles.Current) do
			local CurrentValue = toNumber(readHandle(Handle))

			if CurrentValue == nil or math.abs(CurrentValue - TargetMax) > 0.001 then
				writeHandle(Handle, TargetMax)
			end

			Applied = true
		end

		return Applied
	end

	local function restoreOriginalFlags()
		for _, Handle in ipairs(StaminaFeature.Handles.Flags) do
			local Key = getHandleKey(Handle)
			local OriginalValue = StaminaFeature.OriginalFlagValues[Key]

			if OriginalValue ~= nil then
				writeHandle(Handle, OriginalValue)
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

			local TargetMax = computeTargetMax()
			local HasCurrentHandles = #StaminaFeature.Handles.Current > 0
			local HasSupportHandles = #StaminaFeature.Handles.Flags > 0 or #StaminaFeature.Handles.Guard > 0

			if not HasCurrentHandles and not HasSupportHandles then
				warnMissingHandles()
				return false
			end

			applyFlagHandles()
			applyGuardHandles()
			applyMaxHandles(TargetMax)

			if HasCurrentHandles then
				return applyCurrentHandles(TargetMax)
			end

			return HasSupportHandles
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

		if self.Enabled then
			step()

			if #self.Connections == 0 then
				table.insert(self.Connections, RunService.RenderStepped:Connect(function()
					if self.Enabled then
						step()
					end
				end))
				table.insert(self.Connections, RunService.Stepped:Connect(function()
					if self.Enabled then
						step()
					end
				end))
				table.insert(self.Connections, RunService.Heartbeat:Connect(function()
					if self.Enabled then
						step()
					end
				end))
			end
		else
			restoreOriginalFlags()
			self.StepBusy = false
			disconnectConnections()
		end

		return true
	end

	function StaminaFeature:Destroy()
		self.Enabled = false
		restoreOriginalFlags()
		self.StepBusy = false
		disconnectConnections()

		if self.CharacterAddedConnection then
			self.CharacterAddedConnection:Disconnect()
			self.CharacterAddedConnection = nil
		end

		self.LastResolveAt = 0
		self.LastKnownMax = nil
		clearHandles()
		table.clear(self.OriginalFlagValues)
	end

	StaminaFeature.CharacterAddedConnection = LocalPlayer.CharacterAdded:Connect(function()
		StaminaFeature.LastResolveAt = 0
		StaminaFeature.LastKnownMax = nil
	end)

	return StaminaFeature
end
