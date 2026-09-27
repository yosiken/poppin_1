@tool
extends EditorScript
##
## モデルのテクスチャが正しく取り込まれているかを調べる診断用スクリプト。
##
## 使い方（コマンドライン不要）:
##   1. Godotエディタ上部の「スクリプト」タブを開く
##   2. このファイル (tools/check_model_texture.gd) を開く
##   3. メニューの ファイル → 実行  （Ctrl+Shift+X）
##   4. 下の「出力」パネルに結果が出る
##
## テクスチャが (なし) なら原因は Blender→Godot の取り込み側。
## パスが出ているのに白く見えるなら、原因は描画側（シェーダーやGPU）
##

const MODEL := "res://resources/model/player_8.blend"
const EXPECTED_TEX := "res://resources/model/player_8_LOW_basecolor.png.png"
const TOON := "res://resources/shader/toon_character.gdshader"


func _run() -> void:
	print("========== モデルのテクスチャ診断 ==========")
	print("レンダラー: ", ProjectSettings.get_setting("rendering/renderer/rendering_method"))
	print("GPU: ", RenderingServer.get_video_adapter_name())
	print("テクスチャPNGの存在: ", ResourceLoader.exists(EXPECTED_TEX))

	# テクスチャ単体が正しく取り込めているか
	var tex: Texture2D = load(EXPECTED_TEX) as Texture2D
	if tex == null:
		print("!! テクスチャを読み込めない（インポート失敗）")
	else:
		print("テクスチャ: %s  サイズ=%s" % [tex.get_class(), str(tex.get_size())])
		var img := tex.get_image()
		if img == null:
			print("!! 画像データを取り出せない（VRAM圧縮の展開に失敗）")
		else:
			print("画像: %dx%d 形式=%d" % [img.get_width(), img.get_height(), img.get_format()])

	print("トゥーンシェーダー: ", "読み込みOK" if load(TOON) else "!! 読み込み失敗")

	# モデル側のマテリアル
	var ps: PackedScene = load(MODEL)
	if ps == null:
		print("!! モデルを読み込めない。Blenderのパス設定を確認すること")
		print("==========================================")
		return
	var root := ps.instantiate()
	_walk(root)
	root.free()
	print("==========================================")


func _walk(n: Node) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		var mesh := mi.mesh
		if mesh:
			for i in mesh.get_surface_count():
				var m := mi.get_active_material(i)
				var t: Texture2D = null
				if m is BaseMaterial3D:
					t = (m as BaseMaterial3D).albedo_texture
				print("メッシュ '%s'[%d]  マテリアル=%s  テクスチャ=%s"
					% [mi.name, i, m.resource_name if m else "-",
						t.resource_path if t else "(なし)"])
	for c in n.get_children():
		_walk(c)
