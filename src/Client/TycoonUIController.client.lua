--[[
	TycoonUIController（Client / LocalScript）
	消防署タイクーンのクライアント表示。
	  ・所持金 HUD（左下、スコアパネルの上）とランク表示
	  ・「消防署へ」「町へ」テレポートボタン
	  ・購入パッドの価格表示を「買える＝緑／買えない＝赤」に色分け
	  ・出動レーンを走るミニ消防車の演出（サーバーの TycoonDropEvent を受けて再生）
	  ・回収額／購入結果／消火報酬のポップアップ
	  ・隊員の消火支援の水しぶき演出（CrewSupportEvent）
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local Workspace         = game:GetService("Workspace")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Shared       = ReplicatedStorage:WaitForChild("Shared")
local TycoonConfig = require(Shared:WaitForChild("TycoonConfig"))

local TycoonDropEvent     = ReplicatedStorage:WaitForChild("TycoonDropEvent")
local TycoonCollectEvent  = ReplicatedStorage:WaitForChild("TycoonCollectEvent")
local TycoonPurchaseEvent = ReplicatedStorage:WaitForChild("TycoonPurchaseEvent")
local TycoonTeleportEvent = ReplicatedStorage:WaitForChild("TycoonTeleportEvent")
local CrewSupportEvent    = ReplicatedStorage:WaitForChild("CrewSupportEvent")

local leaderstats = player:WaitForChild("leaderstats")
local moneyValue  = leaderstats:WaitForChild("Money")
local rankValue   = leaderstats:WaitForChild("Rank")

local COLOR_AFFORD   = Color3.fromRGB(120, 255, 140)
local COLOR_NO_MONEY = Color3.fromRGB(255, 90, 90)

-- ── HUD ─────────────────────────────────────────────────────

local screenGui = Instance.new("ScreenGui")
screenGui.Name           = "TycoonUI"
screenGui.ResetOnSpawn   = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent         = playerGui

-- 角丸の半透明パネルを作る
local function makePanel(name, position, size)
	local frame = Instance.new("Frame")
	frame.Name                   = name
	frame.AnchorPoint            = Vector2.new(0, 1)
	frame.Position               = position
	frame.Size                   = size
	frame.BackgroundColor3       = Color3.fromRGB(0, 0, 0)
	frame.BackgroundTransparency = 0.45
	frame.BorderSizePixel        = 0
	frame.Parent                 = screenGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent       = frame
	return frame
end

-- 所持金パネル（ScoreUI のスコアパネルと「🚒 呼ぶ」ボタンの上に置く）
local moneyPanel = makePanel("MoneyPanel", UDim2.new(0, 16, 1, -126), UDim2.new(0, 200, 0, 52))

local moneyLabel = Instance.new("TextLabel")
moneyLabel.Name                   = "MoneyLabel"
moneyLabel.Position               = UDim2.new(0, 12, 0, 4)
moneyLabel.Size                   = UDim2.new(1, -24, 0, 28)
moneyLabel.BackgroundTransparency = 1
moneyLabel.Font                   = Enum.Font.GothamBlack
moneyLabel.TextSize               = 24
moneyLabel.TextColor3             = Color3.fromRGB(120, 255, 140)
moneyLabel.TextXAlignment         = Enum.TextXAlignment.Left
moneyLabel.Text                   = "💵 $0"
moneyLabel.Parent                 = moneyPanel

local rankLabel = Instance.new("TextLabel")
rankLabel.Name                   = "RankLabel"
rankLabel.Position               = UDim2.new(0, 12, 0, 30)
rankLabel.Size                   = UDim2.new(1, -24, 0, 18)
rankLabel.BackgroundTransparency = 1
rankLabel.Font                   = Enum.Font.GothamBold
rankLabel.TextSize               = 14
rankLabel.TextColor3             = Color3.fromRGB(220, 220, 220)
rankLabel.TextXAlignment         = Enum.TextXAlignment.Left
rankLabel.Parent                 = moneyPanel

-- テレポートボタン
local function makeTeleportButton(name, text, xOffset, destination)
	local btn = Instance.new("TextButton")
	btn.Name                   = name
	btn.AnchorPoint            = Vector2.new(0, 1)
	btn.Position               = UDim2.new(0, xOffset, 1, -126)
	btn.Size                   = UDim2.new(0, 110, 0, 52)
	btn.BackgroundColor3       = Color3.fromRGB(190, 40, 35)
	btn.BackgroundTransparency = 0.1
	btn.BorderSizePixel        = 0
	btn.Font                   = Enum.Font.GothamBold
	btn.TextSize               = 16
	btn.TextColor3             = Color3.new(1, 1, 1)
	btn.Text                   = text
	btn.Parent                 = screenGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent       = btn

	btn.Activated:Connect(function()
		TycoonTeleportEvent:FireServer(destination)
	end)
	return btn
end

makeTeleportButton("ToStationButton", "🚒 消防署へ", 224, "station")
local toTownBtn = makeTeleportButton("ToTownButton", "🏙 町へ", 342, "town")
toTownBtn.BackgroundColor3 = Color3.fromRGB(50, 90, 160)

local function updateMoney()
	moneyLabel.Text = "💵 " .. TycoonConfig.formatMoney(moneyValue.Value)
end

-- ランク名・収入倍率・隊員数（倍率と隊員数はサーバーが Attribute で送る）
local function updateRank()
	local def  = TycoonConfig.Ranks[rankValue.Value] or TycoonConfig.Ranks[1]
	local mult = player:GetAttribute("IncomeMult") or def.mult
	local crew = player:GetAttribute("CrewCount") or 0
	rankLabel.Text = ("🏅 %s ｜ 収入×%s ｜ 👨‍🚒%d"):format(def.name, tostring(mult), crew)
end

updateMoney()
updateRank()
rankValue.Changed:Connect(updateRank)
player:GetAttributeChangedSignal("IncomeMult"):Connect(updateRank)
player:GetAttributeChangedSignal("CrewCount"):Connect(updateRank)

-- ── 購入パッドの色分け ───────────────────────────────────────

local trackedPads = {}  -- [Part] = true

local function colorPad(pad)
	local price = pad:GetAttribute("Price") or 0
	local gui   = pad:FindFirstChild("PriceGui")
	local label = gui and gui:FindFirstChild("PriceLabel")
	if not label then return end
	local affordable = moneyValue.Value >= price
	label.TextColor3 = affordable and COLOR_AFFORD or COLOR_NO_MONEY
	-- パッド本体の色もローカルだけで変える（他プレイヤーには影響しない）
	pad.Color = affordable and Color3.fromRGB(60, 200, 90) or Color3.fromRGB(150, 60, 60)
end

local function trackPad(pad)
	if not (pad:IsA("BasePart") and pad:GetAttribute("ButtonId")) then return end
	trackedPads[pad] = true
	-- PriceGui の複製が遅れて届く場合に備えて待ってから色を付ける
	task.spawn(function()
		pad:WaitForChild("PriceGui", 5)
		if pad.Parent then colorPad(pad) end
	end)
	pad.AncestryChanged:Connect(function(_, parent)
		if not parent then trackedPads[pad] = nil end
	end)
end

local tycoons = Workspace:WaitForChild("Tycoons")
for _, obj in tycoons:GetDescendants() do
	trackPad(obj)
end
tycoons.DescendantAdded:Connect(trackPad)

moneyValue.Changed:Connect(function()
	updateMoney()
	for pad in pairs(trackedPads) do
		colorPad(pad)
	end
end)

-- ── ミニ消防車の演出 ─────────────────────────────────────────

local function getMyPlot()
	local index = player:GetAttribute("PlotIndex")
	return index and tycoons:FindFirstChild("Plot_" .. index)
end

-- 小さな消防車（箱2つ）をローカルで作る
local function makeMiniTruck(cf)
	local model = Instance.new("Model")
	model.Name = "MiniTruck"

	local body = Instance.new("Part")
	body.Name       = "Body"
	body.Size       = Vector3.new(2.2, 1.4, 3.4)
	body.Color      = Color3.fromRGB(210, 30, 30)
	body.Material   = Enum.Material.SmoothPlastic
	body.Anchored   = true
	body.CanCollide = false
	body.CanQuery   = false
	body.CanTouch   = false
	body.CFrame     = cf
	body.Parent     = model

	local cab = Instance.new("Part")
	cab.Name       = "Light"
	cab.Size       = Vector3.new(1.2, 0.4, 0.6)
	cab.Color      = Color3.fromRGB(80, 160, 255)
	cab.Material   = Enum.Material.Neon
	cab.Anchored   = true
	cab.CanCollide = false
	cab.CanQuery   = false
	cab.CanTouch   = false
	cab.CFrame     = cf * CFrame.new(0, 0.9, 0)
	cab.Parent     = model

	model.PrimaryPart = body
	return model, body, cab
end

TycoonDropEvent.OnClientEvent:Connect(function(dropperId)
	local plot = getMyPlot()
	local structure = plot and plot:FindFirstChild("Structures") and plot.Structures:FindFirstChild(dropperId)
	if not structure then return end
	local startPart = structure:FindFirstChild("LaneStart")
	local endPart   = structure:FindFirstChild("LaneEnd")
	if not (startPart and endPart) then return end

	-- 終点の方向を向かせる
	local startCF = CFrame.lookAt(startPart.Position, endPart.Position)
	local endCF   = CFrame.lookAt(endPart.Position, endPart.Position + startCF.LookVector)

	local model, body, light = makeMiniTruck(startCF)
	model.Parent = Workspace

	local info = TweenInfo.new(1.6, Enum.EasingStyle.Linear)
	TweenService:Create(body, info, { CFrame = endCF }):Play()
	local lightTween = TweenService:Create(light, info, { CFrame = endCF * CFrame.new(0, 0.9, 0) })
	lightTween:Play()
	lightTween.Completed:Wait()
	model:Destroy()
end)

-- ── ポップアップ ─────────────────────────────────────────────

-- 画面下中央から上に浮かんで消えるテキスト
local function popup(text, color)
	local label = Instance.new("TextLabel")
	label.AnchorPoint            = Vector2.new(0.5, 1)
	label.Position               = UDim2.new(0.5, 0, 1, -140)
	label.Size                   = UDim2.new(0, 420, 0, 44)
	label.BackgroundTransparency = 1
	label.Font                   = Enum.Font.GothamBlack
	label.TextSize               = 32
	label.TextColor3             = color
	label.TextStrokeTransparency = 0.2
	label.Text                   = text
	label.Parent                 = screenGui

	local info = TweenInfo.new(1.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(label, info, {
		Position = UDim2.new(0.5, 0, 1, -220),
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	}):Play()
	task.delay(1.5, function() label:Destroy() end)
end

-- ── 隊員の消火支援演出 ───────────────────────────────────────

-- 燃えている位置に水しぶきを一瞬出す
CrewSupportEvent.OnClientEvent:Connect(function(position)
	local anchor = Instance.new("Part")
	anchor.Anchored     = true
	anchor.CanCollide   = false
	anchor.CanQuery     = false
	anchor.CanTouch     = false
	anchor.Transparency = 1
	anchor.Size         = Vector3.new(1, 1, 1)
	anchor.Position     = position + Vector3.new(0, 6, 0)
	anchor.Parent       = Workspace

	local splash = Instance.new("ParticleEmitter")
	splash.Color        = ColorSequence.new(Color3.fromRGB(150, 210, 255))
	splash.LightEmission = 0.3
	splash.Size         = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 1.6) })
	splash.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	splash.Lifetime     = NumberRange.new(0.6, 1)
	splash.Speed        = NumberRange.new(10, 16)
	splash.SpreadAngle  = Vector2.new(35, 35)
	splash.Acceleration = Vector3.new(0, -40, 0)
	splash.EmissionDirection = Enum.NormalId.Bottom
	splash.Rate         = 0
	splash.Parent       = anchor
	splash:Emit(30)

	task.delay(1.5, function() anchor:Destroy() end)
end)

TycoonCollectEvent.OnClientEvent:Connect(function(amount)
	popup("+" .. TycoonConfig.formatMoney(amount), Color3.fromRGB(120, 255, 140))
end)

TycoonPurchaseEvent.OnClientEvent:Connect(function(ok, buttonName, reason)
	if ok then
		popup("🏗 " .. buttonName .. " を建設！", Color3.fromRGB(255, 230, 80))
	else
		popup("❌ " .. (reason or "購入できません"), COLOR_NO_MONEY)
	end
end)

print("[TycoonUIController] タイクーンUIを起動しました。")
