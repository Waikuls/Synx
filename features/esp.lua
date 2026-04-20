return function(Config)
	local Notification = Config.Notification
	local Players = game:GetService("Players")
	local RunService = game:GetService("RunService")
	local CoreGui = game:GetService("CoreGui")
	local LocalPlayer = Players.LocalPlayer
	local SupportsDrawing = type(Drawing) == "table" and type(Drawing.new) == "function"

	local ESP = {
		Enabled = false,
		Entries = {},
		Connection = nil,
		GuiRoot = nil,
		UseDrawing = SupportsDrawing,
		FallbackNotified = false,
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

	local function getLocalRootPart()
		local Character = LocalPlayer and LocalPlayer.Character

		if not Character then
			return nil
		end

		return Character:FindFirstChild("HumanoidRootPart")
	end

	local function getHealthColor(Health, MaxHealth)
		local Ratio = math.clamp(Health / math.max(MaxHealth, 1), 0, 1)

		return Color3.fromRGB(
			math.floor(255 * (1 - Ratio)),
			math.floor(255 * Ratio),
			90
		)
	end

	local function hideDrawing(DrawingObject)
		if DrawingObject then
			DrawingObject.Visible = false
		end
	end

	local function hideInstance(InstanceObject)
		if InstanceObject and InstanceObject:IsA("Highlight") then
			InstanceObject.Enabled = false
		elseif InstanceObject and InstanceObject:IsA("BillboardGui") then
			InstanceObject.Enabled = false
		elseif InstanceObject and InstanceObject:IsA("GuiObject") then
			InstanceObject.Visible = false
		end
	end

	local function getCharacterBounds(Character)
		local Camera = getCurrentCamera()

		if not Camera then
			return nil
		end

		local Success, BoundingCFrame, BoundingSize = pcall(function()
			return Character:GetBoundingBox()
		end)

		if not Success or not BoundingCFrame or not BoundingSize then
			return nil
		end

		local HalfSize = BoundingSize * 0.5
		local ViewportSize = Camera.ViewportSize
		local MinX = math.huge
		local MinY = math.huge
		local MaxX = -math.huge
		local MaxY = -math.huge
		local AnyVisible = false
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

					if ScreenPoint.Z <= 0 then
						return nil
					end

					MinX = math.min(MinX, ScreenPoint.X)
					MinY = math.min(MinY, ScreenPoint.Y)
					MaxX = math.max(MaxX, ScreenPoint.X)
					MaxY = math.max(MaxY, ScreenPoint.Y)
					AnyVisible = AnyVisible or OnScreen
				end
			end
		end

		if not AnyVisible then
			return nil
		end

		if MaxX < 0 or MinX > ViewportSize.X or MaxY < 0 or MinY > ViewportSize.Y then
			return nil
		end

		local Width = MaxX - MinX
		local Height = MaxY - MinY

		if Width < 2 or Height < 2 then
			return nil
		end

		return MinX, MinY, MaxX, MaxY
	end

	function ESP:GetGuiRoot()
		if self.GuiRoot and self.GuiRoot.Parent then
			return self.GuiRoot
		end

		local ScreenGui = Instance.new("ScreenGui")
		ScreenGui.Name = "FatalityESP"
		ScreenGui.ResetOnSpawn = false
		ScreenGui.IgnoreGuiInset = true
		ScreenGui.DisplayOrder = 999
		ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		ScreenGui.Parent = getGuiParent()

		self.GuiRoot = ScreenGui

		return ScreenGui
	end

	function ESP:CreateDrawingEntry(Player)
		local Outline = Drawing.new("Square")
		Outline.Visible = false
		Outline.Color = Color3.fromRGB(0, 0, 0)
		Outline.Thickness = 3
		Outline.Filled = false
		Outline.Transparency = 1

		local Box = Drawing.new("Square")
		Box.Visible = false
		Box.Color = Color3.fromRGB(245, 49, 116)
		Box.Thickness = 1
		Box.Filled = false
		Box.Transparency = 1

		local Name = Drawing.new("Text")
		Name.Visible = false
		Name.Center = true
		Name.Outline = true
		Name.Size = 13
		Name.Font = 2
		Name.Color = Color3.fromRGB(255, 255, 255)
		Name.Transparency = 1

		local Health = Drawing.new("Text")
		Health.Visible = false
		Health.Center = true
		Health.Outline = true
		Health.Size = 13
		Health.Font = 2
		Health.Color = Color3.fromRGB(110, 255, 140)
		Health.Transparency = 1

		self.Entries[Player] = {
			Mode = "drawing",
			Outline = Outline,
			Box = Box,
			Name = Name,
			Health = Health
		}

		return self.Entries[Player]
	end

	function ESP:CreateInstanceEntry(Player)
		local Highlight = Instance.new("Highlight")
		Highlight.Name = "FatalityESPHighlight"
		Highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		Highlight.FillTransparency = 1
		Highlight.OutlineTransparency = 0
		Highlight.OutlineColor = Color3.fromRGB(245, 49, 116)
		Highlight.Enabled = false
		Highlight.Parent = workspace

		local Billboard = Instance.new("BillboardGui")
		Billboard.Name = "FatalityESPBillboard"
		Billboard.AlwaysOnTop = true
		Billboard.LightInfluence = 0
		Billboard.ResetOnSpawn = false
		Billboard.Size = UDim2.new(0, 180, 0, 36)
		Billboard.StudsOffset = Vector3.new(0, 3.25, 0)
		Billboard.Enabled = false
		Billboard.Parent = self:GetGuiRoot()

		local Name = Instance.new("TextLabel")
		Name.Name = "Name"
		Name.BackgroundTransparency = 1
		Name.Size = UDim2.new(1, 0, 0, 18)
		Name.Position = UDim2.new(0, 0, 0, 0)
		Name.Font = Enum.Font.GothamSemibold
		Name.TextColor3 = Color3.fromRGB(255, 255, 255)
		Name.TextSize = 13
		Name.TextStrokeTransparency = 0.35
		Name.TextXAlignment = Enum.TextXAlignment.Center
		Name.Visible = false
		Name.Parent = Billboard

		local Health = Instance.new("TextLabel")
		Health.Name = "Health"
		Health.BackgroundTransparency = 1
		Health.Size = UDim2.new(1, 0, 0, 18)
		Health.Position = UDim2.new(0, 0, 0, 16)
		Health.Font = Enum.Font.GothamSemibold
		Health.TextColor3 = Color3.fromRGB(110, 255, 140)
		Health.TextSize = 13
		Health.TextStrokeTransparency = 0.35
		Health.TextXAlignment = Enum.TextXAlignment.Center
		Health.Visible = false
		Health.Parent = Billboard

		self.Entries[Player] = {
			Mode = "instance",
			Highlight = Highlight,
			Billboard = Billboard,
			Name = Name,
			Health = Health
		}

		return self.Entries[Player]
	end

	function ESP:GetEntry(Player)
		local Entry = self.Entries[Player]

		if Entry then
			return Entry
		end

		if self.UseDrawing then
			local Success, Result = pcall(self.CreateDrawingEntry, self, Player)

			if Success and Result then
				return Result
			end

			self.UseDrawing = false
			self:Clear()

			if Notification and not self.FallbackNotified then
				self.FallbackNotified = true
				Notification:Notify({
					Title = "ESP",
					Content = "Drawing failed, switching to Highlight ESP.",
					Duration = 4,
					Icon = "info"
				})
			end
		end

		return self:CreateInstanceEntry(Player)
	end

	function ESP:HideEntry(Player)
		local Entry = self.Entries[Player]

		if not Entry then
			return
		end

		if Entry.Mode == "drawing" then
			hideDrawing(Entry.Outline)
			hideDrawing(Entry.Box)
			hideDrawing(Entry.Name)
			hideDrawing(Entry.Health)
			return
		end

		hideInstance(Entry.Highlight)
		hideInstance(Entry.Billboard)
		hideInstance(Entry.Name)
		hideInstance(Entry.Health)
	end

	function ESP:RemoveEntry(Player)
		local Entry = self.Entries[Player]

		if not Entry then
			return
		end

		if Entry.Mode == "drawing" then
			Entry.Outline:Remove()
			Entry.Box:Remove()
			Entry.Name:Remove()
			Entry.Health:Remove()
		else
			if Entry.Highlight then
				Entry.Highlight:Destroy()
			end

			if Entry.Billboard then
				Entry.Billboard:Destroy()
			end
		end

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

	function ESP:UpdateDrawingEntry(Player, Humanoid, MinX, MinY, MaxX, MaxY)
		local Width = math.max(MaxX - MinX, 2)
		local Height = math.max(MaxY - MinY, 2)
		local Entry = self:GetEntry(Player)

		Entry.Outline.Size = Vector2.new(Width, Height)
		Entry.Outline.Position = Vector2.new(MinX, MinY)
		Entry.Outline.Visible = true

		Entry.Box.Size = Vector2.new(Width, Height)
		Entry.Box.Position = Vector2.new(MinX, MinY)
		Entry.Box.Visible = true

		if self.Settings.ShowName then
			Entry.Name.Text = Player.DisplayName or Player.Name
			Entry.Name.Position = Vector2.new(MinX + (Width * 0.5), MinY - 14)
			Entry.Name.Visible = true
		else
			hideDrawing(Entry.Name)
		end

		if self.Settings.ShowHealth then
			Entry.Health.Text = string.format(
				"%d / %d",
				math.floor(Humanoid.Health + 0.5),
				math.floor(Humanoid.MaxHealth + 0.5)
			)
			Entry.Health.Color = getHealthColor(Humanoid.Health, Humanoid.MaxHealth)
			Entry.Health.Position = Vector2.new(MinX + (Width * 0.5), MaxY + 2)
			Entry.Health.Visible = true
		else
			hideDrawing(Entry.Health)
		end
	end

	function ESP:UpdateInstanceEntry(Player, Character, Humanoid, RootPart)
		local Entry = self:GetEntry(Player)
		local DisplayPart = Character:FindFirstChild("Head") or RootPart

		self:UpdateBillboardLayout(Entry)

		Entry.Highlight.Adornee = Character
		Entry.Highlight.Enabled = true
		Entry.Billboard.Adornee = DisplayPart
		Entry.Billboard.Enabled = self.Settings.ShowName or self.Settings.ShowHealth

		if self.Settings.ShowName then
			Entry.Name.Text = Player.DisplayName or Player.Name
			Entry.Name.Visible = true
		else
			hideInstance(Entry.Name)
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
			hideInstance(Entry.Health)
		end
	end

	function ESP:UpdatePlayer(Player)
		if Player == LocalPlayer then
			self:RemoveEntry(Player)
			return false
		end

		local Character = Player.Character
		local Humanoid = Character and Character:FindFirstChildOfClass("Humanoid")
		local RootPart = Character and Character:FindFirstChild("HumanoidRootPart")
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

		if self.UseDrawing then
			local MinX, MinY, MaxX, MaxY = getCharacterBounds(Character)

			if not MinX then
				self:HideEntry(Player)
				return false
			end

			self:UpdateDrawingEntry(Player, Humanoid, MinX, MinY, MaxX, MaxY)
			return true
		end

		self:UpdateInstanceEntry(Player, Character, Humanoid, RootPart)
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
			if not self.UseDrawing and Notification then
				Notification:Notify({
					Title = "ESP",
					Content = "Drawing unavailable, using Highlight ESP.",
					Duration = 4,
					Icon = "info"
				})
			end

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

		for Player, Entry in pairs(self.Entries) do
			if Entry.Mode == "drawing" then
				if not self.Settings.ShowName then
					hideDrawing(Entry.Name)
				end
			else
				self:UpdateBillboardLayout(Entry)

				if not self.Settings.ShowName then
					hideInstance(Entry.Name)
				elseif self.Enabled then
					local CurrentPlayer = Players:FindFirstChild(Player.Name)

					if CurrentPlayer then
						local Character = CurrentPlayer.Character
						local Humanoid = Character and Character:FindFirstChildOfClass("Humanoid")
						local RootPart = Character and Character:FindFirstChild("HumanoidRootPart")

						if Character and Humanoid and RootPart and Humanoid.Health > 0 then
							self:UpdateInstanceEntry(CurrentPlayer, Character, Humanoid, RootPart)
						end
					end
				end
			end
		end
	end

	function ESP:SetShowHealth(Value)
		self.Settings.ShowHealth = Value and true or false

		for Player, Entry in pairs(self.Entries) do
			if Entry.Mode == "drawing" then
				if not self.Settings.ShowHealth then
					hideDrawing(Entry.Health)
				end
			else
				self:UpdateBillboardLayout(Entry)

				if not self.Settings.ShowHealth then
					hideInstance(Entry.Health)
				elseif self.Enabled then
					local CurrentPlayer = Players:FindFirstChild(Player.Name)

					if CurrentPlayer then
						local Character = CurrentPlayer.Character
						local Humanoid = Character and Character:FindFirstChildOfClass("Humanoid")
						local RootPart = Character and Character:FindFirstChild("HumanoidRootPart")

						if Character and Humanoid and RootPart and Humanoid.Health > 0 then
							self:UpdateInstanceEntry(CurrentPlayer, Character, Humanoid, RootPart)
						end
					end
				end
			end
		end
	end

	return ESP
end
