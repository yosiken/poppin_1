@tool
class_name PogoPlayer
extends CharacterBody2D
##
## ポゴ跳躍プレイヤー。
##
## 設計方針:
##   - 数値は一切ハードコードせず、全て PogoStats から読む
##   - スキル効果は _mods（加算/乗算モディファイア）経由で重ねる。
##     stats リソース自体は書き換えないので、いつでも素の値に戻せる
##   - コリジョン形状は stats から実行時に組み立てる。@tool なのでエディタでも即反映
##

signal bounced(strength: float, normal: Vector2)
signal fell(fall_distance: float, from_position: Vector2)
signal charge_changed(ratio: float)

const UP := Vector2.UP

# ─────────────────────────────── 設定
@export var stats: PogoStats:
	set(value):
		if stats and stats.changed.is_connected(_on_stats_changed):
			stats.changed.disconnect(_on_stats_changed)
		stats = value
		if stats and not stats.changed.is_connected(_on_stats_changed):
			stats.changed.connect(_on_stats_changed)
		_apply_shape()

## デバッグ描画（傾き軸・接触法線・チャージ）
@export var debug_draw := true

## スーパージャンプ解放フラグ（スキルツリーから設定）
@export var super_jump_unlocked := false

# ─────────────────────────────── 内部状態
var tilt_deg := 0.0            ## 現在の傾き角（右が正）
var charge := 0.0              ## 0.0〜1.0
var last_normal := Vector2.UP  ## 直近の接触法線（デバッグ用）

var _shape_node: CollisionShape2D
var _capsule: CapsuleShape2D
var _mods: Dictionary = {}     ## { "bounce_add": {"add": 0.0, "mul": 1.0}, ... }

var _super_cd := 0.0
var _charge_released_at := -999.0
var _charge_at_release := 0.0
var _apex_y := 0.0             ## 直近の最高到達点（落下距離計測用）
var _was_rising := false
var _snap_hold_timer := 0.0        ## 着地スナップ後、スタビライズを止めておく残り時間
var _charge_hold_timer := 0.0      ## チャージ中にその場で留まれる残り時間
var _charge_pinned := false        ## チャージでその場固定中かどうか
var _pin_impact_velocity := Vector2.ZERO  ## 固定に入った瞬間の進入速度（解除時の反発に使う）


# ═══════════════════════════════ ライフサイクル

func _ready() -> void:
	_apply_shape()
	_apex_y = global_position.y
	if Engine.is_editor_hint():
		set_physics_process(false)


func _physics_process(delta: float) -> void:
	if stats == null:
		return

	_process_tilt(delta)
	_process_charge(delta)

	_super_cd = maxf(0.0, _super_cd - delta)

	_apply_gravity(delta)
	_track_apex()
	_move_and_bounce(delta)

	if debug_draw:
		queue_redraw()


# ═══════════════════════════════ 入力・角度

func _process_tilt(delta: float) -> void:
	var input := Input.get_axis(&"pogo_left", &"pogo_right")
	var limit := _s("tilt_limit")

	if absf(input) > 0.01:
		tilt_deg += input * _s("tilt_speed") * delta
	elif _snap_hold_timer <= 0.0:
		# 中央へ自動復元。安定性スキルでここが速くなる
		tilt_deg = move_toward(tilt_deg, 0.0, _s("stabilize_rate") * delta)

	# 着地スナップ直後は一定時間スタビライズを止める。経過すると強制解除される
	_snap_hold_timer = maxf(0.0, _snap_hold_timer - delta)

	tilt_deg = clampf(tilt_deg, -limit, limit)


func _process_charge(delta: float) -> void:
	var t := _s("charge_time")
	if Input.is_action_just_pressed(&"pogo_charge"):
		# 押し始めた瞬間にホールド時間を満タンにする（着地済みでも空中先行入力でも同じ）
		_charge_hold_timer = _s("charge_hold_time")

	if Input.is_action_pressed(&"pogo_charge"):
		charge = minf(1.0, charge + delta / maxf(t, 0.001))
	elif charge > 0.0:
		# 離した瞬間の値を入力バッファ用に保持
		_charge_at_release = charge
		_charge_released_at = _now()
		charge = 0.0
	charge_changed.emit(charge)


