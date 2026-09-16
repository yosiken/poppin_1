extends SceneTree
##
## モデルのテクスチャが正しく取り込まれているかを調べる診断用スクリプト。
##
##     godot --headless --path . --script res://tools/check_model_texture.gd
##
## 「Godotに取り込まれた時点で」テクスチャが付いているかを見る。
## ここで (なし) なら原因は Blender→Godot の取り込み、
## 付いているのにゲームで白いなら原因はその先（シェーダーや実行時）
##

const MODEL := "res://resources/model/player_8.blend"
const EXPECTED_TEX := "res://resources/model/player_8_LOW_basecolor.png.png"


func _initialize() -> void:
	print("== モデル: ", MODEL)
	print("== テクスチャPNGの存在: ", ResourceLoader.exists(EXPECTED_TEX))

	var ps: PackedScene = load(MODEL)
	if ps == null:
		print("!! モデルを読み込めない。Blenderのパス設定を確認すること")
		quit()
		return
	_walk(ps.instantiate())
	quit()


func _walk(n: Node) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		var mesh := mi.mesh
		if mesh:
			for i in mesh.get_surface_count():
				var m := mi.get_active_material(i)
				var kind := m.get_class() if m else "null"
				var mname: String = m.resource_name if m else "-"
				var tex: Texture2D = null
				if m is BaseMaterial3D:
					tex = (m as BaseMaterial3D).albedo_texture
				print("-- メッシュ '%s' [%d]" % [mi.name, i])
				print("     マテリアル: %s (%s)" % [mname, kind])
				print("     テクスチャ: %s" % [tex.resource_path if tex else "(なし)"])
				if m is BaseMaterial3D:
					print("     ベースカラー: %s" % str((m as BaseMaterial3D).albedo_color))
	for c in n.get_children():
		_walk(c)
