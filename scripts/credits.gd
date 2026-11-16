class_name Credits
extends CanvasLayer
##
## クリア後のスタッフクレジット。
##
## 設計方針:
##   - 中身は CreditsData (.tres) に置き、インスペクタで編集する。
##     人を1人足すのにシーンを開く必要がない。イベント(Cutscene)と同じ考え方
##   - UI のノードはここで実行時に組み立てる。Cutscene / TutorialUI と同じ方式
##   - 1画面に1人ずつ、順に出す。流れる(スクロール)のではなく、出して消す
##   - 再生中はツリー全体を pause し、このノードだけ PROCESS_MODE_ALWAYS で動かす
##
## 操作:
##   Space / クリック / チャージボタン … 次の人へ
##   Enter                          … クレジット全体をスキップ
##

signal finished

## 背景の上に敷く暗幕の濃さ。絵の上でも名前が読めるようにする
const DIM := Color(0.03, 0.04, 0.07, 0.45)
## 名前の後ろに敷く帯。明るい背景でも白い字が沈まないようにする。
## 上下は透明へ抜くので、はっきりした境目は出ない
const BAND := Color(0.0, 0.0, 0.02, 0.55)
## 帯の高さ (px)。画面の中央を上下にこれだけ覆う
const BAND_HEIGHT := 420.0
const ROLE_COLOR := Color(1.0, 0.86, 0.35)
const NAME_COLOR := Color(0.96, 0.97, 1.0)

## 曲を鳴らすプレイヤー。Game が自分のものを渡す。null なら自前で作る
var bgm_player: AudioStreamPlayer

var _data: CreditsData
var _back: ColorRect
var _bg: TextureRect
var _dim: ColorRect
var _band: TextureRect
var _box: VBoxContainer
var _role: Label
var _name: Label
var _closing: Label
var _playing := false
## Enter。クレジット全体を飛ばす
var _skip := false
## Space / クリック。今出している1画面を切り上げる
var _advance := false
var _bgm_tween: Tween


func _init() -> void:
	# イベント(32)や記憶コレクション(48)より上、クリア表示(64)より下
	layer = 56
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false


func _ready() -> void:
	_build()


func is_playing() -> bool:
	return _playing


## 今出している1画面の文字。確認用
func current_text() -> String:
	if not _playing:
		return ""
	if _closing.visible:
		return _closing.text
	return _name.text if _name.text != "" else _role.text


# ═══════════════════════════════ 再生

func play(data: CreditsData) -> void:
	if _playing:
		return
	if data == null or data.entries.is_empty():
		push_warning("Credits: 出すものが無い（CreditsData が空）")
		finished.emit()
		return

	_data = data
	_playing = true
	_skip = false
	_advance = false
	visible = true
	get_tree().paused = true

	_back.color = Color(0.0, 0.0, 0.0, 1.0)
	_bg.texture = data.background
	_bg.modulate.a = 0.0
	_dim.modulate.a = 0.0
	_band.modulate.a = 0.0
	_role.modulate.a = 0.0
	_name.modulate.a = 0.0
	_closing.modulate.a = 0.0
	_closing.visible = false
	_box.visible = true

	_start_bgm(data.bgm)
	await _fade(_bg, 1.0, data.open_fade)
	_dim.modulate.a = 1.0
	_band.modulate.a = 1.0

	for e in data.entries:
		if _skip:
			break
		if e == null:
			continue
		await _show_entry(e)

	if not _skip and data.closing.strip_edges() != "":
		await _show_closing(data.closing, data.closing_hold)

	# 残りを飛ばして来ても、暗転と曲の始末はいつもどおり行う
	_skip = false
	_stop_bgm(data.bgm_fade)
	_box.visible = false
	_band.modulate.a = 0.0
	await _fade(_bg, 0.0, data.open_fade)
	_dim.modulate.a = 0.0

	get_tree().paused = false
	visible = false
	_playing = false
	finished.emit()


func _show_entry(entry: CreditEntry) -> void:
	_closing.visible = false
	if entry.person == "":
		# 名前が無い＝見出しだけの画面。小さい字で出すと見出しに見えない
		_role.visible = false
		_name.text = entry.role
		_name.visible = entry.role != ""
	else:
		_role.text = entry.role
		_role.visible = entry.role != ""
		_name.text = entry.person
		_name.visible = true
	_advance = false

	await _fade_pair(1.0, _data.fade)
	await _wait(_data.hold_of(entry))
	await _fade_pair(0.0, _data.fade)


func _show_closing(text: String, hold: float) -> void:
	_role.visible = false
	_name.visible = false
	_closing.text = text
	_closing.visible = true
	_advance = false

	await _fade(_closing, 1.0, _data.fade)
	await _wait(hold)
	await _fade(_closing, 0.0, _data.fade)


func _fade_pair(to: float, sec: float) -> void:
	# 役割と名前は一緒に出入りさせる。別々だとちらついて読みにくい
	if sec <= 0.0 or _skip:
		_role.modulate.a = to
		_name.modulate.a = to
		return
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_role, "modulate:a", to, sec)
	tw.tween_property(_name, "modulate:a", to, sec)
	await tw.finished


