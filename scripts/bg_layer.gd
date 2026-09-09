@tool
class_name BgLayer
extends Parallax2D
##
## 背景の1枚。パララックスとラスタースクロールを持つ。
##
## Parallax2D を土台にしている。カメラへの追従率・自動スクロール・
## 繰り返しは組み込みの機能なので、このスクリプトは
##   - 絵を出す Sprite2D の面倒を見る
##   - 繰り返し幅を画像の大きさから自動で決める
##   - ラスタースクロールのシェーダーに値を渡す
## だけを受け持つ。
##
## Parallax2D は CanvasLayer の中に入れると正しく働かない（画面を覆えず、
## 右と上に隙間が出る）。2Dシーンに直接置いて、z_index で奥へ送ること。
##
## 3枚重ねる想定:
##   奥  parallax 0.1 くらい。空や海。海の部分だけラスターを効かせる
##   中  parallax 0.3 くらい。雲。ゆっくり自動スクロール
##   手前 parallax 0.6 くらい。木立など
##

const RASTER_SHADER := "res://resources/shader/raster_scroll.gdshader"

@export var texture: Texture2D:
	set(value):
		texture = value
		_apply()

## 画像の色みを変える。奥ほど薄くすると距離が出る
@export var tint := Color.WHITE:
	set(value):
		tint = value
		_apply()

## 画像を何倍で出すか。cover_screen が入っているときは無視される
@export_range(0.1, 16.0, 0.05) var zoom := 1.0:
	set(value):
		zoom = value
		_apply()

## 画面を必ず覆う大きさまで自動で拡大する。
## 空のように隙間が出せない層に使う。縦にずらすと下が抜けるので、
## この層は parallax の y を 0 にしておくこと
@export var cover_screen := false:
	set(value):
		cover_screen = value
		_apply()

## cover_screen の余白の倍率。1.0 だとぴったりで隙間の余裕が無い。
## カメラのスムージングがカットシーンの一時停止などに追いつききらないと
## 端に一瞬隙間が出るので、その分の余裕を持たせる
@export_range(1.0, 2.0, 0.05) var cover_margin := 1.3:
	set(value):
		cover_margin = value
		_apply()

## 画面のどこに合わせるか。0 = 上端、1 = 下端、0.5 = 中央。
## 画像の同じ割合の位置が画面のその位置に来る
@export_range(0.0, 1.0, 0.05) var anchor_y := 0.0:
	set(value):
		anchor_y = value
		_apply()

## 合わせた位置からのずらし量
@export var image_offset := Vector2.ZERO:
	set(value):
		image_offset = value
		_apply()

@export_group("Parallax")
## カメラの動きへの追従率。0 = 動かない、1 = 一緒に動く。
## 小さいほど遠くに見える
@export var parallax := Vector2(0.3, 0.3):
	set(value):
		parallax = value
		scroll_scale = value

## 勝手に流れる速さ (px/秒)
@export var flow := Vector2.ZERO:
	set(value):
		flow = value
		autoscroll = value

## 横に繰り返すか
@export var repeat_x := true:
	set(value):
		repeat_x = value
		_apply()

## 縦に繰り返すか
@export var repeat_y := false:
	set(value):
		repeat_y = value
		_apply()

@export_group("Raster scroll")
## 走査線ごとに横へずらして水面の揺れを出す
@export var raster := false:
	set(value):
		raster = value
		_apply()

## 横ずれの大きさ (px)
@export_range(0.0, 64.0, 0.5) var raster_amplitude := 2.0:
	set(value):
		raster_amplitude = value
		_push_shader()

## 波の縦方向の間隔 (px)。小さいほど細かく波打つ
@export_range(1.0, 512.0, 1.0) var raster_wavelength := 24.0:
	set(value):
		raster_wavelength = value
		_push_shader()

## 波が流れる速さ
@export_range(-20.0, 20.0, 0.1) var raster_speed := 2.0:
	set(value):
		raster_speed = value
		_push_shader()

## 効かせ始める高さ。画像の上端 0.0 〜 下端 1.0
@export_range(0.0, 1.0, 0.01) var raster_from := 0.5:
	set(value):
		raster_from = value
		_push_shader()

