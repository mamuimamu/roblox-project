--[[
	ExtinguisherController（Client / LocalScript）
	消火器ツール装備中のみ動作。クリック/タップ保持でスプレーエフェクトを出しつつ
	消火イベントをサーバーへ送信し続ける。

	モバイル対応:
	  - Beam エフェクトを追加（低品質設定でも必ず描画される）
	  - ParticleEmitter は Emit() で強制バースト（Enabled トグルより確実）
	  - MIN_SPRAY_DURATION でタップ一回でも十分な時間エフェクトが出る
	  - InputBegan/InputChanged でタッチ位置を明示追跡し、ビームを正しい方向へ飛ばす
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService  = game:GetService("UserInputService")
local Workspace         = game:GetService("Workspace")

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera

local ExtinguishEvent = ReplicatedStorage:WaitForChild("ExtinguishEvent")

local SPRAY_INTERVAL     = 0.12   -- サーバーへの送信間隔（秒）
local SPRAY_DISTANCE     = 28     -- Beam エフェクトの長さ（スタッズ）
local MIN_SPRAY_DURATION = 0.5    -- モバイルタップでも見えるよう最低継続時間（秒）
local TOOL_NAME          = "消火器"

local equippedTool    = nil
local isSpraying      = false
local particleEmitter = nil
local sprayBeam       = nil
local beamTargetPart  = nil
local activatedConn   = nil
local deactivatedConn = nil
local sprayStartTime  = -math.huge

-- ── モバイルタッチ位置追跡 ────────────────────────────────────────
-- GetMouseLocation() はモバイルで指を離すと正しい位置を返さない場合があるため、
-- InputBegan/InputChanged で明示的にタッチ位置を記録する

local isTouchDevice  = UserInputService.TouchEnabled
local lastTouchPos   = nil  -- 最後のタッチ画面座標（Vector2）

UserInputService.InputBegan:Connect(function(input)
	-- gameProcessed チェックなし: ツール使用時も gameProcessed=true になる場合があるため
	if input.UserInputType == Enum.UserInputType.Touch then
		lastTouchPos = Vector2.new(input.Position.X, input.Position.Y)
	end
end)

UserInputService.InputChanged:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.Touch then
		lastTouchPos = Vector2.new(input.Position.X, input.Position.Y)
	end
end)

-- ── パーティクル作成 ──────────────────────────────────────────

local function setupParticles(handle)
	local old = handle:FindFirstChild("SprayParticles")
	if old then old:Destroy() end

	local e = Instance.new("ParticleEmitter")
	e.Name    = "SprayParticles"
	e.Enabled = false   -- Emit() で制御するため常時オフ
	e.Rate    = 0       -- Emit() 使用時は Rate=0 が推奨
	e.Color   = ColorSequence.new({
		ColorSequenceKeypoint.new(0,   Color3.new(1, 1, 1)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(210, 235, 255)),
		ColorSequenceKeypoint.new(1,   Color3.fromRGB(180, 205, 230)),
	})
	e.LightEmission  = 0.15
	e.LightInfluence = 0.7
	-- PC では十分見えるよう少し大きめに
	e.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0,    0.2),
		NumberSequenceKeypoint.new(0.35, 0.8),
		NumberSequenceKeypoint.new(1,    0),
	})
	e.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0,   0),
		NumberSequenceKeypoint.new(0.5, 0.4),
		NumberSequenceKeypoint.new(1,   1),
	})
	e.Lifetime    = NumberRange.new(0.4, 0.7)
	e.Speed       = NumberRange.new(20, 32)
	e.SpreadAngle = Vector2.new(30, 30)
	e.RotSpeed    = NumberRange.new(-60, 60)
	e.Rotation    = NumberRange.new(0, 360)
	e.Parent      = handle
	return e
end

-- ── Beam エフェクト作成（低品質設定でも描画される） ────────────

local function setupBeam(handle)
	local oldBeam = handle:FindFirstChild("SprayBeam")
	if oldBeam then oldBeam:Destroy() end

	-- ノズル側アタッチメント
	local att0 = handle:FindFirstChild("SprayNozzle")
	if not att0 then
		att0      = Instance.new("Attachment")
		att0.Name = "SprayNozzle"
		att0.Parent = handle
	end

	-- ビーム先端用の不可視パーツ（照準方向に毎フレーム移動）
	if beamTargetPart then beamTargetPart:Destroy() end
	beamTargetPart              = Instance.new("Part")
	beamTargetPart.Size         = Vector3.one * 0.05
	beamTargetPart.Transparency = 1
	beamTargetPart.CanCollide   = false
	beamTargetPart.Anchored     = true
	beamTargetPart.CastShadow   = false
	beamTargetPart.Parent       = Workspace

	local att1        = Instance.new("Attachment")
	att1.Parent       = beamTargetPart

	local beam            = Instance.new("Beam")
	beam.Name             = "SprayBeam"
	beam.Attachment0      = att0
	beam.Attachment1      = att1
	beam.Color            = ColorSequence.new({
		ColorSequenceKeypoint.new(0,   Color3.fromRGB(240, 250, 255)),
		ColorSequenceKeypoint.new(0.6, Color3.fromRGB(200, 230, 255)),
		ColorSequenceKeypoint.new(1,   Color3.fromRGB(180, 215, 240)),
	})
	beam.Transparency     = NumberSequence.new({
		NumberSequenceKeypoint.new(0,   0.0),
		NumberSequenceKeypoint.new(0.7, 0.3),
		NumberSequenceKeypoint.new(1,   0.9),
	})
	beam.Width0           = 0.75
	beam.Width1           = 0.05
	beam.Segments         = 6
	beam.LightInfluence   = 0
	beam.LightEmission    = 0.6
	beam.Enabled          = false
	beam.Parent           = handle
	return beam
