return function(Config)
	local Window = Config.Window
	local Fatality = Config.Fatality
	local StatsFeature = Config.StatsFeature

	local RunService = game:GetService("RunService")

	local Controller = {
		Connection = nil,
		Elapsed = 0
	}

	local function createPreviewText(Parent)
		local Label = Instance.new("TextLabel")

		Label.Name = "StatsText"
		Label.Parent = Parent
		Label.BackgroundTransparency = 1
		Label.Position = UDim2.new(0, 6, 0, 4)
		Label.Size = UDim2.new(1, -12, 1, -8)
		Label.FontFace = Fatality.FontSemiBold
		Label.Text = ""
		Label.TextColor3 = Color3.fromRGB(255, 255, 255)
		Label.TextSize = 12
		Label.TextTransparency = 0
		Label.TextStrokeTransparency = 0.9
		Label.TextWrapped = false
		Label.TextXAlignment = Enum.TextXAlignment.Left
		Label.TextYAlignment = Enum.TextYAlignment.Top
		Label.ZIndex = 21

		return Label
	end

	local function updateText(Label, Lines)
		Label.Text = table.concat(Lines, "\n")
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

	local CharacterText = createPreviewText(CharacterPreview)
	local DetailsText = createPreviewText(DetailsPreview)

	local function refresh()
		local LeftLines, RightLines = StatsFeature:GetPanels()

		updateText(CharacterText, LeftLines)
		updateText(DetailsText, RightLines)
	end

	refresh()

	Controller.Connection = RunService.Heartbeat:Connect(function(DeltaTime)
		Controller.Elapsed = Controller.Elapsed + DeltaTime

		if Controller.Elapsed < 0.25 then
			return
		end

		Controller.Elapsed = 0
		refresh()
	end)

	function Controller:Destroy()
		if self.Connection then
			self.Connection:Disconnect()
			self.Connection = nil
		end
	end

	return Controller
end
