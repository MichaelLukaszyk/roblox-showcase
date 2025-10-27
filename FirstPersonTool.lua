local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local GameFunctions = require(ReplicatedStorage.Modules.GameFunctions)
local ActionSetup = require(ReplicatedStorage.Modules.ActionSetup)
local LocalHider = require(ReplicatedStorage.Modules.LocalHider)
local Interface = require(ReplicatedStorage.Modules.Interface)
local Basics = require(ReplicatedStorage.Modules.Basics)
local EffectEvent = ReplicatedStorage.Events.EffectEvent

local Player = Players.LocalPlayer
local Camera = workspace.CurrentCamera
local CameraInput = require(Player.PlayerScripts:WaitForChild("PlayerModule"):WaitForChild("CameraModule"):WaitForChild("CameraInput"))
local Cameras = require(Player.PlayerScripts:WaitForChild("PlayerModule")):GetCameras()

local Rendering = false
local AimLooping = false
local StartSensitivity = nil
local ScopeGui = nil
local Rig = nil
local RigHead = nil

local FakeModel = nil
local ActiveToolModel = nil
local ActiveTurret = nil
local HeadOffset = nil
local SwayOffset = nil
local Barrel_3rd = nil
local Barrel_FPS = nil
local Busy = false

local DisconnectAimDown = nil
local EndAimDown = nil
local Subject_3rd = script.Subject_3rd
local Subject_FPS = script.Subject_FPS
local ExtCharTracks = {}
local ExtRigTracks = {}
local CharTracks = {}
local RigTracks = {}
local Module = {
	["FirstPerson"] = false,
	["AimingDown"] = false,
	["ScopeGuiActive"] = false,
	["Sights"] = false,
	["ExtCharTracks"] = ExtCharTracks,
	["ExtRigTracks"] = ExtRigTracks,
	["CharTracks"] = CharTracks,
	["RigTracks"] = RigTracks,
	["Subject_3rd"] = Subject_3rd,
	["Subject_FPS"] = Subject_FPS
}

do --//Manage rig
	local Parts = {"Body Colors", "HumanoidRootPart", "Humanoid", "Head", "Torso", "Left Arm", "Right Arm"}
	local RigTorso = nil
	
	local function UpdateClothing()
		local CharShirt = Player.Character:FindFirstChildWhichIsA("Shirt")
		local RigShirt = Rig:FindFirstChildWhichIsA("Shirt")
		if CharShirt and not RigShirt then
			RigShirt = CharShirt:Clone()
			RigShirt.Parent = Rig
			CharShirt:GetPropertyChangedSignal("ShirtTemplate"):Connect(function()
				RigShirt.ShirtTemplate = CharShirt.ShirtTemplate
			end)
		elseif not CharShirt and RigShirt then
			RigShirt:Destroy()
		end
	end

	local function MakeRig(Character)
		for _, Name in ipairs(Parts) do
			Character:WaitForChild(Name)
		end
		Character.Archivable = true
		Rig = Character:Clone()
		Rig.Name = "FPS_Rig"
		Rig.Parent = ReplicatedStorage

		for _, Part in ipairs(Rig:GetChildren()) do
			if not table.find(Parts, Part.Name) then
				Part:Destroy()
			elseif Part:IsA("BasePart") then
				Part.CastShadow = false
				Part.CanCollide = false
			end
		end
		GameFunctions:SetTransparency(Rig, 0)
		
		local Face = Rig.Head:FindFirstChild("face")
		if Face then
			Face.Transparency = 1
		end
		Rig.Humanoid.EvaluateStateMachine = false
		Rig.Head.Anchored = true
		Rig.Head.Transparency = 1
		Rig.Torso.Transparency = 1
		Rig["Left Arm"].Size *= Vector3.new(0.7, 1, 0.7)
		Rig["Right Arm"].Size *= Vector3.new(0.7, 1, 0.7)
		RigHead = Rig.Head
		RigTorso = Rig.Torso
		
		do --//Sync motor C0s
			local CharTorso = Character:WaitForChild("Torso")
			for _, Name in ipairs({"Right Shoulder", "Left Shoulder"}) do
				local Real = CharTorso:WaitForChild(Name)
				local Fake = RigTorso:WaitForChild(Name)
				if Real:GetAttribute("BaseC0") then
					Fake.C0 = Real:GetAttribute("BaseC0")
				end
				Real:GetAttributeChangedSignal("BaseC0"):Connect(function()
					Fake.C0 = Real:GetAttribute("BaseC0")
				end)
			end
		end
		
		Character.ChildAdded:Connect(UpdateClothing)
		Character.ChildRemoved:Connect(UpdateClothing)
		UpdateClothing()
	end

	if Player.Character then
		MakeRig(Player.Character)
	end
	Player.CharacterAdded:Connect(MakeRig)
	Player.CharacterRemoving:Connect(function()
		if Rig then
			Rig:Destroy()
			Rig = nil
		end
		Module:EndRender()
	end)
	
	RunService.Stepped:Connect(function()
		if RigTorso then
			RigTorso.CanCollide = false
		end
	end)
