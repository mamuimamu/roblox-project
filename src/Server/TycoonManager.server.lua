--[[
	TycoonManager（Server / Script）
	消防署タイクーンの中核。
	  ・区画（Plot）の生成とプレイヤーへの割り当て
	  ・購入パッドの表示／購入判定（価格・前提条件はサーバー側で再チェック）
	  ・通報センター（ドロッパー）の収入ループ → 回収カウンターに $ を貯める
	  ・回収パッドで Money に加算
	  ・「消防署へ／町へ」テレポート
	  ・隊員 NPC の出現・巡回と、ウェーブ中の消火支援（BurningHouseManager へ通知）
	  ・車庫の購入で消防車を解放（VehiclePurchased）
	  ・ランク昇格（リバース）: Money・建物・隊員をリセットし、収入倍率を永続アップ
	  ・課金連携: 自動回収パス / 精鋭隊員パス / 即時建設（TycoonGrantNextButton）/ ショップ看板

	データ:
	  ・Money は leaderstats.Money（DataManager がセーブ）
	  ・所持ボタンなどは PlayerProfiles（DataManager がロード／セーブ）
	  ・DataManager が player:SetAttribute("DataLoaded", true) を立てるまで区画を割り当てない
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage     = game:GetService("ServerStorage")
local Workspace         = game:GetService("Workspace")

local Shared         = ReplicatedStorage:WaitForChild("Shared")
local TycoonConfig   = require(Shared:WaitForChild("TycoonConfig"))
local StationBuilder = require(script.Parent:WaitForChild("StationBuilder"))
local PlayerProfiles = require(script.Parent:WaitForChild("PlayerProfiles"))
local Economy        = require(script.Parent:WaitForChild("Economy"))

local PAD_DEBOUNCE     = 0.6  -- 同じパッドの連続購入判定を防ぐ（秒）
local COLLECT_DEBOUNCE = 0.5  -- 回収パッドの連続判定を防ぐ（秒）

-- ── RemoteEvent ─────────────────────────────────────────────

local function getOrCreateRemoteEvent(name)
	local existing = ReplicatedStorage:FindFirstChild(name)
	if existing and existing:IsA("RemoteEvent") then return existing end
	local event = Instance.new("RemoteEvent")
	event.Name   = name
	event.Parent = ReplicatedStorage
	return event
end

local TycoonDropEvent     = getOrCreateRemoteEvent("TycoonDropEvent")      -- S→C: ミニ消防車の演出（dropperId）
local TycoonCollectEvent  = getOrCreateRemoteEvent("TycoonCollectEvent")   -- S→C: 回収額の表示（amount）
local TycoonPurchaseEvent = getOrCreateRemoteEvent("TycoonPurchaseEvent")  -- S→C: 購入結果（ok, buttonName, reason）
local TycoonTeleportEvent = getOrCreateRemoteEvent("TycoonTeleportEvent")  -- C→S: "station" / "town"
local TycoonRankUpEvent   = getOrCreateRemoteEvent("TycoonRankUpEvent")    -- C→S: 昇格リクエスト / S→C: 結果（ok, newRank, reason）
local OpenShopEvent       = getOrCreateRemoteEvent("OpenShopEvent")        -- S→C: ショップ画面を開く（看板のプロンプト）

-- 隊員の消火支援を BurningHouseManager に伝える（player, amount）
local CrewExtinguish = ServerStorage:FindFirstChild("CrewExtinguish")
if not (CrewExtinguish and CrewExtinguish:IsA("BindableEvent")) then
	CrewExtinguish        = Instance.new("BindableEvent")
	CrewExtinguish.Name   = "CrewExtinguish"
	CrewExtinguish.Parent = ServerStorage
end

-- ── 区画の生成 ──────────────────────────────────────────────

local tycoonsFolder = Instance.new("Folder")
tycoonsFolder.Name   = "Tycoons"
tycoonsFolder.Parent = Workspace

--[[
	plots[i] = {
		index, origin, folder, base（StationBuilder.buildBase の戻り値）,
		structures（建物フォルダ）, pads（パッドフォルダ）, crew（隊員 NPC フォルダ）,
		owner（Player or nil）, stored（回収カウンターに貯まっている $）,
		nextDrop = { [dropperId] = 次に出動する os.clock() },
	}
]]
local plots = {}

for i, origin in ipairs(TycoonConfig.PlotOrigins) do
	local folder = Instance.new("Folder")
	folder.Name   = "Plot_" .. i
	folder.Parent = tycoonsFolder

	local base = StationBuilder.buildBase(folder, origin, TycoonConfig.PlotSize)

	local structures = Instance.new("Folder")
	structures.Name   = "Structures"
	structures.Parent = folder

	local pads = Instance.new("Folder")
	pads.Name   = "Pads"
	pads.Parent = folder

	local crew = Instance.new("Folder")
	crew.Name   = "Crew"
	crew.Parent = folder

	plots[i] = {
		index      = i,
		origin     = origin,
		folder     = folder,
		base       = base,
		structures = structures,
		pads       = pads,
		crew       = crew,
		crewSpawned = 0,
		eliteSpawned = false,  -- 精鋭隊員パスの NPC を出したか
		owner      = nil,
		stored     = 0,
		nextDrop   = {},
	}
end

-- ── ヘルパー ────────────────────────────────────────────────

local function getMoneyValue(player)
	local ls = player:FindFirstChild("leaderstats")
	return ls and ls:FindFirstChild("Money")
end

local function getPlotOf(player)
	for _, plot in ipairs(plots) do
		if plot.owner == player then return plot end
	end
	return nil
end

-- 倍率・容量は Economy モジュールに集約（Phase 3〜5 の倍率もそこに追加する）
local getMultiplier = Economy.getMultiplier
local getCapacity   = Economy.getCapacity

-- クライアント表示用に、隊員数・収入倍率・秒間収入・ブースト終了時刻を player の Attribute に反映する
local function syncStatsAttributes(player)
	local profile = PlayerProfiles.get(player)
	if profile then profile.CrewCount = Economy.getHiredCrewCount(player) end
	player:SetAttribute("CrewCount", Economy.getCrewCount(player))
	player:SetAttribute("IncomeMult", math.floor(getMultiplier(player) * 100 + 0.5) / 100)
	player:SetAttribute("IncomePerSec", math.floor(Economy.getIncomePerSecond(player) * 10 + 0.5) / 10)
	player:SetAttribute("BoostUntil", profile and profile.BoostUntil or 0)
end

-- 前提ボタンをすべて所持しているか
local function requirementsMet(profile, def)
	for _, req in ipairs(def.requires) do
		if not profile.OwnedButtons[req] then return false end
	end
	return true
end

-- 回収カウンターの表示を更新
local function updateCollectorLabel(plot)
	if not plot.owner then
		plot.base.collectorLabel.Text = ""
		return
	end
	-- 自動回収パス所持者は貯まらないので表示を切り替える
	if Economy.hasPass(plot.owner, "AutoCollect") then
		plot.base.collectorLabel.Text = "⚡ 自動回収中"
		return
	end
	local cap = getCapacity(plot.owner)
	local text = TycoonConfig.formatMoney(plot.stored)
	if plot.stored >= cap then
		text ..= "（満杯！）"
	end
	plot.base.collectorLabel.Text = text
end

-- ── 購入パッド ──────────────────────────────────────────────

local purchaseButton  -- 前方宣言（パッドの接続で使う）

-- 所持状況に合わせてパッドを出し入れする
local function refreshPads(plot)
	local owner   = plot.owner
	local profile = owner and PlayerProfiles.get(owner)

	for _, def in ipairs(TycoonConfig.Buttons) do
		local pad = plot.pads:FindFirstChild("Pad_" .. def.id)
		local shouldShow = profile ~= nil
			and not profile.OwnedButtons[def.id]
			and requirementsMet(profile, def)

		if shouldShow and not pad then
			pad = StationBuilder.buildPad(plot.pads, plot.origin, def)

			-- 踏んで購入
			local lastTouch = 0
			pad.Touched:Connect(function(hit)
				if os.clock() - lastTouch < PAD_DEBOUNCE then return end
				local char = hit:FindFirstAncestorOfClass("Model")
				local player = char and Players:GetPlayerFromCharacter(char)
				if not player then return end
				lastTouch = os.clock()
				purchaseButton(player, plot, def.id)
			end)
			-- プロンプトで購入
			pad.BuyPrompt.Triggered:Connect(function(player)
				purchaseButton(player, plot, def.id)
			end)
		elseif not shouldShow and pad then
			pad:Destroy()
		end
	end
end

-- ── 隊員 NPC ────────────────────────────────────────────────

-- 隊員が歩き回る範囲（区画ローカル。パッド列のある中央の広場）
local CREW_WANDER_MIN = Vector3.new(-78, 0, -18)
local CREW_WANDER_MAX = Vector3.new(78, 0, 0)
local QUARTERS_DOOR   = Vector3.new(-70, 3, -16)  -- 待機室の前（出現位置）

local wanderRng = Random.new()

-- 隊員を区画内でランダムに歩かせる（NPC が消えたら終了）
local function startWander(plot, model)
	local hum = model:FindFirstChildOfClass("Humanoid")
	if not hum then return end
	task.spawn(function()
		while model.Parent do
			local target = plot.origin * Vector3.new(
				wanderRng:NextNumber(CREW_WANDER_MIN.X, CREW_WANDER_MAX.X),
				0,
				wanderRng:NextNumber(CREW_WANDER_MIN.Z, CREW_WANDER_MAX.Z))
			hum:MoveTo(target)
			-- 到着 or 8秒でタイムアウト
			local arrived = false
			local conn = hum.MoveToFinished:Connect(function() arrived = true end)
			local deadline = os.clock() + 8
			while model.Parent and not arrived and os.clock() < deadline do
				task.wait(0.2)
			end
			conn:Disconnect()
			task.wait(wanderRng:NextNumber(1, 4))  -- 少し立ち止まる
		end
	end)
end

-- elite = true で精鋭隊員（ゲームパス）として生成する
local function spawnCrew(plot, elite)
	-- モデル生成が yield するため、番号は先にカウンターで確定させる（並行生成でも重複しない）
	plot.crewSpawned += 1
	local index = plot.crewSpawned
	local offset = Vector3.new(wanderRng:NextNumber(-3, 3), 0, 0)
	local owner = plot.owner
	local model = StationBuilder.buildCrew(plot.crew, plot.origin, index, QUARTERS_DOOR + offset, elite)
	if not model then return end
	-- 生成を待っている間にオーナーが退出していたら片付ける
	if plot.owner ~= owner then
		model:Destroy()
		return
	end
	startWander(plot, model)
end

-- ── 車庫 → 消防車の解放 ──────────────────────────────────────

local function grantVehicle(player)
	player:SetAttribute("VehiclePurchased", true)
	-- 車両モデル側の購入フラグ（VehiclePromptHandler / BurningHouseManager が参照）
	local vehicle = Workspace:FindFirstChild("RescueVehicle") or ServerStorage:FindFirstChild("RescueVehicle")
	if vehicle then
		vehicle:SetAttribute("VehiclePurchased", true)
	end
	-- 「🚒 呼ぶ」ボタンを表示させる（ScoreUIController / VehicleController が受信）
	local stateEvent = ReplicatedStorage:FindFirstChild("VehicleStateEvent")
	if stateEvent then
		local spawned = vehicle ~= nil and vehicle.Parent == Workspace
		stateEvent:FireClient(player, spawned, true)
	end
end

-- ボタンの効果を適用（建物・ドロッパー・隊員・消防車）
local function applyButton(plot, def, animate)
	StationBuilder.build(plot.structures, plot.origin, def, animate)
	if def.kind == "dropper" then
		plot.nextDrop[def.id] = os.clock() + def.interval
	elseif def.kind == "crew" then
		task.spawn(spawnCrew, plot)  -- モデル生成は yield するので別スレッド
	end
	if def.grantsVehicle and plot.owner then
		grantVehicle(plot.owner)
	end
end

--[[
	購入処理。クライアントから直接呼ばれることはなく、パッドの接触／プロンプト経由のみ。
	価格・前提条件・所有者はすべてここで検証する。
]]
function purchaseButton(player, plot, buttonId)
	if plot.owner ~= player then return end
	local profile = PlayerProfiles.get(player)
	local money   = getMoneyValue(player)
	local def     = TycoonConfig.ButtonById[buttonId]
	if not (profile and money and def) then return end
	if profile.OwnedButtons[buttonId] then return end
	if not requirementsMet(profile, def) then return end

	if money.Value < def.price then
		TycoonPurchaseEvent:FireClient(player, false, def.name, "お金が足りません")
		return
	end

	money.Value -= def.price
	profile.OwnedButtons[buttonId] = true
	applyButton(plot, def, true)
	refreshPads(plot)
	updateCollectorLabel(plot)
	syncStatsAttributes(player)

	TycoonPurchaseEvent:FireClient(player, true, def.name)
	print(("[TycoonManager] %s が %s を購入（$%d）"):format(player.Name, def.name, def.price))
end

-- ── 回収 ────────────────────────────────────────────────────

local function collect(player, plot)
	if plot.owner ~= player or plot.stored <= 0 then return end
	local money = getMoneyValue(player)
	if not money then return end

	local amount = math.floor(plot.stored)
	money.Value += amount
	plot.stored  = 0
	updateCollectorLabel(plot)
	TycoonCollectEvent:FireClient(player, amount)
end

for _, plot in ipairs(plots) do
	local lastTouch = 0
	plot.base.collectPad.Touched:Connect(function(hit)
		if os.clock() - lastTouch < COLLECT_DEBOUNCE then return end
		local char = hit:FindFirstAncestorOfClass("Model")
		local player = char and Players:GetPlayerFromCharacter(char)
		if not player then return end
		lastTouch = os.clock()
		collect(player, plot)
	end)
end

-- ── 区画の割り当て／解放 ────────────────────────────────────

local function assignPlot(player)
	if getPlotOf(player) then return end

	local plot
	for _, p in ipairs(plots) do
		if not p.owner then plot = p; break end
	end
	if not plot then
		warn("[TycoonManager] 空き区画がありません: " .. player.Name)
		return
	end

	plot.owner  = player
	plot.stored = 0
	table.clear(plot.nextDrop)
	player:SetAttribute("PlotIndex", plot.index)
	local profileForSign = PlayerProfiles.get(player)
	local rankDef = TycoonConfig.Ranks[profileForSign and profileForSign.Rank or 1] or TycoonConfig.Ranks[1]
	plot.base.signLabel.Text = player.DisplayName .. " " .. rankDef.name

	-- 所持済みの建物を定義順に復元（演出なし）
	local profile = PlayerProfiles.get(player)
	for _, def in ipairs(TycoonConfig.Buttons) do
		if profile.OwnedButtons[def.id] then
			applyButton(plot, def, false)
		end
	end
	refreshPads(plot)
	updateCollectorLabel(plot)
	syncStatsAttributes(player)
	print(("[TycoonManager] %s に区画 %d を割り当て"):format(player.Name, plot.index))
end

-- 区画の建物・パッド・隊員・貯まった $ をすべて片付ける（退出時・昇格時に共通で使う）
local function clearPlot(plot)
	plot.stored = 0
	table.clear(plot.nextDrop)
	plot.structures:ClearAllChildren()
	plot.pads:ClearAllChildren()
	plot.crew:ClearAllChildren()
	plot.crewSpawned  = 0
	plot.eliteSpawned = false
end

local function releasePlot(player)
	local plot = getPlotOf(player)
	if not plot then return end
	plot.owner = nil
	clearPlot(plot)
	plot.base.signLabel.Text = "空き区画"
	updateCollectorLabel(plot)
end

-- ── ランク昇格（リバース）─────────────────────────────────────

local rankUpBusy = {}  -- [Player] = true（処理中の二重リクエスト防止）

--[[
	昇格処理。条件（次ランクの cost 以上の所持金）はサーバーで検証する。
	リセット: Money / OwnedButtons / 隊員 / 回収ボックス
	維持    : Rank 倍率・消防車解放（VehiclePurchased）・ウェーブ番号・Points
]]
local function rankUp(player)
	if rankUpBusy[player] then return end
	local plot    = getPlotOf(player)
	local profile = PlayerProfiles.get(player)
	local money   = getMoneyValue(player)
	if not (plot and profile and money) then return end

	local nextRank = profile.Rank + 1
	local nextDef  = TycoonConfig.Ranks[nextRank]
	if not nextDef then
		TycoonRankUpEvent:FireClient(player, false, profile.Rank, "最高ランクに到達しています")
		return
	end
	if money.Value < nextDef.cost then
		TycoonRankUpEvent:FireClient(player, false, profile.Rank, "お金が足りません")
		return
	end

	rankUpBusy[player] = true

	-- リセット
	money.Value          = 0
	profile.OwnedButtons = {}
	profile.CrewCount    = 0
	profile.Rank         = nextRank
	local ls = player:FindFirstChild("leaderstats")
	local rankValue = ls and ls:FindFirstChild("Rank")
	if rankValue then rankValue.Value = nextRank end

	-- 区画を建て直す（何も所持していない状態 → 無料の通報センター①のパッドだけが出る）
	clearPlot(plot)
	refreshPads(plot)
	updateCollectorLabel(plot)
	syncStatsAttributes(player)
	plot.base.signLabel.Text = player.DisplayName .. " " .. nextDef.name

	-- 進行が消えないよう、昇格直後にセーブする
	local saveBindable = ServerStorage:FindFirstChild("SaveAllPlayers")
	if saveBindable then
		task.spawn(function() saveBindable:Invoke() end)
	end

	TycoonRankUpEvent:FireClient(player, true, nextRank)
	print(("[TycoonManager] %s が %s に昇格（収入×%s）"):format(player.Name, nextDef.name, tostring(nextDef.mult)))
	rankUpBusy[player] = nil
end

TycoonRankUpEvent.OnServerEvent:Connect(rankUp)

local function onPlayerAdded(player)
	-- DataManager のロード完了を待つ（最大15秒）
	local deadline = os.clock() + 15
	while player.Parent and player:GetAttribute("DataLoaded") ~= true and os.clock() < deadline do
		task.wait(0.1)
	end
	if not player.Parent then return end
	if not PlayerProfiles.get(player) then
		warn("[TycoonManager] プロフィール未ロードのため区画を割り当てません: " .. player.Name)
		return
	end
	assignPlot(player)
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end
Players.PlayerRemoving:Connect(releasePlot)

-- ── 収入ループ ──────────────────────────────────────────────
-- 物理パーツは落とさず、時刻ベースで報酬を加算する（サーバー負荷を抑えるため）。
-- 見た目のミニ消防車はクライアント側で走らせる。

task.spawn(function()
	while true do
		task.wait(TycoonConfig.IncomeTickInterval)
		local now = os.clock()
		for _, plot in ipairs(plots) do
			local owner = plot.owner
			if owner then
				local cap     = getCapacity(owner)
				local mult    = getMultiplier(owner)
				local changed = false
				for dropperId, nextTime in pairs(plot.nextDrop) do
					if now >= nextTime then
						local def = TycoonConfig.ButtonById[dropperId]
						plot.nextDrop[dropperId] = now + def.interval
						if plot.stored < cap or Economy.hasPass(owner, "AutoCollect") then
							plot.stored = math.min(cap, plot.stored + def.value * mult)
							changed = true
							TycoonDropEvent:FireClient(owner, dropperId)
						end
					end
				end
				-- 自動回収パス: 貯まった $ をそのまま所持金へ（回収ボックスが満杯で止まることもない）
				if changed and Economy.hasPass(owner, "AutoCollect") then
					local money = getMoneyValue(owner)
					if money and plot.stored >= 1 then
						local amount = math.floor(plot.stored)
						money.Value += amount
						plot.stored -= amount
					end
				end
				if changed then
					updateCollectorLabel(plot)
				end
			end
		end
	end
end)

-- ── 状態の定期同期（1秒ごと）──────────────────────────────────
-- ゲームパス購入・ブーストの開始/終了で倍率が変わるため、定期的に Attribute を更新する。
-- 精鋭隊員パスを持っていれば NPC を3人出す。

task.spawn(function()
	while true do
		task.wait(1)
		for _, plot in ipairs(plots) do
			local owner = plot.owner
			if owner then
				syncStatsAttributes(owner)
				if Economy.hasPass(owner, "EliteCrew") and not plot.eliteSpawned then
					plot.eliteSpawned = true
					for _ = 1, Economy.ELITE_CREW_COUNT do
						task.spawn(spawnCrew, plot, true)
					end
				end
			end
		end
	end
end)

-- ── 即時建設（デベロッパー製品）────────────────────────────────
-- MonetizationManager から呼ばれる。今表示されているパッドのうち一番安い有料の建物を無料で建てる。
-- 戻り値: 建てたボタン名（建てられるものが無ければ nil）

local GrantNextButton = Instance.new("BindableFunction")
GrantNextButton.Name   = "TycoonGrantNextButton"
GrantNextButton.Parent = ServerStorage
GrantNextButton.OnInvoke = function(player)
	local plot    = getPlotOf(player)
	local profile = PlayerProfiles.get(player)
	if not (plot and profile) then return nil end

	local best
	for _, def in ipairs(TycoonConfig.Buttons) do
		if def.price > 0 and not profile.OwnedButtons[def.id] and requirementsMet(profile, def) then
			if not best or def.price < best.price then best = def end
		end
	end
	if not best then return nil end

	profile.OwnedButtons[best.id] = true
	applyButton(plot, best, true)
	refreshPads(plot)
	updateCollectorLabel(plot)
	syncStatsAttributes(player)
	TycoonPurchaseEvent:FireClient(player, true, best.name)
	print(("[TycoonManager] %s に即時建設: %s"):format(player.Name, best.name))
	return best.name
end

-- ── ショップ看板 ────────────────────────────────────────────────

for _, plot in ipairs(plots) do
	plot.base.shopPrompt.Triggered:Connect(function(player)
		OpenShopEvent:FireClient(player)
	end)
end

-- ── 隊員の消火支援ループ ────────────────────────────────────
-- ウェーブ中かどうかの判定と対象の火の選択は BurningHouseManager 側で行う。

task.spawn(function()
	while true do
		task.wait(TycoonConfig.CrewSupportInterval)
		for _, plot in ipairs(plots) do
			local owner = plot.owner
			if owner then
				local crewCount = Economy.getCrewCount(owner)
				if crewCount > 0 then
					CrewExtinguish:Fire(owner, crewCount * TycoonConfig.CrewSupportAmount)
				end
			end
		end
	end
end)

-- ── テレポート ──────────────────────────────────────────────

-- 町側の出現位置（SpawnLocation があればそれ、なければ町の中心）
local function getTownSpawnCFrame()
	local spawn = Workspace:FindFirstChildOfClass("SpawnLocation")
	if spawn then
		return spawn.CFrame + Vector3.new(0, 4, 0)
	end
	return CFrame.new(0, 5, 0)
end

local lastTeleport = {}  -- [Player] = os.clock()（連打防止）

TycoonTeleportEvent.OnServerEvent:Connect(function(player, destination)
	if destination ~= "station" and destination ~= "town" then return end
	if lastTeleport[player] and os.clock() - lastTeleport[player] < 1 then return end
	lastTeleport[player] = os.clock()

	local char = player.Character
	local hum  = char and char:FindFirstChildOfClass("Humanoid")
	if not (char and hum) or hum.Health <= 0 then return end

	local target
	if destination == "station" then
		local plot = getPlotOf(player)
		if not plot then return end
		-- 区画入口を向いた状態で出現させる
		target = plot.base.spawnPoint.CFrame
	else
		target = getTownSpawnCFrame()
	end

	-- 乗車中なら降ろしてから移動する
	if hum.SeatPart then
		hum.Sit = false
		task.wait(0.1)
	end
	char:PivotTo(target)
end)

Players.PlayerRemoving:Connect(function(player)
	lastTeleport[player] = nil
	rankUpBusy[player]   = nil
end)

print("[TycoonManager] 消防署タイクーンを起動しました。区画数: " .. #plots)
