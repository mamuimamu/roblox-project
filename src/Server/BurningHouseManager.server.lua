--[[
	BurningHouseManager（Server / Script）
	消火判定・焦げ変化・環境音・ウェーブ管理・制限時間・マルチ火災・ショップを担う。
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage     = game:GetService("ServerStorage")
local Workspace         = game:GetService("Workspace")
local Players           = game:GetService("Players")

local Shared     = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))

local FIRE_SOUND_ID       = "rbxassetid://6792293721"
local CHAR_COLOR          = Color3.fromRGB(22, 22, 22)
local CHAR_RATE           = 1 / 90
local UPDATE_INTERVAL     = 0.5
local EXTINGUISHER_AMOUNT = 0.25
local WATER_CANNON_AMOUNT = 0.5
local WAVE_START_DELAY    = GameConfig.ShopDuration + 5  -- ショップ時間 + バッファ
local WAVE_TIME_LIMIT     = GameConfig.WaveTimeLimit
local MAX_FIRES           = 5
local MIN_PLAYER_DIST     = 25
local DEFAULT_WALKSPEED   = 16
local BOOST_WALKSPEED     = 24

-- BurningHouse の実測サイズは概ね X=36, Z=26.6（GetBoundingBox 実測値）。
-- ランダムY回転も加わるため、外接円（対角線の半分）を「家の半径」として安全マージンに使う。
-- sqrt((36/2)^2 + (26.6/2)^2) ≈ 22.4 → 安全のため 23 に切り上げ
local HOUSE_RADIUS         = 23
-- 家同士: 中心間距離がこの半径の2倍未満だと必ず外接円が重なる（=見た目の重なりが確定する下限）
local HOUSE_OVERLAP_FLOOR  = HOUSE_RADIUS * 2       -- 46: 絶対に下回ってはいけない最終ライン
local MIN_HOUSE_DIST       = HOUSE_OVERLAP_FLOOR + 8 -- 54: 通常運用時の心地よい間隔
-- 建物との距離も「家の半径」を考慮しないと、建物の角に家の壁がめり込む
local BUILDING_MARGIN      = HOUSE_RADIUS + 6        -- 29: 建物外縁から家の外周まで最低6スタッズ離す
-- スポーン範囲（家の専有面積が大きいので、それに合わせて拡大）
local SPAWN_HALF_EXTENT      = 85
local BOSS_SPAWN_HALF_EXTENT = 140  -- ボスウェーブは火災数(8件)が多いためさらに拡大

-- ボスウェーブ設定（5の倍数ウェーブで発動）
local BOSS_WAVE_INTERVAL  = 5    -- 5の倍数ウェーブでボス戦
local BOSS_FIRE_COUNT     = 8    -- ボスウェーブの同時火災数
local BOSS_FIRE_INTENSITY = 3.0  -- ボス火事の初期強度（通常の3倍耐久）
local BOSS_BOSS_COUNT     = 2    -- うちボス火事（高耐久）の数
local BOSS_TIME_BONUS     = 60   -- ボスウェーブ追加制限時間（秒）

-- セッションごとに異なるシードで初期化し、毎回同じ位置にならないようにする
local rng = Random.new()

local currentWave          = 0
local isFirstWaveInit      = true   -- セッション最初のウェーブ開始時はセーブをスキップ
local isWaveTransitioning  = false
local waveToken            = 0
local waveStartTime        = 0
local currentWaveTimeLimit = WAVE_TIME_LIMIT

-- ショップ状態（次ウェーブ分）
local nextWavePowerups = { waterBoost = false, timeExtend = false, speedBoost = false }
local powerupBuyers    = {}   -- [itemId] = playerName

-- 消防車参照（Workspace または ServerStorage 内の Model）
local rescueVehicle    = nil

-- 現ウェーブのアクティブパワーアップ
local activePowerups = { waterBoost = false, speedBoost = false }

local shopDelayThread = nil  -- ショップ待機スレッド（買い物終了で cancel）

-- 町の建物 AABB キャッシュ（スポーン位置の重複回避に使用）
local townBuildings = {}

local burningData  = {}
local activeHouses = {}

local templateHouse
local originalPivotY

-- ── RemoteEvent ─────────────────────────────────────────────

local function getOrCreateRemoteEvent(name)
	local existing = ReplicatedStorage:FindFirstChild(name)
	if existing and existing:IsA("RemoteEvent") then return existing end
	local event = Instance.new("RemoteEvent")
	event.Name   = name
	event.Parent = ReplicatedStorage
	return event
end

