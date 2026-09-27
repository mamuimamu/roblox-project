--[[
	StationBuilder（Server / ModuleScript）
	消防署タイクーンの区画・建物をパーツで手続き生成する。
	TownGenerator と同じ「makePart で直接組み立てる」スタイル。

	座標はすべて区画ローカル（origin の CFrame 基準、-Z が町側の入口）。
]]

local TweenService = game:GetService("TweenService")

local StationBuilder = {}

-- ── 色・素材 ────────────────────────────────────────────────
local CLR = {
	floor   = Color3.fromRGB(150, 150, 145),
	brick   = Color3.fromRGB(170, 45, 40),
	trim    = Color3.fromRGB(235, 235, 230),
	roof    = Color3.fromRGB(55, 55, 60),
	glass   = Color3.fromRGB(42, 58, 80),
	lane    = Color3.fromRGB(35, 35, 38),
	stripe  = Color3.fromRGB(255, 200, 40),
	metal   = Color3.fromRGB(90, 90, 95),
	grass   = Color3.fromRGB(106, 127, 63),
	road    = Color3.fromRGB(45, 45, 45),
	counter = Color3.fromRGB(200, 40, 35),
	collect = Color3.fromRGB(255, 210, 50),
	shutter = Color3.fromRGB(190, 190, 195),
}

-- ── ユーティリティ ───────────────────────────────────────────

-- 区画ローカル座標 pos（Vector3）にパーツを置く
local function makePart(parent, origin, name, size, pos, color, mat, props)
	local p = Instance.new("Part")
	p.Name          = name
	p.Size          = size
	p.CFrame        = origin * CFrame.new(pos)
	p.Anchored      = true
	p.CanCollide    = true
	p.Color         = color
	p.Material      = mat or Enum.Material.SmoothPlastic
	p.TopSurface    = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if props then
		for k, v in pairs(props) do
			p[k] = v
		end
	end
	p.Parent = parent
	return p
end

-- 見えない目印パーツ（出動レーンの始点・終点、テレポート先など）
local function makeMarker(parent, origin, name, pos)
	return makePart(parent, origin, name, Vector3.new(1, 1, 1), pos, CLR.trim, nil, {
		Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false,
	})
end

-- パーツの面に文字を貼る（看板）
local function addSurfaceText(part, face, text, textColor, bgColor)
	local gui = Instance.new("SurfaceGui")
	gui.Name           = "SignGui"
	gui.Face           = face
	gui.SizingMode     = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud  = 40
	gui.Parent         = part

	local label = Instance.new("TextLabel")
	label.Name                   = "Text"
	label.Size                   = UDim2.fromScale(1, 1)
	label.BackgroundColor3       = bgColor or CLR.brick
	label.BackgroundTransparency = bgColor and 0 or 1
	label.Font                   = Enum.Font.GothamBlack
	label.TextScaled             = true
	label.TextColor3             = textColor or CLR.trim
	label.Text                   = text
	label.Parent                 = gui
	return label
end

-- 頭上に浮く文字（BillboardGui）
local function addBillboard(part, text, offsetY, color)
	local bb = Instance.new("BillboardGui")
	bb.Name        = "Label"
	bb.Size        = UDim2.fromOffset(200, 50)
	bb.StudsOffset = Vector3.new(0, offsetY or 3, 0)
	bb.AlwaysOnTop = false
	bb.MaxDistance = 120
	bb.Parent      = part

	local label = Instance.new("TextLabel")
	label.Name                   = "Text"
	label.Size                   = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font                   = Enum.Font.GothamBold
	label.TextScaled             = true
	label.TextColor3             = color or Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.3
	label.Text                   = text
	label.Parent                 = bb
	return label
end

-- 建てた直後にフェードインさせる演出（見えないパーツは対象外）
local function playBuildEffect(model)
	for _, obj in model:GetDescendants() do
		if obj:IsA("BasePart") and obj.Transparency < 1 then
			local target = obj.Transparency
			obj.Transparency = 1
			TweenService:Create(obj, TweenInfo.new(0.6, Enum.EasingStyle.Quad), { Transparency = target }):Play()
		end
	end
end

-- ── 区画の土台 ──────────────────────────────────────────────

