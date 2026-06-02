# Blender Python スクリプトで Roblox の Tool アイコンを自動生成する

## はじめに

Roblox Studio で Tool（武器・道具）を作ると、デフォルトではインベントリやホットバーのアイコンが**真っ白（空白）** のままになります。

アイコンを設定するには `Tool.TextureId` に画像の Asset ID を指定する必要がありますが、「どうやってアイコン画像を作るの？」という部分に意外と情報が少ないです。

この記事では、**Blender Python スクリプトを使ってワンクリックでアイコン用レンダリング画像を自動生成する方法**を紹介します。毎回手動でカメラをセットしてレンダリングする手間がなくなり、モデルを更新するたびに使い回せます。

---

## 環境

- Blender 3.x または 4.x（両方対応）
- Roblox Studio（任意のバージョン）
- Tool のモデルを含む `.blend` ファイル

---

## 完成イメージ

スクリプトを実行すると以下が自動で行われます。

1. シーン内のメッシュ全体を囲む AABB（バウンディングボックス）を計算
2. モデルを斜め上から映すカメラを自動配置
3. キー・フィル・リムの 3 点照明を自動設置
4. 解像度 420×420 px、**透明背景（PNG RGBA）** でレンダリング
5. 指定パスに PNG を保存

---

## なぜ 420×420 px か

Roblox の Tool アイコンは正方形で表示されます。公式の推奨サイズは明示されていませんが、**420×420 px** がコミュニティで広く使われており、ホットバー・インベントリともにきれいに表示されます。

---

## スクリプト全文

```python
"""
render_icon.py
Roblox Tool アイコン（420×420 PNG）を自動レンダリングする。

使い方:
  1. モデルの .blend ファイルを Blender で開く
  2. Scripting タブでこのファイルを読み込む
  3. ▶ Run Script を押す
"""

import bpy
import math
import os
from mathutils import Vector

# ── 設定 ─────────────────────────────────────────
OUTPUT_PATH   = "//../images/tool_icon.png"  # .blend からの相対パス
ICON_SIZE     = 420        # px
ELEV_DEG      = 20         # 仰角（度）
AZIMUTH_DEG   = 40         # 方位角（度）
CAMERA_DIST_F = 6.0        # モデル半径の何倍カメラを離すか
LENS_MM       = 85         # レンズ焦点距離（大きいほど歪みが少ない）
EEVEE_SAMPLES = 64

# ── モデル全体の AABB を取得 ──────────────────────
def get_model_bounds():
    inf = float('inf')
    mn = Vector(( inf,  inf,  inf))
    mx = Vector((-inf, -inf, -inf))
    found = False
    for obj in bpy.context.scene.objects:
        if obj.type != 'MESH':
            continue
        found = True
        for corner in obj.bound_box:
            wc = obj.matrix_world @ Vector(corner)
            mn.x = min(mn.x, wc.x);  mx.x = max(mx.x, wc.x)
            mn.y = min(mn.y, wc.y);  mx.y = max(mx.y, wc.y)
            mn.z = min(mn.z, wc.z);  mx.z = max(mx.z, wc.z)
    if not found:
        return Vector((0, 0, 0)), 1.0
    center = (mn + mx) / 2
    radius = max(mx.x - mn.x, mx.y - mn.y, mx.z - mn.z) / 2
    return center, max(radius, 0.01)

# ── カメラ配置 ────────────────────────────────────
def setup_camera(center, radius):
    for obj in list(bpy.data.objects):
        if obj.type == 'CAMERA':
            bpy.data.objects.remove(obj, do_unlink=True)

    dist = radius * CAMERA_DIST_F
    elev = math.radians(ELEV_DEG)
    azim = math.radians(AZIMUTH_DEG)

    cam_x = center.x + dist * math.cos(elev) * math.sin(azim)
    cam_y = center.y - dist * math.cos(elev) * math.cos(azim)
    cam_z = center.z + dist * math.sin(elev)

    cam_data             = bpy.data.cameras.new("IconCamera")
    cam_data.type        = 'PERSP'
    cam_data.lens        = LENS_MM
    cam_data.clip_start  = 0.01
    cam_data.clip_end    = 1000.0

    cam_obj              = bpy.data.objects.new("IconCamera", cam_data)
    bpy.context.scene.collection.objects.link(cam_obj)
    cam_obj.location     = Vector((cam_x, cam_y, cam_z))
    direction            = center - cam_obj.location
    cam_obj.rotation_euler = direction.to_track_quat('-Z', 'Y').to_euler()
    bpy.context.scene.camera = cam_obj

# ── 3 点照明 ──────────────────────────────────────
def setup_lights(center, radius):
    for obj in list(bpy.data.objects):
        if obj.type == 'LIGHT':
            bpy.data.objects.remove(obj, do_unlink=True)

    def add_point(name, offset, energy, color=(1.0, 1.0, 1.0)):
        ld = bpy.data.lights.new(name, type='POINT')
        ld.energy = energy
        ld.color  = color
        lo = bpy.data.objects.new(name, ld)
        bpy.context.scene.collection.objects.link(lo)
        lo.location = center + Vector(offset) * radius

    # キーライト（正面右上・温白色）
    add_point("KeyLight",  ( 2.5, -2.0,  3.5), radius * 700, (1.00, 0.97, 0.93))
    # フィルライト（正面左・青白色）
    add_point("FillLight", (-2.0, -1.5,  1.0), radius * 180, (0.80, 0.90, 1.00))
    # リムライト（背面・輪郭強調）
    add_point("RimLight",  (-0.5,  3.0,  2.5), radius * 350, (1.00, 1.00, 1.00))

    world = bpy.context.scene.world
    if world and world.node_tree:
        bg = world.node_tree.nodes.get("Background")
        if bg:
            bg.inputs[1].default_value = 0.02  # 背景光をほぼゼロに

# ── レンダリング設定 ───────────────────────────────
def setup_render():
    scene  = bpy.context.scene
    render = scene.render

    # Blender 3.x・4.x 両対応（4.2 で EEVEE Next が BLENDER_EEVEE に統合）
    render.engine = 'BLENDER_EEVEE'

    render.resolution_x              = ICON_SIZE
    render.resolution_y              = ICON_SIZE
    render.resolution_percentage     = 100
    render.film_transparent          = True    # 透明背景
    render.image_settings.file_format = 'PNG'
    render.image_settings.color_mode  = 'RGBA'
    render.image_settings.compression = 15
    render.filepath                   = OUTPUT_PATH

    eevee = getattr(scene, 'eevee', None)
    if eevee and hasattr(eevee, 'taa_render_samples'):
        eevee.taa_render_samples = EEVEE_SAMPLES

# ── メイン ────────────────────────────────────────
def main():
    center, radius = get_model_bounds()
    setup_camera(center, radius)
    setup_lights(center, radius)
    setup_render()

    abs_out = bpy.path.abspath(OUTPUT_PATH)
    os.makedirs(os.path.dirname(abs_out), exist_ok=True)

    bpy.ops.render.render(write_still=True)
    print(f"完了 → {abs_out}")

main()
```