end

do --//Aim down
	EndAimDown = function()
		if AimLooping then
			if ActiveTurret then
				LocalHider:Show(ActiveTurret, "Turret")
				ActiveTurret = nil
			end
			if Rig then
				LocalHider:Show(Rig, "ScopeGui")
			end
			if ScopeGui then
				ScopeGui.Enabled = false
			end
			Camera.FieldOfView = 70
			UserInputService.MouseDeltaSensitivity = StartSensitivity
			CameraInput["Sensitivity"]["Gamepad"] = CameraInput["Original"]["Gamepad"]
			CameraInput["Sensitivity"]["Touch"] = CameraInput["Original"]["Touch"]
			Interface["FadeGui"].Enabled = false
			Interface["CanFade"] = true
			HeadOffset = CFrame.new()
			Module["AimingDown"] = false
			Module["ScopeGuiActive"] = false
			AimLooping = false
			RunService:UnbindFromRenderStep("AimDown")
		end
	end

	function Module:AimDown(Enabled, Settings)
		if not Enabled then
			Module["AimingDown"] = false
		elseif Module["FirstPerson"] then
			Module["AimingDown"] = true
		end

		if Module["AimingDown"] and not AimLooping then
			local TurretSights = Settings["SightsPart"] or Subject_FPS.Value
			Module["Sights"] = Settings["SightsPart"] and true or false
			local ToolMode = nil
			if Rendering and FakeModel then
				ToolMode = true
			elseif Subject_FPS.Value then
				ToolMode = false
			else
				return
			end

			local StartOffset = HeadOffset
			local Visible = true
			local LinearElapsed = 0
			AimLooping = true
			ActiveTurret = Settings["Turret"]
			StartSensitivity = UserInputService.MouseDeltaSensitivity

			if Settings["ScopeGui"] then
				if not Settings["ScopeFadeOut"] then
					Settings["ScopeFadeOut"] = 0.1
				end
				if not ScopeGui then
					ScopeGui = Settings["ScopeGui"]:Clone()
					ScopeGui.Enabled = false
					ScopeGui.Parent = Player.PlayerGui
				end
				Interface["CanFade"] = false
				Interface["FadeFrame"].BackgroundTransparency = 1
				Interface["FadeGui"].Enabled = true
			end

			if not Settings["AimDownTime"] then
				Settings["AimDownTime"] = 0.1
			end

			if not Settings["AimDownFOV"] then
				Settings["AimDownFOV"] = 60
			end

			RunService:BindToRenderStep("AimDown", Enum.RenderPriority.Camera.Value + 2, function(Delta)
				local Elapsed = nil
				if Module["AimingDown"] then
					LinearElapsed = math.min(LinearElapsed + Delta, Settings["AimDownTime"])
					Elapsed = LinearElapsed
				else
					LinearElapsed = math.max(LinearElapsed - Delta, 0)
					Elapsed = Settings["AimDownTime"] - LinearElapsed
				end

				local Percent = LinearElapsed / Settings["AimDownTime"]
				local ShouldShow = true

				if ScopeGui then
					local InTime = Settings["AimDownTime"] - Settings["ScopeFadeOut"]
					if Module["AimingDown"] then
						local InPercent = Elapsed / InTime
						local OutPercent = (Elapsed - InTime) / Settings["ScopeFadeOut"]
						if InPercent < 1 then
							Interface["FadeFrame"].BackgroundTransparency = 1 - InPercent
							ShouldShow = true
						else
							Interface["FadeFrame"].BackgroundTransparency = OutPercent
							ShouldShow = false
						end
					else
						local OutPercent = Elapsed / Settings["ScopeFadeOut"]
						local InPercent = (Elapsed - Settings["ScopeFadeOut"]) / InTime
						if OutPercent < 1 then
							Interface["FadeFrame"].BackgroundTransparency = 1 - OutPercent
							ShouldShow = false
						else
							Interface["FadeFrame"].BackgroundTransparency = InPercent
							ShouldShow = true
						end
					end
				end

				if ShouldShow ~= Visible then
					Visible = ShouldShow
					if Visible then
						ScopeGui.Enabled = false
						if ToolMode then
							LocalHider:Show(Rig, "ScopeGui")
						else
							LocalHider:Show(ActiveTurret, "Turret")
						end
					else
						ScopeGui.Enabled = true
						if ToolMode then
							LocalHider:Hide(Rig, "ScopeGui")
						else
							LocalHider:Hide(ActiveTurret, "Turret")
						end
					end
					Module["ScopeGuiActive"] = ScopeGui.Enabled
				end

				if (Percent == 0 and not Module["AimingDown"]) or not Module["FirstPerson"] then
					EndAimDown()
				else
					if ToolMode then
						local Sights0 = FakeModel:FindFirstChild("Sights")
						local Sights1 = FakeModel:FindFirstChild("Sights1")
						local Sights2 = FakeModel:FindFirstChild("Sights2")
						local SightCFrame = nil
						local Distance = Sights1 and Sights1:GetAttribute("Distance") or 0.75
						if Sights0 then
							SightCFrame = Sights0.CFrame
						elseif Sights1 and Sights2 then
							local Relative = Sights1.CFrame:ToObjectSpace(Sights2.CFrame)
							if Relative.Y < 0 then
								SightCFrame = Sights1.CFrame * CFrame.new(0, 0, Distance)
							else
								SightCFrame = CFrame.lookAt(Sights1.Position, Sights2.Position, Sights1.CFrame.UpVector) * CFrame.new(0, 0, Distance)
							end
						elseif Sights1 then
							SightCFrame = Sights1.CFrame * CFrame.new(0, 0, Distance)
						end
						local GoalOffset = SightCFrame and SightCFrame:ToObjectSpace(RigHead.CFrame) or CFrame.new()
						HeadOffset = StartOffset:Lerp(GoalOffset, Percent)
						Module["Sights"] = SightCFrame and true or false
					else
						local Current = CFrame.new(Subject_FPS.Value.Position) * SwayOffset
						Camera.CFrame = Current:Lerp(TurretSights.CFrame, Percent)
					end

					if Settings["AimDownFOV"] then
						Camera.FieldOfView = 70 - (70 - Settings["AimDownFOV"]) * Percent
					end
					UserInputService.MouseDeltaSensitivity = StartSensitivity * (Camera.FieldOfView / 250)
					CameraInput["Sensitivity"]["Gamepad"] = CameraInput["Original"]["Gamepad"] * (Camera.FieldOfView / 150)
					CameraInput["Sensitivity"]["Touch"] = CameraInput["Original"]["Touch"] * (Camera.FieldOfView / 150)
				end
			end)
		end
	end
