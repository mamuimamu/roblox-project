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
local SPAWN_HALF_EXTENT   = 60
local MAX_FIRES           = 5
local MIN_HOUSE_DIST      = 30
local MIN_PLAYER_DIST     = 25
local DEFAULT_WALKSPEED   = 16
local BOOST_WALKSPEED     = 24

local currentWave          = 0
local isWaveTransitioning  = false
local waveToken            = 0
local waveStartTime        = 0
local currentWaveTimeLimit = WAVE_TIME_LIMIT

-- ショップ状態（次ウェーブ分）
local nextWavePowerups = { waterBoost = false, timeExtend = false, speedBoost = false }
local powerupBuyers    = {}   -- [itemId] = playerName

-- 永続購入（Wave をまたいでリセットしない）
local vehiclePurchased = false
local rescueVehicle    = nil  -- Workspace の RescueVehicle 参照

-- 現ウェーブのアクティブパワーアップ
local activePowerups = { waterBoost = false, speedBoost = false }

local shopDelayThread = nil  -- ショップ待機スレッド（買い物終了で cancel）

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

local function initPart(part)
	if not part:IsA("BasePart") then return end
	if burningData[part] then return end
	local sound = attachSound(part)
	burningData[part] = {
		intensity    = 1.0,
		charLevel    = 0.0,
		origColor    = part.Color,
		origMaterial = part.Material,
		sound        = sound,
		extinguished = false,
	}
	part:SetAttribute("IsBurning",     true)
	part:SetAttribute("BurnIntensity", 1.0)
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

local function pickPosition(usedPositions, playerPositions)
	for _ = 1, 30 do
		local x = math.random(-SPAWN_HALF_EXTENT, SPAWN_HALF_EXTENT)
		local z = math.random(-SPAWN_HALF_EXTENT, SPAWN_HALF_EXTENT)
		local candidate = Vector3.new(x, 0, z)
		local ok = true
		for _, p in ipairs(usedPositions) do
			if (candidate - Vector3.new(p.X, 0, p.Z)).Magnitude < MIN_HOUSE_DIST then
				ok = false; break
			end
		end
		if ok then
			for _, p in ipairs(playerPositions) do
				if (candidate - Vector3.new(p.X, 0, p.Z)).Magnitude < MIN_PLAYER_DIST then
					ok = false; break
				end
			end
		end
		if ok then return x, z end
	end
	return math.random(-SPAWN_HALF_EXTENT, SPAWN_HALF_EXTENT),
	       math.random(-SPAWN_HALF_EXTENT, SPAWN_HALF_EXTENT)
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
	return currentWave, remainingFireCount(), remaining
end

local function allExtinguished()
	for _, d in pairs(burningData) do
		if not d.extinguished then return false end
	end
	return next(burningData) ~= nil
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
end

local function spawnWaveHouses(count)
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
		local x, z = pickPosition(usedPositions, playerPositions)
		table.insert(usedPositions, Vector3.new(x, 0, z))

		local clone = templateHouse:Clone()
		clone.Name = "BurningHouse_" .. i
		clone:PivotTo(CFrame.new(x, originalPivotY, z))
		clone.Parent = Workspace

		local part = selectBurningPart(clone)
		if part then initPart(part) end

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
			ShopOpenEvent:FireAllClients(GameConfig.ShopDuration, nextWavePowerups, powerupBuyers, vehiclePurchased)
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

local function raycastExtinguish(origin, direction, range, amount, player)
	local parts = burningPartsList()
	if #parts == 0 then return end
	local mult   = activePowerups.waterBoost and 1.5 or 1.0
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = parts
	local result = Workspace:Spherecast(origin, 4, direction * range, params)
	if result and burningData[result.Instance] then
		extinguishHit(result.Instance, amount * mult, player)
	end
end

-- ── ウェーブ管理 ─────────────────────────────────────────────

startNextWave = function()
	currentWave += 1
	local fireCount = math.min(currentWave, MAX_FIRES)

	-- 時間延長パワーアップを反映
	currentWaveTimeLimit = WAVE_TIME_LIMIT
	if nextWavePowerups.timeExtend then
		currentWaveTimeLimit = WAVE_TIME_LIMIT + 60
	end

	-- clearActiveHouses でリセットされるため spawnWaveHouses の後に適用
	local applySpeed = nextWavePowerups.speedBoost
	local applyWater = nextWavePowerups.waterBoost

	-- ショップ状態をリセット（次のウェーブ間用）
	nextWavePowerups = { waterBoost = false, timeExtend = false, speedBoost = false }
	powerupBuyers    = {}

	spawnWaveHouses(fireCount)

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

	WaveStartEvent:FireAllClients(currentWave, fireCount, currentWaveTimeLimit, activePowerups)
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
	raycastExtinguish(origin, direction.Unit, 32, EXTINGUISHER_AMOUNT, player)
end)

WaterCannonFire.OnServerEvent:Connect(function(player, camPos, direction)
	if typeof(camPos) ~= "Vector3" or typeof(direction) ~= "Vector3" then return end
	if direction.Magnitude < 1e-4 then return end
	raycastExtinguish(camPos, direction.Unit, 210, WATER_CANNON_AMOUNT, player)
end)

RetryWaveEvent.OnServerEvent:Connect(function()
	if not isWaveTransitioning then return end
	isWaveTransitioning = false
	local fireCount = math.min(currentWave, MAX_FIRES)
	spawnWaveHouses(fireCount)
	WaveStartEvent:FireAllClients(currentWave, fireCount, currentWaveTimeLimit, activePowerups)
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
		-- 永続購入（Wave をまたいでリセット対象外）
		if vehiclePurchased then return end
		points.Value   -= item.price
		vehiclePurchased = true
		if rescueVehicle then rescueVehicle:SetAttribute("VehiclePurchased", true) end
		ShopUpdateEvent:FireAllClients(nextWavePowerups, powerupBuyers, vehiclePurchased)
		print(("[BurningHouseManager] %s が消防車を購入"):format(player.Name))
	else
		-- Wave 限定パワーアップ
		if nextWavePowerups[itemId] then return end
		points.Value          -= item.price
		nextWavePowerups[itemId] = true
		powerupBuyers[itemId]    = player.Name
		ShopUpdateEvent:FireAllClients(nextWavePowerups, powerupBuyers, vehiclePurchased)
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

currentWave          = 1
currentWaveTimeLimit = WAVE_TIME_LIMIT
local initFireCount  = math.min(currentWave, MAX_FIRES)
spawnWaveHouses(initFireCount)
WaveStartEvent:FireAllClients(currentWave, initFireCount, currentWaveTimeLimit, activePowerups)
beginWaveTimer(currentWaveTimeLimit)
print(("[BurningHouseManager] Wave 1 開始 (%d 件)"):format(initFireCount))
