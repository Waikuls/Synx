return function(Config)
	local Players = game:GetService("Players")
	local RunService = game:GetService("RunService")
	local LocalPlayer = Players.LocalPlayer
	local Notification = Config and Config.Notification

	local WheyAliases = {
		"whey protein",
		"fat burner",
		"muscle burner"
	}

	local WheyFeature = {
		Enabled = false,
		IsConsuming = false,
		LastBuffCheckAt = 0,
		BuffCheckInterval = 2,
		CachedBuffActive = false,
		LastConsumeAt = 0,
		ConsumeCooldown = 20,
	}

	local function findWheyTool()
		local Character = LocalPlayer.Character
		local Backpack = LocalPlayer:FindFirstChildOfClass("Backpack")

		local function check(Container)
			if not Container then return nil end
			for _, Item in ipairs(Container:GetChildren()) do
				if Item:IsA("Tool") then
					local NameLower = string.lower(Item.Name)
					for _, Alias in ipairs(WheyAliases) do
						if string.find(NameLower, Alias, 1, true) then
							return Item
						end
					end
				end
			end
			return nil
		end

		return check(Character) or check(Backpack)
	end

	local function isBuffActive()
		local Now = os.clock()

		if (Now - WheyFeature.LastBuffCheckAt) < WheyFeature.BuffCheckInterval then
			return WheyFeature.CachedBuffActive
		end

		WheyFeature.LastBuffCheckAt = Now

		local PlayerGui = LocalPlayer:FindFirstChild("PlayerGui")
		if not PlayerGui then
			WheyFeature.CachedBuffActive = false
			return false
		end

		for _, Desc in ipairs(PlayerGui:GetDescendants()) do
			if Desc:IsA("TextLabel") or Desc:IsA("TextButton") then
				local Ok, Text = pcall(function() return Desc.Text end)
				if Ok and type(Text) == "string" then
					local Lower = string.lower(Text)
					for _, Alias in ipairs(WheyAliases) do
						if string.find(Lower, Alias, 1, true) and string.find(Text, "%d+:%d%d") then
							WheyFeature.CachedBuffActive = true
							return true
						end
					end
				end
			end
		end

		WheyFeature.CachedBuffActive = false
		return false
	end

	local function getCustomHotbarRemote()
		local Remotes = game:GetService("ReplicatedStorage"):FindFirstChild("Remotes")
		if not Remotes then return nil end
		local Remote = Remotes:FindFirstChild("CustomHotbar")
		if not Remote or not Remote:IsA("RemoteEvent") then return nil end
		return Remote
	end

	local function getInputRemote()
		local Character = LocalPlayer.Character
		if not Character then return nil end
		local MainScript = Character:FindFirstChild("MainScript")
		if not MainScript then return nil end
		local Remote = MainScript:FindFirstChild("Input")
		if not Remote or not Remote:IsA("RemoteEvent") then return nil end
		return Remote
	end

	local function fireInputKey(Name, IsDown)
		local Remote = getInputRemote()
		if not Remote then return end
		pcall(function()
			Remote:FireServer({
				KeyInfo = {Direction = "None", Name = Name, Airborne = false},
				IsDown = IsDown
			})
		end)
	end

	local function consumeWhey(Tool)
		if WheyFeature.IsConsuming then return end

		WheyFeature.IsConsuming = true
		WheyFeature.LastConsumeAt = os.clock()

		task.spawn(function()
			local HotbarRemote = getCustomHotbarRemote()

			if HotbarRemote then
				pcall(function() HotbarRemote:FireServer(Tool.Name) end)

				local Character = LocalPlayer.Character
				if Character then
					local Deadline = os.clock() + 1.5
					repeat task.wait(0.05) until Tool.Parent == Character or os.clock() > Deadline
				end

				task.wait(0.1)
				fireInputKey("LMB", true)
				task.wait(0.1)
				fireInputKey("LMB", false)
			else
				local Character = LocalPlayer.Character
				local Humanoid = Character and Character:FindFirstChildOfClass("Humanoid")
				if Character and Humanoid then
					pcall(function() Humanoid:EquipTool(Tool) end)
					local Deadline = os.clock() + 1.5
					repeat task.wait(0.05) until Tool.Parent == Character or os.clock() > Deadline
					task.wait(0.1)
					pcall(function() Tool:Activate() end)
				end
			end

			task.wait(0.3)

			local Character = LocalPlayer.Character
			local Humanoid = Character and Character:FindFirstChildOfClass("Humanoid")
			if Humanoid then
				pcall(function() Humanoid:UnequipTools() end)
			end

			WheyFeature.IsConsuming = false
		end)
	end

	function WheyFeature:ShouldConsume()
		if (os.clock() - self.LastConsumeAt) < self.ConsumeCooldown then
			return false
		end
		return not isBuffActive()
	end

	function WheyFeature:IsBuffActive()
		return isBuffActive()
	end

	function WheyFeature:TryConsume(FoodBusy)
		if not self.Enabled then return false end
		if self.IsConsuming then return true end
		if FoodBusy then return false end
		if (os.clock() - self.LastConsumeAt) < self.ConsumeCooldown then return true end

		local Tool = findWheyTool()
		if not Tool then return false end

		consumeWhey(Tool)
		return true
	end

	function WheyFeature:SetEnabled(Value)
		self.Enabled = Value and true or false
		self.LastBuffCheckAt = 0
		self.CachedBuffActive = false
	end

	function WheyFeature:Destroy()
		self.Enabled = false
		self.IsConsuming = false
	end

	return WheyFeature
end