---

## 各パートの解説

### 1. AABB でモデルサイズを自動取得

```python
def get_model_bounds():
    ...
    center = (mn + mx) / 2
    radius = max(mx.x - mn.x, mx.y - mn.y, mx.z - mn.z) / 2
```

シーン内の全メッシュのワールド座標バウンディングボックスを合算して、**中心点と最大半径**を求めます。これによりモデルのスケールに関係なく、カメラとライトの距離が自動で適切な値になります。

### 2. 球面座標でカメラを配置

```python
cam_x = center.x + dist * math.cos(elev) * math.sin(azim)
cam_y = center.y - dist * math.cos(elev) * math.cos(azim)
cam_z = center.z + dist * math.sin(elev)
```

仰角（`ELEV_DEG`）と方位角（`AZIMUTH_DEG`）を球面座標として計算し、カメラをモデルの周囲に配置します。その後 `to_track_quat('-Z', 'Y')` でカメラを中心に向けます。

**調整のコツ**：

| パラメータ | 効果 |
|---|---|
| `ELEV_DEG` を大きく | より上から見下ろす |
| `AZIMUTH_DEG` を変える | 左右の向きを変える |
| `CAMERA_DIST_F` を大きく | 引き（モデルが小さく映る） |
| `LENS_MM` を大きく | 歪みが少なくなる |

### 3. 3 点照明

ゲームアイコンでよく使われる 3 点照明をモデルサイズに合わせて自動配置します。

- **キーライト**：正面右上から当てる主光源。温かみのある白色
- **フィルライト**：影を和らげる補助光。青みがかった色で立体感を出す
- **リムライト**：背面から当ててモデルの輪郭を際立たせる

### 4. 透明背景（`film_transparent = True`）

```python
render.film_transparent = True
render.image_settings.color_mode = 'RGBA'
```

これが最重要の設定です。Roblox の Tool アイコンは正方形フレームの中に表示されるため、**背景が透明な PNG** にしておくと背景色がホットバーの色に合わせて自然に馴染みます。

### 5. Blender バージョン互換

Blender 4.2 で EEVEE Next が正式版になり、エンジン ID が `BLENDER_EEVEE` に統合されました。3.x・4.x ともに `'BLENDER_EEVEE'` で動作します。

---

## Roblox Studio への適用手順

1. **Asset Manager を開く**（ホームタブ → Asset Manager）
2. 「インポート」→ 生成した PNG ファイルを選択
3. アップロード完了後に表示される `rbxassetid://XXXXXXXXX` をコピー
4. Explorer で Tool を選択 → Properties → **TextureId** に貼り付け

---

## カスタマイズ例

```python
# 剣など縦長モデルは仰角を高めに
ELEV_DEG = 30
AZIMUTH_DEG = 25

# 盾など横広モデルは引きを増やす
CAMERA_DIST_F = 8.0

# 高品質版（時間がかかる）
EEVEE_SAMPLES = 128
```

---

## まとめ

- Blender Python でカメラ・ライト・レンダリング設定をすべて自動化できる
- `get_model_bounds()` によりモデルサイズに依存しない汎用スクリプトになっている
- `film_transparent = True` + RGBA PNG が Roblox アイコンには必須
- 設定値を変えるだけでどんな Tool モデルにも使い回せる

モデルを更新したとき、手動でカメラを直す手間がなくなるのが最大のメリットです。Roblox 以外でもゲームエンジンへのアセット納品に同じ手法が使えます。

---

## 参考

- [Blender Python API ドキュメント](https://docs.blender.org/api/current/)
- [Roblox Tool.TextureId プロパティ](https://create.roblox.com/docs/reference/engine/classes/Tool#TextureId)