end

do --//Aim down setup
	local Connected = false
	local SettingsSave = nil
	local CanAimDownSave = nil
	local Connection1 = nil
	local Connection2 = nil

	DisconnectAimDown = function()
		if Connected then
			Connected = false
			ActionSetup:Unbind("AimDown")
			ActionSetup:Unbind("TouchAimDown")
			Connection1:Disconnect()
			Connection2:Disconnect()
			Connection1 = nil
			Connection2 = nil
		end
	end

	local function HandleAction(Action, InputState, InputObject)
		if InputState == Enum.UserInputState.Begin then
			if Action == "AimDown" and (not CanAimDownSave or CanAimDownSave()) then
				Module:AimDown(true, SettingsSave)
			elseif Action == "TouchAimDown" then
				local CameraController = Cameras.activeCameraController
				if CameraController and not Module["FirstPerson"] then
					CameraController:SetCameraToSubjectDistance(0)
				end
				if Module["AimingDown"] then
					HandleAction("AimDown", Enum.UserInputState.End)
				else
					HandleAction("AimDown", Enum.UserInputState.Begin)
				end
			end
		elseif InputState == Enum.UserInputState.End then
			if Action == "AimDown" then
				Module:AimDown(false)
			end
		end
	end

	function Module:ConnectAimDown(Settings, CanAimDown)
		DisconnectAimDown()
		Connected = true
		SettingsSave = Settings
		CanAimDownSave = CanAimDown
		ActionSetup:Bind("AimDown", HandleAction, Enum.KeyCode.ButtonL2)
		ActionSetup:Bind("TouchAimDown", HandleAction)

		Connection1 = UserInputService.InputBegan:Connect(function(Input, GameProcessed)
			if Input.UserInputType == Enum.UserInputType.MouseButton2 then
				HandleAction("AimDown", Enum.UserInputState.Begin)
			end
		end)

		Connection2 = UserInputService.InputEnded:Connect(function(Input)
			if Input.UserInputType == Enum.UserInputType.MouseButton2 then
				HandleAction("AimDown", Enum.UserInputState.End)
			end
		end)
	end
