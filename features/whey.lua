return function(Config)
	local Players = game:GetService("Players")
	local RunService = game:GetService("RunService")
	local LocalPlayer = Players.LocalPlayer
	local Notification = Config and Config.Notification

	warn("[KELV][Whey] module loaded version=v2-standalone-loop")

	-- Each entry is a substring pattern matched against the lowercased,
	-- punctuation-stripped tool name. "whey" alone is intentional so
	-- CamelCase names like "WheyProtein" still match.
	local WheyAliases = {
		"whey",
		"fat burner",
		"fatburner",
		"muscle burner",
		"muscleburner",
	}

	local WheyFeature = {
		Enabled = false,
		IsConsuming = false,
		LastBuffCheckAt = 0,
		BuffCheckInterval = 2,
		CachedBuffActive = false,
		LastConsumeAt = 0,
		ConsumeCooldown = 20,
		Connection = nil,
		LoopInterval = 3,
		LoopElapsed = 0,
		LastDebugAt = 0,
		DebugInterval = 10,
	}

	local function squashToolName(Name)
		if type(Name) ~= "string" then return "" end
		local Lower = string.lower(Name)
		return (string.gsub(Lower, "[^%w]", ""))
	end

	local function findWheyTool()
		local Character = LocalPlayer.Character
		local Backpack = LocalPlayer:FindFirstChildOfClass("Backpack")

		local function check(Container)
			if not Container then return nil end
			for _, Item in ipairs(Container:GetChildren()) do
				if Item:IsA("Tool") then
					local NameLower = string.lower(Item.Name)
					local Squashed = squashToolName(Item.Name)

					for _, Alias in ipairs(WheyAliases) do
						if string.find(NameLower, Alias, 1, true) then
							return Item
						end

						local AliasSquashed = squashToolName(Alias)

						if AliasSquashed ~= "" and string.find(Squashed, AliasSquashed, 1, true) then
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

		if not Tool then
			local Now = os.clock()

			if (Now - self.LastDebugAt) >= self.DebugInterval then
				self.LastDebugAt = Now
				warn("[KELV][Whey] no whey/burner tool found in Character or Backpack")
			end

			return false
		end

		warn(string.format("[KELV][Whey] consuming %s", Tool.Name))
		consumeWhey(Tool)
		return true
	end

	local function standaloneTick(self)
		if not self.Enabled then return end
		if self.IsConsuming then return end

		if (os.clock() - self.LastConsumeAt) < self.ConsumeCooldown then
			return
		end

		if isBuffActive() then
			return
		end

		self:TryConsume(false)
	end

	function WheyFeature:SetEnabled(Value)
		local State = Value and true or false

		if self.Enabled == State then
			return State
		end

		self.Enabled = State
		self.LastBuffCheckAt = 0
		self.CachedBuffActive = false

		if self.Connection then
			self.Connection:Disconnect()
			self.Connection = nil
		end

		if State then
			self.LoopElapsed = 0
			self.Connection = RunService.Heartbeat:Connect(function(DeltaTime)
				self.LoopElapsed = self.LoopElapsed + DeltaTime

				if self.LoopElapsed < self.LoopInterval then
					return
				end

				self.LoopElapsed = 0
				standaloneTick(self)
			end)

			warn("[KELV][Whey] enabled — standalone loop every " .. tostring(self.LoopInterval) .. "s")
		else
			warn("[KELV][Whey] disabled")
		end

		return State
	end

	function WheyFeature:Destroy()
		self.Enabled = false
		self.IsConsuming = false

		if self.Connection then
			self.Connection:Disconnect()
			self.Connection = nil
		end
	end

	return WheyFeature
end
