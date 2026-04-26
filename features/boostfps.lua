return function(Config)
	local Lighting = game:GetService("Lighting")
	local Workspace = game:GetService("Workspace")

	local Notification = Config and Config.Notification

	-- Effect ClassNames we silence to free render budget. These fire
	-- every frame regardless of view direction.
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
		-- "normal" or "ultra".
		Mode = nil,
		-- Saved global properties (Lighting / Terrain / Workspace).
		Saved = {},
		-- Per-instance property snapshots:
		--   TouchedInstances[Inst] = { [Prop] = OriginalValue, ... }
		-- Lets us restore exactly what we mutated, including
		-- properties already at the target value (we skip those at
		-- mutation time so they never enter this map).
		TouchedInstances = {},
		Connections = {},
		-- Background scan generation. Ultra's workspace walk yields
		-- between chunks; if the user toggles off mid-scan we bump this
		-- and the in-flight scan exits on its next yield.
		ScanGeneration = 0,
		-- Normal mode keeps fog comfortable for melee / interior play.
		NormalFogEnd = 250,
		-- Ultra pulls fog in tight so distant geometry still gets
		-- fog-blended (mostly visual, not the main perf gain).
		UltraFogEnd = 80,
		-- Ultra streaming radius (only honored when StreamingEnabled).
		UltraStreamingRadius = 64,
		-- How many descendants to touch per chunk before yielding.
		-- Smaller = lighter per-frame work (smoother during scan) at
		-- the cost of longer total scan time. 100 keeps individual
		-- frames cheap so Ultra activation doesn't hitch the client.
		ScanChunkSize = 100,
	}

	local function trackProperty(Inst, Prop, NewValue)
		if not Inst or type(Prop) ~= "string" then
			return
		end

		local Existing = BoostFps.TouchedInstances[Inst]

		-- Already touched this prop on this instance — leave the
		-- saved original alone and don't overwrite our snapshot.
		if Existing and Existing[Prop] ~= nil then
			return
		end

		local Ok, OldValue = pcall(function() return Inst[Prop] end)

		if not Ok then
			return
		end

		-- Already at target — nothing to mutate, nothing to restore.
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

	local function applyEffectDisable(Inst)
		if DisableableEffects[Inst.ClassName] then
			trackProperty(Inst, "Enabled", false)
		end
	end

	local function applyPostEffectDisable(Inst)
		if PostEffectClasses[Inst.ClassName] then
			trackProperty(Inst, "Enabled", false)
		end
	end

	-- The Ultra-only per-instance mutations. Fog distance alone doesn't
	-- really cull rendering, so Ultra needs per-instance changes — but
	-- only the cheap-to-apply ones. RenderFidelity = Performance was
	-- previously here and pulled because it forces Roblox to reload
	-- LOD meshes for every MeshPart at once, which stalls the render
	-- thread far worse than any FPS gain it produces.
	local function applyUltraInstance(Inst)
		if Inst:IsA("BasePart") then
			-- CastShadow off saves the shadow rasterization pass even
			-- after GlobalShadows toggle.
			trackProperty(Inst, "CastShadow", false)
		end

		-- Texture inherits Decal, so this branch matches both.
		if Inst:IsA("Decal") then
			-- Hides the surface image and skips its texture sampler.
			-- Walls / signs lose their art — the visible "Ultra is
			-- ugly" tradeoff the user opted into.
			trackProperty(Inst, "Transparency", 1)
		end
	end

	local function scanWorkspace(Mode, Generation)
		local Descendants = Workspace:GetDescendants()

		for Index, Inst in ipairs(Descendants) do
			if not BoostFps.Enabled or BoostFps.ScanGeneration ~= Generation then
				return
			end

			applyEffectDisable(Inst)

			if Mode == "ultra" then
				applyUltraInstance(Inst)
			end

			if Index % BoostFps.ScanChunkSize == 0 then
				task.wait()
			end
		end
	end

	local function applyBoost(Mode)
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

		-- Existing post effects under Lighting
		for _, Inst in ipairs(Lighting:GetDescendants()) do
			applyPostEffectDisable(Inst)
		end

		-- Workspace scan happens in the background so the toggle
		-- callback returns immediately. Big worlds (50k+ descendants)
		-- can otherwise freeze the client for hundreds of ms.
		task.spawn(function()
			scanWorkspace(Mode, Generation)
		end)

		-- Hook future additions so effects spawned mid-session
		-- (explosions, weather) also get silenced. Ultra-specific
		-- mutations (CastShadow / Decal transparency) intentionally do
		-- NOT run here — Workspace.DescendantAdded fires constantly in
		-- physics-heavy games (projectiles / debris) and per-fire
		-- IsA + property writes adds steady CPU overhead that wipes
		-- out the Ultra savings.
		table.insert(BoostFps.Connections, Workspace.DescendantAdded:Connect(function(Inst)
			if not BoostFps.Enabled then return end

			applyEffectDisable(Inst)
		end))

		table.insert(BoostFps.Connections, Lighting.DescendantAdded:Connect(function(Inst)
			if not BoostFps.Enabled then return end

			applyPostEffectDisable(Inst)
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
		-- Bump generation first so any in-flight Ultra scan exits on
		-- its next yield instead of mutating state we're about to
		-- restore.
		BoostFps.ScanGeneration = BoostFps.ScanGeneration + 1

		for _, Conn in ipairs(BoostFps.Connections) do
			pcall(function() Conn:Disconnect() end)
		end
		BoostFps.Connections = {}

		-- Restore every per-instance property we mutated.
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

		if Saved.StreamingTargetRadius ~= nil then
			pcall(function() Workspace.StreamingTargetRadius = Saved.StreamingTargetRadius end)
		end

		BoostFps.Saved = {}
	end

	function BoostFps:SetEnabled(Value, Mode)
		local State = Value and true or false
		Mode = Mode or "normal"

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

		-- Switching modes: revert first so the new mode applies on top
		-- of the saved originals, not on top of an already-mutated set.
		if self.Enabled then
			revertBoost()
		end

		self.Enabled = true
		self.Mode = Mode
		applyBoost(Mode)

		if Notification then
			local Msg = "Graphics minimized for higher FPS"

			if Mode == "ultra" then
				Msg = "Ultra mode applying — scan runs in background"
			end

			Notification:Notify({
				Title = "Boost FPS",
				Content = Msg,
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
