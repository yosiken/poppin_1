extends CanvasLayer
class_name PogoTuner
##
## 実行中に PogoStats / PogoVisualStats を触るためのデバッグUI。
##
## 各リソースの @export_range 付き変数（float / int）と bool を走査して
## スライダー・チェックボックスを自動生成するので、
## パラメータを追加してもこのスクリプトは触らなくてよい。
## 見出しの分類だけ各リソースの GROUPS に足すこと。
##
## 操作:
##   F1  … 表示切替
##   Save Preset   … user://pogo_presets/<name>.tres と <name>.visual.tres に書き出し
##   Copy to Clipboard … 現在値を GDScript の代入文として出力（.tres に手で戻す用）
##
## 使い方: Player と同じシーンにこのノードを置き、target に PogoPlayer を指定。
##

@export var target: PogoPlayer
@export var panel_width := 380
@export var start_visible := true

var _stats: PogoStats
var _visual: PogoVisualStats
## 走査対象。{ "key": 保存時の接尾辞, "obj": リソース, "groups": 見出し定義 }
var _sections: Array[Dictionary] = []
var _defaults: Dictionary = {}   ## "section/param" -> 値
var _rows: Dictionary = {}       ## "section/param" -> {control, label, section, param}
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
	_sections.append({"key": "stats", "obj": _stats, "groups": PogoStats.GROUPS})

	# 見た目パラメータ（PlayerVisual.visual_stats）も同じ扱いで並べる
	var visual_node := target.get_node_or_null(^"Visual") as PlayerVisual
	if visual_node and visual_node.visual_stats:
		_visual = visual_node.visual_stats.duplicate(true)
		visual_node.visual_stats = _visual
		_sections.append({"key": "visual", "obj": _visual, "groups": PogoVisualStats.GROUPS})

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

	for section in _sections:
		var current_group := ""
		for prop in section["obj"].get_property_list():
			if not _is_tunable(prop):
				continue
			var group: String = _group_of(section, prop["name"])
			if group != current_group:
				current_group = group
				_add_header(box, "%s / %s" % [section["key"].to_upper(), current_group.to_upper()])
			_add_row(box, section, prop)


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


func _add_row(box: VBoxContainer, section: Dictionary, prop: Dictionary) -> void:
	var param: String = prop["name"]
	var obj: Resource = section["obj"]
	var key := "%s/%s" % [section["key"], param]

	var label := Label.new()
	label.add_theme_font_size_override("font_size", 12)
	box.add_child(label)

	# ラムダにリソースを直接キャプチャさせると、シグナル経由の循環参照になって
	# 終了時にリークとして報告される。キー文字列だけ渡して _rows から引く
	var control: Control
	var is_int := int(prop["type"]) == TYPE_INT
	if int(prop["type"]) == TYPE_COLOR:
		var picker := ColorPickerButton.new()
		picker.color = obj.get(param)
		picker.custom_minimum_size = Vector2(0, 22)
		picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.add_child(picker)
		control = picker
	elif int(prop["type"]) == TYPE_BOOL:
		var check := CheckBox.new()
		check.button_pressed = obj.get(param)
		check.text = "on"
		box.add_child(check)
		control = check
	else:
		var range_info := _parse_range(prop["hint_string"])
		var slider := HSlider.new()
		slider.min_value = range_info.x
		slider.max_value = range_info.y
		slider.step = range_info.z
		slider.value = obj.get(param)
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.add_child(slider)
		control = slider

	_rows[key] = {"control": control, "label": label, "section": section,
		"param": param, "is_int": is_int}
	_update_label(label, key, param, obj.get(param))

	if control is ColorPickerButton:
		(control as ColorPickerButton).color_changed.connect(_on_row_changed.bind(key))
	elif control is CheckBox:
		(control as CheckBox).toggled.connect(_on_row_changed.bind(key))
	else:
		(control as HSlider).value_changed.connect(_on_row_changed.bind(key))


func _on_row_changed(value: Variant, key: String) -> void:
	var row: Dictionary = _rows[key]
	var obj: Resource = row["section"]["obj"]
	match typeof(value):
		TYPE_BOOL, TYPE_COLOR:
			obj.set(row["param"], value)
		_:
			obj.set(row["param"], int(value) if row["is_int"] else float(value))
	obj.emit_changed()          # コリジョン形状などを即再構築させる
	_update_label(row["label"], key, row["param"], value)


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


