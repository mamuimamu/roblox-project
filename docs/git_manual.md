# 🚀 今村さん専用：GitHub・Git Bash操作マニュアル

新しくリポジトリを作ったときの「クローン（初回のみ）」の手順と、日々の開発成果を保存する「コミット＆プッシュ（毎回）」の手順です。

---

## 1. 初回のみ：GitHubからPCへクローン（ダウンロード）する手順

GitHub（ウェブサイト）でリポジトリを作成した直後に、PCにフォルダを引っ張ってくる手順です。

### 1-1. パスの確認と移動
Git Bashを開き、Windowsのフォルダ（例：C:\Users\kr_im\Development）へ移動します。
※Git Bashではスラッシュ / を使い、ドライブ名は /c/ と書くのがルールです。
※ディレクトリをドラッグアンドドロップでもOK

【実行するコマンド】
cd /c/Users/kr_im/Development
【ここまで】

### 1-2. クローンを実行
GitHubのウェブ画面でコピーしたURLを使って、PCにフォルダを自動生成します。

【実行するコマンド】
git clone https://github.com/ユーザー名/my-roblox-project.git
【ここまで】

### 1-3. 生成されたフォルダ内へ移動
クローンが終わったら、作業を始めるために必ずそのフォルダの中に入ります。

【実行するコマンド】
cd roblox-project
【ここまで】

---

## 2. フォルダ階層の作成（今回の環境構築時のみ）
リポジトリ内に、CursorやRoblox AIが迷わないための標準フォルダを一括作成します。

【実行するコマンド】
mkdir -p assets/blender/scripts assets/textures src/Client src/Server src/Shared docs
touch assets/blender/scripts/.gitkeep assets/textures/.gitkeep src/Client/.gitkeep src/Server/.gitkeep src/Shared/.gitkeep
【ここまで】

---

## 3. 日々の作業時：変更をGitHubに保存（Push）する手順 【超重要】

Blenderでモデルを作ったり、Roblox StudioでWeldの設定をしたり、Cursorでスクリプトを書いた後、「今日の成果をGitHubにバックアップする」ための毎回行う手順です。

必ずリポジトリのルートフォルダ（my-roblox-project）にいる状態で実行します。

### 🔄 黄金の3ステップ（Add ➔ Commit ➔ Push）

#### ① 変更されたファイルをすべてステージング（荷造り）する
PC側で追加・修正したファイルすべてを「今からアップロードするリスト」に登録します。
（最後の「 . 」はすべてのファイルという意味です）

【実行するコマンド】
git add .
【ここまで】

#### ② コミット（セーブデータの作成）
何を変更したかをメッセージ（メモ）として残し、ローカルPC内にセーブデータを作ります。
※SEPG（プロセス改善）の視点からも、メッセージは具体的（feat: や chore: など）に書くのがベストプラクティスです。

【実行するコマンド】
git commit -m "feat: 消火器モデルをインポートしHandleへのWeld自動化を完了"
【ここまで】

#### ③ プッシュ（GitHubへの送信・同期）
PC内のセーブデータを、インターネット上のGitHub（リモート）へ送信して同期させます。

【実行するコマンド】
git push origin main
【ここまで】

---

## 🛠 困ったときの便利コマンド

### 現在の状態を確認する
「今、どのファイルが変更されているか？」「addし忘れているファイルはないか？」を確認できます。作業の区切りに叩くと安心です。

【実行するコマンド】
git status
【ここまで】

### 過去のセーブ履歴を見る
これまでどんなコミット（セーブ）をしてきたかの履歴を一覧表示します。

【実行するコマンド】
git log --oneline
【ここまで】