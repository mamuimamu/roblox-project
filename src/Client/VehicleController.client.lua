--[[
	VehicleSeat の WASD 操作（PlayerModule がない環境向け）
	Heartbeat ごとに Throttle / Steer をセットする。
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local humanoid

local function refreshHumanoid(character)
	humanoid = character:WaitForChild("Humanoid")
end

local character = player.Character
if character then refreshHumanoid(character) end
player.CharacterAdded:Connect(refreshHumanoid)

RunService.Heartbeat:Connect(function()
	if not humanoid then return end
	local seat = humanoid.SeatPart
	if not seat or not seat:IsA("VehicleSeat") then return end

	local throttle = 0
	local steer = 0

	if UserInputService:IsKeyDown(Enum.KeyCode.W) then throttle = 1
	elseif UserInputService:IsKeyDown(Enum.KeyCode.S) then throttle = -1 end

	if UserInputService:IsKeyDown(Enum.KeyCode.A) then steer = -1
	elseif UserInputService:IsKeyDown(Enum.KeyCode.D) then steer = 1 end

	seat.Throttle = throttle
	seat.Steer = steer
end)
