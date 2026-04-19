print("Stamina module loaded")

return function(Config)
	local Players = game:GetService("Players")
	local RunService = game:GetService("RunService")
	local LocalPlayer = Players.LocalPlayer
	local Notification = Config and Config.Notification
	local StaminaFeature = {
		Enabled = false,
		DebugEnabled = false,
		CurrentProfile = "Run",
		CapturedLines = {},
		Connections = {},
		ValueConnections = {},
		HookStatus = "Disabled for stability",
	}

	local function setHookStatus(Message)
		StaminaFeature.HookStatus = Message
	end

	local function findMainScript()
		local Entities = workspace:FindFirstChild("Entities")
		if not Entities then
			return nil
		end

		local Entity = Entities:FindFirstChild(LocalPlayer.Name) or Entities:FindFirstChild("Kiwzex")
		if not Entity then
			return nil
		end

		return Entity:FindFirstChild("MainScript")
	end

	local function setupValueHooks()
		StaminaFeature.ValueConnections = {}

		local MainScript = findMainScript()
		if not MainScript then
			return
		end

		local Stats = MainScript:FindFirstChild("Stats")
		if not Stats then
			return
		end

		local Stamina = Stats:FindFirstChild("Stamina")
		local MaxStamina = Stats:FindFirstChild("MaxStamina")
		local NoStaminaCost = Stats:FindFirstChild("NoStaminaCost")
		local NoCooldown = Stats:FindFirstChild("NoCooldown")
		local BodyFatigue = Stats:FindFirstChild("BodyFatigue") or Stats:FindFirstChild("BodyFatique")
		local Exhaustion = Stats:FindFirstChild("Exhaustion")

		if NoStaminaCost and NoStaminaCost:IsA("BoolValue") then
			NoStaminaCost.Value = true
			table.insert(StaminaFeature.ValueConnections, NoStaminaCost:GetPropertyChangedSignal("Value"):Connect(function()
				if StaminaFeature.Enabled then
					NoStaminaCost.Value = true
				end
			end))
		end

		if NoCooldown and NoCooldown:IsA("BoolValue") then
			NoCooldown.Value = true
		end

		if BodyFatigue and BodyFatigue:IsA("NumberValue") then
			BodyFatigue.Value = 0
		end

		if Exhaustion and Exhaustion:IsA("NumberValue") then
			Exhaustion.Value = 0
		end

		if Stamina and Stamina:IsA("NumberValue") and MaxStamina then
			table.insert(StaminaFeature.ValueConnections, Stamina:GetPropertyChangedSignal("Value"):Connect(function()
				if StaminaFeature.Enabled and Stamina.Value < MaxStamina.Value * 0.95 then
					Stamina.Value = MaxStamina.Value
				end
			end))
		end
	end

	local function enforceStamina()
		if not StaminaFeature.Enabled then
			return
		end

		local MainScript = findMainScript()
		if not MainScript then
			return
		end

		pcall(function()
			local Stats = MainScript:FindFirstChild("Stats")
			if not Stats then
				return
			end

			local NoStaminaCost = Stats:FindFirstChild("NoStaminaCost")
			local NoCooldown = Stats:FindFirstChild("NoCooldown")
			local BodyFatigue = Stats:FindFirstChild("BodyFatigue") or Stats:FindFirstChild("BodyFatique")
			local Exhaustion = Stats:FindFirstChild("Exhaustion")
			local StaminaInStat = Stats:FindFirstChild("StaminaInStat")
			local MaxStamina = Stats:FindFirstChild("MaxStamina")

			if NoStaminaCost and not NoStaminaCost.Value then
				NoStaminaCost.Value = true
			end

			if NoCooldown and not NoCooldown.Value then
				NoCooldown.Value = true
			end

			if BodyFatigue and BodyFatigue.Value ~= 0 then
				BodyFatigue.Value = 0
			end

			if Exhaustion and Exhaustion.Value ~= 0 then
				Exhaustion.Value = 0
			end

			if StaminaInStat and MaxStamina and StaminaInStat.Value ~= MaxStamina.Value then
				StaminaInStat.Value = MaxStamina.Value
			end
		end)
	end

	local function hookRemotes()
		setHookStatus("Disabled for stability")
		return false
	end

	local function hookValueNewIndex()
		setHookStatus("Disabled for stability")
		return false
	end

	function StaminaFeature:SetEnabled(Value)
		self.Enabled = Value

		if Value then
			task.wait(0.5)
			setupValueHooks()

			hookRemotes()
			hookValueNewIndex()

			table.insert(self.Connections, RunService.RenderStepped:Connect(enforceStamina))
			table.insert(self.Connections, workspace.ChildAdded:Connect(function(child)
				if child.Name == "Entities" then
					task.delay(1, setupValueHooks)
				end
			end))

			if Notification then
				Notification:Notify({
					Title = "Inf Stamina",
					Content = "Enabled - safe mode active. Rejoin once if old hook spam is still active.",
					Icon = "check-circle"
				})
			end
		else
			for _, Connection in ipairs(self.Connections) do
				Connection:Disconnect()
			end

			for _, Connection in ipairs(self.ValueConnections) do
				Connection:Disconnect()
			end

			self.Connections = {}
			self.ValueConnections = {}

			if Notification then
				Notification:Notify({
					Title = "Inf Stamina",
					Content = "Disabled",
					Icon = "x-circle"
				})
			end
		end
	end

	function StaminaFeature:Destroy()
		self:SetEnabled(false)
	end

	function StaminaFeature:IsDebugEnabled()
		return self.DebugEnabled
	end

	function StaminaFeature:SetDebugEnabled(Value)
		self.DebugEnabled = Value

		if Value then
			self.CapturedLines = {}
		end
	end

	function StaminaFeature:GetDebugProfile()
		return self.CurrentProfile
	end

	function StaminaFeature:SetDebugProfile(Profile)
		if table.find({"Free", "Run", "Dash", "Attack"}, Profile) then
			self.CurrentProfile = Profile
			self.CapturedLines = {}
			return true
		end

		return false
	end

	function StaminaFeature:StartDebugCapture(Profile)
		if Profile then
			self:SetDebugProfile(Profile)
		end

		self.DebugEnabled = true
		self.CapturedLines = {"Capture started for profile: " .. self.CurrentProfile}
		return true
	end

	function StaminaFeature:ClearDebugCapture()
		self.CapturedLines = {}
		self.DebugEnabled = false
		return true
	end

	function StaminaFeature:GetDebugLines()
		if not self.DebugEnabled then
			return {}
		end

		local Lines = table.clone(self.CapturedLines)
		table.insert(Lines, "Profile: " .. self.CurrentProfile)
		table.insert(Lines, "Enabled: " .. tostring(self.Enabled))
		return Lines
	end

	function StaminaFeature:GetStatusLines()
		return {
			"InfStamina: " .. (self.Enabled and "ACTIVE" or "OFF"),
			"Prevention: Flags + Hooks + Block",
			"Profile: " .. self.CurrentProfile,
			"Hooks: " .. self.HookStatus,
			"Note: Actions should not drain stamina"
		}
	end

	return StaminaFeature
end