--[[
	区画の床・町との接続道路・回収カウンター・回収パッド・入口看板を作る。
	戻り値: { folder, collector, collectPad, collectorLabel, signLabel, spawnPoint }
]]
function StationBuilder.buildBase(parent, origin, plotSize)
	local base = Instance.new("Folder")
	base.Name   = "Base"
	base.Parent = parent

	-- 区画の床（上面が Y=0）
	makePart(base, origin, "Floor", plotSize, Vector3.new(0, -0.5, 0), CLR.floor, Enum.Material.Concrete)

	-- 区画のふち（赤いライン）
	local hx, hz = plotSize.X / 2, plotSize.Z / 2
	makePart(base, origin, "Curb_L", Vector3.new(1, 0.6, plotSize.Z), Vector3.new(-hx + 0.5, 0.3, 0), CLR.brick)
	makePart(base, origin, "Curb_R", Vector3.new(1, 0.6, plotSize.Z), Vector3.new(hx - 0.5, 0.3, 0), CLR.brick)
	makePart(base, origin, "Curb_B", Vector3.new(plotSize.X, 0.6, 1), Vector3.new(0, 0.3, hz - 0.5), CLR.brick)

	-- 町（地面の端 Z=160）と区画の入口をつなぐ地面と道路
	local gapLen = 30
	makePart(base, origin, "LinkGround", Vector3.new(plotSize.X, 1, gapLen),
		Vector3.new(0, -0.5, -hz - gapLen / 2), CLR.grass, Enum.Material.Grass)
	makePart(base, origin, "LinkRoad", Vector3.new(12, 0.3, gapLen + 2),
		Vector3.new(0, 0.15, -hz - gapLen / 2 + 1), CLR.road)

	-- 入口アーチと看板（プレイヤー名を後から書き込む）
	makePart(base, origin, "Arch_L", Vector3.new(1.2, 14, 1.2), Vector3.new(-8, 7, -hz + 1), CLR.trim)
	makePart(base, origin, "Arch_R", Vector3.new(1.2, 14, 1.2), Vector3.new(8, 7, -hz + 1), CLR.trim)
	local beam = makePart(base, origin, "Arch_Sign", Vector3.new(18, 3, 1), Vector3.new(0, 14.5, -hz + 1), CLR.brick)
	local signLabel = addSurfaceText(beam, Enum.NormalId.Front, "空き区画", CLR.trim, CLR.brick)

	-- 回収カウンター（出動レーンの終点。ここに報酬 $ が貯まる）
	local collector = makePart(base, origin, "Collector", Vector3.new(96, 3.5, 3),
		Vector3.new(0, 1.75, 12), CLR.counter, Enum.Material.SmoothPlastic)
	makePart(base, origin, "CollectorTop", Vector3.new(96.4, 0.4, 3.4),
		Vector3.new(0, 3.7, 12), CLR.trim)
	local collectorLabel = addBillboard(collector, "$0", 5, Color3.fromRGB(255, 230, 80))
	collectorLabel.Parent.Size = UDim2.fromOffset(260, 60)
	collectorLabel.Parent.MaxDistance = 200

	-- 回収パッド（触れると貯まった $ を受け取る）
	local collectPad = makePart(base, origin, "CollectPad", Vector3.new(8, 0.6, 5),
		Vector3.new(0, 0.3, 6), CLR.collect, Enum.Material.Neon)
	addBillboard(collectPad, "💰 回収", 2.5, Color3.fromRGB(255, 240, 150))

	-- テレポート先（「消防署へ」ボタン）
	local spawnPoint = makeMarker(base, origin, "StationSpawn", Vector3.new(0, 3, -4))

	-- ショップ看板（本署と放水塔のあいだ。プロンプトで Robux ショップを開く）
	local kiosk = makePart(base, origin, "ShopKiosk", Vector3.new(6, 7, 1.5), Vector3.new(24, 3.5, -40),
		Color3.fromRGB(215, 160, 20), Enum.Material.SmoothPlastic)
	addSurfaceText(kiosk, Enum.NormalId.Front, "🛒 SHOP", Color3.new(1, 1, 1), Color3.fromRGB(215, 160, 20))
	local shopPrompt = Instance.new("ProximityPrompt")
	shopPrompt.Name                  = "ShopPrompt"
	shopPrompt.ActionText            = "ショップを開く"
	shopPrompt.ObjectText            = "消防署ショップ"
	shopPrompt.HoldDuration          = 0
	shopPrompt.MaxActivationDistance = 10
	shopPrompt.RequiresLineOfSight   = false
	shopPrompt.Parent                = kiosk

	return {
		folder         = base,
		collector      = collector,
		collectPad     = collectPad,
		collectorLabel = collectorLabel,
		signLabel      = signLabel,
		spawnPoint     = spawnPoint,
		shopPrompt     = shopPrompt,
	}
end

-- ── 建物ごとのビルド関数 ─────────────────────────────────────

local builders = {}

