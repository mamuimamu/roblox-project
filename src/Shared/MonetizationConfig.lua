--[[
	MonetizationConfig（Shared / ModuleScript）
	Robux 課金アイテム（ゲームパス・デベロッパー製品）の定義。

	★ id は Creator Dashboard（https://create.roblox.com/）で作成後に記入する。
	   id = 0 のあいだは「準備中」と表示され、購入ボタンは押せない。
	   ・ゲームパス      : 体験 → 収益化 → パス
	   ・デベロッパー製品: 体験 → 収益化 → デベロッパー製品
]]

local MonetizationConfig = {}

-- ── ゲームパス（買い切り・永続）──────────────────────────────
-- key はサーバーで player:SetAttribute("Pass_" .. key, true) として使う
MonetizationConfig.GamePasses = {
	{ key = "DoubleMoney", id = 0, name = "💰 マネー2倍",
	  desc = "すべての $ 収入が永続で2倍になる" },
	{ key = "AutoCollect", id = 0, name = "⚡ 自動回収",
	  desc = "回収ボックスに行かなくても $ が自動で入る" },
	{ key = "VIPTruck",    id = 0, name = "🚒 VIP消防車",
	  desc = "消防車の最高速度 1.3倍・放水銃の消火力 1.5倍" },
	{ key = "EliteCrew",   id = 0, name = "👨‍🚒 精鋭隊員3人",
	  desc = "精鋭隊員3人が常駐（収入+45%・消火支援）" },
	{ key = "OfflineMax",  id = 0, name = "🌙 オフライン収入24時間",
	  desc = "オフライン収入の上限が 8時間 → 24時間" },
}

-- ── デベロッパー製品（消費型・何度でも買える）────────────────
--[[
	kind = "money"  : seconds 秒ぶんの秒間収入を付与（最低 minAmount）
	kind = "boost"  : duration 秒間、収入2倍（重ねて買うと延長）
	kind = "build"  : 今買えるパッドのうち一番安い建物を無料で建てる
]]
MonetizationConfig.Products = {
	{ key = "MoneySmall",  id = 0, name = "💵 資金パック S", kind = "money", seconds = 300,  minAmount = 1000 },
	{ key = "MoneyMedium", id = 0, name = "💵 資金パック M", kind = "money", seconds = 1200, minAmount = 5000 },
	{ key = "MoneyLarge",  id = 0, name = "💵 資金パック L", kind = "money", seconds = 3600, minAmount = 20000 },
	{ key = "Boost2x",     id = 0, name = "⚡ 収入2倍ブースト（15分）", kind = "boost", duration = 900 },
	{ key = "InstantBuild", id = 0, name = "🏗 即時建設", kind = "build",
	  desc = "今買える一番安い建物を無料で建てる" },
}

-- 逆引きテーブル
MonetizationConfig.PassByKey    = {}
MonetizationConfig.PassById     = {}
MonetizationConfig.ProductByKey = {}
MonetizationConfig.ProductById  = {}
for _, pass in ipairs(MonetizationConfig.GamePasses) do
	MonetizationConfig.PassByKey[pass.key] = pass
	if pass.id ~= 0 then MonetizationConfig.PassById[pass.id] = pass end
end
for _, product in ipairs(MonetizationConfig.Products) do
	MonetizationConfig.ProductByKey[product.key] = product
	if product.id ~= 0 then MonetizationConfig.ProductById[product.id] = product end
end

-- 資金パックの付与額（秒間収入 × 秒数、最低額あり）。クライアントの表示と共通
function MonetizationConfig.moneyPackAmount(product, incomePerSec)
	return math.max(product.minAmount, math.floor((incomePerSec or 0) * product.seconds))
end

return MonetizationConfig
