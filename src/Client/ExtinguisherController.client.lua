--[[
	ExtinguisherController（Client / LocalScript）
	消火器ツール装備中のみ動作。クリック保持でパーティクルスプレーを出しつつ
	消火イベントをサーバーへ送信し続ける。
]]

local Players          = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace        = game:GetService("Workspace")

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera

local ExtinguishEvent = ReplicatedStorage:WaitForChild("ExtinguishEvent")

local SPRAY_INTERVAL = 0.12   -- サーバーへ送信する間隔（秒）
local TOOL_NAME      = "消火器"

local equippedTool    = nil
local isSpraying      = false
local particleEmitter = nil
local activatedConn   = nil
local deactivatedConn = nil

-- ── パーティクル作成 ─────────────────────────────────────────────────────

local function setupParticles(handle)
	local old = handle:FindFirstChild("SprayParticles")
	if old then old:Destroy() end

	local e = Instance.new("ParticleEmitter")
	e.Name    = "SprayParticles"
	e.Enabled = false
	e.Color   = ColorSequence.new({
		ColorSequenceKeypoint.new(0,   Color3.new(1, 1, 1)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(210, 235, 255)),
		ColorSequenceKeypoint.new(1,   Color3.fromRGB(180, 205, 230)),
	})
	e.LightEmission  = 0
	e.LightInfluence = 0.9
	e.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0,    0.1),
		NumberSequenceKeypoint.new(0.35, 0.5),
		NumberSequenceKeypoint.new(1,    0),
	})
	e.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0,   0.1),
		NumberSequenceKeypoint.new(0.5, 0.5),
		NumberSequenceKeypoint.new(1,   1),
	})
	e.Lifetime    = NumberRange.new(0.35, 0.6)
	e.Rate        = 100
	e.Speed       = NumberRange.new(20, 32)
	e.SpreadAngle = Vector2.new(30, 30)
	e.RotSpeed    = NumberRange.new(-60, 60)
	e.Rotation    = NumberRange.new(0, 360)
	e.Parent      = handle
	return e
end

-- ── エイムレイ取得 ───────────────────────────────────────────────────────

local function getAimRay()
	if not camera then camera = Workspace.CurrentCamera end
	if not camera then return nil, nil end
	local mouse = UserInputService:GetMouseLocation()
	local ray   = camera:ScreenPointToRay(mouse.X, mouse.Y)
	return ray.Origin, ray.Direction.Unit
end

-- ── スプレー開始 / 停止 ───────────────────────────────────────────────────

local function startSpray()
	if isSpraying then return end
	isSpraying = true
	if particleEmitter then particleEmitter.Enabled = true end

	task.spawn(function()
		while isSpraying do
			local origin, dir = getAimRay()
			if origin and dir then
				ExtinguishEvent:FireServer(origin, dir)
			end
			task.wait(SPRAY_INTERVAL)
		end
	end)
end

local function stopSpray()
	isSpraying = false
	if particleEmitter then particleEmitter.Enabled = false end
end

-- ── ツール接続管理 ───────────────────────────────────────────────────────

local function disconnectTool()
	if activatedConn   then activatedConn:Disconnect();   activatedConn   = nil end
	if deactivatedConn then deactivatedConn:Disconnect(); deactivatedConn = nil end
end

local function onToolAdded(tool)
	if tool.Name ~= TOOL_NAME then return end
	equippedTool = tool
	disconnectTool()

	local handle = tool:FindFirstChild("Handle")
	if handle then
		particleEmitter = setupParticles(handle)
	end

	activatedConn   = tool.Activated:Connect(startSpray)
	deactivatedConn = tool.Deactivated:Connect(stopSpray)
end

local function onToolRemoved(child)
	if child ~= equippedTool then return end
	disconnectTool()
	stopSpray()
	equippedTool    = nil
	particleEmitter = nil
end

local function setupCharacter(character)
	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("Tool") then onToolAdded(child) end
	end
	character.ChildAdded:Connect(function(child)
		if child:IsA("Tool") then onToolAdded(child) end
	end)
	character.ChildRemoved:Connect(onToolRemoved)
end

player.CharacterAdded:Connect(setupCharacter)
if player.Character then setupCharacter(player.Character) end

print("[Client] ExtinguisherController: 消火器コントローラーを有効にしました。")