-- 通報センター（ドロッパー）: 奥側に建物、手前に回収カウンターへ向かう出動レーン
function builders.Dispatch(model, origin, def)
	local x = def.slotX
	makePart(model, origin, "Building", Vector3.new(14, 10, 10), Vector3.new(x, 5, 36), CLR.brick, Enum.Material.Brick)
	makePart(model, origin, "Roof", Vector3.new(14.6, 0.8, 10.6), Vector3.new(x, 10.4, 36), CLR.roof, Enum.Material.Concrete)
	makePart(model, origin, "Window", Vector3.new(10, 3, 0.2), Vector3.new(x, 6, 30.9), CLR.glass)
	-- 出動口（シャッター）
	makePart(model, origin, "Door", Vector3.new(6, 4, 0.3), Vector3.new(x, 2, 30.9), CLR.shutter, Enum.Material.DiamondPlate)
	-- 屋上の赤色灯
	makePart(model, origin, "Siren", Vector3.new(1.2, 1.2, 1.2), Vector3.new(x, 11.4, 36),
		Color3.fromRGB(255, 40, 40), Enum.Material.Neon, { Shape = Enum.PartType.Ball })
	local sign = makePart(model, origin, "Sign", Vector3.new(10, 1.6, 0.3), Vector3.new(x, 8.8, 30.8), CLR.trim)
	addSurfaceText(sign, Enum.NormalId.Front, def.name, CLR.brick, CLR.trim)

	-- 出動レーン（ベルトコンベア風）
	makePart(model, origin, "Lane", Vector3.new(4, 0.4, 17), Vector3.new(x, 0.2, 22), CLR.lane, Enum.Material.Fabric)
	makePart(model, origin, "LaneStripe_L", Vector3.new(0.3, 0.45, 17), Vector3.new(x - 2, 0.225, 22), CLR.stripe, Enum.Material.Neon)
	makePart(model, origin, "LaneStripe_R", Vector3.new(0.3, 0.45, 17), Vector3.new(x + 2, 0.225, 22), CLR.stripe, Enum.Material.Neon)

	-- クライアントがミニ消防車を走らせる始点・終点
	makeMarker(model, origin, "LaneStart", Vector3.new(x, 1.4, 30))
	makeMarker(model, origin, "LaneEnd",   Vector3.new(x, 1.4, 14.2))
end

-- 本署（1階）: 入口正面の建物
function builders.MainHall(model, origin)
	local cx, cz, w, d, h = 0, -31, 30, 22, 13
	makePart(model, origin, "Slab", Vector3.new(w, 0.4, d), Vector3.new(cx, 0.2, cz), CLR.trim, Enum.Material.Concrete)
	makePart(model, origin, "Wall_Back", Vector3.new(w, h, 1), Vector3.new(cx, h / 2, cz + d / 2 - 0.5), CLR.brick, Enum.Material.Brick)
	makePart(model, origin, "Wall_L", Vector3.new(1, h, d), Vector3.new(cx - w / 2 + 0.5, h / 2, cz), CLR.brick, Enum.Material.Brick)
	makePart(model, origin, "Wall_R", Vector3.new(1, h, d), Vector3.new(cx + w / 2 - 0.5, h / 2, cz), CLR.brick, Enum.Material.Brick)
	-- 正面の壁は中央を出入口として空ける
	makePart(model, origin, "Wall_FL", Vector3.new(10, h, 1), Vector3.new(cx - 10, h / 2, cz - d / 2 + 0.5), CLR.brick, Enum.Material.Brick)
	makePart(model, origin, "Wall_FR", Vector3.new(10, h, 1), Vector3.new(cx + 10, h / 2, cz - d / 2 + 0.5), CLR.brick, Enum.Material.Brick)
	makePart(model, origin, "Wall_FTop", Vector3.new(10, 4, 1), Vector3.new(cx, h - 2, cz - d / 2 + 0.5), CLR.brick, Enum.Material.Brick)
	makePart(model, origin, "Roof", Vector3.new(w + 1, 1, d + 1), Vector3.new(cx, h + 0.5, cz), CLR.roof, Enum.Material.Concrete)
	-- 窓
	makePart(model, origin, "Win_L", Vector3.new(6, 3, 0.2), Vector3.new(cx - 10, 7, cz - d / 2 - 0.05), CLR.glass)
	makePart(model, origin, "Win_R", Vector3.new(6, 3, 0.2), Vector3.new(cx + 10, 7, cz - d / 2 - 0.05), CLR.glass)
	-- 看板
	local sign = makePart(model, origin, "Sign", Vector3.new(12, 2, 0.3), Vector3.new(cx, h - 2, cz - d / 2 - 0.2), CLR.trim)
	addSurfaceText(sign, Enum.NormalId.Front, "消防署", CLR.brick, CLR.trim)
end

-- 車庫: 左手前。シャッター付きのガレージ
function builders.Garage(model, origin)
	local cx, cz, w, d, h = -34, -31, 22, 22, 12
	makePart(model, origin, "Slab", Vector3.new(w, 0.3, d), Vector3.new(cx, 0.15, cz), CLR.floor, Enum.Material.Concrete)
	makePart(model, origin, "Wall_Back", Vector3.new(w, h, 1), Vector3.new(cx, h / 2, cz + d / 2 - 0.5), CLR.brick, Enum.Material.Brick)
	makePart(model, origin, "Wall_L", Vector3.new(1, h, d), Vector3.new(cx - w / 2 + 0.5, h / 2, cz), CLR.brick, Enum.Material.Brick)
	makePart(model, origin, "Wall_R", Vector3.new(1, h, d), Vector3.new(cx + w / 2 - 0.5, h / 2, cz), CLR.brick, Enum.Material.Brick)
	makePart(model, origin, "Wall_FTop", Vector3.new(w, 3, 1), Vector3.new(cx, h - 1.5, cz - d / 2 + 0.5), CLR.brick, Enum.Material.Brick)
	makePart(model, origin, "Roof", Vector3.new(w + 1, 1, d + 1), Vector3.new(cx, h + 0.5, cz), CLR.roof, Enum.Material.Concrete)
	-- 半分開いたシャッター
	makePart(model, origin, "Shutter", Vector3.new(w - 2, 3, 0.3), Vector3.new(cx, h - 4.5, cz - d / 2 + 0.6), CLR.shutter, Enum.Material.DiamondPlate)
	local sign = makePart(model, origin, "Sign", Vector3.new(8, 1.6, 0.3), Vector3.new(cx, h - 1.5, cz - d / 2 - 0.2), CLR.trim)
	addSurfaceText(sign, Enum.NormalId.Front, "車庫", CLR.brick, CLR.trim)