end

function Module:StartRender(ToolModel, UseArmSway)
	if Player.Character and Rig and not Rendering and not Busy then
		Rendering = true
		Busy = true
		HeadOffset = CFrame.new()
		SwayOffset = CFrame.new()
		ToolModel.PrimaryPart = Basics:WaitForChild(ToolModel, {"Grip", "RightGrip"})

		for _, Part in ipairs(ToolModel:GetDescendants()) do
			if Part:IsA("Motor6D") then
				if not Part.Part0 then
					Part:GetPropertyChangedSignal("Part0"):Wait()
				end
				if not Part.Part1 then
					Part:GetPropertyChangedSignal("Part1"):Wait()
				end
			end
		end
		
		ActiveToolModel = ToolModel
		FakeModel = ToolModel:Clone()
		FakeModel.Parent = Rig
		for _, Part in ipairs(FakeModel:GetDescendants()) do
			if Part:IsA("Motor6D") then
				if Part.Part0 and Part.Part0.Parent == Player.Character then
					Part.Part0 = Rig:WaitForChild(Part.Part0.Name)
				end
				if Part.Part1 and Part.Part1.Parent == Player.Character then
					Part.Part1 = Rig:WaitForChild(Part.Part1.Name)
				end
			elseif Part:IsA("BasePart") then
				Part.CastShadow = false
				Part.CanCollide = false
			end
		end
		
		Barrel_3rd = ToolModel:FindFirstChild("Barrel")
		Barrel_FPS = FakeModel:FindFirstChild("Barrel")
		Module["Model"] = FakeModel
		Module["Barrel"] = Barrel_3rd
		Module["FakeBarrel"] = Barrel_FPS
		
		if Module["FirstPerson"] then
			Module["ActiveBarrel"] = Barrel_FPS
			LocalHider:Hide(ToolModel, "Character")
		else
			Module["ActiveBarrel"] = Barrel_3rd
			LocalHider:Show(ToolModel, "Character")
		end
		
		Busy = false
	end
end

