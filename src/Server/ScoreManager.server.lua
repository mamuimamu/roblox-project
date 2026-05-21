--[[
	プレイヤースコア管理（Server / Script）
	参加時に leaderstats と Fires（消火数）を作成する。
]]

local Players = game:GetService("Players")

local function setupLeaderstats(player)
	if player:FindFirstChild("leaderstats") then
		return
	end

	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	leaderstats.Parent = player

	local fires = Instance.new("IntValue")
	fires.Name = "Fires"
	fires.Value = 0
	fires.Parent = leaderstats
end

local function onPlayerAdded(player)
	setupLeaderstats(player)
end

Players.PlayerAdded:Connect(onPlayerAdded)

for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end

print("[Server] ScoreManager: スコア管理を起動しました。")