local MissionCompleteEvent  = getOrCreateRemoteEvent("MissionCompleteEvent")
local WaveStartEvent        = getOrCreateRemoteEvent("WaveStartEvent")
local ExtinguishEvent       = getOrCreateRemoteEvent("ExtinguishEvent")
local WaterCannonFire       = getOrCreateRemoteEvent("WaterCannonFire")
local TimeUpEvent           = getOrCreateRemoteEvent("TimeUpEvent")
local RetryWaveEvent        = getOrCreateRemoteEvent("RetryWaveEvent")
local FireExtinguishedEvent = getOrCreateRemoteEvent("FireExtinguishedEvent")
local ShopOpenEvent         = getOrCreateRemoteEvent("ShopOpenEvent")
local ShopUpdateEvent       = getOrCreateRemoteEvent("ShopUpdateEvent")
local ShopBuyEvent          = getOrCreateRemoteEvent("ShopBuyEvent")
local ShopEndEvent          = getOrCreateRemoteEvent("ShopEndEvent")
local BossWaveStartEvent    = getOrCreateRemoteEvent("BossWaveStartEvent")  -- ボスウェーブ通知
local PowerupsSyncEvent     = getOrCreateRemoteEvent("PowerupsSyncEvent")   -- バフ復元など、UIのみ更新したい時の通知

local GetWaveState = ReplicatedStorage:FindFirstChild("GetWaveState")
if not (GetWaveState and GetWaveState:IsA("RemoteFunction")) then
	GetWaveState        = Instance.new("RemoteFunction")
	GetWaveState.Name   = "GetWaveState"
	GetWaveState.Parent = ReplicatedStorage
end

-- ── スコア付与 ──────────────────────────────────────────────

local function addExtinguishScore(player, remainingTime)
	if not player then return end
	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then return end

	local fires = leaderstats:FindFirstChild("Fires")
	if fires and fires:IsA("IntValue") then
		fires.Value += 1
	end

	local points = leaderstats:FindFirstChild("Points")
	if points and points:IsA("IntValue") then
		local timeBonus = math.floor((remainingTime / currentWaveTimeLimit) * GameConfig.TimeBonusMax)
		points.Value += GameConfig.PointsPerFire + timeBonus
	end
end

-- ── 音声セットアップ ─────────────────────────────────────────

local function attachSound(part)
	local snd = Instance.new("Sound")
	snd.Name               = "FireCrackle"
	snd.SoundId            = FIRE_SOUND_ID
	snd.Volume             = 0.55
	snd.RollOffMaxDistance = 55
	snd.RollOffMinDistance = 4
	snd.Looped             = true
	snd.Parent             = part
	snd:Play()
	return snd
end

-- ── パーツ初期化 ────────────────────────────────────────────

-- initialIntensity: ボス火事は 3.0 など通常より高い値を渡す
local function initPart(part, initialIntensity)
	if not part:IsA("BasePart") then return end
	if burningData[part] then return end
	initialIntensity = initialIntensity or 1.0
	local isBoss = initialIntensity > 1.0
	local sound = attachSound(part)
	burningData[part] = {
		intensity    = initialIntensity,
		charLevel    = 0.0,
		origColor    = part.Color,
		origMaterial = part.Material,
		sound        = sound,
		extinguished = false,
		isBoss       = isBoss,
	}
	part:SetAttribute("IsBurning",     true)
	part:SetAttribute("BurnIntensity", initialIntensity)
	-- ボス火事はクライアント側演出用にフラグを立てる
	part:SetAttribute("IsBossFire",    isBoss)
end

-- ── 焦げ色・音量の反映 ──────────────────────────────────────

local function applyState(part, d)
	part.Color = d.origColor:Lerp(CHAR_COLOR, math.min(d.charLevel * 1.25, 1))
	if d.charLevel > 0.42 and part.Material ~= Enum.Material.Slate then
		part.Material = Enum.Material.Slate
	end
	d.sound.Volume = 0.55 * math.max(d.intensity, 0)
	part:SetAttribute("BurnIntensity", d.intensity)
end

-- ── 燃焼パーツ選択 ──────────────────────────────────────────

