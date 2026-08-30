class_name Cutscene
extends CanvasLayer
##
## イベント（OP/ED・ステージ前後の会話）の再生。
##
## 設計方針:
##   - 内容は CutsceneData (.tres) 側に置き、インスペクタで編集する。
##     テキストを1行足すのにシーンを開く必要がない
##   - UI のノードはここで実行時に組み立てる。PogoTuner などと同じ方式
##   - 再生中はツリー全体を pause し、このノードだけ PROCESS_MODE_ALWAYS で動かす
##

signal finished

@export_group("Layout")
## テキストウインドウの高さ (px)
@export_range(80, 600, 10) var window_height := 220
## ウインドウの左右と下の余白 (px)
@export_range(0, 200, 4) var window_margin := 48
## 立ち絵の高さ。画面高に対する比率
@export_range(0.2, 1.0, 0.05) var portrait_height_ratio := 0.75
## 立ち絵を画面端からどれだけ内側に置くか。画面幅に対する比率
@export_range(0.0, 0.5, 0.01) var portrait_inset := 0.06

@export_group("Timing")
## 画像の切り替え・移動にかける秒数
@export_range(0.0, 2.0, 0.05) var fade_time := 0.35
## 1文字あたりの表示秒数。0 で一括表示
@export_range(0.0, 0.2, 0.005) var type_speed := 0.03
## 話していない側の立ち絵の暗さ (1.0 で暗くしない)
@export_range(0.2, 1.0, 0.05) var dim_amount := 0.55
## スライドインの移動量。画面幅に対する比率
@export_range(0.0, 0.5, 0.01) var slide_distance := 0.08

var _bg: TextureRect
var _left: TextureRect
var _right: TextureRect
var _window: PanelContainer
var _name_label: Label
var _text_label: RichTextLabel
var _playing := false
var _advance := false


func _ready() -> void:
	layer = 32
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	visible = false


func _unhandled_input(event: InputEvent) -> void:
	if not _playing:
		return
	var pressed := event.is_action_pressed(&"pogo_charge")
	if not pressed and event is InputEventKey:
		var k := event as InputEventKey
		pressed = k.pressed and not k.echo and (k.keycode == KEY_ENTER or k.keycode == KEY_SPACE)
	if not pressed and event is InputEventMouseButton:
		pressed = (event as InputEventMouseButton).pressed
	if pressed:
		_advance = true
		get_viewport().set_input_as_handled()


## イベントを最後まで再生する。呼び出し側は await できる
func play(data: CutsceneData) -> void:
	if data == null or data.lines.is_empty():
		finished.emit()
		return

	_playing = true
	visible = true
	get_tree().paused = true

	for line in data.lines:
		if line != null:
			await _play_line(line)

	if data.clear_on_finish:
		await _clear_all()

	get_tree().paused = false
	visible = false
	_playing = false
	finished.emit()


func _play_line(line: CutsceneLine) -> void:
	if line.delay > 0.0:
		await _wait(line.delay)

	_apply_visuals(line)

	if line.text.strip_edges() == "":
		_window.visible = false
		await _wait(maxf(fade_time, 0.05))
		return

	_window.visible = true
	_name_label.visible = line.speaker != ""
	_name_label.text = line.speaker
	_text_label.text = line.text

	# 文字送りは visible_characters（整数）で行う。
	# visible_ratio は丸めで、-1（全部出す）はこの環境では末尾1文字が出ないため、
	# 出し切るときも総文字数をそのまま入れる
	_advance = false
	var total := _text_label.get_total_character_count()
	if type_speed > 0.0 and total > 0:
		_text_label.visible_characters = 0
		var shown := 0.0
		while shown < float(total):
			if _advance:
				_advance = false
				break
			await get_tree().process_frame
			shown += get_process_delta_time() / maxf(type_speed, 0.001)
			_text_label.visible_characters = mini(int(shown), total)
	_text_label.visible_characters = total

	if line.auto_advance > 0.0:
		await _wait(line.auto_advance)
	else:
		_advance = false
		while not _advance:
			await get_tree().process_frame
		_advance = false


## pause 中でも進むタイマー待ち
func _wait(sec: float) -> void:
	await get_tree().create_timer(sec, true, false, true).timeout


func _apply_visuals(line: CutsceneLine) -> void:
	if line.clear_background:
		_fade_texture(_bg, null)
	elif line.background:
		_fade_texture(_bg, line.background)

	_update_portrait(_left, line.left, line.clear_left, line.slide_in, true)
	_update_portrait(_right, line.right, line.clear_right, line.slide_in, false)
	_apply_dim(line.speaking)


