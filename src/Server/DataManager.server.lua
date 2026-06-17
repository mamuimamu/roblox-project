--[[
	DataManager（Server / Script）
	プレイヤーデータ（消火件数・ポイント・ウェーブ番号・消防車購入フラグ）の永続セーブ／ロード。

	アーキテクチャ（per-player 方式）:
	  ・購入フラグ（VehiclePurchased）はプレイヤー個人の Attribute に保持する。
	  ・ServerStorage.VehiclePurchased など「グローバル共有変数」は使用しない。
	    → 複数アカウントが同じサーバーに入っても互いのデータを上書きしない。
	  ・player:SetAttribute("DataLoaded", true) をロード完了の合図に使う。
	  ・ActiveWaterBoost/ActiveSpeedBoost は「現在のウェーブ全員に効くチームバフ」なので
	    per-player ではなく ServerStorage に OR ロジックで保持する
	    （誰か1人でも true なら true を維持。2人目の未取得プレイヤーが false で上書きしない）。

	ServerStorage との連携:
	  SaveAllPlayers   (BindableFunction) : セーブを要求
	  LoadedWave       (IntValue)         : BurningHouseManager が起動時に参照するウェーブ番号
	  CurrentWave      (IntValue)         : BurningHouseManager がウェーブ番号を書き込む
	  ActiveWaterBoost (BoolValue)        : 消火強化バフ（OR ロジックで双方向同期）
	  ActiveSpeedBoost (BoolValue)        : スピードブーストバフ（OR ロジックで双方向同期）
]]

local DataStoreService = game:GetService("DataStoreService")
local Players          = game:GetService("Players")
local ServerStorage    = game:GetService("ServerStorage")

local PlayerDataStore = DataStoreService:GetDataStore("PlayerData_v2")  -- v1 から変更してクリーンスタート

-- ── ServerStorage: ウェーブ番号のみ管理 ──────────────────────

-- 複数プレイヤーがいる場合は最も進んでいるウェーブを使用（MAX ロジック）
local function createLoadedWaveMax(wave)
	local existing = ServerStorage:FindFirstChild("LoadedWave")
	if existing then
		if wave > existing.Value then
			existing.Value = wave
		end
	else
		local lw = Instance.new("IntValue")
		lw.Name   = "LoadedWave"
		lw.Value  = wave
		lw.Parent = ServerStorage
	end
end

-- OR セット: 複数プレイヤーがいる場合に「誰か1人でも true なら true を維持」する
-- （バフはチーム全体に効くため、未取得の2人目プレイヤーの false で上書きしない）
local function setStorageBoolOR(name, value)
	local existing = ServerStorage:FindFirstChild(name)
	if existing then
		if value then existing.Value = true end
	else
		local bv = Instance.new("BoolValue")
		bv.Name   = name
		bv.Value  = value
		bv.Parent = ServerStorage
	end
end

-- ── セーブ ──────────────────────────────────────────────────

local function savePlayerData(player)
	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then return end

	local fires  = leaderstats:FindFirstChild("Fires")
	local points = leaderstats:FindFirstChild("Points")

	-- ウェーブ番号は BurningHouseManager が ServerStorage.CurrentWave に書き込む
	local cwVal = ServerStorage:FindFirstChild("CurrentWave")
	local wave  = cwVal and cwVal.Value or 1

	-- 消防車購入フラグはプレイヤー個人の Attribute から読む（per-player）
	local vehiclePurchased = player:GetAttribute("VehiclePurchased") == true

	-- アクティブバフは ServerStorage（BurningHouseManager が同期）から読む（チーム共有）
	local awVal = ServerStorage:FindFirstChild("ActiveWaterBoost")
	local asVal = ServerStorage:FindFirstChild("ActiveSpeedBoost")

	local data = {
		Fires            = fires  and fires.Value  or 0,
		Points           = points and points.Value or 0,
		Wave             = wave,
		VehiclePurchased = vehiclePurchased,
		ActiveWaterBoost = awVal and awVal.Value or false,
		ActiveSpeedBoost = asVal and asVal.Value or false,
	}

	local ok, err = pcall(function()
		PlayerDataStore:SetAsync("player_" .. player.UserId, data)
	end)

	if ok then
		print(("[DataManager] %s をセーブ (Wave:%d Fires:%d Points:%d Vehicle:%s Water:%s Speed:%s)"):format(
			player.Name, data.Wave, data.Fires, data.Points, tostring(data.VehiclePurchased),
			tostring(data.ActiveWaterBoost), tostring(data.ActiveSpeedBoost)))
	else
		warn(("[DataManager] %s のセーブ失敗: %s"):format(player.Name, tostring(err)))
	end