end

-- 放水塔（ホース乾燥塔）: 右手前の鉄骨タワー
function builders.Tower(model, origin)
	local cx, cz, s, h = 36, -32, 6, 28
	for _, off in ipairs({ { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }) do
		makePart(model, origin, "Leg", Vector3.new(1, h, 1),
			Vector3.new(cx + off[1] * s / 2, h / 2, cz + off[2] * s / 2), CLR.brick, Enum.Material.Metal)
	end
	-- 横材（白）
	for y = 6, h - 2, 6 do
		makePart(model, origin, "Brace_F", Vector3.new(s, 0.5, 0.5), Vector3.new(cx, y, cz - s / 2), CLR.trim, Enum.Material.Metal)
		makePart(model, origin, "Brace_B", Vector3.new(s, 0.5, 0.5), Vector3.new(cx, y, cz + s / 2), CLR.trim, Enum.Material.Metal)
		makePart(model, origin, "Brace_L", Vector3.new(0.5, 0.5, s), Vector3.new(cx - s / 2, y, cz), CLR.trim, Enum.Material.Metal)
		makePart(model, origin, "Brace_R", Vector3.new(0.5, 0.5, s), Vector3.new(cx + s / 2, y, cz), CLR.trim, Enum.Material.Metal)
	end
	makePart(model, origin, "Deck", Vector3.new(s + 2, 0.6, s + 2), Vector3.new(cx, h + 0.3, cz), CLR.metal, Enum.Material.DiamondPlate)
	makePart(model, origin, "Beacon", Vector3.new(1.5, 1.5, 1.5), Vector3.new(cx, h + 1.4, cz),
		Color3.fromRGB(255, 40, 40), Enum.Material.Neon, { Shape = Enum.PartType.Ball })
	-- 吊り下げたホース（見た目）
	makePart(model, origin, "Hose", Vector3.new(0.6, h - 6, 0.6), Vector3.new(cx, (h - 6) / 2 + 5, cz), CLR.trim, Enum.Material.Fabric)
end

-- 司令室（2階）: 本署の上に増築
function builders.Office(model, origin)
	local cx, cz, w, d, h, y0 = 0, -31, 28, 20, 9, 14
	makePart(model, origin, "Wall_Back", Vector3.new(w, h, 1), Vector3.new(cx, y0 + h / 2, cz + d / 2 - 0.5), CLR.trim, Enum.Material.Concrete)
	makePart(model, origin, "Wall_L", Vector3.new(1, h, d), Vector3.new(cx - w / 2 + 0.5, y0 + h / 2, cz), CLR.trim, Enum.Material.Concrete)
	makePart(model, origin, "Wall_R", Vector3.new(1, h, d), Vector3.new(cx + w / 2 - 0.5, y0 + h / 2, cz), CLR.trim, Enum.Material.Concrete)
	-- 正面は全面ガラス
	makePart(model, origin, "Glass_F", Vector3.new(w, h, 0.4), Vector3.new(cx, y0 + h / 2, cz - d / 2 + 0.5), CLR.glass, Enum.Material.Glass,
		{ Transparency = 0.3 })
	makePart(model, origin, "Roof", Vector3.new(w + 1, 1, d + 1), Vector3.new(cx, y0 + h + 0.5, cz), CLR.brick, Enum.Material.Concrete)
	-- アンテナ
	makePart(model, origin, "Antenna", Vector3.new(0.4, 8, 0.4), Vector3.new(cx + 10, y0 + h + 5, cz + 5), CLR.metal, Enum.Material.Metal)
	local sign = makePart(model, origin, "Sign", Vector3.new(14, 2.4, 0.3), Vector3.new(cx, y0 + h + 2.2, cz - d / 2 + 1), CLR.brick)
	addSurfaceText(sign, Enum.NormalId.Front, "🚒 司令室", CLR.trim, CLR.brick)
end

-- 待機室: 左翼手前。隊員が寝泊まりする平屋
function builders.Quarters(model, origin)
	local cx, cz, w, d, h = -70, -31, 22, 22, 10
	makePart(model, origin, "Slab", Vector3.new(w, 0.3, d), Vector3.new(cx, 0.15, cz), CLR.trim, Enum.Material.Concrete)
	makePart(model, origin, "Wall_Back", Vector3.new(w, h, 1), Vector3.new(cx, h / 2, cz + d / 2 - 0.5), CLR.trim, Enum.Material.Concrete)
	makePart(model, origin, "Wall_L", Vector3.new(1, h, d), Vector3.new(cx - w / 2 + 0.5, h / 2, cz), CLR.trim, Enum.Material.Concrete)
	makePart(model, origin, "Wall_R", Vector3.new(1, h, d), Vector3.new(cx + w / 2 - 0.5, h / 2, cz), CLR.trim, Enum.Material.Concrete)
	makePart(model, origin, "Wall_FL", Vector3.new(8, h, 1), Vector3.new(cx - 7, h / 2, cz - d / 2 + 0.5), CLR.trim, Enum.Material.Concrete)
	makePart(model, origin, "Wall_FR", Vector3.new(8, h, 1), Vector3.new(cx + 7, h / 2, cz - d / 2 + 0.5), CLR.trim, Enum.Material.Concrete)
	makePart(model, origin, "Wall_FTop", Vector3.new(6, 3, 1), Vector3.new(cx, h - 1.5, cz - d / 2 + 0.5), CLR.trim, Enum.Material.Concrete)
	makePart(model, origin, "Roof", Vector3.new(w + 1, 1, d + 1), Vector3.new(cx, h + 0.5, cz), CLR.brick, Enum.Material.Concrete)
	-- 室内の二段ベッド（左右に2台）
	for _, bx in ipairs({ -7, 7 }) do
		makePart(model, origin, "Bunk_Low", Vector3.new(4, 0.6, 7), Vector3.new(cx + bx, 1.5, cz + 5), CLR.brick, Enum.Material.Fabric)
		makePart(model, origin, "Bunk_High", Vector3.new(4, 0.6, 7), Vector3.new(cx + bx, 4.5, cz + 5), CLR.brick, Enum.Material.Fabric)
		makePart(model, origin, "Bunk_Post", Vector3.new(0.4, 5, 0.4), Vector3.new(cx + bx - 1.8, 2.5, cz + 1.7), CLR.metal, Enum.Material.Metal)
	end
	local sign = makePart(model, origin, "Sign", Vector3.new(8, 1.6, 0.3), Vector3.new(cx, h - 1.5, cz - d / 2 - 0.2), CLR.brick)
	addSurfaceText(sign, Enum.NormalId.Front, "待機室", CLR.trim, CLR.brick)
end

-- 訓練場: 左翼奥。土のグラウンド＋訓練塔＋障害物
function builders.Training(model, origin)
	local cx, cz = -70, 26
	makePart(model, origin, "Yard", Vector3.new(26, 0.2, 32), Vector3.new(cx, 0.1, cz), Color3.fromRGB(150, 115, 80), Enum.Material.Ground)
	-- 訓練塔（窓付きの細いビル）
	makePart(model, origin, "DrillTower", Vector3.new(8, 22, 8), Vector3.new(cx - 6, 11, cz + 10), CLR.floor, Enum.Material.Concrete)
	for y = 5, 19, 7 do
		makePart(model, origin, "DrillWindow", Vector3.new(3, 3, 0.2), Vector3.new(cx - 6, y, cz + 5.9), CLR.lane)
	end
	-- 立てかけたはしご
	makePart(model, origin, "Ladder_L", Vector3.new(0.3, 18, 0.3), Vector3.new(cx - 4, 9, cz + 4.5), CLR.metal, Enum.Material.Metal)
	makePart(model, origin, "Ladder_R", Vector3.new(0.3, 18, 0.3), Vector3.new(cx - 2, 9, cz + 4.5), CLR.metal, Enum.Material.Metal)
	for y = 1.5, 17, 1.5 do
		makePart(model, origin, "Ladder_Step", Vector3.new(2, 0.2, 0.2), Vector3.new(cx - 3, y, cz + 4.5), CLR.metal, Enum.Material.Metal)
	end
	-- 障害物の壁とコーン
	makePart(model, origin, "DrillWall", Vector3.new(8, 3, 1), Vector3.new(cx + 5, 1.5, cz - 4), CLR.brick, Enum.Material.Brick)
	for i = 0, 4 do
		makePart(model, origin, "Cone", Vector3.new(1, 1.6, 1), Vector3.new(cx - 8 + i * 4, 0.8, cz - 11),
			Color3.fromRGB(255, 120, 20), Enum.Material.SmoothPlastic)
	end
	local sign = makePart(model, origin, "Sign", Vector3.new(10, 2, 0.3), Vector3.new(cx + 6, 3, cz - 15.8), CLR.trim)
	addSurfaceText(sign, Enum.NormalId.Front, "訓練場", CLR.brick, CLR.trim)
end

-- 救急棟: 右翼手前。白い建物＋赤十字＋救急車
function builders.Ambulance(model, origin)
	local cx, cz, w, d, h = 70, -31, 22, 22, 11
	local white = Color3.fromRGB(245, 245, 245)
	makePart(model, origin, "Body", Vector3.new(w, h, d), Vector3.new(cx, h / 2, cz), white, Enum.Material.Concrete)
	makePart(model, origin, "Roof", Vector3.new(w + 1, 1, d + 1), Vector3.new(cx, h + 0.5, cz), CLR.roof, Enum.Material.Concrete)
	makePart(model, origin, "Door", Vector3.new(8, 6, 0.3), Vector3.new(cx, 3, cz - d / 2 - 0.1), CLR.glass, Enum.Material.Glass)
	-- 赤十字
	local red = Color3.fromRGB(220, 30, 30)
	makePart(model, origin, "Cross_V", Vector3.new(1.4, 4.5, 0.3), Vector3.new(cx, h - 2.8, cz - d / 2 - 0.2), red, Enum.Material.Neon)
	makePart(model, origin, "Cross_H", Vector3.new(4.5, 1.4, 0.3), Vector3.new(cx, h - 2.8, cz - d / 2 - 0.2), red, Enum.Material.Neon)
	-- 建物の斜め前（区画内）に停めた救急車（箱の組み合わせ）
	makePart(model, origin, "Amb_Body", Vector3.new(5, 4, 9), Vector3.new(cx + 8, 2.4, cz + 19), white)
	makePart(model, origin, "Amb_Cab", Vector3.new(5, 3, 3), Vector3.new(cx + 8, 1.9, cz + 13), white)
	makePart(model, origin, "Amb_Stripe", Vector3.new(5.1, 0.6, 9.1), Vector3.new(cx + 8, 2.2, cz + 19), red)
	makePart(model, origin, "Amb_Light", Vector3.new(2, 0.5, 0.8), Vector3.new(cx + 8, 4.65, cz + 16), red, Enum.Material.Neon)
end

-- ヘリポート: 右翼奥。円形の発着場＋Hマーク＋ヘリコプター
function builders.Helipad(model, origin)
	local cx, cz = 70, 26
	makePart(model, origin, "Pad", Vector3.new(1, 26, 26), Vector3.new(cx, 0.5, cz), CLR.lane, Enum.Material.Concrete,
		{ Shape = Enum.PartType.Cylinder, CFrame = origin * CFrame.new(cx, 0.5, cz) * CFrame.Angles(0, 0, math.rad(90)) })
	-- H マーク
	makePart(model, origin, "H_L", Vector3.new(1.2, 0.1, 8), Vector3.new(cx - 3, 1.05, cz), CLR.trim)
	makePart(model, origin, "H_R", Vector3.new(1.2, 0.1, 8), Vector3.new(cx + 3, 1.05, cz), CLR.trim)
	makePart(model, origin, "H_C", Vector3.new(6, 0.1, 1.2), Vector3.new(cx, 1.05, cz), CLR.trim)
	-- 縁のライト
	for i = 0, 7 do
		local a = i / 8 * math.pi * 2
		makePart(model, origin, "EdgeLight", Vector3.new(0.8, 0.4, 0.8),
			Vector3.new(cx + math.cos(a) * 12, 1.2, cz + math.sin(a) * 12), Color3.fromRGB(80, 255, 120), Enum.Material.Neon)
	end
	-- ヘリコプター（Hマークの奥側に駐機）
	local heliRed = Color3.fromRGB(200, 30, 30)
	makePart(model, origin, "Heli_Body", Vector3.new(5, 4, 8), Vector3.new(cx, 3.2, cz + 6), heliRed)
	makePart(model, origin, "Heli_Window", Vector3.new(4.6, 2, 0.3), Vector3.new(cx, 3.8, cz + 1.9), CLR.glass, Enum.Material.Glass)
	makePart(model, origin, "Heli_Tail", Vector3.new(1, 1, 9), Vector3.new(cx, 3.8, cz + 14), heliRed)
	makePart(model, origin, "Heli_Fin", Vector3.new(0.3, 3, 1.5), Vector3.new(cx, 5, cz + 18), CLR.trim)
	makePart(model, origin, "Heli_Mast", Vector3.new(0.6, 1, 0.6), Vector3.new(cx, 5.7, cz + 6), CLR.metal, Enum.Material.Metal)
	makePart(model, origin, "Heli_Rotor1", Vector3.new(18, 0.2, 0.8), Vector3.new(cx, 6.3, cz + 6), CLR.lane, Enum.Material.Metal)
	makePart(model, origin, "Heli_Rotor2", Vector3.new(0.8, 0.2, 18), Vector3.new(cx, 6.3, cz + 6), CLR.lane, Enum.Material.Metal)
	makePart(model, origin, "Heli_Skid_L", Vector3.new(0.4, 0.4, 8), Vector3.new(cx - 2.5, 1.2, cz + 6), CLR.metal, Enum.Material.Metal)
	makePart(model, origin, "Heli_Skid_R", Vector3.new(0.4, 0.4, 8), Vector3.new(cx + 2.5, 1.2, cz + 6), CLR.metal, Enum.Material.Metal)
end

-- 消防本部タワー: 司令室（屋根の上面 Y=24）の上に3フロア積み上げる高層ビル
function builders.HQTower(model, origin)
	local cx, cz, w, d = 0, -31, 18, 14   -- 司令室のアンテナ（X=10）に当たらない幅
	local y0, floorH, floors = 24, 8, 3
	local white = Color3.fromRGB(235, 235, 235)
	for f = 0, floors - 1 do
		local yb = y0 + f * floorH
		-- 床スラブ（赤いライン）と、全面ガラスのフロア
		makePart(model, origin, "FloorBand", Vector3.new(w + 0.6, 1, d + 0.6), Vector3.new(cx, yb + 0.5, cz), CLR.brick, Enum.Material.Concrete)
		makePart(model, origin, "FloorGlass", Vector3.new(w, floorH - 1, d), Vector3.new(cx, yb + 1 + (floorH - 1) / 2, cz),
			CLR.glass, Enum.Material.Glass, { Transparency = 0.15 })
		-- 四隅の柱（白）
		for _, off in ipairs({ { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }) do
			makePart(model, origin, "Pillar", Vector3.new(1.2, floorH, 1.2),
				Vector3.new(cx + off[1] * (w / 2), yb + floorH / 2, cz + off[2] * (d / 2)), white, Enum.Material.Concrete)
		end
	end
	local topY = y0 + floors * floorH
	makePart(model, origin, "Roof", Vector3.new(w + 1, 1.2, d + 1), Vector3.new(cx, topY + 0.6, cz), CLR.brick, Enum.Material.Concrete)

	-- 屋上の看板（町側を向く）
	local sign = makePart(model, origin, "Sign", Vector3.new(16, 3.4, 0.4), Vector3.new(cx, topY + 3, cz - d / 2 + 1), CLR.brick)
	addSurfaceText(sign, Enum.NormalId.Front, "🚒 消防本部", CLR.trim, CLR.brick)
	makePart(model, origin, "SignPost_L", Vector3.new(0.4, 2, 0.4), Vector3.new(cx - 6, topY + 1.2, cz - d / 2 + 1), CLR.metal, Enum.Material.Metal)
	makePart(model, origin, "SignPost_R", Vector3.new(0.4, 2, 0.4), Vector3.new(cx + 6, topY + 1.2, cz - d / 2 + 1), CLR.metal, Enum.Material.Metal)

	-- 通信アンテナと赤色灯
	makePart(model, origin, "Mast", Vector3.new(0.6, 14, 0.6), Vector3.new(cx + 5, topY + 8, cz + 3), CLR.metal, Enum.Material.Metal)
	makePart(model, origin, "MastBeacon", Vector3.new(1.4, 1.4, 1.4), Vector3.new(cx + 5, topY + 15.5, cz + 3),
		Color3.fromRGB(255, 40, 40), Enum.Material.Neon, { Shape = Enum.PartType.Ball })
	makePart(model, origin, "Dish", Vector3.new(0.6, 4, 4), Vector3.new(cx - 5, topY + 3, cz + 3), white, Enum.Material.Metal,
		{ Shape = Enum.PartType.Cylinder, CFrame = origin * CFrame.new(cx - 5, topY + 3, cz + 3) * CFrame.Angles(0, 0, math.rad(20)) })
end

--[[
	ボタン定義 def に対応する建物を parent（Structures フォルダ）に建てる。
	build が nil（upgrade 等）の場合は何もしない。
	animate = true のときフェードイン演出を行う（ロード復元時は false）。
]]
function StationBuilder.build(parent, origin, def, animate)
	if not def.build then return nil end
	local fn = builders[def.build]
	if not fn then
		warn("[StationBuilder] 未定義の建築タイプ: " .. tostring(def.build))
		return nil
	end

	local model = Instance.new("Model")
	model.Name = def.id
	fn(model, origin, def)
	model.Parent = parent

	if animate then
		playBuildEffect(model)
	end
	return model
end

-- ── 購入パッド ──────────────────────────────────────────────

--[[
	購入パッド（踏むと購入）を作る。Attribute に ButtonId / Price を持たせ、
	クライアント側で「買える／買えない」の色分けに使う。
]]
function StationBuilder.buildPad(parent, origin, def)
	local pad = makePart(parent, origin, "Pad_" .. def.id, Vector3.new(5, 0.6, 5),
		Vector3.new(def.pad.X, 0.3, def.pad.Y), Color3.fromRGB(60, 200, 90), Enum.Material.Neon)
	pad:SetAttribute("ButtonId", def.id)
	pad:SetAttribute("Price", def.price)

	local bb = Instance.new("BillboardGui")
	bb.Name        = "PriceGui"
	bb.Size        = UDim2.fromOffset(180, 56)
	bb.StudsOffset = Vector3.new(0, 3.2, 0)
	bb.MaxDistance = 90
	bb.Parent      = pad

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name                   = "NameLabel"
	nameLabel.Size                   = UDim2.new(1, 0, 0.55, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font                   = Enum.Font.GothamBold
	nameLabel.TextScaled             = true
	nameLabel.TextColor3             = Color3.new(1, 1, 1)
	nameLabel.TextStrokeTransparency = 0.3
	nameLabel.Text                   = def.name
	nameLabel.Parent                 = bb

	local priceLabel = Instance.new("TextLabel")
	priceLabel.Name                   = "PriceLabel"
	priceLabel.Position               = UDim2.new(0, 0, 0.55, 0)
	priceLabel.Size                   = UDim2.new(1, 0, 0.45, 0)
	priceLabel.BackgroundTransparency = 1
	priceLabel.Font                   = Enum.Font.GothamBlack
	priceLabel.TextScaled             = true
	priceLabel.TextColor3             = Color3.fromRGB(120, 255, 140)
	priceLabel.TextStrokeTransparency = 0.3
	priceLabel.Text                   = def.price == 0 and "無料" or ("$" .. def.price)
	priceLabel.Parent                 = bb

	-- モバイル等で踏みにくい場合のためのプロンプト
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name                  = "BuyPrompt"
	prompt.ActionText            = "購入"
	prompt.ObjectText            = def.name
	prompt.HoldDuration          = 0
	prompt.MaxActivationDistance = 8
	prompt.RequiresLineOfSight   = false
	prompt.Parent                = pad

	return pad
end

-- ── 隊員 NPC ────────────────────────────────────────────────

local Players = game:GetService("Players")

--[[
	消防隊員の NPC（R15）を作る。紺の防火服＋黄色いヘルメット。
	elite = true のときは精鋭隊員（ゲームパス）: 金色ヘルメット＋オレンジの防火服。
	spawnPos: 区画ローカル座標。戻り値は Model（Humanoid 付き）、失敗時 nil。
]]
function StationBuilder.buildCrew(parent, origin, index, spawnPos, elite)
	local desc = Instance.new("HumanoidDescription")
	local navy = elite and Color3.fromRGB(200, 90, 20) or Color3.fromRGB(30, 40, 70)
	local skin = Color3.fromRGB(234, 184, 146)
	desc.HeadColor     = skin
	desc.LeftArmColor  = navy
	desc.RightArmColor = navy
	desc.TorsoColor    = navy
	desc.LeftLegColor  = Color3.fromRGB(25, 25, 30)
	desc.RightLegColor = Color3.fromRGB(25, 25, 30)

	-- CreateHumanoidModelFromDescription は内部で yield し、失敗することもあるので pcall
	local ok, model = pcall(function()
		return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
	end)
	if not ok or not model then
		warn("[StationBuilder] 隊員モデルの生成に失敗: " .. tostring(model))
		return nil
	end

	model.Name = (elite and "EliteCrew_" or "Crew_") .. index
	local hum  = model:FindFirstChildOfClass("Humanoid")
	local head = model:FindFirstChild("Head")
	local root = model:FindFirstChild("HumanoidRootPart")
	if hum then
		hum.DisplayName          = elite and "⭐精鋭隊員" or ("隊員" .. index)
		hum.WalkSpeed            = 8
		hum.DisplayDistanceType  = Enum.HumanoidDisplayDistanceType.Viewer
		hum.NameDisplayDistance  = 40
	end

	-- 黄色いヘルメットと胴の反射テープ（頭・胴に溶接）
	if head then
		local helmet = Instance.new("Part")
		helmet.Name       = "Helmet"
		helmet.Shape      = Enum.PartType.Ball
		helmet.Size       = Vector3.new(1.5, 1.5, 1.5)
		helmet.Color      = elite and Color3.fromRGB(255, 215, 0) or Color3.fromRGB(255, 205, 40)
		helmet.Material   = elite and Enum.Material.Foil or Enum.Material.SmoothPlastic
		helmet.CanCollide = false
		helmet.Massless   = true
		helmet.CFrame     = head.CFrame * CFrame.new(0, 0.35, 0)
		helmet.Parent     = model
		local weld = Instance.new("WeldConstraint")
		weld.Part0  = head
		weld.Part1  = helmet
		weld.Parent = helmet
	end
	local torso = model:FindFirstChild("UpperTorso")
	if torso then
		local tape = Instance.new("Part")
		tape.Name       = "ReflectTape"
		tape.Size       = Vector3.new(torso.Size.X + 0.05, 0.25, torso.Size.Z + 0.05)
		tape.Color      = Color3.fromRGB(230, 255, 80)
		tape.Material   = Enum.Material.Neon
		tape.CanCollide = false
		tape.Massless   = true
		tape.CFrame     = torso.CFrame * CFrame.new(0, -0.3, 0)
		tape.Parent     = model
		local weld = Instance.new("WeldConstraint")
		weld.Part0  = torso
		weld.Part1  = tape
		weld.Parent = tape
	end

	model:PivotTo(origin * CFrame.new(spawnPos))
	model.Parent = parent
	if root then
		-- サーバーが物理を持つ（プレイヤーに所有権が移ってワープしないように）
		pcall(function() root:SetNetworkOwner(nil) end)
	end
	return model
end

return StationBuilder
