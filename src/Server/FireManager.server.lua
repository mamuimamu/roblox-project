--[[
	FireManager（Server / Script）
	消防車の配備ボタンを管理する。
	火事・ウェーブ管理は BurningHouseManager が担う。
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")

local Shared     = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))

local TRUCK_SIZE            = Vector3.new(8, 3, 14)
local TRUCK_SPAWN_POSITION  = Vector3.new(0, 4, 20)
local TRUCK_BUTTON_POSITION = Vector3.new(0, 0.25, 10)

local function createRescueVehicle()
	local model = Instance.new("Model")
	model.Name = "RescueVehicle"

	local seat = Instance.new("VehicleSeat")
	seat.Name = "DriverSeat"
	seat.Size = TRUCK_SIZE
	seat.MaxSpeed = GameConfig.TruckMaxSpeed
	seat.TurnSpeed = GameConfig.TruckSteerSpeed
	seat.BrickColor = BrickColor.new("Really red")
	seat.Material = Enum.Material.SmoothPlastic
	seat.Anchored = false
	seat.CanCollide = true
	seat.CFrame = CFrame.new(TRUCK_SPAWN_POSITION)
	seat.CustomPhysicalProperties = PhysicalProperties.new(0.01, 0.1, 0, 1, 1)
	seat.Parent = model
	model.PrimaryPart = seat

	local boardPrompt = Instance.new("ProximityPrompt")
	boardPrompt.ObjectText = "消防車"
	boardPrompt.ActionText = "運転する"
	boardPrompt.HoldDuration = 0
	boardPrompt.MaxActivationDistance = 12
	boardPrompt.RequiresLineOfSight = false
	boardPrompt.Parent = seat

	seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		boardPrompt.Enabled = (seat.Occupant == nil)
	end)

	boardPrompt.Triggered:Connect(function(player)
		if seat.Occupant ~= nil then return end
		local character = player.Character
		if not character then return end
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			seat:Sit(humanoid)
		end
	end)

	model.Parent = Workspace
	print("[Server] FireManager: 消防車を配備しました。")
	return model
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
		if isSpawning or Workspace:FindFirstChild("RescueVehicle") then return end
		local character = otherPart.Parent
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not humanoid then return end
		isSpawning = true
		createRescueVehicle()
		isSpawning = false
	end)
end

createFireTruckSpawnButton()

print("[Server] FireManager: 消防車ボタンを配置しました。")
