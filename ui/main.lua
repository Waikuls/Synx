return function(Config)
	local Main = Config.Main
	local FoodFeature = Config.FoodFeature

	local Food = Main:AddSection({
		Name = "FOOD",
		Position = "left"
	})

	Food:AddToggle({
		Name = "Auto eat",
		Callback = function(Value)
			FoodFeature:SetEnabled(Value)
		end,
		Flag = "AutoEat"
	})

	Food:AddSlider({
		Name = "Eat at",
		Default = FoodFeature:GetEatThreshold(),
		Min = 0,
		Max = 80,
		Callback = function(Value)
			FoodFeature:SetEatThreshold(Value)
		end,
		Flag = "AutoEatThreshold"
	})
end
