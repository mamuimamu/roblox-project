# Roblox Studio × Claude Code（Cursor）をMCPで繋いでAI駆動開発する方法

## はじめに

Roblox Studio でゲーム開発をするとき、スクリプトを書く→コピペ→Studio で貼り付け→テスト、というサイクルが地味に面倒ですよね。

この記事では **Roblox Studio の公式 MCP（Model Context Protocol）サーバー**を使って、**Claude Code（Cursor）から直接 Studio へスクリプトを反映する**環境の構築手順をまとめます。

セットアップが完了すると次のことが AI（Claude）から直接できるようになります。

- Roblox Studio 内の Workspace・ServerStorage などをスキャンしてツリー構造を取得
- Luau スクリプトを Studio のサービス（ServerScriptService・StarterPlayerScripts など）へ書き込み
- スクリプトの実行結果（`print` の出力）をエディタ側で受け取る

---

## 必要なもの

| ツール | 備考 |
|---|---|
| Roblox Studio | 最新版（StudioMCP.exe が同梱） |
| Claude Code CLI | `npm install -g @anthropic-ai/claude-code` |
| Cursor または VS Code | Claude Code 拡張が使えれば OK |
| Windows 10/11 | mcp.bat を使う都合上 Windows 前提（Mac は exe パスが異なる） |

---

## 仕組みの概要

```
[Cursor / Claude Code]
        ↕ MCP（stdio）
[StudioMCP.exe]  ← Roblox Studio に同梱されたバイナリ
        ↕ WebSocket（ws://127.0.0.1:13469/proxy）
[Roblox Studio]
```

Roblox Studio には `StudioMCP.exe` という MCP サーバーが同梱されています。このバイナリが stdio で MCP プロトコルを受け取り、WebSocket 経由で Studio のプラグインと通信します。Claude Code はこの MCP サーバーに接続することで、Studio 内の Luau コードを実行したり、スクリプトオブジェクトを生成・更新したりできます。

---

## セットアップ手順

### 1. StudioMCP.exe の場所を確認する

Roblox Studio をインストールすると `%LOCALAPPDATA%\Roblox\Versions\version-XXXXXXXX\` 以下に `StudioMCP.exe` が配置されます。

```powershell
Get-ChildItem "$env:LOCALAPPDATA\Roblox\Versions" -Recurse -Filter "StudioMCP.exe"
```

見つかれば OK です。

### 2. mcp.bat を確認する

Roblox Studio は `%LOCALAPPDATA%\Roblox\mcp.bat` も自動生成します。このバッチは常に最新バージョンの `StudioMCP.exe` を探して起動するラッパーです。

```powershell
Get-Content "$env:LOCALAPPDATA\Roblox\mcp.bat"
```

出力例：
```bat
@echo off
if exist "C:\Users\ユーザー名\AppData\Local\Roblox\Versions\version-XXXXXXXX\StudioMCP.exe" (
  "C:\Users\ユーザー名\AppData\Local\Roblox\Versions\version-XXXXXXXX\StudioMCP.exe" %*
) else (
  for /f "tokens=2*" %%A in ('reg query HKEY_CURRENT_USER\Software\Roblox\RobloxStudio /v ContentFolder') do (
    "%%B\..\StudioMCP.exe" %*
  )
)
```

### 3. Claude Code に MCP サーバーを登録する

プロジェクトディレクトリで以下を実行します。

```powershell
claude mcp add --transport stdio Roblox_Studio -- `
  "cmd.exe" "/c" "$env:LOCALAPPDATA\Roblox\mcp.bat"
```

登録確認：

```powershell
claude mcp list
```

`Roblox_Studio` が一覧に表示されれば完了です。

### 4. Roblox Studio を開いて MCP プラグインを有効にする

Studio 側でも MCP の受け口（WebSocket サーバー）を起動する必要があります。

1. Roblox Studio を起動
2. メニュー → **プラグイン** タブを確認
3. Studio の **設定 → セキュリティ** で「Studio へのアクセスを許可するローカルポート」が有効になっていることを確認

> **ポイント**: Studio を起動していない状態で MCP ツールを呼んでもタイムアウトします。必ず Studio を先に開いておいてください。

### 5. 接続テスト

Claude Code のチャットで以下のように指示します。

```
Roblox Studio に接続して print("Hello from Claude!") を実行してください
```

Studio の Output に `Hello from Claude!` が表示されれば成功です。

---

## 実際の開発ワークフロー

### ディレクトリ構成

