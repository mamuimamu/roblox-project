--[[
	RetentionUIController（Client / LocalScript）
	Phase 5 のダイアログ表示。
	  ・オフライン収入（OfflineEarningsEvent）: 「おかえりなさい！」＋獲得額（サーバー側で付与済み）
	  ・デイリーボーナス（DailyRewardEvent）  : 7日分のカード＋「受け取る」ボタン
	ダイアログは順番に1つずつ表示する（オフライン → デイリー の順に届く）。
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Shared       = ReplicatedStorage:WaitForChild("Shared")
local TycoonConfig = require(Shared:WaitForChild("TycoonConfig"))

local OfflineEarningsEvent = ReplicatedStorage:WaitForChild("OfflineEarningsEvent")
local DailyRewardEvent     = ReplicatedStorage:WaitForChild("DailyRewardEvent")
local DailyClaimedEvent    = ReplicatedStorage:WaitForChild("DailyClaimedEvent")

local GOLD = Color3.fromRGB(215, 160, 20)

local screenGui = Instance.new("ScreenGui")
screenGui.Name           = "RetentionUI"
screenGui.ResetOnSpawn   = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.DisplayOrder   = 10  -- ショップより手前
screenGui.Parent         = playerGui

local function addCorner(inst, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or 8)
	c.Parent       = inst
end

local function makeLabel(parent, text, pos, size, textSize, color, font)
	local label = Instance.new("TextLabel")
	label.Position               = pos
	label.Size                   = size
	label.BackgroundTransparency = 1
	label.Font                   = font or Enum.Font.GothamBold
	label.TextSize               = textSize
	label.TextColor3             = color or Color3.new(1, 1, 1)
	label.TextWrapped            = true
	label.Text                   = text
	label.Parent                 = parent
	return label
end

-- ── ダイアログのキュー ───────────────────────────────────────

local queue   = {}     -- 表示待ちの「ダイアログを作る関数」
local showing = false

local showNext

-- 共通の枠を作る。close() を呼ぶと閉じて次のダイアログへ進む
local function makeDialog(height)
	local panel = Instance.new("Frame")
	panel.AnchorPoint      = Vector2.new(0.5, 0.5)
	panel.Position         = UDim2.fromScale(0.5, 0.5)
	panel.Size             = UDim2.new(0.92, 0, 0, height)
	panel.BackgroundColor3 = Color3.fromRGB(25, 25, 32)
	panel.BorderSizePixel  = 0
	panel.Parent           = screenGui
	addCorner(panel, 12)

	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(460, height)
	limit.Parent  = panel

	local stroke = Instance.new("UIStroke")
	stroke.Color     = GOLD
	stroke.Thickness = 2
	stroke.Parent    = panel

	-- ポンと出るアニメーション
	local scale = Instance.new("UIScale")
	scale.Scale  = 0.6
	scale.Parent = panel
	TweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Scale = 1 }):Play()

	local function close()
		panel:Destroy()
		showing = false
		showNext()
	end
	return panel, close
end

local function makeButton(parent, text, color, onClick)
	local btn = Instance.new("TextButton")
	btn.AnchorPoint      = Vector2.new(0.5, 1)
	btn.Position         = UDim2.new(0.5, 0, 1, -16)
	btn.Size             = UDim2.new(0.6, 0, 0, 46)
	btn.BackgroundColor3 = color
	btn.Font             = Enum.Font.GothamBlack
	btn.TextSize         = 20
	btn.TextColor3       = Color3.new(1, 1, 1)
	btn.Text             = text
	btn.Parent           = parent
	addCorner(btn, 10)
	btn.Activated:Connect(onClick)
	return btn
end

function showNext()
	if showing or #queue == 0 then return end
	showing = true
	local build = table.remove(queue, 1)
	build()
end

local function enqueue(build)
	table.insert(queue, build)
	showNext()
end

-- ── オフライン収入 ──────────────────────────────────────────

