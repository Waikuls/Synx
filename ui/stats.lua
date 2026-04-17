return function(Config)
	local Window = Config.Window
	local Fatality = Config.Fatality
	local StatsFeature = Config.StatsFeature

	local RunService = game:GetService("RunService")

	local Controller = {
		Connection = nil
	}

	local function createPreviewColumn(Parent)
		local Container = Instance.new("Frame")
		local Layout = Instance.new("UIListLayout")
		local Padding = Instance.new("UIPadding")
		local Labels = {}

		Container.Name = "StatsContainer"
		Container.Parent = Parent
		Container.BackgroundTransparency = 1
		Container.ClipsDescendants = true
		Container.Size = UDim2.new(1, 0, 1, 0)
		Container.ZIndex = 20

		Padding.Parent = Container
		Padding.PaddingLeft = UDim.new(0, 6)
		Padding.PaddingRight = UDim.new(0, 6)
		Padding.PaddingTop = UDim.new(0, 4)
		Padding.PaddingBottom = UDim.new(0, 4)

		Layout.Parent = Container
		Layout.SortOrder = Enum.SortOrder.LayoutOrder
		Layout.Padding = UDim.new(0, 2)

		for Index = 1, 16 do
			local Label = Instance.new("TextLabel")

			Label.Name = string.format("Line%d", Index)
			Label.Parent = Container
			Label.BackgroundTransparency = 1
			Label.Size = UDim2.new(1, 0, 0, 16)
			Label.FontFace = Fatality.FontSemiBold
			Label.Text = ""
			Label.TextColor3 = Color3.fromRGB(255, 255, 255)
			Label.TextSize = 12
			Label.TextTransparency = 0
			Label.TextStrokeTransparency = 0.9
			Label.TextWrapped = false
			Label.TextXAlignment = Enum.TextXAlignment.Left
			Label.ZIndex = 21

			Labels[Index] = Label
		end

		return Labels
	end

	local function updateLabels(Labels, Lines)
		for Index, Label in ipairs(Labels) do
			Label.Text = Lines[Index] or ""
		end
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

	local CharacterLabels = createPreviewColumn(CharacterPreview)
	local DetailsLabels = createPreviewColumn(DetailsPreview)

	local function refresh()
		local LeftLines, RightLines = StatsFeature:GetPanels()

		updateLabels(CharacterLabels, LeftLines)
		updateLabels(DetailsLabels, RightLines)
	end

	refresh()

	Controller.Connection = RunService.Heartbeat:Connect(refresh)

	function Controller:Destroy()
		if self.Connection then
			self.Connection:Disconnect()
			self.Connection = nil
		end
	end

	return Controller
end
