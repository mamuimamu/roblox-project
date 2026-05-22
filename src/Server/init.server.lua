print("[Server] 救助ゲームシステムが起動しました。")

-- 共有モジュールの読み込み
local SharedModule = require(game:GetService("ReplicatedStorage").Shared:WaitForChild("Config"))
print("[Server] 共通設定を読み込みました。ゲーム名: " .. SharedModule.GameName)

-- 消防車の配備・搭乗は FireManager.server.lua で管理