end

local function saveAllPlayers()
	for _, player in Players:GetPlayers() do
		savePlayerData(player)
	end
end

-- ── ロード ──────────────────────────────────────────────────

local function loadPlayerData(player)
	-- DataStore から取得（WaitForChild より先に実行してラグを減らす）
	local ok, data = pcall(function()
		return PlayerDataStore:GetAsync("player_" .. player.UserId)
	end)

	local savedWave       = 1
	local savedFires      = 0
	local savedPoints     = 0
	local savedVehicle    = false
	local savedWaterBoost = false
	local savedSpeedBoost = false

	if ok and data then
		savedWave       = data.Wave             or 1
		savedFires      = data.Fires            or 0
		savedPoints     = data.Points           or 0
		savedVehicle    = data.VehiclePurchased or false
		savedWaterBoost = data.ActiveWaterBoost or false
		savedSpeedBoost = data.ActiveSpeedBoost or false
		print(("[DataManager] %s をロード (Wave:%d Fires:%d Points:%d Vehicle:%s Water:%s Speed:%s)"):format(
			player.Name, savedWave, savedFires, savedPoints, tostring(savedVehicle),
			tostring(savedWaterBoost), tostring(savedSpeedBoost)))
	elseif not ok then
		warn(("[DataManager] %s のロード失敗: %s"):format(player.Name, tostring(data)))
	else
		print(("[DataManager] %s は新規プレイヤーです"):format(player.Name))
	end

	-- ウェーブ番号: 複数プレイヤーがいる場合は最も進んでいる値を採用
	createLoadedWaveMax(savedWave)

	-- 消防車購入フラグをプレイヤー個人の Attribute に設定
	-- ← ここが重要: ServerStorage（共有グローバル）ではなく player に紐付ける
	player:SetAttribute("VehiclePurchased", savedVehicle)

	-- アクティブバフは ServerStorage に OR ロジックで反映（チーム共有のため per-player にしない）
	setStorageBoolOR("ActiveWaterBoost", savedWaterBoost)
	setStorageBoolOR("ActiveSpeedBoost", savedSpeedBoost)

	-- Fires / Points を leaderstats に反映
	local leaderstats = player:WaitForChild("leaderstats", 10)
	if leaderstats then
		local fires  = leaderstats:FindFirstChild("Fires")
		local points = leaderstats:FindFirstChild("Points")
		if fires  then fires.Value  = savedFires  end
		if points then points.Value = savedPoints end
	else
		warn(("[DataManager] %s の leaderstats が見つかりません（Fires/Points 未反映）"):format(player.Name))
	end

	-- ロード完了フラグ: BurningHouseManager / VehiclePromptHandler が待機している
	player:SetAttribute("DataLoaded", true)
end

-- ── BindableFunction ─────────────────────────────────────────

local SaveAllBindable = Instance.new("BindableFunction")
SaveAllBindable.Name     = "SaveAllPlayers"
SaveAllBindable.Parent   = ServerStorage
SaveAllBindable.OnInvoke = function()
	saveAllPlayers()
end

-- ── イベント接続 ────────────────────────────────────────────

Players.PlayerAdded:Connect(function(player)
	task.spawn(loadPlayerData, player)
end)

Players.PlayerRemoving:Connect(function(player)
	savePlayerData(player)
end)

game:BindToClose(function()
	saveAllPlayers()
end)

-- DataStore 疎通確認（Studio で API アクセスが無効だと保存が全滅するため起動時にチェック）
task.spawn(function()
	local ok, err = pcall(function()
		PlayerDataStore:SetAsync("_connection_test_", os.clock())
	end)
	if ok then
		print("[DataManager] ✅ DataStore 接続OK。セーブ/ロードは正常に動作します。")
	else
		warn("[DataManager] ❌ DataStore 接続失敗！セーブが動作しません。")
		warn("[DataManager] 原因: " .. tostring(err))
		warn("[DataManager] 修正方法: Roblox Studio → ホーム → ゲーム設定 → セキュリティ →")
		warn("[DataManager]   「スタジオ API サービスへのアクセスを有効にする」をONにしてください。")
	end
end)

print("[DataManager] データ管理を起動しました。")
