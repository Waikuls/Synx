return function(Config)
	local Players = game:GetService("Players")
	local RunService = game:GetService("RunService")
	local LocalPlayer = Players.LocalPlayer
	local Notification = Config and Config.Notification

	local StaminaFeature = {
		Enabled = false,
		Connections = {},
		ValueConnections = {},
		Var001Module = nil,
	}

	local function findMainScript()
		local Entities = workspace:FindFirstChild("Entities")
		if not Entities then return nil end
		local Entity = Entities:FindFirstChild(LocalPlayer.Name) or Entities:FindFirstChild("Kiwzex")
		if not Entity then return nil end
		return Entity:FindFirstChild("MainScript")
	end

	local function cacheVar001()
		local MainScript = findMainScript()
		if MainScript and MainScript:FindFirstChild("Var001") and not StaminaFeature.Var001Module then
			local success, module = pcall(require, MainScript.Var001)
			if success then
				StaminaFeature.Var001Module = module
			end
		end
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
		local Exhaustion = Stats:FindFirstChild("Exhaustion")
		local StaminaInStat = Stats:FindFirstChild("StaminaInStat")
		local BodyFatique = Stats:FindFirstChild("BodyFatique") or Stats:FindFirstChild("BodyFatigue")
		local NoCooldown = Stats:FindFirstChild("NoCooldown")

		if Stamina and Stamina:IsA("NumberValue") and MaxStamina then
			table.insert(StaminaFeature.ValueConnections, Stamina:GetPropertyChangedSignal("Value"):Connect(function()
				if StaminaFeature.Enabled then
					Stamina.Value = MaxStamina.Value
				end
			end))
		end
		if Exhaustion and Exhaustion:IsA("NumberValue") then
			table.insert(StaminaFeature.ValueConnections, Exhaustion:GetPropertyChangedSignal("Value"):Connect(function()
				if StaminaFeature.Enabled then
					Exhaustion.Value = 0
				end
			end))
		end
		if NoStaminaCost and NoStaminaCost:IsA("BoolValue") then
			table.insert(StaminaFeature.ValueConnections, NoStaminaCost:GetPropertyChangedSignal("Value"):Connect(function()
				if StaminaFeature.Enabled then
					NoStaminaCost.Value = true
				end
			end))
		end
		if StaminaInStat and StaminaInStat:IsA("NumberValue") then
			table.insert(StaminaFeature.ValueConnections, StaminaInStat:GetPropertyChangedSignal("Value"):Connect(function()
				if StaminaFeature.Enabled then
					StaminaInStat.Value = 100
				end
			end))
		end
		if BodyFatique and BodyFatique:IsA("NumberValue") then
			table.insert(StaminaFeature.ValueConnections, BodyFatique:GetPropertyChangedSignal("Value"):Connect(function()
				if StaminaFeature.Enabled then
					BodyFatique.Value = 0
				end
			end))
		end
		if NoCooldown and NoCooldown:IsA("BoolValue") then
			table.insert(StaminaFeature.ValueConnections, NoCooldown:GetPropertyChangedSignal("Value"):Connect(function()
				if StaminaFeature.Enabled then
					NoCooldown.Value = true
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
				local Stamina = Stats:FindFirstChild("Stamina")
				local MaxStamina = Stats:FindFirstChild("MaxStamina")
				local NoStaminaCost = Stats:FindFirstChild("NoStaminaCost")
				local Exhaustion = Stats:FindFirstChild("Exhaustion")
				local StaminaInStat = Stats:FindFirstChild("StaminaInStat")
				local BodyFatique = Stats:FindFirstChild("BodyFatique") or Stats:FindFirstChild("BodyFatigue")
				local NoCooldown = Stats:FindFirstChild("NoCooldown")

				if Stamina and MaxStamina then
					Stamina.Value = MaxStamina.Value
				end
				if NoStaminaCost then
					NoStaminaCost.Value = true
				end
				if Exhaustion then
					Exhaustion.Value = 0
				end
				if StaminaInStat then
					StaminaInStat.Value = MaxStamina and MaxStamina.Value or 100
				end
				if BodyFatique then
					BodyFatique.Value = 0
				end
				if NoCooldown then
					NoCooldown.Value = true
				end
			end
		end)

		pcall(function()
			local Attributes = MainScript:FindFirstChild("Attributes")
			if Attributes then
				Attributes:SetAttribute("Exhausted", false)
				Attributes:SetAttribute("StaminaRegenPeriod", 0)
				Attributes:SetAttribute("StaminaRegenPercent", 100)
				Attributes:SetAttribute("ExhaustionDeplete", 0)
				Attributes:SetAttribute("ExhaustionDepletePeriod", 0)
				Attributes:SetAttribute("StaminaInStat StatBoost", 0)
				Attributes:SetAttribute("Melee Strength", 1)
				Attributes:SetAttribute("Melee Defense", 1)
				Attributes:SetAttribute("melee AnimationSpeed", 1)
				Attributes:SetAttribute("meleelight AnimationSpeed", 1)
				Attributes:SetAttribute("meleeheavy AnimationSpeed", 1)
				Attributes:SetAttribute("NoCooldown", true)
			end
		end)

		pcall(function()
			local UCooldown = MainScript:FindFirstChild("UCooldown")
			if UCooldown and UCooldown:IsA("NumberValue") then
				UCooldown.Value = 0
			end
		end)

		pcall(function()
			if StaminaFeature.Var001Module then
				StaminaFeature.Var001Module.M1StaminaCost = 0
				StaminaFeature.Var001Module.M2StaminaCost = 0
				StaminaFeature.Var001Module.currentM1StaminaCost = 0
				StaminaFeature.Var001Module.currentM2StaminaCost = 0
			end
		end)
	end

	local function hookRemotes()
		if getgenv().FatalityStaminaHookInstalled then return end
		getgenv().FatalityStaminaBlock = false
		getgenv().FatalityStaminaHookInstalled = true

		local mt = getrawmetatable(game)
		local oldNamecall = mt.__namecall
		setreadonly(mt, false)
		mt.__namecall = newcclosure(function(self, ...)
			if not getgenv().FatalityStaminaBlock then
				return oldNamecall(self, ...)
			end
			local method = getnamecallmethod()
			if method == "FireServer" then
				local MainScript = findMainScript()
				if MainScript then
					local ToggleRemote = MainScript:FindFirstChild("Toggle?")
					local DashRemote = MainScript:FindFirstChild("Dash")
					local InputRemote = MainScript:FindFirstChild("Input")
					if self == ToggleRemote then
						local args = {...}
						if args[1] and args[1].Action == "Run" then
							args[1].State = false
						end
						return oldNamecall(self, unpack(args))
					elseif self == DashRemote then
						return
					elseif self == InputRemote then
						local args = {...}
						if args[1] and args[1].KeyInfo and args[1].KeyInfo.Name == "Q" and not args[1].KeyInfo.Airborne then
							return -- Block skill Q
						end
					end
				end
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
			if StaminaFeature.Enabled and self:IsA("ValueBase") and self.Parent and self.Parent.Name == "Stats" then
				local MainScript = findMainScript()
				if MainScript and self:IsDescendantOf(MainScript) then
					if self.Name == "Stamina" then
						local MaxStamina = self.Parent:FindFirstChild("MaxStamina")
						if MaxStamina then
							value = MaxStamina.Value
						end
					elseif self.Name == "NoStaminaCost" then
						value = true
					elseif self.Name == "Exhaustion" then
						value = 0
					elseif self.Name == "BodyFatique" or self.Name == "BodyFatigue" then
						value = 0
					elseif self.Name == "NoCooldown" then
						value = true
					end
				end
			end
			return oldNewIndex(self, key, value)
		end)
		setreadonly(mt, true)
	end

	function StaminaFeature:SetEnabled(Value)
		self.Enabled = Value
		getgenv().FatalityStaminaBlock = Value
		if Value then
			task.wait(0.1)
			cacheVar001()
			setupValueHooks()
			hookValueNewIndex()
			table.insert(self.Connections, RunService.RenderStepped:Connect(enforceStamina))
			hookRemotes()
			if Notification then
				Notification:Notify({
					Title = "Inf Stamina",
					Content = "เปิดใช้งานแล้ว - Combat unlock + No drop M1/skill Q (__newindex + hooks)",
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
			self.Var001Module = nil
			getgenv().FatalityStaminaBlock = false
			if Notification then
				Notification:Notify({
					Title = "Inf Stamina",
					Content = "ปิดใช้งานแล้ว",
					Icon = "x-circle"
				})
			end
		end
	end

	function StaminaFeature:Destroy()
		self:SetEnabled(false)
	end

	return StaminaFeature
end
