--[[
	TownGenerator（Server / Script）
	道路・歩道・建物・街灯を起動時に自動生成して町を作る。
]]

local Workspace = game:GetService("Workspace")

math.randomseed(2026)  -- 固定シードで毎回同じ町

-- ── 設定 ────────────────────────────────────────────────────

local ROAD_WIDTH    = 12
local BLOCK_SPACING = 80    -- 道路中心間の距離（スタッド）
local ROAD_COUNT    = 3     -- 縦横それぞれの道路本数
local SIDEW_WIDTH   = 4     -- 歩道幅
local MAP_HALF      = 160   -- マップ半径
local GROUND_Y      = 0     -- 地面上面 Y 座標

-- 道路の中心 X/Z 座標
local half = math.floor(ROAD_COUNT / 2)
local roadCoords = {}
for i = -half, half do
	roadCoords[#roadCoords + 1] = i * BLOCK_SPACING
end

-- 建物ブロックの中心（隣接する道路の中間点 + 外側）
local blockAxis = {}
blockAxis[#blockAxis + 1] = roadCoords[1] - BLOCK_SPACING / 2
for i = 1, #roadCoords - 1 do
	blockAxis[#blockAxis + 1] = (roadCoords[i] + roadCoords[i + 1]) / 2
end
blockAxis[#blockAxis + 1] = roadCoords[#roadCoords] + BLOCK_SPACING / 2

-- 建物が使える最大半幅（道路端＋歩道＋余白）
local BUILD_MARGIN = ROAD_WIDTH / 2 + SIDEW_WIDTH + 4
local MAX_BW = BLOCK_SPACING / 2 - BUILD_MARGIN

-- ── フォルダ ────────────────────────────────────────────────

local town = Instance.new("Folder")
town.Name  = "Town"
town.Parent = Workspace

-- ── ユーティリティ ───────────────────────────────────────────

local function makePart(name, sx, sy, sz, cx, cy, cz, color, mat)
	local p = Instance.new("Part")
	p.Name         = name
	p.Size         = Vector3.new(sx, sy, sz)
	p.CFrame       = CFrame.new(cx, cy, cz)
	p.Anchored     = true
	p.CanCollide   = true
	p.Color        = color
	p.Material     = mat
	p.TopSurface   = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent       = town
	return p
end

-- ── 地面 ────────────────────────────────────────────────────

makePart("Ground",
	MAP_HALF * 2, 1, MAP_HALF * 2,
	0, GROUND_Y - 0.5, 0,
	Color3.fromRGB(106, 127, 63), Enum.Material.Grass)

-- ── 道路 ＋ 歩道 ────────────────────────────────────────────

local ROAD_CLR  = Color3.fromRGB(45,  45,  45)
local SIDEW_CLR = Color3.fromRGB(130, 128, 122)
local roadLen   = MAP_HALF * 2

for _, x in ipairs(roadCoords) do
	-- 縦道路（N–S）
	makePart("Road_NS",   ROAD_WIDTH,          0.3, roadLen, x,                          GROUND_Y + 0.15, 0, ROAD_CLR,  Enum.Material.SmoothPlastic)
	makePart("Sidew_L",   SIDEW_WIDTH,         0.4, roadLen, x - ROAD_WIDTH/2 - SIDEW_WIDTH/2, GROUND_Y + 0.2, 0, SIDEW_CLR, Enum.Material.Concrete)
	makePart("Sidew_R",   SIDEW_WIDTH,         0.4, roadLen, x + ROAD_WIDTH/2 + SIDEW_WIDTH/2, GROUND_Y + 0.2, 0, SIDEW_CLR, Enum.Material.Concrete)
end
for _, z in ipairs(roadCoords) do
	-- 横道路（E–W）
	makePart("Road_EW",   roadLen, 0.3,          ROAD_WIDTH,  0, GROUND_Y + 0.15, z,                          ROAD_CLR,  Enum.Material.SmoothPlastic)
	makePart("Sidew_T",   roadLen, 0.4,          SIDEW_WIDTH, 0, GROUND_Y + 0.2, z - ROAD_WIDTH/2 - SIDEW_WIDTH/2, SIDEW_CLR, Enum.Material.Concrete)
	makePart("Sidew_B",   roadLen, 0.4,          SIDEW_WIDTH, 0, GROUND_Y + 0.2, z + ROAD_WIDTH/2 + SIDEW_WIDTH/2, SIDEW_CLR, Enum.Material.Concrete)
end

-- ── 街灯 ─────────────────────────────────────────────────────

local LAMP_CLR     = Color3.fromRGB(65, 65, 65)
local LAMP_SPACING = 28
local LAMP_OFFSET  = ROAD_WIDTH / 2 + SIDEW_WIDTH + 1.5

local function makeStreetLamp(lx, lz)
	local poleH = 13
	makePart("Lamp_Pole", 0.5, poleH, 0.5, lx, GROUND_Y + poleH/2, lz, LAMP_CLR, Enum.Material.Metal)
	makePart("Lamp_Arm",  3,   0.4,  0.4,  lx + 1.5, GROUND_Y + poleH - 0.2, lz, LAMP_CLR, Enum.Material.Metal)
	makePart("Lamp_Bulb", 0.9, 0.9, 0.9, lx + 3, GROUND_Y + poleH - 0.6, lz,
		Color3.fromRGB(240, 240, 240), Enum.Material.SmoothPlastic)
end

for _, x in ipairs(roadCoords) do
	local z = -MAP_HALF + LAMP_SPACING / 2
	while z < MAP_HALF do
		makeStreetLamp(x - LAMP_OFFSET, z)
		makeStreetLamp(x + LAMP_OFFSET, z)
		z = z + LAMP_SPACING
	end
end
for _, z in ipairs(roadCoords) do
	local x = -MAP_HALF + LAMP_SPACING / 2
	while x < MAP_HALF do
		makeStreetLamp(x, z - LAMP_OFFSET)
		makeStreetLamp(x, z + LAMP_OFFSET)
		x = x + LAMP_SPACING
	end
end

-- ── 建物 ─────────────────────────────────────────────────────

local BUILD_COLORS = {
	Color3.fromRGB(160, 150, 138),
	Color3.fromRGB(140, 128, 115),
	Color3.fromRGB(125, 135, 150),
	Color3.fromRGB(150, 140, 122),
	Color3.fromRGB(168, 158, 145),
	Color3.fromRGB(132, 120, 112),
	Color3.fromRGB(142, 152, 135),
	Color3.fromRGB(155, 135, 118),
}

local ROOF_COLORS = {
	Color3.fromRGB(65,  48,  38),
	Color3.fromRGB(48,  48,  58),
	Color3.fromRGB(42,  55,  42),
	Color3.fromRGB(72,  55,  42),
}

-- 暗めのスモークガラス色（白く見えない）
local WIN_CLR = Color3.fromRGB(42, 58, 80)

local function makeBuilding(bx, bz)
	local bw = math.random(10, math.max(11, math.floor(MAX_BW * 1.4)))
	local bd = math.random(10, math.max(11, math.floor(MAX_BW * 1.4)))
	local bh = math.random(10, 32)

	-- 壁
	local wallColor = BUILD_COLORS[math.random(#BUILD_COLORS)]
	makePart("Building", bw, bh, bd, bx, GROUND_Y + bh/2, bz, wallColor, Enum.Material.Concrete)

	-- 屋根
	makePart("Roof", bw + 0.4, 1, bd + 0.4, bx, GROUND_Y + bh + 0.5, bz,
		ROOF_COLORS[math.random(#ROOF_COLORS)], Enum.Material.Concrete)

	-- 窓（各階・4面）すべて SmoothPlastic で統一
	local floors = math.floor(bh / 6)
	for f = 1, floors do
		local wy = GROUND_Y + (f - 0.5) * 6 + 1
		makePart("Win_N", bw * 0.7, 1.6, 0.12, bx, wy, bz - bd/2, WIN_CLR, Enum.Material.SmoothPlastic)
		makePart("Win_S", bw * 0.7, 1.6, 0.12, bx, wy, bz + bd/2, WIN_CLR, Enum.Material.SmoothPlastic)
		makePart("Win_E", 0.12, 1.6, bd * 0.7, bx + bw/2, wy, bz,  WIN_CLR, Enum.Material.SmoothPlastic)
		makePart("Win_W", 0.12, 1.6, bd * 0.7, bx - bw/2, wy, bz,  WIN_CLR, Enum.Material.SmoothPlastic)
	end
end

for _, bax in ipairs(blockAxis) do
	for _, baz in ipairs(blockAxis) do
		local numB = math.random(1, 3)
		for _ = 1, numB do
			local halfW = math.random(5, math.max(6, math.floor(MAX_BW * 0.7)))
			local halfD = math.random(5, math.max(6, math.floor(MAX_BW * 0.7)))
			local maxOx = math.max(0, math.floor(MAX_BW - halfW))
			local maxOz = math.max(0, math.floor(MAX_BW - halfD))
			local ox = math.random(-maxOx, maxOx)
			local oz = math.random(-maxOz, maxOz)
			makeBuilding(bax + ox, baz + oz)
		end
	end
end

print("[TownGenerator] 町の生成完了")
