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

-- push確認用のビルドタグ（pushするたびに値を変えて、Studio側に反映されたか目視確認する）
local BUILD_TAG = "build-1"

local screenGui
local waveTimerThread = nil
local shopUI          = nil  -- ショップオーバーレイ（開いている間 non-nil）
local pendingShopData = nil  -- ShopOpenEvent で受け取ったデータ
local vehicleSpawned  = false
local vehicleBtn      = nil
local buffsHolder     = nil

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

	-- push確認用ビルドタグ（右上に小さく表示）
	local buildLabel = Instance.new("TextLabel")
	buildLabel.Name                 = "BuildLabel"
	buildLabel.AnchorPoint           = Vector2.new(1, 0)
	buildLabel.Position              = UDim2.new(1, -8, 0, 4)
	buildLabel.Size                  = UDim2.new(0, 140, 0, 18)
	buildLabel.BackgroundTransparency = 1
	buildLabel.Font                  = Enum.Font.Gotham
	buildLabel.TextSize              = 12
	buildLabel.TextColor3            = Color3.fromRGB(150, 150, 150)
	buildLabel.TextTransparency      = 0.3
	buildLabel.TextXAlignment        = Enum.TextXAlignment.Right
	buildLabel.Text                  = BUILD_TAG
	buildLabel.Parent                = screenGui

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
	frame.AnchorPoint           = Vector2.new(0, 0)
	frame.Position              = UDim2.new(0, 16, 0, 16)
	frame.Size                  = UDim2.new(0, 160, 0, 80)
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

-- ── 消防車ボタン ─────────────────────────────────────────────

local function createVehicleBtn()
	local btn = Instance.new("TextButton")
	btn.Name             = "VehicleBtn"
	btn.AnchorPoint      = Vector2.new(0, 1)
	btn.Position         = UDim2.new(0, 16, 1, -72)
	btn.Size             = UDim2.new(0, 148, 0, 46)
	btn.BackgroundColor3 = Color3.fromRGB(40, 160, 70)
	btn.BorderSizePixel  = 0
	btn.Font             = Enum.Font.Legacy
	btn.TextSize         = 20
	btn.TextColor3       = Color3.fromRGB(255, 255, 255)
	btn.Text             = "🚒 呼ぶ"
	btn.Visible          = false
	btn.ZIndex           = 5
	btn.Parent           = screenGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = btn

	return btn
end

local function updateVehicleBtn(spawned, purchased)
	if not vehicleBtn then return end
	vehicleSpawned     = spawned
	vehicleBtn.Visible = purchased == true
	if spawned then
		vehicleBtn.BackgroundColor3 = Color3.fromRGB(200, 100, 20)
		vehicleBtn.Text             = "🚒 戻す"
	else
		vehicleBtn.BackgroundColor3 = Color3.fromRGB(40, 160, 70)
		vehicleBtn.Text             = "🚒 呼ぶ"
	end
end

local scoreLabel = createScoreUI()
local waveLabel, timerLabel, fireLabel = createWaveUI()
bindScoreLabel(scoreLabel)
vehicleBtn = createVehicleBtn()

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

-- ── ボスウェーブ開始アニメーション ──────────────────────────
-- Wave 5, 10, 15... のときに showWaveStart の代わりに呼ばれる

