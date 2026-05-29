--[[
	スコアUI + ウェーブタイマーUI + ショップUI（Client / LocalScript）
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Shared     = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))

local WAVE_TIME_LIMIT = GameConfig.WaveTimeLimit

local screenGui
local waveTimerThread = nil
local shopUI          = nil  -- ショップオーバーレイ（開いている間 non-nil）
local pendingShopData = nil  -- ShopOpenEvent で受け取ったデータ

-- ── ユーティリティ ──────────────────────────────────────────

local function formatTime(seconds)
	local m = math.floor(seconds / 60)
	local s = seconds % 60
	return string.format("%d:%02d", m, s)
end

local function getPoints()
	local ls = player:FindFirstChild("leaderstats")
	if not ls then return 0 end
	local p = ls:FindFirstChild("Points")
	return p and p.Value or 0
end

-- ── スコアパネル（左下）────────────────────────────────────

local function createScoreUI()
	screenGui = Instance.new("ScreenGui")
	screenGui.Name           = "ScoreUI"
	screenGui.ResetOnSpawn   = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Parent         = playerGui

	local frame = Instance.new("Frame")
	frame.Name                  = "ScorePanel"
	frame.AnchorPoint           = Vector2.new(0, 1)
	frame.Position              = UDim2.new(0, 16, 1, -16)
	frame.Size                  = UDim2.new(0, 200, 0, 48)
	frame.BackgroundColor3      = Color3.fromRGB(0, 0, 0)
	frame.BackgroundTransparency = 0.45
	frame.BorderSizePixel       = 0
	frame.Parent                = screenGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = frame

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft   = UDim.new(0, 12)
	padding.PaddingRight  = UDim.new(0, 12)
	padding.PaddingTop    = UDim.new(0, 8)
	padding.PaddingBottom = UDim.new(0, 8)
	padding.Parent = frame

	local label = Instance.new("TextLabel")
	label.Name                 = "ScoreLabel"
	label.Size                 = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Font                 = Enum.Font.GothamBold
	label.TextSize             = 20
	label.TextColor3           = Color3.fromRGB(255, 230, 80)
	label.TextXAlignment       = Enum.TextXAlignment.Left
	label.TextYAlignment       = Enum.TextYAlignment.Center
	label.Text                 = "スコア: 0 pt"
	label.Parent               = frame

	return label
end

local function bindScoreLabel(label)
	local leaderstats = player:WaitForChild("leaderstats")
	local points = leaderstats:WaitForChild("Points")

	local function update()
		label.Text = "スコア: " .. tostring(points.Value) .. " pt"
	end
	update()
	points:GetPropertyChangedSignal("Value"):Connect(update)

	-- ショップ内ポイント表示も合わせて更新
	points:GetPropertyChangedSignal("Value"):Connect(function()
		if shopUI then
			local lbl = shopUI:FindFirstChild("PointsLabel", true)
			if lbl then lbl.Text = "所持ポイント: " .. tostring(points.Value) .. " pt" end
		end
	end)
end

-- ── ウェーブパネル（上部中央）──────────────────────────────

