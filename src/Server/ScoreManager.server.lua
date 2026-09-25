--[[
	プレイヤースコア管理（Server / Script）
	参加時に leaderstats、Fires（消火件数）、Points（ショップ通貨）、
	Money（タイクーン通貨 $）、Rank（消防署ランク）を作成する。
]]

local Players = game:GetService("Players")

local function setupLeaderstats(player)
	if player:FindFirstChild("leaderstats") then return end

	local leaderstats = Instance.new("Folder")
	leaderstats.Name   = "leaderstats"
	leaderstats.Parent = player

	local fires = Instance.new("IntValue")
	fires.Name   = "Fires"
	fires.Value  = 0
	fires.Parent = leaderstats

	local points = Instance.new("IntValue")
	points.Name   = "Points"
	points.Value  = 0
	points.Parent = leaderstats

	-- タイクーン通貨（消防署の建設・強化に使う）
	local money = Instance.new("IntValue")
	money.Name   = "Money"
	money.Value  = 0
	money.Parent = leaderstats

	-- 消防署ランク（リバース回数 +1。TycoonConfig.Ranks のインデックス）
	local rank = Instance.new("IntValue")
	rank.Name   = "Rank"
	rank.Value  = 1
	rank.Parent = leaderstats
end

Players.PlayerAdded:Connect(setupLeaderstats)

for _, player in Players:GetPlayers() do
	task.spawn(setupLeaderstats, player)
end

print("[Server] ScoreManager: スコア管理を起動しました。")
