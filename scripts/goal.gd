@tool
class_name Goal
extends Area2D
##
## 到達するとゲームクリアになるゴール。
##
## 設計方針:
##   - 判定形状は子の Sprite2D のテクスチャから実行時に組み立てる。
##     画像を差し替えてもシーンを触らずに追従する（@tool なのでエディタでも即反映）
##   - クリアの見せ方は built_in_overlay を false にすれば差し替えられる。
##     その場合は reached シグナルを拾って自前のUIを出すこと
##

## 到達した瞬間に飛ぶ。引数は開始からの経過秒
signal reached(clear_time: float)

# ─────────────────────────────── 設定
## 判定範囲。スプライトの見た目に対する倍率。
## 1.0 だと絵の端をかすめただけでクリアになるので、既定では少し内側に絞る
@export_range(0.1, 2.0, 0.05) var hit_scale := 0.7:
	set(value):
		hit_scale = value
		_apply_shape()

## クリア時に組み込みのオーバーレイを出すか
@export var built_in_overlay := true

# ─────────────────────────────── 内部状態
var _sprite: Sprite2D
var _shape_node: CollisionShape2D
var _rect: RectangleShape2D
var _reached := false
## 経過時間。実時間ではなく物理ステップの積算で測る
var _elapsed := 0.0
var _overlay: CanvasLayer


# ═══════════════════════════════ ライフサイクル

func _ready() -> void:
	_apply_shape()
	set_physics_process(not Engine.is_editor_hint())
	if Engine.is_editor_hint():
		return
	body_entered.connect(_on_body_entered)


## クリアタイムは実時間ではなく物理ステップの積算で測る。
##   - 表示FPSや処理落ちでタイムが変わらない（非力なマシンが不利にならない）
##   - ツリーを止めている間は進まないので、イベント・見出し・復帰の暗転が
##     自動的にタイムから除外される
func _physics_process(delta: float) -> void:
	if _reached:
		return
	_elapsed += delta


func _unhandled_input(event: InputEvent) -> void:
	if not _reached or Engine.is_editor_hint():
		return
	if event.is_action_pressed(&"pogo_retry"):
		get_viewport().set_input_as_handled()
		get_tree().reload_current_scene()


# ═══════════════════════════════ 到達判定

## デバッグ用。触れたときと同じ処理をそのまま走らせる。
## 判定を迂回した別処理にすると、デバッグと本番で挙動がずれるので通常経路を使う
func force_reach(body: Node2D) -> void:
	_on_body_entered(body)


func _on_body_entered(body: Node2D) -> void:
	if _reached or not body.is_in_group(&"player"):
		return
	_reached = true

	var clear_time := _elapsed
	print("[Goal] クリア %.2f 秒" % clear_time)

	# プレイヤーを止める。velocity を残すと見た目側が振れ続ける
	var player := body as PogoPlayer
	if player:
		player.velocity = Vector2.ZERO
		player.set_physics_process(false)

	reached.emit(clear_time)
	if built_in_overlay:
		_show_overlay(clear_time)


# ═══════════════════════════════ 形状構築

## Sprite2D のテクスチャサイズから判定用の矩形を組み立てる
func _apply_shape() -> void:
	# エクスポートの setter はシーン読み込み中にも呼ばれる。その時点では
	# 子ノードがまだ無いので、Sprite が見つからない間は何もしない
	if not is_inside_tree():
		return
	if _sprite == null:
		_sprite = get_node_or_null(^"Sprite") as Sprite2D
	if _sprite == null or _sprite.texture == null:
		return

	# 名前ではなく型で既存の形状を探す。名前で引くと、取りこぼしたときに
	# Godot が "Hit2" のような別名で二つ目を作ってしまう
	if _shape_node == null or not is_instance_valid(_shape_node):
		for c in get_children():
			if c is CollisionShape2D:
				_shape_node = c as CollisionShape2D
				break
	if _shape_node == null:
		_shape_node = CollisionShape2D.new()
		_shape_node.name = "Hit"
		add_child(_shape_node)
		if Engine.is_editor_hint() and get_tree():
			_shape_node.owner = get_tree().edited_scene_root

	if _rect == null:
		_rect = _shape_node.shape as RectangleShape2D
	if _rect == null:
		_rect = RectangleShape2D.new()
		_shape_node.shape = _rect

	# スプライトシートの場合、見えているのは1コマぶんなので frame の大きさで測る
	var frame_size := _sprite.texture.get_size()
	frame_size.x /= float(maxi(_sprite.hframes, 1))
	frame_size.y /= float(maxi(_sprite.vframes, 1))
	_rect.size = frame_size * _sprite.scale * hit_scale
	_shape_node.position = _sprite.position


# ═══════════════════════════════ クリア表示

func _show_overlay(clear_time: float) -> void:
	_overlay = CanvasLayer.new()
	_overlay.layer = 64          # チューナー(128)より下、ゲーム画面より上
	add_child(_overlay)

	var back := ColorRect.new()
	back.color = Color(0.05, 0.06, 0.09, 0.55)
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(back)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 16)
	_overlay.add_child(box)

	_add_label(box, "GAME CLEAR", 64, Color(1.0, 0.92, 0.4))
	_add_label(box, "TIME  %.2f" % clear_time, 32, Color(0.9, 0.94, 1.0))
	_add_label(box, "[R] リトライ", 20, Color(0.65, 0.7, 0.8))


func _add_label(parent: Node, text: String, size: int, color: Color) -> void:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
