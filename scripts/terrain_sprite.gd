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
## 枠線の見た目をまとめて決める .tres（TerrainLook）。
##
## 割り当てると、このノードの outline_* より**こちらが優先**される。
## 同じ .tres を全ブロックに割り当てておけば、1か所直すだけで
## ステージ中の線が変わる（エディタでもその場で描き直る）。
## 空にすると、下の outline_* がそのまま使われる
@export var outline_look: TerrainLook:
	set(value):
		if outline_look == value:
			return
		if outline_look != null and outline_look.changed.is_connected(_apply):
			outline_look.changed.disconnect(_apply)
		outline_look = value
		if outline_look != null and not outline_look.changed.is_connected(_apply):
			outline_look.changed.connect(_apply)
		_apply()

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

## 輪郭線を2色の縞にする。切ると outline_color 一色
@export var outline_striped := false:
	set(value):
		outline_striped = value
		_apply()

## 縞のもう1色。outline_color と交互に出る
@export var outline_color2 := Color(0.95, 0.86, 0.35, 0.9):
	set(value):
		outline_color2 = value
		_apply()

## 縞1本の長さ (px)。この長さで2色が入れ替わる
@export_range(1.0, 200.0, 1.0) var outline_stripe_length := 14.0:
	set(value):
		outline_stripe_length = value
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


@export_group("模様")
## 模様の .tres（GroundPattern）。**マテリアルのようにドラッグするだけで模様になる。**
##
## resources/ground_pattern_grass.tres をここへ落とせば、このブロックは
## その絵で塗られ、カメラに合わせたパララックスも入る。テクスチャを
## 差し替えたり、下の pattern_enabled を入れたりする必要はない。
## 割り当てているあいだは、下の pattern_* / parallax_* と mirror_tiling より
## こちらが優先される。外すと元のテクスチャの塗りに戻る
@export var ground_pattern: GroundPattern:
	set(value):
		if ground_pattern == value:
			return
		if ground_pattern != null and ground_pattern.changed.is_connected(_on_pattern_changed):
			ground_pattern.changed.disconnect(_on_pattern_changed)
		ground_pattern = value
		if ground_pattern != null and not ground_pattern.changed.is_connected(_on_pattern_changed):
			ground_pattern.changed.connect(_on_pattern_changed)
		_on_pattern_changed()

## テクスチャをワールド座標で敷く。ブロックの拡大率や、地形をどこで
## 分割したかに関係なく、隣のブロックと柄が繋がる。
## 切ると今までどおり Polygon2D の UV で貼る（tile_size が効く）
@export var pattern_enabled := false:
	set(value):
		pattern_enabled = value
		_apply()

## 模様1枚ぶんを何pxで見せるか（ワールドの px）。
## tile_size とは別物。あちらは Polygon2D の UV 側の話。
##
## 絵が 512px なら、1024 で「絵の1ドット = ワールド2px」。カメラの zoom が
## 1.4 なので画面では約2.8px になり、ドットが四角く見える（ピクセルアート風）。
## 小さくするほど絵は細かくなるが、縮小されてドットが潰れる
@export var pattern_size := Vector2(1024.0, 1024.0):
	set(value):
		pattern_size = value
		_apply_material()

## カメラが動いたぶん、模様をどれだけ連れていくか。
## 0.06 ならカメラが 100px 動いて模様が 6px ずれる。0 で動かない。
## 地面そのものは動かないので、強くすると模様が滑って見える
@export_range(0.0, 0.5, 0.005) var parallax_strength := 0.06:
	set(value):
		parallax_strength = value
		_update_parallax_process()

## 追いつく速さ。カメラは着地のたびに上下に揺れるので、
## そのまま拾うと模様が細かく震える。鈍らせて緩やかに追わせる
@export_range(0.5, 20.0, 0.5) var parallax_smoothing := 3.0


const TERRAIN_SHADER := "res://resources/shader/terrain_fill.gdshader"
## 模様で塗るほう。pattern_enabled を入れるとこちらに替わる
const PATTERN_SHADER := "res://resources/shader/terrain_pattern.gdshader"
## slip_stats が未設定のときに読む。本編はこれを使っている
const STATS_PATH := "res://resources/pogo_stats_default.tres"


