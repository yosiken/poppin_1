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


@export_group("滑る面")
## 跳ね返せない角度の面に線を引く。踏む前に「ここは滑る」と分かるようにする
@export var slip_marks_enabled := true:
	set(value):
		slip_marks_enabled = value
		_sync_slip_marks()

## 線の色。チュートリアルの氷の板と同じ青にしてある
@export var slip_color := Color(0.25, 0.72, 1.0, 1.0):
	set(value):
		slip_color = value
		_sync_slip_marks()

## 線の太さ (px)。ワールドの px なので、ブロックの拡大率では変わらない
@export var slip_width := 7.0:
	set(value):
		slip_width = value
		_sync_slip_marks()

## これより立っている面には引かない (度)。
## 真横に近い面は見ただけで壁だと分かるので、引いても賠やかになるだけ
@export_range(40.0, 90.0, 1.0) var slip_max_angle := 80.0:
	set(value):
		slip_max_angle = value
		_sync_slip_marks()

## 滑る角度を読む元。未設定なら STATS_PATH を読む。
## 角度をここに書いてはいけない。跳ね返しの境目(ground_normal_threshold)を
## 後で変えたときに、線だけが嘘になる
@export var slip_stats: PogoStats:
	set(value):
		slip_stats = value
		_sync_slip_marks()


const TERRAIN_SHADER := "res://resources/shader/terrain_fill.gdshader"
## slip_stats が未設定のときに読む。本編はこれを使っている
const STATS_PATH := "res://resources/pogo_stats_default.tres"


func _ready() -> void:
	_apply()
	# 変形の追従はエディタだけ。ゲーム中は地形が動かない
	set_process(Engine.is_editor_hint())


func _process(_delta: float) -> void:
	# エディタでブロックを動かしたり伸ばしたりしている間、線を追従させる。
	# polygon の編集は _set で拾えるが、position や scale の変更は拾えない
	if _marks_xform != global_transform:
		_sync_slip_marks()


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
	_sync_slip_marks()
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

# ═══════════════════════════════ 滑る面の線

var _marks: Node2D
var _marks_xform := Transform2D()


## 跳ね返せる面の境目を PogoStats から取る。法線のY成分で見る(-1.0 が真上)。
## 読めなければ線を引かない。代わりの角度をここに書くと、
## PogoStats を変えたときに線だけが古い値のまま残る
func _slip_threshold() -> float:
	var s := slip_stats
	if s == null:
		s = load(STATS_PATH) as PogoStats
	if s == null:
		push_warning("TerrainSprite: %s が読めないので滑る面の線は引きません" % STATS_PATH)
		return NAN
	return s.ground_normal_threshold


## 形をワールド座標で取る。
##
## 見た目のポリゴンでなく copy_from のコリジョンから取る。
## 見た目は裾を下に伸ばしたりしているので、そこから取ると
## 実際には滑らない边に線が出て、嘘になる
func _collision_points_world() -> PackedVector2Array:
	var xform := global_transform
	var pts := polygon
	if not copy_from.is_empty():
		var src := get_node_or_null(copy_from) as CollisionPolygon2D
		if src != null:
			xform = src.global_transform
			pts = src.polygon
	var out := PackedVector2Array()
	for p in pts:
		out.append(xform * p)
	return out


## 滑る面（跳ね返せない角度の上向きの面）を、ワールド座標の線分で返す。
##
## 角度は必ずワールド座標で見る。ノードが縦横別に拡大されていると
## （Gfx_Block02 の scale(1.64, 1) など）、ローカルの傾きと、実際に
## プレイヤーが当たる傾きが違う
func _slip_segments() -> Array:
	var threshold := _slip_threshold()
	if is_nan(threshold):
		return []
	var pts := _collision_points_world()
	var count := pts.size()
	if count < 3:
		return []

	# 外向きの法線を出したいが、頂点の並び順はブロックごとに違う。
	# 符号付き面積で向きを揃える
	var area := 0.0
	for i in count:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[(i + 1) % count]
		area += a.x * b.y - b.x * a.y
	var s := 1.0 if area > 0.0 else -1.0

	# 立ちすぎた面を外す上限。法線のY成分に直して比べる
	var steepest := -cos(deg_to_rad(slip_max_angle))

	var out := []
	for i in count:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[(i + 1) % count]
		var d := b - a
		if d.length() < 1.0:
			continue
		var normal := Vector2(d.y, -d.x).normalized() * s
		# 上を向いている面のうち、跳ね返せないほど急なものだけ。
		# normal.y <= threshold なら地面扱いで跳ねる。下向きの面は踏めない
		if normal.y > threshold and normal.y <= steepest:
			out.append([a, b])
	return out


func _ensure_marks() -> Node2D:
	if _marks != null and is_instance_valid(_marks):
		return _marks
	_marks = get_node_or_null(^"SlipMarks") as Node2D
	if _marks == null:
		_marks = Node2D.new()
		_marks.name = "SlipMarks"
		add_child(_marks)
	return _marks


## 滑る面の線を引き直す。
##
## Line2D は途切れた線を引けないので、面ご1本ずつ置く。
## 親に直に下げず SlipMarks を挡んで、そこで親の変形を打ち消す。
## こうしないと、縦横別に拡大されたブロックで線の太さまで伸びて、
## ブロックごとに太さが変わってしまう。
##
## ここで作るノードは owner を付けないので .tscn には保存されない。
## 形を直せば次に読んだときに引き直る（Outline と同じやり方）
func _sync_slip_marks() -> void:
	if not is_inside_tree():
		return
	_marks_xform = global_transform
	var segments: Array = _slip_segments() if slip_marks_enabled else []
	if segments.is_empty():
		if _marks != null and is_instance_valid(_marks):
			_marks.visible = false
		return

	var marks := _ensure_marks()
	marks.visible = true
	marks.transform = _marks_xform.affine_inverse()

	# 本数が合わないときだけ作り直す。毎回作り直すと、エディタで
	# 形を触っている間、Line2D の生成と破棄が延々と続く
	if marks.get_child_count() != segments.size():
		for c in marks.get_children():
			marks.remove_child(c)
			c.queue_free()
		for i in segments.size():
			var line := Line2D.new()
			line.name = "Slip%d" % i
			line.begin_cap_mode = Line2D.LINE_CAP_ROUND
			line.end_cap_mode = Line2D.LINE_CAP_ROUND
			line.antialiased = true
			marks.add_child(line)

	for i in segments.size():
		var line := marks.get_child(i) as Line2D
		if line == null:
			continue
		line.width = slip_width
		line.default_color = slip_color
		line.points = PackedVector2Array([segments[i][0], segments[i][1]])
