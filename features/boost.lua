return function(Config)
	local CoreGui = game:GetService("CoreGui")
	local Players = game:GetService("Players")
	local RunService = game:GetService("RunService")

	local LocalPlayer = Players.LocalPlayer

	local Notification = Config and Config.Notification
	local Window = Config and Config.Window

	local BoostFeature = {
		Enabled = false,
		Overlay = nil,
		YenLabel = nil,
		YenConn = nil,
		-- Flags allowed to stay on while boost runs.
		--   AutoJob:      we leave it alone — user controls it
		--   AntiAfk:      stops the game kicking us while AFK farming
		--   BoostAutoJob: the toggle that owns this feature
		-- Note: Fatality stores flags with a type suffix
		-- (Toggle/Slider/Dropdown/...), so the keys here are the actual
		-- WindowFlags keys, not the user-facing Flag names.
		ExemptFlags = {
			BoostAutoJobToggle = true,
			AutoJobToggle = true,
			AntiAfkToggle = true,
		},
		-- FPS to restore on disable. Most executors treat very high values
		-- as effectively uncapped.
		RestoreFps = 240,
		-- FPS while boost is active. 15 keeps Heartbeat / RenderStepped
		-- handlers firing rarely while still leaving AutoJob's task.wait
		-- timing untouched (wall-clock based).
		BoostFps = 15,
	}

	local function formatMoney(Amount)
		local Number = tonumber(Amount) or 0
		local Whole = tostring(math.floor(Number))
		local Sign = ""

		if string.sub(Whole, 1, 1) == "-" then
			Sign = "-"
			Whole = string.sub(Whole, 2)
		end

		while true do
			local Replaced, Count = string.gsub(Whole, "^(%d+)(%d%d%d)", "%1,%2")
			Whole = Replaced

			if Count == 0 then
				break
			end
		end

		return Sign .. Whole
	end

	local function tryDisableFlag(FlagObj)
		if not FlagObj or type(FlagObj.SetValue) ~= "function" or type(FlagObj.GetValue) ~= "function" then
			return
		end

		-- Only touch boolean toggles. Sliders / dropdowns / color pickers
		-- return non-boolean values from GetValue and must be left alone.
		local Ok, Current = pcall(function() return FlagObj:GetValue() end)

		if not Ok or type(Current) ~= "boolean" then
			return
		end

		if Current == true then
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

	local function syncBoostToggle(Value)
		if not Window or type(Window.GetFlags) ~= "function" then
			return false
		end

		local Flag = Window:GetFlags().BoostAutoJobToggle

		if Flag and type(Flag.SetValue) == "function" then
			pcall(function() Flag:SetValue(Value and true or false) end)
			return true
		end

		return false
	end

	local function disconnectYen()
		if BoostFeature.YenConn then
			pcall(function() BoostFeature.YenConn:Disconnect() end)
			BoostFeature.YenConn = nil
		end
	end

	local function bindYen(Label)
		disconnectYen()

		local function attach(YenValue)
			if not BoostFeature.Enabled or not BoostFeature.YenLabel then
				return
			end

			local Ok, Current = pcall(function() return YenValue.Value end)
			Label.Text = formatMoney(Ok and Current or 0)

			BoostFeature.YenConn = YenValue:GetPropertyChangedSignal("Value"):Connect(function()
				if not BoostFeature.YenLabel then return end
				local OkInner, Latest = pcall(function() return YenValue.Value end)
				BoostFeature.YenLabel.Text = formatMoney(OkInner and Latest or 0)
			end)
		end

		-- Currencies / Yen may not exist immediately after spawn. Wait for
		-- them in a background thread so the overlay opens instantly with
		-- "0" and updates as soon as the values are available.
		task.spawn(function()
			local Currencies = LocalPlayer:FindFirstChild("Currencies") or LocalPlayer:WaitForChild("Currencies", 15)

			if not Currencies or not BoostFeature.Enabled then
				return
			end

			local Yen = Currencies:FindFirstChild("Yen") or Currencies:WaitForChild("Yen", 15)

			if Yen and BoostFeature.Enabled and BoostFeature.YenLabel == Label then
				attach(Yen)
			end
		end)
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

		local Stack = Instance.new("Frame")
		Stack.AnchorPoint = Vector2.new(0.5, 0.5)
		Stack.Position = UDim2.new(0.5, 0, 0.5, 0)
		Stack.Size = UDim2.new(0, 900, 0, 260)
		Stack.BackgroundTransparency = 1
		Stack.Parent = Frame

		local Subtitle = Instance.new("TextLabel")
		Subtitle.Size = UDim2.new(1, 0, 0, 16)
		Subtitle.Position = UDim2.new(0, 0, 0, 0)
		Subtitle.BackgroundTransparency = 1
		Subtitle.Text = "BOOST ACTIVE"
		Subtitle.TextColor3 = Color3.fromRGB(160, 160, 160)
		Subtitle.TextSize = 12
		Subtitle.Font = Enum.Font.GothamBold
		Subtitle.Parent = Stack

		local CurrencyTag = Instance.new("TextLabel")
		CurrencyTag.Size = UDim2.new(1, 0, 0, 18)
		CurrencyTag.Position = UDim2.new(0, 0, 0, 24)
		CurrencyTag.BackgroundTransparency = 1
		CurrencyTag.Text = "YEN"
		CurrencyTag.TextColor3 = Color3.fromRGB(255, 106, 133)
		CurrencyTag.TextSize = 14
		CurrencyTag.Font = Enum.Font.GothamBold
		CurrencyTag.Parent = Stack

		local YenLabel = Instance.new("TextLabel")
		YenLabel.Size = UDim2.new(1, 0, 0, 130)
		YenLabel.Position = UDim2.new(0, 0, 0, 50)
		YenLabel.BackgroundTransparency = 1
		YenLabel.Text = "0"
		YenLabel.TextColor3 = Color3.fromRGB(25, 25, 25)
		YenLabel.TextSize = 110
		YenLabel.Font = Enum.Font.GothamBold
		YenLabel.TextXAlignment = Enum.TextXAlignment.Center
		YenLabel.TextYAlignment = Enum.TextYAlignment.Center
		YenLabel.Parent = Stack

		local Btn = Instance.new("TextButton")
		Btn.AnchorPoint = Vector2.new(0.5, 0)
		Btn.Size = UDim2.new(0, 220, 0, 40)
		Btn.Position = UDim2.new(0.5, 0, 0, 200)
		Btn.BackgroundColor3 = Color3.fromRGB(255, 106, 133)
		Btn.BorderSizePixel = 0
		Btn.Text = "DISABLE BOOST"
		Btn.TextColor3 = Color3.fromRGB(255, 255, 255)
		Btn.TextSize = 14
		Btn.Font = Enum.Font.GothamBold
		Btn.AutoButtonColor = true
		Btn.Parent = Stack

		local Corner = Instance.new("UICorner")
		Corner.CornerRadius = UDim.new(0, 6)
		Corner.Parent = Btn

		Btn.MouseButton1Click:Connect(function()
			-- Flip the flag first so the MISC toggle UI clears its check.
			-- That fires the toggle's Callback which re-enters SetEnabled
			-- — guarded by the Enabled-state early-return below.
			if not syncBoostToggle(false) then
				BoostFeature:SetEnabled(false)
			end
		end)

		Gui.Parent = CoreGui

		BoostFeature.YenLabel = YenLabel
		bindYen(YenLabel)

		return Gui
	end

	function BoostFeature:SetEnabled(Value)
		local State = Value and true or false

		if self.Enabled == State then
			return State
		end

		self.Enabled = State

		if State then
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
					Content = "Other features locked off.",
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

			disconnectYen()
			self.YenLabel = nil

			if self.Overlay then
				pcall(function() self.Overlay:Destroy() end)
				self.Overlay = nil
			end

			-- Sync the MISC toggle off in case SetEnabled was called from
			-- somewhere other than the toggle (Quit cleanup, programmatic
			-- disable). syncBoostToggle is a no-op if value matches.
			syncBoostToggle(false)

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
