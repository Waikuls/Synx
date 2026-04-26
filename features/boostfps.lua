return function(Config)
	local Lighting = game:GetService("Lighting")
	local Workspace = game:GetService("Workspace")

	local Notification = Config and Config.Notification

	-- Workspace-side things we silence by setting Enabled = false. Mix
	-- of particle effects and per-light render passes:
	--   * ParticleEmitter / Trail / Beam / Smoke / Fire / Sparkles
	--     fire every frame regardless of view direction.
	--   * PointLight / SpotLight / SurfaceLight each cost a separate
	--     light pass; rooms with stacked lights get expensive fast.
	--   * Highlight runs an outline shader that's surprisingly heavy
	--     once a few are active.
	local DisableableEffects = {
		ParticleEmitter = true,
		Trail = true,
		Beam = true,
		Smoke = true,
		Fire = true,
		Sparkles = true,
		PointLight = true,
		SpotLight = true,
		SurfaceLight = true,
		Highlight = true,
	}

	-- Lighting post-process effects. Each costs a full-screen pass.
	local PostEffectClasses = {
		BloomEffect = true,
		BlurEffect = true,
		ColorCorrectionEffect = true,
		DepthOfFieldEffect = true,
		SunRaysEffect = true,
	}

	local BoostFps = {
		Enabled = false,
		-- Saved global properties (Lighting / Terrain).
		Saved = {},
		-- Per-instance property snapshots:
		--   TouchedInstances[Inst] = { [Prop] = OriginalValue, ... }
		TouchedInstances = {},
		Connections = {},
		-- Background scan generation. Bumped on revert so an in-flight
		-- scan exits at its next yield instead of mutating restored
		-- state.
		ScanGeneration = 0,
		-- Comfortable fog distance — close enough that distant
		-- geometry gets fog-blended, far enough that melee / interior
		-- play isn't visibly clipped.
		FogEnd = 250,
		-- Chunk size for the workspace scan. Small so each frame stays
		-- cheap during activation; total scan finishes in a few
		-- frames either way.
		ScanChunkSize = 200,
	}

	local function trackProperty(Inst, Prop, NewValue)
		if not Inst or type(Prop) ~= "string" then
			return
		end

		local Existing = BoostFps.TouchedInstances[Inst]

		if Existing and Existing[Prop] ~= nil then
			return
		end

		local Ok, OldValue = pcall(function() return Inst[Prop] end)

		if not Ok then
			return
		end

		if OldValue == NewValue then
			return
		end

		if not Existing then
			Existing = {}
			BoostFps.TouchedInstances[Inst] = Existing
		end

		Existing[Prop] = OldValue
		pcall(function() Inst[Prop] = NewValue end)
	end

	local function trackedSet(Key, GetFn, SetFn, NewValue)
		local OkGet, Current = pcall(GetFn)

		if OkGet then
			BoostFps.Saved[Key] = Current
		end

		pcall(SetFn, NewValue)
	end

	local function applyWorkspaceInstance(Inst)
		if DisableableEffects[Inst.ClassName] then
			trackProperty(Inst, "Enabled", false)
		end
	end

	local function applyLightingInstance(Inst)
		if PostEffectClasses[Inst.ClassName] then
			trackProperty(Inst, "Enabled", false)
		elseif Inst.ClassName == "Atmosphere" then
			-- Atmosphere doesn't have an Enabled flag — Density 0
			-- effectively turns the scattering pass off.
			trackProperty(Inst, "Density", 0)
		end
	end

	local function scanWorkspace(Generation)
		local Descendants = Workspace:GetDescendants()

		for Index, Inst in ipairs(Descendants) do
			if not BoostFps.Enabled or BoostFps.ScanGeneration ~= Generation then
				return
			end

			applyWorkspaceInstance(Inst)

			if Index % BoostFps.ScanChunkSize == 0 then
				task.wait()
			end
		end
	end

	local function applyBoost()
		BoostFps.Saved = {}
		BoostFps.TouchedInstances = {}
		BoostFps.ScanGeneration = BoostFps.ScanGeneration + 1
		local Generation = BoostFps.ScanGeneration

		-- Rendering quality (set both knobs — different executors honor
		-- different ones)
		pcall(function()
			local Render = settings().Rendering

			if Render then
				BoostFps.Saved.QualityLevel = Render.QualityLevel
				Render.QualityLevel = Enum.QualityLevel.Level01
			end
		end)

		pcall(function()
			local UserGameSettings = UserSettings():GetService("UserGameSettings")

			if UserGameSettings then
				BoostFps.Saved.SavedQualityLevel = UserGameSettings.SavedQualityLevel
				UserGameSettings.SavedQualityLevel = Enum.SavedQualitySetting.QualityLevel1
			end
		end)

		-- Lighting globals
		trackedSet("GlobalShadows",
			function() return Lighting.GlobalShadows end,
			function(v) Lighting.GlobalShadows = v end,
			false)

		trackedSet("FogEnd",
			function() return Lighting.FogEnd end,
			function(v) Lighting.FogEnd = v end,
			BoostFps.FogEnd)

		trackedSet("EnvironmentDiffuseScale",
			function() return Lighting.EnvironmentDiffuseScale end,
			function(v) Lighting.EnvironmentDiffuseScale = v end,
			0)

		trackedSet("EnvironmentSpecularScale",
			function() return Lighting.EnvironmentSpecularScale end,
			function(v) Lighting.EnvironmentSpecularScale = v end,
			0)

		-- Existing post effects + Atmosphere under Lighting
		for _, Inst in ipairs(Lighting:GetDescendants()) do
			applyLightingInstance(Inst)
		end

		-- Workspace scan runs in background so the toggle returns
		-- immediately. Lights / particles / highlights get touched in
		-- chunks of ScanChunkSize per frame.
		task.spawn(function()
			scanWorkspace(Generation)
		end)

		-- Hook future additions so effects spawned mid-session
		-- (explosions, weather, new highlights) also get silenced.
		-- Cheap because each fire is a single ClassName lookup +
		-- maybe one property write.
		table.insert(BoostFps.Connections, Workspace.DescendantAdded:Connect(function(Inst)
			if not BoostFps.Enabled then return end
			applyWorkspaceInstance(Inst)
		end))

		table.insert(BoostFps.Connections, Lighting.DescendantAdded:Connect(function(Inst)
			if not BoostFps.Enabled then return end
			applyLightingInstance(Inst)
		end))

		-- Terrain water + decoration
		local Terrain = Workspace:FindFirstChildOfClass("Terrain")

		if Terrain then
			BoostFps.Saved.TerrainDecoration = Terrain.Decoration
			BoostFps.Saved.WaterWaveSize = Terrain.WaterWaveSize
			BoostFps.Saved.WaterWaveSpeed = Terrain.WaterWaveSpeed
			BoostFps.Saved.WaterReflectance = Terrain.WaterReflectance
			BoostFps.Saved.WaterTransparency = Terrain.WaterTransparency

			pcall(function()
				Terrain.Decoration = false
				Terrain.WaterWaveSize = 0
				Terrain.WaterWaveSpeed = 0
				Terrain.WaterReflectance = 0
				Terrain.WaterTransparency = 1
			end)
		end
	end

	local function revertBoost()
		BoostFps.ScanGeneration = BoostFps.ScanGeneration + 1

		for _, Conn in ipairs(BoostFps.Connections) do
			pcall(function() Conn:Disconnect() end)
		end
		BoostFps.Connections = {}

		for Inst, Props in pairs(BoostFps.TouchedInstances) do
			if Inst and Inst.Parent then
				for Prop, OldValue in pairs(Props) do
					pcall(function() Inst[Prop] = OldValue end)
				end
			end
		end
		BoostFps.TouchedInstances = {}

		local Saved = BoostFps.Saved

		pcall(function()
			if Saved.QualityLevel ~= nil then
				settings().Rendering.QualityLevel = Saved.QualityLevel
			end
		end)

		pcall(function()
			if Saved.SavedQualityLevel ~= nil then
				UserSettings():GetService("UserGameSettings").SavedQualityLevel = Saved.SavedQualityLevel
			end
		end)

		if Saved.GlobalShadows ~= nil then
			pcall(function() Lighting.GlobalShadows = Saved.GlobalShadows end)
		end

		if Saved.FogEnd ~= nil then
			pcall(function() Lighting.FogEnd = Saved.FogEnd end)
		end

		if Saved.EnvironmentDiffuseScale ~= nil then
			pcall(function() Lighting.EnvironmentDiffuseScale = Saved.EnvironmentDiffuseScale end)
		end

		if Saved.EnvironmentSpecularScale ~= nil then
			pcall(function() Lighting.EnvironmentSpecularScale = Saved.EnvironmentSpecularScale end)
		end

		local Terrain = Workspace:FindFirstChildOfClass("Terrain")

		if Terrain then
			pcall(function()
				if Saved.TerrainDecoration ~= nil then Terrain.Decoration = Saved.TerrainDecoration end
				if Saved.WaterWaveSize ~= nil then Terrain.WaterWaveSize = Saved.WaterWaveSize end
				if Saved.WaterWaveSpeed ~= nil then Terrain.WaterWaveSpeed = Saved.WaterWaveSpeed end
				if Saved.WaterReflectance ~= nil then Terrain.WaterReflectance = Saved.WaterReflectance end
				if Saved.WaterTransparency ~= nil then Terrain.WaterTransparency = Saved.WaterTransparency end
			end)
		end

		BoostFps.Saved = {}
	end

	function BoostFps:SetEnabled(Value)
		local State = Value and true or false

		if self.Enabled == State then
			return State
		end

		self.Enabled = State

		if State then
			applyBoost()

			if Notification then
				Notification:Notify({
					Title = "Boost FPS",
					Content = "Graphics minimized for higher FPS",
					Icon = "check-circle"
				})
			end
		else
			revertBoost()

			if Notification then
				Notification:Notify({
					Title = "Boost FPS",
					Content = "Graphics restored",
					Icon = "x-circle"
				})
			end
		end

		warn("[KELV][BoostFps] " .. (State and "enabled" or "disabled"))

		return State
	end

	function BoostFps:IsEnabled()
		return self.Enabled
	end

	function BoostFps:Destroy()
		self:SetEnabled(false)
	end

	return BoostFps
end
