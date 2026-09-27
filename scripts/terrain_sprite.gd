@tool
class_name TerrainSprite
extends Polygon2D
##
## 地形の見た目を描くポリゴン。コリジョンと同じようにポリゴンを置いて、
## そこにテクスチャを敷き詰める。
##
## 中身は Polygon2D そのままなので、エディタの「ポリゴンを編集」で頂点を
## 触れるし、UV も組み込みの機能で調整できる。このスクリプトが足しているのは
## 3つだけ:
##   - テクスチャの繰り返しと最近傍フィルタを既定にする。
##     Polygon2D の既定は繰り返し無しなので、放っておくと1枚しか貼られず、
##     余った面が引き伸ばされる
##   - 1タイルを何pxで見せるかを px で指定できるようにする。
##     素の texture_scale は「画像の大きさに対する倍率」なので、
##     画像を差し替えると見た目の大きさが変わってしまう
##   - コリジョンから形をコピーする手当て
##
## タイルは resources/texture/Parts/tiles にある。シートのままでは
## 繰り返しに使えないので tools/slice_tiles.gd で切り出してある。
##
## ステージのコリジョンからまとめて作るには tools/make_terrain_sprites.gd。
##

## 1タイルを何pxで見せるか。0 なら画像の原寸。
## y を 0 にすると x から縦横比を保って決める
@export var tile_size := Vector2(160.0, 0.0):
	set(value):
		tile_size = value
		_apply()

## 1マスごとに絵を反転して貼る。上下左右が繋がっていない絵でも
## 継ぎ目が出なくなる代わりに、対称の模様が出る。
## 芝や土のような細かい絵向き。レンガや板のように向きのある絵には向かない
@export var mirror_tiling := false:
	set(value):
		mirror_tiling = value
		_apply_material()

## 形をコピーしてくる CollisionPolygon2D
@export var copy_from: NodePath

## チェックを入れると copy_from の形と位置を取り込む。値は自動で戻る
@export var copy_shape_now := false:
	set(value):
		copy_shape_now = false
		if value:
			_copy_shape()


@export_group("縁取り・影")
## ポリゴンの輪郭に沿って線を描く。BGと足場の境目を見やすくする
@export var outline_enabled := true:
	set(value):
		outline_enabled = value
		_apply()

## 輪郭線の色
@export var outline_color := Color(0.09, 0.07, 0.05, 0.9):
	set(value):
		outline_color = value
		_apply()

## 輪郭線の太さ (px)
@export var outline_width := 4.0:
	set(value):
		outline_width = value
		_apply()

## 下端をどれだけ暗くするか。0 で無効。地面に接している感じを出す
@export_range(0.0, 1.0, 0.05) var shadow_strength := 0.35:
	set(value):
		shadow_strength = value
		_apply_material()

## 下端から何pxぶんを暗くするか
@export var shadow_height := 24.0:
	set(value):
		shadow_height = value
		_apply_material()

## 影の色
@export var shadow_color := Color(0.0, 0.0, 0.0, 1.0):
	set(value):
		shadow_color = value
		_apply_material()


const TERRAIN_SHADER := "res://resources/shader/terrain_fill.gdshader"


func _ready() -> void:
	_apply()


func _set(property: StringName, _value: Variant) -> bool:
	# texture を差し替えたら大きさを取り直す。polygon の編集は輪郭線と
	# 影の下端に反映する必要がある
	if property == &"texture" or property == &"polygon":
		call_deferred("_apply")
	return false


## tile_size を texture_scale に変換する。
## Polygon2D は uv = 頂点 * texture_scale / 画像サイズ で貼るので、
## 1回ぶんが占める幅は 画像サイズ / texture_scale になる
func _apply() -> void:
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_apply_material()
	_sync_outline()
	if texture == null:
		return
	var tex_size := texture.get_size()
	if tex_size.x <= 0.0 or tex_size.y <= 0.0:
		return
	var want := tile_size
	if want.x <= 0.0 and want.y <= 0.0:
		texture_scale = Vector2.ONE
		return
	if want.y <= 0.0:
		want.y = want.x * (tex_size.y / tex_size.x)
	elif want.x <= 0.0:
		want.x = want.y * (tex_size.x / tex_size.y)
	texture_scale = tex_size / want


func _apply_material() -> void:
	var mat := material as ShaderMaterial
	if mat == null or mat.shader == null:
		mat = ShaderMaterial.new()
		mat.shader = load(TERRAIN_SHADER)
		material = mat
	mat.set_shader_parameter(&"mirror_tiling", mirror_tiling)
	mat.set_shader_parameter(&"shadow_height", shadow_height)
	mat.set_shader_parameter(&"shadow_strength", shadow_strength)
	mat.set_shader_parameter(&"shadow_color", shadow_color)
	mat.set_shader_parameter(&"bottom_y", _polygon_bottom_y())


## ポリゴンのローカル座標での下端(最大Y)。影のグラデーションの基準にする
func _polygon_bottom_y() -> float:
	if polygon.is_empty():
		return 0.0
	var max_y := polygon[0].y
	for p in polygon:
		max_y = maxf(max_y, p.y)
	return max_y


var _outline: Line2D


func _ensure_outline() -> void:
	if _outline != null and is_instance_valid(_outline):
		return
	_outline = get_node_or_null(^"Outline") as Line2D
	if _outline != null:
		return
	_outline = Line2D.new()
	_outline.name = "Outline"
	_outline.joint_mode = Line2D.LINE_JOINT_ROUND
	_outline.begin_cap_mode = Line2D.LINE_CAP_ROUND
	_outline.end_cap_mode = Line2D.LINE_CAP_ROUND
	add_child(_outline)


## polygon の形に沿って輪郭線を引き直す
func _sync_outline() -> void:
	if not outline_enabled or polygon.size() < 2:
		if _outline != null and is_instance_valid(_outline):
			_outline.visible = false
		return
	_ensure_outline()
	_outline.visible = true
	_outline.width = outline_width
	_outline.default_color = outline_color
	var pts := PackedVector2Array(polygon)
	pts.append(polygon[0])
	_outline.points = pts


func _copy_shape() -> void:
	if copy_from.is_empty():
		push_warning("TerrainSprite: copy_from が未設定です")
		return
	var src := get_node_or_null(copy_from) as CollisionPolygon2D
	if src == null:
		push_warning("TerrainSprite: copy_from が CollisionPolygon2D ではありません")
		return
	# 位置と回転も合わせる。頂点だけ写すと、親の座標が違うときにずれる
	global_transform = src.global_transform
	polygon = src.polygon.duplicate()
	_apply()
