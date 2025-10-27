local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ReticleManager = require(ReplicatedStorage.Modules.ReticleManager)
local CustomCamera = require(ReplicatedStorage.Modules.CustomCamera)
local MasterInput = require(ReplicatedStorage.Modules.MasterInput)
local ActionSetup = require(ReplicatedStorage.Modules.ActionSetup)
local TouchInput = require(ReplicatedStorage.Modules.TouchInput)
local Interface = require(ReplicatedStorage.Modules.Interface)
local Gamepad = require(ReplicatedStorage.Modules.Gamepad)
local Mouse = require(ReplicatedStorage.Modules.Mouse)
local Math = require(ReplicatedStorage.Modules.Math)

local Player = Players.LocalPlayer
if not Player.Character or Player.Character.Parent ~= workspace then
	Player.CharacterAdded:Wait()
end
local Character = Player.Character
local Humanoid = Character:WaitForChild("Humanoid")
local Settings = require(script:WaitForChild("Settings").Value)
local Vehicle = Settings["Vehicle"]
local DriverSeat = Settings["DriverSeat"]
local Engine = Settings["Engine"]
local Gui = script:WaitForChild("HeliGui")

local Scripts = Vehicle:WaitForChild("Scripts")
local Events = Scripts:WaitForChild("Events")
local FlaresEvent = Events:WaitForChild("FlaresEvent")
local PowerEvent = Events:WaitForChild("PowerEvent")

local EngineAttach = Instance.new("Attachment", Engine)
local BodyGyro = Instance.new("BodyGyro", Engine)
BodyGyro.MaxTorque = Vector3.zero
local VectorForce = Instance.new("VectorForce", EngineAttach)
VectorForce.Attachment0 = EngineAttach
VectorForce.RelativeTo = Enum.ActuatorRelativeTo.World
VectorForce.Force = Vector3.zero

local PowerStartRate = (1 - Settings["PowerGap"]) / Settings["StartTime"]
local Blacklist = {Player.Character, Vehicle}
local Pitch = 0
local Roll = 0
local Spin = 0
local Power = Vehicle:GetAttribute("Power") or 0

local RollInput = 0
local PowerInput = 0

local function EmptyHandler() end
local function HandleAction(Action, InputState, InputObject)
	if InputState == Enum.UserInputState.Begin then
		if Action == "Camera" then
			local Camera = workspace.CurrentCamera
			if Camera.CameraType == Enum.CameraType.Scriptable then
				CustomCamera.Stop(Engine)
			else
				CustomCamera.FollowMode(Engine, CFrame.Angles(math.rad(-12), 0, 0))
			end
		elseif Action == "Flares" then
			FlaresEvent:FireServer()
		elseif Action == "Power+" then
			PowerInput = 1
		elseif Action == "Power-" then
			PowerInput = -1
		elseif Action == "Roll Left" then
			RollInput = -1
		elseif Action == "Roll Right" then
			RollInput = 1
		end
	elseif InputState == Enum.UserInputState.End then
		if Action == "Power+" then
			PowerInput = 0
		elseif Action == "Power-" then
			PowerInput = 0
		elseif Action == "Roll Left" then
			RollInput = 0
		elseif Action == "Roll Right" then
			RollInput = 0
		end
	end
end

do --//Missile lock
	local LockFrame = Gui:WaitForChild("MissileLock")
	
	local function UpdateLock()
		if Engine:GetAttribute("MissileLock") then
			LockFrame.Visible = true
		else
			LockFrame.Visible = false
		end
	end
	
	UpdateLock()
	Engine:GetAttributeChangedSignal("MissileLock"):Connect(UpdateLock)
end

