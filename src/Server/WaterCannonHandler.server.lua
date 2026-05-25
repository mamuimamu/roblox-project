--[[
	放水銃システム（Server / Script）
	クライアントから WaterCannonFire RemoteEvent を受け取り、サーバー側レイキャストで
	FirePart を判定・消火する。視覚エフェクトは WaterCannonEffect で全クライアントに配信。
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")

local Shared     = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))

local WaterCannonFire = Instance.new("RemoteEvent")
WaterCannonFire.Name  = "WaterCannonFire"
WaterCannonFire.Parent = ReplicatedStorage

local WaterCannonEffect = Instance.new("RemoteEvent")
WaterCannonEffect.Name  = "WaterCannonEffect"
WaterCannonEffect.Parent = ReplicatedStorage

local function getRescueVehicle()
	return Workspace:FindFirstChild("RescueVehicle")
end

local function getRescueSeat()
	local rv = getRescueVehicle()
	if not rv then return nil end
	local chassis = rv:FindFirstChild("Chassis")
	return chassis and chassis:FindFirstChild("VehicleSeat")
end

local function isPlayerInRescueSeat(player)
	local seat = getRescueSeat()
	if not seat then return false end
	local char = player.Character
	if not char then return false end
	local hum = char:FindFirstChildOfClass("Humanoid")
	return hum ~= nil and seat.Occupant == hum
end

-- ───────────────────────────────
-- 連続ヒット管理
-- ───────────────────────────────
local fireHitState = {}  -- [firePart] = { startTime, lastHitTime, lastPrintedSec }
local HIT_RESET_GAP = 0.5

local function addScore(player)
	local ls = player:FindFirstChild("leaderstats")
	if not ls then return end
	local fires = ls:FindFirstChild("Fires")
	if fires and fires:IsA("IntValue") then
		fires.Value += GameConfig.PointsPerFire
	end
end

local function trackWaterHit(firePart, player)
	local now   = tick()
	local state = fireHitState[firePart]

	if state == nil then
		fireHitState[firePart] = {
			startTime      = now,
			lastHitTime    = now,
			lastPrintedSec = 0,
			lastPlayer     = player,
		}
		print("[WCH] 消火開始！ (目標: " .. tostring(firePart.Position) .. ")")
		firePart.Destroying:Connect(function()
			fireHitState[firePart] = nil
		end)
		return
	end

	if (now - state.lastHitTime) >= HIT_RESET_GAP then
		-- 途切れたらリセット
		state.startTime      = now
		state.lastHitTime    = now
		state.lastPrintedSec = 0
		state.lastPlayer     = player
		print("[WCH] 消火タイマーリセット（" .. string.format("%.1f", now - state.lastHitTime) .. "秒の空白）")
		return
	end

	-- 連続ヒット中
	state.lastHitTime = now
	state.lastPlayer  = player
	local elapsed = now - state.startTime

	-- 1 秒ごとに進行ログ
	local sec = math.floor(elapsed)
	if sec > state.lastPrintedSec then
		state.lastPrintedSec = sec
		print(string.format("[WCH] 消火進行 %d / %d 秒", sec, GameConfig.WaterCannonExtinguishTime))
	end

	if elapsed >= GameConfig.WaterCannonExtinguishTime then
		print("[WCH] 消火完了！ スコア加算 → " .. player.Name)
		fireHitState[firePart] = nil
		addScore(player)
		firePart:Destroy()
	end
end

-- ───────────────────────────────
-- レイキャスト用 FirePart 収集
-- ───────────────────────────────
local function collectFireParts()
	local list = {}
	for _, child in ipairs(Workspace:GetChildren()) do
		if child:IsA("BasePart") and child.Name == "FirePart" then
			table.insert(list, child)
		end
	end
	return list
end

-- ───────────────────────────────
-- メインイベントハンドラ（レート制限は inSeat ログのみ）
-- ───────────────────────────────
local lastSeatLog = 0

WaterCannonFire.OnServerEvent:Connect(function(player, camPos, direction)
	if typeof(camPos) ~= "Vector3" or typeof(direction) ~= "Vector3" then return end
	if direction.Magnitude < 1e-4 then return end

	local inSeat = isPlayerInRescueSeat(player)

	-- inSeat 確認ログは 2 秒に 1 回だけ
	local now = tick()
	if now - lastSeatLog >= 2 then
		lastSeatLog = now
		local seat = getRescueSeat()
		local occ  = seat and seat.Occupant
		print(string.format("[WCH] inSeat=%s  occupant=%s",
			tostring(inSeat),
			occ and occ.Parent and occ.Parent.Name or "nil"))
	end

	if not inSeat then return end

	WaterCannonEffect:FireAllClients()

	direction = direction.Unit

	local fireParts = collectFireParts()
	if #fireParts == 0 then
		print("[WCH] WARNING: Workspace に FirePart が 1 つもありません")
		return
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = fireParts

	local result = Workspace:Raycast(camPos, direction * GameConfig.WaterCannonRange, params)
	if not result then return end

	-- 車体の前方半球チェック：放水銃から見てマイナス方向（背後）の火は却下
	local seat = getRescueSeat()
	if seat then
		local dirToFire = (result.Position - seat.CFrame.Position).Unit
		if seat.CFrame.LookVector:Dot(dirToFire) < 0 then
			return
		end
	end

	-- Include フィルタなので result.Instance は必ず FirePart
	trackWaterHit(result.Instance, player)
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