func _fade(node: CanvasItem, to: float, sec: float) -> void:
	if sec <= 0.0 or _skip:
		node.modulate.a = to
		return
	var tw := create_tween()
	tw.tween_property(node, "modulate:a", to, sec)
	await tw.finished


## 出しておく時間だけ待つ。送りかスキップが来たらそこで切り上げる。
## ツリーを止めているので、タイマーではなくフレームを数える
func _wait(sec: float) -> void:
	var left := sec
	while left > 0.0:
		if _skip or _advance:
			_advance = false
			return
		await get_tree().process_frame
		left -= get_process_delta_time()


# ═══════════════════════════════ 入力

func _unhandled_input(event: InputEvent) -> void:
	if not _playing:
		return

	# Enter はクレジット全体のスキップ。送りとは別扱いにする（イベントと同じ）
	if event is InputEventKey:
		var key := event as InputEventKey
		var is_enter := key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER
		if key.pressed and not key.echo and is_enter:
			_skip = true
			_advance = true          # 待っているループも抜けさせる
			get_viewport().set_input_as_handled()
			return

	# 送りは Space / クリック / チャージボタン
	var pressed := event.is_action_pressed(&"pogo_charge")
	if not pressed and event is InputEventKey:
		var k := event as InputEventKey
		pressed = k.pressed and not k.echo and k.keycode == KEY_SPACE
	if not pressed and event is InputEventMouseButton:
		pressed = (event as InputEventMouseButton).pressed
	if not pressed:
		return
	_advance = true
	get_viewport().set_input_as_handled()


# ═══════════════════════════════ 曲

func _ensure_bgm_player() -> AudioStreamPlayer:
	if bgm_player == null or not is_instance_valid(bgm_player):
		bgm_player = AudioStreamPlayer.new()
		bgm_player.name = "CreditsBgm"
		bgm_player.bus = &"BGM"
		bgm_player.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(bgm_player)
	return bgm_player


func _start_bgm(stream: AudioStream) -> void:
	if stream == null:
		return
	var p := _ensure_bgm_player()
	_kill_bgm_tween()
	p.volume_db = 0.0
	p.stream = stream
	p.play()


func _stop_bgm(fade: float) -> void:
	if bgm_player == null or not is_instance_valid(bgm_player) or not bgm_player.playing:
		return
	var p := bgm_player
	_kill_bgm_tween()
	if fade <= 0.0:
		p.stop()
		p.volume_db = 0.0
		return
	_bgm_tween = create_tween()
	_bgm_tween.tween_property(p, "volume_db", -40.0, fade)
	_bgm_tween.tween_callback(func() -> void:
		p.stop()
		p.volume_db = 0.0)


func _kill_bgm_tween() -> void:
	if _bgm_tween and _bgm_tween.is_valid():
		_bgm_tween.kill()
	_bgm_tween = null


# ═══════════════════════════════ 組み立て

func _build() -> void:
	_back = ColorRect.new()
	_back.color = Color(0.0, 0.0, 0.0, 1.0)
	_back.set_anchors_preset(Control.PRESET_FULL_RECT)
	_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_back)

	_bg = TextureRect.new()
	_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg.modulate.a = 0.0
	add_child(_bg)

	_dim = ColorRect.new()
	_dim.color = DIM
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dim.modulate.a = 0.0
	add_child(_dim)

	_band = TextureRect.new()
	_band.texture = _band_texture()
	_band.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_band.stretch_mode = TextureRect.STRETCH_SCALE
	_band.anchor_left = 0.0
	_band.anchor_right = 1.0
	_band.anchor_top = 0.5
	_band.anchor_bottom = 0.5
	_band.offset_top = -BAND_HEIGHT * 0.5
	_band.offset_bottom = BAND_HEIGHT * 0.5
	_band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_band.modulate.a = 0.0
	add_child(_band)

	_box = VBoxContainer.new()
	_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_box.add_theme_constant_override("separation", 18)
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_box)

	_role = _add_label(28, ROLE_COLOR)
	_name = _add_label(64, NAME_COLOR)
	_closing = _add_label(48, ROLE_COLOR)
	_closing.visible = false


## 中央だけ暗く、上下へ透明に抜ける帯。境目が線に見えないようにする
func _band_texture() -> GradientTexture2D:
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.38, 0.62, 1.0])
	grad.colors = PackedColorArray([
		Color(BAND.r, BAND.g, BAND.b, 0.0), BAND, BAND,
		Color(BAND.r, BAND.g, BAND.b, 0.0)])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.width = 8
	tex.height = 256
	tex.fill_from = Vector2(0.0, 0.0)
	tex.fill_to = Vector2(0.0, 1.0)
	return tex


func _add_label(font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	l.add_theme_constant_override("shadow_offset_y", 3)
	l.modulate.a = 0.0
	_box.add_child(l)
	return l
