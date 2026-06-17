---
title: "Robloxゲームにセーブ機能を実装した話——DataStoreService有効化のハマりどころ含め"
emoji: "💾"
type: "tech"
topics: ["roblox", "lua", "gamedev", "ai", "claude"]
published: false
---

# Robloxゲームにセーブ機能を実装した話

## 「ゲームを閉じたら進行状況がリセットされる問題」

消火ゲームを作り続けていて、ある問題に気づきました。

ゲームをプレイしてウェーブ5まで進めても、ゲームを閉じて再度開くと**ウェーブ1からやり直し**になる。消防車を買っても次のセッションでは消えている。せっかくポイントを稼いでも記録されない。

これは遊んでいてつらい。というわけで、**セーブ機能（データ永続化）** を実装することにしました。

この記事では、RobloxのDataStoreServiceを使ったセーブ機能の実装手順と、**実際にハマったポイント**を紹介します。

---

## 保存したいデータ

今回保存対象にしたデータは以下の6項目です。

| データ名 | 説明 |
|---------|------|
| `Fires` | 消火した件数（リーダーボード表示） |
| `Points` | 獲得ポイント（ショップで使用） |
| `Wave` | 到達ウェーブ番号 |
| `VehiclePurchased` | 消防車の購入フラグ |
| `ActiveWaterBoost` | 消火強化パワーアップ中かどうか |
| `ActiveSpeedBoost` | スピードブースト中かどうか |

---

## DataStoreServiceとは

Robloxには**DataStoreService**という、プレイヤーごとにデータをクラウドに保存できるAPIが標準で用意されています。

```lua
local DataStoreService = game:GetService("DataStoreService")
local PlayerDataStore = DataStoreService:GetDataStore("PlayerData_v1")
```

`GetDataStore("名前")` でストアを取得し、`SetAsync` / `GetAsync` でデータを読み書きします。キーにはプレイヤーのUserId（数値ID）を使うのが定番です。

```lua
-- 保存
PlayerDataStore:SetAsync("player_" .. player.UserId, data)

-- 読み込み
local data = PlayerDataStore:GetAsync("player_" .. player.UserId)
```

シンプルに見えますが、最初の壁がすぐやってきます。

---

## ハマりポイント①：Studio内でテストしてもデータが保存されない

実装して「よしテストしよう」とRoblox Studioでプレイテストを実行したら、保存も読み込みも一切動きません。エラーはこんな感じ：

```
DataStore request was added to queue. If request queue fills, further requests will be dropped. Try sending fewer requests.
```

あるいは単純に `GetAsync` が `nil` を返し続ける。

**原因：Studio内でのAPI アクセスがデフォルトで無効になっている**

Roblox Studioは本番サーバーとは独立した環境で動いています。DataStoreServiceのような外部API呼び出しは、明示的に許可しないとStudio内では使えません。

### 解決方法

1. Roblox Studioのメニューバーから **「Home」タブ → 「Game Settings」** を開く
2. 左メニューの **「Security」** をクリック
3. **「Enable Studio Access to API Services」** をオンにする

この設定を有効にしないと、**DataStoreServiceは完全に無音で失敗します**。エラーが出ないケースもあるので、気づくのに時間がかかりました。

:::message
この設定はゲームごとの設定で、新しいゲームを作るたびに設定が必要です。
:::

---

## ハマりポイント②：スクリプト間の実行順序

今回のゲームには複数のServerScriptがあります。

- `DataManager` : セーブ・ロードを担当
- `BurningHouseManager` : ウェーブ管理・ゲームロジック

問題は**「BurningHouseManagerがウェーブを開始する前に、DataManagerがロードを終えている保証がない」**ことです。

DataStoreServiceの `GetAsync` は非同期で、場合によっては数秒かかります。一方でBurningHouseManagerはプレイヤーが参加次第ウェーブを始めようとします。順番が狂うと、**セーブデータが反映される前にウェーブ1が始まってしまいます**。

### 解決策：IntValueをシグナルとして使う

DataManagerがロード完了後に `LoadedWave` という IntValue を ServerStorage に作成します。

```lua
-- DataManager.server.lua
local function createLoadedWave(wave)
    local lw = Instance.new("IntValue")
    lw.Name   = "LoadedWave"
    lw.Value  = wave
    lw.Parent = ServerStorage
end

-- GetAsync完了後に即座に呼ぶ
local ok, data = pcall(function()
    return PlayerDataStore:GetAsync("player_" .. player.UserId)
end)
local savedWave = (ok and data) and data.Wave or 1
createLoadedWave(savedWave)  -- ← ここが「ロード完了」のシグナル
```

BurningHouseManagerはこの IntValue が現れるまで待ちます。

