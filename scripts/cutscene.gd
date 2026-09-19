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
## 操作:
##   Space / クリック / チャージボタン … 送り（表示途中なら残りを一括表示）
##   Enter                          … このイベントを最後までスキップ
##

signal finished

@export_group("Layout")
## テキストウインドウの高さ (px)
@export_range(80, 600, 10) var window_height := 220
## ウインドウの左右と下の余白 (px)
@export_range(0, 200, 4) var window_margin := 48
## 立ち絵の高さ。画面高に対する比率（画像の透明な余白を含めたキャンバス基準）
@export_range(0.2, 1.2, 0.05) var portrait_height_ratio := 0.85
## 立ち絵を画面端からどれだけ内側に置くか。画面幅に対する比率
@export_range(0.0, 0.5, 0.01) var portrait_inset := 0.06
## 立ち絵の幅の上限。画面幅に対する比率。
## 横長の絵は高さを揃えると横幅が伸びて画面を占領してしまうので、幅で頭打ちにする
@export_range(0.1, 0.8, 0.01) var portrait_max_width_ratio := 0.34

@export_group("Timing")
## 画像の切り替え・移動にかける秒数
@export_range(0.0, 2.0, 0.05) var fade_time := 0.35
## 1文字あたりの表示秒数。0 で一括表示
@export_range(0.0, 0.2, 0.005) var type_speed := 0.03
## 話していない側の立ち絵の暗さ (1.0 で暗くしない)
@export_range(0.2, 1.0, 0.05) var dim_amount := 0.55
## スライドインの移動量。画面幅に対する比率
@export_range(0.0, 0.5, 0.01) var slide_distance := 0.08

@export_group("Portrait Animation")
## 立ち絵のまばたきと口パク。"OB_a.png" に対して "OB_a_eye.png"（閉じ目）と
## "OB_a_mouth.png"（閉じ口）があるキャラだけ動く
@export var animate_portrait := true
## まばたきの間隔 (秒)。この範囲でばらつかせる
@export var blink_interval := Vector2(2.5, 6.0)
## まぶたを閉じている時間 (秒)
@export_range(0.02, 0.5, 0.01) var blink_hold := 0.12
## 口パクの開閉間隔 (秒)
@export_range(0.02, 0.5, 0.01) var talk_step := 0.09

@export_group("Debug")
## 台本の〔演出：…〕を画面の上に出す。まだ実装していない演出の確認用で、
## 製品の見た目ではない。再生中に F9 で切り替えられる
@export var show_notes := false

@export_group("Test")
## 改行とページ送りのたびに、話している側の立ち絵を次のパターンへ送る（動作確認用）。
## パターンは "OB_a.png" のような末尾1文字の連番から自動で集める。
## まばたき・口パクを入れたので既定では止めてある
@export var rotate_speaker_portrait := false

var _bg: TextureRect
var _left: TextureRect
var _right: TextureRect
var _used_rects: Dictionary[Texture2D, Rect2] = {}
## そのコマで指定された立ち絵。ローテーションで差し替えても、
## 次の切り替え先を決める基準はこちらを見る
var _base_left: Texture2D
var _base_right: Texture2D
var _variant_step := 0
var _variant_cache: Dictionary = {}
## 立ち絵ごとのまばたき残り時間。[rect] -> 次に閉じるまでの秒数
var _blink_timer: Dictionary[TextureRect, float] = {}
var _blink_close: Dictionary[TextureRect, float] = {}
var _talking: Dictionary[TextureRect, bool] = {}
var _talk_timer := 0.0
var _part_cache: Dictionary = {}
var _window: PanelContainer
var _name_label: Label
var _text_label: RichTextLabel
var _note_box: PanelContainer
var _note_label: Label
## いま出しているコマ。F9 で表示を切り替えたときに出し直すために覚えておく
var _current: CutsceneLine
var _playing := false
var _advance := false
var _skip := false
## エディタからのプレビュー中。まばたき・口パクだけは動かしたいので
## _playing とは別に持つ（_playing を立てると送りの入力まで拾ってしまう）
var _previewing := false


