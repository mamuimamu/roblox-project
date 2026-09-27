--[[
	TycoonConfig（Shared / ModuleScript）
	消防署タイクーンのパラメータ定義。サーバー（購入判定・収入計算）と
	クライアント（価格表示・HUD）の双方から require する。

	座標はすべて「区画ローカル座標」（区画中心が原点、-Z 方向が町側の入口）。
]]

local TycoonConfig = {}

-- ── 区画 ────────────────────────────────────────────────────
-- 町の地面（±160）とボスウェーブの火災範囲（±140）の外側に置く。
-- 将来マルチにする場合はここに区画を追加するだけで良い。
TycoonConfig.PlotOrigins = {
	CFrame.new(0, 0, 235),
}
TycoonConfig.PlotSize = Vector3.new(170, 1, 90)  -- 区画の床サイズ（X × Z）。左右 ±55〜85 は Phase 2 の増築エリア

-- ── 収入 ────────────────────────────────────────────────────
TycoonConfig.CollectorBaseCapacity = 1000  -- 回収ボックスに貯められる上限 $
TycoonConfig.IncomeTickInterval    = 0.25  -- 収入ループの判定間隔（秒）

-- ── 隊員 ────────────────────────────────────────────────────
TycoonConfig.CrewIncomeBonus     = 0.15  -- 隊員1人あたりの収入倍率アップ（+15%）
TycoonConfig.CrewSupportInterval = 2     -- ウェーブ中の消火支援間隔（秒）
TycoonConfig.CrewSupportAmount   = 0.02  -- 隊員1人あたり1回の消火量（火の強度は通常 1.0）

-- ── 消火報酬（ウェーブ中のアクティブ収入）────────────────────
-- 1件あたり (Base + PerWave × ウェーブ番号 + 残り時間割合 × TimeBonusMax) × 収入倍率
TycoonConfig.FireMoneyBase         = 40
TycoonConfig.FireMoneyPerWave      = 20
TycoonConfig.FireMoneyTimeBonusMax = 40

-- ── リテンション（Phase 5）─────────────────────────────────────
-- デイリーボーナス: 報酬 = max(minMoney, 秒間収入 × minutes 分)。7日目はブーストも付く
-- 日付の切り替わりは UTC 0時（日本時間 9時）
TycoonConfig.DailyRewards = {
	{ minMoney = 500,   minutes = 5  },
	{ minMoney = 1000,  minutes = 8  },
	{ minMoney = 2000,  minutes = 12 },
	{ minMoney = 3000,  minutes = 15 },
	{ minMoney = 5000,  minutes = 20 },
	{ minMoney = 8000,  minutes = 25 },
	{ minMoney = 15000, minutes = 40, boostMinutes = 15 },
}
TycoonConfig.OfflineRate         = 0.5  -- オフライン収入 = 秒間収入 × 経過秒 × この割合
TycoonConfig.OfflineMaxHours     = 8    -- オフライン収入の上限（時間）
TycoonConfig.OfflineMaxHoursPass = 24   -- 「オフライン24時間」パス所持時の上限
TycoonConfig.OfflineMinSeconds   = 60   -- これ未満の留守はオフライン収入なし
TycoonConfig.PremiumBonus        = 0.1  -- Roblox Premium 会員の収入ボーナス（+10%）

-- ── ランク（リバース）─────────────────────────────────────────
-- cost: そのランクに昇格するのに必要な所持金（昇格すると Money は 0 に戻る）
-- 全ボタン購入の合計は約 $136,600（本部タワー含む）。最初の昇格はヘリポートまで建てた頃に届く額
TycoonConfig.Ranks = {
	{ name = "分署",       mult = 1.0,  cost = 0         },
	{ name = "消防署",     mult = 1.5,  cost = 100000    },
	{ name = "消防本部",   mult = 2.25, cost = 250000    },
	{ name = "広域消防局", mult = 3.4,  cost = 600000    },
	{ name = "消防総監部", mult = 5.0,  cost = 1500000   },
}

