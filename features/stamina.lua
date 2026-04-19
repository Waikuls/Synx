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
	}

	local function findMainScript()
		local Entities = workspace:FindFirstChild("Entities")
		if not Entities then return nil end
		local Entity = Entities:FindFirstChild(LocalPlayer.Name) or Entities:FindFirstChild("Kiwzex")
		if not Entity then return nil end
		local MainScript = Entity:FindFirstChild("MainScript")
		return MainScript
	end


	local function setupValueHooks()
		StaminaFeature.ValueConnections = {}
		local MainScript = findMainScript()
		if not MainScript then return end
		local Stats = MainScript:FindFirstChild("Stats")
		if not Stats then return end

		local Stamina = Stats:FindFirstChild("Stamina")
		local MaxStamina = Stats:FindFirstChild("MaxStamina")
		local NoStaminaCost = Stats:FindFirstChild("NoStaminaCost")
		local NoCooldown = Stats:FindFirstChild("NoCooldown")
		local BodyFatigue = Stats:FindFirstChild("BodyFatigue") or Stats:FindFirstChild("BodyFatique")
		local Exhaustion = Stats:FindFirstChild("Exhaustion")

		-- Set flags at source to prevent cost
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
					-- Only restore if significant drain (avoid loop)
					Stamina.Value = MaxStamina.Value
				end
			end))
		end
	end

	local function enforceStamina()
		if not StaminaFeature.Enabled then return end
		local MainScript = findMainScript()
		if not MainScript then return end

		pcall(function()
			local Stats = MainScript:FindFirstChild("Stats")
			if Stats then
				local NoStaminaCost = Stats:FindFirstChild("NoStaminaCost")
				local NoCooldown = Stats:FindFirstChild("NoCooldown")
				local BodyFatigue = Stats:FindFirstChild("BodyFatigue") or Stats:FindFirstChild("BodyFatique")
				local Exhaustion = Stats:FindFirstChild("Exhaustion")
				local StaminaInStat = Stats:FindFirstChild("StaminaInStat")
				local MaxStamina = Stats:FindFirstChild("MaxStamina")

				-- Only set if not already correct to reduce spam
				if NoStaminaCost and not NoStaminaCost.Value then NoStaminaCost.Value = true end
				if NoCooldown and not NoCooldown.Value then NoCooldown.Value = true end
				if BodyFatigue and BodyFatigue.Value ~= 0 then BodyFatigue.Value = 0 end
				if Exhaustion and Exhaustion.Value ~= 0 then Exhaustion.Value = 0 end
				if StaminaInStat and MaxStamina and StaminaInStat.Value ~= MaxStamina.Value then
					StaminaInStat.Value = MaxStamina.Value
				end
			end
		end)
	end

	local function hookRemotes()
		if getgenv().FatalityStaminaHookInstalled then return end
		getgenv().FatalityStaminaBlock = true
		getgenv().FatalityStaminaHookInstalled = true

		local mt = getrawmetatable(game)
		local oldNamecall = mt.__namecall
		setreadonly(mt, false)
		mt.__namecall = newcclosure(function(self, ...)
			local method = getnamecallmethod()
			if method == "FireServer" and self:IsA("RemoteEvent") and StaminaFeature.Enabled then
				local args = {...}
				local remoteName = self.Name
				local MainScript = findMainScript()
				if MainScript and #args > 0 then
					-- Whitelist common inventory/pickup/equip remotes (add more from your logs if needed)
					local inventoryRemotes = {"Equip", "Pickup", "Bag", "Inventory", "Hold", "UseItem", "Take"}
					if table.find(inventoryRemotes, remoteName) then
						warn("[STAMINA DEBUG] namecall ALLOWED inventory remote:", remoteName)
						return oldNamecall(self, ...)
					end
					-- Only zero stamina cost for action remotes (sprint/attack)
					if typeof(args[1]) == "number" and args[1] > 0 and not table.find(inventoryRemotes, remoteName) then
						warn("[STAMINA DEBUG] namecall ZEROED stamina cost on remote:", remoteName, "arg:", args[1])
						args[1] = 0
					end
				end
				return oldNamecall(self, unpack(args))
			end
			return oldNamecall(self, ...)
		end)
		setreadonly(mt, true)
	end

	local function hookValueNewIndex()
		local mt = getrawmetatable(game)
		local oldNewIndex = mt.__newindex
		setreadonly(mt, false)
		mt.__newindex = newcclosure(function(self, key, value)
			if not StaminaFeature.Enabled then
				return oldNewIndex(self, key, value)
			end
			if self:IsA("ValueBase") and self.Parent and self.Parent.Name == "Stats" then
				local MainScript = findMainScript()
				if MainScript and self:IsDescendantOf(MainScript) then
					local name = self.Name
					local isNumber = typeof(value) == "number"
					if name == "Stamina" and isNumber and value < (self.Value or 100) then
						-- Critical block for stamina (no spam)
						return
					elseif name == "NoStaminaCost" or name == "NoCooldown" then
						value = true
					elseif (name == "BodyFatigue" or name == "BodyFatique" or name == "Exhaustion") and isNumber and value > 0 then
						value = 0
					end
					-- No debug logs in production (spam fixed via conditional enforce)
				end
			end
			return oldNewIndex(self, key, value)
		end)
		setreadonly(mt, true)
	end

	function StaminaFeature:SetEnabled(Value)
		self.Enabled = Value
		if Value then
			local MainScript = findMainScript()
			task.wait(0.5) -- Give time for entity to load
			setupValueHooks()
			hookRemotes()
			hookValueNewIndex()
			table.insert(self.Connections, RunService.RenderStepped:Connect(enforceStamina))

			-- Add entity change listener for respawn
			table.insert(self.Connections, workspace.ChildAdded:Connect(function(child)
				if child.Name == "Entities" then
					task.delay(1, setupValueHooks)
				end
			end))

			if Notification then
				Notification:Notify({
					Title = "Inf Stamina",
					Content = "เปิดแล้ว - Source prevention (flags + hooks + no drain)",
					Icon = "check-circle"
				})
			end
		else
			for _, conn in ipairs(self.Connections) do
				conn:Disconnect()
			end
			for _, conn in ipairs(self.ValueConnections) do
				conn:Disconnect()
			end
			self.Connections = {}
			self.ValueConnections = {}
			if Notification then
				Notification:Notify({
					Title = "Inf Stamina",
					Content = "ปิดแล้ว",
					Icon = "x-circle"
				})
			end
		end
	end

	function StaminaFeature:Destroy()
		self:SetEnabled(false)
	end

	-- Extended API for stats.lua integration and debug
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
		if not self.DebugEnabled then return {} end
		local lines = table.clone(self.CapturedLines)
		table.insert(lines, "Profile: " .. self.CurrentProfile)
		table.insert(lines, "Enabled: " .. tostring(self.Enabled))
		return lines
	end

	function StaminaFeature:GetStatusLines()
		return {
			"InfStamina: " .. (self.Enabled and "ACTIVE" or "OFF"),
			"Prevention: Flags + Hooks + Block",
			"Profile: " .. self.CurrentProfile,
			"Note: Actions should not drain stamina"
		}
	end

	return StaminaFeature
end
