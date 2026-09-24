@tool
class_name JumpTrail
extends Line2D
##
## 溜めジャンプの軌跡をリボンで描く。
##
## 設計方針:
##   - 点はワールド座標で自前に持ち、描くときだけローカルへ変換する。
##     top_level だと親の移動から切り離せる代わりに描画順がツリーから外れ、
##     必ずキャラクターより手前に出てしまうため使わない
##   - 溜めて跳んだときだけ出す。通常のバウンドまで尾を引くとうるさい
##   - 溜め量で太さと長さを変える。「強く跳んだ」ことが画で分かるようにする
##

## 軌跡を出す最低溜め量 (0〜1)。これ未満の溜めでは出さない
@export_range(0.0, 1.0, 0.05) var min_charge := 0.25

@export_group("Position")
## 軌跡を描く基準を足元にするか。
## プレイヤーの原点は当たり判定カプセルの中心なので、そのままだと
## 軌跡が体の真ん中から生えて宙に浮いて見える。true で下端（接地点）へ下ろす
@export var from_feet := true
## 基準位置の微調整 (px)。from_feet で合わせた上からさらにずらす
@export var origin_offset := Vector2.ZERO

@export_group("Shape")
## 保持する点の最大数。多いほど尾が長い
@export_range(4, 200, 1) var max_points := 48
## 点を打つ最小間隔 (px)。近すぎる点を捨てて、停止時に点が団子になるのを防ぐ
@export_range(1.0, 64.0, 1.0) var point_distance := 10.0
## 溜め最大で跳んだときの根元の太さ (px)。溜め量に比例して細くなる
@export_range(1.0, 64.0, 1.0) var max_width := 16.0

@export_group("Look")
## 通常の溜めジャンプの色（根元＝キャラ側の色）。
## インスペクタで変えた瞬間に反映される
@export var trail_color := Color(1.0, 0.93, 0.55, 0.8):
	set(value):
		trail_color = value
		_apply_gradient(false)
## スーパージャンプの色。通常と変えて特別感を出す
@export var super_color := Color(0.55, 0.9, 1.0, 0.9)
## 毛先側の不透明度。0 で毛先へ向かって完全に消える
@export_range(0.0, 1.0, 0.05) var tail_alpha := 0.0
## 色の変化を自分で作りたいときに設定する。
## オフセット0が毛先、1が根元（キャラ側）。
## 未設定なら上の色と tail_alpha から自動で作る
@export var trail_gradient: Gradient
@export var super_gradient: Gradient
## 着地してから尾が消えるまでの時間 (秒)
@export_range(0.05, 3.0, 0.05) var fade_time := 0.3

var _player: PogoPlayer
var _active := false            ## 点を打ち続けている最中か
## 発射後に一度でも地面を離れたか。
## 発射の瞬間はまだ接地判定が残っているので、これを見ないと
## 打ち始めた次のフレームで「着地した」と誤判定して尾が伸びない
var _left_ground := false
## 軌跡の点。ワールド座標で保持する（Line2D 自身はローカル座標しか持てない）
var _world_points: PackedVector2Array = PackedVector2Array()
var _fade := 0.0                ## 1=不透明, 0=消えた


func _ready() -> void:
	# キャラクターより奥に描く。ツリー上でも Visual より前に置いてあるので、
	# この2つでスプライトの裏側に回る
	show_behind_parent = true
	z_as_relative = true
	joint_mode = Line2D.LINE_JOINT_ROUND
	begin_cap_mode = Line2D.LINE_CAP_ROUND
	end_cap_mode = Line2D.LINE_CAP_ROUND
	clear_points()
	_build_taper()
	# 設定した色をエディタでも反映する。発射時にしか代入しないと、
	# インスペクタで色を変えても実際に跳ぶまで見た目が変わらない
	_apply_gradient(false)
	if Engine.is_editor_hint():
		return

	_player = get_parent() as PogoPlayer
	if _player == null:
		push_warning("JumpTrail: 親が PogoPlayer ではありません")
		return
	_player.charged_jump.connect(_on_charged_jump)
	_player.teleported.connect(_reset)


## 軌跡の色を決める。
##
## Line2D はグラデーションを設定すると default_color を見なくなるので、
## 色はすべてこちらへ集約する。オフセット0が最初に打った点＝毛先側、
## 1が最後に打った点＝キャラ側
func _apply_gradient(is_super: bool) -> void:
	var custom := super_gradient if is_super else trail_gradient
	if custom:
		gradient = custom
		return
	var base := super_color if is_super else trail_color
	var g := Gradient.new()
	g.set_color(0, Color(base, base.a * tail_alpha))
	g.set_color(1, base)
	gradient = g


## 先端（＝キャラ側）を太く、末尾を細くする。
## Line2D の幅カーブはオフセット0が最初に打った点＝一番古い側なので、
## 0で細く、1で太くする
func _build_taper() -> void:
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.0))
	curve.add_point(Vector2(1.0, 1.0))
	width_curve = curve


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or _player == null:
		return

	if _active:
		if not _player.is_grounded():
			_left_ground = true
			_push_point(_trail_origin())
		elif _left_ground:
			# 飛んだあとに着地したら打ち止め。そこから尾を消していく
			_active = false
	elif _fade > 0.0:
		_fade = maxf(0.0, _fade - delta / maxf(fade_time, 0.001))
		modulate.a = _fade
		if _fade <= 0.0:
			_world_points.clear()
	if not _world_points.is_empty() or get_point_count() > 0:
		_sync_points()


## 軌跡を描く点。既定はキャラクターの足元（接地している高さ）。
## カプセルの寸法から求めるので、body_height を変えても付いてくる
func _trail_origin() -> Vector2:
	var at := _player.global_position + origin_offset
	if from_feet and _player.stats:
		at.y += _player.stats.body_height * 0.5
	return at


func _push_point(at: Vector2) -> void:
	var count := _world_points.size()
	if count > 0 and _world_points[count - 1].distance_to(at) < point_distance:
		return
	_world_points.append(at)
	# 古い方から捨てる。尾の長さを一定に保つ
	while _world_points.size() > max_points:
		_world_points.remove_at(0)


## 保持しているワールド座標を、このノードのローカル座標へ焼き直す。
## 親（プレイヤー）が動くたびにズレるので毎フレーム引き直す
func _sync_points() -> void:
	clear_points()
	for p in _world_points:
		add_point(to_local(p))


func _on_charged_jump(ratio: float, is_super: bool) -> void:
	if ratio < min_charge:
		return
	_reset()
	_active = true
	_left_ground = false
	_fade = 1.0
	modulate.a = 1.0
	# 溜めが浅いほど細く短い尾にする
	width = max_width * ratio
	_apply_gradient(is_super)
	_push_point(_trail_origin())


## 溜め直しやリスポーンで軌跡を捨てる。
## 座標が飛んだあとに古い点を残すと、ステージを横断する線が引かれる
func _reset() -> void:
	_active = false
	_left_ground = false
	_fade = 0.0
	_world_points.clear()
	clear_points()
	modulate.a = 1.0
