import bpy
import bmesh

# ==========================================
# 🛠️ 設定：マテリアル名とターゲットUV座標の定義
# ==========================================
# パレット上の中心座標 (X, Y) を指定します。
COLOR_MAPPING = {
    "Red":   (0.25, 0.75),  # 左上：赤
    "Black": (0.75, 0.75),  # 右上：黒
    "Silver": (0.25, 0.25), # 左下：銀
    "Yellow": (0.75, 0.25)  # 右下：黄
}

def auto_uv_palette_mapping():
    # 現在選択されているアクティブなオブジェクトを取得
    obj = bpy.context.active_object
    if not obj or obj.type != 'MESH':
        print("エラー: メッシュオブジェクトを選択してください。")
        return

    # 編集モードに切り替え
    bpy.ops.object.mode_set(mode='EDIT')
    
    # BMesh（Blenderのメッシュ操作API）の初期化
    me = obj.data
    bm = bmesh.from_edit_mesh(me)
    
    # UVレイヤーの取得（存在しない場合は新規作成）
    uv_layer = bm.loops.layers.uv.verify()
    
    # オブジェクト内のマテリアル名リストを取得
    material_names = [mat.name for mat in obj.data.materials if mat]

    # 全ての面をループ処理
    for face in bm.faces:
        # 面に設定されているマテリアルのインデックスを確認
        mat_index = face.material_index
        if mat_index >= len(material_names):
            continue
            
        mat_name = material_names[mat_index]
        
        # 定義したマテリアル名に一致する場合のみ処理
        if mat_name in COLOR_MAPPING:
            target_uv = COLOR_MAPPING[mat_name]
            
            # 面を構成するすべての頂点ループに対して処理
            for loop in face.loops:
                # 1. 一旦、面の頂点を中心点に極小化（サイズ0にして1点に集約）
                # 2. その点をターゲットのパレット座標へ移動
                loop[uv_layer].uv = target_uv

    # メッシュの更新とオブジェクトモードへの復帰
    bmesh.update_edit_mesh(me)
    bpy.ops.object.mode_set(mode='OBJECT')
    print("✨ UVの自動パレット配置が完了しました！")

# スクリプトの実行
auto_uv_palette_mapping()