## 接地時に実際に使うチャージ量。離した直後なら入力バッファで救済する
func _consume_charge() -> float:
	var value := charge
	if value <= 0.0:
		var elapsed := _now() - _charge_released_at
		if elapsed <= _s("input_buffer_time"):
			value = _charge_at_release
	charge = 0.0
	_charge_at_release = 0.0
	_charge_released_at = -999.0
	return value


# ═══════════════════════════════ 移動と反発

func _apply_gravity(delta: float) -> void:
	velocity.y += _s("gravity") * delta
	velocity.y = minf(velocity.y, _s("terminal_velocity"))
	velocity.x = lerpf(velocity.x, 0.0, _s("air_drag") * delta)


func _track_apex() -> void:
	var rising := velocity.y < 0.0
	if rising and not _was_rising:
		pass
	if rising:
		_apex_y = minf(_apex_y, global_position.y)
	_was_rising = rising


func _move_and_bounce(delta: float) -> void:
	safe_margin = _s("safe_margin")
	var remaining := delta
	var guard := 0

	while remaining > 0.0 and guard < 4:
		guard += 1
		var col := move_and_collide(velocity * remaining)
		if col == null:
			break

		var normal := col.get_normal()
		last_normal = normal
		remaining -= remaining * col.get_travel().length() / maxf((velocity * remaining).length(), 0.001)
		remaining = maxf(remaining, 0.0)

		if normal.y <= _s("ground_normal_threshold"):
			_resolve_ground(normal, delta)
			break  # 1フレームに複数回バウンドさせない
		elif normal.y >= 0.5:
			_resolve_ceiling(normal)
		else:
			_resolve_wall(normal)


func _resolve_ground(normal: Vector2, delta: float) -> void:
	# ── チャージ中（Space押しっぱなし）は跳ねさせず、その場で角度だけ動かせるようにする。
	#    着地スナップより先に抜けないと、静止中は毎フレーム角度を0付近へ戻され続けて
	#    操作不能になる。ただし charge_hold_time が尽きたら、ボタンを押し続けていても
	#    強制的に解除してそのまま通常の反発処理へ流し、貯めた分で発射させる
	if Input.is_action_pressed(&"pogo_charge") and _charge_hold_timer > 0.0:
		if not _charge_pinned:
			# 固定に入る瞬間の進入速度を保存しておく。固定中は速度を毎フレーム殺すので、
			# 保存しないと解除時に反発の元になる勢いが何もない状態になってしまう
			_charge_pinned = true
			_pin_impact_velocity = velocity
		_charge_hold_timer -= delta
		velocity = velocity.slide(normal)
		_apex_y = global_position.y
		return

	# ── 落下判定（反発処理の前に評価する）
	var fall_dist := global_position.y - _apex_y
	if fall_dist >= _s("fall_threshold"):
		fell.emit(fall_dist, global_position)
	_apex_y = global_position.y

	# ── 着地スナップ。スナップした瞬間はスタビライズ補正を一定時間止め、
	#    角度が0度へ引き戻されないようにする（時間経過で強制解除）
	var normal_deg := rad_to_deg(normal.angle_to(UP)) * -1.0
	if absf(tilt_deg - normal_deg) <= _s("landing_snap_angle"):
		tilt_deg = normal_deg
		_snap_hold_timer = _s("landing_snap_hold_time")

	# ── 反発ベクトル合成。チャージ固定明けは、固定中に殺した進入速度の代わりに
	#    接地した瞬間の速度を使う
	var v_in := _pin_impact_velocity if _charge_pinned else velocity
	_charge_pinned = false
	var reflected := v_in.bounce(normal) * _s("restitution")
	var dir := UP.rotated(deg_to_rad(tilt_deg))
	var authority := _s("pogo_authority")
	var out := reflected.lerp(dir * reflected.length(), authority)

	var c := _consume_charge()
	var mult := lerpf(1.0, _s("charge_mult"), c)
	if super_jump_unlocked and c >= 0.999 and _super_cd <= 0.0:
		mult = _s("super_mult")
		_super_cd = _s("super_cooldown")

	out += normal * _s("bounce_add") * mult
	out = out.limit_length(_s("max_bounce_speed"))

	velocity = out
	bounced.emit(out.length(), normal)

	# ── ボタンを離さず押しっぱなしにしていても、発射直後にホールド時間を満タンへ戻す。
	#    こうしないと is_action_just_pressed が二度と発火せず、次の着地でチャージが効かなくなる
	if Input.is_action_pressed(&"pogo_charge"):
		_charge_hold_timer = _s("charge_hold_time")


