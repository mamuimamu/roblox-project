# Roblox ✕ Cursor ✕ Rojo 開発環境構築マニュアル

本書は、Cursor (IDE) から Rojo を用いて Roblox Studio へコードをリアルタイム同期し、かつ Git によるバージョン管理と 3 層アーキテクチャ（Client / Server / Shared）の一元管理を実現するための環境構築手順書である。

---

## 1. 前提条件とディレクトリ構造

### 1.1 前提とするディレクトリ構造 (Monorepo)
既存の資産（Blender スクリプト、技術ドキュメント）を破壊せず、同一リポジトリ内でコードを管理するため、以下の構造のルート直下に Rojo を展開する。

```text
roblox-project/
 ├── .gitignore               # Git除外設定
 ├── README.md                # プロジェクト概要
 ├── default.project.json     # Rojo設計図（新規作成）
 ├── lobby.project.json       # マルチプレース運用時の設計図（例）
 ├── rojo.exe                 # Rojo本体バイナリ（手動配置・Git除外）
 ├── roblox-project.code-workspace
 ├── assets/                  # Blenderスクリプト・3Dモデル・テクスチャ
 ├── docs/                    # 各種マニュアル・バックログ（Markdown）
 └── src/                     # Roblox Luaソースコード基盤
      ├── Client/             # クライアント側スクリプト（StarterPlayerScriptsへ同期）
      ├── Server/             # サーバー側スクリプト（ServerScriptServiceへ同期）
      └── Shared/             # 共通スクリプト（ReplicatedStorageへ同期）
```

---

## 2. 環境構築手順 (Setup Steps)

### Step 1: Rojo 本体 (v7.6.1) の配置
Roblox Studio 側の公式プラグインのプロトコルバージョン（v4）と一致させるため、安定版である **v7.6.1** の実行ファイルをローカルに直接デプロイする。

1. [Rojo v7.6.1 Releases](https://github.com/rojo-rbx/rojo/releases/tag/v7.6.1) から `rojo-v7.6.1-windows-x86_64.zip` をダウンロードする。
2. 解凍して抽出された `rojo.exe` を、リポジトリのルート（`roblox-project/` 直下）に配置する。

### Step 2: Git 除外設定の追加
不要なバイナリファイルが GitHub にプッシュされるのを防ぐため、`.gitignore` の最下部に以下を追記する。

```text
# Rojo Executable Binary
rojo.exe
```

### Step 3: Rojo 設計図 (`default.project.json`) の作成
リポジトリのルート直下に `default.project.json` を新規作成し、既存の3層構造（`src/` 配下）を Roblox の DataModel へ正確にマッピングする定義を記述する。
※Rojoプラグイン（Studio側）に表示されるプロジェクト名は、このJSON内の `"name"` キーの値が自動反映される。

```json
{
  "name": "MyRescueGame",
  "tree": {
    "$className": "DataModel",

    "ReplicatedStorage": {
      "Shared": {
        "$path": "src/Shared"
      }
    },

    "ServerScriptService": {
      "Server": {
        "$path": "src/Server"
      }
    },

    "StarterPlayer": {
      "StarterPlayerScripts": {
        "Client": {
          "$path": "src/Client"
        }
      }
    }
  }
}
```

### Step 4: Roblox Studio へのプラグインインストール
1. Roblox Studio を起動し、対象のプレース（Baseplate 等）を開く。
2. **「ツールボックス (Toolbox)」** を開き、カテゴリを **「プラグイン (Plugins)」** に切り替える。
3. `rojo` で検索し、公式の **「Rojo (無料、v7.6.1 互換)」** をインストールする。

---

## 3. 開発ワークフローと運用 (Workflow)

### 3.1 同期サーバーの起動
Cursor のターミナルを開き、リポジトリルートにて以下のコマンドを実行する。

```bash
./rojo serve
```
* **正常起動時ログ:** `Rojo server listening: Address: localhost Port: 34872`

### 3.2 Roblox Studio との接続 (Connect)
1. Roblox Studio の **「プラグイン (Plugins)」** タブから Rojo アイコンをクリックする。
2. 開いたダイアログの **「Connect」** ボタンを押下する。
3. エクスプローラー上に `Server`, `Client`, `Shared` がマッピングされれば開通。

### 3.3 スクリプト作成ルール
Rojo はファイル名のサフィックス（拡張子の前の識別子）を識別して Roblox 上のクラスを決定する。

| ローカルファイル名 | Roblox上のクラス | 同期先フォルダ (推奨) | 実行環境 |
| :--- | :--- | :--- | :--- |
| `*.server.lua` | `Script` | `src/Server/` | サーバー (Server) |
| `*.client.lua` | `LocalScript` | `src/Client/` | クライアント (Client) |
| `*.lua` | `ModuleScript` | `src/Shared/` | 双方から呼び出し可能 |

---

## 4. 設計思想：JSONによるマルチプレース制御 (IaC)

Rojoの設計図（`.project.json`）は、**「1つのJSONファイル ＝ 1つのRobloxプレース」**としてマッピングを制御（Infrastructure as Code）している。将来的に「本編ステージ」「ロビープレース」など、複数のプレースを単一リポジトリ（Monorepo）で管理・送り分けたい場合は、以下の2つのアプローチでスケールさせる。

### アプローチA：設計図（JSON）を複数用意して叩き分ける（推奨）
共通の `src/Shared` 資産を活かしつつ、プレースごとに同期するサーバー・クライアントロジックをJSON側で切り替える運用。

* **`default.project.json`（本編用）** ➔ `src/Server` をマッピング
* **`lobby.project.json`（ロビー用）** ➔ `src/LobbyServer` をマッピング

**【コマンドによる叩き分け】**
指定なしで起動した場合は `default.project.json` が読み込まれるが、別プレースと接続する場合は引数で明示的にターゲットのJSONを指定してサーバーを起動する。

```bash
# ロビー用の同期サーバーを起動する場合
./rojo serve lobby.project.json
```

### アプローチB：src配下をプレースごとにディレクトリ分割する
`src/` のルート直下をプレース名で物理的に分離し、共通アセットとプレース固有ロジックの依存関係を明確にするアプローチ。

```text
src/
 ├── Shared/         # 全プレース共通のライブラリや定数データ
 ├── Place_Main/     # 本編専用の Client / Server スクリプト
 └── Place_Lobby/    # ロビー専用の Client / Server スクリプト
```
この場合も、それぞれのプレース用JSONファイルから対象のパス（`"$path": "src/Place_Main/Server"` など）へルーティングを設定して制御する。

---

## 5. 疎通確認用テストコード

環境が正常に同期しているかを検証するためのミニマムコード。

### 5.1 `src/Shared/Config.lua` (定数・設定管理用)
```lua
local Config = {
    GameName = "Rescue Hero Project",
    Version = "1.0.0"
}
return Config
```

### 5.2 `src/Server/init.server.lua` (初期化ロジック)
```lua
print("[Server] 救助ゲームシステムが起動しました。")

local SharedModule = require(game:GetService("ReplicatedStorage").Shared:WaitForChild("Config"))
print("[Server] 共通設定を読み込みました。ゲーム名: " .. SharedModule.GameName)
```

---
**作成日:** 2026年5月20日  
**ステータス:** 構築完了・疎通確認済