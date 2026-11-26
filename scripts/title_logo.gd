class_name TitleLogo
extends Node2D
##
## 起動直後の画面で動くタイトルロゴ。
##
##   TitleLogo        … 画面に合わせて置く・縮める（TitleSplash が決める）
##     Body           … 足元を支点に跳ねたりつぶれたりする
##       TitleLogoLayer × 5（下地・液体・文字・飾り・枠）
##
## - ふだんはふわふわ浮いて、少し傾く
## - ときどきジャンプする（かがむ → 跳ぶ → 着地でつぶれる）
## - 層ごとに少しずらして奥行きを出す（パララックス）
##     ・ゆっくりした揺れに合わせて、depth の分だけずれる
##     ・ジャンプの勢いに、lag の分だけ遅れてついてくる（中の液体が揺れる）
##   色の層は枠の後ろにあり、枠の線の下まで塗り広げてあるので、
##   max_shift までならずらしても隙間は見えない（tools/export_title_logo.py）
##
## 長さは、ことわりがなければ絵の px（縮める前の大きさ）。
##

## 着地した（起動時に落ちてきたときも含む）
signal landed
## 跳んだ
signal jumped

enum Phase { IDLE, CROUCH, AIR, DROP }

@export_group("ふわふわ")
## 上下に浮く幅
@export var float_height := 10.0
## 浮き沈み1回の秒数
@export var float_period := 2.8
## 左右に傾く角度（度）
@export var tilt_degrees := 1.2
## 層がずれる量（depth 1 のとき）
@export var sway := Vector2(7.0, 4.0)
## ずれが一回りする秒数
@export var sway_period := 6.0

@export_group("ジャンプ")
## 次に跳ぶまでの秒数（この間でばらつく）
@export var jump_interval := Vector2(3.5, 6.5)
## 跳ぶ高さ
@export var jump_height := 110.0
## 宙にいる秒数
@export var air_time := 0.62
## 跳ぶ前にかがむ秒数
@export var crouch_time := 0.14
## つぶれ・伸びの強さ
@export_range(0.0, 0.4, 0.01) var squash := 0.11
## 起動したとき上から落ちてくる
@export var drop_in := true
## 落ちてくる高さ
@export var drop_height := 1300.0

@export_group("層のずれ")
## ばねの固さ。大きいほど早く戻る
@export var spring_stiffness := 260.0
## ばねの止まりやすさ。小さいほど長く揺れる
@export var spring_damping := 7.0
## ずれの上限。export_title_logo.py の GROW（12）より小さく保つ
@export var max_shift := 10.0

@export_group("")
## 絵の中心から足元までの距離。つぶれるときの支点
@export var pivot_y := 455.0

var _body: Node2D
var _layers: Array[TitleLogoLayer] = []
var _t := 0.0
var _phase := Phase.IDLE
var _phase_t := 0.0
var _next_jump := 0.0
var _drop_y := 0.0
var _drop_vy := 0.0
var _land_t := 99.0
var _land_strength := 1.0
var _last_y := 0.0
var _last_vy := 0.0
var _started := false


func _ready() -> void:
	_body = get_node_or_null(^"Body") as Node2D
	if _body == null:
		push_error("TitleLogo: Body が無い")
		set_process(false)
		return
	_body.position = Vector2(0.0, pivot_y)
	for child in _body.get_children():
		if child is TitleLogoLayer:
			_layers.append(child)
			(child as TitleLogoLayer).position = Vector2(0.0, -pivot_y)
	_next_jump = randf_range(jump_interval.x, jump_interval.y)
	if drop_in:
		_phase = Phase.DROP
		_drop_y = -drop_height
		_drop_vy = 0.0
		_last_y = _drop_y
	_apply_body(_drop_y if drop_in else 0.0, Vector2.ONE)


## すぐに跳ぶ（宙にいるときは何もしない）
func jump() -> void:
	if _phase == Phase.IDLE:
		_phase = Phase.CROUCH
		_phase_t = 0.0


func is_idle() -> bool:
	return _phase == Phase.IDLE


func _process(delta: float) -> void:
	var dt := minf(delta, 1.0 / 30.0)
	_t += dt
	_phase_t += dt
	_land_t += dt

	var gravity := 8.0 * jump_height / (air_time * air_time)
	var y := 0.0
	var stretch := 0.0      # 正で縦に伸び、負でつぶれる

	match _phase:
		Phase.DROP:
			_drop_vy += gravity * 1.3 * dt
			_drop_y += _drop_vy * dt
			y = _drop_y
			stretch = clampf(_drop_vy / 4000.0, 0.0, 1.0) * squash * 0.8
			if _drop_y >= 0.0:
				_land(1.6)
				y = 0.0
		Phase.IDLE:
			_next_jump -= dt
			if _next_jump <= 0.0:
				jump()
		Phase.CROUCH:
			var k := ease(clampf(_phase_t / crouch_time, 0.0, 1.0), 0.5)
			stretch = -squash * k
			if _phase_t >= crouch_time:
				_phase = Phase.AIR
				_phase_t = 0.0
				jumped.emit()
		Phase.AIR:
			var u := clampf(_phase_t / air_time, 0.0, 1.0)
			y = -jump_height * 4.0 * u * (1.0 - u)
			stretch = squash * 0.8 * maxf(0.0, 1.0 - u * 2.5)
			if u >= 1.0:
				_land(1.0)
				y = 0.0

	# 着地のつぶれ（揺れながら戻る）
	if _land_t < 1.5:
		stretch -= _land_strength * squash * exp(-6.0 * _land_t) * cos(15.0 * _land_t)

	# ふわふわ（ジャンプ中も続ける。跳び始めで途切れないように）
	var bob := sin(_t * TAU / float_period) * float_height
	var body_y := y + bob
	_apply_body(body_y, Vector2(1.0 - stretch * 0.6, 1.0 + stretch))
	_body.rotation = deg_to_rad(tilt_degrees) * sin(_t * TAU / (float_period * 1.9))

	# 層のずれ
	var vy := (body_y - _last_y) / dt if _started else 0.0
	var dv := vy - _last_vy if _started else 0.0
	_last_y = body_y
	_last_vy = vy
	_started = true
	var sway_now := Vector2(sin(_t * TAU / sway_period) * sway.x,
			sin(_t * TAU / (sway_period * 1.37) + 1.3) * sway.y)
	for layer in _layers:
		if layer.lag > 0.0:
			# ロゴが急に動いた分だけ、中身は取り残される
			layer.spring_velocity.y -= dv * layer.lag
			var acc := -spring_stiffness * layer.spring - spring_damping * layer.spring_velocity
			layer.spring_velocity += acc * dt
			layer.spring += layer.spring_velocity * dt
			layer.spring = layer.spring.limit_length(max_shift * 2.0)
		var offset := sway_now * layer.depth + layer.spring
		var amount := offset.length()
		if amount > 0.001:
			# 上限に近づくほどゆっくり止まる
			offset *= max_shift * tanh(amount / max_shift) / amount
		layer.position = Vector2(0.0, -pivot_y) + offset


func _land(strength: float) -> void:
	_phase = Phase.IDLE
	_phase_t = 0.0
	_land_t = 0.0
	_land_strength = strength
	_next_jump = randf_range(jump_interval.x, jump_interval.y)
	landed.emit()


func _apply_body(y: float, scl: Vector2) -> void:
	_body.position = Vector2(0.0, pivot_y + y)
	_body.scale = scl