local function showBossWaveStart(wave, fireCount)
	local overlay = Instance.new("Frame")
	overlay.Name                  = "BossWaveOverlay"
	overlay.Size                  = UDim2.new(1, 0, 1, 0)
	overlay.BackgroundColor3      = Color3.fromRGB(20, 0, 0)
	overlay.BackgroundTransparency = 1
	overlay.ZIndex                = 10
	overlay.Parent                = screenGui

	-- 背景フラッシュ（赤→黒）
	local flashTween = TweenService:Create(overlay,
		TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ BackgroundTransparency = 0.35 })
	flashTween:Play()

	-- BOSS WAVE!! テキスト
	local bossTitle = Instance.new("TextLabel")
	bossTitle.Size                 = UDim2.new(1, 0, 0, 90)
	bossTitle.Position             = UDim2.new(0, 0, 0.3, 0)
	bossTitle.BackgroundTransparency = 1
	bossTitle.Font                 = Enum.Font.GothamBold
	bossTitle.TextSize             = 72
	bossTitle.TextColor3           = Color3.fromRGB(255, 40, 20)
	bossTitle.TextStrokeTransparency = 0.0
	bossTitle.TextStrokeColor3     = Color3.fromRGB(0, 0, 0)
	bossTitle.Text                 = "⚡ BOSS WAVE!! ⚡"
	bossTitle.TextTransparency     = 1
	bossTitle.ZIndex               = 11
	bossTitle.Parent               = overlay

	-- Wave 番号
	local waveNum = Instance.new("TextLabel")
	waveNum.Size                 = UDim2.new(1, 0, 0, 50)
	waveNum.Position             = UDim2.new(0, 0, 0.3, 96)
	waveNum.BackgroundTransparency = 1
	waveNum.Font                 = Enum.Font.GothamBold
	waveNum.TextSize             = 40
	waveNum.TextColor3           = Color3.fromRGB(255, 180, 40)
	waveNum.TextStrokeTransparency = 0.2
	waveNum.Text                 = "Wave " .. wave
	waveNum.TextTransparency     = 1
	waveNum.ZIndex               = 11
	waveNum.Parent               = overlay

	-- 注意書き
	local sub = Instance.new("TextLabel")
	sub.Size                 = UDim2.new(1, 0, 0, 32)
	sub.Position             = UDim2.new(0, 0, 0.3, 152)
	sub.BackgroundTransparency = 1
	sub.Font                 = Enum.Font.Gotham
	sub.TextSize             = 22
	sub.TextColor3           = Color3.fromRGB(255, 255, 255)
	sub.Text                 = "強化火災が " .. fireCount .. " 件同時発生！"
	sub.TextTransparency     = 1
	sub.ZIndex               = 11
	sub.Parent               = overlay

	local tweenIn = TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	TweenService:Create(bossTitle, tweenIn, { TextTransparency = 0 }):Play()
	TweenService:Create(waveNum,   tweenIn, { TextTransparency = 0 }):Play()
	TweenService:Create(sub,
		TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ TextTransparency = 0 }):Play()

	task.wait(2.5)

	local tweenOut = TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	TweenService:Create(overlay,   tweenOut, { BackgroundTransparency = 1 }):Play()
	TweenService:Create(bossTitle, tweenOut, { TextTransparency = 1 }):Play()
	TweenService:Create(waveNum,   tweenOut, { TextTransparency = 1 }):Play()
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

-- ── ショップアイコン定義 ─────────────────────────────────────

local SHOP_ITEM_ICONS = {
	vehicle    = { icon = "🚒", sub = "解放",  color = Color3.fromRGB(210, 55,  30)  },
	waterBoost = { icon = "🧯", sub = "×1.5",  color = Color3.fromRGB(30,  120, 210) },
	timeExtend = { icon = "⏱", sub = "+60秒", color = Color3.fromRGB(170, 120, 20)  },
	speedBoost = { icon = "🏃", sub = "×1.5",  color = Color3.fromRGB(50,  170, 40)  },
}

-- ── ウェーブ中バフ表示 ────────────────────────────────────────

local BUFF_ORDER = { "waterBoost", "speedBoost" }
local BUFF_DEF   = {
	waterBoost = { label = "🧯消火×1.5", color = Color3.fromRGB(30,  120, 210) },
	speedBoost = { label = "🏃速度×1.5", color = Color3.fromRGB(50,  170, 40)  },
}

local function createBuffsHolder()
	local holder = Instance.new("Frame")
	holder.Name                  = "BuffsHolder"
	holder.AnchorPoint           = Vector2.new(0, 0)
	holder.Position              = UDim2.new(0, 16, 0, 100)
	holder.Size                  = UDim2.new(0, 160, 0, 26)
	holder.BackgroundTransparency = 1
	holder.Visible               = false
	holder.Parent                = screenGui

	local layout = Instance.new("UIListLayout")
	layout.FillDirection         = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment   = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment     = Enum.VerticalAlignment.Center
	layout.Padding               = UDim.new(0, 6)
	layout.Parent                = holder

	return holder
end

