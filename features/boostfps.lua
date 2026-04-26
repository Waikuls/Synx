return function(Config)
	local Lighting = game:GetService("Lighting")
	local Workspace = game:GetService("Workspace")

	local Notification = Config and Config.Notification

	-- Effect ClassNames we disable to free render budget. These are the
	-- ones that fire every frame regardless of view direction and add up
	-- fast in busy scenes.
	local DisableableEffects = {
		ParticleEmitter = true,
		Trail = true,
		Beam = true,
		Smoke = true,
		Fire = true,
		Sparkles = true,
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
		-- Single bag of saved values keyed by name. Cleared on disable
		-- after restore.
		Saved = {},
		-- Map: instance -> previous Enabled value. Used so we only
		-- restore exactly what we touched (skip instances that were
		-- already disabled before boost activated).
		TouchedEffects = {},
		Connections = {},
		-- Target FPS cap. 360 is high enough that the cap won't be the
		-- bottleneck on any consumer monitor.
		TargetFps = 360,
		-- FogEnd while boost is on. Small enough that distant geometry
		-- gets fog-clipped (cheaper to render) but far enough that
		-- normal gameplay isn't visibly clipped at melee range.
		BoostFogEnd = 250,
	}

	local function disableEffect(Inst)
		if BoostFps.TouchedEffects[Inst] ~= nil then
			return
		end

		local Ok, OldEnabled = pcall(function() return Inst.Enabled end)

		if not Ok then
			return
		end

		BoostFps.TouchedEffects[Inst] = OldEnabled

		if OldEnabled then
			pcall(function() Inst.Enabled = false end)
		end
	end

	local function trackedSet(Key, GetFn, SetFn, NewValue)
		local OkGet, Current = pcall(GetFn)

		if OkGet then
			BoostFps.Saved[Key] = Current
		end

		pcall(SetFn, NewValue)
	end

	local function applyBoost()
		BoostFps.Saved = {}
		BoostFps.TouchedEffects = {}

		-- Rendering quality
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

		-- Lighting
		trackedSet("GlobalShadows",
			function() return Lighting.GlobalShadows end,
			function(v) Lighting.GlobalShadows = v end,
			false)

		trackedSet("FogEnd",
			function() return Lighting.FogEnd end,
			function(v) Lighting.FogEnd = v end,
			BoostFps.BoostFogEnd)

		trackedSet("EnvironmentDiffuseScale",
			function() return Lighting.EnvironmentDiffuseScale end,
			function(v) Lighting.EnvironmentDiffuseScale = v end,
			0)

		trackedSet("EnvironmentSpecularScale",
			function() return Lighting.EnvironmentSpecularScale end,
			function(v) Lighting.EnvironmentSpecularScale = v end,
			0)

		-- FPS cap raise
		if type(setfpscap) == "function" then
			pcall(setfpscap, BoostFps.TargetFps)
		end

		-- Disable existing effects in workspace + Lighting post effects
		for _, Inst in ipairs(Workspace:GetDescendants()) do
			if DisableableEffects[Inst.ClassName] then
				disableEffect(Inst)
			end
		end

		for _, Inst in ipairs(Lighting:GetDescendants()) do
			if PostEffectClasses[Inst.ClassName] then
				disableEffect(Inst)
			end
		end

		-- Hook future additions so effects spawned mid-session also get
		-- silenced (explosions, weather, etc).
		table.insert(BoostFps.Connections, Workspace.DescendantAdded:Connect(function(Inst)
			if not BoostFps.Enabled then return end

			if DisableableEffects[Inst.ClassName] then
				disableEffect(Inst)
			end
		end))

		table.insert(BoostFps.Connections, Lighting.DescendantAdded:Connect(function(Inst)
			if not BoostFps.Enabled then return end

			if PostEffectClasses[Inst.ClassName] then
				disableEffect(Inst)
			end
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
		for _, Conn in ipairs(BoostFps.Connections) do
			pcall(function() Conn:Disconnect() end)
		end
		BoostFps.Connections = {}

		-- Restore individual effect Enabled flags
		for Inst, OldEnabled in pairs(BoostFps.TouchedEffects) do
			if Inst and Inst.Parent then
				pcall(function() Inst.Enabled = OldEnabled end)
			end
		end
		BoostFps.TouchedEffects = {}

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

		-- FPS cap restore. Most executors treat very high values as
		-- effectively uncapped, which matches the engine's default.
		if type(setfpscap) == "function" then
			pcall(setfpscap, 240)
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
