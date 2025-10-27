local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Basics = require(ReplicatedStorage.Modules.Basics)
local LaunchEvent = script.LaunchEvent

local Module = {}
local Active = {}
local Folder = nil

local DefaultProjectile = script.DefaultProjectile.Value
local function MakeProjectile(Size)
	if DefaultProjectile then
		return DefaultProjectile:Clone()
	else
		local Part = Instance.new("Part")
		Part.BrickColor = BrickColor.new("Cool yellow")
		Part.CastShadow = false
		Part.Material = Enum.Material.Neon
		Part.Anchored = true
		Part.CanCollide = false
		Part.CanTouch = false
		Part.Size = Size
		return Part
	end
end

function Module.EffectDestroy(Projectile)
	local ParticleLifetime = nil
	local Parts = Projectile:GetDescendants()
	table.insert(Parts, Projectile)
	for _, Part in ipairs(Parts) do
		if Part:IsA("BasePart") then
			Part.Transparency = 1
			Part.CanCollide = false
			Part.CanTouch = false
		elseif Part:IsA("ParticleEmitter") then
			Part.Enabled = false
			ParticleLifetime = ParticleLifetime and math.max(Part.Lifetime.Max, ParticleLifetime) or Part.Lifetime.Max
		elseif Part:IsA("BillboardGui") or Part:IsA("Trail") then
			Part:Destroy()
		elseif Part:IsA("Sound") then
			if Part.Looped then
				Part:Destroy()
			elseif Part.Playing then
				local Remaining = Part.TimeLength - Part.TimePosition
				ParticleLifetime = ParticleLifetime and math.max(Remaining, ParticleLifetime) or Remaining
			end
		end
	end
	if ParticleLifetime then
		task.wait(ParticleLifetime)
	end
	Projectile:Destroy()
end

local function GetPosition(Data, Time)
	return Data["Position"] + Data["Velocity"] * Time + 0.5 * Vector3.new(0, -Data["Gravity"], 0) * Time ^ 2
end

local function Cycle(Delta)
	for Index, Data in ipairs(Active) do
		local Projectile = Data["Projectile"]
		local Elapsed = tick() - Data["Start"]
		if Elapsed >= Data["MaxTime"] then
			Projectile:Destroy()
			table.remove(Active, Index)
		else
			local LastPos = GetPosition(Data, math.max(Elapsed - Delta, 0))
			local Position = GetPosition(Data, Elapsed)
			local Rotation = Data["AddRotation"]
			local Spin = Data["Spin"]
			if Spin then
				Rotation *= CFrame.Angles(Spin.X * Elapsed, Spin.Y * Elapsed, Spin.Z * Elapsed)
			end
			if Projectile:IsA("Model") then
				Projectile:SetPrimaryPartCFrame(CFrame.new(Position, LastPos) * Rotation)
			elseif Projectile:IsA("BasePart") then
				Projectile.CFrame = CFrame.new(Position, LastPos) * Rotation
			end
			local Direction = (Position - LastPos).Unit
			local Result = Basics:Raycast(LastPos, Direction * ((Position - LastPos).Magnitude + Data["Radius"]), Data["Parameters"])
			if Result then
				if Data["HitEffect"] then
					local EffectPart = script.HitEffect:Clone()
					EffectPart.CFrame = CFrame.new(Result.Position, Result.Position - Direction)
					EffectPart.Parent = workspace
					for _, Effect in ipairs(EffectPart:GetChildren()) do
						Effect:Emit(Effect.Rate)
					end
					coroutine.wrap(Module.EffectDestroy)(EffectPart)
				end
				if Data["Callback"] then
					coroutine.wrap(Data["Callback"])(Result.Instance, Result.Position, Direction, Result.Normal)
				end
				table.remove(Active, Index)
				Module.EffectDestroy(Projectile)
			end
		end
	end
end

