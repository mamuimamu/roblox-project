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
}

return GameConfig
