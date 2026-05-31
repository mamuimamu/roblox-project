--[[
	放水銃コントローラー（Client / LocalScript）
	RescueVehicle の運転席に着座中、左クリック長押し（またはタップ）で
	水粒子を放出し、WaterCannonFire RemoteEvent でサーバーへ射撃を通知する。
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera
local mouse  = player:GetMouse()

local WaterCannonFire   = ReplicatedStorage:WaitForChild("WaterCannonFire")
local WaterCannonEffect = ReplicatedStorage:WaitForChild("WaterCannonEffect")

local function isInRescueSeat()
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

local function getMuzzleEmitter()
	local rv = Workspace:FindFirstChild("RescueVehicle")
	if not rv then return nil end
	local muzzle = rv:FindFirstChild("WaterCannonMuzzle", true)
	if not muzzle then return nil end
	return muzzle:FindFirstChildOfClass("ParticleEmitter")
end

local function emitParticles()
	local emitter = getMuzzleEmitter()
	if emitter then
		emitter:Emit(14)
	end
end

-- サーバーから「放水エフェクト配信」を受け取ったとき（他プレイヤー分も含む）
WaterCannonEffect.OnClientEvent:Connect(emitParticles)

-- 入力状態
local isFiring = false
local lastFireTime = 0
local FIRE_INTERVAL = 0.1

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.UserInputType == Enum.UserInputType.MouseButton1
	or input.UserInputType == Enum.UserInputType.Touch then
		isFiring = true
	end
end)

UserInputService.InputEnded:Connect(function(input, _)
	if input.UserInputType == Enum.UserInputType.MouseButton1
	or input.UserInputType == Enum.UserInputType.Touch then
		isFiring = false
	end
end)

RunService.Heartbeat:Connect(function()
	if not isFiring then return end
	if not isInRescueSeat() then return end

	local now = tick()
	if now - lastFireTime < FIRE_INTERVAL then return end
	lastFireTime = now

	-- 操作プレイヤーには即時ローカル描画（レスポンス向上）
	emitParticles()

	-- マウスカーソル位置を通るスクリーン Ray をサーバーへ送信
	local ray = camera:ScreenPointToRay(mouse.X, mouse.Y)
	WaterCannonFire:FireServer(ray.Origin, ray.Direction)
end)
