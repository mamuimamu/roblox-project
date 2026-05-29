--[[
	VehicleColorizer（Server / Script）
	起動時に RescueVehicle を消防車カラー（赤）に変更し、
	警察デカールを非表示にする。
]]

local Workspace = game:GetService("Workspace")

local FIRE_RED = Color3.fromRGB(210, 35, 30)

-- 赤く塗らないパーツ（ガラス・ライト・タイヤ・ホイール等）
local KEEP = {
	glass = true, R_glass = true,
	tire = true, trim_black = true, exhaust = true, interior = true,
	light_white = true, light_red = true, light_blue1 = true,
	light_dark_red = true, light_red_tail = true,
	light_rack_glass = true, light_rack1 = true,
	light_rack_red = true, light_rack_red_front = true,
	light_rack_blue = true, light_rack_blue_front = true,
	light_rack_white = true,
	RF_wheel = true, LF_wheel = true, RR_wheel = true, LR_wheel = true,
	RF_wheel_trim = true, LF_wheel_trim = true,
	RR_wheel_trim = true, LR_wheel_trim = true,
}

local function colorize(vehicle)
	local body = vehicle:FindFirstChild("Body")
	if not body then
		warn("[VehicleColorizer] Body が見つかりません")
		return
	end

	for _, obj in body:GetDescendants() do
		if obj:IsA("MeshPart") and not KEEP[obj.Name] then
			obj.Color = FIRE_RED
		end
		if obj:IsA("Decal") then
			obj.Transparency = 1
		end
	end

	print("[VehicleColorizer] 消防車カラーに変更しました")
end

local vehicle = Workspace:FindFirstChild("RescueVehicle")
	or Workspace:WaitForChild("RescueVehicle", 10)

if vehicle then
	colorize(vehicle)
else
	warn("[VehicleColorizer] RescueVehicle が見つかりません")
end
