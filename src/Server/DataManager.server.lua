--[[
	DataManager（Server / Script）
	プレイヤーデータ（消火件数・ポイント・ウェーブ番号・消防車購入フラグ）の永続セーブ／ロード。
	タイクーン要素（Money・所持ボタン・ランク等）も同じキーに保存する。
	  ・Money は leaderstats、それ以外のタイクーンデータは PlayerProfiles モジュールで保持。
	  ・ロード失敗時はセーブしない（空データで上書きして進行が消えるのを防ぐ）。
	  ・UpdateAsync で書き込み、60秒ごとに自動セーブする。

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

local PlayerProfiles = require(script.Parent:WaitForChild("PlayerProfiles"))

local PlayerDataStore = DataStoreService:GetDataStore("PlayerData_v2")  -- v1 から変更してクリーンスタート

local AUTOSAVE_INTERVAL  = 60   -- 自動セーブ間隔（秒）
local LOAD_RETRY_COUNT   = 3    -- ロード失敗時のリトライ回数
local PURCHASE_HISTORY_MAX = 50 -- 保存するレシートIDの最大件数（古いものから捨てる）

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
	-- ロード未完了・ロード失敗のプレイヤーは保存しない（既存データの上書き防止）
	if player:GetAttribute("DataLoaded") ~= true then return end
	if player:GetAttribute("DataLoadFailed") == true then
		warn(("[DataManager] %s はロード失敗状態のためセーブをスキップ"):format(player.Name))
		return
	end

	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then return end

	local fires  = leaderstats:FindFirstChild("Fires")
	local points = leaderstats:FindFirstChild("Points")
	local money  = leaderstats:FindFirstChild("Money")

	-- ウェーブ番号は BurningHouseManager が ServerStorage.CurrentWave に書き込む
	local cwVal = ServerStorage:FindFirstChild("CurrentWave")
	local wave  = cwVal and cwVal.Value or 1

	-- 消防車購入フラグはプレイヤー個人の Attribute から読む（per-player）
	local vehiclePurchased = player:GetAttribute("VehiclePurchased") == true

	-- アクティブバフは ServerStorage（BurningHouseManager が同期）から読む（チーム共有）
	local awVal = ServerStorage:FindFirstChild("ActiveWaterBoost")
	local asVal = ServerStorage:FindFirstChild("ActiveSpeedBoost")

	-- タイクーンデータは PlayerProfiles から読む
	local profile = PlayerProfiles.get(player) or PlayerProfiles.default()

	-- レシート履歴は直近 PURCHASE_HISTORY_MAX 件だけ残す
	local history = profile.PurchaseHistory
	while #history > PURCHASE_HISTORY_MAX do
		table.remove(history, 1)
	end

	local data = {
		Fires            = fires  and fires.Value  or 0,
		Points           = points and points.Value or 0,
		Wave             = wave,
		VehiclePurchased = vehiclePurchased,
		ActiveWaterBoost = awVal and awVal.Value or false,
		ActiveSpeedBoost = asVal and asVal.Value or false,
		-- ── タイクーン ──
		Money            = money and money.Value or 0,
		OwnedButtons     = profile.OwnedButtons,
		Rank             = profile.Rank,
		CrewCount        = profile.CrewCount,
		LastOnline       = os.time(),
		DailyStreak      = profile.DailyStreak,
		LastDailyClaim   = profile.LastDailyClaim,
		PurchaseHistory  = history,
	}

	local ok, err = pcall(function()
		PlayerDataStore:UpdateAsync("player_" .. player.UserId, function()
			return data
		end)
	end)

	if ok then
		local ownedCount = 0
		for _ in pairs(data.OwnedButtons) do ownedCount += 1 end
		print(("[DataManager] %s をセーブ (Wave:%d Fires:%d Points:%d Money:%d Buttons:%d Rank:%d Vehicle:%s Water:%s Speed:%s)"):format(
			player.Name, data.Wave, data.Fires, data.Points, data.Money, ownedCount, data.Rank,
			tostring(data.VehiclePurchased), tostring(data.ActiveWaterBoost), tostring(data.ActiveSpeedBoost)))
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
	-- 一時的な失敗に備えて数回リトライする
	local ok, data
	for attempt = 1, LOAD_RETRY_COUNT do
		ok, data = pcall(function()
			return PlayerDataStore:GetAsync("player_" .. player.UserId)
		end)
		if ok then break end
		warn(("[DataManager] %s のロード失敗（%d/%d回目）: %s"):format(player.Name, attempt, LOAD_RETRY_COUNT, tostring(data)))
		task.wait(1)
	end

	local savedWave       = 1
	local savedFires      = 0
	local savedPoints     = 0
	local savedVehicle    = false
	local savedWaterBoost = false
	local savedSpeedBoost = false
	local savedMoney      = 0
	local profile         = PlayerProfiles.default()

	if ok and data then
		savedWave       = data.Wave             or 1
		savedFires      = data.Fires            or 0
		savedPoints     = data.Points           or 0
		savedVehicle    = data.VehiclePurchased or false
		savedWaterBoost = data.ActiveWaterBoost or false
		savedSpeedBoost = data.ActiveSpeedBoost or false
		-- タイクーンデータ（旧データにはフィールドが無いので既定値を維持）
		savedMoney              = data.Money           or 0
		profile.OwnedButtons    = data.OwnedButtons    or profile.OwnedButtons
		profile.Rank            = data.Rank            or profile.Rank
		profile.CrewCount       = data.CrewCount       or profile.CrewCount
		profile.LastOnline      = data.LastOnline      or profile.LastOnline
		profile.DailyStreak     = data.DailyStreak     or profile.DailyStreak
		profile.LastDailyClaim  = data.LastDailyClaim  or profile.LastDailyClaim
		profile.PurchaseHistory = data.PurchaseHistory or profile.PurchaseHistory
		print(("[DataManager] %s をロード (Wave:%d Fires:%d Points:%d Vehicle:%s Water:%s Speed:%s)"):format(
			player.Name, savedWave, savedFires, savedPoints, tostring(savedVehicle),
			tostring(savedWaterBoost), tostring(savedSpeedBoost)))
	elseif not ok then
		-- ロード失敗: このセッションではセーブしない（DataLoadFailed フラグ）
		player:SetAttribute("DataLoadFailed", true)
		warn(("[DataManager] %s のロードに失敗したため、このセッションの進行は保存されません"):format(player.Name))
	else
		print(("[DataManager] %s は新規プレイヤーです"):format(player.Name))
	end

	-- タイクーン用プロフィールを登録（TycoonManager が参照する）
	PlayerProfiles.set(player, profile)

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
		local money  = leaderstats:FindFirstChild("Money")
		local rank   = leaderstats:FindFirstChild("Rank")
		if fires  then fires.Value  = savedFires  end
		if points then points.Value = savedPoints end
		if money  then money.Value  = savedMoney  end
		if rank   then rank.Value   = profile.Rank end
	else
		warn(("[DataManager] %s の leaderstats が見つかりません（Fires/Points/Money 未反映）"):format(player.Name))
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
	PlayerProfiles.remove(player)
end)

-- 自動セーブ（サーバークラッシュ時や課金直後のデータ消失を最小限にする）
task.spawn(function()
	while true do
		task.wait(AUTOSAVE_INTERVAL)
		saveAllPlayers()
	end
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
