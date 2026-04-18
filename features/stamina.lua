return function(Config)
	local Players = game:GetService("Players")
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local LocalPlayer = Players.LocalPlayer

	local StaminaFeature = {
		Enabled = false,
		Destroyed = false,
		Applying = false,
		RefreshInterval = 0.15,
		ResolveInterval = 1,
		LastResolveAt = 0,
		CurrentHandles = {},
		NoCostHandles = {},
		MaxHandle = nil,
		PeakValues = {},
		OriginalNoCostValues = {},
		ChangeConnections = {},
		CharacterAddedConnection = nil
	}

	local CurrentAliases = {
		"Stamina",
		"StaminaInStat"
	}
	local MaxAliases = {
		"MaxStamina",
		"MaximumStamina",
		"StaminaMax"
	}
	local NoCostAliases = {
		"NoStaminaCost"
	}

	local function createAliasRanking(Aliases)
		local Ranking = {}

		for Index, Name in ipairs(Aliases) do
			Ranking[string.lower(Name)] = Index
		end

		return Ranking
	end

	local CurrentRanking = createAliasRanking(CurrentAliases)
	local MaxRanking = createAliasRanking(MaxAliases)
	local NoCostRanking = createAliasRanking(NoCostAliases)

	local function toNumber(Value)
		if typeof(Value) == "number" then
			return Value
		end

		if typeof(Value) == "string" then
			return tonumber(Value)
		end

		return nil
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

	local function buildSearchRoots()
		local Character = LocalPlayer.Character
		local MainScript = findEntityMainScript()
		local Stats = MainScript and MainScript:FindFirstChild("Stats")
		local Roots = {}
		local Seen = {}

		local function addRoot(Root, Priority)
			if not Root or Seen[Root] then
				return
			end

			Seen[Root] = true
			table.insert(Roots, {
				Root = Root,
				Priority = Priority
			})
		end

		addRoot(Stats, 0)
		addRoot(MainScript, 1)
		addRoot(LocalPlayer:FindFirstChild("Stats"), 2)
		addRoot(Character and Character:FindFirstChild("Stats"), 2)
		addRoot(LocalPlayer:FindFirstChild("Data"), 2)
		addRoot(Character and Character:FindFirstChild("Data"), 2)
		addRoot(Character, 3)
		addRoot(LocalPlayer, 4)

		for _, RootName in ipairs({"PlayerData", "Data", "Stats"}) do
			local Root = ReplicatedStorage:FindFirstChild(RootName)

			if Root then
				addRoot(Root:FindFirstChild(LocalPlayer.Name), 5)
				addRoot(Root:FindFirstChild(tostring(LocalPlayer.UserId)), 5)

				local PlayersFolder = Root:FindFirstChild("Players")

				if PlayersFolder then
					addRoot(PlayersFolder:FindFirstChild(LocalPlayer.Name), 5)
					addRoot(PlayersFolder:FindFirstChild(tostring(LocalPlayer.UserId)), 5)
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

	local function getHandleName(Handle)
		if not Handle then
			return nil
		end

		if Handle.Kind == "attribute" then
			return Handle.Attribute
		end

		return Handle.Instance and Handle.Instance.Name or nil
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

	local function normalizeNumberForHandle(Handle, Value)
		if not Handle or Handle.Kind ~= "value" then
			return Value
		end

		local Instance = Handle.Instance

		if Instance and Instance:IsA("IntValue") then
			return math.floor(Value + 0.5)
		end

		return Value
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

		if typeof(Value) == "number" then
			Value = normalizeNumberForHandle(Handle, Value)
		end

		return pcall(function()
			Handle.Instance.Value = Value
		end)
	end

	local function getModeScore(Handle)
		if Handle.Kind == "value" then
			return 0
		end

		return 1
	end

	local function isBetterCandidate(NewCandidate, CurrentCandidate)
		if not CurrentCandidate then
			return true
		end

		if NewCandidate.AliasRank ~= CurrentCandidate.AliasRank then
			return NewCandidate.AliasRank < CurrentCandidate.AliasRank
		end

		if NewCandidate.Priority ~= CurrentCandidate.Priority then
			return NewCandidate.Priority < CurrentCandidate.Priority
		end

		local NewScore = getModeScore(NewCandidate.Handle)
		local CurrentScore = getModeScore(CurrentCandidate.Handle)

		if NewScore ~= CurrentScore then
			return NewScore < CurrentScore
		end

		local NewName = string.lower(getHandleName(NewCandidate.Handle) or "")
		local CurrentName = string.lower(getHandleName(CurrentCandidate.Handle) or "")

		return NewName < CurrentName
	end

	local function scanHandles()
		local CurrentCandidates = {}
		local NoCostCandidates = {}
		local MaxCandidate = nil

		local function considerNumericCandidate(Store, Ranking, Handle, Name, Value, Priority)
			local AliasRank = Ranking[string.lower(Name)]
			local NumberValue = toNumber(Value)

			if AliasRank == nil or NumberValue == nil then
				return
			end

			local Candidate = {
				AliasRank = AliasRank,
				Priority = Priority,
				Handle = Handle
			}

			if isBetterCandidate(Candidate, Store[string.lower(Name)]) then
				Store[string.lower(Name)] = Candidate
			end
		end

		local function considerNoCostCandidate(Handle, Name, Value, Priority)
			local AliasRank = NoCostRanking[string.lower(Name)]

			if AliasRank == nil then
				return
			end

			local ValueType = typeof(Value)

			if ValueType ~= "boolean" and ValueType ~= "number" and ValueType ~= "string" then
				return
			end

			local Candidate = {
				AliasRank = AliasRank,
				Priority = Priority,
				Handle = Handle
			}

			local Key = string.lower(Name)

			if isBetterCandidate(Candidate, NoCostCandidates[Key]) then
				NoCostCandidates[Key] = Candidate
			end
		end

		local function visit(Instance, Priority)
			if Instance:IsA("ValueBase") then
				local Handle = createValueHandle(Instance)
				local Value = readHandle(Handle)

				considerNumericCandidate(CurrentCandidates, CurrentRanking, Handle, Instance.Name, Value, Priority)

				local MaxAliasRank = MaxRanking[string.lower(Instance.Name)]
				local NumberValue = toNumber(Value)

				if MaxAliasRank ~= nil and NumberValue ~= nil then
					local Candidate = {
						AliasRank = MaxAliasRank,
						Priority = Priority,
						Handle = Handle
					}

					if isBetterCandidate(Candidate, MaxCandidate) then
						MaxCandidate = Candidate
					end
				end

				considerNoCostCandidate(Handle, Instance.Name, Value, Priority)
			end

			for Name, Value in pairs(Instance:GetAttributes()) do
				local Handle = createAttributeHandle(Instance, Name)

				considerNumericCandidate(CurrentCandidates, CurrentRanking, Handle, Name, Value, Priority)

				local MaxAliasRank = MaxRanking[string.lower(Name)]
				local NumberValue = toNumber(Value)

				if MaxAliasRank ~= nil and NumberValue ~= nil then
					local Candidate = {
						AliasRank = MaxAliasRank,
						Priority = Priority,
						Handle = Handle
					}

					if isBetterCandidate(Candidate, MaxCandidate) then
						MaxCandidate = Candidate
					end
				end

				considerNoCostCandidate(Handle, Name, Value, Priority)
			end
		end

		for _, RootInfo in ipairs(buildSearchRoots()) do
			visit(RootInfo.Root, RootInfo.Priority)

			for _, Descendant in ipairs(RootInfo.Root:GetDescendants()) do
				visit(Descendant, RootInfo.Priority)
			end
		end

		local CurrentHandles = {}
		local NoCostHandles = {}
		local SeenCurrent = {}
		local SeenNoCost = {}

		for _, Alias in ipairs(CurrentAliases) do
			local Candidate = CurrentCandidates[string.lower(Alias)]

			if Candidate then
				local Key = getHandleKey(Candidate.Handle)

				if not SeenCurrent[Key] then
					SeenCurrent[Key] = true
					table.insert(CurrentHandles, Candidate.Handle)
				end
			end
		end

		for _, Alias in ipairs(NoCostAliases) do
			local Candidate = NoCostCandidates[string.lower(Alias)]

			if Candidate then
				local Key = getHandleKey(Candidate.Handle)

				if not SeenNoCost[Key] then
					SeenNoCost[Key] = true
					table.insert(NoCostHandles, Candidate.Handle)
				end
			end
		end

		StaminaFeature.CurrentHandles = CurrentHandles
		StaminaFeature.NoCostHandles = NoCostHandles
		StaminaFeature.MaxHandle = MaxCandidate and MaxCandidate.Handle or nil
		StaminaFeature.LastResolveAt = os.clock()
	end

	local function disconnectChangeConnections()
		for _, Connection in ipairs(StaminaFeature.ChangeConnections) do
			Connection:Disconnect()
		end

		table.clear(StaminaFeature.ChangeConnections)
	end

	local function markDirty()
		StaminaFeature.LastResolveAt = 0
	end

	local function connectHandleChange(Handle)
		if not isHandleValid(Handle) then
			return
		end

		local Connection

		if Handle.Kind == "attribute" then
			Connection = Handle.Instance:GetAttributeChangedSignal(Handle.Attribute):Connect(function()
				if StaminaFeature.Enabled and not StaminaFeature.Applying then
					task.defer(function()
						if StaminaFeature.Enabled and not StaminaFeature.Destroyed then
							StaminaFeature:Step(false)
						end
					end)
				end
			end)
		else
			Connection = Handle.Instance:GetPropertyChangedSignal("Value"):Connect(function()
				if StaminaFeature.Enabled and not StaminaFeature.Applying then
					task.defer(function()
						if StaminaFeature.Enabled and not StaminaFeature.Destroyed then
							StaminaFeature:Step(false)
						end
					end)
				end
			end)
		end

		table.insert(StaminaFeature.ChangeConnections, Connection)
	end

	local function refreshHandleConnections()
		disconnectChangeConnections()

		for _, Handle in ipairs(StaminaFeature.CurrentHandles) do
			connectHandleChange(Handle)
		end

		for _, Handle in ipairs(StaminaFeature.NoCostHandles) do
			connectHandleChange(Handle)
		end

		if StaminaFeature.MaxHandle then
			connectHandleChange(StaminaFeature.MaxHandle)
		end
	end

	local function resolveHandles(ForceRefresh)
		local Now = os.clock()

		if not ForceRefresh
			and StaminaFeature.LastResolveAt > 0
			and (Now - StaminaFeature.LastResolveAt) < StaminaFeature.ResolveInterval then
			local HandlesValid = true

			for _, Handle in ipairs(StaminaFeature.CurrentHandles) do
				if not isHandleValid(Handle) then
					HandlesValid = false
					break
				end
			end

			if HandlesValid then
				for _, Handle in ipairs(StaminaFeature.NoCostHandles) do
					if not isHandleValid(Handle) then
						HandlesValid = false
						break
					end
				end
			end

			if HandlesValid and StaminaFeature.MaxHandle and not isHandleValid(StaminaFeature.MaxHandle) then
				HandlesValid = false
			end

			if HandlesValid then
				return
			end
		end

		scanHandles()
		refreshHandleConnections()
	end

	local function rememberOriginalNoCostValues()
		for _, Handle in ipairs(StaminaFeature.NoCostHandles) do
			local Key = getHandleKey(Handle)

			if StaminaFeature.OriginalNoCostValues[Key] == nil then
				StaminaFeature.OriginalNoCostValues[Key] = readHandle(Handle)
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

	local function computeTargetMax()
		local Target = toNumber(readHandle(StaminaFeature.MaxHandle))

		for _, Handle in ipairs(StaminaFeature.CurrentHandles) do
			local CurrentValue = toNumber(readHandle(Handle))
			local Key = getHandleKey(Handle)
			local PeakValue = StaminaFeature.PeakValues[Key]

			if CurrentValue ~= nil and (Target == nil or CurrentValue > Target) then
				Target = CurrentValue
			end

			if PeakValue ~= nil and (Target == nil or PeakValue > Target) then
				Target = PeakValue
			end
		end

		return Target
	end

	local function applyNoCostHandles()
		rememberOriginalNoCostValues()

		for _, Handle in ipairs(StaminaFeature.NoCostHandles) do
			local CurrentValue = readHandle(Handle)
			local DesiredValue = getTruthyValue(CurrentValue)

			if CurrentValue ~= DesiredValue then
				writeHandle(Handle, DesiredValue)
			end
		end
	end

	local function applyCurrentHandles()
		local TargetMax = computeTargetMax()

		if TargetMax == nil then
			return false
		end

		for _, Handle in ipairs(StaminaFeature.CurrentHandles) do
			local Key = getHandleKey(Handle)
			local CurrentValue = toNumber(readHandle(Handle))
			local DesiredValue = TargetMax
			local PeakValue = StaminaFeature.PeakValues[Key]

			if PeakValue ~= nil and PeakValue > DesiredValue then
				DesiredValue = PeakValue
			end

			if CurrentValue ~= nil and CurrentValue > DesiredValue then
				DesiredValue = CurrentValue
			end

			StaminaFeature.PeakValues[Key] = DesiredValue

			if CurrentValue == nil or math.abs(CurrentValue - DesiredValue) > 0.001 then
				writeHandle(Handle, DesiredValue)
			end
		end

		return true
	end

	local function restoreNoCostHandles()
		for _, Handle in ipairs(StaminaFeature.NoCostHandles) do
			local Key = getHandleKey(Handle)
			local OriginalValue = StaminaFeature.OriginalNoCostValues[Key]

			if OriginalValue ~= nil then
				writeHandle(Handle, OriginalValue)
			end
		end

		table.clear(StaminaFeature.OriginalNoCostValues)
	end

	function StaminaFeature:Step(ForceRefresh)
		resolveHandles(ForceRefresh)

		if not self.Enabled then
			return false
		end

		self.Applying = true

		local Success = pcall(function()
			applyNoCostHandles()
			applyCurrentHandles()
		end)

		self.Applying = false

		return Success
	end

	function StaminaFeature:SetEnabled(Value)
		local Enabled = Value and true or false

		if self.Enabled == Enabled then
			return true
		end

		self.Enabled = Enabled
		markDirty()

		if self.Enabled then
			self:Step(true)
		else
			restoreNoCostHandles()
		end

		return true
	end

	function StaminaFeature:Destroy()
		if self.Destroyed then
			return
		end

		self.Enabled = false
		self.Destroyed = true
		self.Applying = false

		restoreNoCostHandles()
		disconnectChangeConnections()

		if self.CharacterAddedConnection then
			self.CharacterAddedConnection:Disconnect()
			self.CharacterAddedConnection = nil
		end

		table.clear(self.CurrentHandles)
		table.clear(self.NoCostHandles)
		table.clear(self.PeakValues)
		self.MaxHandle = nil
		self.LastResolveAt = 0
	end

	StaminaFeature.CharacterAddedConnection = LocalPlayer.CharacterAdded:Connect(function()
		markDirty()
	end)

	task.spawn(function()
		while not StaminaFeature.Destroyed do
			if StaminaFeature.Enabled then
				StaminaFeature:Step(false)
				task.wait(StaminaFeature.RefreshInterval)
			else
				task.wait(0.4)
			end
		end
	end)

	return StaminaFeature
end
