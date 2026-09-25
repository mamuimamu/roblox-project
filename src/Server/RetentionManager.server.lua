--[[
	RetentionManager（Server / Script）
	また遊びに来てもらうための仕組み（Phase 5）。
	  ・オフライン収入   : 前回退出からの経過時間 × 秒間収入 × 50%（上限 8h / パスで 24h）
	  ・デイリーボーナス : 7日間の連続ログイン報酬（途切れると1日目から）
	  ・累計獲得額       : Money が増えた分を TotalEarned に加算（昇格してもリセットしない）
	  ・ランキング       : OrderedDataStore に累計獲得額を書き、上位10人を区画入口の掲示板に表示

	データはすべて PlayerProfiles（DataManager がセーブ）に保持する。
]]

local DataStoreService  = game:GetService("DataStoreService")
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage     = game:GetService("ServerStorage")
local Workspace         = game:GetService("Workspace")

local Shared         = ReplicatedStorage:WaitForChild("Shared")
local TycoonConfig   = require(Shared:WaitForChild("TycoonConfig"))
local PlayerProfiles = require(script.Parent:WaitForChild("PlayerProfiles"))
local Economy        = require(script.Parent:WaitForChild("Economy"))

local LEADERBOARD_INTERVAL = 90  -- ランキング更新間隔（秒）。DataStore の予算を使いすぎないように長め
local LEADERBOARD_SIZE     = 10

local LeaderboardStore = DataStoreService:GetOrderedDataStore("TotalEarned_v1")

-- ── RemoteEvent ─────────────────────────────────────────────

local function getOrCreateRemoteEvent(name)
	local existing = ReplicatedStorage:FindFirstChild(name)
	if existing and existing:IsA("RemoteEvent") then return existing end
	local event = Instance.new("RemoteEvent")
	event.Name   = name
	event.Parent = ReplicatedStorage
	return event
end

local OfflineEarningsEvent = getOrCreateRemoteEvent("OfflineEarningsEvent") -- S→C: (amount, seconds, capHours)
local DailyRewardEvent     = getOrCreateRemoteEvent("DailyRewardEvent")     -- S→C: 表示 (day, rewards) / C→S: 受け取り
local DailyClaimedEvent    = getOrCreateRemoteEvent("DailyClaimedEvent")    -- S→C: 受け取り結果 (day, amount, boostMinutes)

-- ── ヘルパー ────────────────────────────────────────────────

local function getMoneyValue(player)
	local ls = player:FindFirstChild("leaderstats")
	return ls and ls:FindFirstChild("Money")
end

-- UTC 基準の通し日数（日付の切り替わりは UTC 0時 = 日本時間 9時）
local function today()
	return math.floor(os.time() / 86400)
end

local function saveNow(player)
	local savePlayer = ServerStorage:FindFirstChild("SavePlayer")
	if savePlayer then
		task.spawn(function() savePlayer:Invoke(player) end)
	end
end

-- ── オフライン収入 ──────────────────────────────────────────

local function grantOfflineEarnings(player, profile)
	local lastOnline = profile.LastOnline or 0
	if lastOnline <= 0 then return end  -- 初回プレイ

	local elapsed = os.time() - lastOnline
	if elapsed < TycoonConfig.OfflineMinSeconds then return end

	local capHours = Economy.hasPass(player, "OfflineMax")
		and TycoonConfig.OfflineMaxHoursPass or TycoonConfig.OfflineMaxHours
	local seconds = math.min(elapsed, capHours * 3600)

	-- 留守中のブーストは対象外にするため、ブースト抜きの倍率で計算する
	local ips = Economy.getIncomePerSecond(player)
	if Economy.isBoostActive(player) then ips /= 2 end
	local amount = math.floor(ips * seconds * TycoonConfig.OfflineRate)
	if amount < 1 then return end

	local money = getMoneyValue(player)
	if not money then return end
	money.Value += amount
	OfflineEarningsEvent:FireClient(player, amount, seconds, capHours)
	print(("[RetentionManager] %s にオフライン収入 $%d（%d分）"):format(player.Name, amount, math.floor(seconds / 60)))
end

