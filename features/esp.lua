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

			return CoreGui
		end)

		if Success and Result then
			return Result
		end

		return CoreGui
	end

	local function getCurrentCamera()
		return workspace.CurrentCamera
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

	local function getCharacterBounds(Character)
		local Camera = getCurrentCamera()
		local RootPart = getCharacterRoot(Character)

		if not Camera or not RootPart then
			return nil
		end

		local Success, BoundingCFrame, BoundingSize = pcall(function()
			return Character:GetBoundingBox()
		end)

		if not Success or not BoundingCFrame or not BoundingSize then
			BoundingCFrame = RootPart.CFrame
			BoundingSize = RootPart.Size + Vector3.new(2.5, 3.5, 2.5)
		end

		local HalfSize = BoundingSize * 0.5
		local ViewportSize = Camera.ViewportSize
		local MinX = math.huge
		local MinY = math.huge
		local MaxX = -math.huge
		local MaxY = -math.huge
		local VisiblePoints = 0
		local OnScreenPoints = 0
		local Signs = {-1, 1}

		for _, XFactor in ipairs(Signs) do
			for _, YFactor in ipairs(Signs) do
				for _, ZFactor in ipairs(Signs) do
					local Corner = BoundingCFrame:PointToWorldSpace(
						Vector3.new(
							HalfSize.X * XFactor,
							HalfSize.Y * YFactor,
							HalfSize.Z * ZFactor
						)
					)
					local ScreenPoint, OnScreen = Camera:WorldToViewportPoint(Corner)

					if ScreenPoint.Z > 0 then
						VisiblePoints = VisiblePoints + 1
						MinX = math.min(MinX, ScreenPoint.X)
						MinY = math.min(MinY, ScreenPoint.Y)
						MaxX = math.max(MaxX, ScreenPoint.X)
						MaxY = math.max(MaxY, ScreenPoint.Y)

						if OnScreen then
							OnScreenPoints = OnScreenPoints + 1
						end
					end
				end
			end
		end

		if VisiblePoints < 2 or OnScreenPoints == 0 then
			return nil
		end

		if MaxX < -32 or MinX > ViewportSize.X + 32 or MaxY < -32 or MinY > ViewportSize.Y + 32 then
			return nil
		end

		local Width = MaxX - MinX
		local Height = MaxY - MinY

		if Width < 2 or Height < 2 then
			return nil
		end

		if Width > (ViewportSize.X * 1.5) or Height > (ViewportSize.Y * 1.5) then
			return nil
		end

		return MinX, MinY, MaxX, MaxY
	end

	local function createStroke(Parent, Thickness, Color)
		local Stroke = Instance.new("UIStroke")
		Stroke.Thickness = Thickness
		Stroke.Color = Color
		Stroke.Transparency = 0
		Stroke.Parent = Parent

		return Stroke
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
		local Container = Instance.new("Frame")
		Container.Name = string.format("ESP_%s", tostring(Player.UserId))
		Container.BackgroundTransparency = 1
		Container.BorderSizePixel = 0
		Container.Visible = false
		Container.ZIndex = 500
		Container.Parent = self:GetGuiRoot()

		local Outline = Instance.new("Frame")
		Outline.Name = "Outline"
		Outline.BackgroundTransparency = 1
		Outline.BorderSizePixel = 0
		Outline.Size = UDim2.new(1, 0, 1, 0)
		Outline.ZIndex = 500
		Outline.Parent = Container
		createStroke(Outline, 3, Color3.fromRGB(0, 0, 0))

		local Box = Instance.new("Frame")
		Box.Name = "Box"
		Box.BackgroundTransparency = 1
		Box.BorderSizePixel = 0
		Box.Size = UDim2.new(1, 0, 1, 0)
		Box.ZIndex = 501
		Box.Parent = Container
		createStroke(Box, 1, Color3.fromRGB(245, 49, 116))

		local Name = Instance.new("TextLabel")
		Name.Name = "Name"
		Name.AnchorPoint = Vector2.new(0, 1)
		Name.BackgroundTransparency = 1
		Name.BorderSizePixel = 0
		Name.Position = UDim2.new(0, 0, 0, -4)
		Name.Size = UDim2.new(1, 0, 0, 16)
		Name.Font = Enum.Font.GothamSemibold
		Name.Text = ""
		Name.TextColor3 = Color3.fromRGB(255, 255, 255)
		Name.TextSize = 13
		Name.TextStrokeTransparency = 0.35
		Name.TextXAlignment = Enum.TextXAlignment.Center
		Name.Visible = false
		Name.ZIndex = 502
		Name.Parent = Container

		local Health = Instance.new("TextLabel")
		Health.Name = "Health"
		Health.BackgroundTransparency = 1
		Health.BorderSizePixel = 0
		Health.Position = UDim2.new(0, 0, 1, 4)
		Health.Size = UDim2.new(1, 0, 0, 16)
		Health.Font = Enum.Font.GothamSemibold
		Health.Text = ""
		Health.TextColor3 = Color3.fromRGB(110, 255, 140)
		Health.TextSize = 13
		Health.TextStrokeTransparency = 0.35
		Health.TextXAlignment = Enum.TextXAlignment.Center
		Health.Visible = false
		Health.ZIndex = 502
		Health.Parent = Container

		self.Entries[Player] = {
			Container = Container,
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

		Entry.Container.Visible = false
		Entry.Name.Visible = false
		Entry.Health.Visible = false
	end

	function ESP:RemoveEntry(Player)
		local Entry = self.Entries[Player]

		if not Entry then
			return
		end

		Entry.Container:Destroy()
		self.Entries[Player] = nil
	end

	function ESP:Clear()
		for Player in pairs(self.Entries) do
			self:RemoveEntry(Player)
		end
	end

	function ESP:UpdateEntry(Player, Humanoid, MinX, MinY, MaxX, MaxY)
		local Entry = self:GetEntry(Player)
		local Width = math.max(math.floor((MaxX - MinX) + 0.5), 2)
		local Height = math.max(math.floor((MaxY - MinY) + 0.5), 2)

		Entry.Container.Position = UDim2.new(0, math.floor(MinX + 0.5), 0, math.floor(MinY + 0.5))
		Entry.Container.Size = UDim2.new(0, Width, 0, Height)
		Entry.Container.Visible = true

		if self.Settings.ShowName then
			Entry.Name.Text = Player.DisplayName or Player.Name
			Entry.Name.Visible = true
		else
			Entry.Name.Visible = false
		end

		if self.Settings.ShowHealth then
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
		local Humanoid = Character and Character:FindFirstChildOfClass("Humanoid")
		local RootPart = getCharacterRoot(Character)
		local LocalRootPart = getLocalRootPart()

		if not Character or not Humanoid or not RootPart or Humanoid.Health <= 0 then
			self:HideEntry(Player)
			return false
		end

		if LocalRootPart then
			local Distance = (LocalRootPart.Position - RootPart.Position).Magnitude

			if Distance > self.Settings.DistanceLimit then
				self:HideEntry(Player)
				return false
			end
		end

		local MinX, MinY, MaxX, MaxY = getCharacterBounds(Character)

		if not MinX then
			self:HideEntry(Player)
			return false
		end

		self:UpdateEntry(Player, Humanoid, MinX, MinY, MaxX, MaxY)

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
			end
		end
	end

	function ESP:SetShowHealth(Value)
		self.Settings.ShowHealth = Value and true or false

		if not self.Settings.ShowHealth then
			for _, Entry in pairs(self.Entries) do
				Entry.Health.Visible = false
			end
		end
	end

	return ESP
end
