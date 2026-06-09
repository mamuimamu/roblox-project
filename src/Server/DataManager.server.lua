--[[
	DataManager（Server / Script）
	プレイヤーデータ（消火件数・ポイント・ウェーブ番号）の永続セーブ／ロードを担う。

	他スクリプトとのやりとり：
	  ServerStorage.SaveAllPlayers (BindableFunction) : セーブを要求
	  ServerStorage.LoadedWave     (IntValue)         : ロード完了後に保存済みウェーブ番号を格納
	  ServerStorage.CurrentWave    (IntValue)         : BurningHouseManager がウェーブ番号を書き込む
]]

local DataStoreService = game:GetService("DataStoreService")
local Players          = game:GetService("Players")
local ServerStorage    = game:GetService("ServerStorage")

local PlayerDataStore = DataStoreService:GetDataStore("PlayerData_v1")

-- ── セーブ ──────────────────────────────────────────────────

local function savePlayerData(player)
	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then return end

	local fires  = leaderstats:FindFirstChild("Fires")
	local points = leaderstats:FindFirstChild("Points")

	-- ウェーブ番号は BurningHouseManager が ServerStorage.CurrentWave に書き込む
	local cwVal = ServerStorage:FindFirstChild("CurrentWave")
	local wave  = cwVal and cwVal.Value or 1

	local data = {
		Fires  = fires  and fires.Value  or 0,
		Points = points and points.Value or 0,
		Wave   = wave,
	}

	local ok, err = pcall(function()
		PlayerDataStore:SetAsync("player_" .. player.UserId, data)
	end)

	if ok then
		print(("[DataManager] %s をセーブ (Wave: %d, Fires: %d, Points: %d)"):format(
			player.Name, data.Wave, data.Fires, data.Points))
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

local function createLoadedWave(wave)
	-- BurningHouseManager の WaitForChild("LoadedWave") を解除する
	local existing = ServerStorage:FindFirstChild("LoadedWave")
	if existing then
		existing.Value = wave
	else
		local lw = Instance.new("IntValue")
		lw.Name   = "LoadedWave"
		lw.Value  = wave
		lw.Parent = ServerStorage
	end
end

local function loadPlayerData(player)
	-- ① leaderstats を待たずに先に DataStore からデータを取得する
	--    （旧コードは WaitForChild("leaderstats") を先に行っていたため 10 秒ラグが発生していた）
	local ok, data = pcall(function()
		return PlayerDataStore:GetAsync("player_" .. player.UserId)
	end)

	local savedWave   = 1
	local savedFires  = 0
	local savedPoints = 0

	if ok and data then
		savedWave   = data.Wave   or 1
		savedFires  = data.Fires  or 0
		savedPoints = data.Points or 0
		print(("[DataManager] %s をロード (Wave: %d, Fires: %d, Points: %d)"):format(
			player.Name, savedWave, savedFires, savedPoints))
	elseif not ok then
		warn(("[DataManager] %s のロード失敗: %s"):format(player.Name, tostring(data)))
	else
		print(("[DataManager] %s は新規プレイヤーです"):format(player.Name))
	end

	-- ② ウェーブ番号を即座に通知（BurningHouseManager の WaitForChild を解除）
	createLoadedWave(savedWave)

	-- ③ Fires / Points を leaderstats に反映（GetAsync 完了後に別途行う）
	local leaderstats = player:WaitForChild("leaderstats", 10)
	if leaderstats then
		local fires  = leaderstats:FindFirstChild("Fires")
		local points = leaderstats:FindFirstChild("Points")
		if fires  then fires.Value  = savedFires  end
		if points then points.Value = savedPoints end
	else
		warn(("[DataManager] %s の leaderstats が見つかりません（Fires/Points 未反映）"):format(player.Name))
	end
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

print("[DataManager] データ管理を起動しました。")