```
roblox-project/
├── src/
│   ├── Server/
│   │   ├── init.server.lua
│   │   ├── FireManager.server.lua
│   │   └── ...
│   ├── Client/
│   │   ├── ExtinguisherController.client.lua
│   │   └── ...
│   └── Shared/
│       ├── Config.lua
│       └── ...
├── push_to_studio.ps1   ← Studio へ一括反映するスクリプト
├── scan_studio.ps1      ← Studio の構造をスキャンするスクリプト
└── CLAUDE.md            ← Claude への指示書
```

### push_to_studio.ps1 の仕組み

Claude の stdio MCP クライアント（StudioMCP.exe 経由）をバイパスして、その先にある WebSocket エンドポイント（`ws://127.0.0.1:13469/proxy`）に PowerShell から直接接続して Luau を実行するスクリプトです。プロトコル形式は MCP と同じ JSON-RPC をそのまま使っています。

この設計にした理由は、ファイルを10本以上まとめて push するユースケースに合わせるためです。Claude の MCP ツール呼び出しは「考える→ツール実行→結果確認→また考える」のループを1回ずつ回すため、ファイル数分だけトークンと時間を消費します。PowerShell スクリプトに全ファイルを列挙しておけば、Claude から `.\push_to_studio.ps1` を1回実行するだけで確定的に全ファイルを push でき、Claude を介さずに単独実行することもできます。

```powershell
# WebSocket 接続
$ws = New-Object System.Net.WebSockets.ClientWebSocket
$ws.ConnectAsync([Uri]"ws://127.0.0.1:13469/proxy",
  [System.Threading.CancellationToken]::None).Wait(5000) | Out-Null

# JSON-RPC で Luau を実行
function Invoke-RunCode([string]$lua) {
    WsSend @{
        type    = "json_rpc"; jsonrpc = "2.0"; id = "$($script:msgId)"
        method  = "tools/call"
        params  = @{ name = "execute_luau"; arguments = @{ code = $lua } }
    }
    # ... レスポンスを受け取る
}
```

スクリプトの中身は「Luau コードで Studio の Instance を操作する」だけです。例えばファイルをプッシュする部分はこうなっています。

```powershell
function Push-LuaFile([string]$path, [string]$parentLua, [string]$name, [string]$cls) {
    $src = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
    $lua = @"
local hs = game:GetService("HttpService")
local arr = hs:JSONDecode('$esc')   -- ファイル内容をエスケープして埋め込み
local src = arr[1]
local p = $parentLua
local e = p:FindFirstChild("$name"); if e then e:Destroy() end
local s = Instance.new("$cls"); s.Name = "$name"; s.Source = src; s.Parent = p
print("OK:$name")
"@
    Invoke-RunCode $lua
}
```

`Instance.new("Script")` / `Instance.new("LocalScript")` / `Instance.new("ModuleScript")` を動的に生成して `Source` プロパティにコードを書き込んでいます。

### スクリプトを反映する流れ

1. Claude Code で Luau スクリプトを編集・生成してもらう
2. Claude に `push_to_studio.ps1 を実行して` と指示する
3. Studio の Output に `OK:スクリプト名` が並んで反映完了
4. Studio でテストプレイして動作確認

---

## CLAUDE.md でワークフローを自動化する

プロジェクトルートに `CLAUDE.md` を置くことで Claude への恒久的な指示を書けます。

```markdown
# プロジェクトの概要
- Roblox ○○ゲーム開発

## 遵守事項
- ROBLOX Studio にスクリプトをpushする前には許可をとること
- ROBLOX Studio へのスクリプト反映は "push_to_studio.ps1" を使うこと
- スクリプト編集後は毎回 push するか確認すること
- ソースコードには適切なコメントを日本語で記載すること
```

これにより「実装して」と指示するだけで、コード生成→push 確認→反映というサイクルが自然に回ります。

---

## ハマりどころと対処法

### よくあるエラーと解決策

#### `Failed to connect` / タイムアウト

**原因**: Roblox Studio が起動していないか、MCP プラグインが無効

**対処**:
1. Studio を起動（ゲームを開いた状態でないと WebSocket サーバーが立ち上がらない場合がある）
2. Studio の Output を確認（MCP サーバーのログが出る）
3. ファイアウォールで 13469 ポートがブロックされていないか確認

#### `control` メッセージが先に来る問題

WebSocket のレスポンスとして `tools_updated` などの control メッセージが JSON-RPC レスポンスより先に届くことがあります。ループで読み飛ばすのがコツです。

```powershell
$r = WsRecv 20000
while ($r -and $r.type -eq "control") {
    Write-Host "  [control: $($r.control_type)]"
    $r = WsRecv 10000  # 読み飛ばして次を待つ
}
```