local function createWaveUI()
	local frame = Instance.new("Frame")
	frame.Name                  = "WavePanel"
	frame.AnchorPoint           = Vector2.new(0.5, 0)
	frame.Position              = UDim2.new(0.5, 0, 0, 16)
	frame.Size                  = UDim2.new(0, 180, 0, 90)
	frame.BackgroundColor3      = Color3.fromRGB(0, 0, 0)
	frame.BackgroundTransparency = 0.45
	frame.BorderSizePixel       = 0
	frame.Parent                = screenGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = frame

	local waveLabel = Instance.new("TextLabel")
	waveLabel.Name               = "WaveLabel"
	waveLabel.Size               = UDim2.new(1, 0, 0.36, 0)
	waveLabel.Position           = UDim2.new(0, 0, 0, 0)
	waveLabel.BackgroundTransparency = 1
	waveLabel.Font               = Enum.Font.GothamBold
	waveLabel.TextSize           = 20
	waveLabel.TextColor3         = Color3.fromRGB(255, 200, 50)
	waveLabel.TextXAlignment     = Enum.TextXAlignment.Center
	waveLabel.TextYAlignment     = Enum.TextYAlignment.Center
	waveLabel.Text               = "Wave --"
	waveLabel.Parent             = frame

	local timerLabel = Instance.new("TextLabel")
	timerLabel.Name               = "TimerLabel"
	timerLabel.Size               = UDim2.new(1, 0, 0.36, 0)
	timerLabel.Position           = UDim2.new(0, 0, 0.36, 0)
	timerLabel.BackgroundTransparency = 1
	timerLabel.Font               = Enum.Font.GothamBold
	timerLabel.TextSize           = 18
	timerLabel.TextColor3         = Color3.fromRGB(255, 255, 255)
	timerLabel.TextXAlignment     = Enum.TextXAlignment.Center
	timerLabel.TextYAlignment     = Enum.TextYAlignment.Center
	timerLabel.Text               = formatTime(WAVE_TIME_LIMIT)
	timerLabel.Parent             = frame

	local fireLabel = Instance.new("TextLabel")
	fireLabel.Name               = "FireLabel"
	fireLabel.Size               = UDim2.new(1, 0, 0.28, 0)
	fireLabel.Position           = UDim2.new(0, 0, 0.72, 0)
	fireLabel.BackgroundTransparency = 1
	fireLabel.Font               = Enum.Font.Gotham
	fireLabel.TextSize           = 16
	fireLabel.TextColor3         = Color3.fromRGB(255, 160, 80)
	fireLabel.TextXAlignment     = Enum.TextXAlignment.Center
	fireLabel.TextYAlignment     = Enum.TextYAlignment.Center
	fireLabel.Text               = ""
	fireLabel.Parent             = frame

	return waveLabel, timerLabel, fireLabel
end

local scoreLabel = createScoreUI()
local waveLabel, timerLabel, fireLabel = createWaveUI()
bindScoreLabel(scoreLabel)

-- ── カウントダウン ───────────────────────────────────────────

local function stopCountdown()
	if waveTimerThread then
		task.cancel(waveTimerThread)
		waveTimerThread = nil
	end
end

local function startCountdown(seconds)
	stopCountdown()
	waveTimerThread = task.spawn(function()
		local remaining = seconds
		while remaining > 0 do
			timerLabel.Text      = formatTime(remaining)
			timerLabel.TextColor3 = remaining <= 30
				and Color3.fromRGB(255, 80, 50)
				or  Color3.fromRGB(255, 255, 255)
			task.wait(1)
			remaining -= 1
		end
		timerLabel.Text      = "0:00"
		timerLabel.TextColor3 = Color3.fromRGB(255, 80, 50)
	end)
end

-- ── ミッション完了アニメーション ────────────────────────────

local function showMissionComplete()
	local overlay = Instance.new("Frame")
	overlay.Name                  = "MissionCompleteOverlay"
	overlay.Size                  = UDim2.new(1, 0, 1, 0)
	overlay.BackgroundColor3      = Color3.fromRGB(0, 0, 0)
	overlay.BackgroundTransparency = 1
	overlay.ZIndex                = 10
	overlay.Parent                = screenGui

	local title = Instance.new("TextLabel")
	title.Size                 = UDim2.new(1, 0, 0, 80)
	title.Position             = UDim2.new(0, 0, 0.4, 0)
	title.BackgroundTransparency = 1
	title.Font                 = Enum.Font.GothamBold
	title.TextSize             = 64
	title.TextColor3           = Color3.fromRGB(255, 215, 0)
	title.TextStrokeTransparency = 0.4
	title.Text                 = "ミッション完了！"
	title.TextTransparency     = 1
	title.ZIndex               = 11
	title.Parent               = overlay

	local sub = Instance.new("TextLabel")
	sub.Size                 = UDim2.new(1, 0, 0, 36)
	sub.Position             = UDim2.new(0, 0, 0.4, 88)
	sub.BackgroundTransparency = 1
	sub.Font                 = Enum.Font.Gotham
	sub.TextSize             = 28
	sub.TextColor3           = Color3.fromRGB(255, 255, 255)
	sub.Text                 = "全ての火を消し止めました！"
	sub.TextTransparency     = 1
	sub.ZIndex               = 11
	sub.Parent               = overlay

	local tweenIn = TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(overlay, tweenIn, { BackgroundTransparency = 0.55 }):Play()
	TweenService:Create(title,   tweenIn, { TextTransparency = 0 }):Play()
	TweenService:Create(sub,     tweenIn, { TextTransparency = 0 }):Play()

	task.wait(2.5)

	local tweenOut = TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	TweenService:Create(overlay, tweenOut, { BackgroundTransparency = 1 }):Play()
	TweenService:Create(title,   tweenOut, { TextTransparency = 1 }):Play()
	local lastTween = TweenService:Create(sub, tweenOut, { TextTransparency = 1 })
	lastTween:Play()
	lastTween.Completed:Wait()
	overlay:Destroy()