do --//Gui contents
	local VehicleValues = Vehicle:WaitForChild("VehicleValues")
	local MaxHealth = VehicleValues:WaitForChild("MaxHealth")
	local Health = VehicleValues:WaitForChild("Health")

	local Status = Gui:WaitForChild("Status")
	local Condition = Status:WaitForChild("Condition")
	local EntryLabel = script:WaitForChild("EntryLabel")

	local SeatsTitleLabel = Status:WaitForChild("Seats")
	local SeatsLabel = nil
	local GroupSeats = {}
	local SingleSeats = {}

	local function UpdateSeats()
		local Count = 0
		for _, Seat in ipairs(GroupSeats) do
			if Seat.Occupant then
				Count += 1
			end
		end
		SeatsLabel.Text = Count .. "/" .. #GroupSeats
	end

	local function UpdateTitle()
		if #GroupSeats > 0 then
			SeatsTitleLabel.Visible = true
		else
			local Occupied = false
			for _, Seat in ipairs(SingleSeats) do
				if Seat.Occupant then
					Occupied = true
					break
				end
			end
			SeatsTitleLabel.Visible = Occupied
		end
	end

	for _, Seat in ipairs(Vehicle:GetDescendants()) do
		if (Seat:IsA("Seat") or Seat:IsA("VehicleSeat")) and Seat ~= DriverSeat then
			if Seat.Parent.Name == "Seats" then
				table.insert(GroupSeats, Seat)
				if not SeatsLabel then
					SeatsLabel = EntryLabel:Clone()
					SeatsLabel.LayoutOrder = 4
					SeatsLabel.Parent = Status
				end
				UpdateSeats()
				Seat:GetPropertyChangedSignal("Occupant"):Connect(UpdateSeats)
			else
				table.insert(SingleSeats, Seat)
				local Entry = EntryLabel:Clone()
				Entry.LayoutOrder = 3
				Entry.Parent = Status

				local function Update()
					local Occupant = Seat.Occupant and Players:GetPlayerFromCharacter(Seat.Occupant.Parent)
					if Occupant then
						Entry.Text = Occupant.DisplayName
						Entry.Visible = true
					else
						Entry.Visible = false
					end
				end

				Update()
				Seat:GetPropertyChangedSignal("Occupant"):Connect(Update)
				Seat:GetPropertyChangedSignal("Occupant"):Connect(UpdateTitle)
			end
		end
	end
	UpdateTitle()

	local function UpdateHealth()
		local Ratio = Health.Value / MaxHealth.Value
		if Ratio > 0.66 then
			Condition.BackgroundColor3 = Color3.fromRGB(0, 255, 0)
		elseif Ratio > 0.33 then
			Condition.BackgroundColor3 = Color3.fromRGB(255, 170, 0)
		else
			Condition.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
		end
		Condition.Text = math.floor(Ratio * 100) .. "%"
	end
	UpdateHealth()
	Health:GetPropertyChangedSignal("Value"):Connect(UpdateHealth)
	
	--//Mobile controls
	local Lift = Gui:WaitForChild("Lift")
	local Roll = Gui:WaitForChild("Roll")
	local Fire = Gui:WaitForChild("Fire")
	local Eject = Gui:WaitForChild("Eject")
	local LiftSlider = Lift:WaitForChild("Slider")
	local EjectStart = nil
	
	local function HandleMobile(Action, State, Input)
		if State == Enum.UserInputState.Begin or State == Enum.UserInputState.Change then
			if Action == "Power" then
				local Ratio = Interface:GetNormRelPosition(Lift, Input.Position).Y
				PowerInput = -(Ratio * 2 - 1)
				LiftSlider.Position = UDim2.fromScale(0.5, Ratio)
			elseif Action == "Roll" then
				local Ratio = Interface:GetNormRelPosition(Roll, Input.Position).X
				RollInput = Ratio * 2 - 1
			end
		elseif State == Enum.UserInputState.End then
			if Action == "Power" then
				PowerInput = 0
				LiftSlider.Position = UDim2.fromScale(0.5, 0.5)
			elseif Action == "Roll" then
				RollInput = 0
			end
		end
		
		if Action == "Eject" then
			if State == Enum.UserInputState.Begin then
				EjectStart = tick()
				Eject.Icon.Visible = false
				Eject.Counter.Visible = true
				Eject.ImageColor3 = Color3.fromRGB(215, 74, 73)
				repeat
					local Elapsed = tick() - EjectStart
					Eject.Counter.Text = math.floor(math.max(1 - Elapsed, 0) * 10) / 10
					RunService.RenderStepped:Wait()
				until Elapsed >= 1 or not EjectStart
				Eject.Icon.Visible = true
				Eject.Counter.Visible = false
				Eject.ImageColor3 = Color3.fromRGB(128, 211, 83)
				if EjectStart then
					EjectStart = nil
					Humanoid.Jump = true
				end
			elseif State == Enum.UserInputState.End then
				EjectStart = nil
			end
		end
	end
	
	local IsMobile = false
	local function UpdateDevice(Device)
		if Device == "Mobile" then
			if not IsMobile then
				IsMobile = true
				TouchInput:ConnectButton("Fire", ActionSetup:GetFunction("Fire"), Fire)
				TouchInput:ConnectButton("Power", HandleMobile, Lift)
				TouchInput:ConnectButton("Roll", HandleMobile, Roll)
				TouchInput:ConnectButton("Eject", HandleMobile, Eject)
			end
		else
			IsMobile = false
		end
		
		for _, Element in ipairs({Roll, Lift, Eject, Fire}) do
			Element.Visible = IsMobile
		end
	end
	
	UpdateDevice(MasterInput.GetCurrentDevice())
	MasterInput.DeviceChanged:Connect(UpdateDevice)
