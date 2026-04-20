return function(Config)
	local RunService = game:GetService("RunService")
	local UserInputService = game:GetService("UserInputService")
	local ContextActionService = game:GetService("ContextActionService")
	local Notification = Config and Config.Notification
	local BlockedControls = {
		Enum.KeyCode.W,
		Enum.KeyCode.A,
		Enum.KeyCode.S,
		Enum.KeyCode.D,
		Enum.KeyCode.Q,
		Enum.KeyCode.E,
		Enum.KeyCode.Space,
		Enum.KeyCode.LeftShift,
		Enum.KeyCode.RightShift,
		Enum.KeyCode.LeftControl,
		Enum.KeyCode.RightControl
	}
	local BlockActionName = "KELVFreecamBlock"

	local FreecamFeature = {
		Enabled = false,
		Connections = {},
		MoveState = {
			Forward = 0,
			Right = 0,
			Up = 0,
			Fast = false,
			Slow = false
		},
		Looking = false,
		Position = nil,
		Yaw = 0,
		Pitch = 0,
		Speed = 64,
		FastMultiplier = 2.4,
		SlowMultiplier = 0.4,
		MouseSensitivity = 0.0024,
		SavedCameraState = nil,
		SavedMouseBehavior = nil,
		SavedMouseIconEnabled = nil,
		ControlsBound = false
	}

	local function getCurrentCamera()
		return workspace.CurrentCamera
	end

	local function clampPitch(Pitch)
		return math.clamp(Pitch, math.rad(-89), math.rad(89))
	end

	local function getLookVector(Yaw, Pitch)
		return Vector3.new(
			math.sin(Yaw) * math.cos(Pitch),
			math.sin(Pitch),
			-math.cos(Yaw) * math.cos(Pitch)
		)
	end

	local function resetMoveState()
		FreecamFeature.MoveState.Forward = 0
		FreecamFeature.MoveState.Right = 0
		FreecamFeature.MoveState.Up = 0
		FreecamFeature.MoveState.Fast = false
		FreecamFeature.MoveState.Slow = false
	end

	local function refreshMoveState()
		local MoveState = FreecamFeature.MoveState
		local Forward = 0
		local Right = 0
		local Up = 0

		if UserInputService:IsKeyDown(Enum.KeyCode.W) then
			Forward = Forward + 1
		end

		if UserInputService:IsKeyDown(Enum.KeyCode.S) then
			Forward = Forward - 1
		end

		if UserInputService:IsKeyDown(Enum.KeyCode.D) then
			Right = Right + 1
		end

		if UserInputService:IsKeyDown(Enum.KeyCode.A) then
			Right = Right - 1
		end

		if UserInputService:IsKeyDown(Enum.KeyCode.E) or UserInputService:IsKeyDown(Enum.KeyCode.Space) then
			Up = Up + 1
		end

		if UserInputService:IsKeyDown(Enum.KeyCode.Q) then
			Up = Up - 1
		end

		MoveState.Forward = math.clamp(Forward, -1, 1)
		MoveState.Right = math.clamp(Right, -1, 1)
		MoveState.Up = math.clamp(Up, -1, 1)
		MoveState.Fast = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
		MoveState.Slow = UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)
	end

	local function disconnectAll()
		for _, Connection in ipairs(FreecamFeature.Connections) do
			Connection:Disconnect()
		end

		FreecamFeature.Connections = {}
	end

	local function sinkControlAction()
		return Enum.ContextActionResult.Sink
	end

	local function bindControls()
		if FreecamFeature.ControlsBound then
			return
		end

		local Bound = false

		if type(ContextActionService.BindActionAtPriority) == "function" then
			Bound = pcall(function()
				ContextActionService:BindActionAtPriority(
					BlockActionName,
					sinkControlAction,
					false,
					Enum.ContextActionPriority.High.Value,
					table.unpack(BlockedControls)
				)
			end)
		end

		if not Bound then
			Bound = pcall(function()
				ContextActionService:BindAction(
					BlockActionName,
					sinkControlAction,
					false,
					table.unpack(BlockedControls)
				)
			end)
		end

		FreecamFeature.ControlsBound = Bound
	end

	local function unbindControls()
		if not FreecamFeature.ControlsBound then
			return
		end

		pcall(function()
			ContextActionService:UnbindAction(BlockActionName)
		end)

		FreecamFeature.ControlsBound = false
	end

	local function updateMouseCapture()
		if not FreecamFeature.Enabled then
			UserInputService.MouseBehavior = FreecamFeature.SavedMouseBehavior or Enum.MouseBehavior.Default
			UserInputService.MouseIconEnabled = FreecamFeature.SavedMouseIconEnabled ~= false
			return
		end

		if FreecamFeature.Looking then
			UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
			UserInputService.MouseIconEnabled = false
		else
			UserInputService.MouseBehavior = FreecamFeature.SavedMouseBehavior or Enum.MouseBehavior.Default
			UserInputService.MouseIconEnabled = FreecamFeature.SavedMouseIconEnabled ~= false
		end
	end

	local function setLooking(State)
		FreecamFeature.Looking = State and true or false
		updateMouseCapture()
	end

	local function saveCameraState(Camera)
		FreecamFeature.SavedCameraState = {
			CameraType = Camera.CameraType,
			CameraSubject = Camera.CameraSubject,
			CFrame = Camera.CFrame,
			Focus = Camera.Focus,
			FieldOfView = Camera.FieldOfView
		}
		FreecamFeature.SavedMouseBehavior = UserInputService.MouseBehavior
		FreecamFeature.SavedMouseIconEnabled = UserInputService.MouseIconEnabled
	end

	local function restoreCameraState()
		local Camera = getCurrentCamera()
		local SavedState = FreecamFeature.SavedCameraState

		setLooking(false)

		if Camera and SavedState then
			Camera.CameraType = SavedState.CameraType or Enum.CameraType.Custom
			Camera.CameraSubject = SavedState.CameraSubject
			Camera.CFrame = SavedState.CFrame
			Camera.Focus = SavedState.Focus
			Camera.FieldOfView = SavedState.FieldOfView or Camera.FieldOfView
		end

		FreecamFeature.SavedCameraState = nil
		FreecamFeature.SavedMouseBehavior = nil
		FreecamFeature.SavedMouseIconEnabled = nil
	end

	local function renderStep(DeltaTime)
		local Camera = getCurrentCamera()

		if not Camera or not FreecamFeature.Enabled then
			return
		end

		if UserInputService:GetFocusedTextBox() then
			resetMoveState()
			Camera.CameraType = Enum.CameraType.Scriptable
			local LookVector = getLookVector(FreecamFeature.Yaw, FreecamFeature.Pitch)
			Camera.CFrame = CFrame.lookAt(FreecamFeature.Position, FreecamFeature.Position + LookVector)
			Camera.Focus = CFrame.new(FreecamFeature.Position + (LookVector * 512))
			return
		end

		refreshMoveState()
		Camera.CameraType = Enum.CameraType.Scriptable

		local LookVector = getLookVector(FreecamFeature.Yaw, FreecamFeature.Pitch)
		local CameraCFrame = CFrame.lookAt(FreecamFeature.Position, FreecamFeature.Position + LookVector)
		local Forward = Vector3.new(CameraCFrame.LookVector.X, 0, CameraCFrame.LookVector.Z)

		if Forward.Magnitude <= 0.001 then
			Forward = Vector3.new(0, 0, -1)
		else
			Forward = Forward.Unit
		end

		local Right = Vector3.new(CameraCFrame.RightVector.X, 0, CameraCFrame.RightVector.Z)

		if Right.Magnitude <= 0.001 then
			Right = Vector3.new(1, 0, 0)
		else
			Right = Right.Unit
		end

		local Up = Vector3.new(0, 1, 0)
		local MoveState = FreecamFeature.MoveState
		local MoveVector = (Forward * MoveState.Forward) + (Right * MoveState.Right) + (Up * MoveState.Up)
		local Speed = FreecamFeature.Speed

		if MoveState.Fast then
			Speed = Speed * FreecamFeature.FastMultiplier
		end

		if MoveState.Slow then
			Speed = Speed * FreecamFeature.SlowMultiplier
		end

		if MoveVector.Magnitude > 0 then
			FreecamFeature.Position = FreecamFeature.Position + (MoveVector.Unit * Speed * DeltaTime)
			CameraCFrame = CFrame.lookAt(FreecamFeature.Position, FreecamFeature.Position + LookVector)
		end

		Camera.CFrame = CameraCFrame
		Camera.Focus = CFrame.new(FreecamFeature.Position + (LookVector * 512))
	end

	local function setupConnections()
		disconnectAll()

		table.insert(FreecamFeature.Connections, UserInputService.InputBegan:Connect(function(Input, GameProcessed)
			if not FreecamFeature.Enabled then
				return
			end

			if Input.UserInputType == Enum.UserInputType.MouseButton2 then
				setLooking(true)
				return
			end

			if GameProcessed then
				return
			end

			refreshMoveState()
		end))

		table.insert(FreecamFeature.Connections, UserInputService.InputEnded:Connect(function(Input)
			if not FreecamFeature.Enabled then
				return
			end

			if Input.UserInputType == Enum.UserInputType.MouseButton2 then
				setLooking(false)
				return
			end

			refreshMoveState()
		end))

		table.insert(FreecamFeature.Connections, UserInputService.InputChanged:Connect(function(Input, GameProcessed)
			if not FreecamFeature.Enabled or not FreecamFeature.Looking then
				return
			end

			if GameProcessed then
				return
			end

			if Input.UserInputType == Enum.UserInputType.MouseMovement then
				FreecamFeature.Yaw = FreecamFeature.Yaw - (Input.Delta.X * FreecamFeature.MouseSensitivity)
				FreecamFeature.Pitch = clampPitch(FreecamFeature.Pitch - (Input.Delta.Y * FreecamFeature.MouseSensitivity))
			end
		end))

		table.insert(FreecamFeature.Connections, RunService.RenderStepped:Connect(renderStep))
	end

	function FreecamFeature:SetEnabled(Value)
		if self.Enabled == Value then
			return Value
		end

		if Value then
			local Camera = getCurrentCamera()

			if not Camera then
				return false
			end

			self.Enabled = true
			saveCameraState(Camera)

			local LookVector = Camera.CFrame.LookVector
			self.Position = Camera.CFrame.Position
			self.Yaw = math.atan2(LookVector.X, -LookVector.Z)
			self.Pitch = clampPitch(math.asin(math.clamp(LookVector.Y, -1, 1)))

			resetMoveState()
			refreshMoveState()
			bindControls()
			setupConnections()
			updateMouseCapture()

			if Notification then
				Notification:Notify({
					Title = "Freecam",
					Content = "Enabled - WASD move, Q/E vertical, hold RMB to look.",
					Icon = "check-circle"
				})
			end

			return true
		end

		self.Enabled = false
		resetMoveState()
		disconnectAll()
		unbindControls()
		restoreCameraState()

		if Notification then
			Notification:Notify({
				Title = "Freecam",
				Content = "Disabled",
				Icon = "x-circle"
			})
		end

		return false
	end

	function FreecamFeature:Destroy()
		self:SetEnabled(false)
	end

	return FreecamFeature
end
