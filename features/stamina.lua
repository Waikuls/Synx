return function(Config)
	local Players = game:GetService("Players")
	local RunService = game:GetService("RunService")
	local Workspace = game:GetService("Workspace")
	local LocalPlayer = Players.LocalPlayer

	local DEFAULT_DEBUG_PROFILE = "Run"
	local DEBUG_PROFILES = {
		Free = true,
		Run = true,
		Dash = true,
		Attack = true
	}
	local VAR001_FIELDS = {
		"M1StaminaCost",
		"M2StaminaCost",
		"currentM1StaminaCost",
		"currentM2StaminaCost"
	}

	local StaminaFeature = {
		Enabled = false,
		DebugEnabled = false,
		DebugProfile = DEFAULT_DEBUG_PROFILE,
		CharacterAddedConnection = nil,
		HeartbeatConnection = nil,
		Handles = nil,
		LastReason = "idle",
		LastSkillStatus = "not inspected",
		LastPatchSummary = "standby",
		LastVar001Status = "not loaded",
		LastApplyAt = 0,
		RestoreValues = {},
		Var001State = nil
	}

	local function formatValue(Value)
		if typeof(Value) == "boolean" then
			return Value and "true" or "false"
		end

		if typeof(Value) == "number" then
			local Text = string.format("%.3f", Value)
			Text = string.gsub(Text, "0+$", "")
			Text = string.gsub(Text, "%.$", "")
			return Text
		end

		if Value == nil then
			return "N/A"
		end

		return tostring(Value)
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

	local function getTrackedValue(Parent, Name)
		if not Parent then
			return nil
		end

		local Child = Parent:FindFirstChild(Name)

		if Child and Child:IsA("ValueBase") then
			return {
				Kind = "ValueBase",
				Object = Child,
				Name = Name
			}
		end

		local Success, AttributeValue = pcall(function()
			return Parent:GetAttribute(Name)
		end)

		if Success and AttributeValue ~= nil then
			return {
				Kind = "Attribute",
				Object = Parent,
				Name = Name
			}
		end

		return nil
	end

	local function isTrackedValueAlive(TrackedValue)
		return TrackedValue ~= nil
			and TrackedValue.Object ~= nil
			and TrackedValue.Object.Parent ~= nil
	end

	local function getTrackedValueData(TrackedValue)
		if not isTrackedValueAlive(TrackedValue) then
			return nil
		end

		if TrackedValue.Kind == "Attribute" then
			local Success, Value = pcall(function()
				return TrackedValue.Object:GetAttribute(TrackedValue.Name)
			end)

			if Success then
				return Value
			end

			return nil
		end

		local Success, Value = pcall(function()
			return TrackedValue.Object.Value
		end)

		if Success then
			return Value
		end

		return nil
	end

	local function setTrackedValueData(TrackedValue, Value)
		if not isTrackedValueAlive(TrackedValue) then
			return false, false
		end

		local CurrentValue = getTrackedValueData(TrackedValue)

		if CurrentValue == Value then
			return true, false
		end

		local Success

		if TrackedValue.Kind == "Attribute" then
			Success = pcall(function()
				TrackedValue.Object:SetAttribute(TrackedValue.Name, Value)
			end)
		else
			Success = pcall(function()
				TrackedValue.Object.Value = Value
			end)
		end

		return Success, Success
	end

	local function buildRestoreKey(TrackedValue)
		if not isTrackedValueAlive(TrackedValue) then
			return nil
		end

		local Success, FullName = pcall(function()
			return TrackedValue.Object:GetFullName()
		end)

		if Success and typeof(FullName) == "string" then
			return string.format("%s::%s::%s", TrackedValue.Kind, FullName, TrackedValue.Name)
		end

		return string.format("%s::%s", TrackedValue.Kind, TrackedValue.Name)
	end

	local function rememberRestoreValue(Label, TrackedValue)
		local RestoreKey = buildRestoreKey(TrackedValue)
		local ExistingEntry = StaminaFeature.RestoreValues[Label]

		if RestoreKey == nil then
			return
		end

		if ExistingEntry and ExistingEntry.Key == RestoreKey then
			return
		end

		StaminaFeature.RestoreValues[Label] = {
			Key = RestoreKey,
			TrackedValue = TrackedValue,
			Value = getTrackedValueData(TrackedValue)
		}
	end

	local function restoreTrackedValues()
		for Label, RestoreEntry in pairs(StaminaFeature.RestoreValues) do
			local TrackedValue = RestoreEntry.TrackedValue

			if isTrackedValueAlive(TrackedValue) and RestoreEntry.Key == buildRestoreKey(TrackedValue) then
				pcall(function()
					setTrackedValueData(TrackedValue, RestoreEntry.Value)
				end)
			end

			StaminaFeature.RestoreValues[Label] = nil
		end
	end

	local function resolveCharacter()
		local Character = LocalPlayer.Character

		if Character and Character.Parent and Character:FindFirstChild("MainScript") then
			return Character
		end

		local Entities = Workspace:FindFirstChild("Entities")

		if Entities then
			local EntityCharacter = Entities:FindFirstChild(LocalPlayer.Name)

			if EntityCharacter and EntityCharacter.Parent and EntityCharacter:FindFirstChild("MainScript") then
				return EntityCharacter
			end
		end

		if Character and Character.Parent then
			return Character
		end

		return nil
	end

	local function resolveSkillStatus(Character, MainScript)
		if not Character then
			return "no character"
		end

		for _, Child in ipairs(Character:GetChildren()) do
			if Child:IsA("Tool") and Child:FindFirstChild("CastSkill") then
				local CooldownFolder = MainScript and MainScript:FindFirstChild("UCooldown")
				local CooldownState = CooldownFolder and "cooldown found" or "cooldown missing"
				return string.format("%s (%s)", Child.Name, CooldownState)
			end
		end

		return "no skill tool"
	end

	local function resolveVar001(MainScript)
		local ModuleScript = MainScript and MainScript:FindFirstChild("Var001")

		if not ModuleScript then
			return nil, "Var001 missing"
		end

		if not ModuleScript:IsA("ModuleScript") then
			return nil, "Var001 is not ModuleScript"
		end

		local Success, Result = pcall(require, ModuleScript)

		if not Success then
			return nil, string.format("Var001 require failed: %s", tostring(Result))
		end

		if type(Result) ~= "table" then
			return nil, string.format("Var001 returned %s", type(Result))
		end

		return {
			ModuleScript = ModuleScript,
			Data = Result
		}, "ready"
	end

	local function resolveHandles()
		local Character = resolveCharacter()

		if not Character then
			StaminaFeature.LastReason = "character missing"
			StaminaFeature.LastVar001Status = "not loaded"
			return nil
		end

		local MainScript = Character:FindFirstChild("MainScript")

		if not MainScript then
			StaminaFeature.LastReason = "MainScript missing"
			StaminaFeature.LastVar001Status = "not loaded"
			return nil
		end

		local Stats = MainScript:FindFirstChild("Stats")
		local Attributes = MainScript:FindFirstChild("Attributes")
		local Var001, Var001Status = resolveVar001(MainScript)

		StaminaFeature.LastReason = "ready"
		StaminaFeature.LastSkillStatus = resolveSkillStatus(Character, MainScript)
		StaminaFeature.LastVar001Status = Var001Status

		return {
			Character = Character,
			MainScript = MainScript,
			Stats = Stats,
			Attributes = Attributes,
			Stamina = getTrackedValue(Stats, "Stamina"),
			MaxStamina = getTrackedValue(Stats, "MaxStamina"),
			NoStaminaCost = getTrackedValue(Stats, "NoStaminaCost"),
			Exhaustion = getTrackedValue(Stats, "Exhaustion"),
			StaminaInStat = getTrackedValue(Stats, "StaminaInStat"),
			Exhausted = getTrackedValue(Attributes, "Exhausted"),
			StaminaRegenPeriod = getTrackedValue(Attributes, "StaminaRegenPeriod"),
			StaminaRegenPercent = getTrackedValue(Attributes, "StaminaRegenPercent"),
			ExhaustionDeplete = getTrackedValue(Attributes, "ExhaustionDeplete"),
			ExhaustionDepletePeriod = getTrackedValue(Attributes, "ExhaustionDepletePeriod"),
			StaminaInStatBoost = getTrackedValue(Attributes, "StaminaInStat StatBoost"),
			Var001 = Var001
		}
	end

	local function refreshHandles()
		StaminaFeature.Handles = resolveHandles()
		return StaminaFeature.Handles
	end

	local function isHandleSetAlive(Handles)
		return Handles ~= nil
			and Handles.MainScript ~= nil
			and Handles.MainScript.Parent ~= nil
	end

	local function ensureVar001State(Var001)
		if not Var001 or type(Var001.Data) ~= "table" then
			return false
		end

		local ExistingState = StaminaFeature.Var001State

		if ExistingState
			and ExistingState.ModuleScript == Var001.ModuleScript
			and ExistingState.Data == Var001.Data then
			return true
		end

		local OriginalFields = {}

		for _, FieldName in ipairs(VAR001_FIELDS) do
			OriginalFields[FieldName] = Var001.Data[FieldName]
		end

		StaminaFeature.Var001State = {
			ModuleScript = Var001.ModuleScript,
			Data = Var001.Data,
			OriginalFields = OriginalFields
		}

		return true
	end

	local function restoreVar001State()
		local State = StaminaFeature.Var001State

		if not State or type(State.Data) ~= "table" then
			StaminaFeature.Var001State = nil
			return
		end

		local RestoredCount = 0

		for FieldName, OriginalValue in pairs(State.OriginalFields) do
			local Success = pcall(function()
				State.Data[FieldName] = OriginalValue
			end)

			if Success then
				RestoredCount = RestoredCount + 1
			end
		end

		if RestoredCount > 0 then
			StaminaFeature.LastVar001Status = string.format("restored %d field(s)", RestoredCount)
		end

		StaminaFeature.Var001State = nil
	end

	local function patchVar001(Var001)
		if not Var001 or type(Var001.Data) ~= "table" then
			return false
		end

		ensureVar001State(Var001)

		local SeenFieldCount = 0

		for _, FieldName in ipairs(VAR001_FIELDS) do
			if type(Var001.Data[FieldName]) == "number" then
				SeenFieldCount = SeenFieldCount + 1

				pcall(function()
					Var001.Data[FieldName] = 0
				end)
			end
		end

		if SeenFieldCount > 0 then
			StaminaFeature.LastVar001Status = string.format("patched %d field(s)", SeenFieldCount)
			return true
		end

		StaminaFeature.LastVar001Status = "Var001 fields missing"
		return false
	end

	local function collectPatchTargets(Handles)
		local TargetStamina = toNumber(getTrackedValueData(Handles.MaxStamina))

		if TargetStamina == nil then
			TargetStamina = toNumber(getTrackedValueData(Handles.StaminaInStat))
		end

		if TargetStamina == nil then
			TargetStamina = toNumber(getTrackedValueData(Handles.Stamina))
		end

		local ExhaustedValue = getTrackedValueData(Handles.Exhausted)
		local ExhaustedTarget = nil

		if typeof(ExhaustedValue) == "boolean" then
			ExhaustedTarget = false
		elseif typeof(ExhaustedValue) == "number" then
			ExhaustedTarget = 0
		end

		return {
			TargetStamina = TargetStamina,
			ExhaustedTarget = ExhaustedTarget
		}
	end

	local function applyPatch()
		local Handles = StaminaFeature.Handles

		if not isHandleSetAlive(Handles) then
			Handles = refreshHandles()
		end

		if not Handles then
			StaminaFeature.LastPatchSummary = "waiting for handles"
			return false
		end

		local PatchTargets = collectPatchTargets(Handles)
		local AppliedParts = {}

		if PatchTargets.TargetStamina ~= nil then
			local Success = setTrackedValueData(Handles.Stamina, PatchTargets.TargetStamina)

			if Success then
				table.insert(AppliedParts, "stamina lock")
			end
		end

		if isTrackedValueAlive(Handles.NoStaminaCost) then
			rememberRestoreValue("NoStaminaCost", Handles.NoStaminaCost)

			local Success = setTrackedValueData(Handles.NoStaminaCost, true)

			if Success then
				table.insert(AppliedParts, "no cost")
			end
		end

		if toNumber(getTrackedValueData(Handles.Exhaustion)) ~= nil then
			local Success = setTrackedValueData(Handles.Exhaustion, 0)

			if Success then
				table.insert(AppliedParts, "exhaustion reset")
			end
		end

		if PatchTargets.ExhaustedTarget ~= nil then
			local Success = setTrackedValueData(Handles.Exhausted, PatchTargets.ExhaustedTarget)

			if Success then
				table.insert(AppliedParts, "exhausted clear")
			end
		end

		if patchVar001(Handles.Var001) then
			table.insert(AppliedParts, "Var001 cost zero")
		end

		if #AppliedParts == 0 then
			StaminaFeature.LastPatchSummary = "no writable stamina fields"
			StaminaFeature.LastReason = "patch idle"
			return false
		end

		StaminaFeature.LastApplyAt = os.clock()
		StaminaFeature.LastPatchSummary = table.concat(AppliedParts, ", ")
		StaminaFeature.LastReason = "patched"

		return true
	end

	local function stopHeartbeat()
		if StaminaFeature.HeartbeatConnection then
			StaminaFeature.HeartbeatConnection:Disconnect()
			StaminaFeature.HeartbeatConnection = nil
		end
	end

	local function ensureHeartbeat()
		if StaminaFeature.HeartbeatConnection then
			return
		end

		StaminaFeature.HeartbeatConnection = RunService.Heartbeat:Connect(function()
			if not StaminaFeature.Enabled then
				return
			end

			applyPatch()
		end)
	end

	local function resetPatchedState()
		restoreTrackedValues()
		restoreVar001State()
	end

	local function buildStatusLines()
		local Handles = refreshHandles()
		local Mode = StaminaFeature.Enabled and "active patch" or "standby"

		if not Handles then
			return {
				string.format("enabled: %s", StaminaFeature.Enabled and "true" or "false"),
				string.format("mode: %s", Mode),
				string.format("state: %s", StaminaFeature.LastReason),
				string.format("patch: %s", StaminaFeature.LastPatchSummary),
				string.format("var001: %s", StaminaFeature.LastVar001Status)
			}
		end

		return {
			string.format("enabled: %s", StaminaFeature.Enabled and "true" or "false"),
			string.format("mode: %s", Mode),
			string.format("state: %s", StaminaFeature.LastReason),
			string.format("patch: %s", StaminaFeature.LastPatchSummary),
			string.format("stamina: %s / %s", formatValue(getTrackedValueData(Handles.Stamina)), formatValue(getTrackedValueData(Handles.MaxStamina))),
			string.format("stamina stat: %s", formatValue(getTrackedValueData(Handles.StaminaInStat))),
			string.format("exhaustion: %s", formatValue(getTrackedValueData(Handles.Exhaustion))),
			string.format("no stamina cost: %s", formatValue(getTrackedValueData(Handles.NoStaminaCost))),
			string.format("exhausted attr: %s", formatValue(getTrackedValueData(Handles.Exhausted))),
			string.format("var001: %s", StaminaFeature.LastVar001Status),
			string.format("skill: %s", StaminaFeature.LastSkillStatus)
		}
	end

	local function buildDebugLines()
		local Handles = refreshHandles()

		return {
			string.format("debug enabled: %s", StaminaFeature.DebugEnabled and "true" or "false"),
			string.format("profile: %s", StaminaFeature.DebugProfile),
			string.format("heartbeat: %s", StaminaFeature.HeartbeatConnection and "true" or "false"),
			string.format("character: %s", Handles and Handles.Character:GetFullName() or "N/A"),
			string.format("last apply: %s", StaminaFeature.LastApplyAt > 0 and formatValue(StaminaFeature.LastApplyAt) or "N/A"),
			string.format("regen period: %s", Handles and formatValue(getTrackedValueData(Handles.StaminaRegenPeriod)) or "N/A"),
			string.format("regen percent: %s", Handles and formatValue(getTrackedValueData(Handles.StaminaRegenPercent)) or "N/A"),
			string.format("deplete: %s", Handles and formatValue(getTrackedValueData(Handles.ExhaustionDeplete)) or "N/A"),
			string.format("deplete period: %s", Handles and formatValue(getTrackedValueData(Handles.ExhaustionDepletePeriod)) or "N/A"),
			string.format("stamina boost: %s", Handles and formatValue(getTrackedValueData(Handles.StaminaInStatBoost)) or "N/A"),
			string.format("var001: %s", StaminaFeature.LastVar001Status),
			string.format("skill: %s", StaminaFeature.LastSkillStatus)
		}
	end

	function StaminaFeature:SetEnabled(Value)
		self.Enabled = Value == true
		refreshHandles()

		if self.Enabled then
			self.LastPatchSummary = "arming patch"
			self.LastReason = self.Handles and "arming patch" or self.LastReason
			ensureHeartbeat()
			applyPatch()
		else
			stopHeartbeat()
			resetPatchedState()
			self.LastPatchSummary = "disabled"
			self.LastReason = "idle"
		end

		return true
	end

	function StaminaFeature:SetDebugEnabled(Value)
		self.DebugEnabled = Value == true
	end

	function StaminaFeature:IsDebugEnabled()
		return self.DebugEnabled == true
	end

	function StaminaFeature:GetDebugProfile()
		return self.DebugProfile
	end

	function StaminaFeature:SetDebugProfile(Profile)
		if type(Profile) == "string" and DEBUG_PROFILES[Profile] then
			self.DebugProfile = Profile
		end
	end

	function StaminaFeature:StartDebugCapture(Profile)
		self:SetDebugEnabled(true)
		self:SetDebugProfile(Profile)
		refreshHandles()
	end

	function StaminaFeature:ClearDebugCapture()
		self:SetDebugEnabled(false)
		refreshHandles()
	end

	function StaminaFeature:GetStatusLines()
		return buildStatusLines()
	end

	function StaminaFeature:GetDebugLines()
		return buildDebugLines()
	end

	function StaminaFeature:Destroy()
		stopHeartbeat()
		resetPatchedState()

		if self.CharacterAddedConnection then
			self.CharacterAddedConnection:Disconnect()
			self.CharacterAddedConnection = nil
		end

		self.Enabled = false
		self.DebugEnabled = false
		self.Handles = nil
		self.LastReason = "destroyed"
		self.LastPatchSummary = "destroyed"
		self.LastSkillStatus = "not inspected"
		self.LastVar001Status = "not loaded"
		self.LastApplyAt = 0
	end

	StaminaFeature.CharacterAddedConnection = LocalPlayer.CharacterAdded:Connect(function()
		resetPatchedState()
		StaminaFeature.Handles = nil
		StaminaFeature.LastReason = "character changed"
		StaminaFeature.LastPatchSummary = "character changed"
		StaminaFeature.LastSkillStatus = "not inspected"
		StaminaFeature.LastVar001Status = "not loaded"

		task.defer(function()
			refreshHandles()

			if StaminaFeature.Enabled then
				applyPatch()
			end
		end)
	end)

	refreshHandles()

	return StaminaFeature
end
