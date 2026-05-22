local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Shared内にあるGameConfigモジュールを取得
local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))

-- 消防車のモデルと関連パーツを取得
local vehicle = Workspace:WaitForChild("RescueVehicle")
local mainBody = vehicle:WaitForChild("MainBody")
local seat = vehicle:WaitForChild("VehicleSeat")
local prompt = mainBody:WaitForChild("ProximityPrompt")

-- ProximityPromptがトリガーされた時の処理
prompt.Triggered:Connect(function(player)
    local character = player.Character
    if character then
        local humanoid = character:FindFirstChildOfClass("Humanoid")
        if humanoid then
            -- Configから値を読み取ってVehicleSeatに設定
            seat.MaxSpeed = GameConfig.TruckMaxSpeed
            seat.TurnSpeed = GameConfig.TruckSteerSpeed
            
            -- プレイヤーを座らせる
            seat:Sit(humanoid)
        end
    end
end)
