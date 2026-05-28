--[[
	消火数スコアUI（Client / LocalScript）
	leaderstats.Fires の変化を監視し、画面左下に表示する。
	MissionCompleteEvent を受信したらミッション完了エフェクトを表示する。
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local screenGui

local function createScoreUI()
	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "ScoreUI"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Parent = playerGui

	local frame = Instance.new("Frame")
	frame.Name = "ScorePanel"
	frame.AnchorPoint = Vector2.new(0, 1)
	frame.Position = UDim2.new(0, 16, 1, -16)
	frame.Size = UDim2.new(0, 200, 0, 48)
	frame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	frame.BackgroundTransparency = 0.45
	frame.BorderSizePixel = 0
	frame.Parent = screenGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = frame

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 12)
	padding.PaddingRight = UDim.new(0, 12)
	padding.PaddingTop = UDim.new(0, 8)
	padding.PaddingBottom = UDim.new(0, 8)
	padding.Parent = frame

	local label = Instance.new("TextLabel")
	label.Name = "ScoreLabel"
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextSize = 20
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.Text = "消火数: 0"
	label.Parent = frame

	return label
end

local function bindScoreLabel(label)
	local leaderstats = player:WaitForChild("leaderstats")
	local fires = leaderstats:WaitForChild("Fires")

	local function updateDisplay()
		label.Text = "消火数: " .. tostring(fires.Value)
	end

	updateDisplay()
	fires:GetPropertyChangedSignal("Value"):Connect(updateDisplay)
end

local function showMissionComplete()
	local overlay = Instance.new("Frame")
	overlay.Name = "MissionCompleteOverlay"
	overlay.Size = UDim2.new(1, 0, 1, 0)
	overlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	overlay.BackgroundTransparency = 1
	overlay.ZIndex = 10
	overlay.Parent = screenGui

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0, 80)
	title.Position = UDim2.new(0, 0, 0.4, 0)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.TextSize = 64
	title.TextColor3 = Color3.fromRGB(255, 215, 0)
	title.TextStrokeTransparency = 0.4
	title.Text = "ミッション完了！"
	title.TextTransparency = 1
	title.ZIndex = 11
	title.Parent = overlay

	local sub = Instance.new("TextLabel")
	sub.Size = UDim2.new(1, 0, 0, 36)
	sub.Position = UDim2.new(0, 0, 0.4, 88)
	sub.BackgroundTransparency = 1
	sub.Font = Enum.Font.Gotham
	sub.TextSize = 28
	sub.TextColor3 = Color3.fromRGB(255, 255, 255)
	sub.Text = "全ての火を消し止めました！"
	sub.TextTransparency = 1
	sub.ZIndex = 11
	sub.Parent = overlay

	local tweenInfo = TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(overlay, tweenInfo, { BackgroundTransparency = 0.55 }):Play()
	TweenService:Create(title, tweenInfo, { TextTransparency = 0 }):Play()
	TweenService:Create(sub, tweenInfo, { TextTransparency = 0 }):Play()

	task.wait(2.5)

	local fadeOut = TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	TweenService:Create(overlay, fadeOut, { BackgroundTransparency = 1 }):Play()
	TweenService:Create(title, fadeOut, { TextTransparency = 1 }):Play()
	local lastTween = TweenService:Create(sub, fadeOut, { TextTransparency = 1 })
	lastTween:Play()
	lastTween.Completed:Wait()
	overlay:Destroy()
end

local function createWaveUI()
	local frame = Instance.new("Frame")
	frame.Name = "WavePanel"
	frame.AnchorPoint = Vector2.new(0.5, 0)
	frame.Position = UDim2.new(0.5, 0, 0, 16)
	frame.Size = UDim2.new(0, 160, 0, 40)
	frame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	frame.BackgroundTransparency = 0.45
	frame.BorderSizePixel = 0
	frame.Parent = screenGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = frame

	local label = Instance.new("TextLabel")
	label.Name = "WaveLabel"
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextSize = 20
	label.TextColor3 = Color3.fromRGB(255, 200, 50)
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.Text = "Wave --"
	label.Parent = frame

	return label
end

local function showWaveStart(wave, fireCount)
	local overlay = Instance.new("Frame")
	overlay.Name = "WaveStartOverlay"
	overlay.Size = UDim2.new(1, 0, 1, 0)
	overlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	overlay.BackgroundTransparency = 1
	overlay.ZIndex = 10
	overlay.Parent = screenGui

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0, 70)
	title.Position = UDim2.new(0, 0, 0.38, 0)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.TextSize = 56
	title.TextColor3 = Color3.fromRGB(255, 80, 20)
	title.TextStrokeTransparency = 0.4
	title.Text = "Wave " .. wave .. " 開始！"
	title.TextTransparency = 1
	title.ZIndex = 11
	title.Parent = overlay

	local sub = Instance.new("TextLabel")
	sub.Size = UDim2.new(1, 0, 0, 32)
	sub.Position = UDim2.new(0, 0, 0.38, 78)
	sub.BackgroundTransparency = 1
	sub.Font = Enum.Font.Gotham
	sub.TextSize = 24
	sub.TextColor3 = Color3.fromRGB(255, 255, 255)
	sub.Text = "火事が " .. fireCount .. " 件発生！"
	sub.TextTransparency = 1
	sub.ZIndex = 11
	sub.Parent = overlay

	local tweenIn = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(overlay, tweenIn, { BackgroundTransparency = 0.6 }):Play()
	TweenService:Create(title, tweenIn, { TextTransparency = 0 }):Play()
	TweenService:Create(sub, tweenIn, { TextTransparency = 0 }):Play()

	task.wait(2)

	local tweenOut = TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	TweenService:Create(overlay, tweenOut, { BackgroundTransparency = 1 }):Play()
	TweenService:Create(title, tweenOut, { TextTransparency = 1 }):Play()
	local lastTween = TweenService:Create(sub, tweenOut, { TextTransparency = 1 })
	lastTween:Play()
	lastTween.Completed:Wait()
	overlay:Destroy()
end

local scoreLabel = createScoreUI()
local waveLabel  = createWaveUI()
bindScoreLabel(scoreLabel)

local MissionCompleteEvent = ReplicatedStorage:WaitForChild("MissionCompleteEvent")
MissionCompleteEvent.OnClientEvent:Connect(showMissionComplete)

local WaveStartEvent = ReplicatedStorage:WaitForChild("WaveStartEvent")
WaveStartEvent.OnClientEvent:Connect(function(wave, fireCount)
	waveLabel.Text = "Wave " .. wave
	task.spawn(showWaveStart, wave, fireCount)
end)

print("[Client] ScoreUIController: スコアUIを表示しました。")
