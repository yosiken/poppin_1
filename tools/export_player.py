"""player.blend -> resources/model/player.glb 書き出し。

Blender の UI から普通にエクスポートすると、ボーン名の "." がそのまま残り、
Godot 側で PhysicalBone3D がボーンを引けなくなる（ノード名の "." は "_" へ
強制置換されるため）。必ずこのスクリプト経由で書き出すこと。

使い方（リポジトリのルートで）:

  "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b       ../data/models/player.blend --python tools/export_player.py       -- resources/model/player.glb

.blend は保存しない（改名は書き出し用のインメモリ処理のみ）。
"""
import bpy
import os
import sys

out = sys.argv[sys.argv.index("--") + 1]
out = os.path.abspath(out)

# ゲームに要らないので落とす
for ob in [o for o in bpy.data.objects if o.type == 'CAMERA']:
    bpy.data.objects.remove(ob, do_unlink=True)

# ボーン名の "." を潰す。アクションの fcurve は Blender が追従して書き換えてくれるので、
# 手付けしたモーションは壊れない（検証済み）
renamed = 0
for arm in [o for o in bpy.data.objects if o.type == 'ARMATURE']:
    for bone in arm.data.bones:
        if "." in bone.name:
            bone.name = bone.name.replace(".", "_")
            renamed += 1
print("renamed bones:", renamed)

for ob in [o for o in bpy.data.objects if o.type == 'MESH']:
    bad = [g.name for g in ob.vertex_groups if "." in g.name]
    if bad:
        print("WARNING: 頂点グループに '.' が残っています:", ob.name, bad)

bpy.ops.export_scene.gltf(
    filepath=out,
    export_format='GLB',
    export_skins=True,
    export_animations=True,
    export_apply=False,
)
print("exported:", out, os.path.getsize(out), "bytes")