end

-- ── ウェーブ開始アニメーション ───────────────────────────────

local function showWaveStart(wave, fireCount)
	local overlay = Instance.new("Frame")
	overlay.Name                  = "WaveStartOverlay"
	overlay.Size                  = UDim2.new(1, 0, 1, 0)
	overlay.BackgroundColor3      = Color3.fromRGB(0, 0, 0)
	overlay.BackgroundTransparency = 1
	overlay.ZIndex                = 10
	overlay.Parent                = screenGui

	local title = Instance.new("TextLabel")
	title.Size                 = UDim2.new(1, 0, 0, 70)
	title.Position             = UDim2.new(0, 0, 0.38, 0)
	title.BackgroundTransparency = 1
	title.Font                 = Enum.Font.GothamBold
	title.TextSize             = 56
	title.TextColor3           = Color3.fromRGB(255, 80, 20)
	title.TextStrokeTransparency = 0.4
	title.Text                 = "Wave " .. wave .. " 開始！"
	title.TextTransparency     = 1
	title.ZIndex               = 11
	title.Parent               = overlay

	local sub = Instance.new("TextLabel")
	sub.Size                 = UDim2.new(1, 0, 0, 32)
	sub.Position             = UDim2.new(0, 0, 0.38, 78)
	sub.BackgroundTransparency = 1
	sub.Font                 = Enum.Font.Gotham
	sub.TextSize             = 24
	sub.TextColor3           = Color3.fromRGB(255, 255, 255)
	sub.Text                 = "火事が " .. fireCount .. " 件発生！"
	sub.TextTransparency     = 1
	sub.ZIndex               = 11
	sub.Parent               = overlay

	local tweenIn = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(overlay, tweenIn, { BackgroundTransparency = 0.6 }):Play()
	TweenService:Create(title,   tweenIn, { TextTransparency = 0 }):Play()
	TweenService:Create(sub,     tweenIn, { TextTransparency = 0 }):Play()

	task.wait(2)

	local tweenOut = TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	TweenService:Create(overlay, tweenOut, { BackgroundTransparency = 1 }):Play()
	TweenService:Create(title,   tweenOut, { TextTransparency = 1 }):Play()
	local lastTween = TweenService:Create(sub, tweenOut, { TextTransparency = 1 })
	lastTween:Play()
	lastTween.Completed:Wait()
	overlay:Destroy()
end

-- ── タイムオーバーダイアログ ─────────────────────────────────

