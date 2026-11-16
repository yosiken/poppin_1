extends ColorRect
##
## matrix_rain.gdshader の parallax_offset / aspect を動かす。
##
##   カメラ   … 面の中を進むほど背景が横へ滑る（follow_camera）
##   マウス   … カーソルの位置に合わせて各層がずれる
##   矢印キー … 押している間その向きへ流れ続ける
##
## このスクリプトを、シェーダーを持つ ColorRect に付ける。
##
## 背景は画面に貼り付いた CanvasLayer に置くので、カメラが動いても勝手には
## 流れない。進んだぶんを自分でずらしてやると奥行きが出る
##

## カメラに合わせてずらす。横スクロールの面ではこれが主役
@export var follow_camera: bool = true
## カメラがこれだけ動くと視差が1つぶん（画面の parallax_strength ぶん）動く (px)。
## 背景はカメラと逆向きに流れる（右へ進むと背景は左へ）。
## 同じ向きに流したいときは負の値を入れる
@export var camera_span: float = 1600.0
## 縦だけ別の値にしたいとき (px)。0 なら camera_span と同じ。
##
## 本編の共通背景は縦には世界と同じだけ動く（Parallax2D の parallax.y = 1.0）。
## 背景が縦に動かないと、カメラが縦に動いたぶんが「地面だけが跳ねている」
## ように見えるので、こちらも小さい値＝よく動く設定にして揃える
@export var camera_span_y: float = 0.0
## 視差が 0 になるカメラ位置。既定はステージの原点
@export var camera_origin: Vector2 = Vector2.ZERO
@export var mouse_weight: float = 0.6
@export var key_speed: float = 0.9
@export var smoothing: float = 3.0
## これ以上ずれたら滑らせずに飛ばす（区画の切り替えでカメラが飛んだとき）
@export var snap_distance: float = 2.0

var _key_offset: Vector2 = Vector2.ZERO
var _current: Vector2 = Vector2.ZERO
## 1フレーム目だけは、滑らせずにその場所の値から始める
var _warmed: bool = false

func _ready() -> void:
	_update_aspect()
	get_viewport().size_changed.connect(_update_aspect)

func _set_param(name: StringName, value: Variant) -> void:
	var sm := material as ShaderMaterial
	if sm:
		sm.set_shader_parameter(name, value)

func _update_aspect() -> void:
	var vp: Vector2 = get_viewport_rect().size
	if vp.y > 0.0:
		_set_param("aspect", vp.x / vp.y)

## 今カメラが居る場所ぶんのずれ。絶対位置で決めるので、
## 同じ場所へ戻れば背景も同じところへ戻る。
##
## 符号はカメラと逆。右へ進めば背景は左へ流れる。
## （シェーダーは suv = uv - offset で取るので、ここを負にすると逆向きになる）
func _camera_offset() -> Vector2:
	if not follow_camera or is_zero_approx(camera_span):
		return Vector2.ZERO
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return Vector2.ZERO
	var d := camera_origin - cam.get_screen_center_position()
	var span_y := camera_span_y if not is_zero_approx(camera_span_y) else camera_span
	return Vector2(d.x / camera_span, d.y / span_y)

func _process(delta: float) -> void:
	var vp: Vector2 = get_viewport_rect().size
	var mouse_norm: Vector2 = Vector2.ZERO
	if vp.x > 0.0 and vp.y > 0.0:
		mouse_norm = get_global_mouse_position() / vp * 2.0 - Vector2.ONE

	var keys: Vector2 = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	_key_offset = (_key_offset + keys * key_speed * delta).clampf(-1.5, 1.5)

	var target: Vector2 = _camera_offset() + mouse_norm * mouse_weight + _key_offset
	if not _warmed or _current.distance_to(target) > snap_distance:
		# 面に入った瞬間や、区画を切り替えてカメラが飛んだとき。
		# 滑らせると画面を何枚もぶん流れてしまうので、その場で合わせる
		_warmed = true
		_current = target
	else:
		var t: float = 1.0 - exp(-smoothing * delta)
		_current = _current.lerp(target, t)
	_set_param("parallax_offset", _current)
