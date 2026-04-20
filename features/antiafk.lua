return function(Config)
	local Players = game:GetService("Players")
	local VirtualUser = game:GetService("VirtualUser")
	local LocalPlayer = Players.LocalPlayer
	local Notification = Config and Config.Notification

	local AntiAfkFeature = {
		Enabled = false,
		Connection = nil
	}

	local function disconnect()
		if AntiAfkFeature.Connection then
			AntiAfkFeature.Connection:Disconnect()
			AntiAfkFeature.Connection = nil
		end
	end

	local function spoofActivity()
		local Camera = workspace.CurrentCamera

		pcall(function()
			VirtualUser:CaptureController()
		end)

		local Success = pcall(function()
			if Camera then
				VirtualUser:Button2Down(Vector2.new(0, 0), Camera.CFrame)
				task.wait(0.1)
				VirtualUser:Button2Up(Vector2.new(0, 0), Camera.CFrame)
				return
			end

			VirtualUser:ClickButton2(Vector2.new(0, 0))
		end)

		if Success then
			return
		end

		pcall(function()
			VirtualUser:ClickButton2(Vector2.new(0, 0))
		end)
	end

	function AntiAfkFeature:SetEnabled(Value)
		Value = Value and true or false

		if self.Enabled == Value then
			return Value
		end

		disconnect()
		self.Enabled = Value

		if Value then
			if not LocalPlayer then
				self.Enabled = false
				return false
			end

			local Success, Connection = pcall(function()
				return LocalPlayer.Idled:Connect(function()
					spoofActivity()
				end)
			end)

			if not Success or not Connection then
				self.Enabled = false
				return false
			end

			self.Connection = Connection

			if Notification then
				Notification:Notify({
					Title = "Anti Afk",
					Content = "Enabled",
					Icon = "check-circle"
				})
			end

			return true
		end

		if Notification then
			Notification:Notify({
				Title = "Anti Afk",
				Content = "Disabled",
				Icon = "x-circle"
			})
		end

		return false
	end

	function AntiAfkFeature:Destroy()
		self.Enabled = false
		disconnect()
	end

	return AntiAfkFeature
end
