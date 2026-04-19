return function(Config)
	local Players = game:GetService("Players")
	local Workspace = game:GetService("Workspace")
	local LocalPlayer = Players.LocalPlayer

	local DEFAULT_DEBUG_PROFILE = "Run"
	local DEBUG_PROFILES = {
		Free = true,
		Run = true,
		Dash = true,
		Attack = true
	}

	local StaminaFeature = {
		Enabled = false,
		DebugEnabled = false,
		DebugProfile = DEFAULT_DEBUG_PROFILE,
		CharacterAddedConnection = nil,
		Handles = nil,
		LastReason = "idle",
		LastSkillStatus = "not inspected"
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

	local function getObjectValue(Object)
		if not Object or not Object:IsA("ValueBase") then
			return nil
		end

		local Success, Value = pcall(function()
			return Object.Value
		end)

		if Success then
			return Value
		end

		return nil
	end

	local function getValueChild(Parent, Name)
		if not Parent then
			return nil
		end

		local Child = Parent:FindFirstChild(Name)

		if Child and Child:IsA("ValueBase") then
			return Child
		end

		return nil
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

	local function resolveHandles()
		local Character = resolveCharacter()

		if not Character then
			StaminaFeature.LastReason = "character missing"
			return nil
		end

		local MainScript = Character:FindFirstChild("MainScript")

		if not MainScript then
			StaminaFeature.LastReason = "MainScript missing"
			return nil
		end

		local Stats = MainScript:FindFirstChild("Stats")
		local Attributes = MainScript:FindFirstChild("Attributes")

		StaminaFeature.LastReason = "ready"
		StaminaFeature.LastSkillStatus = resolveSkillStatus(Character, MainScript)

		return {
			Character = Character,
			MainScript = MainScript,
			Stats = Stats,
			Attributes = Attributes,
			Stamina = getValueChild(Stats, "Stamina"),
			MaxStamina = getValueChild(Stats, "MaxStamina"),
			NoStaminaCost = getValueChild(Stats, "NoStaminaCost"),
			Exhaustion = getValueChild(Stats, "Exhaustion"),
			StaminaInStat = getValueChild(Stats, "StaminaInStat"),
			Exhausted = getValueChild(Attributes, "Exhausted"),
			StaminaRegenPeriod = getValueChild(Attributes, "StaminaRegenPeriod"),
			StaminaRegenPercent = getValueChild(Attributes, "StaminaRegenPercent"),
			ExhaustionDeplete = getValueChild(Attributes, "ExhaustionDeplete"),
			ExhaustionDepletePeriod = getValueChild(Attributes, "ExhaustionDepletePeriod")
		}
	end

	local function refreshHandles()
		StaminaFeature.Handles = resolveHandles()
		return StaminaFeature.Handles
	end

	local function buildStatusLines()
		local Handles = refreshHandles()

		if not Handles then
			return {
				string.format("enabled: %s", StaminaFeature.Enabled and "true" or "false"),
				string.format("state: %s", StaminaFeature.LastReason),
				"mode: monitor only"
			}
		end

		return {
			string.format("enabled: %s", StaminaFeature.Enabled and "true" or "false"),
			"mode: monitor only",
			string.format("state: %s", StaminaFeature.LastReason),
			string.format("stamina: %s / %s", formatValue(getObjectValue(Handles.Stamina)), formatValue(getObjectValue(Handles.MaxStamina))),
			string.format("stamina stat: %s", formatValue(getObjectValue(Handles.StaminaInStat))),
			string.format("exhaustion: %s", formatValue(getObjectValue(Handles.Exhaustion))),
			string.format("no stamina cost: %s", formatValue(getObjectValue(Handles.NoStaminaCost))),
			string.format("exhausted attr: %s", formatValue(getObjectValue(Handles.Exhausted))),
			string.format("skill: %s", StaminaFeature.LastSkillStatus)
		}
	end

	local function buildDebugLines()
		local Handles = refreshHandles()

		return {
			string.format("debug enabled: %s", StaminaFeature.DebugEnabled and "true" or "false"),
			string.format("profile: %s", StaminaFeature.DebugProfile),
			string.format("character: %s", Handles and Handles.Character:GetFullName() or "N/A"),
			string.format("regen period: %s", Handles and formatValue(getObjectValue(Handles.StaminaRegenPeriod)) or "N/A"),
			string.format("regen percent: %s", Handles and formatValue(getObjectValue(Handles.StaminaRegenPercent)) or "N/A"),
			string.format("deplete: %s", Handles and formatValue(getObjectValue(Handles.ExhaustionDeplete)) or "N/A"),
			string.format("deplete period: %s", Handles and formatValue(getObjectValue(Handles.ExhaustionDepletePeriod)) or "N/A"),
			string.format("skill: %s", StaminaFeature.LastSkillStatus)
		}
	end

	function StaminaFeature:SetEnabled(Value)
		self.Enabled = Value == true
		refreshHandles()

		if self.Enabled then
			self.LastReason = self.Handles and "monitoring" or self.LastReason
		elseif self.LastReason == "monitoring" then
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
		if self.CharacterAddedConnection then
			self.CharacterAddedConnection:Disconnect()
			self.CharacterAddedConnection = nil
		end

		self.Enabled = false
		self.DebugEnabled = false
		self.Handles = nil
		self.LastReason = "destroyed"
		self.LastSkillStatus = "not inspected"
	end

	StaminaFeature.CharacterAddedConnection = LocalPlayer.CharacterAdded:Connect(function()
		StaminaFeature.Handles = nil
		StaminaFeature.LastReason = "character changed"
		StaminaFeature.LastSkillStatus = "not inspected"

		task.defer(function()
			refreshHandles()
		end)
	end)

	refreshHandles()

	return StaminaFeature
end
