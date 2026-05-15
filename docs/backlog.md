# Roblox 消火器プロジェクト バックログ

## 2026/5/14のタスク
- [x] Roblox Studioで消火器モデルをインポート
- [x] Roblox Assistantを使って、パーツ群を `Handle` へ一括Weld（溶接）
- [x] Toolオブジェクト化して、アバターが手に持てるかテストプレイで確認

![alt text](images/image-1.png)

## 2026/5/16のタスク
- [x] Blender Pythonスクリプトで消火器モデルを自動生成（タンク・レバー・ホース・圧力計）
- [x] マテリアルキャッシュ破棄＋赤/黒/銀/黄マテリアルの新規作成・割当
- [x] ホースをレバー反対側へ、圧力ゲージを横配置へ位置調整
- [x] `auto_uv_palette_mapping.py` で256色パレットへのUV自動配置
- [x] 生成スクリプトを `assets/blender/scripts/fire_extingisher/` に整理
- [x] `docs/roblox_manual.md` に Blender→FBX エクスポート手順を追記・全体統合
- [x] `palette_256.png` で4色パレットテクスチャを作成
- [x] `fire_extingisher.blend` / `.fbx` を `assets/models/` にエクスポート