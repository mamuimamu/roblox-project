--[[
	VehicleSeat の WASD 操作（PlayerModule がない環境向け）
	Heartbeat ごとに Throttle / Steer をセットする。
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local humanoid

-- ── 降車ボタン（モバイル向け） ───────────────────────────────

local exitGui = Instance.new("ScreenGui")
exitGui.Name = "ExitVehicleGui"
exitGui.ResetOnSpawn = false
exitGui.Parent = playerGui

local exitBtn = Instance.new("TextButton")
exitBtn.Size = UDim2.new(0, 110, 0, 50)
exitBtn.AnchorPoint = Vector2.new(1, 1)
exitBtn.Position = UDim2.new(1, -16, 1, -16)
exitBtn.BackgroundColor3 = Color3.fromRGB(200, 60, 30)
exitBtn.BorderSizePixel = 0
exitBtn.Font = Enum.Font.GothamBold
exitBtn.TextSize = 20
exitBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
exitBtn.Text = "降りる"
exitBtn.Visible = false
exitBtn.Parent = exitGui

local exitCorner = Instance.new("UICorner")
exitCorner.CornerRadius = UDim.new(0, 10)
exitCorner.Parent = exitBtn

exitBtn.MouseButton1Click:Connect(function()
	if humanoid then humanoid.Sit = false end
end)

local function updateExitButton()
	if not humanoid then exitBtn.Visible = false; return end
	local seat = humanoid.SeatPart
	exitBtn.Visible = (seat ~= nil and seat:IsA("VehicleSeat"))
end

local function refreshHumanoid(character)
	humanoid = character:WaitForChild("Humanoid")
	updateExitButton()
	humanoid:GetPropertyChangedSignal("SeatPart"):Connect(updateExitButton)
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
