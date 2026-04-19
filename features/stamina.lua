return function(Config)
	local Players = game:GetService("Players")
	local RunService = game:GetService("RunService")
	local LocalPlayer = Players.LocalPlayer
	local Notification = Config and Config.Notification

	local StaminaFeature = {
		Enabled = false,
		Connections = {},
		PlayerName = LocalPlayer.Name, -- or "Kiwzex" if fixed
	}

	local function findMainScript()
		local Entities = workspace:FindFirstChild("Entities")
		if not Entities then return nil end
		local Entity = Entities:FindFirstChild(StaminaFeature.PlayerName) or Entities:FindFirstChild("Kiwzex")
		if not Entity then return nil end
		return Entity:FindFirstChild("MainScript")
	end

	local function enforceStamina()
		local MainScript = findMainScript()
		if not MainScript then return end

		local Stats = MainScript:FindFirstChild("Stats")
		if Stats then
			local Stamina = Stats:FindFirstChild("Stamina")
			local MaxStamina = Stats:FindFirstChild("MaxStamina")
			local NoStaminaCost = Stats:FindFirstChild("NoStaminaCost")
			local Exhaustion = Stats:FindFirstChild("Exhaustion")
			local StaminaInStat = Stats:FindFirstChild("StaminaInStat")

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
		end

		local Attributes = MainScript:FindFirstChild("Attributes")
		if Attributes then
			Attributes:SetAttribute("Exhausted", false)
			Attributes:SetAttribute("StaminaRegenPeriod", 0)
			Attributes:SetAttribute("StaminaRegenPercent", 100)
			Attributes:SetAttribute("ExhaustionDeplete", 0)
		end

		local Var001 = MainScript:FindFirstChild("Var001")
		if Var001 then
			local module = require(Var001)
			if module then
				module.M1StaminaCost = 0
				module.M2StaminaCost = 0
				module.currentM1StaminaCost = 0
				module.currentM2StaminaCost = 0
			end
		end
	end

	local function hookRemotes()
		local MainScript = findMainScript()
		if not MainScript then return end

		local ToggleRemote = MainScript:FindFirstChild("Toggle?")
		local DashRemote = MainScript:FindFirstChild("Dash")
		local InputRemote = MainScript:FindFirstChild("Input")

		local mt = getrawmetatable(game)
		local oldNamecall = mt.__namecall
		setreadonly(mt, false)
		mt.__namecall = newcclosure(function(self, ...)
			local method = getnamecallmethod()
			if method == "FireServer" then
				if self == ToggleRemote then
					local args = {...}
					if args[1] and args[1].Action == "Run" then
						args[1].State = false -- Stop run or no cost
					end
					return oldNamecall(self, unpack(args))
				elseif self == DashRemote then
					return -- Block dash
				elseif self == InputRemote then
					local args = {...}
					if args[1] and (args[1].KeyInfo.Name == "LMB" or args[1].KeyInfo.Name == "RMB") then
						return -- Block M1/RMB
					end
				end
			end
			return oldNamecall(self, ...)
		end)
		setreadonly(mt, true)
	end

	function StaminaFeature:SetEnabled(Value)
		self.Enabled = Value
		if Value then
			table.insert(self.Connections, RunService.Heartbeat:Connect(enforceStamina))
			hookRemotes()
			if Notification then
				Notification:Notify({
					Title = "Inf Stamina",
					Content = "เปิดใช้งานแล้ว - Stamina ไม่หมด, No Cost, Block Remotes",
					Icon = "check-circle"
				})
			end
		else
			for _, conn in ipairs(self.Connections) do
				conn:Disconnect()
			end
			self.Connections = {}
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