## 効かせ終わる高さ
@export_range(0.0, 1.0, 0.01) var raster_to := 1.0:
	set(value):
		raster_to = value
		_push_shader()

## 効き始めをなじませる幅。0 にすると境目に段差が出る
@export_range(0.0, 0.5, 0.005) var raster_fade := 0.03:
	set(value):
		raster_fade = value
		_push_shader()

var _sprite: Sprite2D


func _ready() -> void:
	_apply()


# ═══════════════════════════════ 組み立て

func _apply() -> void:
	if not is_inside_tree():
		return
	_ensure_sprite()
	_sprite.texture = texture
	_sprite.modulate = tint
	# 繰り返しはシェーダー側の texture() でも折り返す。
	# 端を舐めたときに反対側の色が出るので、継ぎ目のある絵は使わないこと
	_sprite.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	scroll_scale = parallax
	autoscroll = flow

	if texture == null:
		repeat_size = Vector2.ZERO
		return

	var screen := _screen()
	var tex_size := texture.get_size()
	var used := zoom
	if cover_screen and tex_size.x > 0.0 and tex_size.y > 0.0:
		used = maxf(screen.x / tex_size.x, screen.y / tex_size.y) * cover_margin
	_sprite.scale = Vector2(used, used)

	# 繰り返し幅は「画面上での画像の大きさ」。倍率を掛け忘れると
	# 継ぎ目が重なったり離れたりする
	var shown := tex_size * used
	_sprite.position = Vector2(
		image_offset.x,
		(screen.y - shown.y) * anchor_y + image_offset.y)

	repeat_size = Vector2(shown.x if repeat_x else 0.0, shown.y if repeat_y else 0.0)
	repeat_times = _needed_repeats(shown)
	_apply_material()


## 画面の大きさ。カメラのズームは見ていない。既定のズーム(1.4)では
## 画面に映る範囲より広く出るので足りる。大きく引くと端が抜ける
func _screen() -> Vector2:
	var vp := get_viewport()
	if vp:
		var size := Vector2(vp.get_visible_rect().size)
		if size.x > 0.0 and size.y > 0.0:
			return size
	return Vector2(
		ProjectSettings.get_setting("display/window/size/viewport_width", 1920),
		ProjectSettings.get_setting("display/window/size/viewport_height", 1080))


## 画面を埋めるのに何枚必要か。足りないと端に隙間が出る
func _needed_repeats(shown: Vector2) -> int:
	var screen := _screen()
	var need := 1
	if repeat_x and shown.x > 0.0:
		need = maxi(need, int(ceil(screen.x / shown.x)) + 1)
	if repeat_y and shown.y > 0.0:
		need = maxi(need, int(ceil(screen.y / shown.y)) + 1)
	return need


func _ensure_sprite() -> void:
	if _sprite != null and is_instance_valid(_sprite):
		return
	_sprite = get_node_or_null(^"Image") as Sprite2D
	if _sprite != null:
		return
	_sprite = Sprite2D.new()
	_sprite.name = "Image"
	# 左上を基準にする。中央基準だと image_offset の意味が分かりにくい
	_sprite.centered = false
	add_child(_sprite)


func _apply_material() -> void:
	if _sprite == null:
		return
	if not raster:
		_sprite.material = null
		return
	var mat := _sprite.material as ShaderMaterial
	if mat == null:
		mat = ShaderMaterial.new()
		mat.shader = load(RASTER_SHADER)
		_sprite.material = mat
	_push_shader()


func _push_shader() -> void:
	if _sprite == null:
		return
	var mat := _sprite.material as ShaderMaterial
	if mat == null:
		return
	mat.set_shader_parameter(&"amplitude", raster_amplitude)
	mat.set_shader_parameter(&"wavelength", raster_wavelength)
	mat.set_shader_parameter(&"speed", raster_speed)
	mat.set_shader_parameter(&"from_y", raster_from)
	mat.set_shader_parameter(&"to_y", raster_to)
	mat.set_shader_parameter(&"fade", raster_fade)
