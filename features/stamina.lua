return function(Config)
	local Players = game:GetService("Players")
	local RunService = game:GetService("RunService")
	local LocalPlayer = Players.LocalPlayer
	local Notification = Config and Config.Notification

	local StaminaFeature = {
		Enabled = false,
		Connections = {},
		ValueConnections = {},
	}

	local function findMainScript()
		local Entities = workspace:FindFirstChild("Entities")
		if not Entities then return nil end
		local Entity = Entities:FindFirstChild(LocalPlayer.Name) or Entities:FindFirstChild("Kiwzex")
		if not Entity then return nil end
		return Entity:FindFirstChild("MainScript")
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

		if Stamina and Stamina:IsA("NumberValue") and MaxStamina then
			table.insert(StaminaFeature.ValueConnections, Stamina:GetPropertyChangedSignal("Value"):Connect(function()
				if StaminaFeature.Enabled and Stamina.Value < MaxStamina.Value then
					Stamina.Value = MaxStamina.Value
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
				-- NoStaminaCost prevents drain at source
				if NoStaminaCost then
					NoStaminaCost.Value = true
				end
				if Stamina and MaxStamina then
					Stamina.Value = MaxStamina.Value -- Always set for safety
				end
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
			if method ~= "FireServer" or not self:IsA("RemoteEvent") then
				return oldNamecall(self, ...)
			end
			local MainScript = findMainScript()
			if MainScript then
				warn("DEBUG RemoteEvent FireServer:", self.Name) -- TEMP
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
					if self.Name == "Stamina" and value < self.Value then
						return -- Block drain
					elseif self.Name == "NoStaminaCost" then
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
		if Value then
			task.wait(0.1)
			setupValueHooks()
			hookValueNewIndex()
			table.insert(self.Connections, RunService.RenderStepped:Connect(enforceStamina))
			if Notification then
				Notification:Notify({
					Title = "No Drain Stamina",
					Content = "เปิดแล้ว - No Stamina Drain (value hooks + enforce)",
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
					Title = "No Drain Stamina",
					Content = "ปิดแล้ว",
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
