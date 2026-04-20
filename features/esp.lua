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
			ShowHealth = true,
			ShowDistance = true
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

	local function getTorso(Character, RootPart)
		if not Character then
			return RootPart
		end

		return Character:FindFirstChild("UpperTorso")
			or Character:FindFirstChild("Torso")
			or RootPart
	end

	local function getHead(Character, RootPart)
		if not Character then
			return RootPart
		end

		return Character:FindFirstChild("Head") or RootPart
	end

	local function getHorizontalRadius(Character, RootPart)
		local Torso = getTorso(Character, RootPart)
		local Radius = math.max((RootPart and RootPart.Size.X or 2) * 0.75, 1.35)

		if Torso then
			Radius = math.max(Radius, Torso.Size.X * 0.72)
		end

		return math.clamp(Radius, 1.35, 3.75)
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

	local function getCharacterBounds(Character, Humanoid, RootPart)
		local Camera = getCurrentCamera()
		local Head = getHead(Character, RootPart)
		local Radius = getHorizontalRadius(Character, RootPart)

		if not Camera or not RootPart or not Head then
			return nil
		end

		local ViewportSize = Camera.ViewportSize
		local TopOffset = Head == RootPart and math.max(RootPart.Size.Y * 0.9, 2.4) or ((Head.Size.Y * 0.5) + 0.15)
		local BottomOffset = Humanoid and math.max(Humanoid.HipHeight + 2.6, 2.8) or math.max(RootPart.Size.Y * 1.5, 3)
		local TopWorld = Head.Position + Vector3.new(0, TopOffset, 0)
		local BottomWorld = RootPart.Position - Vector3.new(0, BottomOffset, 0)
		local LeftWorld = RootPart.Position - (Camera.CFrame.RightVector * Radius)
		local RightWorld = RootPart.Position + (Camera.CFrame.RightVector * Radius)
		local TopPoint, TopOnScreen = Camera:WorldToViewportPoint(TopWorld)
		local BottomPoint, BottomOnScreen = Camera:WorldToViewportPoint(BottomWorld)
		local RootPoint, RootOnScreen = Camera:WorldToViewportPoint(RootPart.Position)
		local LeftPoint, LeftOnScreen = Camera:WorldToViewportPoint(LeftWorld)
		local RightPoint, RightOnScreen = Camera:WorldToViewportPoint(RightWorld)

		if TopPoint.Z <= 0 or BottomPoint.Z <= 0 or RootPoint.Z <= 0 or LeftPoint.Z <= 0 or RightPoint.Z <= 0 then
			return nil
		end

		if not TopOnScreen and not BottomOnScreen and not RootOnScreen and not LeftOnScreen and not RightOnScreen then
			return nil
		end

		local Height = math.abs(BottomPoint.Y - TopPoint.Y)

		if Height < 8 or Height > (ViewportSize.Y * 0.9) then
			return nil
		end

		local MinX = math.min(LeftPoint.X, RightPoint.X)
		local MinY = math.min(TopPoint.Y, BottomPoint.Y)
		local MaxX = math.max(LeftPoint.X, RightPoint.X)
		local MaxY = math.max(TopPoint.Y, BottomPoint.Y)

		if MaxX < -24 or MinX > ViewportSize.X + 24 or MaxY < -24 or MinY > ViewportSize.Y + 24 then
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

	local function createLine(Parent, Name, Color, ZIndex)
		local Line = Instance.new("Frame")
		Line.Name = Name
		Line.BackgroundColor3 = Color
		Line.BorderSizePixel = 0
		Line.ZIndex = ZIndex
		Line.Parent = Parent

		return Line
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

		local OutlineTop = createLine(Container, "OutlineTop", Color3.fromRGB(0, 0, 0), 500)
		local OutlineBottom = createLine(Container, "OutlineBottom", Color3.fromRGB(0, 0, 0), 500)
		local OutlineLeft = createLine(Container, "OutlineLeft", Color3.fromRGB(0, 0, 0), 500)
		local OutlineRight = createLine(Container, "OutlineRight", Color3.fromRGB(0, 0, 0), 500)

		local BoxTop = createLine(Container, "BoxTop", Theme.Main, 501)
		local BoxBottom = createLine(Container, "BoxBottom", Theme.Main, 501)
		local BoxLeft = createLine(Container, "BoxLeft", Theme.Main, 501)
		local BoxRight = createLine(Container, "BoxRight", Theme.Main, 501)

		local InfoLabel = Instance.new("TextLabel")
		InfoLabel.Name = "InfoLabel"
		InfoLabel.AnchorPoint = Vector2.new(0.5, 1)
		InfoLabel.BackgroundTransparency = 1
		InfoLabel.BorderSizePixel = 0
		InfoLabel.Position = UDim2.new(0.5, 0, 0, -4)
		InfoLabel.Size = UDim2.new(0, 120, 0, 18)
		InfoLabel.Font = Enum.Font.GothamSemibold
		InfoLabel.RichText = true
		InfoLabel.Text = ""
		InfoLabel.TextColor3 = Theme.Text
		InfoLabel.TextSize = 13
		InfoLabel.TextStrokeColor3 = Theme.Black
		InfoLabel.TextStrokeTransparency = 0.35
		InfoLabel.TextWrapped = false
		InfoLabel.TextXAlignment = Enum.TextXAlignment.Center
		InfoLabel.Visible = false
		InfoLabel.ZIndex = 503
		InfoLabel.Parent = Container

		self.Entries[Player] = {
			Container = Container,
			OutlineTop = OutlineTop,
			OutlineBottom = OutlineBottom,
			OutlineLeft = OutlineLeft,
			OutlineRight = OutlineRight,
			BoxTop = BoxTop,
			BoxBottom = BoxBottom,
			BoxLeft = BoxLeft,
			BoxRight = BoxRight,
			InfoLabel = InfoLabel,
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
		Entry.InfoLabel.Visible = false
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
		local NameText = self.Settings.ShowName and (Player.DisplayName or Player.Name) or nil
		local HealthText = nil
		local DistanceText = self.Settings.ShowDistance and Distance and string.format("%d studs", math.floor(Distance + 0.5)) or nil

		if self.Settings.ShowHealth and Humanoid then
			HealthText = string.format(
				"%d/%d",
				math.floor(Humanoid.Health + 0.5),
				math.floor(Humanoid.MaxHealth + 0.5)
			)
		end
		local Width = math.max(math.floor((MaxX - MinX) + 0.5), 2)
		local Height = math.max(math.floor((MaxY - MinY) + 0.5), 2)

		local PlainInfo, RichInfo = buildInfoText(NameText, HealthText, DistanceText)

		Entry.Container.Position = UDim2.new(0, math.floor(MinX + 0.5), 0, math.floor(MinY + 0.5))
		Entry.Container.Size = UDim2.new(0, Width, 0, Height)
		Entry.Container.Visible = true

		Entry.OutlineTop.Position = UDim2.new(0, -1, 0, -1)
		Entry.OutlineTop.Size = UDim2.new(0, Width + 2, 0, 1)
		Entry.OutlineBottom.Position = UDim2.new(0, -1, 0, Height)
		Entry.OutlineBottom.Size = UDim2.new(0, Width + 2, 0, 1)
		Entry.OutlineLeft.Position = UDim2.new(0, -1, 0, -1)
		Entry.OutlineLeft.Size = UDim2.new(0, 1, 0, Height + 2)
		Entry.OutlineRight.Position = UDim2.new(0, Width, 0, -1)
		Entry.OutlineRight.Size = UDim2.new(0, 1, 0, Height + 2)

		Entry.BoxTop.Position = UDim2.new(0, 0, 0, 0)
		Entry.BoxTop.Size = UDim2.new(0, Width, 0, 1)
		Entry.BoxBottom.Position = UDim2.new(0, 0, 0, Height - 1)
		Entry.BoxBottom.Size = UDim2.new(0, Width, 0, 1)
		Entry.BoxLeft.Position = UDim2.new(0, 0, 0, 0)
		Entry.BoxLeft.Size = UDim2.new(0, 1, 0, Height)
		Entry.BoxRight.Position = UDim2.new(0, Width - 1, 0, 0)
		Entry.BoxRight.Size = UDim2.new(0, 1, 0, Height)

		if RichInfo ~= "" then
			local TextBounds = TextService:GetTextSize(
				PlainInfo,
				13,
				Enum.Font.GothamSemibold,
				Vector2.new(1000, 18)
			)

			Entry.InfoLabel.Text = RichInfo
			Entry.InfoLabel.Size = UDim2.new(0, math.max(TextBounds.X + 8, 48), 0, 18)
			Entry.InfoLabel.Visible = true
		else
			Entry.InfoLabel.Text = ""
			Entry.InfoLabel.Visible = false
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

		local MinX, MinY, MaxX, MaxY = getCharacterBounds(Character, Humanoid, RootPart)

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

	function ESP:SetShowDistance(Value)
		self.Settings.ShowDistance = Value and true or false
	end

	return ESP
end
