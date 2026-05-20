--[[
	プレイヤー操作と放水ビジュアル（Client / LocalScript）
	クリック方向へレイ情報をサーバーへ送り、消火判定をリクエストする。
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local ExtinguishEvent = ReplicatedStorage:WaitForChild("ExtinguishEvent")

local SPRAY_VISUAL_LENGTH = 18
local SPRAY_VISUAL_DURATION = 0.15

local function createSprayVisual(origin, direction)
	local length = math.min(SPRAY_VISUAL_LENGTH, GameConfig.ExtinguisherRange)
	local midpoint = origin + direction * (length / 2)

	local spray = Instance.new("Part")
	spray.Name = "WaterSprayVisual"
	spray.Anchored = true
	spray.CanCollide = false
	spray.CanQuery = false
	spray.CanTouch = false
	spray.Material = Enum.Material.Glass
	spray.BrickColor = BrickColor.new("Bright blue")
	spray.Transparency = 0.4
	spray.Size = Vector3.new(0.35, 0.35, length)
	spray.CFrame = CFrame.lookAt(midpoint, midpoint + direction)
	spray.Parent = Workspace

	task.delay(SPRAY_VISUAL_DURATION, function()
		if spray.Parent then
			spray:Destroy()
		end
	end)
end

local function getAimRay()
	if not camera then
		camera = Workspace.CurrentCamera
	end
	if not camera then
		return nil, nil
	end

	local mouseLocation = UserInputService:GetMouseLocation()
	local unitRay = camera:ScreenPointToRay(mouseLocation.X, mouseLocation.Y)
	return unitRay.Origin, unitRay.Direction.Unit
end

local function requestExtinguish()
	local origin, direction = getAimRay()
	if not origin or not direction then
		return
	end

	createSprayVisual(origin, direction)
	ExtinguishEvent:FireServer(origin, direction)
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end

	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		requestExtinguish()
	end
end)

print("[Client] ExtinguisherController: 消火操作を有効にしました。")