func _ready() -> void:
	_apply()
	# 変形の追従はエディタだけ。ゲーム中は地形が動かない
	set_process(Engine.is_editor_hint() or _parallax_live())
	# 最初の1枚から正しい位置で描く。_process が回り始めるのは次のフレーム
	# からなので、待っていると読み込み直後の数フレームが「ずれ 0」で描かれ、
	# そのあと一気に跳んでいた。遅延呼び出しにしているのは、ステージを
	# 読み込んだ側がこのあとカメラの範囲を設定してカメラを動かすため
	# （game.gd の _apply_camera_bounds）。遅延呼び出しは描画の前に流れる
	if _parallax_live() and not Engine.is_editor_hint():
		_snap_parallax.call_deferred()


func _process(delta: float) -> void:
	# エディタでブロックを動かしたり伸ばしたりしている間、線を追従させる。
	# polygon の編集は _set で拾えるが、position や scale の変更は拾えない
	if Engine.is_editor_hint() and _marks_xform != global_transform:
		_sync_slip_marks()
	if _parallax_live():
		_update_parallax(delta)


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


## .tres の値が変わった・付け替えた
func _on_pattern_changed() -> void:
	_parallax_warm = false
	_apply_material()
	_update_parallax_process()


# 模様の値。ground_pattern があればそちら、無ければノード側
func _pattern_on() -> bool:
	return ground_pattern != null or pattern_enabled


func _pattern_size() -> Vector2:
	return ground_pattern.size if ground_pattern != null else pattern_size


func _pattern_mirror() -> bool:
	return ground_pattern.mirror_tiling if ground_pattern != null else mirror_tiling


func _parallax_strength() -> float:
	return ground_pattern.parallax_strength if ground_pattern != null else parallax_strength


func _parallax_smoothing() -> float:
	return ground_pattern.parallax_smoothing if ground_pattern != null else parallax_smoothing


func _apply_material() -> void:
	var want: String = PATTERN_SHADER if _pattern_on() else TERRAIN_SHADER
	var mat := material as ShaderMaterial
	if mat == null:
		mat = ShaderMaterial.new()
		material = mat
	# 手で別のシェーダー（氷の板や熱い板）を貼ってあるときは、そちらを残す。
	# 模様と塗りの2本だけ、pattern_enabled に合わせて入れ替える
	var now := mat.shader.resource_path if mat.shader != null else ""
	if now == "" or now == TERRAIN_SHADER or now == PATTERN_SHADER:
		if now != want:
			mat.shader = load(want)
	mat.set_shader_parameter(&"pattern_size", _pattern_size())
	mat.set_shader_parameter(&"parallax_offset", _parallax)
	mat.set_shader_parameter(&"mirror_tiling", _pattern_mirror())
	# .tres の絵はノードのテクスチャとは別に渡す。ノードのテクスチャを
	# 書き換えないので、.tres を外せば元の塗りにそのまま戻る
	var pat_tex: Texture2D = ground_pattern.texture if ground_pattern != null else null
	mat.set_shader_parameter(&"use_pattern_texture", pat_tex != null)
	mat.set_shader_parameter(&"pattern_texture", pat_tex)
	mat.set_shader_parameter(&"shadow_height", shadow_height)
	mat.set_shader_parameter(&"shadow_strength", shadow_strength)
	mat.set_shader_parameter(&"shadow_color", shadow_color)
	mat.set_shader_parameter(&"bottom_y", _polygon_bottom_y())


## 模様をずらしている量 (px)
var _parallax := Vector2.ZERO
## 1フレーム目だけは滑らせずに、その場所の値から始める
var _parallax_warm := false
## 前のフレームでカメラが見ていた場所。瞬間移動を見分けるのに使う
var _parallax_last_center := Vector2.ZERO

## カメラが1フレームでこれ以上動いたら、追いかけずにその場へ合わせる (px)。
## 復帰地点への瞬間移動やカメラ範囲の付け直しで、模様がゆっくり
## 滑っていくのを防ぐ。ふだんの移動は1フレーム数十px なので届かない
const PARALLAX_SNAP_DISTANCE := 300.0


