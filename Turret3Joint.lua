local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FirstPersonTool = require(ReplicatedStorage.Modules.FirstPersonTool)
local ReticleManager = require(ReplicatedStorage.Modules.ReticleManager)
local MasterInput = require(ReplicatedStorage.Modules.MasterInput)
local Mouse = require(ReplicatedStorage.Modules.Mouse)
local Math = require(ReplicatedStorage.Modules.Math)
local WeldEvent = ReplicatedStorage.Events.WeldEvent
local Settings = require(script:WaitForChild("Settings").Value)

local Player = Players.LocalPlayer
local Blacklist = {Player.Character, Settings["Vehicle"] or Settings["Turret"]}

local Attachments = Settings["Turret"]:WaitForChild("Attachments")
local BaseAttach = Attachments:WaitForChild("Base")
local BaseYawAttach = Attachments:WaitForChild("BaseYaw")
local YawAttach = Attachments:WaitForChild("Yaw")
local PitchAttach = Attachments:WaitForChild("Pitch")
local BaseYawWeld = BaseYawAttach:WaitForChild("Weld")
local YawWeld = YawAttach:WaitForChild("Weld")
local PitchWeld = PitchAttach:WaitForChild("Weld")
local Barrel = Attachments:FindFirstChild("Barrel")

local YawNoLimits = Settings["YawLimits"] == Vector2.new(-360, 360)
local _, BaseYawY, _ = BaseYawWeld.C0:ToOrientation()
local _, YawY, _ = YawWeld.C0:ToOrientation()
local PitchX, _, _ = PitchWeld.C0:ToOrientation()
local Rotation = {
	[1] = math.deg(-PitchX),
	[2] = math.deg(BaseYawY),
	[3] = math.deg(YawY)
}

local MouseInfo = {
	["UseTouchCenter"] = true
}

local Model = Settings["Turret"]:FindFirstChild("Model")
local Base = Model and Model:FindFirstChild("Base")
local NormalCamera = Settings["NormalCamera"] or (Base and Base:FindFirstChild("NormalCamera"))
local MobileCamera = Settings["MobileCamera"] or (Base and Base:FindFirstChild("MobileCamera"))
if MobileCamera and Player.PlayerGui:FindFirstChild("TouchGui") then
	FirstPersonTool["Subject_3rd"].Value = MobileCamera
elseif NormalCamera then
	FirstPersonTool["Subject_3rd"].Value = NormalCamera
end

local Pitch = Model and Model:FindFirstChild("Pitch")
local FirstPerson = Pitch and Pitch:FindFirstChild("FirstPerson")
if FirstPerson then
	Settings["SightsPart"] = Pitch:FindFirstChild("Sights")
	FirstPersonTool["Subject_FPS"].Value = FirstPerson
	FirstPersonTool:ConnectAimDown(Settings)
end

if Barrel then
	ReticleManager:Add(Barrel, Blacklist)
end

local Seat = Settings["Seat"]
if Seat then
	local PlayerValue = Seat:WaitForChild("PlayerValue")
	PlayerValue:GetPropertyChangedSignal("Value"):Connect(function()
		if not PlayerValue.Value then
			FirstPersonTool["Subject_3rd"].Value = nil
			FirstPersonTool["Subject_FPS"].Value = nil
			ReticleManager:Remove(Barrel)
			script:Destroy()
		end
	end)
end

local Offset = YawAttach.CFrame:ToObjectSpace(PitchAttach.CFrame)
local a = -Offset.Z
local b = Offset.Y
local c = math.sqrt(a ^ 2 + b ^ 2)
local phi = math.atan2(b, a)

RunService:BindToRenderStep("Turret", Enum.RenderPriority.Camera.Value + 1, function(Delta)
	local OldPitch = Rotation[1]
	local OldYaw = Rotation[2] + Rotation[3]
	local OldBaseYaw = Rotation[2]
	if FirstPersonTool["FirstPerson"] then
		--//Use input delta
		local RotDelta = MasterInput:GetRotation(Delta)
		local Max = Settings["Speed"] * Delta
		Rotation[1] = OldPitch + math.clamp(-math.deg(RotDelta.Y), -Max, Max)
		Rotation[2] = OldYaw + math.clamp(math.deg(RotDelta.X), -Max, Max)
	else
		--//Point to mouse
		local Position = Mouse:GetTarget(Blacklist, MouseInfo)
		local PitchOffset = YawAttach.CFrame:ToObjectSpace(CFrame.new(Position))
		local x2 = math.sqrt(PitchOffset.X ^ 2 + PitchOffset.Z ^ 2)
		local y2 = PitchOffset.Y
		local function f(x)
			return math.cos(x)*(x2 - c*math.cos(x + phi)) + math.sin(x)*(y2 - c*math.sin(x + phi)) - math.sqrt((x2 - c*math.cos(x + phi))^2 + (y2 - c*math.sin(x + phi))^2)
		end
		local Pitch = math.deg(Math:NewtonsMethod(f, 0.001, 0, 0.001))
		
		local YawCenter = BaseAttach.CFrame.Rotation + YawAttach.Position
		local YawOffset = YawCenter:ToObjectSpace(CFrame.new(Position))
		local Yaw = math.deg(math.atan2(YawOffset.X, -YawOffset.Z))
		
		--//Pitch
		local DeltaPitch = Math:BoundTo180(Pitch - OldPitch)
		Rotation[1] = OldPitch + math.sign(DeltaPitch) * math.min(
			Settings["Speed"] * Delta,
			math.abs(DeltaPitch)
		)
		
		--//Yaw
		local DeltaYaw = Math:BoundTo180(Yaw - OldYaw)
		Rotation[2] = OldYaw + math.sign(DeltaYaw) * math.min(
			Settings["Speed"] * Delta,
			math.abs(DeltaYaw)
		)
	end
	
	--//Yaw gap
	local DeltaYaw = Math:BoundTo180(Rotation[2] - OldBaseYaw)
	if math.abs(DeltaYaw) < Settings["YawGap"] then
		Rotation[2] = OldBaseYaw
		Rotation[3] = DeltaYaw
	elseif DeltaYaw > 0 then
		Rotation[2] -= Settings["YawGap"]
		Rotation[3] = Settings["YawGap"]
	elseif DeltaYaw < 0 then
		Rotation[2] += Settings["YawGap"]
		Rotation[3] = -Settings["YawGap"]
	end
	
	--//Bound values
	Rotation[1] = math.clamp(
		Rotation[1],
		Settings["PitchLimits"].X,
		Settings["PitchLimits"].Y
	)
	if YawNoLimits then
		Rotation[2] = Math:BoundTo180(Rotation[2])
	else
		Rotation[2] = math.clamp(
			Rotation[2],
			Settings["YawLimits"].X,
			Settings["YawLimits"].Y
		)
	end
	
	--//Welds
	BaseYawWeld.C0 = CFrame.fromOrientation(0, math.rad(Rotation[2]), 0)
	YawWeld.C0 = CFrame.fromOrientation(0, math.rad(Rotation[3]), 0)
	PitchWeld.C0 = CFrame.fromOrientation(math.rad(-Rotation[1]), 0, 0)
	WeldEvent:FireServer(
		{["Weld"] = BaseYawWeld, ["C0"] = BaseYawWeld.C0},
		{["Weld"] = YawWeld, ["C0"] = YawWeld.C0},
		{["Weld"] = PitchWeld, ["C0"] = PitchWeld.C0}
	)
end)