function Module:Launch(Info)
	local Settings = Info["Settings"]["Projectile"]
	local Blacklist = Info["Blacklist"] or {}
	local Parameters = RaycastParams.new()
	Parameters.FilterType = Enum.RaycastFilterType.Exclude
	Parameters.FilterDescendantsInstances = Blacklist
	Parameters:AddToFilter(Folder)
	
	--//Replication
	if RunService:IsClient() and not Info["RenderOnly"] then
		LaunchEvent:FireServer(Info["Settings"]["Module"], Info["Position"], Info["Velocity"], Blacklist, Info["HitEffect"])
	end
	
	--//Setup model
	local Projectile = Settings["Projectile"] and Settings["Projectile"]:Clone() or MakeProjectile(Settings["Size"])
	if Projectile:IsA("BasePart") then
		Projectile.Size = Settings["Size"]
	end
	local Parts = Projectile:GetDescendants()
	table.insert(Parts, Projectile)
	for _, Part in ipairs(Parts) do
		if Part:IsA("BasePart") then
			Part.Anchored = true
		elseif Part:IsA("ParticleEmitter") then
			Part.Enabled = true
		elseif Part:IsA("Motor6D") or Part:IsA("Weld") then
			Part:Destroy()
		end
	end
	Projectile.Parent = Folder
	
	--//Add to loop and set initial position
	local Data = {
		["Projectile"] = Projectile,
		["Start"] = tick() - Settings["Size"].Z / 2 / Info["Velocity"].Magnitude,
		["Parameters"] = Parameters,
		["Position"] = Info["Position"],
		["Velocity"] = Info["Velocity"],
		["Callback"] = Info["Callback"],
		["HitEffect"] = Info["HitEffect"],
		
		["Gravity"] = Settings["Gravity"],
		["Radius"] = Settings["Size"].Z / 2,
		["MaxTime"] = Settings["MaxTime"],
		["AddRotation"] = Settings["AddRotation"] or CFrame.new(),
		["Spin"] = Settings["Spin"]
	}
	table.insert(Active, Data)
	local Position = GetPosition(Data, 0)
	if Projectile:IsA("Model") then
		Projectile:SetPrimaryPartCFrame(CFrame.new(Position, Position - Data["Velocity"]) * Data["AddRotation"])
	elseif Projectile:IsA("BasePart") then
		Projectile.CFrame = CFrame.new(Position, Position - Data["Velocity"]) * Data["AddRotation"]
	end
end

function Module:CharacterLaunch(Info)
	local Character = Players.LocalPlayer.Character
	local Head = Character and Character:FindFirstChild("Head")
	if Head then
		local Parameters = RaycastParams.new()
		Parameters.FilterType = Enum.RaycastFilterType.Exclude
		Parameters.FilterDescendantsInstances = Info["Blacklist"]
		Parameters:AddToFilter(Folder)
		
		--//First check if part is between launch position and head
		local Offset = Info["Position"] - Head.Position
		local Direction = Offset.Unit
		local Result = Basics:Raycast(
			Head.Position,
			Offset,
			Parameters
		)
		if Result then
			if Info["Callback"] then
				coroutine.wrap(Info["Callback"])(Result.Instance, Result.Position, Direction, Result.Normal)
			end
			return
		end
		
		--//Check if part is within hitscan range
		Offset = Info["Velocity"] * 0.1
		Direction = Offset.Unit
		Result = Basics:Raycast(
			Info["Position"],
			Offset,
			Parameters
		)
		if Result then
			if Info["Callback"] then
				coroutine.wrap(Info["Callback"])(Result.Instance, Result.Position, Direction, Result.Normal)
			end
			Info["Callback"] = nil
			Module:Launch(Info)
		else
			Module:Launch(Info)
		end
	end
end

if RunService:IsServer() then
	Folder = Instance.new("Folder", workspace)
	Folder.Name = "Projectiles"
	RunService.Heartbeat:Connect(Cycle)
	
	LaunchEvent.OnServerEvent:Connect(function(Player, ...)
		local Args = {...}
		local Settings = typeof(Args[1]) == "Instance" and Args[1]:IsA("ModuleScript")
		local Position = Settings and typeof(Args[2]) == "Vector3"
		local Velocity = Position and typeof(Args[3]) == "Vector3"
		local Blacklist = Velocity and type(Args[4]) == "table"
		if Blacklist then
			local Character = Player.Character
			local Humanoid = Character and Character:FindFirstChild("Humanoid")
			if Humanoid then
				Humanoid:SetAttribute("HasFired", true)
			end
			for _, Other in ipairs(Players:GetPlayers()) do
				if Other ~= Player then
					LaunchEvent:FireClient(Other, ...)
				end
			end
		end
	end)
elseif RunService:IsClient() then
	Folder = workspace:WaitForChild("Projectiles")
	RunService:BindToRenderStep("Projectiles", Enum.RenderPriority.Last.Value, Cycle)
	
	LaunchEvent.OnClientEvent:Connect(function(...)
		local Args = {...}
		if Args[1] and Args[1].Parent then
			local Settings = require(Args[1])
			if not Settings["Modified"] then
				Settings["Modified"] = true
				for _, Module in ipairs(Settings["Module"]:GetChildren()) do
					if Module:IsA("ModuleScript") and Module.Name == "ModifyStats" then
						local ModifyStats = require(Module)
						ModifyStats(Settings)
					end
				end
			end
			Module:Launch({
				["RenderOnly"] = true,
				["Settings"] = Settings,
				["Position"] = Args[2],
				["Velocity"] = Args[3],
				["Blacklist"] = Args[4],
				["HitEffect"] = Args[5]
			})
		end
	end)
end

return Module
