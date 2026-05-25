--[[
	ゲーム全体のパラメータ管理（Shared / ModuleScript）
	サーバー・クライアント双方から require して利用する。
]]

local GameConfig = {
	FireMaxHealth = 100,
	ExtinguisherDamage = 20,
	ExtinguisherRange = 30,
	PointsPerFire = 1,
	TruckMaxSpeed = 50,
	TruckSteerSpeed = 1,
	RescueTruckMaxSpeed = 50,   -- mph（元デフォルト 75mph の 2/3）
	RescueTruckTorque   = 6000, -- 加速トルク（元デフォルト 30000 の 1/5）
	WaterCannonExtinguishTime = 3,
	WaterCannonRange = 200,
}

return GameConfig
