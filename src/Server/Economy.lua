--[[
	Economy（Server / ModuleScript）
	タイクーンの倍率・容量・報酬の計算を一か所に集約する。
	TycoonManager（収入）と BurningHouseManager（消火報酬・消火力・制限時間）の両方から使う。

	Phase 4（ゲームパス・ブースト）/ Phase 5（Premium）の倍率も getMultiplier に追加していく。
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TycoonConfig   = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("TycoonConfig"))
local PlayerProfiles = require(script.Parent:WaitForChild("PlayerProfiles"))

local Economy = {}

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

-- 雇っている隊員の人数
function Economy.getCrewCount(player)
	local n = 0
	for _, def in ownedDefs(player) do
		if def.kind == "crew" then n += 1 end
	end
	return n
end

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

	return rankDef.mult * (1 + bonus)
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
