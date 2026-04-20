return function(Config)
	local Visual = Config.Visual
	local Window = Config.Window
	local ESP = Config.ESP

	local Misc = Visual:AddSection({
		Name = "MISC",
		Position = 'left'
	})
	
	local Setting = Visual:AddSection({
		Name = "SETTING",
		Position = 'center'
	})
	
	Misc:AddToggle({
		Name = "ESP",
		Callback = function(Value)
			local Enabled = ESP:SetEnabled(Value)

			if not Enabled and Value then
				task.defer(function()
					local Flag = Window:GetFlags().ESPToggle

					if Flag then
						Flag:SetValue(false)
					end
				end)
			end
		end,
		Flag = "ESP"
	})

	Setting:AddSlider({
		Name = "Distance limit",
		Default = 1500,
		Min = 50,
		Max = 1500,
		Type = " stud",
		Callback = function(Value)
			ESP:SetDistanceLimit(Value)
		end
	})

	Setting:AddToggle({
		Name = "Name",
		Default = true,
		Callback = function(Value)
			ESP:SetShowName(Value)
		end
	})

	Setting:AddToggle({
		Name = "Health",
		Default = true,
		Callback = function(Value)
			ESP:SetShowHealth(Value)
		end
	})

	Setting:AddToggle({
		Name = "Distance",
		Default = true,
		Callback = function(Value)
			ESP:SetShowDistance(Value)
		end
	})
end
