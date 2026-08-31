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


const MIRROR_SHADER := "res://resources/shader/mirror_tile.gdshader"


func _ready() -> void:
	_apply()


func _set(property: StringName, _value: Variant) -> bool:
	# texture を差し替えたら大きさを取り直す
	if property == &"texture":
		call_deferred("_apply")
	return false


## tile_size を texture_scale に変換する。
## Polygon2D は uv = 頂点 * texture_scale / 画像サイズ で貼るので、
## 1回ぶんが占める幅は 画像サイズ / texture_scale になる
func _apply() -> void:
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_apply_material()
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
	if not mirror_tiling:
		if material is ShaderMaterial:
			material = null
		return
	var mat := material as ShaderMaterial
	if mat == null or mat.shader == null:
		mat = ShaderMaterial.new()
		mat.shader = load(MIRROR_SHADER)
		material = mat


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
