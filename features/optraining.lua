return function(Config)
	local Players = game:GetService("Players")
	local RunService = game:GetService("RunService")
	local PathfindingService = game:GetService("PathfindingService")
	local UserInputService = game:GetService("UserInputService")
	local HttpService = game:GetService("HttpService")
	local LocalPlayer = Players.LocalPlayer
	local Notification = Config and Config.Notification

	warn("[KELV][OpTraining] module loaded version=v24-sprint-controls-off")

	local WaypointStorageFolder = "KELV"
	local WaypointStoragePath = "KELV/optraining_waypoints.json"

	local OpTrainingFeature = {}
	OpTrainingFeature.Enabled = false
	OpTrainingFeature.Connection = nil
	OpTrainingFeature.LoopInterval = 0.5
	OpTrainingFeature.Elapsed = 0
	OpTrainingFeature.AutoTrainRef = nil

	-- Behavior knobs
	OpTrainingFeature.FatigueTriggerPercent = 40
	OpTrainingFeature.FatigueExitPercent = 0
	OpTrainingFeature.MountWaitSeconds = 3
	OpTrainingFeature.SleepTimeoutSeconds = 180
	OpTrainingFeature.RetryCooldownSeconds = 5
	OpTrainingFeature.WalkTimeoutSeconds = 20
	OpTrainingFeature.WaypointArriveDistance = 4
	OpTrainingFeature.LowStaminaPercent = 3
	OpTrainingFeature.DoubleTapGapSec = 0.08

	-- Waypoints keyed by AutoTrain machine type (Bike, Bench, Treadmill, ...).
	-- Each value is an array of Vector3 walked in order before reaching the
	-- bed, and walked in reverse on the way back. Empty = go straight.
	OpTrainingFeature.WaypointsByType = {}

	-- Runtime state
	OpTrainingFeature.State = "idle"
	OpTrainingFeature.PlayerReturnCFrame = nil
	OpTrainingFeature.LastAttemptAt = 0
	OpTrainingFeature.InputConnection = nil
	OpTrainingFeature.CameraConnection = nil
	OpTrainingFeature.SavedCameraType = nil
	OpTrainingFeature.SavedCameraOffset = nil
	OpTrainingFeature.ControlsDisabled = false

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

	local function getStaminaPercent()
		local Ref = OpTrainingFeature.AutoTrainRef

		if Ref and type(Ref.GetStaminaPercent) == "function" then
			local Ok, Value = pcall(function()
				return Ref:GetStaminaPercent()
			end)

			if Ok and type(Value) == "number" then
				return Value
			end
		end

		return 100
	end

	local function lockCamera()
		if OpTrainingFeature.CameraConnection then
			return
		end

		local Camera = workspace.CurrentCamera

		if not Camera then
			return
		end

		local Root = getRootPart()

		if not Root then
			return
		end

		OpTrainingFeature.SavedCameraType = Camera.CameraType
		OpTrainingFeature.SavedCameraOffset = Root.CFrame:ToObjectSpace(Camera.CFrame)

		Camera.CameraType = Enum.CameraType.Scriptable

		OpTrainingFeature.CameraConnection = RunService.RenderStepped:Connect(function()
			local R = getRootPart()
			local Cam = workspace.CurrentCamera

			if not R or not Cam then
				return
			end

			if OpTrainingFeature.SavedCameraOffset then
				Cam.CFrame = R.CFrame * OpTrainingFeature.SavedCameraOffset
			end
		end)

		warn("[KELV][OpTraining] camera locked (mouse free)")
	end

	local function unlockCamera()
		if OpTrainingFeature.CameraConnection then
			OpTrainingFeature.CameraConnection:Disconnect()
			OpTrainingFeature.CameraConnection = nil
		end

		local Camera = workspace.CurrentCamera

		if Camera and OpTrainingFeature.SavedCameraType then
			Camera.CameraType = OpTrainingFeature.SavedCameraType
		end

		OpTrainingFeature.SavedCameraType = nil
		OpTrainingFeature.SavedCameraOffset = nil

		warn("[KELV][OpTraining] camera unlocked")
	end

	local function getVirtualInputManager()
		local Ok, VIM = pcall(game.GetService, game, "VirtualInputManager")

		if Ok then
			return VIM
		end

		return nil
	end

	local SprintHeld = false
	local SprintRevision = 0

	local function disableDefaultControls()
		if OpTrainingFeature.ControlsDisabled then
			return
		end

		local Ok = pcall(function()
			local PlayerScripts = LocalPlayer:FindFirstChild("PlayerScripts")

			if not PlayerScripts then
				return
			end

			local Module = PlayerScripts:FindFirstChild("PlayerModule")

			if not Module then
				return
			end

			local PM = require(Module)
			local Controls = PM:GetControls()

			if Controls and type(Controls.Disable) == "function" then
				Controls:Disable()
			end
		end)

		if Ok then
			OpTrainingFeature.ControlsDisabled = true
			warn("[KELV][OpTraining] default controls disabled")
		end
	end

	local function enableDefaultControls()
		if not OpTrainingFeature.ControlsDisabled then
			return
		end

		pcall(function()
			local PlayerScripts = LocalPlayer:FindFirstChild("PlayerScripts")

			if not PlayerScripts then
				return
			end

			local Module = PlayerScripts:FindFirstChild("PlayerModule")

			if not Module then
				return
			end

			local PM = require(Module)
			local Controls = PM:GetControls()

			if Controls and type(Controls.Enable) == "function" then
				Controls:Enable()
			end
		end)

		OpTrainingFeature.ControlsDisabled = false
		warn("[KELV][OpTraining] default controls enabled")
	end

	local function sprintOn()
		if SprintHeld then
			return
		end

		local VIM = getVirtualInputManager()

		if not VIM then
			return
		end

		-- ControlScript writes Humanoid.MoveDirection from W input every frame
		-- and was fighting MoveTo, causing the character to walk in circles.
		-- Disable PlayerModule controls — UserInputService events still fire
		-- so the game's sprint detector can still react to the W keys below.
		disableDefaultControls()

		SprintHeld = true
		SprintRevision = SprintRevision + 1
		local MyRev = SprintRevision

		task.spawn(function()
			-- First tap: press + release (quick)
			pcall(function()
				VIM:SendKeyEvent(true, Enum.KeyCode.W, false, game)
			end)

			task.wait(0.03)

			if SprintRevision ~= MyRev then
				return
			end

			pcall(function()
				VIM:SendKeyEvent(false, Enum.KeyCode.W, false, game)
			end)

			task.wait(OpTrainingFeature.DoubleTapGapSec)

			if SprintRevision ~= MyRev or not SprintHeld then
				return
			end

			-- Second press, HOLD — game's sprint state latches on while held.
			pcall(function()
				VIM:SendKeyEvent(true, Enum.KeyCode.W, false, game)
			end)
		end)
	end

	local function sprintOff()
		if not SprintHeld then
			return
		end

		SprintHeld = false
		SprintRevision = SprintRevision + 1

		local VIM = getVirtualInputManager()

		if VIM then
			pcall(function()
				VIM:SendKeyEvent(false, Enum.KeyCode.W, false, game)
			end)
		end
	end

	local function restoreWalkSpeed()
		sprintOff()
		enableDefaultControls()
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

	local function getCurrentMachineType()
		local Ref = OpTrainingFeature.AutoTrainRef

		if Ref and type(Ref.GetSelectedType) == "function" then
			local Ok, Value = pcall(function()
				return Ref:GetSelectedType()
			end)

			if Ok and type(Value) == "string" and Value ~= "" then
				return Value
			end
		end

		return "Default"
	end

	local function getCurrentWaypointList()
		local Type = getCurrentMachineType()

		if not OpTrainingFeature.WaypointsByType[Type] then
			OpTrainingFeature.WaypointsByType[Type] = {}
		end

		return OpTrainingFeature.WaypointsByType[Type], Type
	end

	local function serializeAllWaypoints()
		local Export = {}

		for Type, List in pairs(OpTrainingFeature.WaypointsByType) do
			local Serialized = {}

			for _, Waypoint in ipairs(List) do
				table.insert(Serialized, {X = Waypoint.X, Y = Waypoint.Y, Z = Waypoint.Z})
			end

			Export[Type] = Serialized
		end

		local Ok, Json = pcall(function()
			return HttpService:JSONEncode(Export)
		end)

		if Ok and type(Json) == "string" then
			return Json
		end

		return "{}"
	end

	local function deserializeAllWaypoints(Text)
		local Result = {}

		if type(Text) ~= "string" or Text == "" then
			return Result
		end

		local Ok, Data = pcall(function()
			return HttpService:JSONDecode(Text)
		end)

		if not Ok or type(Data) ~= "table" then
			return Result
		end

		for Type, List in pairs(Data) do
			if type(Type) == "string" and type(List) == "table" then
				local Parsed = {}

				for _, Entry in ipairs(List) do
					if type(Entry) == "table"
						and type(Entry.X) == "number"
						and type(Entry.Y) == "number"
						and type(Entry.Z) == "number" then
						table.insert(Parsed, Vector3.new(Entry.X, Entry.Y, Entry.Z))
					end
				end

				Result[Type] = Parsed
			end
		end

		return Result
	end

	local function saveWaypointsToFile()
		if type(writefile) ~= "function" then
			return
		end

		if type(makefolder) == "function" then
			pcall(makefolder, WaypointStorageFolder)
		end

		pcall(writefile, WaypointStoragePath, serializeAllWaypoints())
	end

	local function loadWaypointsFromFile()
		if type(readfile) ~= "function" then
			return
		end

		local Ok, Result = pcall(readfile, WaypointStoragePath)

		if Ok and type(Result) == "string" and Result ~= "" then
			OpTrainingFeature.WaypointsByType = deserializeAllWaypoints(Result)

			local Summary = {}

			for Type, List in pairs(OpTrainingFeature.WaypointsByType) do
				table.insert(Summary, string.format("%s=%d", Type, #List))
			end

			warn(string.format("[KELV][OpTraining] loaded waypoints: %s", #Summary > 0 and table.concat(Summary, ", ") or "(empty)"))
		end
	end

	local LastSprintLogAt = 0

	local function maintainSprint()
		local Stamina = getStaminaPercent()
		local ShouldSprint = Stamina >= OpTrainingFeature.LowStaminaPercent
		local Now = os.clock()

		if ShouldSprint and not SprintHeld then
			warn(string.format("[KELV][OpTraining] stamina %.1f%% >= %d%%, sprint ON (hold W)", Stamina, OpTrainingFeature.LowStaminaPercent))
			sprintOn()
			LastSprintLogAt = Now
		elseif (not ShouldSprint) and SprintHeld then
			warn(string.format("[KELV][OpTraining] stamina %.1f%% < %d%%, sprint OFF (release W)", Stamina, OpTrainingFeature.LowStaminaPercent))
			sprintOff()
			LastSprintLogAt = Now
		elseif (Now - LastSprintLogAt) >= 3 then
			LastSprintLogAt = Now
			warn(string.format("[KELV][OpTraining] stamina %.1f%% sprinting=%s", Stamina, tostring(SprintHeld)))
		end
	end

	local function walkToPosition(TargetPos, TimeoutSec)
		TimeoutSec = TimeoutSec or 20

		local Humanoid = getHumanoid()
		local Root = getRootPart()

		if not Humanoid or not Root then
			return false, "no humanoid/root"
		end

		maintainSprint()

		local Path = PathfindingService:CreatePath({
			AgentRadius = 2,
			AgentHeight = 5,
			AgentCanJump = true,
			AgentMaxSlope = 60,
		})

		local ComputeOk = pcall(function()
			Path:ComputeAsync(Root.Position, TargetPos)
		end)

		local StartAt = os.clock()

		if ComputeOk and Path.Status == Enum.PathStatus.Success then
			local PathWaypoints = Path:GetWaypoints()
			warn(string.format("[KELV][OpTraining] path computed %d waypoints", #PathWaypoints))

			for _, Waypoint in ipairs(PathWaypoints) do
				if not OpTrainingFeature.Enabled then
					return false, "disabled"
				end

				if os.clock() - StartAt > TimeoutSec then
					return false, "timeout"
				end

				local Hum = getHumanoid()

				if not Hum then
					return false, "humanoid gone"
				end

				if Waypoint.Action == Enum.PathWaypointAction.Jump then
					Hum.Jump = true
				end

				Hum:MoveTo(Waypoint.Position)

				local StepStart = os.clock()

				while os.clock() - StepStart < 6 do
					if not OpTrainingFeature.Enabled then
						return false, "disabled"
					end

					local R = getRootPart()

					if not R then
						return false, "root gone"
					end

					if (R.Position - Waypoint.Position).Magnitude <= OpTrainingFeature.WaypointArriveDistance then
						break
					end

					maintainSprint()
					task.wait(0.1)
				end
			end

			return true
		end

		warn(string.format("[KELV][OpTraining] pathfind failed (status=%s), fallback direct MoveTo", tostring(Path.Status)))

		local Hum = getHumanoid()

		if not Hum then
			return false, "no humanoid"
		end

		Hum:MoveTo(TargetPos)

		while os.clock() - StartAt < TimeoutSec do
			if not OpTrainingFeature.Enabled then
				return false, "disabled"
			end

			local R = getRootPart()

			if not R then
				return false, "root gone"
			end

			if (R.Position - TargetPos).Magnitude <= OpTrainingFeature.WaypointArriveDistance then
				return true
			end

			maintainSprint()
			task.wait(0.2)

			local H = getHumanoid()
			if H then H:MoveTo(TargetPos) end
		end

		return false, "fallback timeout"
	end

	local function walkThroughWaypoints(WaypointList)
		for Index, Waypoint in ipairs(WaypointList) do
			if not OpTrainingFeature.Enabled then
				return false
			end

			warn(string.format("[KELV][OpTraining] walking to waypoint %d: %s", Index, tostring(Waypoint)))
			local Ok, Reason = walkToPosition(Waypoint, OpTrainingFeature.WalkTimeoutSeconds)

			if not Ok then
				warn(string.format("[KELV][OpTraining] waypoint %d failed: %s", Index, tostring(Reason)))
				return false
			end
		end

		return true
	end

	local function reverseArray(Source)
		local Result = {}

		for Index = #Source, 1, -1 do
			table.insert(Result, Source[Index])
		end

		return Result
	end

	function OpTrainingFeature:RunBedRoutine()
		warn(string.format("[KELV][OpTraining] RunBedRoutine entry state=%s", tostring(self.State)))

		if self.State ~= "idle" then
			warn("[KELV][OpTraining] RunBedRoutine: state not idle, abort")
			return
		end

		self.State = "busy"
		self.LastAttemptAt = os.clock()

		notify("OP Training", "Triggered — walking to bed")
		warn("[KELV][OpTraining] state=busy, looking for bed prompt")

		local Prompt = findBedPrompt(nil)

		if not Prompt then
			notify("OP Training", "Bed prompt not found", "alert-circle")
			self.State = "idle"
			return
		end

		warn(string.format(
			"[KELV][OpTraining] Prompt at %s: action=%s",
			Prompt:GetFullName(),
			tostring(Prompt.ActionText)
		))

		local Bed = findBedFromPrompt(Prompt)

		if not Bed then
			notify("OP Training", "Bed model not found", "alert-circle")
			self.State = "idle"
			return
		end

		local RootPart = getRootPart()

		if not RootPart then
			notify("OP Training", "Character not ready", "alert-circle")
			self.State = "idle"
			return
		end

		if type(fireproximityprompt) ~= "function" then
			notify("OP Training", "fireproximityprompt unavailable", "alert-circle")
			self.State = "idle"
			return
		end

		self.PlayerReturnCFrame = RootPart.CFrame

		local SeatPart = Prompt.Parent
		local SeatPosition = (SeatPart and SeatPart:IsA("BasePart")) and SeatPart.Position or Bed:GetPivot().Position

		local CurrentWaypoints, CurrentType = getCurrentWaypointList()

		-- Walk forward through waypoints, then to the seat
		if #CurrentWaypoints > 0 then
			warn(string.format("[KELV][OpTraining] [%s] walking %d forward waypoints", CurrentType, #CurrentWaypoints))

			if not walkThroughWaypoints(CurrentWaypoints) then
				notify("OP Training", "Failed to follow waypoints", "alert-circle")
				self.State = "idle"
				return
			end
		else
			warn(string.format("[KELV][OpTraining] [%s] no waypoints, walking direct", CurrentType))
		end

		warn(string.format("[KELV][OpTraining] walking to seat at %s", tostring(SeatPosition)))
		local WalkOk, WalkReason = walkToPosition(SeatPosition, self.WalkTimeoutSeconds)

		if not WalkOk then
			warn(string.format("[KELV][OpTraining] walk to seat failed: %s", tostring(WalkReason)))
			notify("OP Training", "Could not reach bed", "alert-circle")
			restoreWalkSpeed()
			self.State = "idle"
			return
		end

		restoreWalkSpeed()

		-- Fire prompt while close to the seat
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
		warn(string.format("[KELV][OpTraining] seated=%s SeatPart=%s", tostring(Seated), tostring(getHumanoid() and getHumanoid().SeatPart or "nil")))

		if not Seated then
			notify("OP Training", "Bed use failed — not enough cash?", "alert-circle")
			self.State = "idle"
			return
		end

		notify("OP Training", "Sleeping — fatigue recovering")

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

		-- Stand up
		local Humanoid = getHumanoid()

		if Humanoid then
			pcall(function()
				Humanoid.Sit = false
			end)

			pcall(function()
				Humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
			end)
		end

		task.wait(0.5)

		-- Walk back through reversed waypoints, then to the original position
		if #CurrentWaypoints > 0 then
			warn(string.format("[KELV][OpTraining] [%s] walking back through reversed waypoints", CurrentType))
			walkThroughWaypoints(reverseArray(CurrentWaypoints))
		end

		if self.PlayerReturnCFrame then
			warn(string.format("[KELV][OpTraining] walking back to return position"))
			walkToPosition(self.PlayerReturnCFrame.Position, self.WalkTimeoutSeconds)
		end

		restoreWalkSpeed()

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

			lockCamera()
			notify("OP Training", "Enabled — camera locked, auto bed active")
		else
			restoreWalkSpeed()
			unlockCamera()
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

	function OpTrainingFeature:AddWaypoint(Position)
		if not Position then
			local Root = getRootPart()

			if not Root then
				notify("OP Training", "Character not ready", "alert-circle")
				return false
			end

			Position = Root.Position
		end

		local List, Type = getCurrentWaypointList()
		table.insert(List, Position)
		saveWaypointsToFile()

		notify("OP Training", string.format(
			"[%s] Waypoint %d added (%.0f, %.0f, %.0f)",
			Type,
			#List,
			Position.X,
			Position.Y,
			Position.Z
		), "map-pin")

		warn(string.format("[KELV][OpTraining] [%s] waypoint %d added at %s", Type, #List, tostring(Position)))
		return true
	end

	function OpTrainingFeature:RemoveLastWaypoint()
		local List, Type = getCurrentWaypointList()

		if #List == 0 then
			notify("OP Training", string.format("[%s] No waypoints", Type), "alert-circle")
			return false
		end

		local Removed = table.remove(List)
		saveWaypointsToFile()

		notify("OP Training", string.format("[%s] Removed last (%d remain)", Type, #List), "minus-circle")
		warn(string.format("[KELV][OpTraining] [%s] removed waypoint at %s, %d remain", Type, tostring(Removed), #List))
		return true
	end

	function OpTrainingFeature:ClearWaypoints()
		local List, Type = getCurrentWaypointList()
		local Count = #List
		self.WaypointsByType[Type] = {}
		saveWaypointsToFile()

		notify("OP Training", string.format("[%s] Cleared %d waypoints", Type, Count), "trash-2")
		warn(string.format("[KELV][OpTraining] [%s] cleared %d waypoints", Type, Count))
		return true
	end

	function OpTrainingFeature:GetWaypoints()
		local List = getCurrentWaypointList()
		local Copy = {}

		for Index, Waypoint in ipairs(List) do
			Copy[Index] = Waypoint
		end

		return Copy
	end

	function OpTrainingFeature:SetupKeybinds()
		if self.InputConnection then
			return
		end

		self.InputConnection = UserInputService.InputBegan:Connect(function(Input, Processed)
			if Processed then
				return
			end

			if Input.KeyCode == Enum.KeyCode.Semicolon then
				OpTrainingFeature:AddWaypoint()
			elseif Input.KeyCode == Enum.KeyCode.Minus then
				OpTrainingFeature:RemoveLastWaypoint()
			elseif Input.KeyCode == Enum.KeyCode.Quote then
				OpTrainingFeature:ClearWaypoints()
			end
		end)

		warn("[KELV][OpTraining] keybinds: ';' add wp | '-' remove last | \"'\" clear all")
	end

	function OpTrainingFeature:Destroy()
		self:SetEnabled(false)

		if self.InputConnection then
			self.InputConnection:Disconnect()
			self.InputConnection = nil
		end

		unlockCamera()
		restoreWalkSpeed()
	end

	loadWaypointsFromFile()
	OpTrainingFeature:SetupKeybinds()

	return OpTrainingFeature
end