func _ready() -> void:
	layer = 32
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	visible = false


func _unhandled_input(event: InputEvent) -> void:
	# F9 は演出メモの表示切替。編集ツールのプレビュー中にも効かせたいので
	# _playing の判定より先に見る
	var f9 := event as InputEventKey
	if f9 and f9.pressed and not f9.echo and f9.keycode == KEY_F9:
		if _playing or _previewing:
			show_notes = not show_notes
			_show_note(_current)
			get_viewport().set_input_as_handled()
		return

	if not _playing:
		return

	# Enter はイベント全体のスキップ。送りとは別扱いにする
	if event is InputEventKey:
		var key := event as InputEventKey
		var is_enter := key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER
		if key.pressed and not key.echo and is_enter:
			_skip = true
			_advance = true          # 待機中のループも抜けさせる
			get_viewport().set_input_as_handled()
			return

	# 送りは Space / クリック / チャージボタン
	var pressed := event.is_action_pressed(&"pogo_charge")
	if not pressed and event is InputEventKey:
		var k := event as InputEventKey
		pressed = k.pressed and not k.echo and k.keycode == KEY_SPACE
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
	_previewing = false
	_skip = false
	visible = true
	get_tree().paused = true

	for line in data.lines:
		if _skip:
			break
		if line != null:
			await _play_line(line)

	_skip = false                    # 以降の待ちは飛ばさない
	if data.clear_on_finish:
		await _clear_all()

	get_tree().paused = false
	visible = false
	_playing = false
	finished.emit()


## イベント編集ツール用。指定したコマの見た目を、入力待ちも文字送りもせずに作る。
##
## 立ち絵と背景は「指定したものだけ変わる」方式なので、途中のコマを単独で当てても
## 正しい絵にならない。必ず先頭から index まで積み直す。
## play() と違ってツリーは止めないので、編集UIは動いたままになる
func preview(data: CutsceneData, index: int) -> void:
	if data == null or data.lines.is_empty():
		return
	_previewing = true
	visible = true

	# 積み直しの途中経過は見せたくないので、フェードを切って一気に当てる
	var saved := fade_time
	fade_time = 0.0
	await _clear_all()
	var last := clampi(index, 0, data.lines.size() - 1)
	for i in last + 1:
		if data.lines[i]:
			_apply_visuals(data.lines[i])
	fade_time = saved

	var line := data.lines[last]
	_show_note(line)
	if line == null or line.text.strip_edges() == "":
		_window.visible = false
		return
	_window.visible = true
	_name_label.visible = line.speaker != ""
	_name_label.text = line.speaker
	_text_label.text = line.text
	_text_label.visible_characters = _text_label.get_total_character_count()
	_set_talking(line.speaking)      # 誰が喋っているか分かるよう口は動かしておく


## プレビューを終う
func end_preview() -> void:
	_previewing = false
	_set_talking(CutsceneLine.Side.NONE)
	visible = false


func _play_line(line: CutsceneLine) -> void:
	_show_note(line)
	if line.delay > 0.0:
		await _wait(line.delay)
	if _skip:
		return

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
	_set_talking(line.speaking)
	var total := _text_label.get_total_character_count()
	if type_speed > 0.0 and total > 0:
		# 改行を跨いだところで立ち絵を送るため、BBCode を除いた本文で位置を拾っておく
		var breaks := _newline_positions()
		var next_break := 0
		_text_label.visible_characters = 0
		var shown := 0.0
		while shown < float(total):
			if _advance:
				_advance = false
				break
			if _skip:
				return
			await get_tree().process_frame
			shown += get_process_delta_time() / maxf(type_speed, 0.001)
			_text_label.visible_characters = mini(int(shown), total)
			while next_break < breaks.size() and _text_label.visible_characters > breaks[next_break]:
				next_break += 1
				_rotate_speaker(line.speaking)
	_text_label.visible_characters = total
	_set_talking(CutsceneLine.Side.NONE)      # 出し終わったら口を閉じる

	if line.auto_advance > 0.0:
		await _wait(line.auto_advance)
	else:
		_advance = false
		while not _advance and not _skip:
			await get_tree().process_frame
		_advance = false


