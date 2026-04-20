return function(Config)
	local Players = game:GetService("Players")
	local RunService = game:GetService("RunService")
	local CoreGui = game:GetService("CoreGui")
	local TextService = game:GetService("TextService")
	local LocalPlayer = Players.LocalPlayer

	local Theme = {
		Main = Color3.fromRGB(255, 106, 133),
		Black = Color3.fromRGB(16, 16, 16),
		Border = Color3.fromRGB(29, 29, 29),
		Text = Color3.fromRGB(255, 255, 255),
		Muted = Color3.fromRGB(170, 170, 170)
	}

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

	local function colorToHex(Color)
		return string.format(
			"%02X%02X%02X",
			math.floor((Color.R * 255) + 0.5),
			math.floor((Color.G * 255) + 0.5),
			math.floor((Color.B * 255) + 0.5)
		)
	end

	local MainHex = colorToHex(Theme.Main)
	local TextHex = colorToHex(Theme.Text)
	local MutedHex = colorToHex(Theme.Muted)

	local function getGuiParent()
		if LocalPlayer then
			local PlayerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")

			if PlayerGui then
				return PlayerGui
			end
		end

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

	local function getHumanoid(Character)
		if not Character then
			return nil
		end

		return Character:FindFirstChildOfClass("Humanoid")
	end

	local function getLocalRootPart()
		return getCharacterRoot(LocalPlayer and LocalPlayer.Character)
	end

	local function escapeRichText(Text)
		Text = tostring(Text or "")
		Text = Text:gsub("&", "&amp;")
		Text = Text:gsub("<", "&lt;")
		Text = Text:gsub(">", "&gt;")

		return Text
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
			BoundingSize = RootPart.Size + Vector3.new(4, 5, 4)
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

	local function buildInfoText(NameText, HealthText, DistanceText)
		local PlainParts = {}
		local RichParts = {}

		if NameText and NameText ~= "" then
			table.insert(PlainParts, NameText)
			table.insert(RichParts, string.format('<font color="#%s">%s</font>', TextHex, escapeRichText(NameText)))
		end

		if HealthText and HealthText ~= "" then
			table.insert(PlainParts, "[" .. HealthText .. "]")
			table.insert(
				RichParts,
				string.format(
					'<font color="#%s">[</font><font color="#%s">%s</font><font color="#%s">]</font>',
					MutedHex,
					MainHex,
					escapeRichText(HealthText),
					MutedHex
				)
			)
		end

		if DistanceText and DistanceText ~= "" then
			table.insert(PlainParts, "[" .. DistanceText .. "]")
			table.insert(
				RichParts,
				string.format(
					'<font color="#%s">[</font><font color="#%s">%s</font><font color="#%s">]</font>',
					MutedHex,
					MainHex,
					escapeRichText(DistanceText),
					MutedHex
				)
			)
		end

		return table.concat(PlainParts, " "), table.concat(RichParts, " ")
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
		Container.ClipsDescendants = false
		Container.Visible = false
		Container.ZIndex = 500
		Container.Parent = self:GetGuiRoot()

		local Outline = Instance.new("Frame")
		Outline.Name = "Outline"
		Outline.BackgroundTransparency = 1
		Outline.BorderColor3 = Color3.fromRGB(0, 0, 0)
		Outline.BorderSizePixel = 1
		Outline.Position = UDim2.new(0, -1, 0, -1)
		Outline.Size = UDim2.new(1, 2, 1, 2)
		Outline.ZIndex = 500
		Outline.Parent = Container

		local Box = Instance.new("Frame")
		Box.Name = "Box"
		Box.BackgroundTransparency = 1
		Box.BorderColor3 = Theme.Main
		Box.BorderSizePixel = 1
		Box.Size = UDim2.new(1, 0, 1, 0)
		Box.ZIndex = 501
		Box.Parent = Container

		local InfoFrame = Instance.new("Frame")
		InfoFrame.Name = "InfoFrame"
		InfoFrame.AnchorPoint = Vector2.new(0.5, 1)
		InfoFrame.BackgroundColor3 = Theme.Black
		InfoFrame.BorderColor3 = Theme.Border
		InfoFrame.BorderSizePixel = 1
		InfoFrame.Position = UDim2.new(0.5, 0, 0, -6)
		InfoFrame.Size = UDim2.new(0, 120, 0, 18)
		InfoFrame.Visible = false
		InfoFrame.ZIndex = 502
		InfoFrame.Parent = Container

		local InfoLabel = Instance.new("TextLabel")
		InfoLabel.Name = "InfoLabel"
		InfoLabel.BackgroundTransparency = 1
		InfoLabel.BorderSizePixel = 0
		InfoLabel.Position = UDim2.new(0, 6, 0, 0)
		InfoLabel.Size = UDim2.new(1, -12, 1, 0)
		InfoLabel.Font = Enum.Font.GothamSemibold
		InfoLabel.RichText = true
		InfoLabel.Text = ""
		InfoLabel.TextColor3 = Theme.Text
		InfoLabel.TextSize = 13
		InfoLabel.TextStrokeTransparency = 0.5
		InfoLabel.TextWrapped = false
		InfoLabel.TextXAlignment = Enum.TextXAlignment.Center
		InfoLabel.ZIndex = 503
		InfoLabel.Parent = InfoFrame

		self.Entries[Player] = {
			Container = Container,
			InfoFrame = InfoFrame,
			InfoLabel = InfoLabel
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
		Entry.InfoFrame.Visible = false
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

	function ESP:UpdateEntry(Player, Humanoid, MinX, MinY, MaxX, MaxY, Distance)
		local Entry = self:GetEntry(Player)
		local Width = math.max(math.floor((MaxX - MinX) + 0.5), 2)
		local Height = math.max(math.floor((MaxY - MinY) + 0.5), 2)
		local NameText = self.Settings.ShowName and (Player.DisplayName or Player.Name) or nil
		local HealthText = nil
		local DistanceText = Distance and string.format("%d studs", math.floor(Distance + 0.5)) or nil

		if self.Settings.ShowHealth and Humanoid then
			HealthText = string.format(
				"%d/%d",
				math.floor(Humanoid.Health + 0.5),
				math.floor(Humanoid.MaxHealth + 0.5)
			)
		end

		local PlainInfo, RichInfo = buildInfoText(NameText, HealthText, DistanceText)

		Entry.Container.Position = UDim2.new(0, math.floor(MinX + 0.5), 0, math.floor(MinY + 0.5))
		Entry.Container.Size = UDim2.new(0, Width, 0, Height)
		Entry.Container.Visible = true

		if RichInfo ~= "" then
			local TextBounds = TextService:GetTextSize(
				PlainInfo,
				13,
				Enum.Font.GothamSemibold,
				Vector2.new(1000, 18)
			)

			Entry.InfoLabel.Text = RichInfo
			Entry.InfoFrame.Size = UDim2.new(0, math.max(TextBounds.X + 18, 76), 0, 18)
			Entry.InfoFrame.Visible = true
		else
			Entry.InfoLabel.Text = ""
			Entry.InfoFrame.Visible = false
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
		local Distance = nil

		if not Character or not RootPart then
			self:HideEntry(Player)
			return false
		end

		if Humanoid and Humanoid.Health <= 0 then
			self:HideEntry(Player)
			return false
		end

		if LocalRootPart then
			Distance = (LocalRootPart.Position - RootPart.Position).Magnitude

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

		self:UpdateEntry(Player, Humanoid, MinX, MinY, MaxX, MaxY, Distance)

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
	end

	function ESP:SetShowHealth(Value)
		self.Settings.ShowHealth = Value and true or false
	end

	return ESP
end
