-- Main entry script for using the Fatality UI library.
-- Core library code lives in src/source.luau.
local LoaderVersion = "20260420-loader-12"
local RemoteRef = "edb9b16"

local function getScriptCompiler()
	if type(loadstring) == "function" then
		return loadstring
	end

	if type(load) == "function" then
		return load
	end

	return nil
end

local function executeSource(SourceCode, SourceLabel)
	local Compiler = getScriptCompiler()

	if type(Compiler) ~= "function" then
		error(string.format("No script compiler available for %s", SourceLabel), 0)
	end

	local Chunk, CompileError = Compiler(SourceCode)

	if type(Chunk) ~= "function" then
		error(string.format("Failed to compile %s: %s", SourceLabel, tostring(CompileError)), 0)
	end

	local Success, Result = pcall(Chunk)

	if not Success then
		error(string.format("Failed to run %s: %s", SourceLabel, tostring(Result)), 0)
	end

	return Result
end

local function canReadLocalFile(LocalPath)
	if type(readfile) ~= "function" then
		return false
	end

	local Success, Result = pcall(readfile, LocalPath)

	return Success and type(Result) == "string" and Result ~= ""
end

local function hasCompleteLocalProject()
	local RequiredLocalFiles = {
		"src/source.luau",
		"Fatality/main.lua",
		"ui/main.lua",
		"ui/visual.lua",
		"ui/stats.lua",
		"features/esp.lua",
		"features/food.lua",
		"features/stamina.lua",
		"features/stats.lua"
	}

	for _, LocalPath in ipairs(RequiredLocalFiles) do
		if not canReadLocalFile(LocalPath) then
			return false
		end
	end

	return true
end

local function getSourceMode()
	local Environment = type(getgenv) == "function" and getgenv() or nil
	local ForcedMode = Environment and Environment.__FatalitySourceMode

	if ForcedMode == "local" or ForcedMode == "remote" then
		return ForcedMode
	end

	if Environment then
		Environment.__FatalityLoaderVersion = LoaderVersion
	end

	if hasCompleteLocalProject() then
		return "local"
	end

	return "remote"
end

local SourceMode = getSourceMode()

local function getRemoteSeed()
	local Timestamp = "0"
	local SuccessDateTime, DateTimeValue = pcall(function()
		return DateTime.now().UnixTimestampMillis
	end)

	if SuccessDateTime and DateTimeValue then
		Timestamp = tostring(DateTimeValue)
	elseif type(os.time) == "function" then
		local SuccessOsTime, OsTimeValue = pcall(os.time)

		if SuccessOsTime and OsTimeValue then
			Timestamp = tostring(OsTimeValue)
		end
	end

	local JobId = tostring(game.JobId or "")

	if JobId == "" then
		JobId = tostring(math.floor(os.clock() * 1000000))
	end

	local Entropy = tostring(math.floor(os.clock() * 1000000))
	local SuccessGuid, GuidValue = pcall(function()
		return game:GetService("HttpService"):GenerateGUID(false)
	end)

	if SuccessGuid and type(GuidValue) == "string" and GuidValue ~= "" then
		Entropy = GuidValue
	end

	local Seed = string.format("%s-%s-%s", Timestamp, JobId, Entropy)

	return Seed
end

local RemoteSeed = getRemoteSeed()

local function buildRemoteUrls(Path)
	local EncodedPath = string.gsub(Path, "\\", "/")

	return {
		string.format("https://raw.githubusercontent.com/Waikuls/Synx/%s/%s?v=%s", RemoteRef, EncodedPath, RemoteSeed),
		string.format("https://cdn.jsdelivr.net/gh/Waikuls/Synx@%s/%s?v=%s", RemoteRef, EncodedPath, RemoteSeed)
	}
end

local function tryLoadLocal(LocalPath)
	if not canReadLocalFile(LocalPath) then
		return false, string.format("Local %s unavailable", LocalPath)
	end

	local Success, Result = pcall(readfile, LocalPath)

	if not Success or type(Result) ~= "string" or Result == "" then
		return false, string.format("Local %s unreadable", LocalPath)
	end

	local ExecuteSuccess, ExecuteResult = pcall(executeSource, Result, LocalPath)

	if ExecuteSuccess then
		return true, ExecuteResult
	end

	return false, string.format("Local %s failed: %s", LocalPath, tostring(ExecuteResult))
end