## 本文中の改行の位置。visible_characters と突き合わせるため、
## タグを除いた表示上の文字数で数える
func _newline_positions() -> PackedInt32Array:
	var result: PackedInt32Array = []
	var parsed := _text_label.get_parsed_text()
	for i in parsed.length():
		if parsed[i] == "\n":
			result.append(i)
	return result


## pause 中でも進む待ち。スキップされたら途中で抜ける
func _wait(sec: float) -> void:
	var elapsed := 0.0
	while elapsed < sec:
		if _skip:
			return
		await get_tree().process_frame
		elapsed += get_process_delta_time()


## スキップに影響されない待ち。終了時のフェードなど、必ず見せたいものに使う
func _wait_fixed(sec: float) -> void:
	await get_tree().create_timer(sec, true, false, true).timeout


func _apply_visuals(line: CutsceneLine) -> void:
	if line.clear_background:
		_fade_texture(_bg, null)
	elif line.background:
		_fade_texture(_bg, line.background)

	_update_portrait(_left, line.left, line.clear_left, line.slide_in, true)
	_update_portrait(_right, line.right, line.clear_right, line.slide_in, false)
	if line.clear_left:
		_base_left = null
	elif line.left:
		_base_left = line.left
	if line.clear_right:
		_base_right = null
	elif line.right:
		_base_right = line.right
	_apply_dim(line.speaking)
	_rotate_speaker(line.speaking)


func _update_portrait(rect: TextureRect, tex: Texture2D, clear: bool,
		slide: bool, is_left: bool) -> void:
	if clear:
		_fade_texture(rect, null)
		return
	if tex == null:
		return
	var appearing := rect.texture == null
	rect.texture = tex
	_update_parts(rect)
	_layout_portrait(rect, is_left)
	if appearing and slide:
		var offset := _screen().x * slide_distance
		rect.position.x += -offset if is_left else offset
		rect.modulate.a = 0.0
		_tween(rect, "position:x", _portrait_x(rect, is_left), fade_time)
	_tween(rect, "modulate:a", 1.0, fade_time)


func _set_talking(speaking: int) -> void:
	var both := speaking == CutsceneLine.Side.BOTH
	_talking[_left] = both or speaking == CutsceneLine.Side.LEFT
	_talking[_right] = both or speaking == CutsceneLine.Side.RIGHT


func _process(delta: float) -> void:
	if not (_playing or _previewing) or not animate_portrait:
		return
	_talk_timer += delta
	for rect in [_left, _right]:
		_update_blink(rect, delta)
		_update_mouth(rect)


## まばたき。閉じている間だけ差分を出す
func _update_blink(rect: TextureRect, delta: float) -> void:
	if rect == null or rect.texture == null:
		return
	var eye: TextureRect = rect.get_node_or_null(^"Eye")
	if eye == null or eye.texture == null:
		return
	var closing: float = _blink_close.get(rect, 0.0)
	if closing > 0.0:
		closing -= delta
		_blink_close[rect] = closing
		eye.visible = closing > 0.0
		if closing <= 0.0:
			_blink_timer[rect] = randf_range(blink_interval.x, blink_interval.y)
		return
	var wait: float = _blink_timer.get(rect, randf_range(blink_interval.x, blink_interval.y)) - delta
	_blink_timer[rect] = wait
	if wait <= 0.0:
		_blink_close[rect] = blink_hold
		eye.visible = true