```lua
-- BurningHouseManager.server.lua
-- DataManagerがロード完了後に作成するLoadedWaveを待つ（最大5秒）
local loadedWaveValue = ServerStorage:WaitForChild("LoadedWave", 5)
if loadedWaveValue then
    startWave = math.max(1, loadedWaveValue.Value)
    print(("保存済みウェーブ: %d から開始"):format(startWave))
else
    warn("LoadedWaveの取得タイムアウト。Wave 1 から開始します。")
end
```

`WaitForChild` にタイムアウト（5秒）を設けているのがポイントで、DataManagerが何らかの理由で失敗してもゲームが完全に止まらないようにしています。

---

## ハマりポイント③：leaderstatsを先に待つと10秒ラグが発生した

最初の実装では「leaderstatsが準備できてからデータをロードしよう」という順番で書いていました：

```lua
-- ❌ 悪い例：leaderstatsを先に待ってから GetAsync する
local leaderstats = player:WaitForChild("leaderstats", 10)
local data = PlayerDataStore:GetAsync("player_" .. player.UserId)
leaderstats.Fires.Value = data.Fires
```

これだと `leaderstats` の待機（最大10秒） → `GetAsync`（1〜2秒）の順になり、**ゲーム開始から10秒以上データが反映されない**という問題が発生しました。

### 解決策：GetAsyncを先に実行する

GetAsyncとleaderstats生成は並行して進められます。順番を入れ替えました。

```lua
-- ✅ 良い例：先にGetAsyncを実行し、leaderstatsは後から待つ
local ok, data = pcall(function()
    return PlayerDataStore:GetAsync("player_" .. player.UserId)
end)

-- ウェーブ番号・フラグ類は即座にServerStorageに書き込む（BurningHouseManagerが参照）
createLoadedWave(savedWave)
setStorageBool("VehiclePurchased", savedVehicle)

-- Fires・Points はleaderstatsに直接書く必要があるので後から待つ
local leaderstats = player:WaitForChild("leaderstats", 10)
if leaderstats then
    leaderstats.Fires.Value  = savedFires
    leaderstats.Points.Value = savedPoints
end
```

ウェーブ番号やフラグ類は `ServerStorage` の Value オブジェクトに書けばよいので、leaderstatsを待たずに済みます。leaderstatsへの書き込みが必要なのはポイントと消火件数だけ、と整理できました。

---

## セーブのタイミング

セーブは以下の3つのタイミングで行っています。

### 1. プレイヤーが退出したとき

```lua
Players.PlayerRemoving:Connect(function(player)
    savePlayerData(player)
end)
```

### 2. サーバーがシャットダウンするとき

```lua
game:BindToClose(function()
    saveAllPlayers()
end)
```

### 3. ウェーブクリア時（自動セーブ）

ウェーブを全消火したタイミングでもセーブします。これが一番大事で、プレイヤーが途中でゲームを閉じても直前のウェーブ進行状況が残るようになります。

```lua
-- BurningHouseManager.server.lua
if allExtinguished() and not isWaveTransitioning then
    -- ウェーブクリア時に自動セーブ
    local saveBindable = ServerStorage:FindFirstChild("SaveAllPlayers")
    if saveBindable then
        task.spawn(function() saveBindable:Invoke() end)
    end
end
```

「SaveAllPlayers」という BindableFunction を DataManager が作成しており、他のスクリプトから `Invoke()` で呼び出す仕組みです。

---

## スクリプト間通信の設計

今回の実装でのスクリプト間のデータの流れをまとめると以下のようになります。

```
DataManager (ロード完了)
    │
    ├──→ ServerStorage.LoadedWave      (IntValue)   ←── BurningHouseManager が WaitForChild
    ├──→ ServerStorage.VehiclePurchased (BoolValue)
    ├──→ ServerStorage.ActiveWaterBoost (BoolValue)
    └──→ ServerStorage.ActiveSpeedBoost (BoolValue)

BurningHouseManager (ゲーム進行中)
    │
    ├──→ ServerStorage.CurrentWave     (IntValue)   ←── DataManager がセーブ時に参照
    ├──→ ServerStorage.VehiclePurchased (更新)
    └──→ ServerStorage.ActiveWaterBoost / ActiveSpeedBoost (更新)

DataManager (セーブ時)
    │
    └──→ DataStoreService.SetAsync ← 上記の全Valueを読んで保存
```

`ServerStorage` をスクリプト間の「共有黒板」として使い、直接関数を呼び合うのではなく値の読み書きで連携しています。

---

## 最終的なDataManagerのコード全体

