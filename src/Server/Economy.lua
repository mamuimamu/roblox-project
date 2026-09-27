--[[
	Economy（Server / ModuleScript）
	タイクーンの倍率・容量・報酬の計算を一か所に集約する。
	TycoonManager（収入）と BurningHouseManager（消火報酬・消火力・制限時間）の両方から使う。

	倍率の構成: ランク × (1 + 建物 + 隊員 + Premium) × ゲームパス(マネー2倍) × ブースト(2倍)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TycoonConfig   = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("TycoonConfig"))
local PlayerProfiles = require(script.Parent:WaitForChild("PlayerProfiles"))

local Economy = {}

local ELITE_CREW_COUNT = 3  -- 「精鋭隊員3人」ゲームパスで常駐する人数

-- ゲームパス所持（MonetizationManager が player の Attribute に反映する）
function Economy.hasPass(player, key)
	return player ~= nil and player:GetAttribute("Pass_" .. key) == true
end

-- 収入2倍ブーストが有効か（BoostUntil は os.time() 基準の終了時刻）
function Economy.isBoostActive(player)
	local profile = player and PlayerProfiles.get(player)
	return profile ~= nil and (profile.BoostUntil or 0) > os.time()
end

-- Roblox Premium 会員か
function Economy.isPremium(player)
	return player ~= nil and player.MembershipType == Enum.MembershipType.Premium
end

-- 所持ボタン定義を順に返すイテレータ（プロフィール未ロードなら何も返さない）
local function ownedDefs(player)
	local profile = player and PlayerProfiles.get(player)
	local list = {}
	if profile then
		for id in pairs(profile.OwnedButtons) do
			local def = TycoonConfig.ButtonById[id]
			if def then table.insert(list, def) end
		end
	end
	return ipairs(list)
end

-- 指定フィールドの合計（incomeBonus / extinguishBonus / waveTimeBonus / capacityBonus）
local function sumField(player, field)
	local total = 0
	for _, def in ownedDefs(player) do
		total += def[field] or 0
	end
	return total
end

function Economy.owns(player, buttonId)
	local profile = PlayerProfiles.get(player)
	return profile ~= nil and profile.OwnedButtons[buttonId] == true
end

-- 雇っている隊員の人数（ボタンで雇った人数）
function Economy.getHiredCrewCount(player)
	local n = 0
	for _, def in ownedDefs(player) do
		if def.kind == "crew" then n += 1 end
	end
	return n
end

-- 収入・消火支援に効く隊員の総数（雇用 + 精鋭隊員パス）
function Economy.getCrewCount(player)
	local n = Economy.getHiredCrewCount(player)
	if Economy.hasPass(player, "EliteCrew") then
		n += ELITE_CREW_COUNT
	end
	return n
end

Economy.ELITE_CREW_COUNT = ELITE_CREW_COUNT

--[[
	収入倍率 = ランク倍率 × (1 + 建物ボーナス + 隊員ボーナス)
	通報センターの収入と消火報酬の両方に掛かる。
]]
function Economy.getMultiplier(player)
	local profile = PlayerProfiles.get(player)
	local rank    = profile and profile.Rank or 1
	local rankDef = TycoonConfig.Ranks[rank] or TycoonConfig.Ranks[1]

	local bonus = sumField(player, "incomeBonus")
		+ Economy.getCrewCount(player) * TycoonConfig.CrewIncomeBonus
	-- Roblox Premium 会員ボーナス
	if Economy.isPremium(player) then
		bonus += TycoonConfig.PremiumBonus
	end

	local mult = rankDef.mult * (1 + bonus)
	if Economy.hasPass(player, "DoubleMoney") then mult *= 2 end
	if Economy.isBoostActive(player) then mult *= 2 end
	return mult
end

-- 通報センターによる秒間収入（倍率込み）。資金パックの付与額計算などに使う
function Economy.getIncomePerSecond(player)
	local ips = 0
	for _, def in ownedDefs(player) do
		if def.kind == "dropper" then
			ips += def.value / def.interval
		end
	end
	return ips * Economy.getMultiplier(player)
end

-- 回収ボックスの容量
function Economy.getCapacity(player)
	return TycoonConfig.CollectorBaseCapacity + sumField(player, "capacityBonus")
end

-- 消火力の倍率（放水塔など）
function Economy.getExtinguishMultiplier(player)
	return 1 + sumField(player, "extinguishBonus")
end

-- ウェーブ制限時間の追加秒数（訓練場など）
function Economy.getWaveTimeBonus(player)
	return sumField(player, "waveTimeBonus")
end

--[[
	消火1件あたりの $ 報酬。
	remainingRatio: 残り時間 / 制限時間（0〜1）。早く消すほど多い。
]]
function Economy.getFireReward(player, wave, remainingRatio)
	local base = TycoonConfig.FireMoneyBase
		+ TycoonConfig.FireMoneyPerWave * wave
		+ TycoonConfig.FireMoneyTimeBonusMax * math.clamp(remainingRatio, 0, 1)
	return math.floor(base * Economy.getMultiplier(player))
end

return Economy