local function showTimeOverDialog()
	stopCountdown()
	timerLabel.Text      = "0:00"
	timerLabel.TextColor3 = Color3.fromRGB(255, 80, 50)

	local overlay = Instance.new("Frame")
	overlay.Name                  = "TimeOverOverlay"
	overlay.Size                  = UDim2.new(1, 0, 1, 0)
	overlay.BackgroundColor3      = Color3.fromRGB(0, 0, 0)
	overlay.BackgroundTransparency = 0.4
	overlay.ZIndex                = 20
	overlay.Parent                = screenGui

	local panel = Instance.new("Frame")
	panel.Size                  = UDim2.new(0, 340, 0, 210)
	panel.AnchorPoint           = Vector2.new(0.5, 0.5)
	panel.Position              = UDim2.new(0.5, 0, 0.5, 0)
	panel.BackgroundColor3      = Color3.fromRGB(18, 18, 18)
	panel.BackgroundTransparency = 0.05
	panel.BorderSizePixel       = 0
	panel.ZIndex                = 21
	panel.Parent                = overlay

	local panelCorner = Instance.new("UICorner")
	panelCorner.CornerRadius = UDim.new(0, 12)
	panelCorner.Parent = panel

	local title = Instance.new("TextLabel")
	title.Size                 = UDim2.new(1, 0, 0, 64)
	title.Position             = UDim2.new(0, 0, 0, 18)
	title.BackgroundTransparency = 1
	title.Font                 = Enum.Font.GothamBold
	title.TextSize             = 46
	title.TextColor3           = Color3.fromRGB(255, 80, 50)
	title.Text                 = "タイムオーバー！"
	title.ZIndex               = 22
	title.Parent               = panel

	local sub = Instance.new("TextLabel")
	sub.Size                 = UDim2.new(1, 0, 0, 34)
	sub.Position             = UDim2.new(0, 0, 0, 90)
	sub.BackgroundTransparency = 1
	sub.Font                 = Enum.Font.Gotham
	sub.TextSize             = 24
	sub.TextColor3           = Color3.fromRGB(220, 220, 220)
	sub.Text                 = "リトライしますか？"
	sub.ZIndex               = 22
	sub.Parent               = panel

	local retryBtn = Instance.new("TextButton")
	retryBtn.Size             = UDim2.new(0, 130, 0, 46)
	retryBtn.Position         = UDim2.new(0.5, -144, 1, -62)
	retryBtn.BackgroundColor3 = Color3.fromRGB(230, 90, 30)
	retryBtn.BorderSizePixel  = 0
	retryBtn.Font             = Enum.Font.GothamBold
	retryBtn.TextSize         = 22
	retryBtn.TextColor3       = Color3.fromRGB(255, 255, 255)
	retryBtn.Text             = "リトライ"
	retryBtn.ZIndex           = 22
	retryBtn.Parent           = panel

	local rc = Instance.new("UICorner")
	rc.CornerRadius = UDim.new(0, 8)
	rc.Parent = retryBtn

	local giveUpBtn = Instance.new("TextButton")
	giveUpBtn.Size             = UDim2.new(0, 130, 0, 46)
	giveUpBtn.Position         = UDim2.new(0.5, 14, 1, -62)
	giveUpBtn.BackgroundColor3 = Color3.fromRGB(70, 70, 70)
	giveUpBtn.BorderSizePixel  = 0
	giveUpBtn.Font             = Enum.Font.GothamBold
	giveUpBtn.TextSize         = 22
	giveUpBtn.TextColor3       = Color3.fromRGB(200, 200, 200)
	giveUpBtn.Text             = "あきらめる"
	giveUpBtn.ZIndex           = 22
	giveUpBtn.Parent           = panel

	local gc = Instance.new("UICorner")
	gc.CornerRadius = UDim.new(0, 8)
	gc.Parent = giveUpBtn

	local RetryWaveEvent = ReplicatedStorage:WaitForChild("RetryWaveEvent")

	retryBtn.MouseButton1Click:Connect(function()
		overlay:Destroy()
		RetryWaveEvent:FireServer()
	end)
	giveUpBtn.MouseButton1Click:Connect(function()
		overlay:Destroy()
	end)
end

-- ── ショップUI ───────────────────────────────────────────────

local function applyShopItemState(row, bought, buyerName)
	local btn  = row:FindFirstChild("BuyBtn")
	if not btn then return end
	if bought then
		btn.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
		btn.TextColor3       = Color3.fromRGB(140, 140, 140)
		btn.Text             = "購入済み\n" .. (buyerName or "")
		btn.Active           = false
		btn.AutoButtonColor  = false
	else
		btn.BackgroundColor3 = Color3.fromRGB(40, 160, 70)
		btn.TextColor3       = Color3.fromRGB(255, 255, 255)
		btn.Text             = "購入"
		btn.Active           = true
		btn.AutoButtonColor  = true
	end
end