func _resolve_wall(normal: Vector2) -> void:
	# 壁は跳ね返さない。滑らせて速度を殺す
	velocity = velocity.bounce(normal) * _s("wall_bounce_scale")


func _resolve_ceiling(normal: Vector2) -> void:
	velocity = velocity.slide(normal) * _s("ceiling_keep")
	_apex_y = global_position.y


# ═══════════════════════════════ スキル用モディファイア

## 最終値 = (base + add) * mul
func set_modifier(param: StringName, add: float = 0.0, mul: float = 1.0) -> void:
	_mods[param] = {"add": add, "mul": mul}


func clear_modifiers() -> void:
	_mods.clear()


## パラメータ取得。スキル補正込み
func _s(param: StringName) -> float:
	var base: float = stats.get(param)
	var m: Variant = _mods.get(param)
	if m == null:
		return base
	return (base + float(m["add"])) * float(m["mul"])


# ═══════════════════════════════ 外部から呼ぶユーティリティ

func teleport(to: Vector2) -> void:
	global_position = to
	velocity = Vector2.ZERO
	tilt_deg = 0.0
	charge = 0.0
	_apex_y = to.y


# ═══════════════════════════════ 形状構築

func _apply_shape() -> void:
	if stats == null:
		return

	if _shape_node == null:
		_shape_node = get_node_or_null(^"Body") as CollisionShape2D
	if _shape_node == null:
		_shape_node = CollisionShape2D.new()
		_shape_node.name = "Body"
		add_child(_shape_node)
		if Engine.is_editor_hint() and is_inside_tree():
			_shape_node.owner = get_tree().edited_scene_root

	if _capsule == null:
		_capsule = _shape_node.shape as CapsuleShape2D
	if _capsule == null:
		_capsule = CapsuleShape2D.new()
		_shape_node.shape = _capsule

	_capsule.radius = stats.body_radius
	_capsule.height = maxf(stats.body_height, stats.body_radius * 2.0 + 0.1)
	_shape_node.position = stats.body_offset
	safe_margin = stats.safe_margin


func _on_stats_changed() -> void:
	_apply_shape()


# ═══════════════════════════════ 補助

func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _draw() -> void:
	if not debug_draw or stats == null:
		return
	var h := stats.body_height * 0.5
	var axis := UP.rotated(deg_to_rad(tilt_deg))
	# 傾き軸
	draw_line(-axis * h, axis * h, Color(0.2, 1.0, 0.4), 2.0)
	# 射出方向
	draw_line(Vector2.ZERO, axis * (60.0 + 60.0 * charge), Color(1.0, 0.9, 0.2), 2.0)
	# 直近の接触法線
	draw_line(Vector2.ZERO, last_normal * 40.0, Color(1.0, 0.3, 0.3), 1.0)
	# チャージゲージ
	if charge > 0.0:
		draw_arc(Vector2.ZERO, stats.body_radius + 8.0, -PI * 0.5,
			-PI * 0.5 + TAU * charge, 24, Color(1.0, 0.8, 0.1), 3.0)