end

-- ── エイムレイ取得 ───────────────────────────────────────────

-- aimPos: スプレー開始時にロックした画面座標（nil ならリアルタイム取得）
local function getAimRay(aimPos)
	if not camera then camera = Workspace.CurrentCamera end
	if not camera then return nil, nil end

	-- モバイル: 明示追跡したタッチ位置を優先。GetMouseLocation() は
	-- 指を離した後に正しい値を返さない機種がある。
	local screenPos
	if aimPos then
		screenPos = aimPos
	elseif isTouchDevice and lastTouchPos then
		screenPos = lastTouchPos
	else
		screenPos = UserInputService:GetMouseLocation()
	end

	local ray = camera:ScreenPointToRay(screenPos.X, screenPos.Y)
	return ray.Origin, ray.Direction.Unit
end

-- ── スプレー開始 / 停止 ───────────────────────────────────────

local function startSpray()
	if isSpraying then return end
	isSpraying   = true
	sprayStartTime = os.clock()

	-- モバイルではタップ開始時の画面座標をスナップショット。
	-- 指が離れた後も GetMouseLocation() ではなくこの座標を使い続けることで
	-- ビームが正しく火元を向き続ける。
	local lockedAimPos = (isTouchDevice and lastTouchPos)
		and Vector2.new(lastTouchPos.X, lastTouchPos.Y)
		or nil

	if sprayBeam then sprayBeam.Enabled = true end

	task.spawn(function()
		-- isSpraying が false になっても MIN_SPRAY_DURATION だけは継続
		repeat
			local origin, dir = getAimRay(lockedAimPos)
			if origin and dir then
				-- Beam 先端を照準方向へ更新
				if beamTargetPart then
					beamTargetPart.CFrame = CFrame.new(origin + dir * SPRAY_DISTANCE)
				end
				-- パーティクルを強制バースト（Emit はグラフィック品質に左右されにくい）
				if particleEmitter then
					particleEmitter:Emit(14)
				end
				-- スプレー中のみサーバーへ送信
				if isSpraying then
					ExtinguishEvent:FireServer(origin, dir)
				end
			end
			task.wait(SPRAY_INTERVAL)
		until not isSpraying and (os.clock() - sprayStartTime >= MIN_SPRAY_DURATION)

		if sprayBeam then sprayBeam.Enabled = false end
	end)
end

local function stopSpray()
	isSpraying = false
	-- Beam・パーティクルは repeat ループが終了次第自動停止
end

-- ── ツール接続管理 ───────────────────────────────────────────

local function disconnectTool()
	if activatedConn   then activatedConn:Disconnect();   activatedConn   = nil end
	if deactivatedConn then deactivatedConn:Disconnect(); deactivatedConn = nil end
end

local function onToolAdded(tool)
	-- ツール名を毎回出力して照合確認
	print("[ExtinguisherController] ツール検出:", tool.Name, "/ 期待名:", TOOL_NAME)
	if tool.Name ~= TOOL_NAME then return end
	equippedTool = tool
	disconnectTool()

	local handle = tool:FindFirstChild("Handle")
	if handle then
		print("[ExtinguisherController] Handle を発見しました:", handle.ClassName)
		particleEmitter = setupParticles(handle)
		sprayBeam       = setupBeam(handle)
	else
		warn("[ExtinguisherController] Handle が見つかりません！エフェクトなしで動作します。")
	end

	activatedConn   = tool.Activated:Connect(startSpray)
	deactivatedConn = tool.Deactivated:Connect(stopSpray)
	print("[ExtinguisherController] 消火器を装備しました。スプレー準備完了。")
end

local function onToolRemoved(child)
	if child ~= equippedTool then return end
	disconnectTool()
	stopSpray()
	if beamTargetPart then beamTargetPart:Destroy(); beamTargetPart = nil end
	equippedTool    = nil
	particleEmitter = nil
	sprayBeam       = nil
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
