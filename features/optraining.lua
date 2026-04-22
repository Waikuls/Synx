return function(Config)
	local Players = game:GetService("Players")
	local RunService = game:GetService("RunService")
	local LocalPlayer = Players.LocalPlayer
	local Notification = Config and Config.Notification

	local OpTrainingFeature = {}
	OpTrainingFeature.Enabled = false
	OpTrainingFeature.Connection = nil
	OpTrainingFeature.LoopInterval = 0.5
	OpTrainingFeature.Elapsed = 0

	-- Behavior knobs
	OpTrainingFeature.BedOffsetY = -21
	OpTrainingFeature.FatigueTriggerPercent = 100
	OpTrainingFeature.FatigueExitPercent = 0
	OpTrainingFeature.MountWaitSeconds = 3
	OpTrainingFeature.SleepTimeoutSeconds = 180
	OpTrainingFeature.RetryCooldownSeconds = 5

	-- Runtime state
	OpTrainingFeature.State = "idle"
	OpTrainingFeature.BedOriginalCFrame = nil
	OpTrainingFeature.PlayerReturnCFrame = nil
	OpTrainingFeature.LastAttemptAt = 0

	local function getCharacter()
		return LocalPlayer.Character
	end

	local function getHumanoid()
		local Character = getCharacter()

		if not Character then
			return nil
		end

		return Character:FindFirstChildOfClass("Humanoid")
	end

	local function getRootPart()
		local Character = getCharacter()

		if not Character then
			return nil
		end

		local Root = Character:FindFirstChild("HumanoidRootPart")

		if Root then
			return Root
		end

		Root = Character:FindFirstChild("UpperTorso")

		if Root then
			return Root
		end

		return Character:FindFirstChild("Torso")
	end

	local function findStatsContainer()
		local Character = getCharacter()
		local MainScript = nil

		if Character then
			MainScript = Character:FindFirstChild("MainScript")
		end

		if not MainScript then
			local Entities = workspace:FindFirstChild("Entities")

			if Entities then
				local Entity = Entities:FindFirstChild(LocalPlayer.Name)

				if Entity then
					MainScript = Entity:FindFirstChild("MainScript")

					if not MainScript then
						MainScript = Entity:FindFirstChild("MainScript", true)
					end
				end
			end
		end

		if not MainScript then
			return nil
		end

		local Stats = MainScript:FindFirstChild("Stats")

		if Stats then
			return Stats
		end

		return MainScript:FindFirstChild("Stats", true)
	end

	local function readStat(Name)
		local Stats = findStatsContainer()

		if not Stats then
			return nil
		end

		local Child = Stats:FindFirstChild(Name)

		if Child and Child:IsA("ValueBase") then
			return Child.Value
		end

		local Attribute = Stats:GetAttribute(Name)

		if Attribute ~= nil then
			return Attribute
		end

		local Descendant = Stats:FindFirstChild(Name, true)

		if Descendant and Descendant:IsA("ValueBase") then
			return Descendant.Value
		end

		return nil
	end

	local function getBodyFatigue()
		local Value = readStat("BodyFatigue")

		if type(Value) ~= "number" then
			Value = readStat("BodyFatique")
		end

		if type(Value) == "number" then
			return Value
		end

		return 0
	end

	local function findBed()
		local RootPart = getRootPart()
		local BestBed = nil
		local BestDist = math.huge

		for _, Descendant in ipairs(workspace:GetDescendants()) do
			if Descendant:IsA("Model") and Descendant.Name == "Bed" then
				local Dist = 999999

				if RootPart then
					local Ok, Pivot = pcall(function()
						return Descendant:GetPivot()
					end)

					if Ok and Pivot then
						Dist = (RootPart.Position - Pivot.Position).Magnitude
					end
				end

				if Dist < BestDist then
					BestDist = Dist
					BestBed = Descendant
				end
			end
		end

		return BestBed
	end

	local function findBedPrompt(Bed)
		if not Bed then
			return nil
		end

		for _, Descendant in ipairs(Bed:GetDescendants()) do
			if Descendant:IsA("ProximityPrompt") then
				return Descendant
			end
		end

		return nil
	end

	local function isSeatedOnBed(Bed)
		local Humanoid = getHumanoid()

		if not Humanoid then
			return false
		end

		local SeatPart = Humanoid.SeatPart

		if not SeatPart then
			return false
		end

		local Current = SeatPart

		while Current and Current ~= game do
			if Current == Bed then
				return true
			end

			Current = Current.Parent
		end

		return false
	end

	local function notify(Title, Content, Icon)
		if not Notification then
			return
		end

		pcall(function()
			Notification:Notify({
				Title = Title,
				Content = Content,
				Icon = Icon or "bed"
			})
		end)
	end

	function OpTrainingFeature:RunBedRoutine()
		if self.State ~= "idle" then
			return
		end

		self.State = "busy"
		self.LastAttemptAt = os.clock()

		local Bed = findBed()

		if not Bed then
			self.State = "idle"
			return
		end

		local Prompt = findBedPrompt(Bed)

		if not Prompt then
			self.State = "idle"
			return
		end

		local RootPart = getRootPart()

		if not RootPart then
			self.State = "idle"
			return
		end

		self.BedOriginalCFrame = Bed:GetPivot()
		self.PlayerReturnCFrame = RootPart.CFrame

		local Character = getCharacter()

		if Character then
			pcall(function()
				Character:PivotTo(self.BedOriginalCFrame * CFrame.new(0, 3, 0))
			end)
		end

		task.wait(0.25)

		if type(fireproximityprompt) == "function" then
			pcall(fireproximityprompt, Prompt, Prompt.HoldDuration)
		end

		local WaitStart = os.clock()

		while os.clock() - WaitStart < self.MountWaitSeconds do
			if not self.Enabled then
				break
			end

			if isSeatedOnBed(Bed) then
				break
			end

			task.wait(0.1)
		end

		if not isSeatedOnBed(Bed) then
			notify("OP Training", "Bed use failed — not enough cash?", "alert-circle")
			self.State = "idle"
			return
		end

		notify("OP Training", "Sleeping underground")

		pcall(function()
			Bed:PivotTo(self.BedOriginalCFrame * CFrame.new(0, self.BedOffsetY, 0))
		end)

		local SleepStart = os.clock()

		while self.Enabled do
			local Fatigue = getBodyFatigue()

			if Fatigue <= self.FatigueExitPercent then
				break
			end

			if os.clock() - SleepStart > self.SleepTimeoutSeconds then
				break
			end

			task.wait(0.5)
		end

		pcall(function()
			Bed:PivotTo(self.BedOriginalCFrame)
		end)

		task.wait(0.2)

		local Humanoid = getHumanoid()

		if Humanoid then
			pcall(function()
				Humanoid.Sit = false
			end)

			pcall(function()
				Humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
			end)
		end

		task.wait(0.3)

		local Character2 = getCharacter()

		if Character2 and self.PlayerReturnCFrame then
			pcall(function()
				Character2:PivotTo(self.PlayerReturnCFrame)
			end)
		end

		notify("OP Training", "Done — fatigue recovered", "check-circle")
		self.State = "idle"
	end

	function OpTrainingFeature:Step()
		if not self.Enabled then
			return
		end

		if self.State ~= "idle" then
			return
		end

		if (os.clock() - self.LastAttemptAt) < self.RetryCooldownSeconds then
			return
		end

		local Fatigue = getBodyFatigue()

		if Fatigue >= self.FatigueTriggerPercent then
			task.spawn(function()
				self:RunBedRoutine()
			end)
		end
	end

	function OpTrainingFeature:SetEnabled(Value)
		local State = false

		if Value then
			State = true
		end

		if self.Enabled == State then
			return State
		end

		self.Enabled = State

		if self.Connection then
			self.Connection:Disconnect()
			self.Connection = nil
		end

		if State then
			self.Elapsed = 0
			self.Connection = RunService.Heartbeat:Connect(function(DeltaTime)
				self.Elapsed = self.Elapsed + DeltaTime

				if self.Elapsed < self.LoopInterval then
					return
				end

				self.Elapsed = 0
				self:Step()
			end)

			notify("OP Training", "Enabled — auto bed active")
		else
			notify("OP Training", "Disabled", "x-circle")
		end

		return State
	end

	function OpTrainingFeature:IsEnabled()
		return self.Enabled == true
	end

	function OpTrainingFeature:Destroy()
		self:SetEnabled(false)
	end

	return OpTrainingFeature
end
