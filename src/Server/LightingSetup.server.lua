--[[
	LightingSetup（Server / Script）
	Lighting を昼間・ニュートラルに強制設定して視認性を確保する。
]]

local Lighting = game:GetService("Lighting")

-- ── 昼間・ニュートラルに強制設定 ────────────────────────────

Lighting.ClockTime       = 12    -- 正午（太陽が真上 = 黄色みなし）
Lighting.Brightness      = 1.5
Lighting.Ambient         = Color3.fromRGB(80,  80,  80)
Lighting.OutdoorAmbient  = Color3.fromRGB(135, 135, 135)
Lighting.FogEnd          = 100000
Lighting.GlobalShadows   = true

-- ── 全 Lighting 子要素を診断して調整 ────────────────────────

print("[LightingSetup] Lighting 子要素一覧:")
for _, child in Lighting:GetChildren() do
	print("  -> " .. child.ClassName .. " : " .. child.Name)

	if child:IsA("BloomEffect") then
		child.Intensity = 0.15
		child.Size      = 24
		child.Threshold = 0.95
		print("     BloomEffect を抑制しました")

	elseif child:IsA("ColorCorrectionEffect") then
		child.TintColor  = Color3.new(1, 1, 1)
		child.Brightness = 0
		child.Contrast   = 0
		child.Saturation = 0
		print("     ColorCorrectionEffect をニュートラルに設定しました")

	elseif child:IsA("SunRaysEffect") then
		child.Enabled = false
		print("     SunRaysEffect を無効化しました")

	elseif child:IsA("Atmosphere") then
		child.Haze         = 0
		child.Density      = 0.15
		child.Color        = Color3.fromRGB(199, 199, 199)
		child.Glare        = 0
		child.Decay        = Color3.fromRGB(255, 255, 255)
		print("     Atmosphere を調整しました")

	elseif child:IsA("DepthOfFieldEffect") then
		child.Enabled = false
		print("     DepthOfFieldEffect を無効化しました")

	elseif child:IsA("Sky") then
		print("     Sky オブジェクトが存在します（そのまま）")
	end
end

print("[LightingSetup] Lighting 設定完了（ClockTime=12 に固定）")
