return function(Config)
	local Notification = Config and Config.Notification

	local AutoJobFeature = {
		Enabled = false
	}

	function AutoJobFeature:SetEnabled(Value)
		Value = Value and true or false

		if self.Enabled == Value then
			return Value
		end

		self.Enabled = Value

		if Notification then
			Notification:Notify({
				Title = "Auto Job",
				Content = Value and "Enabled" or "Disabled",
				Icon = Value and "check-circle" or "x-circle"
			})
		end

		return Value
	end

	function AutoJobFeature:Destroy()
		self.Enabled = false
	end

	return AutoJobFeature
end
