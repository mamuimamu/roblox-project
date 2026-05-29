--[[
	MinimapController（Client / LocalScript）
	右下にミニマップを表示し、火災位置とプレイヤー位置をリアルタイムで示す。
]]

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace  = game:GetService("Workspace")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ワールド空間でのマップ半径（TownGenerator の MAP_HALF に合わせる）
local WORLD_HALF = 160
local UI_SIZE    = 150  -- ミニマップの表示サイズ（px）

-- ── UI 構築 ─────────────────────────────────────────────────

local screenGui = Instance.new("ScreenGui")
screenGui.Name           = "MinimapGui"
screenGui.ResetOnSpawn   = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent         = playerGui

-- 外枠
local mapFrame = Instance.new("Frame")
mapFrame.Name                  = "MapFrame"
mapFrame.Size                  = UDim2.new(0, UI_SIZE, 0, UI_SIZE)
mapFrame.AnchorPoint           = Vector2.new(1, 1)
mapFrame.Position              = UDim2.new(1, -16, 1, -80)
mapFrame.BackgroundColor3      = Color3.fromRGB(15, 20, 15)
mapFrame.BackgroundTransparency = 0.3
mapFrame.BorderSizePixel       = 0
mapFrame.ClipsDescendants      = true
mapFrame.Parent                = screenGui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 8)
corner.Parent       = mapFrame

-- ラベル
local label = Instance.new("TextLabel")
label.Size                 = UDim2.new(1, 0, 0, 18)
label.Position             = UDim2.new(0, 0, 0, 0)
label.BackgroundTransparency = 1
label.Font                 = Enum.Font.GothamBold
label.TextSize             = 12
label.TextColor3           = Color3.fromRGB(200, 200, 200)
label.Text                 = "マップ"
label.ZIndex               = 4
label.Parent               = mapFrame

-- 簡易道路（縦横3本ずつ: -80, 0, +80）
local ROAD_COORDS = { -80, 0, 80 }
local ROAD_CLR    = Color3.fromRGB(55, 55, 55)

local function worldToUi(wx, wz)
	local ux = (wx / (WORLD_HALF * 2) + 0.5) * UI_SIZE
	local uz = (wz / (WORLD_HALF * 2) + 0.5) * UI_SIZE
	return math.clamp(ux, 0, UI_SIZE), math.clamp(uz, 0, UI_SIZE)
end

for _, coord in ipairs(ROAD_COORDS) do
	-- 縦道路（X=coord）
	local rNS = Instance.new("Frame")
	rNS.Size                  = UDim2.new(0, 3, 1, 0)
	rNS.AnchorPoint           = Vector2.new(0.5, 0)
	local rx, _ = worldToUi(coord, 0)
	rNS.Position              = UDim2.new(0, rx, 0, 0)
	rNS.BackgroundColor3      = ROAD_CLR
	rNS.BorderSizePixel       = 0
	rNS.ZIndex                = 1
	rNS.Parent                = mapFrame

	-- 横道路（Z=coord）
	local rEW = Instance.new("Frame")
	rEW.Size                  = UDim2.new(1, 0, 0, 3)
	rEW.AnchorPoint           = Vector2.new(0, 0.5)
	local _, rz = worldToUi(0, coord)
	rEW.Position              = UDim2.new(0, 0, 0, rz)
	rEW.BackgroundColor3      = ROAD_CLR
	rEW.BorderSizePixel       = 0
	rEW.ZIndex                = 1
	rEW.Parent                = mapFrame
end

-- プレイヤードット（黄色）
local playerDot = Instance.new("Frame")
playerDot.Name             = "PlayerDot"
playerDot.Size             = UDim2.new(0, 10, 0, 10)
playerDot.AnchorPoint      = Vector2.new(0.5, 0.5)
playerDot.BackgroundColor3 = Color3.fromRGB(255, 230, 50)
playerDot.BorderSizePixel  = 0
playerDot.ZIndex           = 5
playerDot.Parent           = mapFrame

local pdCorner = Instance.new("UICorner")
pdCorner.CornerRadius = UDim.new(1, 0)
pdCorner.Parent       = playerDot

-- ── 火災ドット管理 ───────────────────────────────────────────

local fireDots = {}  -- [part] = Frame

local function createFireDot()
	local dot = Instance.new("Frame")
	dot.Size             = UDim2.new(0, 10, 0, 10)
	dot.AnchorPoint      = Vector2.new(0.5, 0.5)
	dot.BackgroundColor3 = Color3.fromRGB(255, 55, 20)
	dot.BorderSizePixel  = 0
	dot.ZIndex           = 3
	dot.Parent           = mapFrame

	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(1, 0)
	c.Parent       = dot

	-- 点滅エフェクト
	local flash = Instance.new("Frame")
	flash.Size             = UDim2.new(0, 18, 0, 18)
	flash.AnchorPoint      = Vector2.new(0.5, 0.5)
	flash.Position         = UDim2.new(0.5, 0, 0.5, 0)
	flash.BackgroundColor3 = Color3.fromRGB(255, 100, 30)
	flash.BackgroundTransparency = 0.5
	flash.BorderSizePixel  = 0
	flash.ZIndex           = 2
	flash.Parent           = dot

	local fc = Instance.new("UICorner")
	fc.CornerRadius = UDim.new(1, 0)
	fc.Parent       = flash

	task.spawn(function()
		while dot.Parent do
			for t = 0, 1, 0.1 do
				if not dot.Parent then break end
				flash.BackgroundTransparency = 0.3 + t * 0.6
				task.wait(0.05)
			end
			for t = 1, 0, -0.1 do
				if not dot.Parent then break end
				flash.BackgroundTransparency = 0.3 + t * 0.6
				task.wait(0.05)
			end
		end
	end)

	return dot
end

local function removeDot(part)
	if fireDots[part] then
		fireDots[part]:Destroy()
		fireDots[part] = nil
	end
end

local function watchPart(part)
	if not part:IsA("BasePart") then return end
	if fireDots[part] then return end
	if part:GetAttribute("IsBurning") ~= true then return end

	fireDots[part] = createFireDot()

	part:GetAttributeChangedSignal("IsBurning"):Connect(function()
		if part:GetAttribute("IsBurning") ~= true then
			removeDot(part)
		end
	end)
end

local function registerPart(desc)
	if not desc:IsA("BasePart") then return end
	watchPart(desc)
	desc:GetAttributeChangedSignal("IsBurning"):Connect(function()
		if desc:GetAttribute("IsBurning") == true then
			watchPart(desc)
		end
	end)
end

for _, desc in Workspace:GetDescendants() do
	registerPart(desc)
end

Workspace.DescendantAdded:Connect(function(desc)
	task.wait()
	registerPart(desc)
end)

-- ── 毎フレーム更新 ──────────────────────────────────────────

RunService.Heartbeat:Connect(function()
	-- プレイヤー位置
	local char = player.Character
	if char then
		local root = char:FindFirstChild("HumanoidRootPart")
		if root then
			local ux, uz = worldToUi(root.Position.X, root.Position.Z)
			playerDot.Position = UDim2.new(0, ux, 0, uz)
		end
	end

	-- 火災ドット位置
	for part, dot in pairs(fireDots) do
		if part.Parent then
			local ux, uz = worldToUi(part.Position.X, part.Position.Z)
			dot.Position = UDim2.new(0, ux, 0, uz)
		else
			dot:Destroy()
			fireDots[part] = nil
		end
	end
end)

print("[Client] MinimapController: ミニマップ起動しました。")
