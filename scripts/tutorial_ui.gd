class_name TutorialUI
extends CanvasLayer
##
## チュートリアルの画面表示。
##   - 区画の最中     : 上に操作説明（出しっぱなし）
##   - アイテムに触れた: 下にメッセージボックス
##   - ボタンを押した  : 「やり直す / 次へ」の選択
##
## ポーズは掛けない。アイテムに触れた時点で Game 側がプレイヤーを止めるので、
## 止めなくても進まない。止めないぶん、クリアのモーションがそのまま動く
##

## 選択が決まった。retry=true なら同じ区画をやり直す
signal answered(retry: bool)

const PANEL_BG := Color(0.07, 0.08, 0.12, 0.92)
const ACCENT := Color(1.0, 0.86, 0.35)
const TEXT := Color(0.94, 0.96, 1.0)

enum Phase { CLOSED, MESSAGE, CHOICE }

var _phase := Phase.CLOSED
var _hint_panel: PanelContainer
var _hint_label: Label
var _box: PanelContainer
var _header: Label
var _body: Label
var _prompt: Label
var _choice: HBoxContainer
var _choice_hint: Label
var _retry_button: Button
var _next_button: Button


func _init() -> void:
	layer = 60
	# 落下復帰の暗転中などツリーが止まっているときも操作できるようにする
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	_build_hint()
	_build_box()


func is_open() -> bool:
	return _phase != Phase.CLOSED


# ═══════════════════════════════ 操作説明（区画の最中）

## 区画の始めに出す操作説明。空文字なら消す
func show_hint(text: String) -> void:
	if _hint_panel == null:
		return
	_hint_label.text = text
	_hint_panel.visible = text != ""


func hide_hint() -> void:
	show_hint("")


## 今出している操作説明。出していなければ空
func hint_text() -> String:
	if _hint_panel == null or not _hint_panel.visible:
		return ""
	return _hint_label.text


# ═══════════════════════════════ メッセージ

## header 例 "チュートリアル 1/6 クリア"、next_label 例 "次へ進む"
func open(header: String, body: String, next_label: String) -> void:
	_header.text = header
	_body.text = body
	_next_button.text = next_label
	_prompt.visible = true
	_choice.visible = false
	_choice_hint.visible = false
	_box.visible = true
	_phase = Phase.MESSAGE


func close() -> void:
	_phase = Phase.CLOSED
	if _box:
		_box.visible = false


func _input(event: InputEvent) -> void:
	match _phase:
		Phase.MESSAGE:
			_input_message(event)
		Phase.CHOICE:
			_input_choice(event)


func _input_message(event: InputEvent) -> void:
	var pressed := event.is_action_pressed(&"ui_accept") \
		or event.is_action_pressed(&"pogo_charge") \
		or (event is InputEventMouseButton and (event as InputEventMouseButton).pressed)
	if not pressed:
		return
	get_viewport().set_input_as_handled()
	advance()


## 選択は A D（＝遊んでいるときの傾けるキー）でも動かせるようにする。
## 矢印キーとスティックは ui_left / ui_right としてボタン側が自前で拾うので、
## ここで見るのは pogo_left / pogo_right だけでよい
func _input_choice(event: InputEvent) -> void:
	if _retry_button == null or _retry_button.disabled:
		return                       # 選択が出た直後の1フレームは受け付けない
	if event.is_action_pressed(&"pogo_left"):
		_retry_button.grab_focus()
	elif event.is_action_pressed(&"pogo_right"):
		_next_button.grab_focus()
	else:
		return
	get_viewport().set_input_as_handled()


## メッセージを読み終えて選択へ進む。入力からも自動テストからも同じ道を通る
func advance() -> void:
	if _phase != Phase.MESSAGE:
		return
	_phase = Phase.CHOICE
	_prompt.visible = false
	_choice.visible = true
	_choice_hint.visible = true
	_retry_button.disabled = true
	_next_button.disabled = true
	# メッセージを送ったキーがそのままボタンを押さないよう1フレーム空ける
	await get_tree().process_frame
	if _phase != Phase.CHOICE:
		return
	_retry_button.disabled = false
	_next_button.disabled = false
	_next_button.grab_focus()


## 選択を決める。retry=true で同じ区画をやり直す
func choose(retry: bool) -> void:
	if _phase != Phase.CHOICE:
		return
	close()
	answered.emit(retry)


# ═══════════════════════════════ 組み立て

func _build_hint() -> void:
	_hint_panel = PanelContainer.new()
	_hint_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_hint_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_hint_panel.offset_top = 28
	_hint_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint_panel.add_theme_stylebox_override("panel", _style(PANEL_BG, ACCENT))
	_hint_panel.visible = false
	add_child(_hint_panel)

	var margin := MarginContainer.new()
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	_hint_panel.add_child(margin)

	_hint_label = Label.new()
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.add_theme_font_size_override("font_size", 30)
	_hint_label.add_theme_color_override("font_color", TEXT)
	margin.add_child(_hint_label)


func _build_box() -> void:
	_box = PanelContainer.new()
	_box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_box.offset_bottom = -64
	_box.custom_minimum_size = Vector2(1180, 0)
	_box.add_theme_stylebox_override("panel", _style(PANEL_BG, ACCENT))
	_box.visible = false
	add_child(_box)

	var margin := MarginContainer.new()
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 44)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 32)
	_box.add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 18)
	margin.add_child(col)

	_header = Label.new()
	_header.add_theme_font_size_override("font_size", 30)
	_header.add_theme_color_override("font_color", ACCENT)
	col.add_child(_header)

	_body = Label.new()
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_theme_font_size_override("font_size", 34)
	_body.add_theme_color_override("font_color", TEXT)
	col.add_child(_body)

	_prompt = Label.new()
	_prompt.text = "▼  ボタン / SPACE で続ける"
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_prompt.add_theme_font_size_override("font_size", 22)
	_prompt.add_theme_color_override("font_color", Color(0.68, 0.73, 0.84))
	col.add_child(_prompt)

	_choice = HBoxContainer.new()
	_choice.alignment = BoxContainer.ALIGNMENT_CENTER
	_choice.add_theme_constant_override("separation", 36)
	_choice.visible = false
	col.add_child(_choice)

	_retry_button = _add_button(_choice, "もう一度やる", func() -> void: choose(true))
	_next_button = _add_button(_choice, "次へ進む", func() -> void: choose(false))
	# 左右キー／スティックでも選べるようにしておく
	_retry_button.focus_neighbor_right = _next_button.get_path()
	_next_button.focus_neighbor_left = _retry_button.get_path()

	_choice_hint = Label.new()
	_choice_hint.text = "A D  /  ← →  で選ぶ    SPACE で決定"
	_choice_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_choice_hint.add_theme_font_size_override("font_size", 22)
	_choice_hint.add_theme_color_override("font_color", Color(0.68, 0.73, 0.84))
	_choice_hint.visible = false
	col.add_child(_choice_hint)


func _add_button(parent: Node, text: String, callback: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(320, 68)
	b.add_theme_font_size_override("font_size", 30)
	b.pressed.connect(callback)
	parent.add_child(b)
	return b


func _style(bg: Color, border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = Color(border.r, border.g, border.b, 0.75)
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(14)
	return sb