OfflineEarningsEvent.OnClientEvent:Connect(function(amount, seconds, capHours)
	enqueue(function()
		local panel, close = makeDialog(250)
		makeLabel(panel, "🚒 おかえりなさい！", UDim2.new(0, 16, 0, 14), UDim2.new(1, -32, 0, 34), 26,
			Color3.fromRGB(255, 215, 80), Enum.Font.GothamBlack)

		local h = math.floor(seconds / 3600)
		local m = math.floor((seconds % 3600) / 60)
		makeLabel(panel, ("留守の %d時間%d分 のあいだに隊員たちが稼ぎました"):format(h, m),
			UDim2.new(0, 16, 0, 56), UDim2.new(1, -32, 0, 40), 16, Color3.fromRGB(220, 220, 220), Enum.Font.Gotham)
		makeLabel(panel, "+" .. TycoonConfig.formatMoney(amount), UDim2.new(0, 16, 0, 98), UDim2.new(1, -32, 0, 50), 40,
			Color3.fromRGB(120, 255, 140), Enum.Font.GothamBlack)
		makeLabel(panel, ("（最大 %d時間ぶんまで）"):format(capHours), UDim2.new(0, 16, 0, 146), UDim2.new(1, -32, 0, 20), 13,
			Color3.fromRGB(160, 160, 160), Enum.Font.Gotham)

		makeButton(panel, "受け取る", Color3.fromRGB(60, 170, 80), close)
	end)
end)

-- ── デイリーボーナス ────────────────────────────────────────

DailyRewardEvent.OnClientEvent:Connect(function(day, amounts)
	enqueue(function()
		local panel, close = makeDialog(300)
		makeLabel(panel, "🎁 デイリーボーナス", UDim2.new(0, 16, 0, 14), UDim2.new(1, -32, 0, 34), 26,
			Color3.fromRGB(255, 215, 80), Enum.Font.GothamBlack)
		makeLabel(panel, ("連続ログイン %d日目！ 毎日来るほど豪華になります"):format(day),
			UDim2.new(0, 16, 0, 52), UDim2.new(1, -32, 0, 22), 15, Color3.fromRGB(220, 220, 220), Enum.Font.Gotham)

		-- 7日分のカード
		local cards = Instance.new("Frame")
		cards.Position               = UDim2.new(0, 12, 0, 84)
		cards.Size                   = UDim2.new(1, -24, 0, 130)
		cards.BackgroundTransparency = 1
		cards.Parent                 = panel
		local grid = Instance.new("UIGridLayout")
		grid.CellSize    = UDim2.new(1 / 4, -6, 0, 60)
		grid.CellPadding = UDim2.new(0, 6, 0, 6)
		grid.SortOrder   = Enum.SortOrder.LayoutOrder
		grid.Parent      = cards

		for d = 1, #TycoonConfig.DailyRewards do
			local card = Instance.new("Frame")
			card.LayoutOrder      = d
			card.BackgroundColor3 = (d == day and GOLD)
				or (d < day and Color3.fromRGB(50, 90, 60))
				or Color3.fromRGB(50, 50, 62)
			card.Parent = cards
			addCorner(card, 8)

			local label = d < day and "✔ 受取済" or ("Day " .. d)
			if d == #TycoonConfig.DailyRewards then label ..= " ⚡" end  -- 7日目はブースト付き
			makeLabel(card, label, UDim2.new(0, 0, 0, 4), UDim2.new(1, 0, 0, 22), 14)
			makeLabel(card, TycoonConfig.formatMoney(amounts[d] or 0), UDim2.new(0, 0, 0, 28), UDim2.new(1, 0, 0, 26), 15,
				Color3.fromRGB(120, 255, 140), Enum.Font.GothamBlack)
		end

		local btn
		btn = makeButton(panel, ("Day %d を受け取る"):format(day), GOLD, function()
			btn.Active = false
			DailyRewardEvent:FireServer()
			close()
		end)
	end)
end)

-- 受け取り結果のポップアップ
DailyClaimedEvent.OnClientEvent:Connect(function(day, amount, boostMinutes)
	local text = ("🎁 Day %d: +%s"):format(day, TycoonConfig.formatMoney(amount))
	if boostMinutes then
		text ..= ("  ⚡2倍ブースト %d分"):format(boostMinutes)
	end
	local label = makeLabel(screenGui, text, UDim2.new(0.5, -260, 0, 90), UDim2.new(0, 520, 0, 44), 28,
		Color3.fromRGB(255, 215, 80), Enum.Font.GothamBlack)
	label.TextStrokeTransparency = 0.2
	TweenService:Create(label, TweenInfo.new(3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		TextTransparency = 1, TextStrokeTransparency = 1,
	}):Play()
	task.delay(3.1, function() label:Destroy() end)
end)

print("[RetentionUIController] リテンションUIを起動しました。")
