return function(Config)
	local Players = game:GetService("Players")
	local RunService = game:GetService("RunService")
	local LocalPlayer = Players.LocalPlayer
	local Notification = Config and Config.Notification

	warn("[KELV][OpTraining] module loaded version=v7-test-teleport-only")

	local OpTrainingFeature = {}
	OpTrainingFeature.Enabled = false
	OpTrainingFeature.Connection = nil
	OpTrainingFeature.LoopInterval = 0.5
	OpTrainingFeature.Elapsed = 0
	OpTrainingFeature.AutoTrainRef = nil

	-- Behavior knobs
	OpTrainingFeature.BedOffsetY = -21
	OpTrainingFeature.FatigueTriggerPercent = 40
	OpTrainingFeature.FatigueExitPercent = 0
	OpTrainingFeature.MountWaitSeconds = 3
	OpTrainingFeature.SleepTimeoutSeconds = 180
	OpTrainingFeature.RetryCooldownSeconds = 5
	OpTrainingFeature.TestTargetPosition = Vector3.new(1743.629, 38.101, -526.156)

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

	local function getBodyFatigue()
		local Ref = OpTrainingFeature.AutoTrainRef

		if Ref and type(Ref.GetBodyFatigue) == "function" then
			local Ok, Value = pcall(function()
				return Ref:GetBodyFatigue()
			end)

			if Ok and type(Value) == "number" then
				return Value
			end
		end

		return 0
	end

	local function findBedFromPrompt(Prompt)
		if not Prompt then
			return nil
		end

		local BedModel = nil
		local Current = Prompt.Parent

		while Current and Current ~= workspace do
			if Current:IsA("Model") then
				BedModel = Current
			end

			Current = Current.Parent
		end

		return BedModel
	end

	local function promptMentionsBed(Prompt)
		local Action = string.lower(tostring(Prompt.ActionText or ""))
		local Object = string.lower(tostring(Prompt.ObjectText or ""))

		if string.find(Action, "bed", 1, true) or string.find(Object, "bed", 1, true) then
			return true
		end

		if string.find(Action, "sleep", 1, true) or string.find(Object, "sleep", 1, true) then
			return true
		end

		return false
	end

	local function findBedPrompt(Bed)
		local CountBed = 0
		local CountParent = 0
		local CountWorkspace = 0

		if Bed then
			for _, Descendant in ipairs(Bed:GetDescendants()) do
				if Descendant:IsA("ProximityPrompt") then
					warn(string.format("[KELV][OpTraining] findBedPrompt layer1 (Bed descendants) hit: %s", Descendant:GetFullName()))
					return Descendant
				end
			end

			local Parent = Bed.Parent

			if Parent then
				for _, Descendant in ipairs(Parent:GetDescendants()) do
					if Descendant:IsA("ProximityPrompt") then
						CountParent = CountParent + 1

						if promptMentionsBed(Descendant) then
							warn(string.format("[KELV][OpTraining] findBedPrompt layer2 (Parent descendants) hit: %s", Descendant:GetFullName()))
							return Descendant
						end
					end
				end
			end
		end

		local RootPart = getRootPart()
		local Best = nil
		local BestDist = math.huge
		local AllPrompts = {}

		for _, Descendant in ipairs(workspace:GetDescendants()) do
			if Descendant:IsA("ProximityPrompt") then
				CountWorkspace = CountWorkspace + 1
				table.insert(AllPrompts, Descendant)

				if promptMentionsBed(Descendant) then
					local Dist = 999999

					if RootPart then
						local PromptParent = Descendant.Parent

						while PromptParent and PromptParent ~= workspace do
							if PromptParent:IsA("BasePart") then
								Dist = (RootPart.Position - PromptParent.Position).Magnitude
								break
							elseif PromptParent:IsA("Model") then
								local Ok, Pivot = pcall(function()
									return PromptParent:GetPivot()
								end)

								if Ok and Pivot then
									Dist = (RootPart.Position - Pivot.Position).Magnitude
									break
								end
							end

							PromptParent = PromptParent.Parent
						end
					end

					if Dist < BestDist then
						BestDist = Dist
						Best = Descendant
					end
				end
			end
		end

		warn(string.format(
			"[KELV][OpTraining] findBedPrompt summary: layer1=%d layer2=%d workspace-total=%d workspace-bed-matches=%s best=%s",
			CountBed,
			CountParent,
			CountWorkspace,
			Best and "yes" or "no",
			Best and Best:GetFullName() or "none"
		))

		if not Best and #AllPrompts > 0 then
			warn(string.format("[KELV][OpTraining] workspace has %d prompts but none mention bed/sleep. Sample texts:", #AllPrompts))

			for Index = 1, math.min(#AllPrompts, 5) do
				local P = AllPrompts[Index]
				warn(string.format("  [%d] action=%q object=%q at %s", Index, tostring(P.ActionText), tostring(P.ObjectText), P:GetFullName()))
			end
		end

		return Best
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
		warn(string.format("[KELV][OpTraining] RunBedRoutine entry state=%s", tostring(self.State)))

		if self.State ~= "idle" then
			warn("[KELV][OpTraining] RunBedRoutine: state not idle, abort")
			return
		end

		self.State = "busy"
		self.LastAttemptAt = os.clock()

		notify("OP Training", "Triggered — starting bed routine")
		warn("[KELV][OpTraining] state=busy, looking for bed prompt")

		local Prompt = findBedPrompt(nil)

		if not Prompt then
			warn("[KELV][OpTraining] v6 RESULT: no bed prompt in workspace")
			notify("OP Training", "Bed prompt not found anywhere", "alert-circle")
			self.State = "idle"
			return
		end

		warn(string.format(
			"[KELV][OpTraining] Prompt found at %s: action=%s object=%s maxDist=%s",
			Prompt:GetFullName(),
			tostring(Prompt.ActionText),
			tostring(Prompt.ObjectText),
			tostring(Prompt.MaxActivationDistance)
		))

		local Bed = findBedFromPrompt(Prompt)

		if not Bed then
			warn("[KELV][OpTraining] FAIL: could not derive bed model from prompt")
			notify("OP Training", "Bed model not found via prompt", "alert-circle")
			self.State = "idle"
			return
		end

		warn(string.format("[KELV][OpTraining] Bed derived: %s", Bed:GetFullName()))

		local RootPart = getRootPart()

		if not RootPart then
			warn("[KELV][OpTraining] FAIL: no root part")
			notify("OP Training", "Character root part not found", "alert-circle")
			self.State = "idle"
			return
		end

		if type(fireproximityprompt) ~= "function" then
			warn("[KELV][OpTraining] FAIL: fireproximityprompt not a function, type=" .. type(fireproximityprompt))
			notify("OP Training", "fireproximityprompt unavailable in executor", "alert-circle")
			self.State = "idle"
			return
		end

		self.BedOriginalCFrame = Bed:GetPivot()
		self.PlayerReturnCFrame = RootPart.CFrame

		local TargetCFrame = CFrame.new(self.TestTargetPosition)

		warn(string.format(
			"[KELV][OpTraining] TEST: skip bed pivot, teleport char to %s then fire prompt",
			tostring(self.TestTargetPosition)
		))

		local Character = getCharacter()

		if Character then
			local CharOk, CharErr = pcall(function()
				Character:PivotTo(TargetCFrame)
			end)
			warn(string.format("[KELV][OpTraining] Character:PivotTo ok=%s err=%s", tostring(CharOk), tostring(CharErr)))
		end

		task.wait(0.15)

		local FireOk, FireErr = pcall(fireproximityprompt, Prompt, Prompt.HoldDuration)
		warn(string.format("[KELV][OpTraining] fireproximityprompt ok=%s err=%s", tostring(FireOk), tostring(FireErr)))

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

		local Seated = isSeatedOnBed(Bed)
		warn(string.format("[KELV][OpTraining] after mount wait, seated=%s SeatPart=%s", tostring(Seated), tostring(getHumanoid() and getHumanoid().SeatPart or "nil")))

		if not Seated then
			notify("OP Training", "Bed use failed — server rejected or no cash", "alert-circle")

			pcall(function()
				Bed:PivotTo(self.BedOriginalCFrame)
			end)

			local CharacterRestore = getCharacter()

			if CharacterRestore and self.PlayerReturnCFrame then
				pcall(function()
					CharacterRestore:PivotTo(self.PlayerReturnCFrame)
				end)
			end

			self.State = "idle"
			return
		end

		notify("OP Training", "Sleeping underground")

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

	OpTrainingFeature.LastDebugAt = 0
	OpTrainingFeature.DebugInterval = 10

	function OpTrainingFeature:Step()
		if not self.Enabled then
			return
		end

		if self.State ~= "idle" then
			return
		end

		local Now = os.clock()
		local Fatigue = getBodyFatigue()

		if (Now - self.LastDebugAt) >= self.DebugInterval then
			self.LastDebugAt = Now
			local Passes = type(Fatigue) == "number" and Fatigue >= self.FatigueTriggerPercent
			warn(string.format(
				"[KELV][OpTraining] Fatigue=%.6f type=%s trigger>=%s passes=%s RefSet=%s state=%s lastAttempt=%.2fs-ago",
				type(Fatigue) == "number" and Fatigue or -1,
				type(Fatigue),
				tostring(self.FatigueTriggerPercent),
				tostring(Passes),
				tostring(self.AutoTrainRef ~= nil),
				tostring(self.State),
				Now - self.LastAttemptAt
			))
		end

		if (Now - self.LastAttemptAt) < self.RetryCooldownSeconds then
			return
		end

		if Fatigue >= self.FatigueTriggerPercent then
			warn(string.format(
				"[KELV][OpTraining] triggering RunBedRoutine (state=%s)",
				tostring(self.State)
			))
			task.spawn(function()
				local Ok, Err = pcall(function()
					self:RunBedRoutine()
				end)
				if not Ok then
					warn("[KELV][OpTraining] RunBedRoutine error: " .. tostring(Err))
					notify("OP Training", "Error: " .. tostring(Err), "alert-circle")
					self.State = "idle"
				end
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

	function OpTrainingFeature:SetAutoTrainRef(Feature)
		self.AutoTrainRef = Feature
	end

	function OpTrainingFeature:Destroy()
		self:SetEnabled(false)
	end

	return OpTrainingFeature
end
