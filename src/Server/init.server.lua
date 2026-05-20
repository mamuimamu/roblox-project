print("[Server] 救助ゲームシステムが起動しました。")

-- 共有モジュールの読み込み
local SharedModule = require(game:GetService("ReplicatedStorage").Shared:WaitForChild("Config"))
print("[Server] 共通設定を読み込みました。ゲーム名: " .. SharedModule.GameName)

-- 消防車を出現させるボタンの生成ロジック
local function createSpawnButton()
    local button = Instance.new("Part")
    button.Name = "FireTruckButton"
    button.Size = Vector3.new(4, 0.5, 4)
    button.Position = Vector3.new(0, 0.25, 10) -- スポーン地点の少し前方
    button.BrickColor = BrickColor.new("Bright red") -- 消防カラー
    button.Anchored = true
    button.Material = Enum.Material.Neon
    button.Parent = workspace

    -- ボタン接触イベント
    button.Touched:Connect(function(otherPart)
        local character = otherPart.Parent
        local humanoid = character:FindFirstChildOfClass("Humanoid")

        -- 踏んだのがプレイヤーキャラ、かつまだ消防車が出ていない場合
        if humanoid and not workspace:FindFirstChild("RescueVehicle") then
            print("[Server] プレイヤーがボタンを踏みました！消防車を配備します。")

            -- 簡易的な消防車（赤い大きなブロック）を生成
            local truck = Instance.new("Part")
            truck.Name = "RescueVehicle"
            truck.Size = Vector3.new(6, 5, 12)
            truck.Position = Vector3.new(0, 3, 20) -- ボタンのさらに奥に出現
            truck.BrickColor = BrickColor.new("Really red")
            truck.Material = Enum.Material.SmoothPlastic
            truck.Parent = workspace
        end
    end)
end

createSpawnButton()