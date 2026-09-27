--[[
	MonetizationManager（Server / Script）
	Robux 課金（ゲームパス・デベロッパー製品）の判定と付与。

	ゲームパス:
	  ・参加時に UserOwnsGamePassAsync で所持を確認し、player:SetAttribute("Pass_<key>", true)
	  ・ゲーム内で購入した直後は PromptGamePassPurchaseFinished で即反映
	  ・効果の計算は Economy.hasPass で行う（倍率・自動回収・精鋭隊員・VIP消防車）

	デベロッパー製品（ProcessReceipt）:
	  ・PurchaseId を PlayerProfiles.PurchaseHistory に記録して二重付与を防ぐ
	  ・付与後に DataManager の SavePlayer で即セーブし、成功したときだけ PurchaseGranted を返す
	    （セーブ失敗時は NotProcessedYet → Roblox が次回参加時などに再送してくる）
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players            = game:GetService("Players")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local ServerStorage      = game:GetService("ServerStorage")

local Shared             = ReplicatedStorage:WaitForChild("Shared")
local MonetizationConfig = require(Shared:WaitForChild("MonetizationConfig"))
local PlayerProfiles     = require(script.Parent:WaitForChild("PlayerProfiles"))
local Economy            = require(script.Parent:WaitForChild("Economy"))

local SavePlayer = ServerStorage:WaitForChild("SavePlayer", 30)

-- ── RemoteEvent ─────────────────────────────────────────────

local function getOrCreateRemoteEvent(name)
	local existing = ReplicatedStorage:FindFirstChild(name)
	if existing and existing:IsA("RemoteEvent") then return existing end
	local event = Instance.new("RemoteEvent")
	event.Name   = name
	event.Parent = ReplicatedStorage
	return event
end

-- S→C: 課金アイテムの付与結果（ok, message）
local PurchaseResultEvent = getOrCreateRemoteEvent("PurchaseResultEvent")

-- ── ゲームパス ──────────────────────────────────────────────

local function setPassOwned(player, pass)
	player:SetAttribute("Pass_" .. pass.key, true)
	print(("[MonetizationManager] %s はゲームパス「%s」を所持"):format(player.Name, pass.name))
end

-- 参加時に全パスの所持を確認する（API は失敗しうるので pcall）
local function checkGamePasses(player)
	for _, pass in ipairs(MonetizationConfig.GamePasses) do
		if pass.id ~= 0 then
			local ok, owns = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(player.UserId, pass.id)
			end)
			if ok and owns then
				setPassOwned(player, pass)
			elseif not ok then
				warn(("[MonetizationManager] パス確認失敗 %s / %s: %s"):format(player.Name, pass.key, tostring(owns)))
			end
		end
	end
end

-- 確認が終わったら PassesChecked を立てる（オフライン収入の計算がパスの有無を待つため）
local function checkGamePassesAndMark(player)
	checkGamePasses(player)
	player:SetAttribute("PassesChecked", true)
end

Players.PlayerAdded:Connect(checkGamePassesAndMark)
for _, player in Players:GetPlayers() do
	task.spawn(checkGamePassesAndMark, player)
end

-- ゲーム内で買った直後に即反映
MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
	if not purchased then return end
	local pass = MonetizationConfig.PassById[passId]
	if not pass then return end
	setPassOwned(player, pass)
	PurchaseResultEvent:FireClient(player, true, pass.name .. " を手に入れた！")
end)

-- ── デベロッパー製品の付与処理 ───────────────────────────────
-- 戻り値: 付与できたら結果メッセージ、できなければ nil

local grantHandlers = {}

-- 資金パック: 秒間収入 × 秒数（最低額あり）
function grantHandlers.money(player, product)
	local ls    = player:FindFirstChild("leaderstats")
	local money = ls and ls:FindFirstChild("Money")
	if not money then return nil end
	local amount = MonetizationConfig.moneyPackAmount(product, Economy.getIncomePerSecond(player))
	money.Value += amount
	return ("💵 $%d を受け取った！"):format(amount)
end

-- 収入2倍ブースト: 有効中に買うと残り時間に加算
function grantHandlers.boost(player, product)
	local profile = PlayerProfiles.get(player)
	if not profile then return nil end
	local now = os.time()
	profile.BoostUntil = math.max(profile.BoostUntil or 0, now) + product.duration
	player:SetAttribute("BoostUntil", profile.BoostUntil)
	return ("⚡ 収入2倍ブースト 残り%d分"):format(math.ceil((profile.BoostUntil - now) / 60))
end

-- 即時建設: 建てられる物が無いときは資金パック L 相当を代わりに付与（払い損を防ぐ）
function grantHandlers.build(player, _product)
	local grantBindable = ServerStorage:FindFirstChild("TycoonGrantNextButton")
	local builtName = grantBindable and grantBindable:Invoke(player)
	if builtName then
		return ("🏗 %s を即時建設！"):format(builtName)
	end
	local fallback = MonetizationConfig.ProductByKey.MoneyLarge
	local msg = grantHandlers.money(player, fallback)
	return msg and ("建てられる建物が無いため、代わりに " .. msg) or nil
end

-- ── ProcessReceipt ──────────────────────────────────────────

local function alreadyGranted(profile, purchaseId)
	for _, id in ipairs(profile.PurchaseHistory) do
		if id == purchaseId then return true end
	end
	return false
end

MarketplaceService.ProcessReceipt = function(receipt)
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	if not player then
		-- 退出済み: 次回参加時に Roblox が再送してくる
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	-- データのロード完了を待つ（プロフィールが無いと履歴を確認できない）
	local profile = PlayerProfiles.waitFor(player, 15)
	if not profile or player:GetAttribute("DataLoadFailed") == true then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	-- すでに付与済み（前回セーブ後にレシートが再送された）なら完了扱い
	if alreadyGranted(profile, receipt.PurchaseId) then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	local product = MonetizationConfig.ProductById[receipt.ProductId]
	if not product then
		warn("[MonetizationManager] 未登録の製品ID: " .. tostring(receipt.ProductId))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local handler = grantHandlers[product.kind]
	local ok, message = pcall(handler, player, product)
	if not ok or not message then
		warn(("[MonetizationManager] 付与失敗 %s / %s: %s"):format(player.Name, product.key, tostring(message)))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	-- 付与を記録して即セーブ。セーブできなければ未処理扱いにして再送を待つ
	table.insert(profile.PurchaseHistory, receipt.PurchaseId)
	local saved = SavePlayer and SavePlayer:Invoke(player)
	if not saved then
		-- 記録はメモリに残したまま未処理を返す。
		-- ・この後の自動セーブで「付与」と「記録」が一緒に保存される → 再送時は付与済み扱い
		-- ・どちらも保存されずに退出した場合は両方消える → 再送時にもう一度付与（二重にはならない）
		warn(("[MonetizationManager] %s の購入をセーブできませんでした（再送待ち）"):format(player.Name))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	PurchaseResultEvent:FireClient(player, true, message)
	print(("[MonetizationManager] %s に %s を付与: %s"):format(player.Name, product.name, message))
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

print("[MonetizationManager] 課金システムを起動しました。")
