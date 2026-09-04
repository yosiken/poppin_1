class_name TimePassage
extends CanvasLayer
##
## 時間経過の演出。暗転 → キャプション → 明転。
## ステージのクリアデモと、次のステージの冒頭デモの間に挟む。
##
## 設計方針:
##   - 暗転と明転を別のメソッドに分ける。間にステージの差し替えを挟めるので、
##     「暗いうちに場面が変わっていて、明けたら次の場所」という見せ方になる
##   - 暗転から明転までツリーを止めたままにする。止めないと、差し替えた直後の
##     プレイヤーが暗転の裏で落ち始める
##   - 文言はステージごとに変えられる。既定は default_text
##
## 使い方:
##   await time_passage.fade_out("― しばらく後 ―")
##   （ここでステージを差し替える）
##   await time_passage.fade_in()
##
## 操作:
##   Enter … 演出をスキップ（暗転・明転そのものは残す）
##

signal finished

@export_group("Timing")
## 暗転にかける秒数
@export_range(0.05, 3.0, 0.05) var fade_out_time := 0.7
## 明転にかける秒数
@export_range(0.05, 3.0, 0.05) var fade_in_time := 0.7
## キャプションの出入りにかける秒数
@export_range(0.0, 2.0, 0.05) var caption_fade := 0.35
## 点が1つ増えるまでの秒数。時間が流れているように見せるためのもの
@export_range(0.0, 1.0, 0.05) var dot_interval := 0.3
## 点が出そろってから消し始めるまでの秒数
@export_range(0.0, 3.0, 0.05) var hold_time := 0.4
## 始まってからこの秒数は Enter を受け付けない。
## 直前のクリアデモを Enter で飛ばすと、そのキーがこちらまで届いて
## 演出が一瞬で終わってしまうため
@export_range(0.0, 1.0, 0.05) var skip_grace := 0.3

@export_group("Look")
## ステージ側で指定が無いときに出す文言
@export var default_text := "― しばらく後 ―"
## 増えていく点の数
@export_range(0, 8, 1) var dot_count := 3
@export var back_color := Color(0.02, 0.02, 0.04)
@export_range(8, 96, 1) var font_size := 40
@export var text_color := Color(0.86, 0.88, 0.94)

var _back: ColorRect
var _caption_box: VBoxContainer
var _caption: Label
var _dots: Label
## 暗転中かどうか。fade_in を単独で呼ばれても何もしないための目印
var _darkened := false
var _skip := false
## 始まってからの経過秒。skip_grace の判定に使う
var _elapsed := 0.0


# ═══════════════════════════════ ライフサイクル

func _ready() -> void:
	layer = 40                     # イベント(32)より上、ステージ見出し(48)より下
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	visible = false


func _process(delta: float) -> void:
	if _darkened:
		_elapsed += delta


func _unhandled_input(event: InputEvent) -> void:
	if not _darkened or _elapsed < skip_grace or not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	if key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER:
		_skip = true
		get_viewport().set_input_as_handled()


# ═══════════════════════════════ 再生

## 暗転してキャプションを出し、暗いまま戻る。
## 明転は fade_in を呼ぶまで起きない
func fade_out(text := "") -> void:
	if _darkened:
		return
	_darkened = true
	_skip = false
	_elapsed = 0.0
	visible = true
	get_tree().paused = true

	_caption.text = text if text.strip_edges() != "" else default_text
	_caption_box.modulate.a = 0.0
	_dots.text = ""
	_back.color = Color(back_color, 0.0)

	await _tween_wait(_back, ^"color:a", 1.0, fade_out_time)
	await _tween_wait(_caption_box, ^"modulate:a", 1.0, caption_fade)
	for _i in dot_count:
		if _skip:
			break
		_dots.text += "・"
		await _wait(dot_interval)
	await _wait(hold_time)
	await _tween_wait(_caption_box, ^"modulate:a", 0.0, caption_fade)
	_dots.text = ""


## 明転して操作を返す。暗転していなければ何もしない
func fade_in() -> void:
	if not _darkened:
		return
	await _tween_wait(_back, ^"color:a", 0.0, fade_in_time)
	visible = false
	_darkened = false
	_skip = false
	get_tree().paused = false
	finished.emit()


# ═══════════════════════════════ 待ち

## ツリーを止めていても進む Tween。スキップされたら一瞬で終わらせる。
## 暗転・明転そのものは飛ばさない。真っ暗から急に絵が出ると目に痛いため
func _tween_wait(node: Node, prop: NodePath, to: float, time: float) -> void:
	var dur := 0.05 if _skip else maxf(time, 0.01)
	var tw := create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	tw.tween_property(node, prop, to, dur)
	await tw.finished


## ツリーを止めていても進む待ち。スキップされたら途中で抜ける
func _wait(sec: float) -> void:
	var elapsed := 0.0
	while elapsed < sec:
		if _skip:
			return
		await get_tree().process_frame
		elapsed += get_process_delta_time()


# ═══════════════════════════════ 組み立て

func _build_ui() -> void:
	_back = ColorRect.new()
	_back.name = "Back"
	_back.color = Color(back_color, 0.0)
	_back.set_anchors_preset(Control.PRESET_FULL_RECT)
	_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_back)

	var box := VBoxContainer.new()
	box.name = "Caption"
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 18)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)

	_caption = _make_label(font_size)
	box.add_child(_caption)
	_dots = _make_label(font_size)
	box.add_child(_dots)
	# 透明度は文字と点をまとめて動かす。別々に動かすと出入りがずれて見える
	_caption_box = box
	_caption_box.modulate.a = 0.0


func _make_label(size: int) -> Label:
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", text_color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label
