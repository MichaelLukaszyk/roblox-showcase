local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Basics = require(ReplicatedStorage.Modules.Basics)
local LaunchEvent = script.LaunchEvent
local Module = {}
local Active = {}
local Folder

local DefaultProjectile = script.DefaultProjectile.Value
local DefaultSize = DefaultProjectile and DefaultProjectile.Size or Vector3.new(0.5, 0.5, 2)
local function MakeProjectile()
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
		Part.Size = DefaultSize
		return Part
	end
end

local function GetPosition(Data, Time)
	return Data.Position + Data.Velocity * Time + 0.5 * Vector3.new(0, -Data.Gravity, 0) * Time ^ 2
end

local function MoveProjectile(Projectile, Coord)
	if Projectile:IsA("Model") then
		Projectile:PivotTo(Coord)
	elseif Projectile:IsA("BasePart") then
		Projectile.CFrame = Coord
	end
end

local function Cycle(Delta)
	for Index, Data in ipairs(Active) do
		local Projectile = Data.Projectile
		local Elapsed = tick() - Data.Start
		if Elapsed > Data.MaxTime then
			Projectile:Destroy()
			table.remove(Active, Index)
		else
			--//Move
			local LastPos = GetPosition(Data, math.max(Elapsed - Delta, 0))
			local Position = GetPosition(Data, Elapsed)
			local Rotation = Data.Rotation
			local Spin = Data.Spin
			if Spin then
				Rotation *= CFrame.Angles(Spin.X * Elapsed, Spin.Y * Elapsed, Spin.Z * Elapsed)
			end
			MoveProjectile(Projectile, CFrame.new(Position, LastPos) * Rotation)
			
			--//Impact
			local Offset = Position - LastPos
			local Direction = Offset.Unit
			local Result = Basics:Raycast(LastPos, Direction * (Offset.Magnitude + Data.Radius), Data.Parameters)
			if Result then
				if Data.HitEffect then
					local EffectPart = script.HitEffect:Clone()
					EffectPart.CFrame = CFrame.new(Result.Position, Result.Position - Offset)
					EffectPart.Parent = workspace
					for _, Effect in ipairs(EffectPart:GetChildren()) do
						Effect:Emit(Effect.Rate)
					end
					coroutine.wrap(Module.EffectDestroy)(EffectPart)
				end
				if Data.Callback then
					coroutine.wrap(Data.Callback)(Result.Instance, Result.Position, Direction, Result.Normal)
				end
				table.remove(Active, Index)
				Module.EffectDestroy(Projectile)
			end
		end
	end
end

local function LocalLaunch(Position, Velocity, Settings, Callback, Blacklist, HitEffect)
	local Parameters = RaycastParams.new()
	Parameters.FilterType = Enum.RaycastFilterType.Exclude
	Parameters.FilterDescendantsInstances = Blacklist or {}
	Parameters:AddToFilter(Folder)

	--//Setup model
	local LaunchSettings = Settings.Projectile
	local Projectile
	if LaunchSettings.Projectile then
		Projectile = LaunchSettings.Projectile:Clone()
	elseif LaunchSettings.FindProjectile then
		Projectile = LaunchSettings.FindProjectile():Clone()
	else
		Projectile = MakeProjectile()
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
	local Size = LaunchSettings.Size or (Projectile:IsA("BasePart") and Projectile.Size) or DefaultSize
	local Radius = Size.Z / 2
	local Data = {
		["Projectile"] = Projectile,
		["Parameters"] = Parameters,
		["Position"] = Position,
		["Velocity"] = Velocity,
		["Callback"] = Callback,
		["HitEffect"] = HitEffect,
		["Radius"] = Radius,
		["Start"] = tick() - Radius / Velocity.Magnitude,
		
		--//Copy settings
		["Gravity"] = LaunchSettings.Gravity,
		["MaxTime"] = LaunchSettings.MaxTime,
		["Rotation"] = LaunchSettings.Rotation or CFrame.new(),
		["Spin"] = LaunchSettings.Spin
	}
	table.insert(Active, Data)
	local Position = GetPosition(Data, 0)
	MoveProjectile(Projectile, CFrame.new(Position, Position - Velocity) * Data.Rotation)
	return Projectile
