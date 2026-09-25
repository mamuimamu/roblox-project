--[[
	PlayerProfiles（Server / ModuleScript）
	leaderstats に載せないプレイヤーデータ（所持ボタン・ランク・課金履歴など）を
	サーバー内のテーブルで保持する共有ストア。

	・DataManager がロード時に set し、セーブ時に get して DataStore に書き込む。
	・TycoonManager などは get で取得したテーブルを直接書き換える
	  （同じ VM 内の require は同一テーブルを返すため、BindableFunction のような
	    テーブルのコピーが発生しない）。
]]

local PlayerProfiles = {}

local profiles = {}  -- [Player] = profile テーブル

-- 新規プレイヤー用の既定プロフィール
function PlayerProfiles.default()
	return {
		OwnedButtons    = {},  -- [buttonId] = true
		Rank            = 1,   -- TycoonConfig.Ranks のインデックス
		CrewCount       = 0,   -- 隊員数（Phase 2）
		LastOnline      = 0,   -- 最終オンライン時刻 os.time()（Phase 5 オフライン収入）
		DailyStreak     = 0,   -- 連続ログイン日数（Phase 5）
		LastDailyClaim  = 0,   -- 最後にデイリー報酬を受け取った日（Phase 5）
		PurchaseHistory = {},  -- 付与済みレシートID（Phase 4 の二重付与防止）
	}
end

function PlayerProfiles.set(player, profile)
	profiles[player] = profile
end

function PlayerProfiles.get(player)
	return profiles[player]
end

-- ロード完了まで待つ（DataManager が DataLoaded 属性を立てるまで）
function PlayerProfiles.waitFor(player, timeout)
	local deadline = os.clock() + (timeout or 15)
	while not profiles[player] and player.Parent and os.clock() < deadline do
		task.wait(0.1)
	end
	return profiles[player]
end

function PlayerProfiles.remove(player)
	profiles[player] = nil
end

return PlayerProfiles