func _update_label(label: Label, key: String, param: String, value: Variant) -> void:
	var base: Variant = _defaults[key]
	var changed := false
	var shown := ""
	match typeof(value):
		TYPE_COLOR:
			changed = not (value as Color).is_equal_approx(base)
			shown = "#" + (value as Color).to_html(false)
		TYPE_BOOL:
			changed = bool(value) != bool(base)
			shown = "on" if bool(value) else "off"
		_:
			changed = not is_equal_approx(float(value), float(base))
			shown = "%.3f" % float(value)
	label.text = "%s : %s%s" % [param, shown, "  *" if changed else ""]


# ═══════════════════════════════ プロパティ走査

## Resource 自身が持つ組み込みプロパティ（resource_local_to_scene など）を弾くための集合
static var _builtin_props: Dictionary = {}


func _is_tunable(prop: Dictionary) -> bool:
	if not (int(prop["usage"]) & PROPERTY_USAGE_EDITOR):
		return false
	if _builtin_props.is_empty():
		for bp in ClassDB.class_get_property_list("Resource"):
			_builtin_props[bp["name"]] = true
	if _builtin_props.has(prop["name"]):
		return false
	var t := int(prop["type"])
	if t == TYPE_BOOL or t == TYPE_COLOR:
		return true          # チェックボックス / カラーピッカーとして出す
	if t != TYPE_FLOAT and t != TYPE_INT:
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
## 簡易実装として各リソース側の GROUPS 定義を参照する。
func _group_of(section: Dictionary, param: String) -> String:
	var groups: Dictionary = section["groups"]
	for g in groups:
		if param in groups[g]:
			return g
	return "misc"


# ═══════════════════════════════ プリセット入出力

func _capture_defaults() -> void:
	for section in _sections:
		for prop in section["obj"].get_property_list():
			if _is_tunable(prop):
				_defaults["%s/%s" % [section["key"], prop["name"]]] = section["obj"].get(prop["name"])


func _set_control_value(control: Control, value: Variant) -> void:
	if control is ColorPickerButton:
		(control as ColorPickerButton).color = value
	elif control is CheckBox:
		(control as CheckBox).set_pressed_no_signal(bool(value))
	else:
		(control as HSlider).set_value_no_signal(float(value))


func _reset_all() -> void:
	for key in _defaults:
		var row: Dictionary = _rows[key]
		row["section"]["obj"].set(row["param"], _defaults[key])
		_set_control_value(row["control"], _defaults[key])
		_update_label(row["label"], key, row["param"], _defaults[key])
	for section in _sections:
		section["obj"].emit_changed()


## セクションごとに別ファイルへ書き出す。stats は従来どおり <name>.tres
func _preset_path(n: String, section_key: String) -> String:
	if section_key == "stats":
		return "user://pogo_presets/%s.tres" % n
	return "user://pogo_presets/%s.%s.tres" % [n, section_key]


func _save_preset() -> void:
	DirAccess.make_dir_recursive_absolute("user://pogo_presets")
	for section in _sections:
		var path := _preset_path(_name_edit.text, section["key"])
		var err := ResourceSaver.save(section["obj"], path)
		print("[Tuner] save %s -> %s" % [path, error_string(err)])


func _load_preset() -> void:
	for section in _sections:
		var path := _preset_path(_name_edit.text, section["key"])
		if not ResourceLoader.exists(path):
			print("[Tuner] not found: ", path)
			continue
		var loaded: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
		for key in _defaults:
			var row: Dictionary = _rows[key]
			if row["section"]["key"] != section["key"]:
				continue
			var v: Variant = loaded.get(row["param"])
			section["obj"].set(row["param"], v)
			_set_control_value(row["control"], v)
			_update_label(row["label"], key, row["param"], v)
		section["obj"].emit_changed()
		print("[Tuner] load ", path)


## 調整結果を .tres に手で戻すためのテキストを吐く
func _copy_to_clipboard() -> void:
	var lines: PackedStringArray = []
	for key in _defaults:
		var row: Dictionary = _rows[key]
		var v: Variant = row["section"]["obj"].get(row["param"])
		var prefix: String = row["section"]["key"]
		if typeof(v) == TYPE_COLOR:
			if not (v as Color).is_equal_approx(_defaults[key]):
				lines.append("%s.%s = Color(%s)" % [prefix, row["param"],
					"%.3f, %.3f, %.3f" % [v.r, v.g, v.b]])
		elif typeof(v) == TYPE_BOOL:
			if bool(v) != bool(_defaults[key]):
				lines.append("%s.%s = %s" % [prefix, row["param"], str(v)])
		elif not is_equal_approx(float(v), float(_defaults[key])):
			lines.append("%s.%s = %s" % [prefix, row["param"], str(snappedf(float(v), 0.001))])
	var text := "\n".join(lines)
	DisplayServer.clipboard_set(text)
	print("[Tuner] copied %d changed params" % lines.size())
