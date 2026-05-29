--[[
	既存の RescueVehicle モデルに ProximityPrompt を追加し、
	プロンプト起動時にプレイヤーを Chassis.VehicleSeat に着座させる。
	GameConfig の速度パラメータを VehicleSeat に適用する。
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))

local function setupRescueVehicle(vehicle)
	local chassis = vehicle:FindFirstChild("Chassis")
	if not chassis then
		warn("[VehiclePromptHandler] Chassis が見つかりません: " .. vehicle:GetFullName())
		return
	end

	local seat = chassis:FindFirstChild("VehicleSeat")
	if not seat or not seat:IsA("VehicleSeat") then
		warn("[VehiclePromptHandler] VehicleSeat が見つかりません")
		return
	end

	-- Chassis モジュールが読む Attribute で速度・トルクを制御する
	-- （VehicleSeat.MaxSpeed はこの車両では効かない）
	vehicle:SetAttribute("MaxSpeed",     GameConfig.RescueTruckMaxSpeed)
	vehicle:SetAttribute("DrivingTorque", GameConfig.RescueTruckTorque)

	-- 既存の ProximityPrompt があれば再利用、なければ新規作成
	local prompt = seat:FindFirstChildOfClass("ProximityPrompt")
	if not prompt then
		local promptLocation = seat:FindFirstChild("PromptLocation")
		prompt = Instance.new("ProximityPrompt")
		prompt.Parent = promptLocation or seat
	end

	prompt.ObjectText = "消防車"
	prompt.ActionText = "運転する"
	prompt.HoldDuration = 0.5
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false

	local function updatePromptState()
		prompt.Enabled = (seat.Occupant == nil)
			and (vehicle:GetAttribute("VehiclePurchased") == true)
	end
	seat:GetPropertyChangedSignal("Occupant"):Connect(updatePromptState)
	vehicle:GetAttributeChangedSignal("VehiclePurchased"):Connect(updatePromptState)
	updatePromptState()

	prompt.Triggered:Connect(function(player)
		if seat.Occupant ~= nil then return end
		local character = player.Character
		if not character then return end
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			seat:Sit(humanoid)
		end
	end)

	print("[VehiclePromptHandler] RescueVehicle セットアップ完了 (MaxSpeed=" .. GameConfig.RescueTruckMaxSpeed .. "mph, Torque=" .. GameConfig.RescueTruckTorque .. ")")
end

local existing = Workspace:FindFirstChild("RescueVehicle")
if existing then
	setupRescueVehicle(existing)
else
	Workspace.ChildAdded:Connect(function(child)
		if child.Name == "RescueVehicle" then
			task.wait(0.1)
			setupRescueVehicle(child)
		end
	end)
	print("[VehiclePromptHandler] RescueVehicle を待機中...")
end
