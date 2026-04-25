return function(Config)
	local Players = game:GetService("Players")

	local Visual = Config.Visual
	local Window = Config.Window
	local ESP = Config.ESP
	local FreecamFeature = Config.FreecamFeature
	local SpectatorFeature = Config.SpectatorFeature

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

	Misc:AddToggle({
		Name = "Freecam",
		Callback = function(Value)
			if not FreecamFeature then
				return
			end

			local Enabled = FreecamFeature:SetEnabled(Value)

			if not Enabled and Value then
				task.defer(function()
					local Flag = Window:GetFlags().FreecamToggle

					if Flag then
						Flag:SetValue(false)
					end
				end)
			end
		end,
		Flag = "Freecam"
	})

	Misc:AddToggle({
		Name = "Spectator",
		Callback = function(Value)
			if not SpectatorFeature then
				return
			end

			local Enabled = SpectatorFeature:SetEnabled(Value)

			if not Enabled and Value then
				task.defer(function()
					local Flag = Window:GetFlags().SpectatorToggle

					if Flag then
						Flag:SetValue(false)
					end
				end)
			end
		end,
		Flag = "Spectator"
	})

	local SpectatorTargetDropdown = Misc:AddDropdown({
		Name = "Player",
		Default = SpectatorFeature and SpectatorFeature:GetTargetPlayerName() or "(no players)",
		Values = SpectatorFeature and SpectatorFeature:GetPlayerOptions() or {"(no players)"},
		Callback = function(Value)
			if not SpectatorFeature then
				return
			end

			SpectatorFeature:SetTargetPlayerName(Value)
		end,
		Flag = "SpectatorTarget"
	})

	local function refreshSpectatorDropdown()
		if not SpectatorFeature or not SpectatorTargetDropdown then
			return
		end

		SpectatorTargetDropdown:SetData(SpectatorFeature:GetPlayerOptions())
	end

	Players.PlayerAdded:Connect(function()
		task.defer(refreshSpectatorDropdown)
	end)

	Players.PlayerRemoving:Connect(function()
		task.defer(function()
			refreshSpectatorDropdown()

			if not SpectatorFeature then
				return
			end

			local SpectatorFlag = Window:GetFlags().SpectatorToggle

			if SpectatorFlag and SpectatorFlag:GetValue() and not SpectatorFeature:IsEnabled() then
				SpectatorFlag:SetValue(false)
			end

			if SpectatorTargetDropdown then
				SpectatorTargetDropdown:SetValue(SpectatorFeature:GetTargetPlayerName())
			end
		end)
	end)

	Setting:AddSlider({
		Name = "Distance limit",
		Default = 1500,
		Min = 50,
		Max = 1500,
		Type = " stud",
		Flag = "ESPDistanceLimit",
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

	Setting:AddToggle({
		Name = "PVP Protection",
		Default = false,
		Callback = function(Value)
			ESP:SetShowPvpProtection(Value)
		end
	})

	Setting:AddToggle({
		Name = "Money",
		Default = false,
		Callback = function(Value)
			ESP:SetShowMoney(Value)
		end
	})
end
