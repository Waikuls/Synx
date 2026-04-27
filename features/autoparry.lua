return function(Config)
	local Players = game:GetService("Players")
	local Workspace = game:GetService("Workspace")

	local LocalPlayer = Players.LocalPlayer

	local Notification = Config and Config.Notification
	local Window = Config and Config.Window

	local AutoParryFeature = {
		Enabled = false,
		AnimConnections = {},
		EntityConnections = {},
		LastParryAt = 0,
		-- Cooldown between parry attempts. UBG parry has its own internal CD,
		-- but we add this to avoid hammering the remote when several enemies
		-- swing at once and to keep stamina bleed predictable.
		ParryCooldown = 0.25,
	}

	-- Path fragments that mean "definitely not an attack we should parry".
	-- Checked first; if any matches the animation's full path the anim is
	-- skipped before allow-patterns even run.
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

	-- Animation instance names that are never attacks (idle / walk / block /
	-- victim-side skill roles). Catches cases where the path filter would
	-- otherwise let through an off-target child of Skills/Styles.
	local DenyNameSet = {
		Target = true, Victim = true, Grab = true, Counter = true,
		Block = true, BlockOLD = true,
		Idle = true, idle = true,
		Walk = true, walk = true, StyleWalk = true,
		Run = true, Sprint = true, sprint = true,
		Rhythm = true,
		sit = true, climb = true, fall = true, jump = true,
	}

	local function isAttackAnimation(animation)
		if not animation then return false end

		local path = animation:GetFullName()
		local name = animation.Name

		for _, pat in ipairs(DenyPathPatterns) do
			if path:find(pat) then return false end
		end

		if DenyNameSet[name] then return false end

		-- M1 combat strings: Animations.Styles.<X>.Default.Combat.<1-4>
		if path:find("%.Default%.Combat%.") then return true end

		-- M2 / heavy: Animations.Styles.<X>.Default.Critical
		if path:find("%.Default%.Critical$") then return true end

		-- Skill animations (after deny filter strips Target/Victim/Grab/Counter)
		if path:find("Animations%.Skills%.") then return true end

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

	local function shouldSkipTarget(model)
		-- UBG keeps player and NPC entities under workspace.Entities, named
		-- by username for players. The entity model is separate from
		-- Player.Character so GetPlayerFromCharacter returns nil for these
		-- entities. Resolve by name like the other features in this project
		-- (autotrain, esp, food, optraining all use this pattern).
		local plr = Players:FindFirstChild(model.Name)

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

	local function tryParry(model, animation)
		if not AutoParryFeature.Enabled then return end

		local now = os.clock()
		if now - AutoParryFeature.LastParryAt < AutoParryFeature.ParryCooldown then
			return
		end

		if not isAttackAnimation(animation) then return end
		if shouldSkipTarget(model) then return end
		if not isInRange(model) then return end
		if not hasEnoughStamina() then return end

		-- Reserve the cooldown slot before the optional jitter delay so a
		-- second attack arriving during the jitter wait doesn't trigger a
		-- parallel parry.
		AutoParryFeature.LastParryAt = now

		local delayMs = getDelayMs()

		if delayMs > 0 then
			task.wait(math.random(0, delayMs) / 1000)
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
						local anim = track and track.Animation
						tryParry(model, anim)
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
		-- UBG parents both player characters and NPCs under Workspace.Entities.
		-- A single ChildAdded listener on that folder covers everything we
		-- need without double-hooking via Players:GetPlayers().
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