function Module:EndRender()
	if Busy then
		repeat
			task.wait()
		until not Busy
	end
	Busy = true
	
	Barrel_3rd = nil
	Barrel_FPS = nil
	Module["Model"] = nil
	Module["Barrel"] = nil
	Module["FakeBarrel"] = nil
	Module["ActiveBarrel"] = nil
	
	local Humanoid = Player.Character and Player.Character:FindFirstChild("Humanoid")
	Camera.CameraType = Enum.CameraType.Custom
	Camera.CameraSubject = Humanoid
	
	if ActiveToolModel then
		LocalHider:Show(ActiveToolModel, "Character")
		ActiveToolModel = nil
	end
	if ActiveTurret then
		LocalHider:Show(ActiveTurret, "Turret")
		ActiveTurret = nil
	end
	if FakeModel then
		FakeModel:Destroy()
		FakeModel = nil
	end
	if ScopeGui then
		ScopeGui:Destroy()
		ScopeGui = nil
	end
	
	EndAimDown()
	DisconnectAimDown()
	
	--//Switch active CharTracks over to ExtCharTracks
	for Name, Track in pairs(CharTracks) do
		if Track.IsPlaying and ExtCharTracks[Name] then
			ExtCharTracks[Name]:Play(0)
		end
		Track:Stop()
	end
	for Name, Track in pairs(RigTracks) do
		if Track.IsPlaying and ExtRigTracks[Name] then
			ExtRigTracks[Name]:Play(0)
		end
		Track:Stop()
	end
	table.clear(CharTracks)
	table.clear(RigTracks)
	
	Rendering = false
	Busy = false
end

function Module:GetAnimations(Folder, _Animations)
	local Animations = _Animations or {}
	if Folder then
		for _, Obj in ipairs(Folder:GetDescendants()) do
			if Obj:IsA("ObjectValue") then
				Module:GetAnimations(Obj.Value, Animations)
			elseif Obj:IsA("Animation") then
				Animations[Obj.Name] = Obj
			end
		end
	end
	return Animations
end

function Module:LoadTracks(CharAnims, RigAnims, External)
	if Player.Character and Rig then
		--//External tracks are not unloaded by module, but can be interacted with through helper functions
		local CharAnimator = Player.Character:WaitForChild("Humanoid"):WaitForChild("Animator")
		local RigAnimator = Rig:WaitForChild("Humanoid"):WaitForChild("Animator")
		local CharRef = External and ExtCharTracks or CharTracks
		local RigRef = External and ExtRigTracks or RigTracks
		
		CharAnims = Module:GetAnimations(CharAnims)
		RigAnims = Module:GetAnimations(RigAnims)
		for Name, CharAnim in pairs(CharAnims) do
			local RigAnim = RigAnims[Name] or CharAnim
			for _, Group in ipairs({{CharAnimator, CharAnim, CharRef}, {RigAnimator, RigAnim, RigRef}}) do
				local Animator = Group[1]
				local Anim = Group[2]
				local Ref = Group[3]
				local Track = Animator:LoadAnimation(Anim)
				Ref[Name] = Track
				Track.Priority = Anim:GetAttribute("Priority") or Track.Priority
				Track:SetAttribute("Speed", Anim:GetAttribute("Speed"))
				local Looped = Anim:GetAttribute("Looped")
				if Looped ~= nil then
					Track.Looped = Looped
				end
			end
		end
		
		if not External then
			--//Switch active ExtCharTracks over to new CharTracks
			for Name, Track in pairs(ExtCharTracks) do
				if Track.IsPlaying and CharTracks[Name] then
					Track:Stop()
					CharTracks[Name]:Play(0)
				end
			end
			for Name, Track in pairs(ExtRigTracks) do
				if Track.IsPlaying and RigTracks[Name] then
					Track:Stop()
					RigTracks[Name]:Play(0)
				end
			end
		end
		
		return CharRef, RigRef
	end
end

function Module:PlayTrack(Name, FadeTime, Duration)
	--//Tracks from CharTracks have higher priority over ExtCharTracks, only one plays at a time
	local CharTrack = nil
	local RigTrack = nil
	
	if CharTracks[Name] then
		if ExtCharTracks[Name] then
			ExtCharTracks[Name]:Stop()
			ExtRigTracks[Name]:Stop()
		end
		CharTrack = CharTracks[Name]
		RigTrack = RigTracks[Name]
	elseif ExtCharTracks[Name] then
		CharTrack = ExtCharTracks[Name]
		RigTrack = ExtRigTracks[Name]
	end
	
	if CharTrack then
		CharTrack:Play(FadeTime, 1, Duration and CharTrack.Length / Duration or CharTrack:GetAttribute("Speed") or 1)
		RigTrack:Play(FadeTime, 1, Duration and RigTrack.Length / Duration or CharTrack:GetAttribute("Speed") or 1)
	end
