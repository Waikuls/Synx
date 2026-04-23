return function(Config)
	local Players = game:GetService("Players")
	local RunService = game:GetService("RunService")
	local LocalPlayer = Players.LocalPlayer
	local Notification = Config and Config.Notification

	warn("[KELV][Whey] module loaded version=v9-coregui-scan-10m-cooldown")

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
		-- Buff lasts ~35+ minutes in game. Cooldown is the safety cap in
		-- case the GUI-based buff detection misses the active buff; better
		-- to wait longer and drink one shake too few than to chain-drink.
		ConsumeCooldown = 600,
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

	local function textHasAlias(Text)
		if type(Text) ~= "string" or Text == "" then return false end
		local Lower = string.lower(Text)
		for _, Alias in ipairs(WheyAliases) do
			if string.find(Lower, Alias, 1, true) then return true end
		end
		return false
	end

	local function textHasTimer(Text)
		return type(Text) == "string" and string.find(Text, "%d+:%d%d") ~= nil
	end

	local function isVisible(Instance)
		local Current = Instance
		while Current and Current ~= game do
			if Current:IsA("GuiObject") then
				local Ok, Visible = pcall(function() return Current.Visible end)
				if Ok and not Visible then return false end
			end
			Current = Current.Parent
		end
		return true
	end

	local function getInstanceText(Instance)
		if not Instance then return nil end
		if Instance:IsA("TextLabel") or Instance:IsA("TextButton") or Instance:IsA("TextBox") then
			local Ok, Text = pcall(function() return Instance.Text end)
			if Ok then return Text end
		end
		return nil
	end

	-- Collect every text-bearing GUI under PlayerGui (and CoreGui as a
	-- fallback for games that surface buff info on the TopBar) so we can
	-- match alias and timer even when they live in separate labels.
	-- Visibility check is deferred to the matching stage — some games
	-- toggle a parent frame's Visible property while still rendering
	-- the label through ScreenGui.Enabled.
	local function collectTextNodes()
		local Roots = {
			LocalPlayer:FindFirstChild("PlayerGui"),
			game:GetService("CoreGui"),
		}

		local Nodes = {}

		for _, Root in ipairs(Roots) do
			if Root then
				local Ok, Descendants = pcall(function() return Root:GetDescendants() end)

				if Ok and Descendants then
					for _, Desc in ipairs(Descendants) do
						if Desc:IsA("TextLabel") or Desc:IsA("TextButton") or Desc:IsA("TextBox") then
							local TextOk, Text = pcall(function() return Desc.Text end)
							if TextOk and type(Text) == "string" and Text ~= "" then
								table.insert(Nodes, {Instance = Desc, Text = trimString(Text) or Text})
							end
						end
					end
				end
			end
		end

		return Nodes
	end

	local function textOfAnyInstance(Instance)
		if not Instance then return nil end
		if Instance:IsA("TextLabel") or Instance:IsA("TextButton") or Instance:IsA("TextBox") then
			local Ok, Text = pcall(function() return Instance.Text end)
			if Ok and type(Text) == "string" then return trimString(Text) or Text end
		end
		return nil
	end

	local function siblingHasTimer(Instance)
		local Parent = Instance and Instance.Parent
		if not Parent then return false end

		for _, Sibling in ipairs(Parent:GetChildren()) do
			if Sibling ~= Instance then
				local Text = textOfAnyInstance(Sibling)
				if Text and textHasTimer(Text) then
					return true
				end

				-- Cousins: check one level inside the sibling. Covers split
				-- buff cards like {TitleFrame > Title, TimerFrame > Timer}.
				for _, Child in ipairs(Sibling:GetChildren()) do
					local CText = textOfAnyInstance(Child)
					if CText and textHasTimer(CText) then
						return true
					end
				end
			end
		end

		return false
	end

	local function isBuffActive()
		local Now = os.clock()

		if (Now - WheyFeature.LastBuffCheckAt) < WheyFeature.BuffCheckInterval then
			return WheyFeature.CachedBuffActive
		end

		WheyFeature.LastBuffCheckAt = Now

		local Nodes = collectTextNodes()

		for _, Node in ipairs(Nodes) do
			if textHasAlias(Node.Text) then
				-- Case 1: alias + timer in same label (classic buff display)
				if textHasTimer(Node.Text) then
					WheyFeature.CachedBuffActive = true
					return true
				end

				-- Case 2: alias label and timer label are direct siblings
				-- (split buff card: title/timer). Anything looser was too
				-- permissive and matched unrelated UI timers.
				if siblingHasTimer(Node.Instance) then
					WheyFeature.CachedBuffActive = true
					return true
				end
			end
		end

		WheyFeature.CachedBuffActive = false
		return false
	end

	local LastBuffDiagnosticAt = 0

	local function dumpBuffDiagnostic()
		local Now = os.clock()
		if (Now - LastBuffDiagnosticAt) < 15 then return end
		LastBuffDiagnosticAt = Now

		local Nodes = collectTextNodes()

		warn(string.format("[KELV][Whey] diagnostic: scanned %d labels in PlayerGui+CoreGui", #Nodes))

		local AliasCount = 0
		local TimerCount = 0

		for _, Node in ipairs(Nodes) do
			local HasAlias = textHasAlias(Node.Text)
			local HasTimer = textHasTimer(Node.Text)

			if HasAlias then
				warn(string.format("  [alias] text=%q path=%s", Node.Text, Node.Instance:GetFullName()))
				AliasCount = AliasCount + 1
			elseif HasTimer and AliasCount < 20 then
				-- Only show timers if alias count is low, so console isn't flooded
				warn(string.format("  [timer] text=%q path=%s", Node.Text, Node.Instance:GetFullName()))
				TimerCount = TimerCount + 1
			end
		end

		warn(string.format("[KELV][Whey] diagnostic done (alias=%d timer=%d)", AliasCount, TimerCount))
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
			local Character = LocalPlayer.Character
			local Humanoid = Character and Character:FindFirstChildOfClass("Humanoid")
			local HotbarRemote = getCustomHotbarRemote()

			-- Equip via CustomHotbar first (client-authoritative path).
			if HotbarRemote then
				warn("[KELV][Whey] equip via CustomHotbar remote")
				pcall(function() HotbarRemote:FireServer(Tool.Name) end)
			end

			-- Fallback: Humanoid:EquipTool directly so something moves if the
			-- hotbar remote didn't land.
			if Character and Humanoid and Tool.Parent ~= Character then
				warn("[KELV][Whey] equip via Humanoid:EquipTool fallback")
				pcall(function() Humanoid:EquipTool(Tool) end)
			end

			-- Wait up to 2s for the tool to actually appear on the character
			-- before trying to activate it.
			local Deadline = os.clock() + 2

			while os.clock() < Deadline do
				if Tool.Parent == Character then break end
				task.wait(0.05)
			end

			if Tool.Parent ~= Character then
				warn("[KELV][Whey] tool never equipped — aborting")
				WheyFeature.IsConsuming = false
				return
			end

			warn("[KELV][Whey] tool equipped, activating")
			task.wait(0.25)

			-- Fire every activation path we have: Tool:Activate is the
			-- canonical Roblox hook, the Input remote matches the game's
			-- own LMB handler, and firing both covers whichever the item
			-- actually listens to.
			pcall(function() Tool:Activate() end)

			fireInputKey("LMB", true)
			task.wait(0.1)
			fireInputKey("LMB", false)

			-- Wait for the drink animation to finish before unequipping.
			-- The game doesn't auto-remove the tool, so we put it away
			-- ourselves — otherwise the character holds it forever and
			-- can't use the machine afterwards.
			task.wait(1.5)

			local Humanoid = Character and Character:FindFirstChildOfClass("Humanoid")
			if Humanoid then
				pcall(function() Humanoid:UnequipTools() end)
			end

			WheyFeature.IsConsuming = false
			warn("[KELV][Whey] consume sequence complete, tool unequipped")
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

		-- One-time GUI dump so the user can tell us why buff detection
		-- missed the active buff (labels may live in split title/timer
		-- nodes or under an unexpected parent).
		dumpBuffDiagnostic()

		warn(string.format("[KELV][Whey] consuming %s", Tool.Name))
		consumeWhey(Tool)
		return true
	end

	function WheyFeature:SetEnabled(Value)
		local State = Value and true or false

		if self.Enabled == State then
			return State
		end

		self.Enabled = State
		self.LastBuffCheckAt = 0
		self.CachedBuffActive = false

		warn("[KELV][Whey] " .. (State and "enabled — consumes only before machine use" or "disabled"))

		return State
	end

	function WheyFeature:Destroy()
		self.Enabled = false
		self.IsConsuming = false
	end

	return WheyFeature
end
