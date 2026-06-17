--[[
	RescueVehicle のセットアップとスポーン/デスポーン管理。
	ゲーム開始時は ServerStorage に退避し、
	購入後に VehicleSpawnEvent でスポーン/回収できる。
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage     = game:GetService("ServerStorage")
local Workspace         = game:GetService("Workspace")

local Shared     = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))

local vehicleSpawned = false
local originalCFrame = nil
local vehicle        = nil
local seat           = nil
local prompt         = nil

-- ── RemoteEvent / RemoteFunction ─────────────────────────────

local function getOrCreate(name, cls)
	local existing = ReplicatedStorage:FindFirstChild(name)
	if existing and existing:IsA(cls) then return existing end
	local obj = Instance.new(cls)
	obj.Name   = name
	obj.Parent = ReplicatedStorage
	return obj
end

local VehicleSpawnEvent  = getOrCreate("VehicleSpawnEvent",  "RemoteEvent")
local VehicleStateEvent  = getOrCreate("VehicleStateEvent",  "RemoteEvent")
local BoardVehicleEvent  = getOrCreate("BoardVehicleEvent",  "RemoteEvent")
local GetVehicleState    = getOrCreate("GetVehicleState",    "RemoteFunction")

-- ── プロンプト状態更新 ────────────────────────────────────────

local function updatePromptState()
	if not prompt then return end
	prompt.Enabled = vehicleSpawned
		and (seat.Occupant == nil)
		and (vehicle:GetAttribute("VehiclePurchased") == true)
end

-- ── セットアップ ─────────────────────────────────────────────

local function setupRescueVehicle(v)
	vehicle = v
	local chassis = vehicle:FindFirstChild("Chassis")
	if not chassis then
		warn("[VehiclePromptHandler] Chassis が見つかりません: " .. vehicle:GetFullName())
		return false
	end

	seat = chassis:FindFirstChild("VehicleSeat")
	if not seat or not seat:IsA("VehicleSeat") then
		warn("[VehiclePromptHandler] VehicleSeat が見つかりません")
		return false
	end

	vehicle:SetAttribute("MaxSpeed",      GameConfig.RescueTruckMaxSpeed)
	vehicle:SetAttribute("DrivingTorque", GameConfig.RescueTruckTorque)

	-- 車両内の全プロンプトを無効化（元モデルに含まれるものも含む）
	for _, desc in vehicle:GetDescendants() do
		if desc:IsA("ProximityPrompt") then
			desc.Enabled = false
		end
	end

	-- seat 配下を再帰検索してプロンプトを1本に統一、なければ新規作成
	prompt = nil
	for _, desc in seat:GetDescendants() do
		if desc:IsA("ProximityPrompt") then
			prompt = desc
			break
		end
	end
	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.Parent = seat:FindFirstChild("PromptLocation") or seat
	end

	prompt.ObjectText             = "消防車"
	prompt.ActionText             = "運転する"
	prompt.HoldDuration           = 0.5
	prompt.MaxActivationDistance  = 10
	prompt.RequiresLineOfSight    = false
	prompt.Enabled                = false

	seat:GetPropertyChangedSignal("Occupant"):Connect(updatePromptState)

	-- 車両モデルの購入フラグ変化は promptState のみ更新する
	-- クライアントへの通知は BurningHouseManager の ShopBuyEvent が per-player で行う
	vehicle:GetAttributeChangedSignal("VehiclePurchased"):Connect(function()
		updatePromptState()
	end)

	prompt.Triggered:Connect(function(player)
		if seat.Occupant ~= nil then return end
		local character = player.Character
		if not character then return end
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then seat:Sit(humanoid) end
	end)

	return true
end

-- ── スポーン / デスポーン ─────────────────────────────────────

local function spawnVehicle(player)
	if vehicleSpawned or not vehicle then return end

	local spawnCF = originalCFrame
	if player and player.Character then
		local root = player.Character:FindFirstChild("HumanoidRootPart")
		if root then
			local flat = root.CFrame.LookVector * Vector3.new(1, 0, 1)
			if flat.Magnitude > 0.01 then
				flat = flat.Unit
				local pos = Vector3.new(
					root.Position.X + flat.X * 15,
					originalCFrame.Position.Y,
					root.Position.Z + flat.Z * 15
				)
				spawnCF = CFrame.lookAt(pos, pos + flat)
			end
		end
	end

	vehicle:PivotTo(spawnCF)
	vehicle.Parent = Workspace
	vehicleSpawned = true
	updatePromptState()
	-- スポーン通知: 購入済みプレイヤーのみにボタン表示を更新する
	local Players = game:GetService("Players")
	for _, plr in Players:GetPlayers() do
		local vp = plr:GetAttribute("VehiclePurchased") == true
		VehicleStateEvent:FireClient(plr, true, vp)
	end
	print("[VehiclePromptHandler] 消防車をスポーン")
end

local function despawnVehicle()
	if not vehicleSpawned or not vehicle then return end
	vehicle.Parent = ServerStorage
	vehicleSpawned = false
	updatePromptState()
	local Players = game:GetService("Players")
	for _, plr in Players:GetPlayers() do
		local vp = plr:GetAttribute("VehiclePurchased") == true
		VehicleStateEvent:FireClient(plr, false, vp)
	end
	print("[VehiclePromptHandler] 消防車を格納")
end

-- ── RemoteFunction / Event ハンドラ ──────────────────────────

-- GetVehicleState: プレイヤー個人の購入フラグを返す（per-player）
GetVehicleState.OnServerInvoke = function(player)
	local purchased = player:GetAttribute("VehiclePurchased") == true
	return vehicleSpawned and purchased, purchased
end

VehicleSpawnEvent.OnServerEvent:Connect(function(player, shouldSpawn)
	-- このプレイヤー自身が購入済みかチェック（per-player）
	local purchased = player:GetAttribute("VehiclePurchased") == true
	if not purchased then return end
	if shouldSpawn then
		spawnVehicle(player)
	else
		despawnVehicle()
	end
end)

-- モバイル「乗る」ボタンからの乗車リクエスト
local BOARD_MAX_DIST = 18  -- 乗車可能距離（スタッズ）
BoardVehicleEvent.OnServerEvent:Connect(function(player)
	if not vehicleSpawned or not vehicle or not seat then return end
	if vehicle:GetAttribute("VehiclePurchased") ~= true then return end
	if seat.Occupant ~= nil then return end
	local char = player.Character
	if not char then return end
	local root = char:FindFirstChild("HumanoidRootPart")
	if not root then return end
	-- 距離チェック（不正防止）
	if (root.Position - seat.Position).Magnitude > BOARD_MAX_DIST then return end
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	if humanoid then seat:Sit(humanoid) end
end)

-- ── 初期化 ───────────────────────────────────────────────────

local v = Workspace:FindFirstChild("RescueVehicle")
if not v then
	warn("[VehiclePromptHandler] RescueVehicle が Workspace にありません")
else
	if setupRescueVehicle(v) then
		originalCFrame = vehicle:GetPivot()
		vehicle.Parent = ServerStorage
		vehicleSpawned = false
		updatePromptState()
		print("[VehiclePromptHandler] RescueVehicle セットアップ完了（格納済み）")
	end
end