end

function Module.Launch(Position, Velocity, Settings, Callback, Blacklist, HitEffect)
	--//Replication
	if RunService:IsClient() then
		if not Settings.Module then
			warn("Projectile settings does not have associated module!")
		end
		LaunchEvent:FireServer(Position, Velocity, Settings.Module, Blacklist or {}, HitEffect)
	end
	
	return LocalLaunch(Position, Velocity, Settings, Callback, Blacklist, HitEffect)
end

function Module.CharacterLaunch(Position, Velocity, Settings, Callback, Blacklist, HitEffect)
	local Character = Players.LocalPlayer.Character
	local Head = Character and Character:FindFirstChild("Head")
	if Head then
		local Parameters = RaycastParams.new()
		Parameters.FilterType = Enum.RaycastFilterType.Exclude
		Parameters.FilterDescendantsInstances = Blacklist
		Parameters:AddToFilter(Folder)
		
		--//First check if part is between launch position and head
		local Offset = Position - Head.Position
		local Result = Basics:Raycast(Head.Position, Offset, Parameters)
		if Result then
			if Callback then
				coroutine.wrap(Callback)(Result.Instance, Result.Position, Offset.Unit, Result.Normal)
			end
			return
		end
		
		--//Check if part is within hitscan range
		Offset = Velocity * 0.1
		Result = Basics:Raycast(Position, Offset, Parameters)
		if Result and Callback then
			coroutine.wrap(Callback)(Result.Instance, Result.Position, Offset.Unit, Result.Normal)
			Callback = nil
		end
		return Module.Launch(Position, Velocity, Settings, Callback, Blacklist, HitEffect)
	end
end

function Module.EffectDestroy(Model)
	local Lifetime
	local Parts = Model:GetDescendants()
	table.insert(Parts, Model)
	for _, Part in ipairs(Parts) do
		if Part:IsA("BasePart") then
			Part.Transparency = 1
			Part.CanCollide = false
			Part.CanTouch = false
		elseif Part:IsA("ParticleEmitter") then
			Part.Enabled = false
			Lifetime = Lifetime and math.max(Part.Lifetime.Max, Lifetime) or Part.Lifetime.Max
		elseif Part:IsA("BillboardGui") or Part:IsA("Trail") then
			Part:Destroy()
		elseif Part:IsA("Sound") then
			if Part.Looped then
				Part:Destroy()
			elseif Part.Playing then
				local Remaining = Part.TimeLength - Part.TimePosition
				Lifetime = Lifetime and math.max(Remaining, Lifetime) or Remaining
			end
		end
	end
	if Lifetime then
		task.wait(Lifetime)
	end
	Model:Destroy()
end

if RunService:IsServer() then
	Folder = Instance.new("Folder", workspace)
	Folder.Name = "Projectiles"
	RunService.Heartbeat:Connect(Cycle)
	
	--//Position, Velocity, Settings.Module, Blacklist or {}, HitEffect
	local Types = {"Vector3", "Vector3", "Instance", "table", "boolean"}
	LaunchEvent.OnServerEvent:Connect(function(Player, ...)
		local Args = {...}
		for Index, Type in ipairs(Types) do
			if typeof(Args[Index]) ~= Type then
				return
			end
		end
		if Args[3]:IsA("ModuleScript") then
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
	RunService.PreRender:Connect(Cycle)
	
	LaunchEvent.OnClientEvent:Connect(function(...)
		local Args = {...}
		if Args[3] and Args[3].Parent then
			local Settings = require(Args[3])
			if not Settings.Modified then
				Settings.Modified = true
				for _, Module in ipairs(Settings.Module:GetChildren()) do
					if Module:IsA("ModuleScript") and Module.Name == "ModifyStats" then
						local ModifyStats = require(Module)
						ModifyStats(Settings)
					end
				end
			end
			LocalLaunch(Args[1], Args[2], Settings, nil, Args[4], Args[5])
		end
	end)
end

return Module
