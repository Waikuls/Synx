return function(Config)
	local Players = game:GetService("Players")
	local RunService = game:GetService("RunService")
	local VirtualInputManager = game:GetService("VirtualInputManager")
	local LocalPlayer = Players.LocalPlayer
	local Notification = Config and Config.Notification

	local QuestBoardCFrame = CFrame.new(
		1438.12988, 24.8087788, -375.287689,
		0.00739149051, -5.10186169e-08, -0.999972701,
		1.74288317e-08, 1, -5.0891181e-08,
		0.999972701, -1.70521943e-08, 0.00739149051
	)

	local UNDERGROUND_Y = -7
	local DELIVER_DEEP_Y = -9
	local DELIVER_RISE_Y = -6
	local DELIVER_TRIGGER_SIZE = Vector3.new(5, 14, 5)

	local AutoJobFeature = {
		Enabled = false,
		Thread = nil,
		ActiveBodyMovers = {},
		LockConnection = nil,
		NoclipConnection = nil,
		NoclippedParts = {}
	}

	local function getRoot()
		local Character = LocalPlayer.Character
		if not Character then return nil end
		return Character:FindFirstChild("HumanoidRootPart")
	end

	local function getObjectCFrame(Obj)
		if not Obj then return nil end
		if Obj:IsA("BasePart") then return Obj.CFrame end
		if Obj:IsA("Model") then
			local Ok, Pivot = pcall(function() return Obj:GetPivot() end)
			if Ok then return Pivot end
		end
		return nil
	end

	local function cleanupBodyMovers()
		for _, Mover in ipairs(AutoJobFeature.ActiveBodyMovers) do
			if Mover and Mover.Parent then
				pcall(function() Mover:Destroy() end)
			end
		end
		table.clear(AutoJobFeature.ActiveBodyMovers)
	end

	local function cleanupLock()
		if AutoJobFeature.LockConnection then
			pcall(function() AutoJobFeature.LockConnection:Disconnect() end)
			AutoJobFeature.LockConnection = nil
		end
	end

	local function enableNoclip()
		if AutoJobFeature.NoclipConnection then return end
		AutoJobFeature.NoclipConnection = RunService.Stepped:Connect(function()
			local Character = LocalPlayer.Character
			if not Character then return end
			for _, Part in ipairs(Character:GetDescendants()) do
				if Part:IsA("BasePart") and Part.CanCollide then
					Part.CanCollide = false
					AutoJobFeature.NoclippedParts[Part] = true
				end
			end
		end)
	end

	local function disableNoclip()
		if AutoJobFeature.NoclipConnection then
			pcall(function() AutoJobFeature.NoclipConnection:Disconnect() end)
			AutoJobFeature.NoclipConnection = nil
		end
		for Part in pairs(AutoJobFeature.NoclippedParts) do
			if Part and Part.Parent then
				pcall(function() Part.CanCollide = true end)
			end
		end
		table.clear(AutoJobFeature.NoclippedParts)
	end

	local function restoreCharacter()
		cleanupBodyMovers()
		cleanupLock()
		disableNoclip()
		local Root = getRoot()
		if Root then
			pcall(function()
				Root.CFrame = Root.CFrame + Vector3.new(0, -UNDERGROUND_Y, 0)
				Root.Anchored = false
			end)
		end
	end

	local function cancellableWait(Duration)
		local Deadline = os.clock() + Duration
		while AutoJobFeature.Enabled and os.clock() < Deadline do
			task.wait(0.1)
		end
		return AutoJobFeature.Enabled
	end

	local function findQuestBoardPrompt()
		local Board = workspace:FindFirstChild("DelayedChildren")
		if Board then
			for _, Child in ipairs(Board:GetChildren()) do
				if Child.Name == "QuestBoard" or Child:FindFirstChild("Job") then
					local Job = Child:FindFirstChild("Job")
					if Job then
						local Prompt = Job:FindFirstChildOfClass("ProximityPrompt")
						if Prompt then return Prompt end
					end
				end
			end
		end
		local Map = workspace:FindFirstChild("Map")
		if Map then
			local Folder = Map:FindFirstChild("Folder")
			local Board2 = Folder and Folder:FindFirstChild("QuestBoard")
			local Job = Board2 and Board2:FindFirstChild("Job")
			if Job then
				return Job:FindFirstChildOfClass("ProximityPrompt")
			end
		end
		return nil
	end

	local function isSpotActive(Spot)
		if not Spot or not Spot.Parent then return false end
		return Spot:FindFirstChild("Deliver") ~= nil
	end

	local function getSpotsFolder()
		local Jobs = workspace:FindFirstChild("Jobs")
		local Delivery = Jobs and Jobs:FindFirstChild("Delivery")
		return Delivery and Delivery:FindFirstChild("Spots")
	end

	local function hasActiveSpot()
		local Spots = getSpotsFolder()
		if not Spots then return false end
		for _, Spot in ipairs(Spots:GetChildren()) do
			if isSpotActive(Spot) then return true end
		end
		return false
	end

	local function safeTeleport(TargetCFrame)
		local Root = getRoot()
		if not Root then return end
		Root.Anchored = true
		Root.CFrame = TargetCFrame + Vector3.new(0, UNDERGROUND_Y, 0)
		cancellableWait(1)
	end

	local function claimQuestAtBoard(Prompt)
		if not Prompt then return false end

		pcall(function()
			Prompt.MaxActivationDistance = 30
			Prompt.RequiresLineOfSight = false
			Prompt.HoldDuration = 0.3
		end)

		for _ = 1, 5 do
			if not AutoJobFeature.Enabled then return false end

			local Root = getRoot()
			if not Root then return false end

			if not cancellableWait(0.5) then return false end

			local SavedCFrame = Root.CFrame

			local Bv = Instance.new("BodyVelocity")
			Bv.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
			Bv.Velocity = Vector3.zero
			Bv.Parent = Root
			table.insert(AutoJobFeature.ActiveBodyMovers, Bv)

			local Bp = Instance.new("BodyPosition")
			Bp.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
			Bp.D = 1000
			Bp.P = 100000
			Bp.Position = SavedCFrame.Position
			Bp.Parent = Root
			table.insert(AutoJobFeature.ActiveBodyMovers, Bp)

			Root.Anchored = false

			local Locked = true
			AutoJobFeature.LockConnection = RunService.Heartbeat:Connect(function()
				if Locked and Root.Parent then
					Root.CFrame = SavedCFrame
					Root.AssemblyLinearVelocity = Vector3.zero
					Root.AssemblyAngularVelocity = Vector3.zero
				end
			end)

			cancellableWait(0.3)
			pcall(function()
				VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.E, false, game)
			end)
			cancellableWait(0.5)
			pcall(function()
				VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.E, false, game)
			end)
			cancellableWait(1)

			Locked = false
			cleanupLock()
			cleanupBodyMovers()

			if not AutoJobFeature.Enabled then return false end

			if Root.Parent then
				Root.Anchored = true
				Root.CFrame = SavedCFrame
			end

			if not cancellableWait(1.5) then return false end

			if hasActiveSpot() then
				return true
			end
		end

		return false
	end

	local function expandTrigger(Part)
		if not Part or not Part:IsA("BasePart") then return end
		pcall(function()
			Part.Size = DELIVER_TRIGGER_SIZE
		end)
	end

	local function deliverAt(SpotData)
		local SpotCFrame = SpotData.cf
		local DeepCFrame = SpotCFrame + Vector3.new(0, DELIVER_DEEP_Y, 0)
		local RisePos = SpotCFrame.Position + Vector3.new(0, DELIVER_RISE_Y, 0)

		for _ = 1, 2 do
			if not AutoJobFeature.Enabled then return false end
			if not SpotData.object.Parent then return true end

			expandTrigger(SpotData.object)
			expandTrigger(SpotData.object:FindFirstChild("Deliver"))

			local Root = getRoot()
			if not Root then return false end

			Root.Anchored = true
			Root.CFrame = DeepCFrame
			if not cancellableWait(0.2) then return false end

			Root = getRoot()
			if not Root then return false end

			local Bv = Instance.new("BodyVelocity")
			Bv.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
			Bv.Velocity = Vector3.zero
			Bv.Parent = Root
			table.insert(AutoJobFeature.ActiveBodyMovers, Bv)

			local Bp = Instance.new("BodyPosition")
			Bp.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
			Bp.D = 1000
			Bp.P = 5000
			Bp.Position = RisePos
			Bp.Parent = Root
			table.insert(AutoJobFeature.ActiveBodyMovers, Bp)

			Root.Anchored = false

			local Deadline = os.clock() + 2
			while os.clock() < Deadline and AutoJobFeature.Enabled do
				task.wait(0.1)
				if not isSpotActive(SpotData.object) then break end
			end

			cleanupBodyMovers()

			Root = getRoot()
			if Root then
				Root.Anchored = true
				Root.CFrame = DeepCFrame
			end

			if not AutoJobFeature.Enabled then return false end

			if not isSpotActive(SpotData.object) then
				return true
			end

			if not cancellableWait(0.5) then return false end
		end

		return false
	end

	local function claimQuest()
		safeTeleport(QuestBoardCFrame)
		if not AutoJobFeature.Enabled then return end
		if not cancellableWait(0.5) then return end

		local Prompt = findQuestBoardPrompt()
		if not Prompt then return end

		claimQuestAtBoard(Prompt)
	end

	local function getActiveSpots()
		local Result = {}
		local Folder = getSpotsFolder()
		if not Folder then return Result end

		for _, Spot in ipairs(Folder:GetChildren()) do
			if isSpotActive(Spot) then
				local CF = getObjectCFrame(Spot)
				if CF then
					table.insert(Result, {
						cf = CF,
						name = Spot.Name,
						object = Spot
					})
				end
			end
		end

		return Result
	end

	local function deliverAll()
		local Spots = getActiveSpots()
		for Index, SpotData in ipairs(Spots) do
			if not AutoJobFeature.Enabled then return end
			deliverAt(SpotData)
			if Index < #Spots then
				if not cancellableWait(7) then return end
			end
		end
	end

	local function runLoop()
		while AutoJobFeature.Enabled do
			claimQuest()
			if not AutoJobFeature.Enabled then break end
			if not cancellableWait(3) then break end
			deliverAll()
			if not AutoJobFeature.Enabled then break end
			if not cancellableWait(3) then break end
		end
		restoreCharacter()
		AutoJobFeature.Thread = nil
	end

	function AutoJobFeature:SetEnabled(Value)
		Value = Value and true or false

		if self.Enabled == Value then
			return Value
		end

		self.Enabled = Value

		if Value then
			enableNoclip()
			self.Thread = task.spawn(runLoop)

			if Notification then
				Notification:Notify({
					Title = "Auto Job",
					Content = "Enabled",
					Icon = "check-circle"
				})
			end
		else
			restoreCharacter()

			if Notification then
				Notification:Notify({
					Title = "Auto Job",
					Content = "Disabled",
					Icon = "x-circle"
				})
			end
		end

		return Value
	end

	function AutoJobFeature:Destroy()
		self.Enabled = false
		restoreCharacter()
	end

	return AutoJobFeature
end