## パララックスを動かすか。模様を切っていたり、量が 0 なら動かさない
func _parallax_live() -> bool:
	return _pattern_on() and _parallax_strength() > 0.0


## パララックスの要不要が変わったら、_process の出入りをやり直す
func _update_parallax_process() -> void:
	if is_inside_tree():
		set_process(Engine.is_editor_hint() or _parallax_live())


## カメラの居る場所に合わせて模様をずらす。
##
## 見ている場所そのもの（get_screen_center_position）を基準にするので、
## 同じ場所へ戻れば模様も同じところへ戻る。足した量ではないので、
## 行ったり来たりしているうちに模様が流れていくことはない
func _update_parallax(delta: float) -> void:
	var mat := material as ShaderMaterial
	if mat == null:
		return
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return
	var center := cam.get_screen_center_position()
	if _parallax_warm and center.distance_to(_parallax_last_center) > PARALLAX_SNAP_DISTANCE:
		_parallax_warm = false
	_parallax_last_center = center
	var target := center * _parallax_strength()
	var smoothing := _parallax_smoothing()
	if _parallax_warm and smoothing > 0.0:
		_parallax = _parallax.lerp(target, clampf(smoothing * delta, 0.0, 1.0))
	else:
		_parallax = target
		_parallax_warm = true
	mat.set_shader_parameter(&"parallax_offset", _parallax)


## 追いかけずに、今カメラが見ている場所の値へ合わせる
func _snap_parallax() -> void:
	if not is_inside_tree() or not _parallax_live():
		return
	_parallax_warm = false
	_update_parallax(0.0)


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
	if not _look_enabled() or polygon.size() < 2:
		if _outline != null and is_instance_valid(_outline):
			_outline.visible = false
		return
	_ensure_outline()
	_outline.visible = true
	_outline.width = _look_width()
	if _look_striped():
		# 色は絵のほうで持つので、線そのものは白（＝絵の色そのまま）にする
		_outline.default_color = Color.WHITE
		_outline.texture = _stripe_texture()
		_outline.texture_mode = Line2D.LINE_TEXTURE_TILE
		_outline.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		_outline.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	else:
		_outline.default_color = _look_color()
		_outline.texture = null
		_outline.texture_mode = Line2D.LINE_TEXTURE_NONE
	var pts := PackedVector2Array(polygon)
	pts.append(polygon[0])
	_outline.points = pts


var _stripe_tex: ImageTexture
var _stripe_key := ""


## 2色の縞を1組ぶん描いた小さな絵。Line2D に貼って線の長さ方向へ繰り返させる。
##
## Line2D の TILE は、絵の高さを線の太さに合わせてから長さ方向へ並べる。
## 高さを線の太さと同じ px で作っておけば、絵の幅がそのまま縞の長さになる。
## 作り直すのは色・長さ・太さが変わったときだけ（毎フレーム作ると重い）
func _stripe_texture() -> Texture2D:
	var c1 := _look_color()
	var c2 := _look_color2()
	var seg := maxi(1, int(round(_look_stripe_length())))
	var h := maxi(1, int(round(_look_width())))
	var key := "%d_%d_%s_%s" % [seg, h, c1, c2]
	if _stripe_key == key and _stripe_tex != null:
		return _stripe_tex
	var img := Image.create(seg * 2, h, false, Image.FORMAT_RGBA8)
	for x in seg * 2:
		var c := c1 if x < seg else c2
		for y in h:
			img.set_pixel(x, y, c)
	_stripe_tex = ImageTexture.create_from_image(img)
	_stripe_key = key
	return _stripe_tex


## ここから下は「.tres があればそちら、無ければノードの値」を返す小物。
## _sync_outline からはこちらだけを見る

func _look_enabled() -> bool:
	return outline_look.enabled if outline_look != null else outline_enabled


func _look_color() -> Color:
	return outline_look.color if outline_look != null else outline_color


func _look_color2() -> Color:
	return outline_look.color2 if outline_look != null else outline_color2


func _look_width() -> float:
	return outline_look.width if outline_look != null else outline_width


func _look_striped() -> bool:
	return outline_look.striped if outline_look != null else outline_striped


func _look_stripe_length() -> float:
	return outline_look.stripe_length if outline_look != null else outline_stripe_length


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
