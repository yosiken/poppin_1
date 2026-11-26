@tool
class_name TutorialItem
extends Area2D
##
## チュートリアル区画のクリア判定アイテム。触れるとその区画は合格。
##
## ゴール(Goal)と別物にしている理由:
##   - Goal はステージ1本ぶんのクリア。タイム送信・ランキング・記憶コレクションに繋がる
##   - こちらは区画ひとつぶんの合格判定。メッセージを出して次の区画へ渡すだけで、
##     記録にも進行にも影響しない
##
## 絵は子に "Sprite"(Sprite2D) を置けばそれを使う。無ければ仮の丸を自分で描くので、
## 絵が無いうちからレベルデザインを進められる
##

## プレイヤーが触れた
signal touched(body: Node2D)

## 判定半径 (px)
@export var radius := 80.0:
	set(value):
		radius = value
		_apply_shape()
		queue_redraw()

## 仮表示の色。絵を入れたら使われない
@export var color := Color(1.0, 0.86, 0.35)

var _shape_node: CollisionShape2D
var _circle: CircleShape2D
var _taken := false
## 有効化してから1物理フレーム経つまで判定しない。
## 区画を切り替えた瞬間に前の立ち位置で計算された接触通知が遅れて届くため
var _armed := false


func _ready() -> void:
	collision_mask = 2          # プレイヤー(レイヤー2)だけ見る。地形には反応させない
	monitorable = false
	_apply_shape()
	set_process(true)
	if Engine.is_editor_hint():
		return
	body_entered.connect(_on_body_entered)
	set_physics_process(true)


func _process(_delta: float) -> void:
	if _sprite() == null:
		queue_redraw()           # 仮表示を少し脈打たせて、拾う物だと分かるようにする


func _physics_process(_delta: float) -> void:
	# 無効な区画のアイテムは何もしない（monitoring が切れている間は
	# get_overlapping_bodies() を呼べない）
	if _taken or not monitoring:
		return
	if not _armed:
		_armed = true
		# 有効化した瞬間に既に重なっていると body_entered は飛ばない。
		# 1フレーム置いてから自分で見る
		for b in get_overlapping_bodies():
			_on_body_entered(b)
		return


# ═══════════════════════════════ 有効/無効

## その区画を遊んでいる間だけ true。それ以外の区画のアイテムは判定しない。
## 見た目は薄く残す（次にどこへ向かうのかが分かるように）
func set_active(on: bool) -> void:
	monitoring = on
	modulate.a = 1.0 if on else 0.3
	if on:
		_taken = false
		_armed = false


## やり直し用。拾った印を落とす
func reset() -> void:
	_taken = false
	_armed = false


func is_taken() -> bool:
	return _taken


## デバッグ用。触れたときと同じ経路を通す
func force_take(body: Node2D) -> void:
	if _taken:
		return
	_taken = true
	touched.emit(body)


func _on_body_entered(body: Node2D) -> void:
	if _taken or not monitoring or not body.is_in_group(&"player"):
		return
	if not _armed:
		return
	# 本当に届いているかを座標でも見る。区画切り替え直後の遅れた通知を弾く
	if body.global_position.distance_to(global_position) > radius + 72.0:
		return
	_taken = true
	touched.emit(body)


# ═══════════════════════════════ 形状と仮表示

func _apply_shape() -> void:
	if not is_inside_tree() or Engine.is_editor_hint():
		return
	if _shape_node == null or not is_instance_valid(_shape_node):
		for c in get_children():
			if c is CollisionShape2D:
				_shape_node = c as CollisionShape2D
				break
	if _shape_node == null:
		_shape_node = CollisionShape2D.new()
		_shape_node.name = "Hit"
		add_child(_shape_node)
	_circle = _shape_node.shape as CircleShape2D
	if _circle == null:
		_circle = CircleShape2D.new()
		_shape_node.shape = _circle
	_circle.radius = radius


func _sprite() -> Sprite2D:
	return get_node_or_null(^"Sprite") as Sprite2D


## 絵が無いときの仮表示。輪っかと中身で「触る物」だと見せる
func _draw() -> void:
	if _sprite() != null:
		return
	var t := float(Time.get_ticks_msec()) * 0.001
	var pulse := 1.0 + 0.06 * sin(t * 3.0)
	draw_circle(Vector2.ZERO, radius * pulse, Color(color.r, color.g, color.b, 0.28))
	draw_arc(Vector2.ZERO, radius * pulse, 0.0, TAU, 48, color, 6.0, true)
	draw_circle(Vector2.ZERO, radius * 0.42, color)