local function showShopUI(data)
	if shopUI then shopUI:Destroy() end

	local overlay = Instance.new("Frame")
	overlay.Name                  = "ShopOverlay"
	overlay.Size                  = UDim2.new(1, 0, 1, 0)
	overlay.BackgroundColor3      = Color3.fromRGB(0, 0, 0)
	overlay.BackgroundTransparency = 0.5
	overlay.ZIndex                = 15
	overlay.Parent                = screenGui
	shopUI = overlay

	-- パネル本体
	local panel = Instance.new("Frame")
	panel.Name                  = "ShopPanel"
	panel.Size                  = UDim2.new(0, 360, 0, 278)
	panel.AnchorPoint           = Vector2.new(0.5, 0.5)
	panel.Position              = UDim2.new(0.5, 0, 0.5, 0)
	panel.BackgroundColor3      = Color3.fromRGB(12, 14, 24)
	panel.BackgroundTransparency = 0.05
	panel.BorderSizePixel       = 0
	panel.ZIndex                = 16
	panel.Parent                = overlay

	local pc = Instance.new("UICorner")
	pc.CornerRadius = UDim.new(0, 14)
	pc.Parent = panel

	-- ヘッダー行
	local header = Instance.new("Frame")
	header.Size             = UDim2.new(1, 0, 0, 44)
	header.BackgroundColor3 = Color3.fromRGB(20, 24, 40)
	header.BorderSizePixel  = 0
	header.ZIndex           = 17
	header.Parent           = panel

	local hc = Instance.new("UICorner")
	hc.CornerRadius = UDim.new(0, 14)
	hc.Parent = header

	local headerTitle = Instance.new("TextLabel")
	headerTitle.Size                 = UDim2.new(0.6, 0, 1, 0)
	headerTitle.Position             = UDim2.new(0, 14, 0, 0)
	headerTitle.BackgroundTransparency = 1
	headerTitle.Font                 = Enum.Font.GothamBold
	headerTitle.TextSize             = 18
	headerTitle.TextColor3           = Color3.fromRGB(255, 255, 255)
	headerTitle.TextXAlignment       = Enum.TextXAlignment.Left
	headerTitle.TextYAlignment       = Enum.TextYAlignment.Center
	headerTitle.Text                 = "アイテムショップ"
	headerTitle.ZIndex               = 18
	headerTitle.Parent               = header

	local countdownLabel = Instance.new("TextLabel")
	countdownLabel.Name                 = "ShopCountdown"
	countdownLabel.Size                 = UDim2.new(0.4, -10, 1, 0)
	countdownLabel.Position             = UDim2.new(0.6, 0, 0, 0)
	countdownLabel.BackgroundTransparency = 1
	countdownLabel.Font                 = Enum.Font.GothamBold
	countdownLabel.TextSize             = 15
	countdownLabel.TextColor3           = Color3.fromRGB(255, 180, 60)
	countdownLabel.TextXAlignment       = Enum.TextXAlignment.Right
	countdownLabel.TextYAlignment       = Enum.TextYAlignment.Center
	countdownLabel.Text                 = "次Wave: " .. data.duration .. "s"
	countdownLabel.ZIndex               = 18
	countdownLabel.Parent               = header

	-- ポイント表示行
	local pointsRow = Instance.new("Frame")
	pointsRow.Size             = UDim2.new(1, 0, 0, 34)
	pointsRow.Position         = UDim2.new(0, 0, 0, 44)
	pointsRow.BackgroundTransparency = 1
	pointsRow.ZIndex           = 17
	pointsRow.Parent           = panel

	local pointsLabel = Instance.new("TextLabel")
	pointsLabel.Name                 = "PointsLabel"
	pointsLabel.Size                 = UDim2.new(1, -20, 1, 0)
	pointsLabel.Position             = UDim2.new(0, 14, 0, 0)
	pointsLabel.BackgroundTransparency = 1
	pointsLabel.Font                 = Enum.Font.GothamBold
	pointsLabel.TextSize             = 16
	pointsLabel.TextColor3           = Color3.fromRGB(255, 220, 60)
	pointsLabel.TextXAlignment       = Enum.TextXAlignment.Left
	pointsLabel.TextYAlignment       = Enum.TextYAlignment.Center
	pointsLabel.Text                 = "所持ポイント: " .. getPoints() .. " pt"
	pointsLabel.ZIndex               = 18
	pointsLabel.Parent               = pointsRow

	-- 区切り線
	local divider = Instance.new("Frame")
	divider.Size             = UDim2.new(1, -20, 0, 1)
	divider.Position         = UDim2.new(0, 10, 0, 78)
	divider.BackgroundColor3 = Color3.fromRGB(60, 60, 80)
	divider.BorderSizePixel  = 0
	divider.ZIndex           = 17
	divider.Parent           = panel

	-- アイテムリスト
	local itemList = Instance.new("Frame")
	itemList.Name             = "ItemList"
	itemList.Size             = UDim2.new(1, 0, 0, 198)
	itemList.Position         = UDim2.new(0, 0, 0, 80)
	itemList.BackgroundTransparency = 1
	itemList.ZIndex           = 17
	itemList.Parent           = panel

	local ShopBuyEvent  = ReplicatedStorage:WaitForChild("ShopBuyEvent")

	local itemRows = {}  -- [itemId] = row Frame

	for idx, item in ipairs(GameConfig.ShopItems) do
		local row = Instance.new("Frame")
		row.Name             = item.id
		row.Size             = UDim2.new(1, 0, 0, 66)
		row.Position         = UDim2.new(0, 0, 0, (idx - 1) * 66)
		row.BackgroundTransparency = 1
		row.ZIndex           = 17
		row.Parent           = itemList

		-- 区切り（2行目以降）
		if idx > 1 then
			local sep = Instance.new("Frame")
			sep.Size             = UDim2.new(1, -20, 0, 1)
			sep.Position         = UDim2.new(0, 10, 0, 0)
			sep.BackgroundColor3 = Color3.fromRGB(40, 40, 55)
			sep.BorderSizePixel  = 0
			sep.ZIndex           = 17
			sep.Parent           = row
		end

		local nameLabel = Instance.new("TextLabel")
		nameLabel.Size                 = UDim2.new(0.62, 0, 0, 28)
		nameLabel.Position             = UDim2.new(0, 14, 0, 10)
		nameLabel.BackgroundTransparency = 1
		nameLabel.Font                 = Enum.Font.GothamBold
		nameLabel.TextSize             = 16
		nameLabel.TextColor3           = Color3.fromRGB(255, 255, 255)
		nameLabel.TextXAlignment       = Enum.TextXAlignment.Left
		nameLabel.TextYAlignment       = Enum.TextYAlignment.Center
		nameLabel.Text                 = item.name
		nameLabel.ZIndex               = 18
		nameLabel.Parent               = row

		local descLabel = Instance.new("TextLabel")
		descLabel.Size                 = UDim2.new(0.62, 0, 0, 22)
		descLabel.Position             = UDim2.new(0, 14, 0, 36)
		descLabel.BackgroundTransparency = 1
		descLabel.Font                 = Enum.Font.Gotham
		descLabel.TextSize             = 13
		descLabel.TextColor3           = Color3.fromRGB(160, 160, 180)
		descLabel.TextXAlignment       = Enum.TextXAlignment.Left
		descLabel.TextYAlignment       = Enum.TextYAlignment.Center
		descLabel.Text                 = item.desc
		descLabel.ZIndex               = 18
		descLabel.Parent               = row

		local priceLabel = Instance.new("TextLabel")
		priceLabel.Name                 = "PriceLabel"
		priceLabel.Size                 = UDim2.new(0.25, 0, 0, 24)
		priceLabel.Position             = UDim2.new(0.62, 0, 0, 10)
		priceLabel.BackgroundTransparency = 1
		priceLabel.Font                 = Enum.Font.GothamBold
		priceLabel.TextSize             = 14
		priceLabel.TextColor3           = Color3.fromRGB(255, 220, 60)
		priceLabel.TextXAlignment       = Enum.TextXAlignment.Center
		priceLabel.TextYAlignment       = Enum.TextYAlignment.Center
		priceLabel.Text                 = item.price .. " pt"
		priceLabel.ZIndex               = 18
		priceLabel.Parent               = row

		local buyBtn = Instance.new("TextButton")
		buyBtn.Name             = "BuyBtn"
		buyBtn.Size             = UDim2.new(0, 80, 0, 36)
		buyBtn.AnchorPoint      = Vector2.new(1, 0.5)
		buyBtn.Position         = UDim2.new(1, -10, 0.5, 0)
		buyBtn.BackgroundColor3 = Color3.fromRGB(40, 160, 70)
		buyBtn.BorderSizePixel  = 0
		buyBtn.Font             = Enum.Font.GothamBold
		buyBtn.TextSize         = 15
		buyBtn.TextColor3       = Color3.fromRGB(255, 255, 255)
		buyBtn.Text             = "購入"
		buyBtn.ZIndex           = 18
		buyBtn.Parent           = row

		local bc = Instance.new("UICorner")
		bc.CornerRadius = UDim.new(0, 8)
		bc.Parent = buyBtn

		-- 初期状態適用
		local bought, buyerNm
		if item.id == "vehicle" then
			bought  = data.vehiclePurchased == true
			buyerNm = nil
		else
			bought  = data.powerups[item.id] == true
			buyerNm = data.buyers[item.id]
		end
		applyShopItemState(row, bought, buyerNm)

		local capturedId = item.id
		buyBtn.MouseButton1Click:Connect(function()
			if getPoints() < item.price then return end
			ShopBuyEvent:FireServer(capturedId)
		end)

		itemRows[item.id] = row
	end

	-- ショップ更新関数（ShopUpdateEvent から呼ばれる）
	local function onShopUpdate(powerups, buyers, vPurchased)
		if shopUI ~= overlay then return end
		pointsLabel.Text = "所持ポイント: " .. getPoints() .. " pt"
		for _, item in ipairs(GameConfig.ShopItems) do
			local row = itemRows[item.id]
			if row then
				if item.id == "vehicle" then
					applyShopItemState(row, vPurchased == true, nil)
				else
					applyShopItemState(row, powerups[item.id] == true, buyers[item.id])
				end
			end
		end
	end

	-- ShopUpdateEvent を一時接続
	local ShopUpdateEvent = ReplicatedStorage:WaitForChild("ShopUpdateEvent")
	local updateConn
	updateConn = ShopUpdateEvent.OnClientEvent:Connect(function(powerups, buyers, vPurchased)
		onShopUpdate(powerups, buyers, vPurchased)
	end)

	-- カウントダウン
	local remaining = data.duration
	task.spawn(function()
		while remaining > 0 and shopUI == overlay do
			countdownLabel.Text = "次Wave: " .. remaining .. "s"
			task.wait(1)
			remaining -= 1
		end
		if shopUI == overlay then
			updateConn:Disconnect()
			overlay:Destroy()
			shopUI = nil
		end
	end)
