import bpy
import math

def delete_existing_parts_and_materials():
    """古い消火器パーツと、壊れた古いマテリアルキャッシュを完全に削除してクリーンにする"""
    target_objects = ["Tank_Body", "Extinguisher_Head", "Lever", "Hose", "Pressure_Gauge"]
    target_materials = ["Red", "Black", "Silver", "Yellow"]
    
    if bpy.context.mode != 'OBJECT':
        bpy.ops.object.mode_set(mode='OBJECT')
        
    for obj_name in target_objects:
        if obj_name in bpy.data.objects:
            obj = bpy.data.objects[obj_name]
            bpy.data.objects.remove(obj, do_unlink=True)
            
    for mat_name in target_materials:
        if mat_name in bpy.data.materials:
            mat = bpy.data.materials[mat_name]
            bpy.data.materials.remove(mat, do_unlink=True)

def create_material(name):
    """完全にクリーンなマテリアルを新規作成してノードを接続する"""
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    nodes.clear()
    
    node_principled = nodes.new(type='ShaderNodeBsdfPrincipled')
    node_output = nodes.new(type='ShaderNodeOutputMaterial')
    
    node_principled.location = (0, 0)
    node_output.location = (300, 0)
    
    links.new(node_principled.outputs['BSDF'], node_output.inputs['Surface'])
    
    if name == "Red":
        color = (0.8, 0.05, 0.05, 1.0)
    elif name == "Black":
        color = (0.05, 0.05, 0.05, 1.0)
    elif name == "Silver":
        color = (0.6, 0.6, 0.6, 1.0)
        node_principled.inputs['Metallic'].default_value = 1.0
        node_principled.inputs['Roughness'].default_value = 0.3
    elif name == "Yellow":
        color = (0.8, 0.7, 0.05, 1.0)
        
    node_principled.inputs['Base Color'].default_value = color
    mat.diffuse_color = color
        
    return mat

def build_fire_extinguisher():
    # 1. 既存の古いパーツとマテリアルを完全リセット
    delete_existing_parts_and_materials()
    
    # 既存の選択をすべて解除
    bpy.ops.object.select_all(action='DESELECT')
    
    # 2. 綺麗なマテリアルを新規生成
    mat_red = create_material("Red")
    mat_black = create_material("Black")
    mat_silver = create_material("Silver")
    mat_yellow = create_material("Yellow")

    # 3. 各オブジェクトの生成
    # タンク本体 (本体：赤)
    bpy.ops.mesh.primitive_cylinder_add(radius=0.4, depth=1.6, location=(0, 0, 0.8))
    tank = bpy.context.active_object
    tank.name = "Tank_Body"

    # 上部レバー・ノズル部分 (金属：銀)
    bpy.ops.mesh.primitive_cylinder_add(radius=0.15, depth=0.2, location=(0, 0, 1.7))
    head = bpy.context.active_object
    head.name = "Extinguisher_Head"

    # 取手/レバーの簡易表現 (レバーはYプラス方向に伸びている)
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0.2, 1.85))
    lever = bpy.context.active_object
    lever.name = "Lever"
    lever.scale = (0.05, 0.4, 0.02)

    # 【位置修正】ホース部分 (ゴム：黒)
    # レバー（Yプラス）の真反対にするため、Yマイナス方向（0, -0.43, 1.1）に配置
    bpy.ops.mesh.primitive_cylinder_add(radius=0.03, depth=1.0, location=(0, -0.43, 1.1))
    hose = bpy.context.active_object
    hose.name = "Hose"
    # 手前側に綺麗に垂れ下がるよう、角度を調整
    hose.rotation_euler = (math.radians(-2), 0, 0)

    # 【位置修正】圧力ゲージ (メーター：黄)
    # ホースが手前に来たので、メーターは横（Xプラス方向）に配置を変更
    bpy.ops.mesh.primitive_cylinder_add(radius=0.08, depth=0.05, location=(0.18, 0, 1.75))
    gauge = bpy.context.active_object
    gauge.name = "Pressure_Gauge"
    gauge.rotation_euler = (0, math.radians(90), 0)

    # 4. 新しく作ったマテリアルを割り当て
    tank.data.materials.append(mat_red)
    head.data.materials.append(mat_silver)
    lever.data.materials.append(mat_silver)
    hose.data.materials.append(mat_black)
    gauge.data.materials.append(mat_yellow)

    # 全トランスフォームの適用
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    
    # 3Dビューポートの表示設定をMATERIALに更新
    for area in bpy.context.screen.areas:
        if area.type == 'VIEW_3D':
            for space in area.spaces:
                if space.type == 'VIEW_3D':
                    space.shading.type = 'MATERIAL'
    
    print("🚒 ホースをレバーの真反対に配置し、色付きで再生成しました！")

# 関数の呼び出し
build_fire_extinguisher()