--[[
	ShopUIController（Client / LocalScript）
	Robux ショップ画面。
	  ・画面左の「🛒 ショップ」ボタン、または区画の SHOP 看板（OpenShopEvent）で開く
	  ・タブ「ゲームパス」「アイテム」。価格は MarketplaceService:GetProductInfo から取得
	  ・id = 0（未設定）のアイテムは「準備中」で購入不可
	  ・購入結果（PurchaseResultEvent）のポップアップ
	  ・収入2倍ブーストの残り時間表示（所持金パネルの上）
	  ・Roblox Premium の案内（会員は収入 +10%）
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players            = game:GetService("Players")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local TweenService       = game:GetService("TweenService")
local Workspace          = game:GetService("Workspace")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Shared             = ReplicatedStorage:WaitForChild("Shared")
local TycoonConfig       = require(Shared:WaitForChild("TycoonConfig"))
local MonetizationConfig = require(Shared:WaitForChild("MonetizationConfig"))

local OpenShopEvent       = ReplicatedStorage:WaitForChild("OpenShopEvent")
local PurchaseResultEvent = ReplicatedStorage:WaitForChild("PurchaseResultEvent")

local GOLD = Color3.fromRGB(215, 160, 20)

local screenGui = Instance.new("ScreenGui")
screenGui.Name           = "ShopUI"
screenGui.ResetOnSpawn   = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.DisplayOrder   = 5  -- 他の HUD より手前に出す
screenGui.Parent         = playerGui

local function addCorner(inst, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or 8)
	c.Parent       = inst
end

-- ── 価格取得（キャッシュ付き）─────────────────────────────────

local priceCache = {}  -- ["pass:123"] = 99

local function fetchPrice(id, infoType)
	if id == 0 then return nil end
	local cacheKey = tostring(infoType) .. ":" .. id
	if priceCache[cacheKey] then return priceCache[cacheKey] end
	local ok, info = pcall(function()
		return MarketplaceService:GetProductInfo(id, infoType)
	end)
	if ok and info and info.PriceInRobux then
		priceCache[cacheKey] = info.PriceInRobux
		return info.PriceInRobux
	end
	return nil
end

-- ── ショップ画面 ─────────────────────────────────────────────

local panel = Instance.new("Frame")
panel.Name             = "ShopPanel"
panel.AnchorPoint      = Vector2.new(0.5, 0.5)
panel.Position         = UDim2.fromScale(0.5, 0.5)
panel.Size             = UDim2.new(0.92, 0, 0.8, 0)
panel.BackgroundColor3 = Color3.fromRGB(25, 25, 32)
panel.BorderSizePixel  = 0
panel.Visible          = false
panel.Parent           = screenGui
addCorner(panel, 12)

-- PC では大きくなりすぎないよう上限を設ける
local sizeLimit = Instance.new("UISizeConstraint")
sizeLimit.MaxSize = Vector2.new(480, 460)
sizeLimit.Parent  = panel

local stroke = Instance.new("UIStroke")
stroke.Color     = GOLD
stroke.Thickness = 2
stroke.Parent    = panel

local title = Instance.new("TextLabel")
title.Position               = UDim2.new(0, 16, 0, 8)
title.Size                   = UDim2.new(1, -70, 0, 36)
title.BackgroundTransparency = 1
title.Font                   = Enum.Font.GothamBlack
title.TextSize               = 24
title.TextColor3             = Color3.fromRGB(255, 215, 80)
title.TextXAlignment         = Enum.TextXAlignment.Left
title.Text                   = "🛒 消防署ショップ"
title.Parent                 = panel

local closeBtn = Instance.new("TextButton")
closeBtn.AnchorPoint      = Vector2.new(1, 0)
closeBtn.Position         = UDim2.new(1, -10, 0, 10)
closeBtn.Size             = UDim2.new(0, 36, 0, 36)
closeBtn.BackgroundColor3 = Color3.fromRGB(90, 90, 90)
closeBtn.Font             = Enum.Font.GothamBold
closeBtn.TextSize         = 20
closeBtn.TextColor3       = Color3.new(1, 1, 1)
closeBtn.Text             = "✕"
closeBtn.Parent           = panel
addCorner(closeBtn, 8)

-- タブボタン
local tabs = {}
local function makeTab(name, text, xScale)
	local btn = Instance.new("TextButton")
	btn.Name             = name
	btn.Position         = UDim2.new(xScale, 16 - xScale * 32, 0, 50)
	btn.Size             = UDim2.new(0.5, -20, 0, 36)
	btn.BackgroundColor3 = Color3.fromRGB(60, 60, 70)
	btn.Font             = Enum.Font.GothamBold
	btn.TextSize         = 17
	btn.TextColor3       = Color3.new(1, 1, 1)
	btn.Text             = text
	btn.Parent           = panel
	addCorner(btn, 8)
	tabs[name] = btn
	return btn
end
makeTab("Passes", "🎫 ゲームパス", 0)
makeTab("Products", "💎 アイテム", 0.5)

local list = Instance.new("ScrollingFrame")
list.Name                   = "List"
list.Position               = UDim2.new(0, 12, 0, 96)
list.Size                   = UDim2.new(1, -24, 1, -108)
list.BackgroundTransparency = 1
list.BorderSizePixel        = 0
list.ScrollBarThickness     = 6
list.AutomaticCanvasSize    = Enum.AutomaticSize.Y
list.CanvasSize             = UDim2.new()
list.Parent                 = panel

local layout = Instance.new("UIListLayout")
layout.Padding   = UDim.new(0, 8)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent    = list

-- 1行分（名前・説明・購入ボタン）を作る
local function makeRow(order, name, desc, buttonText, buttonColor, enabled, onBuy)
	local row = Instance.new("Frame")
	row.LayoutOrder      = order
	row.Size             = UDim2.new(1, -8, 0, 70)
	row.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
	row.BorderSizePixel  = 0
	row.Parent           = list
	addCorner(row, 8)

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Position               = UDim2.new(0, 12, 0, 6)
	nameLabel.Size                   = UDim2.new(1, -130, 0, 26)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font                   = Enum.Font.GothamBold
	nameLabel.TextSize               = 17
	nameLabel.TextColor3             = Color3.new(1, 1, 1)
	nameLabel.TextXAlignment         = Enum.TextXAlignment.Left
	nameLabel.TextTruncate           = Enum.TextTruncate.AtEnd
	nameLabel.Text                   = name
	nameLabel.Parent                 = row

	local descLabel = Instance.new("TextLabel")
	descLabel.Position               = UDim2.new(0, 12, 0, 32)
	descLabel.Size                   = UDim2.new(1, -130, 0, 32)
	descLabel.BackgroundTransparency = 1
	descLabel.Font                   = Enum.Font.Gotham
	descLabel.TextSize               = 13
	descLabel.TextColor3             = Color3.fromRGB(200, 200, 200)
	descLabel.TextXAlignment         = Enum.TextXAlignment.Left
	descLabel.TextYAlignment         = Enum.TextYAlignment.Top
	descLabel.TextWrapped            = true
	descLabel.Text                   = desc or ""
	descLabel.Parent                 = row

	local buy = Instance.new("TextButton")
	buy.AnchorPoint      = Vector2.new(1, 0.5)
	buy.Position         = UDim2.new(1, -10, 0.5, 0)
	buy.Size             = UDim2.new(0, 104, 0, 44)
	buy.BackgroundColor3 = buttonColor
	buy.AutoButtonColor  = enabled
	buy.Font             = Enum.Font.GothamBold
	buy.TextSize         = 16
	buy.TextColor3       = Color3.new(1, 1, 1)
	buy.Text             = buttonText
	buy.Parent           = row
	addCorner(buy, 8)
	if enabled then
		buy.Activated:Connect(onBuy)
	end
	return buy
end

local currentTab = "Passes"

local function robuxText(price)
	return price and ("R$ " .. price) or "購入"
end

-- 一覧を作り直す（タブ切替・所持状況の変化時）
local function rebuildList()
	for _, child in list:GetChildren() do
		if child:IsA("Frame") then child:Destroy() end
	end
	for name, btn in pairs(tabs) do
		btn.BackgroundColor3 = (name == currentTab) and GOLD or Color3.fromRGB(60, 60, 70)
	end

	if currentTab == "Passes" then
		-- Roblox Premium の案内（会員は収入 +10%。Premium Payouts の対象にもなる）
		local premiumBonus = math.floor(TycoonConfig.PremiumBonus * 100)
		if player.MembershipType == Enum.MembershipType.Premium then
			makeRow(0, "👑 Roblox Premium", ("Premium 会員特典: 収入 +%d%% 適用中"):format(premiumBonus),
				"適用中", Color3.fromRGB(60, 140, 70), false)
		else
			makeRow(0, "👑 Roblox Premium", ("Premium 会員になると収入が +%d%%"):format(premiumBonus),
				"詳しく", Color3.fromRGB(0, 120, 215), true, function()
					MarketplaceService:PromptPremiumPurchase(player)
				end)
		end

		for i, pass in ipairs(MonetizationConfig.GamePasses) do
			local owned = player:GetAttribute("Pass_" .. pass.key) == true
			if owned then
				makeRow(i, pass.name, pass.desc, "所有済み", Color3.fromRGB(60, 140, 70), false)
			elseif pass.id == 0 then
				makeRow(i, pass.name, pass.desc, "準備中", Color3.fromRGB(70, 70, 70), false)
			else
				local btn = makeRow(i, pass.name, pass.desc, "…", GOLD, true, function()
					MarketplaceService:PromptGamePassPurchase(player, pass.id)
				end)
				-- 価格は非同期で取得して後から表示
				task.spawn(function()
					btn.Text = robuxText(fetchPrice(pass.id, Enum.InfoType.GamePass))
				end)
			end
		end
	else
		local ips = player:GetAttribute("IncomePerSec") or 0
		for i, product in ipairs(MonetizationConfig.Products) do
			local desc = product.desc
			if product.kind == "money" then
				local amount = MonetizationConfig.moneyPackAmount(product, ips)
				desc = ("%s を今すぐ受け取る（収入%d分ぶん）"):format(TycoonConfig.formatMoney(amount), product.seconds / 60)
			elseif product.kind == "boost" then
				desc = ("%d分間、すべての $ 収入が2倍（重ねて延長可）"):format(product.duration / 60)
			end
			if product.id == 0 then
				makeRow(i, product.name, desc, "準備中", Color3.fromRGB(70, 70, 70), false)
			else
				local btn = makeRow(i, product.name, desc, "…", GOLD, true, function()
					MarketplaceService:PromptProductPurchase(player, product.id)
				end)
				task.spawn(function()
					btn.Text = robuxText(fetchPrice(product.id, Enum.InfoType.Product))
				end)
			end
		end
	end
end

local function openShop()
	panel.Visible = true
	rebuildList()
end

local function closeShop()
	panel.Visible = false
end

tabs.Passes.Activated:Connect(function()
	currentTab = "Passes"
	rebuildList()
end)
tabs.Products.Activated:Connect(function()
	currentTab = "Products"
	rebuildList()
end)
closeBtn.Activated:Connect(closeShop)
OpenShopEvent.OnClientEvent:Connect(openShop)

-- パスを買ったら「所有済み」に更新
for _, pass in ipairs(MonetizationConfig.GamePasses) do
	player:GetAttributeChangedSignal("Pass_" .. pass.key):Connect(function()
		if panel.Visible then rebuildList() end
	end)
end

-- 画面左中央のショップボタン
local shopBtn = Instance.new("TextButton")
shopBtn.Name             = "ShopButton"
shopBtn.AnchorPoint      = Vector2.new(0, 0.5)
shopBtn.Position         = UDim2.new(0, 16, 0.5, 0)
shopBtn.Size             = UDim2.new(0, 72, 0, 72)
shopBtn.BackgroundColor3 = GOLD
shopBtn.Font             = Enum.Font.GothamBlack
shopBtn.TextSize         = 16
shopBtn.TextColor3       = Color3.new(1, 1, 1)
shopBtn.TextWrapped      = true
shopBtn.Text             = "🛒\nショップ"
shopBtn.Parent           = screenGui
addCorner(shopBtn, 12)
shopBtn.Activated:Connect(function()
	if panel.Visible then closeShop() else openShop() end
end)

-- ── 購入結果のポップアップ ───────────────────────────────────

local function popup(text, color)
	local label = Instance.new("TextLabel")
	label.AnchorPoint            = Vector2.new(0.5, 0)
	label.Position               = UDim2.new(0.5, 0, 0, 90)
	label.Size                   = UDim2.new(0, 520, 0, 44)
	label.BackgroundTransparency = 1
	label.Font                   = Enum.Font.GothamBlack
	label.TextSize               = 28
	label.TextColor3             = color
	label.TextStrokeTransparency = 0.2
	label.Text                   = text
	label.Parent                 = screenGui
	TweenService:Create(label, TweenInfo.new(2.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	}):Play()
	task.delay(2.6, function() label:Destroy() end)
end

PurchaseResultEvent.OnClientEvent:Connect(function(ok, message)
	popup(message, ok and Color3.fromRGB(255, 215, 80) or Color3.fromRGB(255, 90, 90))
end)

-- ── ブースト残り時間 ─────────────────────────────────────────
-- 所持金パネル（TycoonUI、左下 -126）のさらに上に表示する

local boostLabel = Instance.new("TextLabel")
boostLabel.Name                   = "BoostLabel"
boostLabel.AnchorPoint            = Vector2.new(0, 1)
boostLabel.Position               = UDim2.new(0, 16, 1, -184)
boostLabel.Size                   = UDim2.new(0, 200, 0, 28)
boostLabel.BackgroundColor3       = Color3.fromRGB(120, 60, 200)
boostLabel.BackgroundTransparency = 0.15
boostLabel.Font                   = Enum.Font.GothamBold
boostLabel.TextSize               = 16
boostLabel.TextColor3             = Color3.new(1, 1, 1)
boostLabel.Visible                = false
boostLabel.Parent                 = screenGui
addCorner(boostLabel, 8)

task.spawn(function()
	while true do
		-- サーバーの os.time() 基準の終了時刻と、サーバー時刻を比べる
		local remaining = (player:GetAttribute("BoostUntil") or 0) - Workspace:GetServerTimeNow()
		if remaining > 0 then
			boostLabel.Visible = true
			boostLabel.Text = ("⚡ 収入2倍  %d:%02d"):format(math.floor(remaining / 60), math.floor(remaining % 60))
		else
			boostLabel.Visible = false
		end
		task.wait(1)
	end
end)

print("[ShopUIController] ショップUIを起動しました。")
