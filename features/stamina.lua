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
		"StaminaValue"
	}
	local MaxAliases = {
		"MaxStamina",
		"MaximumStamina",
		"StaminaMax"
	}
	local FlagAliases = {
		"NoStaminaCost"
	}
	local GuardAliases = {
		"Exhaustion",
		"BodyFatigue",
		"BodyFatique"
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

	local function buildSearchRoots()
		local Character = LocalPlayer.Character
		local MainScript = findMainScript()
		local Stats = MainScript and MainScript:FindFirstChild("Stats")
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
		addRoot(LocalPlayer:FindFirstChild("Stats"))
		addRoot(Character and Character:FindFirstChild("Stats"))
		addRoot(LocalPlayer:FindFirstChild("Data"))
		addRoot(Character and Character:FindFirstChild("Data"))
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
		if not Handle or not Handle.Instance then
			return "nil"
		end

		if Handle.Kind == "attribute" then
			return getInstanceKey(Handle.Instance) .. "@" .. tostring(Handle.Attribute)
		end

		return getInstanceKey(Handle.Instance)
	end

	local function isHandleValid(Handle)
		if not Handle or not Handle.Instance then
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

		if FlagLookup[Lower] then
			return "Flags"
		end

		if GuardLookup[Lower] then
			return "Guard"
		end

		if MaxLookup[Lower] or (string.find(Lower, "stamina", 1, true) and string.find(Lower, "max", 1, true)) then
			return "Max"
		end

		if CurrentLookup[Lower] then
			return "Current"
		end

		if string.find(Lower, "stamina", 1, true)
			and not string.find(Lower, "max", 1, true)
			and not string.find(Lower, "cost", 1, true)
			and not string.find(Lower, "regen", 1, true)
			and not string.find(Lower, "recover", 1, true)
			and not string.find(Lower, "delay", 1, true) then
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

		for _, Root in ipairs(buildSearchRoots()) do
			visit(Root)

			for _, Descendant in ipairs(Root:GetDescendants()) do
				visit(Descendant)
			end
		end

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
	end

	function StaminaFeature:SetEnabled(Value)
		self.Enabled = Value and true or false
		self.LastResolveAt = 0

		if self.Enabled then
			step()

			if not self.Connection then
				self.Connection = RunService.Heartbeat:Connect(function()
					if not self.Enabled then
						return
					end

					step()
				end)
			end
		else
			restoreOriginalFlags()

			if self.Connection then
				self.Connection:Disconnect()
				self.Connection = nil
			end
		end

		return true
	end

	function StaminaFeature:Destroy()
		self.Enabled = false
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
		table.clear(self.OriginalFlagValues)
	end

	StaminaFeature.CharacterAddedConnection = LocalPlayer.CharacterAdded:Connect(function()
		StaminaFeature.LastResolveAt = 0
		StaminaFeature.LastKnownMax = nil
	end)

	return StaminaFeature
end