end

local LastDevice = nil
local LastMode = nil
local function UpdateControls()
	local Device = MasterInput.GetCurrentDevice()
	local ControlMode = Player:GetAttribute("HelicopterControls")
	if Device ~= LastDevice or ControlMode ~= LastMode then
		LastDevice = Device
		LastMode = ControlMode
		ActionSetup:Unbind("Power+")
		ActionSetup:Unbind("Power-")
		ActionSetup:Unbind("Roll Left")
		ActionSetup:Unbind("Roll Right")

		if Device == "Computer" then
			ActionSetup:Bind("Power+", HandleAction, Enum.KeyCode.E)
			ActionSetup:PriorityBind("Power-", HandleAction, Enum.ContextActionPriority.High.Value, Enum.KeyCode.Q)
			if ControlMode == "Mouse" then
				ActionSetup:Bind("Roll Left", HandleAction, Enum.KeyCode.A, Enum.KeyCode.One)
				ActionSetup:Bind("Roll Right", HandleAction, Enum.KeyCode.D, Enum.KeyCode.Three)
			elseif ControlMode == "Keys" then
				ActionSetup:Bind("Roll Left", HandleAction, Enum.KeyCode.One)
				ActionSetup:Bind("Roll Right", HandleAction, Enum.KeyCode.Three)
			end
		elseif Device == "Gamepad" then
			ActionSetup:Bind("Power+", EmptyHandler, Enum.KeyCode.ButtonR2)
			ActionSetup:Bind("Power-", EmptyHandler, Enum.KeyCode.ButtonL2)
			ActionSetup:Bind("Roll Left", HandleAction, Enum.KeyCode.ButtonL1)
			ActionSetup:Bind("Roll Right", HandleAction, Enum.KeyCode.ButtonR1)
		end
	end
end

ActionSetup:Bind("Camera", HandleAction, Enum.KeyCode.C)
ActionSetup:Bind("Flares", HandleAction, Enum.KeyCode.R, Enum.KeyCode.DPadRight)
Player:GetAttributeChangedSignal("HelicopterControls"):Connect(UpdateControls)
MasterInput.DeviceChanged:Connect(UpdateControls)
UpdateControls()

if Settings["UseReticle"] then
	ReticleManager:Add(Engine, Blacklist, script.ReticleGui)
end
CustomCamera.FollowMode(Engine, CFrame.Angles(math.rad(-12), 0, 0))