end

local function closeShop()
	if shopUI then
		shopUI:Destroy()
		shopUI = nil
	end
	pendingShopData = nil
end

-- ── 起動時ウェーブ状態取得 ──────────────────────────────────

task.spawn(function()
	local GetWaveState = ReplicatedStorage:WaitForChild("GetWaveState", 10)
	if not GetWaveState then return end
	local wave, fireCount, timeRemaining = GetWaveState:InvokeServer()
	if wave and wave > 0 then
		waveLabel.Text       = "Wave " .. wave
		fireLabel.Text       = "火災 " .. fireCount .. " 件"
		fireLabel.TextColor3 = Color3.fromRGB(255, 160, 80)
		startCountdown(timeRemaining)
	end
end)

-- ── イベント接続 ────────────────────────────────────────────

local MissionCompleteEvent = ReplicatedStorage:WaitForChild("MissionCompleteEvent")
MissionCompleteEvent.OnClientEvent:Connect(function()
	stopCountdown()
	timerLabel.Text       = "CLEAR!"
	timerLabel.TextColor3 = Color3.fromRGB(100, 230, 100)
	fireLabel.Text        = ""
	task.spawn(function()
		showMissionComplete()
		if pendingShopData then
			local d = pendingShopData
			pendingShopData = nil
			showShopUI(d)
		end
	end)
end)

