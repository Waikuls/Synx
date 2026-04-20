return function(Config)
	local Players = game:GetService("Players")
	local RunService = game:GetService("RunService")
	local CoreGui = game:GetService("CoreGui")
	local LocalPlayer = Players.LocalPlayer

	local ESP = {
		Enabled = false,
		Entries = {},
		Connection = nil,
		GuiRoot = nil,
		Settings = {
			DistanceLimit = 1500,
			ShowName = true,
			ShowHealth = true
		}
	}

	local function getGuiParent()
		local Success, Result = pcall(function()
			if type(gethui) == "function" then
				return gethui()
			end

			if LocalPlayer then
				local PlayerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")

				if PlayerGui then
					return PlayerGui
				end
			end

			return CoreGui
		end)

		if Success and Result then
			return Result
		end

		if LocalPlayer then
			local PlayerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")

			if PlayerGui then
				return PlayerGui
			end
		end

		return CoreGui
	end

	local function getCharacterRoot(Character)
		if not Character then
			return nil
		end

		return Character:FindFirstChild("HumanoidRootPart")
			or Character.PrimaryPart
			or Character:FindFirstChild("UpperTorso")
			or Character:FindFirstChild("Torso")
			or Character:FindFirstChild("Head")
			or Character:FindFirstChildWhichIsA("BasePart")
	end

	local function getDisplayPart(Character)
		if not Character then
			return nil
		end

		return Character:FindFirstChild("Head") or getCharacterRoot(Character)
	end

	local function getHumanoid(Character)
		if not Character then
			return nil
		end

		return Character:FindFirstChildOfClass("Humanoid")
	end

	local function getLocalRootPart()
		return getCharacterRoot(LocalPlayer and LocalPlayer.Character)
	end

	local function getHealthColor(Health, MaxHealth)
		local Ratio = math.clamp(Health / math.max(MaxHealth, 1), 0, 1)

		return Color3.fromRGB(
			math.floor(255 * (1 - Ratio)),
			math.floor(255 * Ratio),
			90
		)
	end

	function ESP:GetGuiRoot()
		if self.GuiRoot and self.GuiRoot.Parent then
			return self.GuiRoot
		end

		local ScreenGui = Instance.new("ScreenGui")
		ScreenGui.Name = "FatalityESP"
		ScreenGui.ResetOnSpawn = false
		ScreenGui.IgnoreGuiInset = true
		ScreenGui.DisplayOrder = 9999
		ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		ScreenGui.Parent = getGuiParent()

		self.GuiRoot = ScreenGui

		return ScreenGui
	end

	function ESP:CreateEntry(Player)
		local SelectionBox = Instance.new("SelectionBox")
		SelectionBox.Name = string.format("ESP_%s_Box", tostring(Player.UserId))
		SelectionBox.Adornee = nil
		SelectionBox.Color3 = Color3.fromRGB(245, 49, 116)
		SelectionBox.LineThickness = 0.05
		SelectionBox.SurfaceColor3 = Color3.fromRGB(245, 49, 116)
		SelectionBox.SurfaceTransparency = 1
		SelectionBox.Transparency = 0
		SelectionBox.Parent = workspace

		local Billboard = Instance.new("BillboardGui")
		Billboard.Name = string.format("ESP_%s_Info", tostring(Player.UserId))
		Billboard.AlwaysOnTop = true
		Billboard.LightInfluence = 0
		Billboard.ResetOnSpawn = false
		Billboard.Size = UDim2.new(0, 180, 0, 36)
		Billboard.StudsOffset = Vector3.new(0, 3.4, 0)
		Billboard.Enabled = false
		Billboard.Parent = self:GetGuiRoot()

		local Name = Instance.new("TextLabel")
		Name.Name = "Name"
		Name.BackgroundTransparency = 1
		Name.BorderSizePixel = 0
		Name.Position = UDim2.new(0, 0, 0, 0)
		Name.Size = UDim2.new(1, 0, 0, 18)
		Name.Font = Enum.Font.GothamSemibold
		Name.Text = ""
		Name.TextColor3 = Color3.fromRGB(255, 255, 255)
		Name.TextSize = 13
		Name.TextStrokeTransparency = 0.35
		Name.TextXAlignment = Enum.TextXAlignment.Center
		Name.Visible = false
		Name.Parent = Billboard

		local Health = Instance.new("TextLabel")
		Health.Name = "Health"
		Health.BackgroundTransparency = 1
		Health.BorderSizePixel = 0
		Health.Position = UDim2.new(0, 0, 0, 16)
		Health.Size = UDim2.new(1, 0, 0, 18)
		Health.Font = Enum.Font.GothamSemibold
		Health.Text = ""
		Health.TextColor3 = Color3.fromRGB(110, 255, 140)
		Health.TextSize = 13
		Health.TextStrokeTransparency = 0.35
		Health.TextXAlignment = Enum.TextXAlignment.Center
		Health.Visible = false
		Health.Parent = Billboard

		self.Entries[Player] = {
			SelectionBox = SelectionBox,
			Billboard = Billboard,
			Name = Name,
			Health = Health
		}

		return self.Entries[Player]
	end

	function ESP:GetEntry(Player)
		return self.Entries[Player] or self:CreateEntry(Player)
	end

	function ESP:HideEntry(Player)
		local Entry = self.Entries[Player]

		if not Entry then
			return
		end

		Entry.SelectionBox.Adornee = nil
		Entry.Billboard.Adornee = nil
		Entry.Billboard.Enabled = false
		Entry.Name.Visible = false
		Entry.Health.Visible = false
	end

	function ESP:RemoveEntry(Player)
		local Entry = self.Entries[Player]

		if not Entry then
			return
		end

		Entry.SelectionBox:Destroy()
		Entry.Billboard:Destroy()
		self.Entries[Player] = nil
	end

	function ESP:Clear()
		for Player in pairs(self.Entries) do
			self:RemoveEntry(Player)
		end
	end

	function ESP:UpdateBillboardLayout(Entry)
		local ShowName = self.Settings.ShowName
		local ShowHealth = self.Settings.ShowHealth

		if ShowName and ShowHealth then
			Entry.Billboard.Size = UDim2.new(0, 180, 0, 36)
			Entry.Name.Position = UDim2.new(0, 0, 0, 0)
			Entry.Health.Position = UDim2.new(0, 0, 0, 16)
		elseif ShowName or ShowHealth then
			Entry.Billboard.Size = UDim2.new(0, 180, 0, 20)
			Entry.Name.Position = UDim2.new(0, 0, 0, 1)
			Entry.Health.Position = UDim2.new(0, 0, 0, 1)
		else
			Entry.Billboard.Size = UDim2.new(0, 180, 0, 0)
		end
	end

	function ESP:UpdateEntry(Player, Character, Humanoid)
		local Entry = self:GetEntry(Player)
		local DisplayPart = getDisplayPart(Character)

		Entry.SelectionBox.Adornee = Character
		self:UpdateBillboardLayout(Entry)

		if DisplayPart and (self.Settings.ShowName or self.Settings.ShowHealth) then
			Entry.Billboard.Adornee = DisplayPart
			Entry.Billboard.Enabled = true
		else
			Entry.Billboard.Adornee = nil
			Entry.Billboard.Enabled = false
		end

		if self.Settings.ShowName then
			Entry.Name.Text = Player.DisplayName or Player.Name
			Entry.Name.Visible = true
		else
			Entry.Name.Visible = false
		end

		if self.Settings.ShowHealth and Humanoid then
			Entry.Health.Text = string.format(
				"%d / %d",
				math.floor(Humanoid.Health + 0.5),
				math.floor(Humanoid.MaxHealth + 0.5)
			)
			Entry.Health.TextColor3 = getHealthColor(Humanoid.Health, Humanoid.MaxHealth)
			Entry.Health.Visible = true
		else
			Entry.Health.Visible = false
		end
	end

	function ESP:UpdatePlayer(Player)
		if Player == LocalPlayer then
			self:RemoveEntry(Player)
			return false
		end

		local Character = Player.Character
		local RootPart = getCharacterRoot(Character)
		local Humanoid = getHumanoid(Character)
		local LocalRootPart = getLocalRootPart()

		if not Character or not RootPart then
			self:HideEntry(Player)
			return false
		end

		if Humanoid and Humanoid.Health <= 0 then
			self:HideEntry(Player)
			return false
		end

		if LocalRootPart and RootPart then
			local Distance = (LocalRootPart.Position - RootPart.Position).Magnitude

			if Distance > self.Settings.DistanceLimit then
				self:HideEntry(Player)
				return false
			end
		end

		self:UpdateEntry(Player, Character, Humanoid)

		return true
	end

	function ESP:Update()
		local SeenPlayers = {}

		for _, Player in ipairs(Players:GetPlayers()) do
			if self:UpdatePlayer(Player) then
				SeenPlayers[Player] = true
			end
		end

		for Player in pairs(self.Entries) do
			if not Players:FindFirstChild(Player.Name) then
				self:RemoveEntry(Player)
			elseif not SeenPlayers[Player] then
				self:HideEntry(Player)
			end
		end
	end

	function ESP:SetEnabled(State)
		if self.Enabled == State then
			return State
		end

		self.Enabled = State

		if self.Connection then
			self.Connection:Disconnect()
			self.Connection = nil
		end

		if State then
			self:GetGuiRoot()
			self.Connection = RunService.RenderStepped:Connect(function()
				self:Update()
			end)
		else
			self:Clear()
		end

		return State
	end

	function ESP:Destroy()
		self:SetEnabled(false)
		self:Clear()

		if self.GuiRoot then
			self.GuiRoot:Destroy()
			self.GuiRoot = nil
		end
	end

	function ESP:SetDistanceLimit(Value)
		self.Settings.DistanceLimit = math.max(Value or self.Settings.DistanceLimit, 1)
	end

	function ESP:SetShowName(Value)
		self.Settings.ShowName = Value and true or false

		if not self.Settings.ShowName then
			for _, Entry in pairs(self.Entries) do
				Entry.Name.Visible = false

				if not self.Settings.ShowHealth then
					Entry.Billboard.Enabled = false
				end
			end
		end
	end

	function ESP:SetShowHealth(Value)
		self.Settings.ShowHealth = Value and true or false

		if not self.Settings.ShowHealth then
			for _, Entry in pairs(self.Entries) do
				Entry.Health.Visible = false

				if not self.Settings.ShowName then
					Entry.Billboard.Enabled = false
				end
			end
		end
	end

	return ESP
end
