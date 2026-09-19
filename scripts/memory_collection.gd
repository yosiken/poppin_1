class_name MemoryCollection
extends CanvasLayer
##
## 記憶コレクション画面。取り戻した「10個の大好物」を並べて見せる。
##
## ステージのゴールでアイテムを取ったあと、outro の会話が終わった時点で出す。
## 未取得はシルエット、取得済みは本体。いま取ったものだけ、シルエットから
## 本体へ変わる瞬間を見せてからカウンタを進める。
##
## 毎ステージ後に必ず挟むことで「あと何個で帰れるのか」が常に見えるようにする。
## ST9 を終えた時点で残り1つなのが分かるので、最後のステージの重さが
## 台詞に頼らず伝わる。
##
## 設計方針は Cutscene と同じで、UI のノードはここで実行時に組み立てる。
## 再生中はツリー全体を pause し、このノードだけ PROCESS_MODE_ALWAYS で動かす。
##

signal finished

@export_group("Items")
## 10個の大好物。ステージ1〜10の順に並べる。
## 並び順がそのまま枠の順序と、acquire() に渡すステージ番号に対応する
@export var items: Array[Texture2D] = []

@export_group("Layout")
@export_range(2, 10, 1) var columns := 5
## 1枠の一辺 (px)
@export_range(80, 400, 10) var slot_size := 190
## 枠と枠の間隔 (px)
@export_range(0, 80, 4) var slot_gap := 22

@export_group("Timing")
## 画面全体の出入りにかける秒数
@export_range(0.0, 2.0, 0.05) var fade_time := 0.3
## シルエットから本体へ変わるのにかける秒数
@export_range(0.1, 3.0, 0.05) var reveal_time := 0.7
## 変わったあと、閉じるまでに置く秒数
@export_range(0.0, 5.0, 0.1) var hold_time := 1.4

@export_group("Look")
## 未取得の見え方。取得済みとの差が分かる程度に潰す
@export var silhouette_color := Color(0.05, 0.06, 0.10, 0.92)
## 取り戻した瞬間に枠を光らせる色
@export var flash_color := Color(1.0, 0.95, 0.75)

const TELOP := "記憶を1つ取り戻した"

## 取得済みのステージ番号 (0 起点)
var _acquired: Dictionary[int, bool] = {}
var _slots: Array[TextureRect] = []
var _frames: Array[Panel] = []
var _grid: GridContainer
var _counter: Label
var _telop: Label
var _dim: ColorRect
var _advance := false
var _showing := false


func _ready() -> void:
	layer = 30                      # Cutscene(32) より下。会話の上には被せない
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	visible = false


func _unhandled_input(event: InputEvent) -> void:
	if not _showing:
		return
	var pressed := event.is_action_pressed(&"pogo_charge")
	if not pressed and event is InputEventKey:
		var k := event as InputEventKey
		pressed = k.pressed and not k.echo and (k.keycode == KEY_SPACE
			or k.keycode == KEY_ENTER or k.keycode == KEY_KP_ENTER)
	if not pressed and event is InputEventMouseButton:
		pressed = (event as InputEventMouseButton).pressed
	if pressed:
		_advance = true
		get_viewport().set_input_as_handled()


## そのステージのアイテムを取り戻したことにして、画面を見せる。
## 呼び出し側は await できる
func acquire(index: int) -> void:
	_ensure_slots()
	if index < 0 or index >= _slots.size():
		finished.emit()
		return
	var already := _acquired.has(index)
	_acquired[index] = true

	_showing = true
	_advance = false
	visible = true
	get_tree().paused = true

	_refresh(index if not already else -1)
	_counter.text = "%d / %d" % [_acquired.size() - (0 if already else 1), _slots.size()]
	_telop.visible = false
	_dim.modulate.a = 0.0
	await _fade(1.0)

	if not already:
		await _reveal_slot(index)
	await _wait(hold_time)

	await _fade(0.0)
	visible = false
	_showing = false
	get_tree().paused = false
	finished.emit()


## 取得済みの数
func count() -> int:
	return _acquired.size()


func has(index: int) -> bool:
	return _acquired.has(index)


