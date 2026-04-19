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

		if Stamina and Stamina:IsA("NumberValue") and MaxStamina then
			table.insert(StaminaFeature.ValueConnections, Stamina:GetPropertyChangedSignal("Value"):Connect(function()
				if StaminaFeature.Enabled and Stamina.Value < MaxStamina.Value then
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
				local Stamina = Stats:FindFirstChild("Stamina")
				local MaxStamina = Stats:FindFirstChild("MaxStamina")
				if Stamina and MaxStamina and Stamina.Value < MaxStamina.Value then
					Stamina.Value = MaxStamina.Value
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
					if self.Name == "Stamina" and value < self.Value then
						return -- Block drain
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
