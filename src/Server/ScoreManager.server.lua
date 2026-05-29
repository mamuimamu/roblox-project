--[[
	プレイヤースコア管理（Server / Script）
	参加時に leaderstats、Fires（消火件数）、Points（ショップ通貨）を作成する。
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
end

Players.PlayerAdded:Connect(setupLeaderstats)

for _, player in Players:GetPlayers() do
	task.spawn(setupLeaderstats, player)
end

print("[Server] ScoreManager: スコア管理を起動しました。")
