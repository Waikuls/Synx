return function(Config)
	local Notification = Config.Notification
	local Players = game:GetService("Players")
	local RunService = game:GetService("RunService")
	local Camera = workspace.CurrentCamera
	local LocalPlayer = Players.LocalPlayer

	local ESP = {
		Enabled = false,
		Boxes = {},
		Connection = nil,
		Settings = {
			DistanceLimit = 1500,
			ShowName = true,
			ShowHealth = true
		}
	}

	local function getLocalRootPart()
		local Character = LocalPlayer.Character

		if not Character then
			return nil
		end

		return Character:FindFirstChild("HumanoidRootPart")
	end

	local function hideDrawing(DrawingObject)
		if DrawingObject then
			DrawingObject.Visible = false
		end
	end

	local function getCharacterBounds(Character, Humanoid, RootPart)
		local Head = Character:FindFirstChild("Head")
		local ViewportSize = Camera.ViewportSize

		if not Head then
			return nil
		end

		local TopWorld = Head.Position + Vector3.new(0, 0.6, 0)
		local BottomWorld = RootPart.Position - Vector3.new(0, Humanoid.HipHeight + 2.6, 0)

		local TopPoint, TopOnScreen = Camera:WorldToViewportPoint(TopWorld)
		local BottomPoint, BottomOnScreen = Camera:WorldToViewportPoint(BottomWorld)
		local RootPoint, RootOnScreen = Camera:WorldToViewportPoint(RootPart.Position)

		if TopPoint.Z <= 0 or BottomPoint.Z <= 0 or RootPoint.Z <= 0 then
			return nil
		end

		if not RootOnScreen and not TopOnScreen and not BottomOnScreen then
			return nil
		end

		local Height = math.abs(BottomPoint.Y - TopPoint.Y)

		if Height < 6 or Height > ViewportSize.Y * 0.9 then
			return nil
		end

		local Width = math.max(Height * 0.6, 4)
		local MinX = RootPoint.X - (Width * 0.5)
		local MinY = math.min(TopPoint.Y, BottomPoint.Y)
		local MaxX = RootPoint.X + (Width * 0.5)
		local MaxY = math.max(TopPoint.Y, BottomPoint.Y)

		if MaxX < 0 or MinX > ViewportSize.X or MaxY < 0 or MinY > ViewportSize.Y then
			return nil
		end

		return MinX, MinY, MaxX, MaxY
	end

	function ESP:CreateBox(Player)
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

		self.Boxes[Player] = {
			Outline = Outline,
			Box = Box,
			Name = Name,
			Health = Health
		}

		return self.Boxes[Player]
	end

	function ESP:HideBox(Player)
		local Drawings = self.Boxes[Player]

		if not Drawings then
			return
		end

		hideDrawing(Drawings.Outline)
		hideDrawing(Drawings.Box)
		hideDrawing(Drawings.Name)
		hideDrawing(Drawings.Health)
	end

	function ESP:RemoveBox(Player)
		local Drawings = self.Boxes[Player]

		if not Drawings then
			return
		end

		Drawings.Outline:Remove()
		Drawings.Box:Remove()
		Drawings.Name:Remove()
		Drawings.Health:Remove()
		self.Boxes[Player] = nil
	end

	function ESP:Clear()
		for Player in pairs(self.Boxes) do
			self:RemoveBox(Player)
		end
	end

	function ESP:UpdatePlayer(Player)
		if Player == LocalPlayer then
			self:RemoveBox(Player)
			return false
		end

		local Character = Player.Character
		local Humanoid = Character and Character:FindFirstChildOfClass("Humanoid")
		local RootPart = Character and Character:FindFirstChild("HumanoidRootPart")
		local LocalRootPart = getLocalRootPart()
		local Distance

		if not Character or not Humanoid or not RootPart or Humanoid.Health <= 0 then
			self:HideBox(Player)
			return false
		end

		if LocalRootPart then
			Distance = (LocalRootPart.Position - RootPart.Position).Magnitude

			if Distance > self.Settings.DistanceLimit then
				self:HideBox(Player)
				return false
			end
		end

		local MinX, MinY, MaxX, MaxY = getCharacterBounds(Character, Humanoid, RootPart)

		if not MinX then
			self:HideBox(Player)
			return false
		end

		local Width = math.max(MaxX - MinX, 2)
		local Height = math.max(MaxY - MinY, 2)
		local Drawings = self.Boxes[Player] or self:CreateBox(Player)

		Drawings.Outline.Size = Vector2.new(Width, Height)
		Drawings.Outline.Position = Vector2.new(MinX, MinY)
		Drawings.Outline.Visible = true

		Drawings.Box.Size = Vector2.new(Width, Height)
		Drawings.Box.Position = Vector2.new(MinX, MinY)
		Drawings.Box.Visible = true

		local InfoParts = {}

		if self.Settings.ShowName then
			table.insert(InfoParts, Player.DisplayName)
		end

		if self.Settings.ShowHealth then
			table.insert(
				InfoParts,
				string.format(
					"[%d/%d]",
					math.floor(Humanoid.Health + 0.5),
					math.floor(Humanoid.MaxHealth + 0.5)
				)
			)
		end

		if Distance then
			table.insert(InfoParts, string.format("[%d studs]", math.floor(Distance + 0.5)))
		end

		if #InfoParts > 0 then
			Drawings.Name.Text = table.concat(InfoParts, " ")
			Drawings.Name.Position = Vector2.new(MinX + (Width * 0.5), MinY - 14)
			Drawings.Name.Visible = true
		else
			hideDrawing(Drawings.Name)
		end

		hideDrawing(Drawings.Health)

		return true
	end

	function ESP:Update()
		Camera = workspace.CurrentCamera

		local SeenPlayers = {}

		for _, Player in ipairs(Players:GetPlayers()) do
			if self:UpdatePlayer(Player) then
				SeenPlayers[Player] = true
			end
		end

		for Player in pairs(self.Boxes) do
			if not Players:FindFirstChild(Player.Name) then
				self:RemoveBox(Player)
			elseif not SeenPlayers[Player] then
				self:HideBox(Player)
			end
		end
	end

	function ESP:SetEnabled(State)
		if State and not Drawing then
			if Notification then
				Notification:Notify({
					Title = "ESP",
					Content = "Your executor does not support Drawing.",
					Duration = 5,
					Icon = "info"
				})
			end

			return false
		end

		if self.Enabled == State then
			return State
		end

		self.Enabled = State

		if self.Connection then
			self.Connection:Disconnect()
			self.Connection = nil
		end

		if State then
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
	end

	function ESP:SetDistanceLimit(Value)
		self.Settings.DistanceLimit = math.max(Value or self.Settings.DistanceLimit, 1)
	end

	function ESP:SetShowName(Value)
		self.Settings.ShowName = Value and true or false

		if not self.Settings.ShowName then
			for _, Drawings in pairs(self.Boxes) do
				hideDrawing(Drawings.Name)
			end
		end
	end

	function ESP:SetShowHealth(Value)
		self.Settings.ShowHealth = Value and true or false

		if not self.Settings.ShowHealth then
			for _, Drawings in pairs(self.Boxes) do
				hideDrawing(Drawings.Health)
			end
		end
	end

	return ESP
end
