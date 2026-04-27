return function(Config)
	local Players = game:GetService("Players")
	local Workspace = game:GetService("Workspace")
	local MarketplaceService = game:GetService("MarketplaceService")

	local LocalPlayer = Players.LocalPlayer

	local Notification = Config and Config.Notification
	local Window = Config and Config.Window

	local AutoParryFeature = {
		Enabled = false,
		AnimConnections = {},
		EntityConnections = {},
		LastParryAt = 0,
		-- Cooldown between parry attempts. The game's parry has its own
		-- internal CD; we add this to avoid hammering the remote when
		-- several enemies swing at once.
		ParryCooldown = 0.25,
		-- AnimationId → bool. Built from a one-shot scan of game descendants
		-- on enable: classifies every parented Animation instance via path
		-- patterns and stores the verdict by ID. At runtime the game tends
		-- to play dynamic Instance.new("Animation") clones whose
		-- :GetFullName() returns just "Animation", so we can't classify by
		-- path on the live track — but the AnimationId still matches the
		-- parented one in ReplicatedStorage, so we just look it up.
		IdMap = {},
		-- AnimationId → name string from MarketplaceService. Used as a
		-- fallback for IDs that weren't found during the descendants scan
		-- (e.g. animations referenced only by script code, never as
		-- parented Instances).
		NameCache = {},
		NameFetching = {},
	}

	-- Path fragments that mean "definitely not an attack we should parry".
	-- Applied to the parented Animation's GetFullName() during the IdMap
	-- pre-scan and as a runtime fallback when the live animation has a
	-- meaningful path.
	local DenyPathPatterns = {
		"Animations%.Misc",
		"Animations%.General",
		"Animations%.Movement",
		"Animations%.Dash",
		"Animations%.Cape",
		"Animations%.Emotes",
		"Animations%.Knockback",
		"Animations%.Awakens",
		"Animations%.TargetHitSkill",
		"Animations%.Cutscenes",
		"Resources%.Cutscenes",
		"Modules%.Morpher",
		"%.BlockHits",
		"%.Idles?%.",
		"%.Counter%.",
		"Workspace%.NPCS",
		"Workspace%.Trainers",
		"Workspace%.Entities%.[^.]+%.Animate",
		"Workspace%.Entities%.[^.]+%.MainScript%.BotAnimate",
	}

	local DenyNameSet = {
		Target = true, Victim = true, Grab = true, Counter = true,
		Block = true, BlockOLD = true,
		Idle = true, idle = true,
		Walk = true, walk = true, StyleWalk = true,
		Run = true, Sprint = true, sprint = true,
		Rhythm = true,
		sit = true, climb = true, fall = true, jump = true,
	}

	-- Substring keywords used by the MarketplaceService name fallback.
	-- Comparison is case-insensitive (both sides lowercased before find).
	-- Deny is checked first so e.g. "BlockHit" doesn't slip through "Hit".
	local DenyKeywords = {
		"idle", "walk", "run", "sprint", "jump", "fall", "climb", "sit",
		"stance", "rhythm", "rythem", "stylewalk",
		"block", "counter", "stun", "knockback",
		"cape", "dance", "emote",
		"carry", "eating", "holding", "cleaning",
		"skipping", "squat", "bench", "barbell",
		"cam", "cutscene", "awaken", "stage",
		"victim", "target", "grab",
	}

	local AttackKeywords = {
		"m1", "m2", "m3", "m4",
		"attack", "hit", "critical", "critital", "heavy",
		"strike", "slash", "swing", "sword",
		"punch", "kick", "knee", "elbow", "bite",
		"slam", "drop", "barrage", "break", "cut",
		"hadoken", "tatsumaki", "shoryuken", "retsukyaku",
		"bulldoze", "hardpoint", "payback", "floatahh",
		"body drop", "six seiken", "devil", "cleaving",
		"predictive", "cranium", "gazelle", "liver",
		"madeed", "ma deed", "nerve", "stardrop", "star drop",
		"rupture", "whirl", "chokeslam", "thousand",
		"triple kick", "vengeance", "promised", "write em",
		"demon fist",
		"lg", "yuzuki",
		"sky ",
		"attacker",
	}

	local function pathIsAttack(path, name)
		if not path or path == "" then return false end

		for _, pat in ipairs(DenyPathPatterns) do
			if path:find(pat) then return false end
		end

		if DenyNameSet[name] then return false end

		if path:find("%.Default%.Combat%.") then return true end
		if path:find("%.Default%.Critical$") then return true end
		if path:find("Animations%.Skills%.") then return true end

		return false
	end

	local function nameIsAttack(rawName)
		if not rawName or rawName == "" then return false end
		local lower = rawName:lower()

		for _, kw in ipairs(DenyKeywords) do
			if lower:find(kw, 1, true) then return false end
		end

		for _, kw in ipairs(AttackKeywords) do
			if lower:find(kw, 1, true) then return true end
		end

		return false
	end

	-- Scans every Animation instance currently in the game tree, classifies
	-- it via path patterns, and caches the verdict by AnimationId. Run once
	-- on enable; covers the static Animations folder (ReplicatedStorage)
	-- which is what Style/Skill IDs come from in practice.
	local function buildIdMap()
		local map = {}
		local count = 0

		for _, obj in ipairs(game:GetDescendants()) do
			if obj:IsA("Animation") then
				local id = obj.AnimationId

				if id and id ~= "" then
					local verdict = pathIsAttack(obj:GetFullName(), obj.Name)
					-- Same ID can appear under different parents (e.g. a
					-- Combat anim and a BlockHits anim sharing assets).
					-- Bias toward ALLOW so we don't miss a real attack
					-- because a duplicate copy lived under a deny path.
					if verdict or map[id] == nil then
						map[id] = verdict
					end
					count = count + 1
				end
			end
		end

		AutoParryFeature.IdMap = map
		return count
	end

	local function fetchAnimNameAsync(id)
		if AutoParryFeature.NameCache[id] ~= nil then
			return AutoParryFeature.NameCache[id]
		end

		if AutoParryFeature.NameFetching[id] then
			return nil
		end

		AutoParryFeature.NameFetching[id] = true

		task.spawn(function()
			local idNum = tonumber(id:match("%d+"))
			local resolved = ""

			if idNum then
				local ok, info = pcall(function()
					return MarketplaceService:GetProductInfo(idNum)
				end)

				if ok and info and type(info.Name) == "string" then
					resolved = info.Name
				end
			end

			AutoParryFeature.NameCache[id] = resolved
			AutoParryFeature.NameFetching[id] = nil
		end)

		return nil
	end

	local function isDebug()
		if not Window or type(Window.GetFlags) ~= "function" then return false end
		local flag = Window:GetFlags().AutoParryDebugToggle
		if not flag or type(flag.GetValue) ~= "function" then return false end
		local ok, val = pcall(function() return flag:GetValue() end)
		return ok and val == true
	end

	local function debugLog(reason, model, animation, extra)
		if not isDebug() then return end
		local id = animation and animation.AnimationId or "?"
		local name = animation and animation.Name or "?"
		warn(string.format("[KELV][AutoParry] %s | model=%s | name=%s | id=%s%s",
			reason,
			model and model.Name or "?",
			name,
			id,
			extra and (" | " .. extra) or ""))
	end

	local function isAttackAnimation(track, animation)
		animation = animation or (track and track.Animation)
		if not animation then return false end

		local id = animation.AnimationId
		if not id or id == "" then return false end

		-- 1. Cached verdict from a previous resolution.
		local cached = AutoParryFeature.IdMap[id]
		if cached ~= nil then return cached end

		local path = animation:GetFullName()
		local instName = animation.Name

		-- 2. Real path classification (works when the game plays a parented
		-- Animation directly).
		if path and path ~= "" and path ~= "Animation" then
			local verdict = pathIsAttack(path, instName)
			AutoParryFeature.IdMap[id] = verdict
			return verdict
		end

		-- 3. Reject obvious non-combat by instance name. The standard Roblox
		-- Animate script names its tracks "idle" / "walk" / "run" / "jump" /
		-- "fall" / "climb" / "sit" — those cover the cases we want to skip
		-- before guessing.
		if DenyNameSet[instName] then
			AutoParryFeature.IdMap[id] = false
			return false
		end

		-- 4. Track-based heuristic. The game tends to fire combat anims via
		-- Instance.new("Animation") + LoadAnimation, leaving the instance
		-- name at its default "Animation". Movement uses the standard
		-- Animate script which names tracks properly. So a non-looped track
		-- named exactly "Animation" with combat-shaped length is almost
		-- always an attack.
		if instName == "Animation" and track and not track.Looped then
			local len = track.Length
			if len and len > 0.1 and len < 3.5 then
				AutoParryFeature.IdMap[id] = true
				return true
			end
		end

		-- 5. Last resort: MarketplaceService name lookup. Async — first
		-- encounter returns nil ("still fetching"); subsequent plays of the
		-- same ID hit the resolved cache.
		local nm = fetchAnimNameAsync(id)
		if nm == nil then return false end

		local verdict = (nm ~= "") and nameIsAttack(nm) or false
		AutoParryFeature.IdMap[id] = verdict
		return verdict
	end

	local function readFlag(name, default)
		if not Window or type(Window.GetFlags) ~= "function" then
			return default
		end

		local flag = Window:GetFlags()[name]

		if not flag or type(flag.GetValue) ~= "function" then
			return default
		end

		local ok, val = pcall(function() return flag:GetValue() end)

		if ok and val ~= nil then return val end

		return default
	end

	local function getRange()
		return tonumber(readFlag("AutoParryRangeSlider", 15)) or 15
	end

	local function getDelayMs()
		return tonumber(readFlag("AutoParryDelaySlider", 50)) or 50
	end

	local function getMinStamina()
		return tonumber(readFlag("AutoParryMinStaminaSlider", 20)) or 20
	end

	local function shouldStaminaCheck()
		return readFlag("AutoParryStaminaCheckToggle", false) == true
	end

	local function shouldSkipTeam()
		return readFlag("AutoParrySkipTeamToggle", false) == true
	end

	local function shouldSkipFriends()
		return readFlag("AutoParrySkipFriendsToggle", false) == true
	end

	local function shouldParryNpc()
		return readFlag("AutoParryNpcToggle", false) == true
	end

	local function getCharacterPos(model)
		if not model then return nil end
		local pivot = model:FindFirstChild("HumanoidRootPart") or model:FindFirstChild("Head")
		if pivot then return pivot.Position end
		return nil
	end

	local function isInRange(model)
		local myChar = LocalPlayer.Character
		if not myChar then return false end

		local myPos = getCharacterPos(myChar)
		local theirPos = getCharacterPos(model)

		if not myPos or not theirPos then return false end

		return (theirPos - myPos).Magnitude <= getRange()
	end

	-- Try every resolution strategy because games name entity models by
	-- either username, display name, or set Player.Character to the entity.
	-- Missing any one of those produces false-NPC verdicts, which then get
	-- skipped silently when "Parry NPC" is off.
	local function resolvePlayer(model)
		if not model then return nil end

		local plr = Players:GetPlayerFromCharacter(model)
		if plr then return plr end

		plr = Players:FindFirstChild(model.Name)
		if plr then return plr end

		for _, p in ipairs(Players:GetPlayers()) do
			if p.DisplayName == model.Name then return p end
		end

		return nil
	end

	local function shouldSkipTarget(model)
		local plr = resolvePlayer(model)

		if not plr then
			-- Non-player entity (NPC). Toggle controls whether we engage.
			return not shouldParryNpc()
		end

		if plr == LocalPlayer then return true end

		if shouldSkipTeam() and plr.Team and LocalPlayer.Team and plr.Team == LocalPlayer.Team then
			return true
		end

		if shouldSkipFriends() then
			local ok, isFriend = pcall(function()
				return LocalPlayer:IsFriendsWith(plr.UserId)
			end)
			if ok and isFriend then return true end
		end

		return false
	end

	local function getStaminaPercent()
		local entities = Workspace:FindFirstChild("Entities")
		if not entities then return 100 end

		local entity = entities:FindFirstChild(LocalPlayer.Name)
		if not entity then return 100 end

		local mainScript = entity:FindFirstChild("MainScript")
		if not mainScript then return 100 end

		local stats = mainScript:FindFirstChild("Stats")
		if not stats then return 100 end

		local stamina = stats:FindFirstChild("Stamina")
		local maxStamina = stats:FindFirstChild("MaxStamina")

		if not stamina or not maxStamina or maxStamina.Value <= 0 then
			return 100
		end

		return (stamina.Value / maxStamina.Value) * 100
	end

	local function hasEnoughStamina()
		if not shouldStaminaCheck() then return true end
		return getStaminaPercent() >= getMinStamina()
	end

	local function findInputRemote()
		local char = LocalPlayer.Character
		if not char then return nil end

		local main = char:FindFirstChild("MainScript")
		if not main then return nil end

		local input = main:FindFirstChild("Input")

		if input and input:IsA("RemoteEvent") then
			return input
		end

		return nil
	end

	local function fireParry()
		local remote = findInputRemote()
		if not remote then return end

		local downArgs = {
			KeyInfo = { Direction = "None", Name = "F", Airborne = false },
			IsDown = true
		}
		local upArgs = {
			KeyInfo = { Direction = "None", Name = "F", Airborne = false },
			IsDown = false
		}

		pcall(function() remote:FireServer(downArgs) end)
		task.wait(0.05)
		pcall(function() remote:FireServer(upArgs) end)
	end

	local function tryParry(model, track)
		if not AutoParryFeature.Enabled then return end

		local animation = track and track.Animation
		if not animation then return end

		local now = os.clock()
		if now - AutoParryFeature.LastParryAt < AutoParryFeature.ParryCooldown then
			return
		end

		if not isAttackAnimation(track, animation) then
			debugLog("skip: not attack", model, animation)
			return
		end

		if shouldSkipTarget(model) then
			debugLog("skip: whitelist", model, animation)
			return
		end

		if not isInRange(model) then
			debugLog("skip: out of range", model, animation,
				string.format("range=%d", getRange()))
			return
		end

		if not hasEnoughStamina() then
			debugLog("skip: low stamina", model, animation)
			return
		end

		-- Reserve the cooldown slot before the optional jitter delay so a
		-- second attack arriving during the jitter wait doesn't trigger a
		-- parallel parry.
		AutoParryFeature.LastParryAt = now

		-- Parry windows sit in the back half of the attack wind-up, so
		-- firing F immediately on AnimationPlayed lands well before the
		-- window opens. Use the track's own Length to derive a base delay
		-- aimed ~70% through the wind-up; the user's slider then adds
		-- random jitter on top for both anti-detection and edge-case
		-- robustness.
		local userJitter = getDelayMs()
		local len = (track and track.Length) or 0
		local baseDelay = 0

		if len > 0.15 and len < 3.0 then
			baseDelay = math.floor(len * 700)
		end

		local jitter = (userJitter > 0) and math.random(0, userJitter) or 0
		local actualDelay = baseDelay + jitter

		debugLog("FIRE", model, animation,
			string.format("len=%.2fs base=%dms jitter=%dms total=%dms",
				len, baseDelay, jitter, actualDelay))

		if actualDelay > 0 then
			task.wait(actualDelay / 1000)
		end

		if not AutoParryFeature.Enabled then return end

		task.spawn(fireParry)
	end

	local function hookCharacter(model)
		if not model or AutoParryFeature.AnimConnections[model] then return end

		-- Reserve the slot up-front so concurrent ChildAdded fires (e.g. a
		-- character respawn racing the toggle) don't double-hook.
		AutoParryFeature.AnimConnections[model] = true

		task.spawn(function()
			for _ = 1, 10 do
				if not AutoParryFeature.Enabled then
					AutoParryFeature.AnimConnections[model] = nil
					return
				end

				if not model.Parent then
					AutoParryFeature.AnimConnections[model] = nil
					return
				end

				local animator
				local hum = model:FindFirstChildOfClass("Humanoid")

				if hum then
					animator = hum:FindFirstChildOfClass("Animator")
				end

				if not animator then
					local ac = model:FindFirstChildOfClass("AnimationController")
					if ac then animator = ac:FindFirstChildOfClass("Animator") end
				end

				if animator then
					local conn = animator.AnimationPlayed:Connect(function(track)
						tryParry(model, track)
					end)
					AutoParryFeature.AnimConnections[model] = conn
					return
				end

				task.wait(0.5)
			end

			-- Gave up finding an Animator. Leave the slot nil so a later hook
			-- attempt (e.g. respawn) can retry.
			if AutoParryFeature.AnimConnections[model] == true then
				AutoParryFeature.AnimConnections[model] = nil
			end
		end)
	end

	local function unhookCharacter(model)
		local conn = AutoParryFeature.AnimConnections[model]

		if conn and conn ~= true then
			pcall(function() conn:Disconnect() end)
		end

		AutoParryFeature.AnimConnections[model] = nil
	end

	local function disconnectAll()
		for model, conn in pairs(AutoParryFeature.AnimConnections) do
			if conn ~= true then
				pcall(function() conn:Disconnect() end)
			end
		end
		AutoParryFeature.AnimConnections = {}

		for _, conn in ipairs(AutoParryFeature.EntityConnections) do
			pcall(function() conn:Disconnect() end)
		end
		AutoParryFeature.EntityConnections = {}
	end

	local function setupHooks()
		-- Pre-scan all parented Animation instances and build an
		-- AnimationId → verdict map. The runtime hooks below classify
		-- live tracks against this map because the live Animation
		-- instances are typically dynamic clones with no parent path.
		local count = buildIdMap()

		if isDebug() then
			warn(string.format("[KELV][AutoParry] indexed %d Animation instances", count))
		end

		-- The game parents both player characters and NPCs under
		-- Workspace.Entities. A single ChildAdded listener covers
		-- everything without double-hooking via Players:GetPlayers().
		local entities = Workspace:FindFirstChild("Entities")

		if not entities then
			warn("[KELV][AutoParry] Workspace.Entities not found — feature inert")
			return
		end

		for _, m in ipairs(entities:GetChildren()) do
			hookCharacter(m)
		end

		local addedConn = entities.ChildAdded:Connect(function(child)
			if AutoParryFeature.Enabled then
				hookCharacter(child)
			end
		end)
		table.insert(AutoParryFeature.EntityConnections, addedConn)

		local removedConn = entities.ChildRemoved:Connect(function(child)
			unhookCharacter(child)
		end)
		table.insert(AutoParryFeature.EntityConnections, removedConn)
	end

	function AutoParryFeature:SetEnabled(Value)
		local State = Value and true or false

		if self.Enabled == State then
			return State
		end

		self.Enabled = State

		if State then
			setupHooks()

			if Notification then
				Notification:Notify({
					Title = "Auto Parry",
					Content = "Enabled",
					Icon = "check-circle"
				})
			end
		else
			disconnectAll()

			if Notification then
				Notification:Notify({
					Title = "Auto Parry",
					Content = "Disabled",
					Icon = "x-circle"
				})
			end
		end

		return State
	end

	function AutoParryFeature:IsEnabled()
		return self.Enabled
	end

	function AutoParryFeature:Destroy()
		self:SetEnabled(false)
	end

	return AutoParryFeature
end