local function updateBuffsDisplay(powerups)
	if not buffsHolder then return end
	for _, child in buffsHolder:GetChildren() do
		if not child:IsA("UIListLayout") then child:Destroy() end
	end

	local anyActive = false
	for _, id in ipairs(BUFF_ORDER) do
		if powerups and powerups[id] then
			anyActive = true
			local def   = BUFF_DEF[id]
			local badge = Instance.new("Frame")
			badge.Size                   = UDim2.new(0, 84, 0, 24)
			badge.BackgroundColor3       = def.color
			badge.BackgroundTransparency = 0.2
			badge.BorderSizePixel        = 0
			badge.Parent                 = buffsHolder

			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0, 6)
			corner.Parent       = badge

			local lbl = Instance.new("TextLabel")
			lbl.Size                 = UDim2.new(1, 0, 1, 0)
			lbl.BackgroundTransparency = 1
			lbl.Font                 = Enum.Font.Legacy
			lbl.TextSize             = 13
			lbl.TextColor3           = Color3.fromRGB(255, 255, 255)
			lbl.TextXAlignment       = Enum.TextXAlignment.Center
			lbl.TextYAlignment       = Enum.TextYAlignment.Center
			lbl.Text                 = def.label
			lbl.Parent               = badge
		end
	end

	buffsHolder.Visible = anyActive
end

