--[[
	火の生成・耐久管理・消火判定、消防車の配備（Server / Script）
	クライアントからの ExtinguishEvent を受け取り、サーバー側レイキャストで権威的に判定する。
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))

-- 火の自動生成パラメータ（GameConfig には含めない運用値）
local INITIAL_FIRE_COUNT = 5
local PERIODIC_FIRE_COUNT = 2
local FIRE_SPAWN_INTERVAL = 45
local FIRE_SPAWN_HALF_EXTENT = 40

-- 消防車（低重心・幅広で安定、地面から少し浮かせて配置）
local TRUCK_SIZE = Vector3.new(8, 3, 14)
local TRUCK_SPAWN_POSITION = Vector3.new(0, 4, 20)
local TRUCK_BUTTON_POSITION = Vector3.new(0, 0.25, 10)

local function getOrCreateExtinguishEvent()
	local existing = ReplicatedStorage:FindFirstChild("ExtinguishEvent")
	if existing and existing:IsA("RemoteEvent") then
		return existing
	end

	local event = Instance.new("RemoteEvent")
	event.Name = "ExtinguishEvent"
	event.Parent = ReplicatedStorage
	return event
end

local ExtinguishEvent = getOrCreateExtinguishEvent()

local function createFirePart(position)
	local part = Instance.new("Part")
	part.Name = "FirePart"
	part.Size = Vector3.new(4, 4, 4)
	part.Position = position
	part.Anchored = true
	part.BrickColor = BrickColor.new("Bright red")
	part.Material = Enum.Material.Neon
	part:SetAttribute("FireHealth", GameConfig.FireMaxHealth)
	part.Parent = Workspace
	return part
end

local function randomFirePosition()
	local x = math.random(-FIRE_SPAWN_HALF_EXTENT, FIRE_SPAWN_HALF_EXTENT)
	local z = math.random(-FIRE_SPAWN_HALF_EXTENT, FIRE_SPAWN_HALF_EXTENT)
	return Vector3.new(x, 4, z)
end

local function spawnFires(count)
	for _ = 1, count do
		createFirePart(randomFirePosition())
	end
end

local function resolveFirePart(instance)
	if not instance then
		return nil
	end

	if instance:IsA("BasePart") and instance.Name == "FirePart" then
		return instance
	end

	local ancestor = instance:FindFirstAncestorWhichIsA("BasePart")
	if ancestor and ancestor.Name == "FirePart" then
		return ancestor
	end

	return nil
end

local function isOriginNearPlayer(player, origin)
	local character = player.Character
	if not character then
		return false
	end

	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return false
	end

	-- カメラ原点の誤差を許容（クライアント送信 origin の緩い検証）
	local maxOffset = 25
	return (origin - root.Position).Magnitude <= maxOffset
end

local function addExtinguishScore(player)
	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then
		leaderstats = player:WaitForChild("leaderstats", 5)
	end
	if not leaderstats then
		return
	end

	local fires = leaderstats:FindFirstChild("Fires")
	if fires and fires:IsA("IntValue") then
		fires.Value += GameConfig.PointsPerFire
	end
end

local function applyExtinguishDamage(firePart, player)
	local health = firePart:GetAttribute("FireHealth")
	if typeof(health) ~= "number" then
		firePart:SetAttribute("FireHealth", GameConfig.FireMaxHealth)
		health = GameConfig.FireMaxHealth
	end

	health -= GameConfig.ExtinguisherDamage
	if health <= 0 then
		addExtinguishScore(player)
		firePart:Destroy()
	else
		firePart:SetAttribute("FireHealth", health)
	end
end

local function handleExtinguishRequest(player, origin, direction)
	if typeof(origin) ~= "Vector3" or typeof(direction) ~= "Vector3" then
		return
	end

	if direction.Magnitude < 1e-4 then
		return
	end
	direction = direction.Unit

	if not isOriginNearPlayer(player, origin) then
		return
	end

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude

	local character = player.Character
	if character then
		raycastParams.FilterDescendantsInstances = { character }
	end

	local result = Workspace:Raycast(origin, direction * GameConfig.ExtinguisherRange, raycastParams)
	if not result then
		return
	end

	local firePart = resolveFirePart(result.Instance)
	if not firePart then
		return
	end

	applyExtinguishDamage(firePart, player)
end

ExtinguishEvent.OnServerEvent:Connect(handleExtinguishRequest)

local function createRescueVehicle()
	local truck = Instance.new("Part")
	truck.Name = "RescueVehicle"
	truck.Size = TRUCK_SIZE
	truck.Position = TRUCK_SPAWN_POSITION
	truck.BrickColor = BrickColor.new("Really red")
	truck.Material = Enum.Material.SmoothPlastic
	truck.Anchored = false
	truck.CanCollide = true
	truck.Parent = Workspace

	local driverSeat = Instance.new("VehicleSeat")
	driverSeat.Name = "DriverSeat"
	driverSeat.Size = Vector3.new(2, 1, 2)
	driverSeat.MaxSpeed = GameConfig.TruckMaxSpeed
	driverSeat.TurnSpeed = GameConfig.TruckSteerSpeed
	driverSeat.Anchored = false
	driverSeat.CanCollide = true
	driverSeat.CFrame = truck.CFrame * CFrame.new(0, (TRUCK_SIZE.Y + driverSeat.Size.Y) / 2, 1)
	driverSeat.Parent = truck

	local seatWeld = Instance.new("WeldConstraint")
	seatWeld.Name = "SeatWeld"
	seatWeld.Part0 = truck
	seatWeld.Part1 = driverSeat
	seatWeld.Parent = truck

	local boardPrompt = Instance.new("ProximityPrompt")
	boardPrompt.ObjectText = "消防車"
	boardPrompt.ActionText = "運転する"
	boardPrompt.HoldDuration = 0
	boardPrompt.MaxActivationDistance = 12
	boardPrompt.Parent = truck

	boardPrompt.Triggered:Connect(function(player)
		local character = player.Character
		if not character then
			return
		end

		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			driverSeat:Sit(humanoid)
		end
	end)

	print("[Server] FireManager: 消防車を配備しました。")
	return truck
end

local function createFireTruckSpawnButton()
	local button = Instance.new("Part")
	button.Name = "FireTruckButton"
	button.Size = Vector3.new(4, 0.5, 4)
	button.Position = TRUCK_BUTTON_POSITION
	button.BrickColor = BrickColor.new("Bright red")
	button.Anchored = true
	button.Material = Enum.Material.Neon
	button.CanCollide = true
	button.Parent = Workspace

	local isSpawning = false

	button.Touched:Connect(function(otherPart)
		if isSpawning or Workspace:FindFirstChild("RescueVehicle") then
			return
		end

		local character = otherPart.Parent
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not humanoid then
			return
		end

		isSpawning = true
		createRescueVehicle()
		isSpawning = false
	end)
end

createFireTruckSpawnButton()

spawnFires(INITIAL_FIRE_COUNT)

task.spawn(function()
	while true do
		task.wait(FIRE_SPAWN_INTERVAL)
		spawnFires(PERIODIC_FIRE_COUNT)
	end
end)

print("[Server] FireManager: 消火システムを起動しました。")
