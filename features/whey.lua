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

	local function consumeWhey(Tool)
		if WheyFeature.IsConsuming then return end

		WheyFeature.IsConsuming = true
		WheyFeature.LastConsumeAt = os.clock()

		task.spawn(function()
			local Character = LocalPlayer.Character
			local Humanoid = Character and Character:FindFirstChildOfClass("Humanoid")

			if not Character or not Humanoid then
				WheyFeature.IsConsuming = false
				return
			end

			pcall(function() Humanoid:EquipTool(Tool) end)

			local Equipped = false
			local Deadline = os.clock() + 0.5
			repeat
				task.wait(0.05)
				Equipped = Tool.Parent == Character
			until Equipped or os.clock() > Deadline

			if Equipped then
				task.wait(0.1)
				pcall(function() Tool:Activate() end)
				if type(firesignal) == "function" then
					pcall(function() firesignal(Tool.Activated) end)
				end
				local Ok, Vim = pcall(game.GetService, game, "VirtualInputManager")
				if Ok and Vim then
					local Camera = workspace.CurrentCamera
					local Vp = Camera and Camera.ViewportSize or Vector2.new(1280, 720)
					local Cx, Cy = math.floor(Vp.X * 0.5), math.floor(Vp.Y * 0.5)
					pcall(function()
						Vim:SendMouseButtonEvent(Cx, Cy, 0, true, game, 0)
						task.wait(0.05)
						Vim:SendMouseButtonEvent(Cx, Cy, 0, false, game, 0)
					end)
				end
			end

			task.wait(0.3)
			pcall(function() Humanoid:UnequipTools() end)

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
