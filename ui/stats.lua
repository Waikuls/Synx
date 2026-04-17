return function(Config)
	local Players = game:GetService("Players")
	local Window = Config.Window
	local Fatality = Config.Fatality
	local StatsFeature = Config.StatsFeature

	local RunService = game:GetService("RunService")

	local Controller = {
		RefreshConnection = nil,
		PlayerAddedConnection = nil,
		PlayerRemovingConnection = nil,
		Elapsed = 0
	}

	local function createPreviewText(Parent)
		local ScrollFrame = Instance.new("ScrollingFrame")
		local Label = Instance.new("TextLabel")

		ScrollFrame.Name = "StatsScroll"
		ScrollFrame.Parent = Parent
		ScrollFrame.Active = true
		ScrollFrame.BackgroundTransparency = 1
		ScrollFrame.BorderSizePixel = 0
		ScrollFrame.Position = UDim2.new(0, 6, 0, 6)
		ScrollFrame.Size = UDim2.new(1, -12, 1, -12)
		ScrollFrame.CanvasSize = UDim2.new()
		ScrollFrame.ScrollBarImageColor3 = Fatality.Colors.Main
		ScrollFrame.ScrollBarThickness = 3
		ScrollFrame.ScrollingDirection = Enum.ScrollingDirection.Y
		ScrollFrame.AutomaticCanvasSize = Enum.AutomaticSize.None
		ScrollFrame.ZIndex = 21

		Label.Name = "StatsText"
		Label.Parent = ScrollFrame
		Label.BackgroundTransparency = 1
		Label.Position = UDim2.new()
		Label.Size = UDim2.new(1, -4, 0, 0)
		Label.AutomaticSize = Enum.AutomaticSize.Y
		Label.FontFace = Fatality.FontSemiBold
		Label.Text = ""
		Label.TextColor3 = Color3.fromRGB(255, 255, 255)
		Label.TextSize = 14
		Label.TextTransparency = 0
		Label.TextStrokeTransparency = 0.9
		Label.TextWrapped = false
		Label.LineHeight = 1.1
		Label.TextXAlignment = Enum.TextXAlignment.Left
		Label.TextYAlignment = Enum.TextYAlignment.Top
		Label.ZIndex = 21

		local function updateCanvas()
			local ContentHeight = math.max(Label.TextBounds.Y + 8, ScrollFrame.AbsoluteSize.Y)

			ScrollFrame.CanvasSize = UDim2.fromOffset(0, ContentHeight)
		end

		Label:GetPropertyChangedSignal("TextBounds"):Connect(updateCanvas)
		ScrollFrame:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateCanvas)
		updateCanvas()

		return {
			ScrollFrame = ScrollFrame,
			Label = Label,
			UpdateCanvas = updateCanvas
		}
	end

	local function updateText(View, Lines)
		View.Label.Text = table.concat(Lines, "\n\n")
		View.UpdateCanvas()
	end

	local function syncPlayerDropdown(Dropdown)
		Dropdown:SetData(StatsFeature:GetPlayerOptions())
	end

	local StatsMenu = Window:AddMenu({
		Name = "STATS",
		Icon = "code"
	})

	local CharacterPreview = StatsMenu:AddPreview({
		Name = "CHARACTER",
		Position = "left",
		Height = 315
	})

	local DetailsPreview = StatsMenu:AddPreview({
		Name = "DETAILS",
		Position = "center",
		Height = 315
	})

	local Setting = StatsMenu:AddSection({
		Name = "SETTING",
		Position = "right"
	})

	local CharacterText = createPreviewText(CharacterPreview)
	local DetailsText = createPreviewText(DetailsPreview)
	local refresh

	refresh = function()
		local LeftLines, RightLines = StatsFeature:GetPanels()

		updateText(CharacterText, LeftLines)
		updateText(DetailsText, RightLines)
	end

	local SelectedPlayerDropdown = Setting:AddDropdown({
		Name = "Player",
		Default = StatsFeature:GetTargetPlayerName(),
		Values = StatsFeature:GetPlayerOptions(),
		Callback = function(Value)
			StatsFeature:SetTargetPlayer(Value)
			refresh()
		end
	})

	refresh()
	syncPlayerDropdown(SelectedPlayerDropdown)

	Controller.RefreshConnection = RunService.Heartbeat:Connect(function(DeltaTime)
		Controller.Elapsed = Controller.Elapsed + DeltaTime

		if Controller.Elapsed < 0.25 then
			return
		end

		Controller.Elapsed = 0
		refresh()
	end)

	Controller.PlayerAddedConnection = Players.PlayerAdded:Connect(function()
		syncPlayerDropdown(SelectedPlayerDropdown)
	end)

	Controller.PlayerRemovingConnection = Players.PlayerRemoving:Connect(function(Player)
		local WasViewingPlayer = StatsFeature:GetTargetPlayerName() == Player.Name

		syncPlayerDropdown(SelectedPlayerDropdown)

		if WasViewingPlayer then
			local FallbackPlayer = StatsFeature:SetTargetPlayer(nil)

			SelectedPlayerDropdown:SetValue(FallbackPlayer.Name)
		end
	end)

	function Controller:Destroy()
		if self.RefreshConnection then
			self.RefreshConnection:Disconnect()
			self.RefreshConnection = nil
		end

		if self.PlayerAddedConnection then
			self.PlayerAddedConnection:Disconnect()
			self.PlayerAddedConnection = nil
		end

		if self.PlayerRemovingConnection then
			self.PlayerRemovingConnection:Disconnect()
			self.PlayerRemovingConnection = nil
		end
	end

	return Controller
end