end

function Module:StopTrack(Name)
	local CharTrack = CharTracks[Name] or ExtCharTracks[Name]
	local RigTrack = RigTracks[Name] or ExtRigTracks[Name]
	if CharTrack and RigTrack then
		CharTrack:Stop()
		RigTrack:Stop()
	end
end

function Module:IsTrackPlaying(Name)
	local CharTrack = CharTracks[Name] or ExtCharTracks[Name]
	if CharTrack and CharTrack.IsPlaying then
		return true
	end
	return false
end

function Module:PlaySound(Name)
	local Sound_3rd = Module["Barrel"] and Module["Barrel"]:FindFirstChild(Name)
	local Sound_Active = Module["ActiveBarrel"] and Module["ActiveBarrel"]:FindFirstChild(Name)
	if Sound_3rd and Sound_Active then
		Sound_Active:Stop()
		Sound_Active:Play()
		EffectEvent:FireServer(true, Sound_3rd)
	end
end

function Module:StopSound(Name)
	local Sound_3rd = Module["Barrel"] and Module["Barrel"]:FindFirstChild(Name)
	local Sound_FPS = Module["FakeBarrel"] and Module["FakeBarrel"]:FindFirstChild(Name)
	if Sound_3rd and Sound_FPS then
		Sound_3rd:Stop()
		Sound_FPS:Stop()
		EffectEvent:FireServer(false, Sound_3rd, Sound_FPS)
	end
end

Subject_3rd:GetPropertyChangedSignal("Value"):Connect(function()
	local Value = Subject_3rd.Value
	if not Module["FirstPerson"] then
		local Humanoid = Player.Character and Player.Character:FindFirstChild("Humanoid")
		Camera.CameraSubject = Value or Humanoid
	end
end)

Subject_FPS:GetPropertyChangedSignal("Value"):Connect(function()
	local Value = Subject_FPS.Value
	if Module["FirstPerson"] then
		local Humanoid = Player.Character and Player.Character:FindFirstChild("Humanoid")
		Camera.CameraSubject = Value or Humanoid
	end
	if not Value then
		Module:EndRender()
	end
end)