buffsHolder = createBuffsHolder()

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
	panel.Size                  = UDim2.new(0, 360, 0, 400)
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
	itemList.Size             = UDim2.new(1, 0, 0, 264)
	itemList.Position         = UDim2.new(0, 0, 0, 80)
	itemList.BackgroundTransparency = 1
	itemList.ZIndex           = 17
	itemList.Parent           = panel

	local ShopBuyEvent  = ReplicatedStorage:WaitForChild("ShopBuyEvent")
	local ShopEndEvent  = ReplicatedStorage:WaitForChild("ShopEndEvent")

	local itemRows = {}  -- [itemId] = row Frame

	for idx, item in ipairs(GameConfig.ShopItems) do
		local iconData = SHOP_ITEM_ICONS[item.id] or { icon = "?", sub = "", color = Color3.fromRGB(80, 80, 80) }

		local row = Instance.new("Frame")
		row.Name                   = item.id
		row.Size                   = UDim2.new(1, 0, 0, 66)
		row.Position               = UDim2.new(0, 0, 0, (idx - 1) * 66)
		row.BackgroundTransparency = 1
		row.ZIndex                 = 17
		row.Parent                 = itemList

		if idx > 1 then
			local sep = Instance.new("Frame")
			sep.Size             = UDim2.new(1, -20, 0, 1)
			sep.Position         = UDim2.new(0, 10, 0, 0)
			sep.BackgroundColor3 = Color3.fromRGB(40, 40, 55)
			sep.BorderSizePixel  = 0
			sep.ZIndex           = 17
			sep.Parent           = row
		end

		-- ── アイコン ──────────────────────────────────────────
		local iconBg = Instance.new("Frame")
		iconBg.Size                   = UDim2.new(0, 52, 0, 52)
		iconBg.AnchorPoint            = Vector2.new(0, 0.5)
		iconBg.Position               = UDim2.new(0, 8, 0.5, 0)
		iconBg.BackgroundColor3       = iconData.color
		iconBg.BackgroundTransparency = 0.25
		iconBg.BorderSizePixel        = 0
		iconBg.ZIndex                 = 18
		iconBg.Parent                 = row

		local iconBgCorner = Instance.new("UICorner")
		iconBgCorner.CornerRadius = UDim.new(0, 10)
		iconBgCorner.Parent       = iconBg

		local iconEmoji = Instance.new("TextLabel")
		iconEmoji.Size                 = UDim2.new(1, 0, 0, 34)
		iconEmoji.Position             = UDim2.new(0, 0, 0, 1)
		iconEmoji.BackgroundTransparency = 1
		iconEmoji.Font                 = Enum.Font.Legacy
		iconEmoji.TextSize             = 26
		iconEmoji.TextColor3           = Color3.fromRGB(255, 255, 255)
		iconEmoji.TextXAlignment       = Enum.TextXAlignment.Center
		iconEmoji.TextYAlignment       = Enum.TextYAlignment.Center
		iconEmoji.Text                 = iconData.icon
		iconEmoji.ZIndex               = 19
		iconEmoji.Parent               = iconBg

		local iconSub = Instance.new("TextLabel")
		iconSub.Size                   = UDim2.new(1, 0, 0, 18)
		iconSub.AnchorPoint            = Vector2.new(0, 1)
		iconSub.Position               = UDim2.new(0, 0, 1, -1)
		iconSub.BackgroundTransparency = 1
		iconSub.Font                   = Enum.Font.GothamBold
		iconSub.TextSize               = 11
		iconSub.TextColor3             = Color3.fromRGB(255, 255, 220)
		iconSub.TextXAlignment         = Enum.TextXAlignment.Center
		iconSub.TextYAlignment         = Enum.TextYAlignment.Center
		iconSub.Text                   = iconData.sub
		iconSub.ZIndex                 = 19
		iconSub.Parent                 = iconBg

		-- ── テキスト ──────────────────────────────────────────
		local nameLabel = Instance.new("TextLabel")
		nameLabel.Size                   = UDim2.new(0, 170, 0, 26)
		nameLabel.Position               = UDim2.new(0, 68, 0, 7)
		nameLabel.BackgroundTransparency = 1
		nameLabel.Font                   = Enum.Font.GothamBold
		nameLabel.TextSize               = 15
		nameLabel.TextColor3             = Color3.fromRGB(255, 255, 255)
		nameLabel.TextXAlignment         = Enum.TextXAlignment.Left
		nameLabel.TextYAlignment         = Enum.TextYAlignment.Center
		nameLabel.Text                   = item.name
		nameLabel.ZIndex                 = 18
		nameLabel.Parent                 = row

		local descLabel = Instance.new("TextLabel")
		descLabel.Size                   = UDim2.new(0, 170, 0, 20)
		descLabel.Position               = UDim2.new(0, 68, 0, 35)
		descLabel.BackgroundTransparency = 1
		descLabel.Font                   = Enum.Font.Gotham
		descLabel.TextSize               = 12
		descLabel.TextColor3             = Color3.fromRGB(160, 160, 180)
		descLabel.TextXAlignment         = Enum.TextXAlignment.Left
		descLabel.TextYAlignment         = Enum.TextYAlignment.Center
		descLabel.Text                   = item.desc
		descLabel.ZIndex                 = 18
		descLabel.Parent                 = row

		-- ── 価格・購入ボタン ──────────────────────────────────
		local priceLabel = Instance.new("TextLabel")
		priceLabel.Name                   = "PriceLabel"
		priceLabel.Size                   = UDim2.new(0, 82, 0, 20)
		priceLabel.AnchorPoint            = Vector2.new(1, 0)
		priceLabel.Position               = UDim2.new(1, -8, 0, 6)
		priceLabel.BackgroundTransparency = 1
		priceLabel.Font                   = Enum.Font.GothamBold
		priceLabel.TextSize               = 14
		priceLabel.TextColor3             = Color3.fromRGB(255, 220, 60)
		priceLabel.TextXAlignment         = Enum.TextXAlignment.Right
		priceLabel.TextYAlignment         = Enum.TextYAlignment.Center
		priceLabel.Text                   = item.price .. " pt"
		priceLabel.ZIndex                 = 18
		priceLabel.Parent                 = row

		local buyBtn = Instance.new("TextButton")
		buyBtn.Name             = "BuyBtn"
		buyBtn.Size             = UDim2.new(0, 82, 0, 32)
		buyBtn.AnchorPoint      = Vector2.new(1, 1)
		buyBtn.Position         = UDim2.new(1, -8, 1, -6)
		buyBtn.BackgroundColor3 = Color3.fromRGB(40, 160, 70)
		buyBtn.BorderSizePixel  = 0
		buyBtn.Font             = Enum.Font.GothamBold
		buyBtn.TextSize         = 14
		buyBtn.TextColor3       = Color3.fromRGB(255, 255, 255)
		buyBtn.Text             = "購入"
		buyBtn.ZIndex           = 18
		buyBtn.Parent           = row

		local bc = Instance.new("UICorner")
		bc.CornerRadius = UDim.new(0, 8)
		bc.Parent       = buyBtn

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

	-- 買い物終了ボタン
	local endDivider = Instance.new("Frame")
	endDivider.Size             = UDim2.new(1, -20, 0, 1)
	endDivider.Position         = UDim2.new(0, 10, 0, 350)
	endDivider.BackgroundColor3 = Color3.fromRGB(60, 60, 80)
	endDivider.BorderSizePixel  = 0
	endDivider.ZIndex           = 17
	endDivider.Parent           = panel

	local endBtn = Instance.new("TextButton")
	endBtn.Size             = UDim2.new(1, -20, 0, 40)
	endBtn.Position         = UDim2.new(0, 10, 0, 356)
	endBtn.BackgroundColor3 = Color3.fromRGB(60, 140, 220)
	endBtn.BorderSizePixel  = 0
	endBtn.Font             = Enum.Font.GothamBold
	endBtn.TextSize         = 16
	endBtn.TextColor3       = Color3.fromRGB(255, 255, 255)
	endBtn.Text             = "買い物終了 →"
	endBtn.ZIndex           = 18
	endBtn.Parent           = panel

	local endBtnCorner = Instance.new("UICorner")
	endBtnCorner.CornerRadius = UDim.new(0, 8)
	endBtnCorner.Parent       = endBtn

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

	local function finishShopping()
		if shopUI ~= overlay then return end
		updateConn:Disconnect()
		overlay:Destroy()
		shopUI = nil
	end

	endBtn.MouseButton1Click:Connect(function()
		ShopEndEvent:FireServer()
		finishShopping()
	end)

	-- カウントダウン
	local remaining = data.duration
	task.spawn(function()
		while remaining > 0 and shopUI == overlay do
			countdownLabel.Text = "次Wave: " .. remaining .. "s"
			task.wait(1)
			remaining -= 1
		end
		finishShopping()
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
	local wave, fireCount, timeRemaining, activePowerups = GetWaveState:InvokeServer()
	if wave and wave > 0 then
		waveLabel.Text       = "Wave " .. wave
		fireLabel.Text       = "火災 " .. fireCount .. " 件"
		fireLabel.TextColor3 = Color3.fromRGB(255, 160, 80)
		startCountdown(timeRemaining)
		updateBuffsDisplay(activePowerups or {})
	end

	local GetVehicleState = ReplicatedStorage:WaitForChild("GetVehicleState", 10)
	if GetVehicleState then
		local spawned, purchased = GetVehicleState:InvokeServer()
		updateVehicleBtn(spawned, purchased)
	end
end)