## 口パク。喋っている間だけ開閉を繰り返し、黙っているときは閉じたままにする
func _update_mouth(rect: TextureRect) -> void:
	if rect == null or rect.texture == null:
		return
	var mouth: TextureRect = rect.get_node_or_null(^"Mouth")
	if mouth == null or mouth.texture == null:
		return
	if not _talking.get(rect, false):
		mouth.visible = true          # 差分が閉じ口。出しっぱなしで口を閉じておく
		return
	mouth.visible = int(_talk_timer / maxf(talk_step, 0.01)) % 2 == 0


## 立ち絵に対応する目・口の差分を差し込む。無ければ非表示のままにする
func _update_parts(rect: TextureRect) -> void:
	for part in ["Eye", "Mouth"]:
		var node: TextureRect = rect.get_node_or_null(NodePath(part))
		if node == null:
			continue
		node.texture = _part_texture(rect.texture, part.to_lower())
		node.visible = false


## "OB_a.png" から "OB_a_eye.png" のような差分を引く
func _part_texture(tex: Texture2D, suffix: String) -> Texture2D:
	if tex == null:
		return null
	var key := "%s#%s" % [tex.resource_path, suffix]
	if _part_cache.has(key):
		return _part_cache[key]
	var path := "%s_%s.%s" % [tex.resource_path.get_basename(), suffix,
		tex.resource_path.get_extension()]
	var found: Texture2D = load(path) if ResourceLoader.exists(path) else null
	_part_cache[key] = found
	return found


## 話している側の立ち絵を次のパターンへ送る。
## レイアウトは差し替え前のまま使う。パターンは同じキャンバスに描かれている前提で、
## 測り直すと中身の大きさの違いで立ち位置が跳ねてしまうため
func _rotate_speaker(speaking: int) -> void:
	if not rotate_speaker_portrait:
		return
	_variant_step += 1
	var both := speaking == CutsceneLine.Side.BOTH
	if both or speaking == CutsceneLine.Side.LEFT:
		_apply_variant(_left, _base_left)
	if both or speaking == CutsceneLine.Side.RIGHT:
		_apply_variant(_right, _base_right)


func _apply_variant(rect: TextureRect, base: Texture2D) -> void:
	if rect == null or base == null or rect.texture == null:
		return
	var list := _variants_of(base)
	if list.size() > 1:
		rect.texture = list[_variant_step % list.size()]
		_update_parts(rect)


## 末尾1文字が連番になっている絵をまとめて集める。
## "OB_a.png" を渡すと OB_a〜OB_e が、途切れたところで打ち切られる。
## 絵を追加すればそのまま輪に入るので、増やすたびに設定を触らなくてよい
func _variants_of(tex: Texture2D) -> Array[Texture2D]:
	var path := tex.resource_path
	if _variant_cache.has(path):
		var cached: Array[Texture2D] = _variant_cache[path]
		return cached

	var list: Array[Texture2D] = []
	var base_path := path.get_basename()
	var ext := path.get_extension()
	if base_path.length() >= 2 and base_path[base_path.length() - 2] == "_":
		var stem := base_path.substr(0, base_path.length() - 1)
		for i in 26:
			var p := "%s%s.%s" % [stem, char("a".unicode_at(0) + i), ext]
			if not ResourceLoader.exists(p):
				break
			list.append(load(p))
	if list.is_empty():
		list.append(tex)
	_variant_cache[path] = list
	return list


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
	_current = null
	if _note_box:
		_note_box.visible = false
	for r in [_left, _right, _bg]:
		_fade_texture(r, null)
	await _wait_fixed(fade_time)


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
	_build_note_box()


## 〔演出：…〕を出す枠。本文のウインドウとぶつからないよう画面の上に置く
func _build_note_box() -> void:
	_note_box = PanelContainer.new()
	_note_box.name = "Note"
	_note_box.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_note_box.offset_left = window_margin
	_note_box.offset_right = -window_margin
	_note_box.offset_top = window_margin
	_note_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_note_box.visible = false
	add_child(_note_box)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.09, 0.02, 0.85)
	style.border_color = Color(1.0, 0.82, 0.30, 0.8)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(14)
	_note_box.add_theme_stylebox_override("panel", style)

	_note_label = Label.new()
	_note_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note_label.add_theme_font_size_override("font_size", 22)
	_note_label.add_theme_color_override("font_color", Color(1.0, 0.86, 0.45))
	_note_box.add_child(_note_label)