local function CharacterAdded(Character)
	local Humanoid = Character:WaitForChild("Humanoid")
	local Head = Character:WaitForChild("Head")
	
	local SwayMagnitude = 0.1
	local SwayFrequency = 2
	local SwayCount = 0
	local LastCameraCFrame = Camera.CFrame
	HeadOffset = CFrame.new()
	SwayOffset = CFrame.new()
	Module["FirstPerson"] = false
	Module["AimingDown"] = false
	Module["ScopeGuiActive"] = false
	
	pcall(function()
		RunService:UnbindFromRenderStep("FirstPersonTool")
	end)
	
	ReplicatedStorage:WaitForChild("FPS_Rig", math.huge)
	
	RunService:BindToRenderStep("FirstPersonTool", Enum.RenderPriority.Camera.Value + 3, function(Delta)
		if Player.Character ~= Character then
			RunService:UnbindFromRenderStep("FirstPersonTool")
			return
		end
		
		if not Rig then
			return
		end
		
		--//Do not run while there is a custom camera implementation
		if Camera.CameraType == Enum.CameraType.Scriptable then
			if not Subject_3rd.Value and not Subject_FPS.Value then
				return
			end
		end
		
		local IsFirstPerson = true
		local CameraController = Cameras.activeCameraController
		if CameraController then
			if CameraController:InFirstPerson() then
				IsFirstPerson = true
			else
				IsFirstPerson = false
			end
		elseif Camera.CameraType == Enum.CameraType.Scriptable then
			local ZoomDelta = CameraInput.getZoomDelta()
			if ZoomDelta > 0 then
				Camera.CameraType = Enum.CameraType.Custom
				IsFirstPerson = false
			end
		end
		
		--//Transition between first and third person
		if IsFirstPerson and not Module["FirstPerson"] then
			--//First person
			Module["FirstPerson"] = true
			Module["ActiveBarrel"] = Barrel_FPS
			
			Player:SetAttribute("FirstPerson", true)
			LocalHider:Hide(Character, "Character")
			if Subject_FPS.Value then
				Camera.CameraSubject = Subject_FPS.Value
			end
			
			--//Update rig tracks
			for Name, CharTrack in pairs(CharTracks) do
				local RigTrack = RigTracks[Name] or ExtRigTracks[Name]
				if RigTrack and not RigTrack.Looped then
					if CharTrack.IsPlaying then
						RigTrack:Play(0, RigTrack.Speed)
						RigTrack.TimePosition = RigTrack.Length * CharTrack.TimePosition / CharTrack.Length
					else
						RigTrack:Stop()
					end
				end
			end
		elseif not IsFirstPerson and Module["FirstPerson"] then
			--//Third person
			Module["FirstPerson"] = false
			Module["ActiveBarrel"] = Barrel_3rd
			
			Player:SetAttribute("FirstPerson", false)
			LocalHider:Show(Character, "Character")
			Rig.Parent = ReplicatedStorage
			Camera.CameraType = Enum.CameraType.Custom
			Camera.CameraSubject = Subject_3rd.Value or Humanoid
		end
		
		if Module["FirstPerson"] then
			if Rendering then
				--//Fake tool model
				local HeadCFrame = Camera.CFrame * HeadOffset
				local GoalMagnitude = 0.07
				local GoalFrequency = 4
				if Character:GetAttribute("Stance") == 1 then
					GoalMagnitude = 0.05
				elseif Character:GetAttribute("Stance") == 2 then
					GoalMagnitude = 0.03
				end
				if Module["AimingDown"] then
					GoalMagnitude = 0.005
				end
				GoalMagnitude *= 1 + math.min(Head.AssemblyLinearVelocity.Magnitude / Humanoid.WalkSpeed, 1) * 0.5
				GoalFrequency *= 1 + math.min(Head.AssemblyLinearVelocity.Magnitude / Humanoid.WalkSpeed, 1) * 4
				SwayMagnitude = SwayMagnitude + (GoalMagnitude - SwayMagnitude) * 0.1
				SwayFrequency = SwayFrequency + (GoalFrequency - SwayFrequency) * 0.1
				SwayCount += Delta * SwayFrequency

				local X, Y = Camera.CFrame:ToObjectSpace(LastCameraCFrame):ToOrientation()
				local MaxSway = math.rad(15)
				X = math.clamp(X * 0.5, -MaxSway, MaxSway)
				Y = math.clamp(Y * 0.5, -MaxSway, MaxSway)
				SwayOffset = SwayOffset:Lerp(CFrame.Angles(-X, -Y, 0), 0.1)
				
				HeadCFrame *= SwayOffset * CFrame.new(
					math.sin(SwayCount * 0.5) * SwayMagnitude,
					math.sin(SwayCount) * SwayMagnitude * 0.5,
					0
				)
				RigHead:PivotTo(HeadCFrame)
				Rig.Parent = Camera
			else
				--//Workspace model
				if Subject_FPS.Value then
					UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
					Camera.CameraType = Enum.CameraType.Scriptable
					SwayOffset = SwayOffset:Lerp(Subject_FPS.Value.CFrame.Rotation, 0.5)
					if not AimLooping then
						Camera.CFrame = CFrame.new(Subject_FPS.Value.Position) * SwayOffset
					end
				else
					Camera.CameraType = Enum.CameraType.Custom
				end
				Rig.Parent = ReplicatedStorage
			end
		end
		
		LastCameraCFrame = Camera.CFrame
	end)
end

if Player.Character then
	coroutine.wrap(CharacterAdded)(Player.Character)
end
Player.CharacterAdded:Connect(CharacterAdded)

return Module
