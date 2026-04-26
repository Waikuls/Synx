return function(Config)
	local CoreGui = game:GetService("CoreGui")
	local RunService = game:GetService("RunService")

	local Notification = Config and Config.Notification
	local Window = Config and Config.Window

	local BoostFeature = {
		Enabled = false,
		Overlay = nil,
		-- Flags allowed to stay on while boost runs.
		--   AutoJob:      the whole point of "For Auto Job"
		--   AntiAfk:      stops the game kicking us while AFK farming
		--   BoostAutoJob: the toggle that owns this feature
		ExemptFlags = {
			BoostAutoJob = true,
			AutoJob = true,
			AntiAfk = true,
		},
		-- FPS to restore on disable. Most executors treat very high values
		-- as effectively uncapped.
		RestoreFps = 240,
		-- FPS while boost is active. 15 keeps Heartbeat / RenderStepped
		-- handlers firing rarely while still leaving AutoJob's task.wait
		-- timing untouched (wall-clock based).
		BoostFps = 15,
	}

	local function tryDisableFlag(FlagObj)
		if not FlagObj or type(FlagObj.SetValue) ~= "function" then
			return
		end

		-- Only touch boolean toggles. Dropdowns / sliders / color pickers
		-- carry non-boolean Value fields and must be left alone.
		if type(FlagObj.Value) ~= "boolean" then
			return
		end

		if FlagObj.Value == true then
			pcall(function() FlagObj:SetValue(false) end)
		end
	end

	local function forceDisableOthers()
		if not Window or type(Window.GetFlags) ~= "function" then
			return
		end

		local Flags = Window:GetFlags()

		if type(Flags) ~= "table" then
			return
		end

		for FlagName, FlagObj in pairs(Flags) do
			if not BoostFeature.ExemptFlags[FlagName] then
				tryDisableFlag(FlagObj)
			end
		end
	end

	local function ensureAutoJobOn()
		if not Window or type(Window.GetFlags) ~= "function" then
			return
		end

		local AutoJobFlag = Window:GetFlags().AutoJob

		if AutoJobFlag and type(AutoJobFlag.SetValue) == "function" and AutoJobFlag.Value ~= true then
			pcall(function() AutoJobFlag:SetValue(true) end)
		end
	end

	local function buildOverlay()
		local Gui = Instance.new("ScreenGui")
		Gui.Name = "KELVBoostOverlay"
		Gui.IgnoreGuiInset = true
		-- High enough to cover the 3D scene + most game UI. The DISABLE
		-- BOOST button is the intended way out.
		Gui.DisplayOrder = 999
		Gui.ResetOnSpawn = false

		local Frame = Instance.new("Frame")
		Frame.Size = UDim2.new(1, 0, 1, 0)
		Frame.BackgroundColor3 = Color3.new(1, 1, 1)
		Frame.BorderSizePixel = 0
		Frame.Parent = Gui

		local Label = Instance.new("TextLabel")
		Label.AnchorPoint = Vector2.new(0.5, 0.5)
		Label.Size = UDim2.new(0, 400, 0, 28)
		Label.Position = UDim2.new(0.5, 0, 0.5, -30)
		Label.BackgroundTransparency = 1
		Label.Text = "BOOST ACTIVE - AUTO JOB ONLY"
		Label.TextColor3 = Color3.fromRGB(40, 40, 40)
		Label.TextSize = 18
		Label.Font = Enum.Font.GothamBold
		Label.Parent = Frame

		local Btn = Instance.new("TextButton")
		Btn.AnchorPoint = Vector2.new(0.5, 0.5)
		Btn.Size = UDim2.new(0, 200, 0, 36)
		Btn.Position = UDim2.new(0.5, 0, 0.5, 20)
		Btn.BackgroundColor3 = Color3.fromRGB(255, 106, 133)
		Btn.BorderSizePixel = 0
		Btn.Text = "DISABLE BOOST"
		Btn.TextColor3 = Color3.fromRGB(255, 255, 255)
		Btn.TextSize = 14
		Btn.Font = Enum.Font.GothamBold
		Btn.Parent = Frame

		local Corner = Instance.new("UICorner")
		Corner.CornerRadius = UDim.new(0, 4)
		Corner.Parent = Btn

		Btn.MouseButton1Click:Connect(function()
			-- Prefer flipping the flag so the toggle UI in MISC stays in
			-- sync. Falls back to direct disable if the flag is gone.
			local Flag = Window and Window:GetFlags() and Window:GetFlags().BoostAutoJob

			if Flag and type(Flag.SetValue) == "function" then
				pcall(function() Flag:SetValue(false) end)
			else
				BoostFeature:SetEnabled(false)
			end
		end)

		Gui.Parent = CoreGui
		return Gui
	end

	function BoostFeature:SetEnabled(Value)
		local State = Value and true or false

		if self.Enabled == State then
			return State
		end

		self.Enabled = State

		if State then
			ensureAutoJobOn()
			forceDisableOthers()

			if type(setfpscap) == "function" then
				pcall(setfpscap, self.BoostFps)
			end

			pcall(function()
				RunService:Set3dRenderingEnabled(false)
			end)

			self.Overlay = buildOverlay()

			-- Slow re-enforce loop. 1 s is plenty: it just snaps any
			-- toggle the user flips while boost is on back off.
			task.spawn(function()
				while self.Enabled do
					forceDisableOthers()
					task.wait(1)
				end
			end)

			if Notification then
				Notification:Notify({
					Title = "Boost",
					Content = "Auto Job only. Other features locked off.",
					Icon = "check-circle"
				})
			end
		else
			if type(setfpscap) == "function" then
				pcall(setfpscap, self.RestoreFps)
			end

			pcall(function()
				RunService:Set3dRenderingEnabled(true)
			end)

			if self.Overlay then
				pcall(function() self.Overlay:Destroy() end)
				self.Overlay = nil
			end

			if Notification then
				Notification:Notify({
					Title = "Boost",
					Content = "Disabled",
					Icon = "x-circle"
				})
			end
		end

		warn("[KELV][Boost] " .. (State and "enabled" or "disabled"))

		return State
	end

	function BoostFeature:IsEnabled()
		return self.Enabled
	end

	function BoostFeature:Destroy()
		self:SetEnabled(false)
	end

	return BoostFeature
end
