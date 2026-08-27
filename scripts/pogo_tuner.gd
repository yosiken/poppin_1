extends CanvasLayer
class_name PogoTuner
##
## 実行中に PogoStats を触るためのデバッグUI。
##
## PogoStats の @export_range 付き変数を走査して自動でスライダーを生成するので、
## パラメータを追加してもこのスクリプトは触らなくてよい。
##
## 操作:
##   F1  … 表示切替
##   Save Preset   … user://pogo_presets/<name>.tres に書き出し
##   Copy to Clipboard … 現在値を GDScript の代入文として出力（.tres に手で戻す用）
##
## 使い方: Player と同じシーンにこのノードを置き、target に PogoPlayer を指定。
##

@export var target: PogoPlayer
@export var panel_width := 380
@export var start_visible := true

var _stats: PogoStats
var _defaults: Dictionary = {}
var _rows: Dictionary = {}   ## param -> {slider, label}
var _root: PanelContainer
var _name_edit: LineEdit


func _ready() -> void:
	layer = 128
	if target == null:
		target = get_tree().get_first_node_in_group(&"player") as PogoPlayer
	if target == null or target.stats == null:
		push_warning("PogoTuner: target / stats が未設定です")
		return

	# 元の .tres を汚さないように複製して差し込む
	_stats = target.stats.duplicate(true)
	target.stats = _stats
	_capture_defaults()
	_build_ui()
	_root.visible = start_visible


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F1 and _root:
			_root.visible = not _root.visible
			get_viewport().set_input_as_handled()


# ═══════════════════════════════ UI構築

func _build_ui() -> void:
	_root = PanelContainer.new()
	_root.custom_minimum_size = Vector2(panel_width, 0)
	_root.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_root.position = Vector2(-panel_width - 12, 12)
	_root.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	add_child(_root)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(panel_width, 640)
	_root.add_child(scroll)

	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 2)
	scroll.add_child(box)

	_add_header(box, "POGO TUNER  [F1]")
	_build_actions(box)

	var current_group := ""
	for prop in _stats.get_property_list():
		if not _is_tunable(prop):
			continue
		var group: String = _group_of(prop["name"])
		if group != current_group:
			current_group = group
			_add_header(box, current_group.to_upper())
		_add_slider(box, prop)


func _build_actions(box: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	box.add_child(row)

	_name_edit = LineEdit.new()
	_name_edit.text = "tuned"
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_name_edit)

	_add_button(row, "Save", _save_preset)
	_add_button(row, "Load", _load_preset)

	var row2 := HBoxContainer.new()
	box.add_child(row2)
	_add_button(row2, "Reset", _reset_all)
	_add_button(row2, "Copy to Clipboard", _copy_to_clipboard)


func _add_slider(box: VBoxContainer, prop: Dictionary) -> void:
	var param: String = prop["name"]
	var range_info := _parse_range(prop["hint_string"])

	var label := Label.new()
	label.add_theme_font_size_override("font_size", 12)
	box.add_child(label)

	var slider := HSlider.new()
	slider.min_value = range_info.x
	slider.max_value = range_info.y
	slider.step = range_info.z
	slider.value = _stats.get(param)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(slider)

	slider.value_changed.connect(func(v: float) -> void:
		_stats.set(param, v)
		_stats.emit_changed()          # コリジョン形状などを即再構築させる
		_update_label(label, param, v)
	)

	_rows[param] = {"slider": slider, "label": label}
	_update_label(label, param, slider.value)


func _add_header(box: VBoxContainer, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", Color(0.55, 0.85, 1.0))
	box.add_child(l)


func _add_button(parent: Node, text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	parent.add_child(b)


func _update_label(label: Label, param: String, value: float) -> void:
	var base: float = _defaults[param]
	var mark := "" if is_equal_approx(base, value) else "  *"
	label.text = "%s : %.3f%s" % [param, value, mark]


# ═══════════════════════════════ プロパティ走査

func _is_tunable(prop: Dictionary) -> bool:
	if not (int(prop["usage"]) & PROPERTY_USAGE_EDITOR):
		return false
	if int(prop["type"]) != TYPE_FLOAT:
		return false
	return int(prop["hint"]) == PROPERTY_HINT_RANGE


func _parse_range(hint: String) -> Vector3:
	var parts := hint.split(",")
	var mn := 0.0
	var mx := 1.0
	var st := 0.01
	if parts.size() >= 1: mn = float(parts[0])
	if parts.size() >= 2: mx = float(parts[1])
	if parts.size() >= 3: st = float(parts[2])
	return Vector3(mn, mx, st)


## @export_group はプロパティリストに区切りとして現れないため、
## 命名規則ではなく宣言順のグループ見出しを別途持つ。
## 簡易実装として PogoStats 側の GROUPS 定義を参照する。
func _group_of(param: String) -> String:
	for g in PogoStats.GROUPS:
		if param in PogoStats.GROUPS[g]:
			return g
	return "misc"


# ═══════════════════════════════ プリセット入出力

func _capture_defaults() -> void:
	for prop in _stats.get_property_list():
		if _is_tunable(prop):
			_defaults[prop["name"]] = _stats.get(prop["name"])


func _reset_all() -> void:
	for param in _defaults:
		_stats.set(param, _defaults[param])
		var row: Dictionary = _rows[param]
		row["slider"].set_value_no_signal(_defaults[param])
		_update_label(row["label"], param, _defaults[param])
	_stats.emit_changed()


func _preset_path(n: String) -> String:
	return "user://pogo_presets/%s.tres" % n


func _save_preset() -> void:
	DirAccess.make_dir_recursive_absolute("user://pogo_presets")
	var err := ResourceSaver.save(_stats, _preset_path(_name_edit.text))
	print("[Tuner] save %s -> %s" % [_name_edit.text, error_string(err)])


func _load_preset() -> void:
	var path := _preset_path(_name_edit.text)
	if not ResourceLoader.exists(path):
		print("[Tuner] not found: ", path)
		return
	var loaded: PogoStats = ResourceLoader.load(path, "PogoStats", ResourceLoader.CACHE_MODE_IGNORE)
	for param in _defaults:
		_stats.set(param, loaded.get(param))
		var row: Dictionary = _rows[param]
		row["slider"].set_value_no_signal(_stats.get(param))
		_update_label(row["label"], param, _stats.get(param))
	_stats.emit_changed()


## 調整結果を .tres に手で戻すためのテキストを吐く
func _copy_to_clipboard() -> void:
	var lines: PackedStringArray = []
	for param in _defaults:
		var v: float = _stats.get(param)
		if not is_equal_approx(v, _defaults[param]):
			lines.append("stats.%s = %s" % [param, str(snappedf(v, 0.001))])
	var text := "\n".join(lines)
	DisplayServer.clipboard_set(text)
	print("[Tuner] copied %d changed params" % lines.size())
