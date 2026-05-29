--[[
	GameModeManager（Server / Script）
	ゲームモードを管理する。現在はソロ固定。
	将来: ロビー画面で "solo" / "multi" を選択できるようにする予定。
	  - multi 時の拡張ポイント:
	      - 定員を MaxPlayers > 1 に変更
	      - BurningHouseManager の火災件数をプレイヤー数に応じてスケール
	      - 追加の消防車をスポーンさせるロジック
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared     = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))

-- クライアントがモードを問い合わせるための RemoteFunction
local GetGameMode = ReplicatedStorage:FindFirstChild("GetGameMode")
if not (GetGameMode and GetGameMode:IsA("RemoteFunction")) then
	GetGameMode        = Instance.new("RemoteFunction")
	GetGameMode.Name   = "GetGameMode"
	GetGameMode.Parent = ReplicatedStorage
end
GetGameMode.OnServerInvoke = function()
	return GameConfig.GameMode, GameConfig.MaxPlayers
end

-- ── ソロモード: 定員超過をキック ────────────────────────────

if GameConfig.GameMode == "solo" then
	local function enforceLimit(newPlayer)
		if #Players:GetPlayers() > GameConfig.MaxPlayers then
			newPlayer:Kick(
				"このサーバーはソロプレイ専用です。\n" ..
				"マルチプレイは現在準備中です。"
			)
		end
	end
	Players.PlayerAdded:Connect(enforceLimit)
end

-- ── multi モード用の拡張スタブ（将来実装） ─────────────────
--[[
if GameConfig.GameMode == "multi" then
	-- TODO: ロビー UI の表示、ゲーム開始トリガー、車の追加スポーン など
end
]]

print(("[Server] GameModeManager: モード = %s (最大 %d 名)"):format(
	GameConfig.GameMode, GameConfig.MaxPlayers
))
