local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FirstPersonTool = require(ReplicatedStorage.Modules.FirstPersonTool)
local ReticleManager = require(ReplicatedStorage.Modules.ReticleManager)
local MasterInput = require(ReplicatedStorage.Modules.MasterInput)
local Mouse = require(ReplicatedStorage.Modules.Mouse)
local Math = require(ReplicatedStorage.Modules.Math)
local Settings = require(script:WaitForChild("Settings").Value)

local Player = Players.LocalPlayer
local Blacklist = {Player.Character, Settings["Vehicle"] or Settings["Turret"]}
local Params = RaycastParams.new()
Params.FilterType = Enum.RaycastFilterType.Exclude
Params.FilterDescendantsInstances = Blacklist

local WeldEvent = Settings["Turret"]:WaitForChild("WeldEvent")
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
local OldBaseRot = nil
local MouseInfo = {
	["UseTouchCenter"] = true
}

while FirstPersonTool.State.FakeModel do
	task.wait()
end
local Model = Settings["Turret"]:FindFirstChild("Model")
local Base = Model and Model:FindFirstChild("Base")
local NormalCamera = Settings["NormalCamera"] or (Base and Base:FindFirstChild("NormalCamera"))
local MobileCamera = Settings["MobileCamera"] or (Base and Base:FindFirstChild("MobileCamera"))
if MobileCamera and Player.PlayerGui:FindFirstChild("TouchGui") then
	FirstPersonTool.SetSubject_3rd(MobileCamera)
elseif NormalCamera then
	FirstPersonTool.SetSubject_3rd(NormalCamera)
end

local Pitch = Model and Model:FindFirstChild("Pitch")
local FirstPerson = Pitch and Pitch:FindFirstChild("FirstPerson")
if FirstPerson then
	Settings["SightsPart"] = Pitch:FindFirstChild("Sights")
	FirstPersonTool.SetSubject_FPS(FirstPerson)
	FirstPersonTool.AimDown.Connect(Settings)
end

if Barrel then
	ReticleManager:Add(Barrel, Params)
end

BaseYawWeld:SetAttribute("ClientWeld", true)
YawWeld:SetAttribute("ClientWeld", true)
PitchWeld:SetAttribute("ClientWeld", true)

local Seat = Settings["Seat"]
if Seat then
	local PlayerValue = Seat:WaitForChild("PlayerValue")
	PlayerValue:GetPropertyChangedSignal("Value"):Connect(function()
		if not PlayerValue.Value then
			FirstPersonTool.SetSubject_3rd(nil)
			FirstPersonTool.SetSubject_FPS(nil)
			ReticleManager:Remove(Barrel)
			BaseYawWeld:SetAttribute("ClientWeld", nil)
			YawWeld:SetAttribute("ClientWeld", nil)
			PitchWeld:SetAttribute("ClientWeld", nil)
			script:Destroy()
		end
	end)
end

local Offset = YawAttach.CFrame:ToObjectSpace(PitchAttach.CFrame)
local a = -Offset.Z
local b = Offset.Y
local c = math.sqrt(a ^ 2 + b ^ 2)
local phi = math.atan2(b, a)

--//Must be after simulation since it grabs part.CFrame, works best with PreRender
RunService.PreRender:Connect(function(Delta)
	local OldPitch = Rotation[1]
	local OldYaw = Rotation[2] + Rotation[3]
	local OldBaseYaw = Rotation[2]
	if Player:GetAttribute("FirstPerson") then
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
	
	--//Decouple rotation
	if Player:GetAttribute("DecoupleTurretRotation") then
		local PitchX, YawY, _ = BaseAttach.CFrame:ToOrientation()
		local BaseRot = {
			[1] = math.deg(-PitchX),
			[2] = math.deg(YawY)
		}
		if OldBaseRot then
			Rotation[1] += BaseRot[1] - OldBaseRot[1]
			Rotation[2] += BaseRot[2] - OldBaseRot[2]
		end
		OldBaseRot = BaseRot
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
	local BaseYaw = math.rad(Rotation[2])
	local Yaw = math.rad(Rotation[3])
	local Pitch = math.rad(-Rotation[1])
	BaseYawWeld.C0 = CFrame.fromOrientation(0, BaseYaw, 0)
	YawWeld.C0 = CFrame.fromOrientation(0, Yaw, 0)
	PitchWeld.C0 = CFrame.fromOrientation(Pitch, 0, 0)
	WeldEvent:FireServer(BaseYaw, Yaw, Pitch)
end)
