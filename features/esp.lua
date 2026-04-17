return function(Config)
	local Notification = Config.Notification
	local Players = game:GetService("Players")
	local RunService = game:GetService("RunService")
	local Camera = workspace.CurrentCamera
	local LocalPlayer = Players.LocalPlayer

	local ESP = {
		Enabled = false,
		Boxes = {},
		Connection = nil
	}

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

		self.Boxes[Player] = {
			Outline = Outline,
			Box = Box
		}

		return self.Boxes[Player]
	end

	function ESP:HideBox(Player)
		local Drawings = self.Boxes[Player]

		if not Drawings then
			return
		end

		Drawings.Outline.Visible = false
		Drawings.Box.Visible = false
	end

	function ESP:RemoveBox(Player)
		local Drawings = self.Boxes[Player]

		if not Drawings then
			return
		end

		Drawings.Outline:Remove()
		Drawings.Box:Remove()
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

		if not Character or not Humanoid or not RootPart or Humanoid.Health <= 0 then
			self:HideBox(Player)
			return false
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

	return ESP
end