local function selectBurningPart(house)
	local parts = {}
	for _, desc in house:GetDescendants() do
		if desc:IsA("BasePart") then parts[#parts + 1] = desc end
	end
	if #parts == 0 then return nil end

	local minY, maxY = math.huge, -math.huge
	local minX, maxX = math.huge, -math.huge
	local minZ, maxZ = math.huge, -math.huge
	for _, p in ipairs(parts) do
		local pos, sz = p.Position, p.Size
		minY = math.min(minY, pos.Y - sz.Y / 2)
		maxY = math.max(maxY, pos.Y + sz.Y / 2)
		minX = math.min(minX, pos.X - sz.X / 2)
		maxX = math.max(maxX, pos.X + sz.X / 2)
		minZ = math.min(minZ, pos.Z - sz.Z / 2)
		maxZ = math.max(maxZ, pos.Z + sz.Z / 2)
	end
	local heightRange = maxY - minY
	local cx = (minX + maxX) / 2
	local cz = (minZ + maxZ) / 2

	local candidates = {}
	for _, p in ipairs(parts) do
		if p.Position.Y <= minY + heightRange * 0.5 then
			candidates[#candidates + 1] = p
		end
	end
	if #candidates == 0 then candidates = parts end

	local bestPart, bestScore = nil, -1
	for _, p in ipairs(candidates) do
		local score = math.max(math.abs(p.Position.X - cx), math.abs(p.Position.Z - cz))
		if score > bestScore then bestScore = score; bestPart = p end
	end
	return bestPart or candidates[1]
end

-- ── ランダム位置生成 ─────────────────────────────────────────

-- 起動時に Town フォルダの建物 AABB を収集する
local function collectTownBuildings()
	local town = Workspace:WaitForChild("Town", 15)
	if not town then
		warn("[BurningHouseManager] Town フォルダが見つかりません。建物回避をスキップします。")
		return
	end
	for _, obj in town:GetChildren() do
		if obj.Name == "Building" and obj:IsA("BasePart") then
			table.insert(townBuildings, {
				cx = obj.Position.X,
				cz = obj.Position.Z,
				hx = obj.Size.X / 2,
				hz = obj.Size.Z / 2,
			})
		end
	end
	print(("[BurningHouseManager] 町の建物 %d 件を回避リストに登録"):format(#townBuildings))
end

-- 町の建物（AABB）と重なっていないか。これは全フェーズで絶対に守る（緩和しない）。
local function isInsideAnyBuilding(x, z)
	for _, b in ipairs(townBuildings) do
		if math.abs(x - b.cx) < b.hx + BUILDING_MARGIN
		and math.abs(z - b.cz) < b.hz + BUILDING_MARGIN then
			return true
		end
	end
	return false
end

-- 家同士の最低距離を満たすか
local function satisfiesHouseDist(x, z, usedPositions, minDist)
	for _, p in ipairs(usedPositions) do
		if (Vector3.new(x, 0, z) - Vector3.new(p.X, 0, p.Z)).Magnitude < minDist then
			return false
		end
	end
	return true
end

-- プレイヤーとの最低距離を満たすか
local function satisfiesPlayerDist(x, z, playerPositions, minDist)
	for _, p in ipairs(playerPositions) do
		if (Vector3.new(x, 0, z) - Vector3.new(p.X, 0, p.Z)).Magnitude < minDist then
			return false
		end
	end
	return true
end

-- halfExtent: スポーン可能範囲（ボスウェーブは火災数が多いため広げて呼ばれる）
-- 建物との重なりは全フェーズで絶対条件として維持し、家同士の距離・プレイヤー距離のみ段階的に緩和する。
local function pickPosition(usedPositions, playerPositions, halfExtent)
	halfExtent = halfExtent or SPAWN_HALF_EXTENT

	-- フェーズ1: 全条件（建物・プレイヤー・他の家との距離）を満たす位置を探す
	for _ = 1, 80 do
		local x = rng:NextNumber(-halfExtent, halfExtent)
		local z = rng:NextNumber(-halfExtent, halfExtent)
		if not isInsideAnyBuilding(x, z)
		and satisfiesHouseDist(x, z, usedPositions, MIN_HOUSE_DIST)
		and satisfiesPlayerDist(x, z, playerPositions, MIN_PLAYER_DIST) then
			return x, z
		end
	end

	-- フェーズ2: プレイヤー回避は諦めるが、建物回避と家同士の最低距離は維持する
	for _ = 1, 60 do
		local x = rng:NextNumber(-halfExtent, halfExtent)
		local z = rng:NextNumber(-halfExtent, halfExtent)
		if not isInsideAnyBuilding(x, z)
		and satisfiesHouseDist(x, z, usedPositions, MIN_HOUSE_DIST) then
			return x, z
		end
	end

	-- フェーズ3: 心地よい間隔は諦めるが、HOUSE_OVERLAP_FLOOR（外接円が重ならない絶対下限）は維持する
	-- ここを下回ると家の見た目が確実に重なるため、緩和してもこの値より下げない
	for _ = 1, 80 do
		local x = rng:NextNumber(-halfExtent, halfExtent)
		local z = rng:NextNumber(-halfExtent, halfExtent)
		if not isInsideAnyBuilding(x, z)
		and satisfiesHouseDist(x, z, usedPositions, HOUSE_OVERLAP_FLOOR) then
			return x, z
		end
	end

	-- 最終手段: 建物回避は厳守。家同士は「サンプル中で最も離れた位置」を選び、
	-- それが HOUSE_OVERLAP_FLOOR を満たすものを優先する（満たさない場合のみ次善で妥協）
	local bestX, bestZ, bestDist = nil, nil, -1
	local floorX, floorZ, floorDist = nil, nil, -1
	for _ = 1, 200 do
		local x = rng:NextNumber(-halfExtent, halfExtent)
		local z = rng:NextNumber(-halfExtent, halfExtent)
		if not isInsideAnyBuilding(x, z) then
			local minDist = math.huge
			for _, p in ipairs(usedPositions) do
				minDist = math.min(minDist, (Vector3.new(x, 0, z) - Vector3.new(p.X, 0, p.Z)).Magnitude)
			end
			if minDist > bestDist then
				bestDist, bestX, bestZ = minDist, x, z
			end
			if minDist >= HOUSE_OVERLAP_FLOOR and minDist > floorDist then
				floorDist, floorX, floorZ = minDist, x, z
			end
		end
	end
	if floorX then return floorX, floorZ end  -- 重なりゼロを保証できる位置が見つかった
	if bestX then
		warn("[BurningHouseManager] 重なり回避の下限を満たす空き地が見つからず、最善の位置を使用します。")
		return bestX, bestZ
	end

	-- ここに到達するのは建物が密集しすぎて空き地が皆無の場合のみ（通常は発生しない）
	warn("[BurningHouseManager] 建物を避けた空きスポーン地点が見つかりませんでした。")
	return rng:NextNumber(-halfExtent, halfExtent), rng:NextNumber(-halfExtent, halfExtent)
end

-- ── アクティブ火災管理 ───────────────────────────────────────

local function remainingFireCount()
	local count = 0
	for _, d in pairs(burningData) do
		if not d.extinguished then count += 1 end
	end
	return count
end

GetWaveState.OnServerInvoke = function()
	local elapsed   = os.clock() - waveStartTime
	local remaining = math.max(0, currentWaveTimeLimit - math.floor(elapsed))
	-- activePowerups も返すことでクライアントが再参加時にパワーアップ状態を把握できる
	return currentWave, remainingFireCount(), remaining, activePowerups
end

local function allExtinguished()
	for _, d in pairs(burningData) do
		if not d.extinguished then return false end
	end
	return next(burningData) ~= nil
end

-- activePowerups の現在値を ServerStorage に同期する（DataManager が OR ロジックでセーブに使う）
local function syncPowerupsToStorage()
	local awVal = ServerStorage:FindFirstChild("ActiveWaterBoost")
	if awVal then awVal.Value = activePowerups.waterBoost end
	local asVal = ServerStorage:FindFirstChild("ActiveSpeedBoost")
	if asVal then asVal.Value = activePowerups.speedBoost end
end

local function resetSpeedBoost()
	if not activePowerups.speedBoost then return end
	for _, plr in Players:GetPlayers() do
		local char = plr.Character
		if char then
			local hum = char:FindFirstChild("Humanoid")
			if hum then hum.WalkSpeed = DEFAULT_WALKSPEED end
		end
	end
	activePowerups.speedBoost = false
end

local function clearActiveHouses()
	resetSpeedBoost()
	activePowerups.waterBoost = false
	for _, d in pairs(burningData) do
		if d.sound then d.sound:Stop() end
	end
	burningData = {}
	for _, house in ipairs(activeHouses) do
		house:Destroy()
	end
	activeHouses = {}
	-- ウェーブ終了時にパワーアップをリセット → ストレージも同期（次回ロード時に false が伝わる）
	syncPowerupsToStorage()
end

-- bossFireCount: 先頭からこの数の家をボス火事（高耐久）として生成する
-- halfExtent: スポーン範囲（ボスウェーブは火災数が多いため広めの範囲を渡す）
local function spawnWaveHouses(count, bossFireCount, halfExtent)
	bossFireCount = bossFireCount or 0
	clearActiveHouses()
	local playerPositions = {}
	for _, plr in ipairs(Players:GetPlayers()) do
		local char = plr.Character
		if char then
			local root = char:FindFirstChild("HumanoidRootPart")
			if root then table.insert(playerPositions, root.Position) end
		end
	end
	local vehicleRef = rescueVehicle and rescueVehicle.Parent == Workspace and rescueVehicle or nil
	if vehicleRef then table.insert(playerPositions, vehicleRef:GetPivot().Position) end

	local usedPositions = {}
	for i = 1, count do
		local x, z = pickPosition(usedPositions, playerPositions, halfExtent)
		table.insert(usedPositions, Vector3.new(x, 0, z))

		local clone = templateHouse:Clone()
		clone.Name = "BurningHouse_" .. i
		-- ランダムなY軸回転を加えて配置に変化をもたせる
		local rotation = rng:NextNumber(0, math.pi * 2)
		clone:PivotTo(CFrame.new(x, originalPivotY, z) * CFrame.Angles(0, rotation, 0))
		clone.Parent = Workspace

		-- 先頭 bossFireCount 件をボス火事として高耐久で初期化
		local intensity = (i <= bossFireCount) and BOSS_FIRE_INTENSITY or 1.0
		local part = selectBurningPart(clone)
		if part then initPart(part, intensity) end

		table.insert(activeHouses, clone)
	end
end

-- ── ウェーブタイマー ─────────────────────────────────────────

local function beginWaveTimer(timeLimit)
	waveStartTime = os.clock()
	waveToken += 1
	local myToken = waveToken
	task.delay(timeLimit, function()
		if waveToken ~= myToken then return end
		if isWaveTransitioning then return end
		isWaveTransitioning = true
		TimeUpEvent:FireAllClients(currentWave)
		print("[BurningHouseManager] Wave " .. currentWave .. " タイムオーバー")
	end)
end

-- ── 鎮火処理 ────────────────────────────────────────────────

local startNextWave

local function extinguishHit(part, amount, player)
	local d = burningData[part]
	if not d or d.extinguished then return end

	d.intensity = math.max(0, d.intensity - amount)
	applyState(part, d)

	if d.intensity <= 0 then
		d.extinguished = true
		d.sound:Stop()
		part.Color    = CHAR_COLOR
		part.Material = Enum.Material.Slate
		part:SetAttribute("IsBurning",     false)
		part:SetAttribute("BurnIntensity", 0)
		print("[BurningHouseManager] 鎮火: " .. part:GetFullName())

		local remainingTime = math.max(0, currentWaveTimeLimit - math.floor(os.clock() - waveStartTime))
		addExtinguishScore(player, remainingTime)

		local remaining = remainingFireCount()
		FireExtinguishedEvent:FireAllClients(remaining)

		if allExtinguished() and not isWaveTransitioning then
			isWaveTransitioning = true
			waveToken += 1
			MissionCompleteEvent:FireAllClients(currentWave)

			-- ウェーブクリア時にプレイヤーデータを自動セーブ
			local saveBindable = ServerStorage:FindFirstChild("SaveAllPlayers")
			if saveBindable then
				task.spawn(function() saveBindable:Invoke() end)
			end

			-- ショップ開始: 消防車購入状態はプレイヤー個別に通知する
			for _, plr in Players:GetPlayers() do
				local vp = plr:GetAttribute("VehiclePurchased") == true
				ShopOpenEvent:FireClient(plr, GameConfig.ShopDuration, nextWavePowerups, powerupBuyers, vp)
			end
			shopDelayThread = task.delay(WAVE_START_DELAY, function()
				shopDelayThread = nil
				isWaveTransitioning = false
				startNextWave()
			end)
		end
	end
end

-- ── 焦げ進行ループ ───────────────────────────────────────────

task.spawn(function()
	while true do
		task.wait(UPDATE_INTERVAL)
		for part, d in pairs(burningData) do
			if not d.extinguished then
				d.charLevel = math.min(d.charLevel + CHAR_RATE * UPDATE_INTERVAL, 1)
				applyState(part, d)
			end
		end
	end
end)

-- ── レイキャスト消火 ─────────────────────────────────────────

local function burningPartsList()
	local list = {}
	for part, d in pairs(burningData) do
		if not d.extinguished then list[#list + 1] = part end
	end
	return list
end

-- maxPlayerDist: プレイヤーのルートからヒット地点までの最大距離（スタッズ）
-- 壁を無視するレイキャスト特性を補うため、ヒット後に距離を再チェックする
local function raycastExtinguish(origin, direction, range, amount, player, maxPlayerDist)
	local parts = burningPartsList()
	if #parts == 0 then return end
	local mult   = activePowerups.waterBoost and 1.5 or 1.0
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = parts
	local result = Workspace:Spherecast(origin, 4, direction * range, params)
	if result and burningData[result.Instance] then
		-- プレイヤーのルートパーツからヒット地点までの実距離チェック
		if maxPlayerDist and player and player.Character then
			local root = player.Character:FindFirstChild("HumanoidRootPart")
			if root and (result.Position - root.Position).Magnitude > maxPlayerDist then
				return
			end
		end
		extinguishHit(result.Instance, amount * mult, player)
	end
end

-- ── ウェーブ管理 ─────────────────────────────────────────────

startNextWave = function()
	currentWave += 1

	-- 5の倍数ウェーブかどうか判定
	local isBossWave = (currentWave % BOSS_WAVE_INTERVAL == 0)

	-- CurrentWave を常に更新（PlayerRemoving セーブが正しいウェーブを参照するため）
	local cwVal = ServerStorage:FindFirstChild("CurrentWave")
	if cwVal then cwVal.Value = currentWave end

	-- ボスウェーブは専用の火災数・耐久設定を使用
	local fireCount, bossFireCount
	if isBossWave then
		fireCount     = BOSS_FIRE_COUNT
		bossFireCount = BOSS_BOSS_COUNT
	else
		fireCount     = math.min(currentWave, MAX_FIRES)
		bossFireCount = 0
	end

	-- 時間延長パワーアップを反映（ボスウェーブは基本時間が長い）
	if isBossWave then
		currentWaveTimeLimit = WAVE_TIME_LIMIT + BOSS_TIME_BONUS
		if nextWavePowerups.timeExtend then
			currentWaveTimeLimit = currentWaveTimeLimit + 60
		end
	else
		currentWaveTimeLimit = WAVE_TIME_LIMIT
		if nextWavePowerups.timeExtend then
			currentWaveTimeLimit = WAVE_TIME_LIMIT + 60
		end
	end

	-- clearActiveHouses でリセットされるため spawnWaveHouses の後に適用
	local applySpeed = nextWavePowerups.speedBoost
	local applyWater = nextWavePowerups.waterBoost

	-- ショップ状態をリセット（次のウェーブ間用）
	nextWavePowerups = { waterBoost = false, timeExtend = false, speedBoost = false }
	powerupBuyers    = {}

	-- ボスウェーブは火災数が多いためスポーン範囲を広げて重なりを防ぐ
	local halfExtent = isBossWave and BOSS_SPAWN_HALF_EXTENT or SPAWN_HALF_EXTENT
	spawnWaveHouses(fireCount, bossFireCount, halfExtent)

	-- パワーアップ適用（clearActiveHouses のリセット後）
	activePowerups.waterBoost = applyWater
	if applySpeed then
		activePowerups.speedBoost = true
		for _, plr in Players:GetPlayers() do
			local char = plr.Character
			if char then
				local hum = char:FindFirstChild("Humanoid")
				if hum then hum.WalkSpeed = BOOST_WALKSPEED end
			end
		end
	end
	-- 新ウェーブのパワーアップ状態を ServerStorage へ同期（DataManager のセーブ用）
	syncPowerupsToStorage()

	-- セッション最初のウェーブはロード済みデータを上書きしないようにセーブをスキップ
	-- ここ（パワーアップ同期後）でセーブすることで、購入したばかりのバフも正しく保存される
	if not isFirstWaveInit then
		local saveBindable = ServerStorage:FindFirstChild("SaveAllPlayers")
		if saveBindable then
			task.spawn(function() saveBindable:Invoke() end)
		end
	end
	isFirstWaveInit = false

	-- ボスウェーブは専用イベントを追加で送信してクライアント側演出を起動する
	if isBossWave then
		BossWaveStartEvent:FireAllClients(currentWave, fireCount, bossFireCount, currentWaveTimeLimit)
		print(("[BurningHouseManager] ★ BOSS Wave %d 開始 (火災 %d 件 / ボス火事 %d 件, %ds)"):format(
			currentWave, fireCount, bossFireCount, currentWaveTimeLimit))
	end

	-- isBossWave を 5番目の引数で渡してクライアント側が演出を切り替えられるようにする
	WaveStartEvent:FireAllClients(currentWave, fireCount, currentWaveTimeLimit, activePowerups, isBossWave)
	beginWaveTimer(currentWaveTimeLimit)
	print(("[BurningHouseManager] Wave %d 開始 (%d 件, %ds)"):format(currentWave, fireCount, currentWaveTimeLimit))
end

-- ── イベント接続 ────────────────────────────────────────────

ExtinguishEvent.OnServerEvent:Connect(function(player, origin, direction)
	if typeof(origin) ~= "Vector3" or typeof(direction) ~= "Vector3" then return end
	if direction.Magnitude < 1e-4 then return end
	local char = player.Character
	if not char then return end
	local root = char:FindFirstChild("HumanoidRootPart")
	if not root then return end
	if (origin - root.Position).Magnitude > 28 then return end
	-- 消火器: プレイヤーから35スタッズ以内の火にのみ有効
	raycastExtinguish(origin, direction.Unit, 32, EXTINGUISHER_AMOUNT, player, 35)
end)

WaterCannonFire.OnServerEvent:Connect(function(player, camPos, direction)
	if typeof(camPos) ~= "Vector3" or typeof(direction) ~= "Vector3" then return end
	if direction.Magnitude < 1e-4 then return end

	local CANNON_RANGE = 180
	local char = player.Character
	local rv   = Workspace:FindFirstChild("RescueVehicle")

	-- Step1: 燃えているパーツを探す（壁は無視して火だけを対象にする）
	local parts = burningPartsList()
	if #parts == 0 then return end
	local burnParams = RaycastParams.new()
	burnParams.FilterType = Enum.RaycastFilterType.Include
	burnParams.FilterDescendantsInstances = parts
	local burnResult = Workspace:Spherecast(camPos, 5, direction.Unit * CANNON_RANGE, burnParams)
	if not burnResult or not burningData[burnResult.Instance] then return end

	-- 距離チェック
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if root and (burnResult.Position - root.Position).Magnitude > CANNON_RANGE then return end

	-- Step2: 障害物チェック（プレイヤー・消防車・対象の燃えている家を除いてレイキャスト）
	-- 他の建物が間にある場合はブロックする
	local hitHouse = burnResult.Instance.Parent  -- BurningHouse_X
	local excludeList = {}
	if char    then table.insert(excludeList, char)    end
	if rv      then table.insert(excludeList, rv)      end
	if hitHouse then table.insert(excludeList, hitHouse) end

	local toHit = burnResult.Position - camPos
	local obsParams = RaycastParams.new()
	obsParams.FilterType = Enum.RaycastFilterType.Exclude
	obsParams.FilterDescendantsInstances = excludeList
	local obstacle = Workspace:Raycast(camPos, toHit, obsParams)
	if obstacle then return end  -- 他の建物が遮っている

	local mult = activePowerups.waterBoost and 1.5 or 1.0
	extinguishHit(burnResult.Instance, WATER_CANNON_AMOUNT * mult, player)
end)

RetryWaveEvent.OnServerEvent:Connect(function()
	if not isWaveTransitioning then return end
	isWaveTransitioning = false
	local isBossWave = (currentWave % BOSS_WAVE_INTERVAL == 0)
	local fireCount, bossFireCount
	if isBossWave then
		fireCount     = BOSS_FIRE_COUNT
		bossFireCount = BOSS_BOSS_COUNT
	else
		fireCount     = math.min(currentWave, MAX_FIRES)
		bossFireCount = 0
	end
	local halfExtent = isBossWave and BOSS_SPAWN_HALF_EXTENT or SPAWN_HALF_EXTENT
	spawnWaveHouses(fireCount, bossFireCount, halfExtent)
	if isBossWave then
		BossWaveStartEvent:FireAllClients(currentWave, fireCount, bossFireCount, currentWaveTimeLimit)
	end
	WaveStartEvent:FireAllClients(currentWave, fireCount, currentWaveTimeLimit, activePowerups, isBossWave)
	beginWaveTimer(currentWaveTimeLimit)
	print("[BurningHouseManager] Wave " .. currentWave .. " リトライ")
end)

ShopEndEvent.OnServerEvent:Connect(function()
	if not isWaveTransitioning then return end
	if shopDelayThread then
		task.cancel(shopDelayThread)
		shopDelayThread = nil
	end
	isWaveTransitioning = false
	startNextWave()
end)

ShopBuyEvent.OnServerEvent:Connect(function(player, itemId)
	if not isWaveTransitioning then return end

	-- アイテム検索
	local item = nil
	for _, i in ipairs(GameConfig.ShopItems) do
		if i.id == itemId then item = i; break end
	end
	if not item then return end

	-- ポイント確認
	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then return end
	local points = leaderstats:FindFirstChild("Points")
	if not points or points.Value < item.price then return end

	if itemId == "vehicle" then
		-- このプレイヤーがすでに購入済みなら何もしない（per-player チェック）
		if player:GetAttribute("VehiclePurchased") == true then return end
		points.Value -= item.price
		-- プレイヤー個人の属性に保存（DataManager がここから読み取る）
		player:SetAttribute("VehiclePurchased", true)
		-- 車両モデルに購入フラグを立てる（VehiclePromptHandler / BoardEvent がこれを参照）
		if rescueVehicle then rescueVehicle:SetAttribute("VehiclePurchased", true) end
		-- ショップ更新: 消防車状態はプレイヤー個別に通知
		for _, plr in Players:GetPlayers() do
			local vp = plr:GetAttribute("VehiclePurchased") == true
			ShopUpdateEvent:FireClient(plr, nextWavePowerups, powerupBuyers, vp)
		end
		print(("[BurningHouseManager] %s が消防車を購入"):format(player.Name))
	else
		-- Wave 限定パワーアップ
		if nextWavePowerups[itemId] then return end
		points.Value             -= item.price
		nextWavePowerups[itemId]  = true
		powerupBuyers[itemId]     = player.Name
		-- パワーアップ更新は全員共通（共有バフなので FireAllClients でOK）
		for _, plr in Players:GetPlayers() do
			local vp = plr:GetAttribute("VehiclePurchased") == true
			ShopUpdateEvent:FireClient(plr, nextWavePowerups, powerupBuyers, vp)
		end
		print(("[BurningHouseManager] %s が %s を購入"):format(player.Name, item.name))
	end
end)

-- ── BurningHouse 初期化 ─────────────────────────────────────

local found = Workspace:FindFirstChild("BurningHouse")
	or Workspace:WaitForChild("BurningHouse", 60)

if not found then
	warn("[BurningHouseManager] 'BurningHouse' が Workspace に見つかりません。")
	return
end

templateHouse  = found
originalPivotY = templateHouse:GetPivot().Y
templateHouse.Parent = ServerStorage

-- 町の建物位置を収集（スポーン時の重複回避に使用）
collectTownBuildings()

do
	local deadline = tick() + 10
	repeat
		rescueVehicle = Workspace:FindFirstChild("RescueVehicle")
			or ServerStorage:FindFirstChild("RescueVehicle")
		if not rescueVehicle then task.wait(0.5) end
	until rescueVehicle or tick() > deadline
end
if not rescueVehicle then
	warn("[BurningHouseManager] RescueVehicle が見つかりません（スキップ）")
end

-- CurrentWave IntValue を ServerStorage に作成（DataManager がセーブ時にウェーブ番号を読み取る）
local currentWaveValue = Instance.new("IntValue")
currentWaveValue.Name   = "CurrentWave"
currentWaveValue.Value  = 1
currentWaveValue.Parent = ServerStorage

-- 最初のプレイヤーが参加してキャラクター生成されるまで待つ。
-- これにより WaveStartEvent がプレイヤーに届き、Wave 1 のアニメーションが正しく表示される。
-- （TeleportAsync で転送されてきたプレイヤーも含む）
local firstPlayer
do
	firstPlayer = Players:GetPlayers()[1]
	if not firstPlayer then
		firstPlayer = Players.PlayerAdded:Wait()
	end
	if not firstPlayer.Character then
		firstPlayer.CharacterAdded:Wait()
	end
	task.wait(0.5)  -- クライアントスクリプトの RemoteEvent 接続を待つバッファ
end

-- DataManager がロード完了後に作成する LoadedWave IntValue を待つ（最大5秒）
-- DataManager は GetAsync 完了直後に作成するため通常 1〜2 秒で解決する
local startWave = 1
local loadedWaveValue = ServerStorage:WaitForChild("LoadedWave", 5)
if loadedWaveValue then
	startWave = math.max(1, loadedWaveValue.Value)
	print(("[BurningHouseManager] 保存済みウェーブ: %d から開始"):format(startWave))
else
	warn("[BurningHouseManager] LoadedWave の取得タイムアウト。Wave 1 から開始します。")
end

-- DataManager がプレイヤーのデータをロードするのを待つ（DataLoaded 属性が合図）
-- GetAsync は 1〜3 秒かかるので最大 10 秒待機する
do
	local deadline = tick() + 10
	repeat
		task.wait(0.1)
	until firstPlayer:GetAttribute("DataLoaded") == true or tick() > deadline

	if firstPlayer:GetAttribute("DataLoaded") ~= true then
		warn("[BurningHouseManager] DataManager のロード待機タイムアウト（DataLoaded 未設定）")
	end
end

-- 消防車購入状態をプレイヤー属性から復元（per-player: このプレイヤーが購入済みなら車両を有効化）
if firstPlayer:GetAttribute("VehiclePurchased") == true then
	if rescueVehicle then
		rescueVehicle:SetAttribute("VehiclePurchased", true)
	end
	print("[BurningHouseManager] 消防車購入済みを復元しました（" .. firstPlayer.Name .. "）")
end

-- アクティブバフ（ウェーブ中に効くチーム共有バフ）の保存値を読み取る
-- DataManager の loadPlayerData が DataLoaded 設定前に OR ロジックで書き込んでいる
-- ⚠️ ここでは値の「読み取り」のみ行い、適用は startNextWave() の後で行う。
--    startNextWave 内の spawnWaveHouses → clearActiveHouses が activePowerups を
--    リセットしてしまうため、ここで適用すると直後に自分で打ち消すことになってしまう。
local loadedWaterBoostValue = ServerStorage:FindFirstChild("ActiveWaterBoost")
local loadedSpeedBoostValue = ServerStorage:FindFirstChild("ActiveSpeedBoost")
local restoreWaterBoost = loadedWaterBoostValue ~= nil and loadedWaterBoostValue.Value
local restoreSpeedBoost = loadedSpeedBoostValue ~= nil and loadedSpeedBoostValue.Value

-- スピードブースト中に死亡・再スポーンしたときも速度を再適用する
local function onCharacterSpawned(character)
	if not activePowerups.speedBoost then return end
	local hum = character:FindFirstChildOfClass("Humanoid")
		or character:WaitForChild("Humanoid", 5)
	if hum then hum.WalkSpeed = BOOST_WALKSPEED end
end

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(onCharacterSpawned)
end)
for _, plr in Players:GetPlayers() do
	plr.CharacterAdded:Connect(onCharacterSpawned)
end

-- startNextWave がインクリメントするため 1 引いてセット
currentWave = startWave - 1
startNextWave()

-- ウェーブ開始後にアクティブバフを再適用する
-- （startNextWave 内の clearActiveHouses で一旦リセットされた後なので、ここで適用しないと反映されない）
if restoreWaterBoost then
	activePowerups.waterBoost = true
	print("[BurningHouseManager] 消火強化バフを復元しました")
end
if restoreSpeedBoost then
	activePowerups.speedBoost = true
	for _, plr in Players:GetPlayers() do
		local char = plr.Character
		if char then
			local hum = char:FindFirstChild("Humanoid")
			if hum then hum.WalkSpeed = BOOST_WALKSPEED end
		end
	end
	print("[BurningHouseManager] スピードブーストを復元しました")
end
if restoreWaterBoost or restoreSpeedBoost then
	-- startNextWave 末尾の sync が false で書き込んだ値を、復元後の正しい値で上書きする
	syncPowerupsToStorage()
	-- WaveStartEvent は復元前に発火済みのため、バフアイコンだけを別途更新する
	PowerupsSyncEvent:FireAllClients(activePowerups)
end