func _update_portrait(rect: TextureRect, tex: Texture2D, clear: bool,
		slide: bool, is_left: bool) -> void:
	if clear:
		_fade_texture(rect, null)
		return
	if tex == null:
		return
	var appearing := rect.texture == null
	rect.texture = tex
	_layout_portrait(rect, is_left)
	if appearing and slide:
		var offset := _screen().x * slide_distance
		rect.position.x += -offset if is_left else offset
		rect.modulate.a = 0.0
		_tween(rect, "position:x", _portrait_x(rect, is_left), fade_time)
	_tween(rect, "modulate:a", 1.0, fade_time)


func _apply_dim(speaking: int) -> void:
	var left_on := speaking == CutsceneLine.Side.LEFT or speaking == CutsceneLine.Side.BOTH
	var right_on := speaking == CutsceneLine.Side.RIGHT or speaking == CutsceneLine.Side.BOTH
	if speaking == CutsceneLine.Side.NONE:
		left_on = true
		right_on = true
	_tween_value(_left, 1.0 if left_on else dim_amount)
	_tween_value(_right, 1.0 if right_on else dim_amount)


func _fade_texture(rect: TextureRect, tex: Texture2D) -> void:
	if tex == null:
		var t := _tween(rect, "modulate:a", 0.0, fade_time)
		if t:
			t.finished.connect(func() -> void:
				if rect.modulate.a <= 0.01:
					rect.texture = null)
		return
	if rect.texture == null:
		rect.texture = tex
		rect.modulate.a = 0.0
		_tween(rect, "modulate:a", 1.0, fade_time)
		return
	# 既に何か出ているときは一度落としてから差し替える（簡易クロスフェード）
	var t2 := _tween(rect, "modulate:a", 0.0, fade_time * 0.5)
	if t2:
		t2.finished.connect(func() -> void:
			rect.texture = tex
			_tween(rect, "modulate:a", 1.0, fade_time * 0.5))


## pause 中でも進む Tween を作る
func _tween(node: Node, prop: String, to: Variant, time: float) -> Tween:
	if node == null:
		return null
	var tw := create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	tw.tween_property(node, prop, to, time)
	return tw


func _tween_value(rect: TextureRect, value: float) -> void:
	if rect == null or rect.texture == null:
		return
	_tween(rect, "modulate:v", value, fade_time)


func _clear_all() -> void:
	_window.visible = false
	for r in [_left, _right, _bg]:
		_fade_texture(r, null)
	await _wait(fade_time)


func _screen() -> Vector2:
	return Vector2(
		ProjectSettings.get_setting("display/window/size/viewport_width", 1920),
		ProjectSettings.get_setting("display/window/size/viewport_height", 1080))


func _build_ui() -> void:
	_bg = TextureRect.new()
	_bg.name = "Bg"
	_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg.modulate.a = 0.0
	add_child(_bg)

	_left = _make_portrait("PortraitLeft", true)
	_right = _make_portrait("PortraitRight", false)

	_window = PanelContainer.new()
	_window.name = "Window"
	_window.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_window.offset_left = window_margin
	_window.offset_right = -window_margin
	_window.offset_top = -window_height - window_margin
	_window.offset_bottom = -window_margin
	_window.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_window)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.07, 0.11, 0.88)
	style.border_color = Color(0.55, 0.65, 0.85, 0.7)
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(20)
	_window.add_theme_stylebox_override("panel", style)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_window.add_child(box)

	_name_label = Label.new()
	_name_label.add_theme_font_size_override("font_size", 26)
	_name_label.add_theme_color_override("font_color", Color(1.0, 0.88, 0.45))
	box.add_child(_name_label)

	_text_label = RichTextLabel.new()
	_text_label.bbcode_enabled = true
	_text_label.scroll_active = false
	_text_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_text_label.add_theme_font_size_override("normal_font_size", 24)
	box.add_child(_text_label)

	_window.visible = false


func _make_portrait(node_name: String, is_left: bool) -> TextureRect:
	var rect := TextureRect.new()
	rect.name = node_name
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 立ち絵はドット絵で、画面高に合わせて3倍以上に拡大される。
	# 既定の線形補間だとぼやけるので最近傍にする
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	rect.modulate.a = 0.0
	add_child(rect)
	_layout_portrait(rect, is_left)
	return rect


func _layout_portrait(rect: TextureRect, is_left: bool) -> void:
	var screen := _screen()
	# ウインドウより上に収まる高さに抑える。画面外へ突き抜けると頭が切れる
	var available := screen.y - window_height - window_margin * 1.5
	var h := minf(screen.y * portrait_height_ratio, available)
	var w := h * 0.6
	if rect.texture:
		var ts := rect.texture.get_size()
		if ts.y > 0.0:
			w = h * (ts.x / ts.y)
	rect.size = Vector2(w, h)
	rect.position = Vector2(_portrait_x(rect, is_left), available - h)


func _portrait_x(rect: TextureRect, is_left: bool) -> float:
	var screen_w := _screen().x
	var inset := screen_w * portrait_inset
	return inset if is_left else screen_w - inset - rect.size.x