func _show_note(line: CutsceneLine) -> void:
	_current = line
	if _note_box == null:
		return
	var text := line.note if line else ""
	_note_label.text = text
	_note_box.visible = show_notes and text != ""


func _make_portrait(node_name: String, is_left: bool) -> TextureRect:
	var rect := TextureRect.new()
	rect.name = node_name
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 立ち絵は表示サイズより大きい絵を縮小して使う。
	# 最近傍で縮小すると輪郭がガタつくので線形補間にする
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	rect.modulate.a = 0.0
	add_child(rect)
	# 目と口の差分は立ち絵の子として重ねる。位置・大きさ・暗転が親のものを
	# そのまま引き継ぐので、レイアウトを二重に計算しなくてよい
	_add_overlay(rect, "Eye")
	_add_overlay(rect, "Mouth")
	_layout_portrait(rect, is_left)
	return rect


func _add_overlay(parent: TextureRect, node_name: String) -> void:
	var rect := TextureRect.new()
	rect.name = node_name
	rect.expand_mode = parent.expand_mode
	rect.stretch_mode = parent.stretch_mode
	rect.texture_filter = parent.texture_filter
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.visible = false
	parent.add_child(rect)


func _layout_portrait(rect: TextureRect, is_left: bool) -> void:
	var screen := _screen()
	# ウインドウより上を立ち絵の置き場にする
	var available := screen.y - window_height - window_margin * 1.5
	if rect.texture == null:
		var fallback := minf(screen.y * portrait_height_ratio, available)
		rect.size = Vector2(fallback * 0.6, fallback)
		rect.position = Vector2(_portrait_x(rect, is_left), available - fallback)
		return

	var ts := rect.texture.get_size()
	var used := _used_rect(rect.texture)
	var s := screen.y * portrait_height_ratio / ts.y
	# 頭が切れないよう、絵の中身がウインドウより上に収まる大きさに抑える
	if used.size.y * s > available:
		s = available / used.size.y
	# 1枚が画面幅を占領しないよう頭打ちにする。
	# 中身ではなくキャンバス基準で見るので、絵の周りの余白の取り方で
	# キャラごとの大きさ（人物は大きく、小さい生き物は小さく）を作れる
	var max_w := screen.x * portrait_max_width_ratio
	if ts.x * s > max_w:
		s = max_w / ts.x

	rect.size = ts * s
	rect.position = Vector2(_portrait_x(rect, is_left), available - used.end.y * s)


## 透明な余白の量は絵ごとに違うので、キャンバスの端ではなく
## 中身の端を基準に置く。そうしないと絵を差し替えるたびに立ち位置がずれる
func _portrait_x(rect: TextureRect, is_left: bool) -> float:
	var screen_w := _screen().x
	var inset := screen_w * portrait_inset
	var used := Rect2(Vector2.ZERO, rect.size)
	if rect.texture:
		var ts := rect.texture.get_size()
		if ts.x > 0.0 and ts.y > 0.0:
			used = _used_rect(rect.texture)
			used.position *= rect.size.x / ts.x
			used.size *= rect.size.x / ts.x
	if is_left:
		return inset - used.position.x
	return screen_w - inset - used.end.x


## 不透明部分の矩形 (テクスチャのピクセル単位)。
## get_image() は重いのでテクスチャごとに一度だけ測って使い回す
func _used_rect(tex: Texture2D) -> Rect2:
	if _used_rects.has(tex):
		return _used_rects[tex]
	var result := Rect2(Vector2.ZERO, tex.get_size())
	var img := tex.get_image()
	if img:
		var used := img.get_used_rect()
		if used.size.x > 0 and used.size.y > 0:
			result = Rect2(used)
	_used_rects[tex] = result
	return result
