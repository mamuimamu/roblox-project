--[[
	BurningHouseManager（Server / Script）
	消火判定・焦げ変化・環境音・ウェーブ管理を担う。
	パーティクルエフェクトはクライアント側 BurningHouseController が管理する。
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")

local Shared     = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))

local FIRE_SOUND_ID       = "rbxassetid://6792293721"
local CHAR_COLOR          = Color3.fromRGB(22, 22, 22)
local CHAR_RATE           = 1 / 90
local UPDATE_INTERVAL     = 0.5
local EXTINGUISHER_AMOUNT = 0.25
local WATER_CANNON_AMOUNT = 0.5
local WAVE_START_DELAY    = 5
local SPAWN_HALF_EXTENT   = 60  -- ランダム出現範囲（スタッド）

local currentWave         = 0
local isWaveTransitioning = false

-- [part] = { intensity, charLevel, origColor, origMaterial, sound, extinguished }
local burningData = {}

-- BurningHouse の参照と元の Y 座標（前方宣言）
local burningHouse
local originalPivotY

local function getOrCreateRemoteEvent(name)
	local existing = ReplicatedStorage:FindFirstChild(name)
	if existing and existing:IsA("RemoteEvent") then return existing end
	local event = Instance.new("RemoteEvent")
	event.Name = name
	event.Parent = ReplicatedStorage
	return event
end

local MissionCompleteEvent = getOrCreateRemoteEvent("MissionCompleteEvent")
local WaveStartEvent       = getOrCreateRemoteEvent("WaveStartEvent")
local ExtinguishEvent      = getOrCreateRemoteEvent("ExtinguishEvent")
local WaterCannonFire      = getOrCreateRemoteEvent("WaterCannonFire")

-- ── スコア付与 ──────────────────────────────────────────────

local function addExtinguishScore(player)
	if not player then return end
	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then return end
	local fires = leaderstats:FindFirstChild("Fires")
	if fires and fires:IsA("IntValue") then
		fires.Value += GameConfig.PointsPerFire
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
	part:SetAttribute("IsBurning",    true)
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

-- ── 再点火 ──────────────────────────────────────────────────

local function resetFire(part)
	local d = burningData[part]
	if not d then return end
	part.Color    = d.origColor
	part.Material = d.origMaterial
	d.intensity    = 1.0
	d.charLevel    = 0.0
	d.extinguished = false
	d.sound:Play()
	part:SetAttribute("IsBurning",    true)
	part:SetAttribute("BurnIntensity", 1.0)
	print("[BurningHouseManager] 再出火: " .. part:GetFullName())
end

-- ── ランダム移動 ─────────────────────────────────────────────

local function moveBurningHouseRandom()
	if not burningHouse then return end
	local x = math.random(-SPAWN_HALF_EXTENT, SPAWN_HALF_EXTENT)
	local z = math.random(-SPAWN_HALF_EXTENT, SPAWN_HALF_EXTENT)
	burningHouse:PivotTo(CFrame.new(x, originalPivotY, z))
	print(("[BurningHouseManager] BurningHouse 移動: (%.1f, %.1f, %.1f)"):format(x, originalPivotY, z))
end

local startNextWave  -- forward declaration

-- ── 鎮火処理 ────────────────────────────────────────────────

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
		part:SetAttribute("IsBurning",    false)
		part:SetAttribute("BurnIntensity", 0)
		print("[BurningHouseManager] 鎮火: " .. part:GetFullName())

		addExtinguishScore(player)

		if not isWaveTransitioning then
			isWaveTransitioning = true
			MissionCompleteEvent:FireAllClients(currentWave)
			task.delay(WAVE_START_DELAY, function()
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
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = parts
	local result = Workspace:Spherecast(origin, 4, direction * range, params)
	if result and burningData[result.Instance] then
		extinguishHit(result.Instance, amount, player)
	end
end

-- ── ウェーブ管理 ─────────────────────────────────────────────

startNextWave = function()
	currentWave += 1
	moveBurningHouseRandom()
	for part in pairs(burningData) do
		resetFire(part)
	end
	WaveStartEvent:FireAllClients(currentWave, 1)
	print("[BurningHouseManager] Wave " .. currentWave .. " 開始")
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

WaterCannonFire.OnServerEvent:Connect(function(_, camPos, direction)
	if typeof(camPos) ~= "Vector3" or typeof(direction) ~= "Vector3" then return end
	if direction.Magnitude < 1e-4 then return end
	raycastExtinguish(camPos, direction.Unit, 210, WATER_CANNON_AMOUNT, nil)
end)

-- ── BurningHouse 初期化 ─────────────────────────────────────

burningHouse = Workspace:FindFirstChild("BurningHouse")
	or Workspace:WaitForChild("BurningHouse", 60)

if not burningHouse then
	warn("[BurningHouseManager] 'BurningHouse' が Workspace に見つかりません。")
	return
end

originalPivotY = burningHouse:GetPivot().Y

local function selectBurningPart(house)
	local parts = {}
	for _, desc in house:GetDescendants() do
		if desc:IsA("BasePart") then
			parts[#parts + 1] = desc
		end
	end
	if #parts == 0 then return nil end

	local minY, maxY =  math.huge, -math.huge
	local minX, maxX =  math.huge, -math.huge
	local minZ, maxZ =  math.huge, -math.huge
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
		local dx = math.abs(p.Position.X - cx)
		local dz = math.abs(p.Position.Z - cz)
		local score = math.max(dx, dz)
		if score > bestScore then
			bestScore = score
			bestPart  = p
		end
	end

	return bestPart or candidates[1]
end

local targetPart = selectBurningPart(burningHouse)

if targetPart then
	initPart(targetPart)
	moveBurningHouseRandom()  -- Wave 1 もランダム位置からスタート
	currentWave = 1
	WaveStartEvent:FireAllClients(currentWave, 1)
	print("[BurningHouseManager] Wave 1 開始 / 火災パーツ: " .. targetPart:GetFullName())
else
	warn("[BurningHouseManager] 燃やすパーツが見つかりません。")
end