local function tryLoadRemote(LocalPath, RemoteUrls)
	local Errors = {}

	if type(RemoteUrls) ~= "table" or #RemoteUrls == 0 then
		return false, string.format("No remote urls available for %s", LocalPath)
	end

	for AttemptIndex = 1, 2 do
		for _, RemoteUrl in ipairs(RemoteUrls) do
			local Success, Result = pcall(function()
				return game:HttpGet(RemoteUrl)
			end)

			if Success and type(Result) == "string" and Result ~= "" then
				local ExecuteSuccess, ExecuteResult = pcall(executeSource, Result, RemoteUrl)

				if ExecuteSuccess then
					return true, ExecuteResult
				end

				table.insert(Errors, string.format("Remote %s failed: %s", LocalPath, tostring(ExecuteResult)))
			else
				table.insert(Errors, string.format("Remote %s request failed on attempt %d", LocalPath, AttemptIndex))
			end
		end

		if AttemptIndex == 1 then
			task.wait(0.2)
		end
	end

	return false, table.concat(Errors, " | ")
end

local function loadScript(LocalPath, RemoteUrls)
	local Attempts = (SourceMode == "local" and {"local", "remote"}) or {"remote", "local"}
	local Errors = {}

	for _, Attempt in ipairs(Attempts) do
		if Attempt == "local" then
			local Success, Result = tryLoadLocal(LocalPath)

			if Success then
				return Result
			end

			table.insert(Errors, Result)
		elseif Attempt == "remote" then
			local Success, Result = tryLoadRemote(LocalPath, RemoteUrls)

			if Success then
				return Result
			end

			table.insert(Errors, Result)
		end
	end

	if #Errors > 0 then
		error(table.concat(Errors, " | "), 0)
	end

	error(string.format("No source available for %s", LocalPath), 0)
end

local Fatality = loadScript("src/source.luau", buildRemoteUrls("src/source.luau"))
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
	Name = "KELV",
	Duration = 4
});

Notification:Notify({
	Title = "KELV",
	Content = "Hello, "..game.Players.LocalPlayer.DisplayName..' Welcome back!',
	Icon = "clipboard"
})

local function notifyModuleFailure(ModulePath, ErrorMessage)
	warn(string.format("[KELV] Failed to load %s: %s", ModulePath, tostring(ErrorMessage)))

	task.defer(function()
		Notification:Notify({
			Title = "KELV",
			Content = string.format("%s failed to load. Other menus will stay available.", ModulePath),
			Icon = "alert-circle"
		})
	end)
end

local function createFallbackStaminaFeature(ErrorMessage)
	notifyModuleFailure("features/stamina.lua", ErrorMessage)

	return {
		SetEnabled = function()
			return false
		end,
		Destroy = function()
		end
	}
end

local function createFallbackESP(ErrorMessage)
	notifyModuleFailure("features/esp.lua", ErrorMessage)

	return {
		SetEnabled = function()
			return false
		end,
		SetDistanceLimit = function()
		end,
		SetShowName = function()
		end,
		SetShowHealth = function()
		end,
		Destroy = function()
		end
	}
end

local function createFallbackFoodFeature(ErrorMessage)
	notifyModuleFailure("features/food.lua", ErrorMessage)

	return {
		SetEnabled = function()
			return false
		end,
		GetEatThreshold = function()
			return 15
		end,
		SetEatThreshold = function()
		end,
		GetNoFoodAction = function()
			return "Do nothing"
		end,
		SetNoFoodAction = function()
		end,
		Destroy = function()
		end
	}
end

local function createFallbackStatsFeature(ErrorMessage)
	notifyModuleFailure("features/stats.lua", ErrorMessage)

	return {
		GetPanels = function()
			return {"Stats unavailable."}, {"Check loader output."}
		end,
		GetPlayerOptions = function()
			return {game.Players.LocalPlayer.Name}
		end,
		GetTargetPlayerName = function()
			return game.Players.LocalPlayer.Name
		end,
		SetTargetPlayer = function()
			return game.Players.LocalPlayer
		end,
		IsStaminaDebugAvailable = function()
			return false
		end,
		IsStaminaDebugEnabled = function()
			return false
		end,
		SetStaminaDebugEnabled = function()
		end,
		GetStaminaDebugProfile = function()
			return "Run"
		end,
		GetStaminaCaptureProfiles = function()
			return {"Free", "Run", "Dash", "Attack"}
		end,
		SetStaminaDebugProfile = function()
		end,
		StartStaminaDebugCapture = function()
			return false
		end,
		ClearStaminaDebugCapture = function()
		end
	}
end