-- ── イベント接続 ────────────────────────────────────────────

local MissionCompleteEvent = ReplicatedStorage:WaitForChild("MissionCompleteEvent")
MissionCompleteEvent.OnClientEvent:Connect(function()
	stopCountdown()
	timerLabel.Text       = "CLEAR!"
	timerLabel.TextColor3 = Color3.fromRGB(100, 230, 100)
	fireLabel.Text        = ""
	updateBuffsDisplay({})
	task.spawn(function()
		showMissionComplete()
		if pendingShopData then
			local d = pendingShopData
			pendingShopData = nil
			showShopUI(d)
		end
	end)
end)

-- サーバー起動時のバフ復元など、UIだけを更新したい場合に使うイベント
local PowerupsSyncEvent = ReplicatedStorage:WaitForChild("PowerupsSyncEvent")
PowerupsSyncEvent.OnClientEvent:Connect(function(powerups)
	updateBuffsDisplay(powerups or {})
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
WaveStartEvent.OnClientEvent:Connect(function(wave, fireCount, timeLimit, activePowerups, isBossWave)
	closeShop()
	-- ボスウェーブはウェーブラベルを赤色にして視覚的に区別する
	if isBossWave then
		waveLabel.Text       = "Wave " .. wave .. " ⚡"
		waveLabel.TextColor3 = Color3.fromRGB(255, 60, 40)
	else
		waveLabel.Text       = "Wave " .. wave
		waveLabel.TextColor3 = Color3.fromRGB(255, 200, 50)
	end
	timerLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	fireLabel.Text        = "火災 " .. fireCount .. " 件"
	fireLabel.TextColor3  = Color3.fromRGB(255, 160, 80)
	startCountdown(timeLimit or WAVE_TIME_LIMIT)
	updateBuffsDisplay(activePowerups or {})
	if isBossWave then
		task.spawn(showBossWaveStart, wave, fireCount)
	else
		task.spawn(showWaveStart, wave, fireCount)
	end
end)

local TimeUpEvent = ReplicatedStorage:WaitForChild("TimeUpEvent")
TimeUpEvent.OnClientEvent:Connect(function()
	closeShop()
	updateBuffsDisplay({})
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

local VehicleSpawnEvent = ReplicatedStorage:WaitForChild("VehicleSpawnEvent")
local VehicleStateEvent = ReplicatedStorage:WaitForChild("VehicleStateEvent")

vehicleBtn.MouseButton1Click:Connect(function()
	VehicleSpawnEvent:FireServer(not vehicleSpawned)
end)

VehicleStateEvent.OnClientEvent:Connect(function(spawned, purchased)
	updateVehicleBtn(spawned, purchased)
end)

print("[Client] ScoreUIController: スコアUIを表示しました。")
