return function(Config)
	local Players = game:GetService("Players")
	local LocalPlayer = Players.LocalPlayer
	local Notification = Config and Config.Notification

	local SpectatorFeature = {
		Enabled = false,
		TargetName = nil,
		SavedSubject = nil,
		SavedCameraType = nil,
		TargetCharacterConnection = nil,
		TargetLeaveConnection = nil,
		LocalRespawnConnection = nil
	}

	local function getCamera()
		return workspace.CurrentCamera
	end

	local function notify(Title, Content, Icon)
		if not Notification then
			return
		end

		Notification:Notify({
			Title = Title,
			Content = Content,
			Icon = Icon
		})
	end

	local function findPlayerByName(Name)
		if type(Name) ~= "string" or Name == "" then
			return nil
		end

		for _, Player in ipairs(Players:GetPlayers()) do
			if Player.Name == Name then
				return Player
			end
		end

		return nil
	end

	local function collectOtherPlayers()
		local OtherPlayers = {}

		for _, Player in ipairs(Players:GetPlayers()) do
			if Player ~= LocalPlayer then
				table.insert(OtherPlayers, Player)
			end
		end

		table.sort(OtherPlayers, function(Left, Right)
			return Left.Name < Right.Name
		end)

		return OtherPlayers
	end

	local function disconnectTrackers()
		if SpectatorFeature.TargetCharacterConnection then
			SpectatorFeature.TargetCharacterConnection:Disconnect()
			SpectatorFeature.TargetCharacterConnection = nil
		end

		if SpectatorFeature.TargetLeaveConnection then
			SpectatorFeature.TargetLeaveConnection:Disconnect()
			SpectatorFeature.TargetLeaveConnection = nil
		end

		if SpectatorFeature.LocalRespawnConnection then
			SpectatorFeature.LocalRespawnConnection:Disconnect()
			SpectatorFeature.LocalRespawnConnection = nil
		end
	end

	local function bindCharacter(Character)
		if not Character then
			return
		end

		local Camera = getCamera()

		if not Camera then
			return
		end

		task.spawn(function()
			local Humanoid = Character:FindFirstChildOfClass("Humanoid")

			if not Humanoid then
				Humanoid = Character:WaitForChild("Humanoid", 5)
			end

			if not Humanoid or not SpectatorFeature.Enabled then
				return
			end

			Camera.CameraSubject = Humanoid
			Camera.CameraType = Enum.CameraType.Custom
		end)
	end

	local function attachTarget(Player)
		if SpectatorFeature.TargetCharacterConnection then
			SpectatorFeature.TargetCharacterConnection:Disconnect()
			SpectatorFeature.TargetCharacterConnection = nil
		end

		if not Player then
			return
		end

		if Player.Character then
			bindCharacter(Player.Character)
		end

		SpectatorFeature.TargetCharacterConnection = Player.CharacterAdded:Connect(function(Character)
			if not SpectatorFeature.Enabled then
				return
			end

			bindCharacter(Character)
		end)
	end

	local function saveCameraState()
		local Camera = getCamera()

		if not Camera then
			return
		end

		SpectatorFeature.SavedSubject = Camera.CameraSubject
		SpectatorFeature.SavedCameraType = Camera.CameraType
	end

	local function restoreCameraState()
		local Camera = getCamera()

		if not Camera then
			return
		end

		local Subject = SpectatorFeature.SavedSubject

		if Subject and Subject.Parent then
			Camera.CameraSubject = Subject
		else
			local Character = LocalPlayer.Character

			if Character then
				local Humanoid = Character:FindFirstChildOfClass("Humanoid")

				if Humanoid then
					Camera.CameraSubject = Humanoid
				end
			end
		end

		Camera.CameraType = SpectatorFeature.SavedCameraType or Enum.CameraType.Custom

		SpectatorFeature.SavedSubject = nil
		SpectatorFeature.SavedCameraType = nil
	end

	function SpectatorFeature:GetPlayerOptions()
		local Options = {}

		for _, Player in ipairs(collectOtherPlayers()) do
			table.insert(Options, Player.Name)
		end

		if #Options == 0 then
			table.insert(Options, "(no players)")
		end

		return Options
	end

	function SpectatorFeature:GetTargetPlayerName()
		if self.TargetName and findPlayerByName(self.TargetName) then
			return self.TargetName
		end

		local OtherPlayers = collectOtherPlayers()

		if #OtherPlayers > 0 then
			return OtherPlayers[1].Name
		end

		return "(no players)"
	end

	function SpectatorFeature:IsEnabled()
		return self.Enabled
	end

	function SpectatorFeature:SetTargetPlayerName(Name)
		local Resolved = (type(Name) == "string" and Name ~= "" and Name ~= "(no players)") and Name or nil

		self.TargetName = Resolved

		if not self.Enabled then
			return Resolved
		end

		local Target = findPlayerByName(Resolved)

		if not Target then
			self:SetEnabled(false)
			notify("Spectator", "Target unavailable", "alert-circle")
			return Resolved
		end

		attachTarget(Target)
		notify("Spectator", "Watching " .. Target.Name, "eye")

		return Resolved
	end

	function SpectatorFeature:SetEnabled(Value)
		local Desired = Value and true or false

		if self.Enabled == Desired then
			return self.Enabled
		end

		if Desired then
			local Target = findPlayerByName(self.TargetName)

			if not Target then
				local OtherPlayers = collectOtherPlayers()
				Target = OtherPlayers[1]

				if Target then
					self.TargetName = Target.Name
				end
			end

			if not Target then
				notify("Spectator", "No players to spectate", "alert-circle")
				return false
			end

			saveCameraState()
			self.Enabled = true
			attachTarget(Target)

			self.TargetLeaveConnection = Players.PlayerRemoving:Connect(function(LeavingPlayer)
				if not self.Enabled then
					return
				end

				if LeavingPlayer.Name == self.TargetName then
					notify("Spectator", LeavingPlayer.Name .. " left", "x-circle")
					self:SetEnabled(false)
				end
			end)

			self.LocalRespawnConnection = LocalPlayer.CharacterAdded:Connect(function()
				if not self.Enabled then
					return
				end

				local CurrentTarget = findPlayerByName(self.TargetName)

				if CurrentTarget then
					attachTarget(CurrentTarget)
				end
			end)

			notify("Spectator", "Watching " .. Target.Name, "eye")

			return true
		end

		self.Enabled = false
		disconnectTrackers()
		restoreCameraState()
		notify("Spectator", "Disabled", "x-circle")

		return false
	end

	function SpectatorFeature:Destroy()
		self:SetEnabled(false)
	end

	return SpectatorFeature
end
