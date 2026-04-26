return function(Config)
	local Players = game:GetService("Players")
	local RunService = game:GetService("RunService")
	local Workspace = game:GetService("Workspace")

	local LocalPlayer = Players.LocalPlayer
	local Notification = Config and Config.Notification

	local NpcFreeze = {
		Enabled = false,
		-- Beyond this distance from the local character, NPC animation
		-- tracks get paused. Inside this radius they play normally so
		-- nothing nearby looks frozen.
		FarDistance = 100,
		-- Loop tick rate. 0.5 s catches NPCs entering/leaving range
		-- fast enough to look natural without burning per-frame budget.
		TickInterval = 0.5,
		HeartbeatConnection = nil,
		AddedConnection = nil,
		-- Set of every Humanoid we've ever seen. Stale refs (Humanoid
		-- without a Parent) are pruned during tick — cheaper than
		-- maintaining a per-instance disconnect.
		HumanoidCache = {},
		-- Map: AnimationTrack -> original Speed. Lets us restore the
		-- exact speed each track had before we paused it.
		PausedTracks = {},
	}

	local function getLocalRoot()
		local Char = LocalPlayer.Character

		if not Char then
			return nil
		end

		return Char:FindFirstChild("HumanoidRootPart") or Char:FindFirstChild("Torso") or Char:FindFirstChild("UpperTorso")
	end

	local function isLocalHumanoid(Humanoid)
		local Char = LocalPlayer.Character
		return Char and Humanoid:IsDescendantOf(Char)
	end

	local function trackHumanoid(Humanoid)
		if not Humanoid:IsA("Humanoid") then
			return
		end

		if isLocalHumanoid(Humanoid) then
			return
		end

		NpcFreeze.HumanoidCache[Humanoid] = true
	end

	local function pauseTrack(Track)
		if NpcFreeze.PausedTracks[Track] ~= nil then
			return
		end

		local OkSpeed, Speed = pcall(function() return Track.Speed end)
		NpcFreeze.PausedTracks[Track] = OkSpeed and Speed or 1
		pcall(function() Track:AdjustSpeed(0) end)
	end

	local function resumeTrack(Track)
		local Speed = NpcFreeze.PausedTracks[Track]

		if Speed == nil then
			return
		end

		pcall(function() Track:AdjustSpeed(Speed) end)
		NpcFreeze.PausedTracks[Track] = nil
	end

	local function processHumanoid(Humanoid, LocalPos)
		local Model = Humanoid.Parent

		if not Model then
			return
		end

		local Root = Model:FindFirstChild("HumanoidRootPart") or Model:FindFirstChild("Torso") or Model:FindFirstChild("UpperTorso")

		if not Root then
			return
		end

		local Distance = (Root.Position - LocalPos).Magnitude
		local ShouldPause = Distance > NpcFreeze.FarDistance

		local Animator = Humanoid:FindFirstChildOfClass("Animator")

		if not Animator then
			return
		end

		local OkTracks, Tracks = pcall(function() return Animator:GetPlayingAnimationTracks() end)

		if not OkTracks or type(Tracks) ~= "table" then
			return
		end

		for _, Track in ipairs(Tracks) do
			if ShouldPause then
				pauseTrack(Track)
			else
				resumeTrack(Track)
			end
		end
	end

	local function tick()
		local LocalRoot = getLocalRoot()

		if not LocalRoot then
			return
		end

		local LocalPos = LocalRoot.Position

		for Humanoid in pairs(NpcFreeze.HumanoidCache) do
			if Humanoid.Parent then
				processHumanoid(Humanoid, LocalPos)
			else
				NpcFreeze.HumanoidCache[Humanoid] = nil
			end
		end
	end

	local function startLoop()
		-- Seed cache with humanoids that already exist
		for _, Inst in ipairs(Workspace:GetDescendants()) do
			if Inst:IsA("Humanoid") then
				trackHumanoid(Inst)
			end
		end

		-- Pick up humanoids spawned later
		NpcFreeze.AddedConnection = Workspace.DescendantAdded:Connect(function(Inst)
			if not NpcFreeze.Enabled then return end

			if Inst:IsA("Humanoid") then
				trackHumanoid(Inst)
			end
		end)

		local Elapsed = 0
		NpcFreeze.HeartbeatConnection = RunService.Heartbeat:Connect(function(Dt)
			Elapsed = Elapsed + Dt

			if Elapsed < NpcFreeze.TickInterval then
				return
			end

			Elapsed = 0
			tick()
		end)
	end

	local function stopLoop()
		if NpcFreeze.HeartbeatConnection then
			pcall(function() NpcFreeze.HeartbeatConnection:Disconnect() end)
			NpcFreeze.HeartbeatConnection = nil
		end

		if NpcFreeze.AddedConnection then
			pcall(function() NpcFreeze.AddedConnection:Disconnect() end)
			NpcFreeze.AddedConnection = nil
		end

		-- Resume every paused track. Loop over a copy because
		-- resumeTrack mutates the table.
		local Snapshot = {}

		for Track, Speed in pairs(NpcFreeze.PausedTracks) do
			Snapshot[Track] = Speed
		end

		for Track in pairs(Snapshot) do
			resumeTrack(Track)
		end

		NpcFreeze.PausedTracks = {}
		NpcFreeze.HumanoidCache = {}
	end

	function NpcFreeze:SetEnabled(Value)
		local State = Value and true or false

		if self.Enabled == State then
			return State
		end

		self.Enabled = State

		if State then
			startLoop()

			if Notification then
				Notification:Notify({
					Title = "NPC Freeze",
					Content = "Far NPC animations paused",
					Icon = "check-circle"
				})
			end
		else
			stopLoop()

			if Notification then
				Notification:Notify({
					Title = "NPC Freeze",
					Content = "Restored",
					Icon = "x-circle"
				})
			end
		end

		warn("[KELV][NpcFreeze] " .. (State and "enabled" or "disabled"))

		return State
	end

	function NpcFreeze:IsEnabled()
		return self.Enabled
	end

	function NpcFreeze:Destroy()
		self:SetEnabled(false)
	end

	return NpcFreeze
end