local ShopOpenEvent = ReplicatedStorage:WaitForChild("ShopOpenEvent")
ShopOpenEvent.OnClientEvent:Connect(function(duration, powerups, buyers, vPurchased)
	pendingShopData = {
		duration         = duration,
		powerups         = powerups    or {},
		buyers           = buyers      or {},
		vehiclePurchased = vPurchased  or false,
	}
end)

local WaveStartEvent = ReplicatedStorage:WaitForChild("WaveStartEvent")
WaveStartEvent.OnClientEvent:Connect(function(wave, fireCount, timeLimit)
	closeShop()
	waveLabel.Text        = "Wave " .. wave
	timerLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	fireLabel.Text        = "火災 " .. fireCount .. " 件"
	fireLabel.TextColor3  = Color3.fromRGB(255, 160, 80)
	startCountdown(timeLimit or WAVE_TIME_LIMIT)
	task.spawn(showWaveStart, wave, fireCount)
end)

local TimeUpEvent = ReplicatedStorage:WaitForChild("TimeUpEvent")
TimeUpEvent.OnClientEvent:Connect(function()
	closeShop()
	task.spawn(showTimeOverDialog)
end)

local FireExtinguishedEvent = ReplicatedStorage:WaitForChild("FireExtinguishedEvent")
FireExtinguishedEvent.OnClientEvent:Connect(function(remaining)
	if remaining > 0 then
		fireLabel.Text       = "残り " .. remaining .. " 件"
		fireLabel.TextColor3 = remaining == 1
			and Color3.fromRGB(255, 100, 50)
			or  Color3.fromRGB(255, 160, 80)
	end
end)

print("[Client] ScoreUIController: スコアUIを表示しました。")
