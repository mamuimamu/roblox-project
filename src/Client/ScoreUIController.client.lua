--[[
	消火数スコアUI（Client / LocalScript）
	leaderstats.Fires の変化を監視し、画面左下に表示する。
]]

local Players = game:GetService("Players")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local function createScoreUI()
	local screenGui = Instance.new("ScreenGui")
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

local scoreLabel = createScoreUI()
bindScoreLabel(scoreLabel)

print("[Client] ScoreUIController: スコアUIを表示しました。")
