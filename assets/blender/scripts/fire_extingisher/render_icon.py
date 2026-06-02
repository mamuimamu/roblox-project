"""
render_icon.py
消火器モデルの Roblox Tool アイコン（420×420 PNG）を自動レンダリングする。

使い方:
  1. fire_extingisher.blend を Blender で開く
  2. Scripting タブを開き、このファイルを読み込む
  3. ▶ Run Script を押す
  4. assets/images/fire_extinguisher_icon.png が生成される

出力先: assets/images/fire_extinguisher_icon.png
"""

import bpy
import math
import os
from mathutils import Vector

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 設定（ここを調整してアングルや品質を変更できる）
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# 出力パス（// = .blend ファイルのディレクトリ = assets/models/）
OUTPUT_PATH   = "//../images/fire_extinguisher_icon.png"
ICON_SIZE     = 420          # Roblox Tool アイコン推奨サイズ（px）

# カメラアングル
ELEV_DEG      = 20           # 仰角（度）: 大きいほど上から見る
AZIMUTH_DEG   = 40           # 方位角（度）: 正面から右に何度回すか
CAMERA_DIST_F = 6.0          # モデル半径の何倍離れるか（大きいほど引き）
LENS_MM       = 85           # レンズ焦点距離（大きいほど歪みが少ない）

# サンプル数（大きいほど高品質・低速）
EEVEE_SAMPLES = 64


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# モデル全体の AABB を取得
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

def get_model_bounds():
    """シーン内の全メッシュオブジェクトの AABB（中心・半径）を返す"""
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
        print("[render_icon] メッシュが見つかりません。デフォルト値を使用します。")
        return Vector((0, 0, 0)), 1.0

    center = (mn + mx) / 2
    radius = max(mx.x - mn.x, mx.y - mn.y, mx.z - mn.z) / 2
    return center, max(radius, 0.01)


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# カメラ配置
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

def setup_camera(center, radius):
    """既存カメラを削除し、モデルを正面やや斜め上から映すカメラを配置する"""
    for obj in list(bpy.data.objects):
        if obj.type == 'CAMERA':
            bpy.data.objects.remove(obj, do_unlink=True)

    dist = radius * CAMERA_DIST_F
    elev = math.radians(ELEV_DEG)
    azim = math.radians(AZIMUTH_DEG)

    # 球面座標 → デカルト座標
    cam_x = center.x + dist * math.cos(elev) * math.sin(azim)
    cam_y = center.y - dist * math.cos(elev) * math.cos(azim)
    cam_z = center.z + dist * math.sin(elev)

    cam_data             = bpy.data.cameras.new("IconCamera")
    cam_data.type        = 'PERSP'
    cam_data.lens        = LENS_MM
    cam_data.clip_start  = 0.01
    cam_data.clip_end    = 1000.0

    cam_obj          = bpy.data.objects.new("IconCamera", cam_data)
    bpy.context.scene.collection.objects.link(cam_obj)
    cam_obj.location = Vector((cam_x, cam_y, cam_z))

    # カメラを center に向ける
    direction             = center - cam_obj.location
    cam_obj.rotation_euler = direction.to_track_quat('-Z', 'Y').to_euler()

    bpy.context.scene.camera = cam_obj
    print(f"[render_icon] カメラ位置: ({cam_x:.2f}, {cam_y:.2f}, {cam_z:.2f})")


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 3点照明（キー・フィル・リム）
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

def setup_lights(center, radius):
    """既存ライトを削除し、アイコン向け3点照明を設置する"""
    for obj in list(bpy.data.objects):
        if obj.type == 'LIGHT':
            bpy.data.objects.remove(obj, do_unlink=True)

    def add_point(name, offset, energy, color=(1.0, 1.0, 1.0)):
        ld        = bpy.data.lights.new(name, type='POINT')
        ld.energy = energy
        ld.color  = color
        lo        = bpy.data.objects.new(name, ld)
        bpy.context.scene.collection.objects.link(lo)
        lo.location = center + Vector(offset) * radius
        return lo

    r = 1.0
    # キーライト: 正面右上（温かみのある白）
    add_point("KeyLight",  ( 2.5, -2.0,  3.5), energy=radius * 700,
              color=(1.00, 0.97, 0.93))
    # フィルライト: 正面左（青みがかった補助光）
    add_point("FillLight", (-2.0, -1.5,  1.0), energy=radius * 180,
              color=(0.80, 0.90, 1.00))
    # リムライト: 背面上（輪郭を際立たせる）
    add_point("RimLight",  (-0.5,  3.0,  2.5), energy=radius * 350,
              color=(1.00, 1.00, 1.00))

    # World 背景を暗め（透明背景で余計な光を抑える）
    world = bpy.context.scene.world
    if world and world.node_tree:
        bg_node = world.node_tree.nodes.get("Background")
        if bg_node:
            bg_node.inputs[1].default_value = 0.02  # 強度をほぼゼロに

    print("[render_icon] 3点照明 配置完了")


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# レンダリング設定
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

def setup_render():
    """解像度・透明背景・PNG 出力などのレンダリング設定を行う"""
    scene  = bpy.context.scene
    render = scene.render

    # 全バージョン共通: 3.x は旧EEVEE、4.2+ は EEVEE Next が同じ ID に統合済み
    render.engine = 'BLENDER_EEVEE'

    render.resolution_x              = ICON_SIZE
    render.resolution_y              = ICON_SIZE
    render.resolution_percentage     = 100
    render.film_transparent          = True   # 透明背景（Alpha チャンネル付き）
    render.image_settings.file_format = 'PNG'
    render.image_settings.color_mode  = 'RGBA'
    render.image_settings.compression = 15
    render.filepath                   = OUTPUT_PATH

    # EEVEE サンプル数
    eevee = getattr(scene, 'eevee', None)
    if eevee:
        if hasattr(eevee, 'taa_render_samples'):
            eevee.taa_render_samples = EEVEE_SAMPLES
        if hasattr(eevee, 'use_bloom'):
            eevee.use_bloom = True

    print(f"[render_icon] レンダラー: {render.engine}, サイズ: {ICON_SIZE}×{ICON_SIZE}px")


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# メイン
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

def main():
    print("=" * 50)
    print("render_icon.py 開始")
    print("=" * 50)

    center, radius = get_model_bounds()
    print(f"[render_icon] モデル中心={center}, 半径={radius:.3f}")

    setup_camera(center, radius)
    setup_lights(center, radius)
    setup_render()

    # 出力ディレクトリが存在しない場合は作成
    abs_out = bpy.path.abspath(OUTPUT_PATH)
    os.makedirs(os.path.dirname(abs_out), exist_ok=True)

    print(f"[render_icon] レンダリング実行中...")
    bpy.ops.render.render(write_still=True)

    print("=" * 50)
    print(f"完了！ → {abs_out}")
    print("次のステップ:")
    print("  1. Roblox Studio の Asset Manager でこの PNG をインポート")
    print("  2. 取得した rbxassetid を Tool.TextureId に設定")
    print("=" * 50)


main()