-- ── デイリーボーナス ────────────────────────────────────────

-- 今日受け取れる日（1〜7）。受け取り済みなら nil
local function getClaimableDay(profile)
	local last = profile.LastDailyClaim or 0
	local now  = today()
	if last == now then return nil end
	if last == now - 1 then
		-- 連続ログイン: 7日目の次は1日目に戻る
		return (profile.DailyStreak % #TycoonConfig.DailyRewards) + 1
	end
	return 1  -- 初回 or 途切れた
end

-- 報酬額（秒間収入に応じてスケール）
local function getDailyAmount(player, day)
	local def = TycoonConfig.DailyRewards[day]
	return math.max(def.minMoney, math.floor(Economy.getIncomePerSecond(player) * def.minutes * 60))
end

local function offerDailyReward(player, profile)
	local day = getClaimableDay(profile)
	if not day then return end
	-- 7日分の報酬額を一覧で送る（カードに表示）
	local amounts = {}
	for d = 1, #TycoonConfig.DailyRewards do
		amounts[d] = getDailyAmount(player, d)
	end
	DailyRewardEvent:FireClient(player, day, amounts)
end

DailyRewardEvent.OnServerEvent:Connect(function(player)
	local profile = PlayerProfiles.get(player)
	local money   = getMoneyValue(player)
	if not (profile and money) then return end
	local day = getClaimableDay(profile)
	if not day then return end  -- 受け取り済み（連打・改ざん対策）

	local def    = TycoonConfig.DailyRewards[day]
	local amount = getDailyAmount(player, day)
	money.Value += amount
	profile.DailyStreak    = day
	profile.LastDailyClaim = today()

	-- 7日目のおまけ: 収入2倍ブースト
	if def.boostMinutes then
		profile.BoostUntil = math.max(profile.BoostUntil or 0, os.time()) + def.boostMinutes * 60
		player:SetAttribute("BoostUntil", profile.BoostUntil)
	end

	DailyClaimedEvent:FireClient(player, day, amount, def.boostMinutes)
	saveNow(player)
	print(("[RetentionManager] %s がデイリー %d日目を受け取り $%d"):format(player.Name, day, amount))
end)

-- ── 累計獲得額の追跡 ─────────────────────────────────────────
-- Money が増えたぶんだけ加算（購入・昇格による減少は無視）。
-- ロード完了後に接続するので、セーブデータの読み込み自体は加算されない。

local function trackEarnings(player, profile)
	local money = getMoneyValue(player)
	if not money then return end
	local last = money.Value
	money.Changed:Connect(function(value)
		if value > last then
			profile.TotalEarned = (profile.TotalEarned or 0) + (value - last)
		end
		last = value
	end)
end

-- ── 参加時の処理 ────────────────────────────────────────────

local function onPlayerAdded(player)
	-- DataManager のロード完了を待つ
	local deadline = os.clock() + 15
	while player.Parent and player:GetAttribute("DataLoaded") ~= true and os.clock() < deadline do
		task.wait(0.1)
	end
	local profile = PlayerProfiles.get(player)
	if not (player.Parent and profile) then return end

	trackEarnings(player, profile)

	-- ゲームパスの確認（オフライン24時間パス・マネー2倍）を待ってから計算する
	deadline = os.clock() + 10
	while player.Parent and player:GetAttribute("PassesChecked") ~= true and os.clock() < deadline do
		task.wait(0.1)
	end
	if not player.Parent then return end

	task.wait(2)  -- クライアントの UI 準備を待つ
	grantOfflineEarnings(player, profile)
	offerDailyReward(player, profile)
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end

-- ── ランキング掲示板 ────────────────────────────────────────

-- 区画入口の横（町側の芝生の上）に掲示板を立てる
local function buildBoard()
	local origin = TycoonConfig.PlotOrigins[1]
	local boardCF = origin * CFrame.new(-24, 9, -TycoonConfig.PlotSize.Z / 2 - 12)

	local board = Instance.new("Part")
	board.Name          = "LeaderboardBoard"
	board.Size          = Vector3.new(16, 14, 1)
	board.CFrame        = boardCF
	board.Anchored      = true
	board.Color         = Color3.fromRGB(30, 30, 40)
	board.Material      = Enum.Material.SmoothPlastic
	board.TopSurface    = Enum.SurfaceType.Smooth
	board.BottomSurface = Enum.SurfaceType.Smooth
	board.Parent        = Workspace

	for _, x in ipairs({ -7, 7 }) do
		local pole = Instance.new("Part")
		pole.Name     = "LeaderboardPole"
		pole.Size     = Vector3.new(0.8, 9, 0.8)
		pole.CFrame   = boardCF * CFrame.new(x, -5, 0)  -- 地面（Y=0）から掲示板の下端まで
		pole.Anchored = true
		pole.Color    = Color3.fromRGB(90, 90, 95)
		pole.Material = Enum.Material.Metal
		pole.Parent   = board
	end

	local gui = Instance.new("SurfaceGui")
	gui.Face          = Enum.NormalId.Front  -- 町側（-Z）を向く
	gui.SizingMode    = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 30
	gui.Parent        = board

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Size                   = UDim2.new(1, 0, 0.14, 0)
	titleLabel.BackgroundColor3       = Color3.fromRGB(190, 40, 35)
	titleLabel.Font                   = Enum.Font.GothamBlack
	titleLabel.TextScaled             = true
	titleLabel.TextColor3             = Color3.new(1, 1, 1)
	titleLabel.Text                   = "🏆 総獲得額ランキング"
	titleLabel.Parent                 = gui

	local rows = {}
	for i = 1, LEADERBOARD_SIZE do
		local row = Instance.new("TextLabel")
		row.Position               = UDim2.new(0.04, 0, 0.15 + (i - 1) * 0.083, 0)
		row.Size                   = UDim2.new(0.92, 0, 0.08, 0)
		row.BackgroundTransparency = 1
		row.Font                   = Enum.Font.GothamBold
		row.TextScaled             = true
		row.TextXAlignment         = Enum.TextXAlignment.Left
		row.TextColor3             = (i == 1 and Color3.fromRGB(255, 215, 80))
			or (i == 2 and Color3.fromRGB(210, 210, 220))
			or (i == 3 and Color3.fromRGB(220, 150, 90))
			or Color3.new(1, 1, 1)
		row.Text                   = ""
		row.Parent                 = gui
		rows[i] = row
	end
	rows[1].Text = "集計中…"
	return rows
end

local boardRows = buildBoard()
local nameCache = {}  -- [userId] = 表示名

local function getName(userId)
	if nameCache[userId] then return nameCache[userId] end
	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	name = ok and name or ("Player" .. userId)
	nameCache[userId] = name
	return name
end

local function updateLeaderboard()
	-- 1) 参加中プレイヤーの累計額を書き込む（Studio のテストユーザーは除外）
	for _, player in Players:GetPlayers() do
		local profile = PlayerProfiles.get(player)
		if profile and player.UserId > 0 and player:GetAttribute("DataLoadFailed") ~= true then
			pcall(function()
				LeaderboardStore:SetAsync(tostring(player.UserId), math.floor(profile.TotalEarned or 0))
			end)
		end
	end

	-- 2) 上位を取得して掲示板に反映
	local ok, pages = pcall(function()
		return LeaderboardStore:GetSortedAsync(false, LEADERBOARD_SIZE)
	end)
	if not ok then
		warn("[RetentionManager] ランキング取得失敗: " .. tostring(pages))
		return
	end
	local entries = pages:GetCurrentPage()
	for i = 1, LEADERBOARD_SIZE do
		local entry = entries[i]
		if entry then
			local name = getName(tonumber(entry.key))
			boardRows[i].Text = ("%d. %s   %s"):format(i, name, TycoonConfig.formatMoney(entry.value))
		else
			boardRows[i].Text = (i == 1 and #entries == 0) and "まだ記録がありません" or ""
		end
	end
end

task.spawn(function()
	task.wait(10)  -- 起動直後はロード処理を優先
	while true do
		updateLeaderboard()
		task.wait(LEADERBOARD_INTERVAL)
	end
end)

print("[RetentionManager] リテンション機能を起動しました。")
