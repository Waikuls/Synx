return function(Config)
	local Main = Config.Main
	local FoodFeature = Config.FoodFeature
	local WheyFeature = Config.WheyFeature
	local AutoTrainFeature = Config.AutoTrainFeature
	local AutoJobFeature = Config.AutoJobFeature

	local Food = Main:AddSection({
		Name = "FOOD",
		Position = "left",
		Height = 10
	})

	Food:AddToggle({
		Name = "Auto eat",
		Callback = function(Value)
			FoodFeature:SetEnabled(Value)
		end,
		Flag = "AutoEat"
	})

	Food:AddToggle({
		Name = "Auto whey",
		Callback = function(Value)
			if WheyFeature then
				WheyFeature:SetEnabled(Value)
			end
		end,
		Flag = "AutoWhey"
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

	Food:AddDropdown({
		Name = "No food",
		Default = FoodFeature:GetNoFoodAction(),
		Values = {"Do nothing", "Kick"},
		Callback = function(Value)
			FoodFeature:SetNoFoodAction(Value)
		end,
		Flag = "AutoEatNoFoodAction"
	})

	local Character = Main:AddSection({
		Name = "CHARACTER",
		Position = "left",
		Height = 115
	})

	local AutoTrain = Main:AddSection({
		Name = "AUTO TRAIN",
		Position = "center",
		Height = 175
	})

	AutoTrain:AddToggle({
		Name = "Enabled",
		Callback = function(Value)
			if AutoTrainFeature then
				AutoTrainFeature:SetEnabled(Value)
			end
		end,
		Flag = "AutoTrain"
	})

	AutoTrain:AddToggle({
		Name = "OP Training",
		Default = AutoTrainFeature and AutoTrainFeature:IsOpTrainingEnabled() or false,
		Callback = function(Value)
			if AutoTrainFeature then
				AutoTrainFeature:SetOpTrainingEnabled(Value)
			end
		end,
		Flag = "AutoTrainOpTraining"
	})

	AutoTrain:AddDropdown({
		Name = "Type",
		Default = AutoTrainFeature and AutoTrainFeature:GetSelectedType() or "Bike",
		Values = AutoTrainFeature and AutoTrainFeature:GetAvailableTypes() or {"Bag", "Bar", "Bench", "Bike", "Squat machine", "Treadmill"},
		Callback = function(Value)
			if AutoTrainFeature then
				AutoTrainFeature:SetSelectedType(Value)
			end
		end,
		Flag = "AutoTrainType"
	})

	AutoTrain:AddDropdown({
		Name = "Continue",
		Default = AutoTrainFeature and AutoTrainFeature:GetContinueLevel() or "mid",
		Values = {"low", "mid", "high"},
		Callback = function(Value)
			if AutoTrainFeature then
				AutoTrainFeature:SetContinueLevel(Value)
			end
		end,
		Flag = "AutoTrainContinue"
	})

	AutoTrain:AddDropdown({
		Name = "Max Fatigue",
		Default = AutoTrainFeature and AutoTrainFeature:GetMaxFatigueAction() or "Do nothing",
		Values = {"Do nothing", "Kick"},
		Callback = function(Value)
			if AutoTrainFeature then
				AutoTrainFeature:SetMaxFatigueAction(Value)
			end
		end,
		Flag = "AutoTrainMaxFatigue"
	})

	local AutoJob = Main:AddSection({
		Name = "AUTO JOB",
		Position = "right",
		Height = 10
	})

	AutoJob:AddToggle({
		Name = "Enabled",
		Callback = function(Value)
			if AutoJobFeature then
				AutoJobFeature:SetEnabled(Value)
			end
		end,
		Flag = "AutoJob"
	})
end