if ActionSetup["JumpButton"] then
	ActionSetup["JumpButton"].Visible = false
end

DriverSeat:GetPropertyChangedSignal("Occupant"):Connect(function()
	if not DriverSeat.Occupant then
		if ActionSetup["JumpButton"] then
			ActionSetup["JumpButton"].Visible = true
		end
		CustomCamera.Stop()
		ActionSetup:Unbind("Camera")
		ActionSetup:Unbind("Flares")
		ActionSetup:Unbind("Power+")
		ActionSetup:Unbind("Power-")
		ActionSetup:Unbind("Roll Left")
		ActionSetup:Unbind("Roll Right")
		ReticleManager:Remove(Engine)
		EngineAttach:Destroy()
		BodyGyro:Destroy()
		Gui:Destroy()
		script:Destroy()
	end
end)

RunService:BindToRenderStep("Vehicle", Enum.RenderPriority.Last.Value, function(Delta)
	local ControlMode = Player:GetAttribute("HelicopterControls")
	
	--//Get inputs
	local PitchInput = DriverSeat.ThrottleFloat
	local SpinInput = DriverSeat.SteerFloat
	local GoalPitch = nil
	local GoalYaw = nil
	
	local Device = MasterInput.GetCurrentDevice()
	if Device == "Computer" and ControlMode == "Mouse" then
		local Origin = Engine.CFrame
		local Position = Mouse:GetTarget(Blacklist)
		local Direction = (Position - Origin.Position).Unit
		local Plane = CFrame.lookAlong(Origin.Position, Vector3.new(Origin.LookVector.X, 0, Origin.LookVector.Z))
		local Offset = Plane:ToObjectSpace(CFrame.new(Position)).Position
		GoalPitch = math.deg(math.asin(-Offset.Y / Offset.Magnitude))
		GoalYaw = math.deg(math.atan2(-Offset.X, -Offset.Z))
	elseif Device == "Gamepad" then
		local Stick1 = MasterInput:ThumbstickCurve(Gamepad["States"][Enum.KeyCode.Thumbstick1].Position)
		local Stick2 = MasterInput:ThumbstickCurve(Gamepad["States"][Enum.KeyCode.Thumbstick2].Position)
		local LT = Gamepad["States"][Enum.KeyCode.ButtonL2].Position.Z
		local RT = Gamepad["States"][Enum.KeyCode.ButtonR2].Position.Z
		PowerInput = math.clamp(RT - LT, -1, 1)
		SpinInput = Stick1.X
		PitchInput = -Stick1.Y
	end
	
	--//Adjust values based on inputs
	local Flying = Power >= 1 - Settings["PowerGap"]
	if Flying then
		if PitchInput == 0 and not GoalPitch then
			Pitch = Math:Step(Pitch, 0, Settings["PitchSpeed"] * Delta)
		else
			local Goal = nil
			if GoalPitch and PitchInput == 0 then
				Goal = math.clamp(GoalPitch, -Settings["BackPitch"], Settings["ForwPitch"])
			else
				Goal = PitchInput > 0 and Settings["ForwPitch"] * PitchInput or Settings["BackPitch"] * PitchInput
			end
			Pitch = Math:Step(Pitch, Goal, Settings["PitchSpeed"] * Delta)
		end

		do --//Yaw
			local Speed = Settings["SpinSpeed"]
			local Accel = Settings["SpinAccel"]
			if GoalYaw then
				local Sign = math.sign(GoalYaw)
				local Stop = Spin^2 / (2 * Accel)
				if math.abs(GoalYaw) > Stop then
					--//Accelerate toward target
					Spin = Math:Step(Spin, Speed * Sign, Accel * Delta)
				else
					--//Decelerate
					Spin = Math:Step(Spin, 0, Accel * Delta)
				end
			else
				if SpinInput == 0 then
					Spin = Math:Step(Spin, 0, Accel * Delta)
				else
					Spin = Math:Step(Spin, -Speed * SpinInput, Accel * Delta)
				end
			end
		end
		
		local RollTarget = 0
		if RollInput == 0 then
			RollTarget = -Settings["RollAngle"] * math.abs(Pitch) / Settings["ForwPitch"] * Spin / Settings["SpinSpeed"]
		else
			RollTarget = Settings["RollAngle"] * RollInput
		end
		Roll = Math:Step(
			Roll,
			math.clamp(RollTarget, -Settings["RollAngle"], Settings["RollAngle"]),
			Settings["RollSpeed"] * Delta
		)
	end
	
	--//Calculate drag
	local v = Engine.AssemblyLinearVelocity
	local v_local = Engine.CFrame:VectorToObjectSpace(v)
	v_local = Vector3.new(
		math.clamp(v_local.X, -500, 500),
		math.clamp(v_local.Y, -500, 500),
		math.clamp(v_local.Z, -500, 500)
	)
	--//X: side, Y: top/bottom, Z: front/back
	local DragCoeff = 120
	local QuadCoeff = Vehicle:GetAttribute("QuadCoeff")
	local LinearCoeff = Vehicle:GetAttribute("LinearCoeff")
	local Quad = Vector3.new(
		v_local.X * math.abs(v_local.X) * QuadCoeff.X,
		v_local.Y * math.abs(v_local.Y) * QuadCoeff.Y,
		v_local.Z * math.abs(v_local.Z) * QuadCoeff.Z
	)
	local Linear = Vector3.new(
		v_local.X * LinearCoeff.X,
		v_local.Y * LinearCoeff.Y,
		v_local.Z * LinearCoeff.Z
	)
	local DragLocal = -(Quad + Linear) * DragCoeff
	local Drag = Engine.CFrame:VectorToWorldSpace(DragLocal)
	local Weight = Engine.AssemblyMass * workspace.Gravity
	
	--//Power
	local PowerTarget = 0
	if Flying then
		--//Attempt to maintain constant vertical velocity
		local Cosine = Engine.CFrame.UpVector:Dot(Vector3.new(0, 1, 0))
		local Drag0 = (v.Y * math.abs(v.Y) * QuadCoeff.Y + v.Y * LinearCoeff.Y) * DragCoeff
		PowerTarget = 1 + Settings["PowerGap"] * PowerInput
		PowerTarget *= (1 - (Drag.Y + Drag0) / Weight) / Cosine
	else
		if PowerInput == 0 then
			PowerTarget = 0
		else
			PowerTarget = math.max(PowerInput, 0)
		end
	end
	
	local Rate = Flying and Settings["PowerRate"] or PowerStartRate
	local Min = Flying and (1 - Settings["PowerGap"]) or 0
	Power = Math:Step(
		Power,
		math.clamp(PowerTarget, Min, 1 + Settings["PowerGap"]),
		Rate * Delta
	)
	
	--//Apply physical changes
	local MinPower = 1 - Settings["PowerGap"]
	local DefaultScale = 1.2
	local Scale = (1-DefaultScale*MinPower)/(MinPower^2-MinPower)*Power^2 + (DefaultScale-(1-DefaultScale*MinPower)/(MinPower^2-MinPower))*Power
	if Flying then
		local Lift = Engine.CFrame.UpVector * Weight * Power
		VectorForce.Force = Lift + Drag
		Engine.AssemblyAngularVelocity = Vector3.new(Engine.AssemblyAngularVelocity.X, math.rad(Spin), Engine.AssemblyAngularVelocity.Z)
		
		BodyGyro.MaxTorque = Vector3.new(1, 0, 1) * Engine.AssemblyMass * 20^2 * Scale
		BodyGyro.CFrame = CFrame.new(Engine.Position) * CFrame.fromOrientation(math.rad(-Pitch), math.rad(Engine.Orientation.Y), math.rad(-Roll))
	else
		VectorForce.Force = Vector3.zero
		BodyGyro.MaxTorque = Vector3.zero
	end
	
	PowerEvent:FireServer(Power)
end)