local function createFallbackUI(ModulePath, ErrorMessage)
	notifyModuleFailure(ModulePath, ErrorMessage)

	return function()
	end
end

local function createFallbackStatsUI(ErrorMessage)
	notifyModuleFailure("ui/stats.lua", ErrorMessage)

	return {
		Destroy = function()
		end
	}
end

local function safeLoadModule(ModulePath, FallbackFactory)
	local Success, Result = pcall(loadScript, ModulePath, buildRemoteUrls(ModulePath))

	if Success then
		return Result
	end

	if type(FallbackFactory) == "function" then
		return FallbackFactory(Result)
	end

	error(tostring(Result), 0)
end

local function safeCreateModule(ModulePath, Factory, Arguments, FallbackFactory)
	if type(Factory) == "table" then
		return Factory
	end

	if type(Factory) ~= "function" then
		if type(FallbackFactory) == "function" then
			return FallbackFactory(string.format("%s did not return a function", ModulePath))
		end

		error(string.format("%s did not return a function", ModulePath), 0)
	end

	local Success, Result = pcall(Factory, Arguments)

	if Success then
		return Result
	end

	if type(FallbackFactory) == "function" then
		return FallbackFactory(Result)
	end

	error(tostring(Result), 0)
end

local function safeRunModule(ModulePath, Factory, Arguments)
	if type(Factory) ~= "function" then
		notifyModuleFailure(ModulePath, string.format("%s did not return a function", ModulePath))
		return false
	end

	local Success, Result = pcall(Factory, Arguments)

	if not Success then
		notifyModuleFailure(ModulePath, Result)
		return false
	end

	return Result
end

local function safeBuildBlock(BlockLabel, Builder)
	if type(Builder) ~= "function" then
		return false
	end

	local Success, Result = pcall(Builder)

	if not Success then
		notifyModuleFailure(BlockLabel, Result)
		return false
	end

	return Result
end

local Window = Fatality.new({
	Name = "KELV",
	Expire = "never",
});
local MainWindowGui = Fatality.Windows[#Fatality.Windows]

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

local CreateESP = safeLoadModule("features/esp.lua", createFallbackESP)
local CreateFoodFeature = safeLoadModule("features/food.lua", createFallbackFoodFeature)
local CreateStaminaFeature = safeLoadModule("features/stamina.lua", createFallbackStaminaFeature)
local CreateStatsFeature = safeLoadModule("features/stats.lua", createFallbackStatsFeature)
local CreateMainUI = safeLoadModule("ui/main.lua", function(ErrorMessage)
	return createFallbackUI("ui/main.lua", ErrorMessage)
end)
local CreateVisualUI = safeLoadModule("ui/visual.lua", function(ErrorMessage)
	return createFallbackUI("ui/visual.lua", ErrorMessage)
end)
local CreateStatsUI = safeLoadModule("ui/stats.lua", function(ErrorMessage)
	return function()
		return createFallbackStatsUI(ErrorMessage)
	end
end)

local ESP = safeCreateModule("features/esp.lua", CreateESP, {
	Notification = Notification
}, createFallbackESP)
local FoodFeature = safeCreateModule("features/food.lua", CreateFoodFeature, {
	Notification = Notification
}, createFallbackFoodFeature)
local StaminaFeature = safeCreateModule("features/stamina.lua", CreateStaminaFeature, {
	Notification = Notification
}, createFallbackStaminaFeature)
local StatsFeature = safeCreateModule("features/stats.lua", CreateStatsFeature, {
	StaminaFeature = StaminaFeature
}, createFallbackStatsFeature)
local StatsUI = safeCreateModule("ui/stats.lua", CreateStatsUI, {
	Window = Window,
	Fatality = Fatality,
	StatsFeature = StatsFeature
}, createFallbackStatsUI)

safeRunModule("ui/main.lua", CreateMainUI, {
	Main = Main,
	FoodFeature = FoodFeature,
	StaminaFeature = StaminaFeature
})

safeRunModule("ui/visual.lua", CreateVisualUI, {
	Visual = Visual,
	Window = Window,
	ESP = ESP
})

safeBuildBlock("Fatality/main.lua:LEGIT_STATIC", function()
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
end)

safeBuildBlock("Fatality/main.lua:MISC_STATIC", function()
	local General = Misc:AddSection({
		Name = "GENERAL",
		Position = 'left'
	})

	General:AddButton({
		Name = "Quit",
		Callback = function()
			ESP:Destroy()
			FoodFeature:Destroy()
			StaminaFeature:Destroy()
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
end)
