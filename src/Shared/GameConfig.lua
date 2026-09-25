--[[
	ゲーム全体のパラメータ管理（Shared / ModuleScript）
	サーバー・クライアント双方から require して利用する。
]]

local GameConfig = {
	-- ── モード設定 ──────────────────────────────────────────
	-- "solo"  : 1人専用（定員超過は自動キック）
	-- "multi" : 将来実装予定（ロビー画面で選択式にする）
	GameMode   = "solo",
	MaxPlayers = 1,

	-- ── ゲームパラメータ ────────────────────────────────────
	FireMaxHealth             = 100,
	ExtinguisherDamage        = 20,
	ExtinguisherRange         = 30,
	PointsPerFire             = 10,   -- 消火1件あたりの固定ポイント
	TimeBonusMax              = 20,   -- 残り時間に応じた最大ボーナス
	TruckMaxSpeed             = 50,
	TruckSteerSpeed           = 1,
	RescueTruckMaxSpeed       = 50,
	RescueTruckTorque         = 6000,
	WaterCannonExtinguishTime = 3,
	WaterCannonRange          = 200,
	WaveTimeLimit             = 180,
	ShopDuration              = 15,   -- ウェーブ間ショップ表示秒数
	ShopItems = {
		-- 消防車は Phase 2 から消防署タイクーンの「車庫」建設で解放する（TycoonConfig 参照）
		{ id = "waterBoost",  name = "消火強化",   desc = "消火力 1.5倍（今Wave）",       price = 25  },
		{ id = "timeExtend",  name = "時間延長",   desc = "次Wave +60秒",                 price = 40  },
		{ id = "speedBoost",  name = "スピードUP", desc = "移動速度 1.5倍（今Wave）",     price = 15  },
	},
}

return GameConfig