#### `CancellationToken` で WebSocket が Aborted になる

タイムアウト時に新しい `CancellationToken` を渡すと WebSocket ソケットが `Aborted` 状態になり、以降の通信が全滅します。

**対処**: pending な Task を保持しておき、次の受信時に再利用する。

```powershell
# タイムアウトしたタスクを保持して再利用
$script:pendingRecvTask = $null
$script:pendingRecvBuf  = $null

function WsRecv([int]$ms = 15000) {
    $mem = New-Object System.IO.MemoryStream
    do {
        if ($null -ne $script:pendingRecvTask) {
            # タイムアウトした前回のタスクを再利用
            $t   = $script:pendingRecvTask
            $buf = $script:pendingRecvBuf
            $script:pendingRecvTask = $null
            $script:pendingRecvBuf  = $null
        } else {
            $buf = [byte[]]::new(65536)
            $seg = [ArraySegment[byte]]::new($buf)
            $t   = $ws.ReceiveAsync($seg, [System.Threading.CancellationToken]::None)
        }
        if (-not $t.Wait($ms)) {
            # タイムアウト：タスクを保持して次回に回す
            $script:pendingRecvTask = $t
            $script:pendingRecvBuf  = $buf
            return $null
        }
        # ...
    } while ($true)
}
```

#### Luau 内に `'`（シングルクォート）が含まれると壊れる

Luau コードを PowerShell の文字列に埋め込む際、シングルクォートがエスケープされず構文エラーになります。

**対処**: `ConvertTo-Json` で一度 JSON 文字列にしてから `HttpService:JSONDecode` で戻す。

```powershell
$srcJson = $src | ConvertTo-Json -Compress   # " は \" にエスケープされる
$arr     = "[$srcJson]"
$esc     = $arr.Replace("\","\\").Replace("'","\'")   # \ と ' を追加エスケープ

$lua = "local arr=hs:JSONDecode('$esc'); local src=arr[1]"
```

---

## Studio スキャンで構造を把握する

開発中に Studio の現状をエディタ側で把握したいときは、以下のような Luau をオンデマンドで実行できます。

```lua
-- Workspace の階層を深さ3まで出力
local results = {}
local function scan(obj, depth)
    if depth > 3 then return end
    local indent = string.rep("  ", depth)
    table.insert(results, indent .. obj.Name .. " [" .. obj.ClassName .. "]")
    for _, child in ipairs(obj:GetChildren()) do
        scan(child, depth + 1)
    end
end
for _, child in ipairs(game:GetService("Workspace"):GetChildren()) do
    scan(child, 0)
end
return table.concat(results, "\n")
```

Claude に「Studio の現在の構造を教えて」と聞くと、この種の Luau を実行して返してくれます。

---

## Tips：Cursor での使い方

Claude Code は CLI ですが、Cursor の AI チャットから `claude` CLI を呼ぶより、**Claude Code の VSCode/Cursor 拡張**を使うのが便利です。

1. Cursor の拡張機能マーケットプレイスで **Claude Code** を検索してインストール
2. `Ctrl+Shift+P` → `Claude Code: Open` で起動
3. チャットパネルに Studio とのやり取りを指示する

拡張経由だと、ファイルの差分を自動で検知して「このファイルを Studio に反映しますか？」といった文脈のある会話ができます。

---

## まとめ

| やること | コマンド / ファイル |
|---|---|
| MCP サーバー登録 | `claude mcp add --transport stdio Roblox_Studio -- cmd.exe /c mcp.bat` |
| 接続テスト | チャットで「print テストして」 |
| スクリプト反映 | `push_to_studio.ps1` を実行 |
| Studio 構造スキャン | `scan_studio.ps1` を実行 |
| ワークフロー定義 | `CLAUDE.md` に記述 |

Roblox の MCP は公式バイナリが同梱されているので、セットアップはほぼ「登録するだけ」です。一番のコツは **`CLAUDE.md` に push のルールを書いておくこと** で、「書いたら必ず push 確認する」というサイクルが自然に定着します。

AI と Studio を繋ぐと、Luau の文法を都度調べなくても「○○する仕組みを作って」という指示だけで動くコードが出てくるので、ゲームの発想と実装のサイクルがかなり速くなりました。参考になれば嬉しいです。

---

## 参考リンク

- [Roblox Studio MCP 公式ドキュメント](https://create.roblox.com/docs)
- [Claude Code ドキュメント](https://docs.anthropic.com/claude-code)
- [Model Context Protocol（MCP）仕様](https://modelcontextprotocol.io)
