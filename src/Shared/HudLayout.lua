--[[
	HudLayout（Shared / ModuleScript・クライアント専用）
	スマホでも UI が画面からはみ出さないための共通レイアウト。

	・applyScale(screenGui)
	    画面サイズに合わせて UIScale を付ける。PC（1000×560 以上）は等倍、
	    スマホ横持ち（高さ 300px 前後）は 0.6 倍程度まで縮小する。
	    ScreenGui 直下の UIScale は「画面を 1/scale 倍の大きさとして描いてから縮める」動きになる。
	    オフセット（px）指定の要素だけが小さくなり、中央寄せ・右下寄せなど Scale 指定の位置や
	    サイズは画面に対して変わらない（Studio で実測済み）。
	・getColumn()
	    画面左端・中央の縦一列のボタン置き場（UIListLayout）。複数の LocalScript が
	    ここにボタンを入れる（LayoutOrder で並び順を決める）。
	    左下はスマホのスティック操作の範囲なので、ボタンは置かない。
	・makeColumnButton(name, text, order, color)
	    縦一列用の統一デザインのボタンを作る。
]]

local Players = game:GetService("Players")

local HudLayout = {}

local BASE_WIDTH  = 1000  -- この幅以上なら等倍
local BASE_HEIGHT = 560   -- この高さ以上なら等倍
local MIN_SCALE   = 0.6   -- 文字が読めなくならない下限

HudLayout.COLUMN_BUTTON_SIZE = Vector2.new(132, 46)

-- 画面サイズ（GUI の描画領域）から縮小率を決める
function HudLayout.getScale(absSize)
	local s = math.min(absSize.X / BASE_WIDTH, absSize.Y / BASE_HEIGHT, 1)
	return math.max(MIN_SCALE, s)
end

-- ScreenGui に UIScale を付け、画面サイズ（回転など）の変化に追従させる
function HudLayout.applyScale(screenGui)
	local uiScale = screenGui:FindFirstChild("HudScale")
	if not uiScale then
		uiScale = Instance.new("UIScale")
		uiScale.Name   = "HudScale"
		uiScale.Parent = screenGui
	end
	local function update()
		local size = screenGui.AbsoluteSize
		if size.X > 0 and size.Y > 0 then
			uiScale.Scale = HudLayout.getScale(size)
		end
	end
	screenGui:GetPropertyChangedSignal("AbsoluteSize"):Connect(update)
	update()
	return uiScale
end

-- 左端中央の縦一列（無ければ作る）
function HudLayout.getColumn()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local gui = playerGui:FindFirstChild("HudColumnGui")
	if gui then
		return gui:FindFirstChild("Column")
	end

	gui = Instance.new("ScreenGui")
	gui.Name           = "HudColumnGui"
	gui.ResetOnSpawn   = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent         = playerGui
	HudLayout.applyScale(gui)

	local column = Instance.new("Frame")
	column.Name                   = "Column"
	column.AnchorPoint            = Vector2.new(0, 0.5)
	column.Position               = UDim2.new(0, 12, 0.5, 24)  -- 左上のウェーブパネルと重ならないよう少し下げる
	column.Size                   = UDim2.fromOffset(HudLayout.COLUMN_BUTTON_SIZE.X, 0)
	column.AutomaticSize          = Enum.AutomaticSize.Y
	column.BackgroundTransparency = 1
	column.Parent                 = gui

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.SortOrder     = Enum.SortOrder.LayoutOrder
	layout.Padding       = UDim.new(0, 6)
	layout.Parent        = column

	return column
end

-- 縦一列用のボタン（統一デザイン）
function HudLayout.makeColumnButton(name, text, order, color)
	local btn = Instance.new("TextButton")
	btn.Name                   = name
	btn.LayoutOrder            = order
	btn.Size                   = UDim2.fromOffset(HudLayout.COLUMN_BUTTON_SIZE.X, HudLayout.COLUMN_BUTTON_SIZE.Y)
	btn.BackgroundColor3       = color
	btn.BackgroundTransparency = 0.05
	btn.BorderSizePixel        = 0
	btn.Font                   = Enum.Font.GothamBold
	btn.TextSize               = 16
	btn.TextColor3             = Color3.new(1, 1, 1)
	btn.TextWrapped            = true
	btn.Text                   = text
	btn.Parent                 = HudLayout.getColumn()

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent       = btn

	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color           = Color3.new(0, 0, 0)
	stroke.Transparency    = 0.6
	stroke.Parent          = btn
	return btn
end

return HudLayout
