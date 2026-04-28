return function(Config)
	local Players = game:GetService("Players")
	local Workspace = game:GetService("Workspace")
	local MarketplaceService = game:GetService("MarketplaceService")

	local LocalPlayer = Players.LocalPlayer

	-- Bump on every change. Always printed on SetEnabled(true) so the user
	-- can confirm the loader actually picked up the latest source after a
	-- re-inject.
	local AutoParryVersion = "20260428-r9"

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
		-- AnimationId → true. Built on enable: every parented Animation
		-- whose path classifies as combat (Default.Combat / Default.Critical
		-- / Animations.Skills.<X>.Attacker etc.) lands here so the runtime
		-- hook can ALLOW instantly without re-checking.
		IdMap = {},
		-- AnimationId → true. The "this id has been seen as movement"
		-- registry. The Roblox Animate script names tracks "idle"/"walk"/
		-- "run"/etc; this game also reuses those exact AnimationIds for
		-- replicated remote characters but plays them as
		-- Instance.new("Animation") clones (name="Animation"). Without this
		-- set we'd happily parry an idling player. Populated from pre-scan
		-- (deny-path Animations) and updated whenever we observe a track
		-- with a movement-typed name at runtime.
		DenyIdSet = {},
		-- AnimationId → name string from MarketplaceService. Used as a
		-- last-resort fallback for ids absent from both maps above.
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

	local function pathMatchesAnyDeny(path)
		if not path or path == "" then return false end

		for _, pat in ipairs(DenyPathPatterns) do
			if path:find(pat) then return true end
		end

		return false
	end

	local function pathIsAttack(path, name)
		if not path or path == "" then return false end

		if pathMatchesAnyDeny(path) then return false end
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

	-- Scans every Animation instance in the game tree and partitions them
	-- by AnimationId into:
	--   IdMap     — ALLOW (combat anims under Default.Combat / Critical /
	--               Skills.X.Attacker etc.)
	--   DenyIdSet — explicitly-known non-combat: only added when an
	--               Animation lives under a recognised deny path
	--               (Animate folder / Cape / Emote / Misc / BlockHits /
	--               Idles / Movement / Dash / Morpher / Cutscenes / etc.)
	--               OR is named with a movement role
	--               (idle/walk/run/jump/StyleWalk/...).
	-- Same id appearing in both buckets is treated as ALLOW (an attack id
	-- duplicated under a deny path doesn't mean it isn't an attack).
	local function buildIdMap()
		local map = {}
		local denyIds = {}
		local total = 0

		for _, obj in ipairs(game:GetDescendants()) do
			if obj:IsA("Animation") then
				local id = obj.AnimationId

				if id and id ~= "" then
					local path = obj:GetFullName()
					local name = obj.Name

					if pathIsAttack(path, name) then
						map[id] = true
						denyIds[id] = nil
					elseif not map[id]
						and (pathMatchesAnyDeny(path) or DenyNameSet[name])
					then
						denyIds[id] = true
					end
					total = total + 1
				end
			end
		end

		AutoParryFeature.IdMap = map
		AutoParryFeature.DenyIdSet = denyIds

		local allow, deny = 0, 0
		for _ in pairs(map) do allow = allow + 1 end
		for _ in pairs(denyIds) do deny = deny + 1 end
		return total, allow, deny
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

	-- Side-channel so the caller (tryParry) can log which layer rejected
	-- a track without us having to thread the reason through every return.
	local lastVerdictReason = ""

	local function isAttackAnimation(track, animation)
		animation = animation or (track and track.Animation)
		if not animation then
			lastVerdictReason = "no animation"
			return false
		end

		local id = animation.AnimationId
		if not id or id == "" then
			lastVerdictReason = "no id"
			return false
		end

		-- 0. Known movement id (idle/walk/run/jump/cape/emote/etc.). Comes
		-- before the allow cache because it's the most authoritative
		-- "definitely not combat" signal — the same id often plays as a
		-- dynamic name="Animation" clone for replicated remote characters.
		if AutoParryFeature.DenyIdSet[id] then
			lastVerdictReason = "deny-id-set"
			return false
		end

		-- 1. Cached ALLOW verdict from pre-scan or earlier runtime decision.
		if AutoParryFeature.IdMap[id] then
			lastVerdictReason = "id-map allow"
			return true
		end

		local path = animation:GetFullName()
		local instName = animation.Name

		-- 2. Live path classification (only useful when the game plays a
		-- parented Animation directly; usually the live path is just
		-- "Animation" because of Instance.new). We commit a verdict here
		-- only when the path is definitively allow OR definitively deny.
		-- Unknown paths (e.g. MainScript.AnimCache.X) are left to the
		-- track heuristic so they aren't poisoned as deny.
		if path and path ~= "" and path ~= "Animation" then
			if pathIsAttack(path, instName) then
				AutoParryFeature.IdMap[id] = true
				lastVerdictReason = "path allow"
				return true
			end
			if pathMatchesAnyDeny(path) or DenyNameSet[instName] then
				AutoParryFeature.DenyIdSet[id] = true
				lastVerdictReason = "path deny"
				return false
			end
			-- Unknown path → fall through.
		end

		-- 3. Reject and record movement names. Roblox's standard Animate
		-- script names its tracks "idle"/"walk"/"run"/"jump"/etc. The
		-- same ids may later play as dynamic clones for replicated remote
		-- characters, so we record them in DenyIdSet for that case.
		if DenyNameSet[instName] then
			AutoParryFeature.DenyIdSet[id] = true
			lastVerdictReason = "name in DenyNameSet"
			return false
		end

		-- 4. Track-based heuristic. Combat anims in this game are loaded
		-- via Instance.new("Animation") + LoadAnimation, leaving the
		-- instance name at the default "Animation". Movement-named tracks
		-- are caught by Layer 3 above (or recorded in DenyIdSet from the
		-- local Animate script's prior plays). What survives to here with
		-- name="Animation" is almost always an attack fire.
		--
		-- We don't gate on track.Looped: this game sets Looped=true on
		-- combat anims too, so that filter rejected legitimate parries.
		if instName == "Animation" then
			AutoParryFeature.IdMap[id] = true
			lastVerdictReason = "heuristic allow"
			return true
		end

		-- 5. Last resort: MarketplaceService name lookup. Async — first
		-- encounter returns nil ("still fetching"); subsequent plays of the
		-- same id hit the resolved cache.
		local nm = fetchAnimNameAsync(id)
		if nm == nil then
			lastVerdictReason = "marketplace pending"
			return false
		end

		if nm ~= "" then
			if nameIsAttack(nm) then
				AutoParryFeature.IdMap[id] = true
				lastVerdictReason = "marketplace allow (" .. nm .. ")"
				return true
			end

			-- Only cache deny when the Marketplace name explicitly matches
			-- a deny keyword. Anything else is "we don't recognise this
			-- name" → no cache, retry next time.
			local lower = nm:lower()
			for _, kw in ipairs(DenyKeywords) do
				if lower:find(kw, 1, true) then
					AutoParryFeature.DenyIdSet[id] = true
					lastVerdictReason = "marketplace deny (" .. nm .. ")"
					return false
				end
			end
			lastVerdictReason = "marketplace unknown (" .. nm .. ")"
			return false
		end

		lastVerdictReason = "marketplace empty"
		return false
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
			local extra
			if track then
				extra = string.format("reason=%s | looped=%s len=%.2fs",
					lastVerdictReason, tostring(track.Looped), track.Length or 0)
			else
				extra = "reason=" .. lastVerdictReason
			end
			debugLog("skip: not attack", model, animation, extra)
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
			-- 50% lands the F press around the middle of the wind-up,
			-- which empirically catches the parry window better than
			-- 70% (which fires too late after the window closes).
			baseDelay = math.floor(len * 500)
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
						-- Cheap distance prefilter so far-away entities
						-- don't spam logs or pay the classification cost.
						-- Anything beyond 2x the configured range is dropped
						-- silently before we even look at the track.
						local myChar = LocalPlayer.Character
						if myChar then
							local myPos = getCharacterPos(myChar)
							local theirPos = getCharacterPos(model)
							if myPos and theirPos then
								local mag = (theirPos - myPos).Magnitude
								if mag > getRange() * 2 then return end
							end
						end
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

		-- Clear classification caches so a re-enable rescans fresh. Useful
		-- when something looks misclassified — toggling off/on resets it.
		AutoParryFeature.IdMap = {}
		AutoParryFeature.DenyIdSet = {}
		AutoParryFeature.NameCache = {}
		AutoParryFeature.NameFetching = {}
	end

	local function setupHooks()
		-- Pre-scan all parented Animation instances and build an
		-- AnimationId → verdict map. The runtime hooks below classify
		-- live tracks against this map because the live Animation
		-- instances are typically dynamic clones with no parent path.
		local total, allow, deny = buildIdMap()

		-- Always print version + index counts on enable so the user can
		-- verify the loader actually picked up the latest source.
		warn(string.format(
			"[KELV][AutoParry %s] indexed %d animations | allow=%d deny=%d",
			AutoParryVersion, total, allow, deny))

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
					Content = "Enabled (" .. AutoParryVersion .. ")",
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
