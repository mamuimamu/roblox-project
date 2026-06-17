--[[
	BurningHouseController（Client / LocalScript）
	IsBurning 属性を監視してパーティクルをローカル管理。
	Workspace 全体を監視するためクローンされた複数の火災建物に対応。
]]

local Workspace = game:GetService("Workspace")

local partEffects = {}  -- [part] = { att, fire, smoke }

-- ── ユーティリティ ──────────────────────────────────────────

local function ns(kps)
	local out = {}
	for _, k in ipairs(kps) do
		out[#out + 1] = NumberSequenceKeypoint.new(k[1], k[2], k[3] or 0)
	end
	return NumberSequence.new(out)
end

local function fireScale(part)
	local avg = (part.Size.X + part.Size.Y + part.Size.Z) / 3
	return math.clamp(avg * 0.22, 0.25, 2.2)
end

-- ── パーティクル生成 ─────────────────────────────────────────

local function createEffects(part)
	local s = fireScale(part)
	local isBoss = part:GetAttribute("IsBossFire") == true
	-- ボス火事はパーティクルを1.8倍スケールにして視覚的に強調する
	local sm = isBoss and 1.8 or 1.0

	local att = Instance.new("Attachment")
	att.Name     = "BurnAttachment"
	att.Position = Vector3.new(0, part.Size.Y * 0.38, 0)
	att.Parent   = part

	local fire = Instance.new("ParticleEmitter")
	fire.Name  = "FlameEmitter"
	-- ボス火事は深紅・暗赤、通常は黄橙色
	if isBoss then
		fire.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0,    Color3.fromRGB(255,  80,   0)),
			ColorSequenceKeypoint.new(0.3,  Color3.fromRGB(220,  10,   0)),
			ColorSequenceKeypoint.new(1,    Color3.fromRGB( 80,   0,   0)),
		})
	else
		fire.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0,    Color3.fromRGB(255, 220,  20)),
			ColorSequenceKeypoint.new(0.35, Color3.fromRGB(255,  70,   0)),
			ColorSequenceKeypoint.new(1,    Color3.fromRGB(170,  10,   0)),
		})
	end
	fire.LightEmission  = isBoss and 0.4 or 0
	fire.LightInfluence = 0
	fire.Size         = ns({{0, s*sm*0.55, s*sm*0.18}, {0.4, s*sm*1.1, s*sm*0.25}, {1, 0, 0}})
	fire.Transparency = ns({{0, 0.05, 0}, {0.6, 0.28, 0}, {1, 1, 0}})
	fire.Speed        = NumberRange.new(3, 10)
	fire.SpreadAngle  = Vector2.new(28, 28)
	fire.Lifetime     = NumberRange.new(0.4, 1.3)
	fire.Rate         = isBoss and 80 or 45  -- ボス火事は初期レートも高め
	fire.RotSpeed     = NumberRange.new(-70, 70)
	fire.Rotation     = NumberRange.new(0, 360)
	fire.LockedToPart = false
	fire.Parent       = att

	local smoke = Instance.new("ParticleEmitter")
	smoke.Name  = "SmokeEmitter"
	-- ボス火事は濃い黒煙
	if isBoss then
		smoke.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0,    Color3.fromRGB(10,  10,  10)),
			ColorSequenceKeypoint.new(0.45, Color3.fromRGB(40,  40,  40)),
			ColorSequenceKeypoint.new(1,    Color3.fromRGB(90,  90,  90)),
		})
	else
		smoke.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0,    Color3.fromRGB(25,  25,  25)),
			ColorSequenceKeypoint.new(0.45, Color3.fromRGB(75,  75,  75)),
			ColorSequenceKeypoint.new(1,    Color3.fromRGB(155, 155, 155)),
		})
	end
	smoke.LightEmission  = 0
	smoke.LightInfluence = 0.55
	smoke.Size         = ns({{0, s*sm*0.7, 0}, {0.35, s*sm*2.8, s*sm*0.45}, {1, s*sm*4.5, 0}})
	smoke.Transparency = ns({{0, 0.18, 0}, {0.5, 0.52, 0}, {1, 1, 0}})
	smoke.Speed        = NumberRange.new(10, 28)
	smoke.SpreadAngle  = Vector2.new(7, 7)
	smoke.Lifetime     = NumberRange.new(3, 7)
	smoke.Rate         = isBoss and 22 or 14
	smoke.RotSpeed     = NumberRange.new(-18, 18)
	smoke.Rotation     = NumberRange.new(0, 360)
	smoke.LockedToPart = false
	smoke.Parent       = att

	return att, fire, smoke
end

-- ── パーティクル即時消去 ─────────────────────────────────────

local function doExtinguish(part)
	local d = partEffects[part]
	if not d then return end
	partEffects[part] = nil

	if d.att and d.att.Parent then
		d.att:Destroy()
	end

	for _, child in part:GetDescendants() do
		if child:IsA("Fire") or child:IsA("Smoke") then
			child.Enabled = false
		elseif child:IsA("ParticleEmitter") then
			child:Clear()
			child.Enabled = false
		elseif child:IsA("Attachment") and child.Name == "BurnAttachment" then
			child:Destroy()
		end
	end

	print("[Client] 鎮火エフェクト消去:", part.Name)
end

-- ── パーツ監視登録 ───────────────────────────────────────────

local function watchPart(part)
	if not part:IsA("BasePart") then return end
	if partEffects[part] then return end
	if part:GetAttribute("IsBurning") ~= true then return end

	local att, fire, smoke = createEffects(part)
	partEffects[part] = { att = att, fire = fire, smoke = smoke }
	print("[Client] 火災エフェクト開始:", part.Name)

	part:GetAttributeChangedSignal("IsBurning"):Connect(function()
		if part:GetAttribute("IsBurning") == false then
			doExtinguish(part)
		end
	end)

	part:GetAttributeChangedSignal("BurnIntensity"):Connect(function()
		local d = partEffects[part]
		if not d then return end
		local i = math.max(part:GetAttribute("BurnIntensity") or 0, 0)
		d.fire.Rate  = math.floor(45 * i)
		d.smoke.Rate = math.floor(14 * i)
		d.fire.Speed  = NumberRange.new(math.max(3 * i, 0.5), math.max(10 * i, 1))
		d.smoke.Speed = NumberRange.new(math.max(10 * i, 1),  math.max(28 * i, 2))
	end)
end

local function registerPart(desc)
	if not desc:IsA("BasePart") then return end
	watchPart(desc)
	desc:GetAttributeChangedSignal("IsBurning"):Connect(function()
		if desc:GetAttribute("IsBurning") == true and not partEffects[desc] then
			watchPart(desc)
		end
	end)
end

-- ── ポーリングループ（シグナルを補完） ────────────────────────

task.spawn(function()
	while true do
		task.wait(0.2)
		local toRemove = {}
		for part in pairs(partEffects) do
			if part:GetAttribute("IsBurning") == false then
				toRemove[#toRemove + 1] = part
			end
		end
		for _, part in ipairs(toRemove) do
			doExtinguish(part)
		end
	end
end)

-- ── Workspace 全体を監視（クローン対応） ────────────────────

for _, desc in Workspace:GetDescendants() do
	registerPart(desc)
end

Workspace.DescendantAdded:Connect(function(desc)
	task.wait()
	registerPart(desc)
end)

print("[Client] BurningHouseController: 起動しました。")
