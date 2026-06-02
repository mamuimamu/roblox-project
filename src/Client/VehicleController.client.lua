--[[
	VehicleSeat の WASD 操作（PlayerModule がない環境向け）
	Heartbeat ごとに Throttle / Steer をセットする。
	モバイル向けに「乗る」「降りる」ボタンを提供する。
]]

local Players           = game:GetService("Players")
local UserInputService  = game:GetService("UserInputService")
local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local humanoid

local BoardVehicleEvent = ReplicatedStorage:WaitForChild("BoardVehicleEvent")
local VehicleStateEvent = ReplicatedStorage:WaitForChild("VehicleStateEvent")

local BOARD_DIST        = 18   -- 乗るボタンを表示する距離（スタッズ）
local vehicleSpawned    = false
local vehiclePurchased  = false

-- ── GUI（乗る・降りるボタン共通 ScreenGui） ───────────────────

local vehicleGui = Instance.new("ScreenGui")
vehicleGui.Name          = "VehicleGui"
vehicleGui.ResetOnSpawn  = false
vehicleGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
vehicleGui.Parent        = playerGui

-- 降りるボタン
local exitBtn = Instance.new("TextButton")
exitBtn.Size             = UDim2.new(0, 110, 0, 50)
exitBtn.AnchorPoint      = Vector2.new(1, 1)
exitBtn.Position         = UDim2.new(1, -16, 1, -16)
exitBtn.BackgroundColor3 = Color3.fromRGB(200, 60, 30)
exitBtn.BorderSizePixel  = 0
exitBtn.Font             = Enum.Font.GothamBold
exitBtn.TextSize         = 20
exitBtn.TextColor3       = Color3.fromRGB(255, 255, 255)
exitBtn.Text             = "降りる"
exitBtn.Visible          = false
exitBtn.ZIndex           = 5
exitBtn.Parent           = vehicleGui

local exitCorner = Instance.new("UICorner")
exitCorner.CornerRadius = UDim.new(0, 10)
exitCorner.Parent = exitBtn

-- 乗るボタン（降りるボタンの上に配置）
local boardBtn = Instance.new("TextButton")
boardBtn.Size             = UDim2.new(0, 110, 0, 50)
boardBtn.AnchorPoint      = Vector2.new(1, 1)
boardBtn.Position         = UDim2.new(1, -16, 1, -74)
boardBtn.BackgroundColor3 = Color3.fromRGB(30, 140, 60)
boardBtn.BorderSizePixel  = 0
boardBtn.Font             = Enum.Font.GothamBold
boardBtn.TextSize         = 20
boardBtn.TextColor3       = Color3.fromRGB(255, 255, 255)
boardBtn.Text             = "🚒 乗る"
boardBtn.Visible          = false
boardBtn.ZIndex           = 5
boardBtn.Parent           = vehicleGui

local boardCorner = Instance.new("UICorner")
boardCorner.CornerRadius = UDim.new(0, 10)
boardCorner.Parent = boardBtn

-- ── 乗り物の座席を取得 ────────────────────────────────────────

local function getVehicleSeat()
	local v = Workspace:FindFirstChild("RescueVehicle")
	if not v then return nil end
	local chassis = v:FindFirstChild("Chassis")
	if not chassis then return nil end
	return chassis:FindFirstChild("VehicleSeat")
end

-- ── ボタン表示状態の更新 ──────────────────────────────────────

local function updateBoardButton()
	if not humanoid then boardBtn.Visible = false; return end
	-- 乗車中は非表示
	local seatPart = humanoid.SeatPart
	if seatPart and seatPart:IsA("VehicleSeat") then
		boardBtn.Visible = false
		return
	end
	-- 車両が未スポーン/未購入なら非表示
	if not vehicleSpawned or not vehiclePurchased then
		boardBtn.Visible = false
		return
	end
	-- 距離チェック
	local seat = getVehicleSeat()
	if not seat or seat.Occupant ~= nil then
		boardBtn.Visible = false
		return
	end
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root then boardBtn.Visible = false; return end
	boardBtn.Visible = (root.Position - seat.Position).Magnitude <= BOARD_DIST
end

local function updateExitButton()
	if not humanoid then exitBtn.Visible = false; return end
	local seat = humanoid.SeatPart
	exitBtn.Visible = (seat ~= nil and seat:IsA("VehicleSeat"))
end

-- ── ボタン操作 ────────────────────────────────────────────────

boardBtn.MouseButton1Click:Connect(function()
	BoardVehicleEvent:FireServer()
end)

exitBtn.MouseButton1Click:Connect(function()
	if humanoid then humanoid.Sit = false end
end)

-- ── キャラクター接続 ──────────────────────────────────────────

local function refreshHumanoid(character)
	humanoid = character:WaitForChild("Humanoid")
	updateExitButton()
	updateBoardButton()
	humanoid:GetPropertyChangedSignal("SeatPart"):Connect(function()
		updateExitButton()
		updateBoardButton()
	end)
end

local character = player.Character
if character then refreshHumanoid(character) end
player.CharacterAdded:Connect(refreshHumanoid)

-- 車両状態の変化を受信
VehicleStateEvent.OnClientEvent:Connect(function(spawned, purchased)
	vehicleSpawned   = spawned
	vehiclePurchased = purchased
	updateBoardButton()
end)

-- 起動時に現在状態を取得
task.spawn(function()
	local GetVehicleState = ReplicatedStorage:WaitForChild("GetVehicleState", 10)
	if not GetVehicleState then return end
	local spawned, purchased = GetVehicleState:InvokeServer()
	vehicleSpawned   = spawned   or false
	vehiclePurchased = purchased or false
	updateBoardButton()
end)

local boardCheckTimer = 0
RunService.Heartbeat:Connect(function(dt)
	if not humanoid then return end

	-- 「乗る」ボタンの距離チェック（0.2 秒ごとに更新）
	boardCheckTimer += dt
	if boardCheckTimer >= 0.2 then
		boardCheckTimer = 0
		updateBoardButton()
	end

	-- WASD 運転（乗車中のみ）
	local seat = humanoid.SeatPart
	if not seat or not seat:IsA("VehicleSeat") then return end

	local throttle = 0
	local steer    = 0

	if UserInputService:IsKeyDown(Enum.KeyCode.W) then throttle = 1
	elseif UserInputService:IsKeyDown(Enum.KeyCode.S) then throttle = -1 end

	if UserInputService:IsKeyDown(Enum.KeyCode.A) then steer = -1
	elseif UserInputService:IsKeyDown(Enum.KeyCode.D) then steer = 1 end

	seat.Throttle = throttle
	seat.Steer    = steer
end)

-- F キーで降車
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if input.KeyCode ~= Enum.KeyCode.F then return end
	if not humanoid then return end
	local seat = humanoid.SeatPart
	if seat and seat:IsA("VehicleSeat") then
		humanoid.Sit = false
	end
end)