## 最初からやり直すときに呼ぶ
func reset() -> void:
	_acquired.clear()
	_ensure_slots()
	_refresh(-1)


## items の数だけ枠を用意する。items は Game 側から後で入るので、
## _ready の時点では組めない。数が変わったときだけ組み直す
func _ensure_slots() -> void:
	if _slots.size() == items.size() and not _slots.is_empty():
		return
	for child in _grid.get_children():
		child.queue_free()
	_slots.clear()
	_frames.clear()
	for i in items.size():
		var frame := Panel.new()
		frame.custom_minimum_size = Vector2(slot_size, slot_size)
		frame.add_theme_stylebox_override("panel", _slot_style())
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_grid.add_child(frame)

		var pic := TextureRect.new()
		pic.texture = items[i]
		pic.set_anchors_preset(Control.PRESET_FULL_RECT)
		pic.offset_left = 12
		pic.offset_top = 12
		pic.offset_right = -12
		pic.offset_bottom = -12
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pic.modulate = silhouette_color
		frame.add_child(pic)

		_frames.append(frame)
		_slots.append(pic)
	_counter.text = "%d / %d" % [_acquired.size(), _slots.size()]


## いま取ったものだけシルエットのままにしておく。
## except に -1 を渡すと、取得済みは全部本体で表示する
func _refresh(except: int) -> void:
	for i in _slots.size():
		var lit := _acquired.has(i) and i != except
		_slots[i].modulate = Color.WHITE if lit else silhouette_color
		_frames[i].modulate = Color.WHITE


## シルエット → 本体。枠を光らせ、少し跳ねさせてからカウンタを進める
func _reveal_slot(index: int) -> void:
	var slot := _slots[index]
	var frame := _frames[index]
	slot.pivot_offset = slot.size * 0.5
	frame.pivot_offset = frame.size * 0.5

	var tw := _tween()
	tw.set_parallel(true)
	tw.tween_property(slot, "modulate", Color.WHITE, reveal_time)
	tw.tween_property(frame, "modulate", flash_color, reveal_time * 0.4)
	tw.tween_property(frame, "scale", Vector2(1.12, 1.12), reveal_time * 0.4)
	await tw.finished

	var tw2 := _tween()
	tw2.set_parallel(true)
	tw2.tween_property(frame, "modulate", Color.WHITE, reveal_time * 0.6)
	tw2.tween_property(frame, "scale", Vector2.ONE, reveal_time * 0.6)

	_counter.text = "%d / %d" % [_acquired.size(), _slots.size()]
	_telop.visible = true
	_telop.modulate.a = 0.0
	_tween().tween_property(_telop, "modulate:a", 1.0, reveal_time * 0.5)
	await tw2.finished


func _fade(to: float) -> void:
	var tw := _tween()
	tw.tween_property(_dim, "modulate:a", to, fade_time)
	await tw.finished


## 送り入力が来たら途中で抜ける待ち
func _wait(sec: float) -> void:
	var elapsed := 0.0
	while elapsed < sec:
		if _advance:
			return
		await get_tree().process_frame
		elapsed += get_process_delta_time()


## pause 中でも進む Tween
func _tween() -> Tween:
	var tw := create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	return tw


func _build_ui() -> void:
	_dim = ColorRect.new()
	_dim.name = "Dim"
	_dim.color = Color(0.02, 0.03, 0.06, 0.82)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dim)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 26)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dim.add_child(box)

	_telop = _label(TELOP, 40, Color(1.0, 0.94, 0.78))
	box.add_child(_telop)

	_grid = GridContainer.new()
	_grid.columns = columns
	_grid.add_theme_constant_override("h_separation", slot_gap)
	_grid.add_theme_constant_override("v_separation", slot_gap)
	_grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(_grid)

	_counter = _label("0 / 0", 56, Color(0.92, 0.95, 1.0))
	box.add_child(_counter)


func _slot_style() -> StyleBoxFlat:
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.10, 0.12, 0.18, 0.9)
	st.border_color = Color(0.45, 0.55, 0.75, 0.8)
	st.set_border_width_all(3)
	st.set_corner_radius_all(10)
	return st


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
