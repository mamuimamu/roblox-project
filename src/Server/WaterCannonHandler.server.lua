--[[
	放水銃システム（Server / Script）
	クライアントから WaterCannonFire RemoteEvent を受け取り、サーバー側レイキャストで
	FirePart を判定・消火する。視覚エフェクトは WaterCannonEffect で全クライアントに配信。
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")


-- 既存のイベントを再利用し、重複作成を防ぐ
local function getOrCreate(name)
	local existing = ReplicatedStorage:FindFirstChild(name)
	if existing and existing:IsA("RemoteEvent") then return existing end
	local e = Instance.new("RemoteEvent")
	e.Name   = name
	e.Parent = ReplicatedStorage
	return e
end

local WaterCannonFire   = getOrCreate("WaterCannonFire")
local WaterCannonEffect = getOrCreate("WaterCannonEffect")

local function getRescueVehicle()
	return Workspace:FindFirstChild("RescueVehicle")
end

local function isPlayerInRescueSeat(player)
	local char = player.Character
	if not char then return false end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum then return false end
	local seatPart = hum.SeatPart
	if not seatPart or not seatPart:IsA("VehicleSeat") then return false end
	local chassis = seatPart.Parent
	if not chassis or chassis.Name ~= "Chassis" then return false end
	return chassis.Parent ~= nil and chassis.Parent.Name == "RescueVehicle"
end

-- ───────────────────────────────
-- 連続ヒット管理
-- ───────────────────────────────
-- ───────────────────────────────
-- メインイベントハンドラ
-- ───────────────────────────────
WaterCannonFire.OnServerEvent:Connect(function(player, camPos, direction)
	if typeof(camPos) ~= "Vector3" or typeof(direction) ~= "Vector3" then return end
	if direction.Magnitude < 1e-4 then return end

	if not isPlayerInRescueSeat(player) then return end

	-- エフェクトを全クライアントに配信（消火処理は BurningHouseManager が担当）
	WaterCannonEffect:FireAllClients()
end)

-- ───────────────────────────────
-- 放水銃マズルの Attachment + ParticleEmitter をセットアップ
-- ───────────────────────────────
local function setupWaterCannon(vehicle)
	if vehicle:FindFirstChild("WaterCannonMuzzle", true) then return end

	local body = vehicle:FindFirstChild("Body")
	local anchorPart = (body and body:FindFirstChild("Center"))
		or (vehicle:FindFirstChild("Chassis") and vehicle.Chassis:FindFirstChild("VehicleSeat"))

	if not anchorPart then
		warn("[WaterCannonHandler] アンカーパーツが見つかりません")
		return
	end

	local att = Instance.new("Attachment")
	att.Name  = "WaterCannonMuzzle"
	att.CFrame = CFrame.new(0, 1, -anchorPart.Size.Z * 0.5) * CFrame.Angles(-math.pi / 2, 0, 0)
	att.Parent = anchorPart

	local emitter = Instance.new("ParticleEmitter")
	emitter.Name   = "WaterSpray"
	emitter.Color  = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(170, 220, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(80,  160, 255)),
	})
	emitter.LightEmission  = 0.15
	emitter.LightInfluence = 0.8
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0,   0.45, 0),
		NumberSequenceKeypoint.new(0.5, 0.28, 0),
		NumberSequenceKeypoint.new(1,   0.05, 0),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0,   0.1, 0),
		NumberSequenceKeypoint.new(0.6, 0.5, 0),
		NumberSequenceKeypoint.new(1,   1.0, 0),
	})
	emitter.Speed       = NumberRange.new(45, 65)
	emitter.SpreadAngle = Vector2.new(4, 4)
	emitter.Lifetime    = NumberRange.new(0.8, 1.6)
	emitter.Rate        = 0
	emitter.RotSpeed    = NumberRange.new(-30, 30)
	emitter.Rotation    = NumberRange.new(0, 360)
	emitter.Parent      = att

	print("[WaterCannonHandler] 放水銃セットアップ完了 | アンカー: " .. anchorPart.Name)
end

local existing = getRescueVehicle()
if existing then
	task.wait(1)
	setupWaterCannon(existing)
else
	Workspace.ChildAdded:Connect(function(child)
		if child.Name == "RescueVehicle" then
			task.wait(1)
			setupWaterCannon(child)
		end
	end)
end

print("[WaterCannonHandler] 起動完了")
