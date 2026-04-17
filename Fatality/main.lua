-- Main entry script for using the Fatality UI library.
-- Core library code lives in src/source.luau.
local function loadScript(LocalPath, RemoteUrl)
	local SourceCode

	if type(readfile) == "function" then
		local Success, Result = pcall(readfile, LocalPath)

		if Success and type(Result) == "string" and Result ~= "" then
			SourceCode = Result
		end
	end

	if not SourceCode then
		SourceCode = game:HttpGet(RemoteUrl)
	end

	return loadstring(SourceCode)()
end

local Fatality = loadScript("src/source.luau", "https://raw.githubusercontent.com/Waikuls/Synx/main/src/source.luau")
local CoreGui = game:GetService("CoreGui")
local ExistingCoreGuis = {}

for _, Gui in ipairs(CoreGui:GetChildren()) do
	ExistingCoreGuis[Gui] = true
end

local Notification = Fatality:CreateNotifier();
local NotifierGui

for _, Gui in ipairs(CoreGui:GetChildren()) do
	if Gui:IsA("ScreenGui") and not ExistingCoreGuis[Gui] then
		NotifierGui = Gui
		break
	end
end

Fatality:Loader({
	Name = "FATALITY",
	Duration = 4
});

Notification:Notify({
	Title = "FATALITY",
	Content = "Hello, "..game.Players.LocalPlayer.DisplayName..' Welcome back!',
	Icon = "clipboard"
})

local Window = Fatality.new({
	Name = "FATALITY",
	Expire = "never",
});
local MainWindowGui = Fatality.Windows[#Fatality.Windows]
local CreateESP = loadScript("features/esp.lua", "https://raw.githubusercontent.com/Waikuls/Synx/main/features/esp.lua")
local CreateFoodFeature = loadScript("features/food.lua", "https://raw.githubusercontent.com/Waikuls/Synx/main/features/food.lua")
local CreateStatsFeature = loadScript("features/stats.lua", "https://raw.githubusercontent.com/Waikuls/Synx/main/features/stats.lua")
local CreateMainUI = loadScript("ui/main.lua", "https://raw.githubusercontent.com/Waikuls/Synx/main/ui/main.lua")
local CreateVisualUI = loadScript("ui/visual.lua", "https://raw.githubusercontent.com/Waikuls/Synx/main/ui/visual.lua")
local CreateStatsUI = loadScript("ui/stats.lua", "https://raw.githubusercontent.com/Waikuls/Synx/main/ui/stats.lua")
local ESP = CreateESP({
	Notification = Notification
})
local FoodFeature = CreateFoodFeature({
	Notification = Notification
})
local StatsFeature = CreateStatsFeature()

local Main = Window:AddMenu({
	Name = "MAIN",
	Icon = "skull"
})

local Legit = Window:AddMenu({
	Name = "LEGIT",
	Icon = "target"
})

local Visual = Window:AddMenu({
	Name = "VISUAL",
	Icon = "eye"
})

local Misc = Window:AddMenu({
	Name = "MISC",
	Icon = "settings"
})

local Skins = Window:AddMenu({
	Name = "SKINS",
	Icon = "palette"
})
local StatsUI = CreateStatsUI({
	Window = Window,
	Fatality = Fatality,
	StatsFeature = StatsFeature
})

do
	local Aim = Legit:AddSection({
		Position = 'left',
		Name = "AIM"
	});
	
	local Rcs = Legit:AddSection({
		Position = 'left',
		Name = "RCS"
	});

	local Trigger = Legit:AddSection({
		Position = 'center',
		Name = "TRIGGER"
	});
	
	local Backtrack = Legit:AddSection({
		Position = 'center',
		Name = "BACKTRACK"
	});

	local General = Legit:AddSection({
		Position = 'right',
		Name = "GENERAL"
	});
	
	Aim:AddToggle({
		Name = "Aim assist"
	})
	
	Aim:AddDropdown({
		Name = "Mode",
		Default = "Adaptive",
		Values = {"Adaptive","value 1",'Value 2'}
	})
	
	Aim:AddDropdown({
		Name = "Hitboxes",
		Multi = true,
		Default = {
			["Head"] = true
		},
		Values = {
			"Head",
			'Neck',
			'Arms',
			'Legs'
		}
	})
	
	Aim:AddSlider({
		Name = "Multipoint"
	})
	
	Aim:AddSlider({
		Name = "Aim fov",
		Round = 1,
		Default = 0.1,
		Type = " deg"
	})
	
	Aim:AddSlider({
		Name = "Aim speed",
		Default = 1,
		Type = "%"
	})
	
	Aim:AddSlider({
		Name = "Min-damage",
		Default = 61,
	})
	

	Aim:AddToggle({
		Name = "Only in scpoe"
	})
	

	Aim:AddToggle({
		Name = "Autostop"
	})
	
	Rcs:AddToggle({
		Name = "Recoil control"
	})
	
	Rcs:AddSlider({
		Name = "Speed",
		Default = 1,
		Type = "%"
	})
	

	Rcs:AddToggle({
		Name = "Re-center"
	})
	

	Rcs:AddSlider({
		Name = "Start bullet",
		Default = 1,
	})
	
	Trigger:AddToggle({
		Name = "Triggerbot"
	})
	
	Trigger:AddSlider({
		Name = "Hit-chance",
		Default = 100,
		Type = "%"
	})
	
	Trigger:AddToggle({
		Name = "Use seed when available"
	})
	
	Trigger:AddSlider({
		Name = "Min-damage",
		Default = 0,
		Type = "%"
	})
	
	Trigger:AddSlider({
		Name = "Reaction time",
		Default = 0,
		Type = "ms"
	})
	
	Trigger:AddToggle({
		Name = "Wait for aim assist hitgroup"
	})
	
	Trigger:AddToggle({
		Name = "Only in Scope"
	})
	
	Backtrack:AddSlider({
		Name = "Backtrack",
		Default = 0,
		Type = "%"
	})
	
	General:AddToggle({
		Name = "Enabled"
	})
	
	General:AddDropdown({
		Name = "Disablers",
		Values = {"d1",'d2'}
	})
	
	General:AddToggle({
		Name = "Visualize fov",
		Option = true
	}).Option:AddColorPicker({
		Name = "Color",
		Default = Color3.fromRGB(255, 34, 75)
	})
	
	General:AddToggle({
		Name = "Autorevolver"
	})
end

do
	local General = Misc:AddSection({
		Name = "GENERAL",
		Position = 'left'
	})

	General:AddButton({
		Name = "Quit",
		Callback = function()
			ESP:Destroy()
			FoodFeature:Destroy()
			StatsUI:Destroy()
			table.clear(Fatality.DragBlacklist)

			if MainWindowGui then
				Fatality.WindowFlags[MainWindowGui] = nil
			end

			if NotifierGui and NotifierGui.Parent then
				NotifierGui:Destroy()
				NotifierGui = nil
			end

			if MainWindowGui and MainWindowGui.Parent then
				MainWindowGui:Destroy()
				MainWindowGui = nil
			end

			table.clear(Fatality.Windows)
		end,
	})
end

CreateMainUI({
	Main = Main,
	FoodFeature = FoodFeature
})

CreateVisualUI({
	Visual = Visual,
	Window = Window,
	ESP = ESP
})