-- ── 購入ボタン定義 ──────────────────────────────────────────
--[[
	id       : 一意なID（セーブデータの OwnedButtons のキーになる）
	name     : 表示名
	price    : 価格（$）
	requires : 先に所持している必要があるボタンID一覧（全部満たすとパッドが出現）
	kind     : "dropper"   = 通報センター（一定間隔で出動報酬を生む）
	           "structure" = 建物（見た目・Phase2 以降で効果を付与）
	           "upgrade"   = 数値強化（建物なし）
	build    : StationBuilder に渡す建築タイプ名
	pad      : 購入パッドの位置（区画ローカル X, Z）
	slotX    : dropper の設置 X 座標（出動レーンの位置）
	value    : dropper の1回あたりの報酬 $
	interval : dropper の出動間隔（秒）
	capacityBonus : upgrade で増える回収ボックス容量
	── 建物の効果（Phase 2）──
	grantsVehicle   : 購入すると消防車（VehiclePurchased）を解放
	extinguishBonus : 消火力アップ（0.1 = +10%）
	waveTimeBonus   : ウェーブ制限時間 +秒
	incomeBonus     : 収入倍率アップ（0.2 = +20%）
	kind = "crew"   : 隊員1人を雇う（NPC が区画に出現し、ウェーブ中は消火を支援）
]]
TycoonConfig.Buttons = {
	{ id = "dispatch1", name = "通報センター①", price = 0,    requires = {},
	  kind = "dropper", build = "Dispatch", pad = Vector2.new(-36, 4), slotX = -36, value = 5,  interval = 2 },

	{ id = "hall",      name = "本署（1階）",     price = 50,   requires = { "dispatch1" },
	  kind = "structure", build = "MainHall", pad = Vector2.new(0, -12) },

	{ id = "dispatch2", name = "通報センター②", price = 150,  requires = { "dispatch1" },
	  kind = "dropper", build = "Dispatch", pad = Vector2.new(-12, 4), slotX = -12, value = 12, interval = 2 },

	{ id = "garage",    name = "車庫（消防車解放）", price = 400,  requires = { "hall" },
	  kind = "structure", build = "Garage", pad = Vector2.new(-34, -12), grantsVehicle = true },

	{ id = "dispatch3", name = "通報センター③", price = 800,  requires = { "dispatch2" },
	  kind = "dropper", build = "Dispatch", pad = Vector2.new(12, 4), slotX = 12, value = 30, interval = 2 },

	{ id = "collector1", name = "回収ボックス拡張", price = 1000, requires = { "dispatch2" },
	  kind = "upgrade", build = nil, pad = Vector2.new(24, 4), capacityBonus = 4000 },

	{ id = "tower",     name = "放水塔",           price = 1500, requires = { "garage" },
	  kind = "structure", build = "Tower", pad = Vector2.new(34, -12), extinguishBonus = 0.1 },

	{ id = "dispatch4", name = "通報センター④", price = 3000, requires = { "dispatch3" },
	  kind = "dropper", build = "Dispatch", pad = Vector2.new(36, 4), slotX = 36, value = 75, interval = 2 },

	{ id = "office",    name = "司令室（2階）",   price = 6000, requires = { "tower", "hall" },
	  kind = "structure", build = "Office", pad = Vector2.new(0, -12), incomeBonus = 0.1 },

	-- ── Phase 2: 隊員と増築 ──
	{ id = "quarters",  name = "待機室",           price = 1200, requires = { "garage" },
	  kind = "structure", build = "Quarters", pad = Vector2.new(-66, -12) },

	{ id = "crew1",     name = "隊員を雇う①",     price = 500,  requires = { "quarters" },
	  kind = "crew", pad = Vector2.new(-66, -12) },
	{ id = "crew2",     name = "隊員を雇う②",     price = 900,  requires = { "crew1" },
	  kind = "crew", pad = Vector2.new(-66, -12) },
	{ id = "crew3",     name = "隊員を雇う③",     price = 1600, requires = { "crew2" },
	  kind = "crew", pad = Vector2.new(-66, -12) },

	{ id = "training",  name = "訓練場",           price = 5000, requires = { "crew3" },
	  kind = "structure", build = "Training", pad = Vector2.new(-66, 4), waveTimeBonus = 20 },

	{ id = "collector2", name = "回収ボックス拡張Ⅱ", price = 8000, requires = { "collector1", "dispatch4" },
	  kind = "upgrade", pad = Vector2.new(24, 4), capacityBonus = 20000 },

	{ id = "crew4",     name = "隊員を雇う④",     price = 3500, requires = { "crew3", "training" },
	  kind = "crew", pad = Vector2.new(-66, -12) },
	{ id = "crew5",     name = "隊員を雇う⑤",     price = 6000, requires = { "crew4" },
	  kind = "crew", pad = Vector2.new(-66, -12) },
	{ id = "crew6",     name = "隊員を雇う⑥",     price = 10000, requires = { "crew5" },
	  kind = "crew", pad = Vector2.new(-66, -12) },

	{ id = "ambulance", name = "救急棟",           price = 12000, requires = { "office" },
	  kind = "structure", build = "Ambulance", pad = Vector2.new(66, -12), incomeBonus = 0.2 },

	{ id = "helipad",   name = "ヘリポート",       price = 25000, requires = { "ambulance" },
	  kind = "structure", build = "Helipad", pad = Vector2.new(66, 4), incomeBonus = 0.3 },

	-- 最上位の建物: 本署＋司令室の上に積み上げる高層タワー（パッドは司令室と同じ位置を再利用）
	{ id = "hq",        name = "消防本部タワー",   price = 50000, requires = { "helipad", "office" },
	  kind = "structure", build = "HQTower", pad = Vector2.new(0, -12), incomeBonus = 0.5 },
}

-- id → 定義 の逆引きテーブル
TycoonConfig.ButtonById = {}
for _, def in ipairs(TycoonConfig.Buttons) do
	TycoonConfig.ButtonById[def.id] = def
end

-- 金額を「1.2K」「3.4M」形式に整形（HUD・看板で共通利用）
function TycoonConfig.formatMoney(n)
	n = math.floor(n or 0)
	if n >= 1e9 then
		return string.format("$%.2fB", n / 1e9)
	elseif n >= 1e6 then
		return string.format("$%.2fM", n / 1e6)
	elseif n >= 1e4 then
		return string.format("$%.1fK", n / 1e3)
	end
	return "$" .. tostring(n)
end

return TycoonConfig