```lua
--[[
    DataManager（Server / Script）
    プレイヤーデータの永続セーブ／ロードを担う。
]]

local DataStoreService = game:GetService("DataStoreService")
local Players          = game:GetService("Players")
local ServerStorage    = game:GetService("ServerStorage")

local PlayerDataStore = DataStoreService:GetDataStore("PlayerData_v1")

local function setStorageBool(name, value)
    local existing = ServerStorage:FindFirstChild(name)
    if existing then
        existing.Value = value
    else
        local bv = Instance.new("BoolValue")
        bv.Name   = name
        bv.Value  = value
        bv.Parent = ServerStorage
    end
end

local function savePlayerData(player)
    local leaderstats = player:FindFirstChild("leaderstats")
    if not leaderstats then return end

    local cwVal  = ServerStorage:FindFirstChild("CurrentWave")
    local vpVal  = ServerStorage:FindFirstChild("VehiclePurchased")
    local awVal  = ServerStorage:FindFirstChild("ActiveWaterBoost")
    local asVal  = ServerStorage:FindFirstChild("ActiveSpeedBoost")

    local data = {
        Fires            = leaderstats.Fires.Value,
        Points           = leaderstats.Points.Value,
        Wave             = cwVal  and cwVal.Value  or 1,
        VehiclePurchased = vpVal  and vpVal.Value  or false,
        ActiveWaterBoost = awVal  and awVal.Value  or false,
        ActiveSpeedBoost = asVal  and asVal.Value  or false,
    }

    local ok, err = pcall(function()
        PlayerDataStore:SetAsync("player_" .. player.UserId, data)
    end)

    if ok then
        print(("[DataManager] %s をセーブ"):format(player.Name))
    else
        warn(("[DataManager] セーブ失敗: %s"):format(tostring(err)))
    end
end

local function loadPlayerData(player)
    -- ① 先にGetAsyncを実行（leaderstats待機の前に）
    local ok, data = pcall(function()
        return PlayerDataStore:GetAsync("player_" .. player.UserId)
    end)

    local savedWave, savedFires, savedPoints = 1, 0, 0
    local savedVehicle, savedWaterBoost, savedSpeedBoost = false, false, false

    if ok and data then
        savedWave       = data.Wave             or 1
        savedFires      = data.Fires            or 0
        savedPoints     = data.Points           or 0
        savedVehicle    = data.VehiclePurchased  or false
        savedWaterBoost = data.ActiveWaterBoost  or false
        savedSpeedBoost = data.ActiveSpeedBoost  or false
    end

    -- ② ウェーブ番号・フラグをServerStorageへ即座に通知
    local lw = Instance.new("IntValue")
    lw.Name = "LoadedWave"; lw.Value = savedWave; lw.Parent = ServerStorage

    setStorageBool("VehiclePurchased",  savedVehicle)
    setStorageBool("ActiveWaterBoost",  savedWaterBoost)
    setStorageBool("ActiveSpeedBoost",  savedSpeedBoost)

    -- ③ Fires/Pointsはleaderstatsができてから反映
    local leaderstats = player:WaitForChild("leaderstats", 10)
    if leaderstats then
        leaderstats.Fires.Value  = savedFires
        leaderstats.Points.Value = savedPoints
    end
end

-- 他スクリプトから呼び出せるセーブ用BindableFunction
local SaveAllBindable = Instance.new("BindableFunction")
SaveAllBindable.Name     = "SaveAllPlayers"
SaveAllBindable.Parent   = ServerStorage
SaveAllBindable.OnInvoke = function()
    for _, player in Players:GetPlayers() do
        savePlayerData(player)
    end
end

Players.PlayerAdded:Connect(function(player)
    task.spawn(loadPlayerData, player)
end)

Players.PlayerRemoving:Connect(function(player)
    savePlayerData(player)
end)

game:BindToClose(function()
    for _, player in Players:GetPlayers() do
        savePlayerData(player)
    end
end)
```

---

## まとめ：ハマったポイント一覧

| # | ハマりポイント | 解決策 |
|---|-------------|--------|
| 1 | StudioでDataStoreが動かない | Game Settings > Security > Enable Studio Access to API Services をオン |
| 2 | ウェーブがデータより先に始まる | `LoadedWave` IntValueをシグナルとして使い、`WaitForChild` で待機 |
| 3 | データ反映まで10秒ラグ | `GetAsync` を先に実行し、leaderstatsへの書き込みは後回しにする |

特に①はドキュメントを読んでいれば分かることですが、エラーが無音で失敗するケースがあるので気づくのが遅れました。同じところでハマっている方の参考になれば幸いです。

---

## 使用した技術・ツール

- Roblox Studio
- Luau（Robloxのプログラミング言語）
- Claude（AIアシスタント） + Claude Code（CLI）
- MCP（Model Context Protocol）によるStudio連携

記事中のコードはAIと会話しながら設計・実装しました。「スクリプト間でどう連携させる？」という設計の相談から「このエラーの原因は？」というデバッグまで、AI込みで進めるとゲーム開発の試行錯誤がかなりやりやすくなりました。
