return function(Config)
	local Lighting = game:GetService("Lighting")
	local Workspace = game:GetService("Workspace")

	local Notification = Config and Config.Notification

	-- Effect ClassNames we disable to free render budget. These fire
	-- every frame regardless of view direction and add up fast in busy
	-- scenes.
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
		-- "normal" or "ultra". Tracked so the UI can mutual-exclude the
		-- two toggles cleanly.
		Mode = nil,
		-- Single bag of saved values keyed by name. Cleared on disable
		-- after restore.
		Saved = {},
		-- Map: instance -> previous Enabled value. Lets us restore only
		-- the instances we actually touched.
		TouchedEffects = {},
		Connections = {},
		-- Normal mode keeps fog comfortable for melee / interior play.
		NormalFogEnd = 250,
		-- Ultra pulls fog in tight so distant geometry gets clipped.
		-- Looks foggy but cuts the most render work outside.
		UltraFogEnd = 80,
		-- Ultra streaming radius (only honored when the place uses
		-- StreamingEnabled). 64 studs unloads anything past close
		-- proximity.
		UltraStreamingRadius = 64,
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

	local function applyBoost(Mode)
		BoostFps.Saved = {}
		BoostFps.TouchedEffects = {}

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

		-- Lighting
		local FogEndTarget = (Mode == "ultra") and BoostFps.UltraFogEnd or BoostFps.NormalFogEnd

		trackedSet("GlobalShadows",
			function() return Lighting.GlobalShadows end,
			function(v) Lighting.GlobalShadows = v end,
			false)

		trackedSet("FogEnd",
			function() return Lighting.FogEnd end,
			function(v) Lighting.FogEnd = v end,
			FogEndTarget)

		trackedSet("EnvironmentDiffuseScale",
			function() return Lighting.EnvironmentDiffuseScale end,
			function(v) Lighting.EnvironmentDiffuseScale = v end,
			0)

		trackedSet("EnvironmentSpecularScale",
			function() return Lighting.EnvironmentSpecularScale end,
			function(v) Lighting.EnvironmentSpecularScale = v end,
			0)

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

		-- Ultra-only: shrink streaming radius. Only meaningful for
		-- places that ship with StreamingEnabled — otherwise silently
		-- skipped so we don't break worlds that load everything.
		if Mode == "ultra" then
			pcall(function()
				if Workspace.StreamingEnabled then
					BoostFps.Saved.StreamingTargetRadius = Workspace.StreamingTargetRadius
					Workspace.StreamingTargetRadius = BoostFps.UltraStreamingRadius
				end
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

		if Saved.StreamingTargetRadius ~= nil then
			pcall(function() Workspace.StreamingTargetRadius = Saved.StreamingTargetRadius end)
		end

		BoostFps.Saved = {}
	end

	function BoostFps:SetEnabled(Value, Mode)
		local State = Value and true or false
		Mode = Mode or "normal"

		-- No-op if nothing is changing.
		if State == self.Enabled and (not State or Mode == self.Mode) then
			return State
		end

		if not State then
			if self.Enabled then
				revertBoost()
			end

			self.Enabled = false
			self.Mode = nil

			if Notification then
				Notification:Notify({
					Title = "Boost FPS",
					Content = "Graphics restored",
					Icon = "x-circle"
				})
			end

			warn("[KELV][BoostFps] disabled")
			return State
		end

		-- Enabling, possibly switching modes — revert old state first
		-- so the new mode applies on top of the saved originals, not on
		-- top of an already-mutated lighting set.
		if self.Enabled then
			revertBoost()
		end

		self.Enabled = true
		self.Mode = Mode
		applyBoost(Mode)

		if Notification then
			Notification:Notify({
				Title = "Boost FPS",
				Content = (Mode == "ultra") and "Ultra mode active" or "Graphics minimized for higher FPS",
				Icon = "check-circle"
			})
		end

		warn("[KELV][BoostFps] enabled mode=" .. Mode)
		return State
	end

	function BoostFps:GetMode()
		return self.Mode
	end

	function BoostFps:IsEnabled()
		return self.Enabled
	end

	function BoostFps:Destroy()
		self:SetEnabled(false)
	end

	return BoostFps
end
