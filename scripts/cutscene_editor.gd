class_name CutsceneEditor
extends Control
##
## イベント（OP/ED・ステージ前後の会話）の演出を、見た目を確かめながら編集するツール。
##
##   godot --path <project> res://scenes/CutsceneEditor.tscn
##
## 左がイベント一覧とコマ一覧と詳細、右が本番と同じ Cutscene によるプレビュー。
## コマを選ぶとその時点の絵が出る。立ち絵と背景は「指定したものだけ変わる」方式なので、
## プレビューは毎回イベントの先頭から積み直している。
##
## 保存すると .tres を書き戻す。台本から作り直しても（tools/make_cutscenes.gd）、
## ここで入れた演出は本文を手掛かりに引き継がれる。逆に本文と話者は台本が正なので、
## ここで直しても次の再生成で戻る。
##
## 操作:
##   F5      … 選択中のイベントを通しで再生
##   Ctrl+S  … 保存
##

const CUTSCENE_DIR := "res://resources/cutscene"
## 背景として並べる画像の置き場。イベント用は event/ の下にある
const BG_DIR := "res://resources/texture/BG"
const EVENT_BG_DIR := "res://resources/texture/BG/event"
## ポップアップ（カットイン）として並べる画像の置き場
const POPUP_DIR := "res://resources/texture/event/popup"
## BGM と効果音の置き場
const BGM_DIR := "res://resources/sound/bgm"
const SFX_DIR := "res://resources/sound"
## 立ち絵として並べる画像の接頭辞。キャラを足したらここに足す
const PORTRAIT_DIR := "res://resources/texture"
const PORTRAIT_PREFIXES: Array[String] = ["OB_", "kanie"]

const PANEL_WIDTH := 560
## プレビューの内寸。本番の画面と同じにしないと立ち絵の位置がずれる
const VIEW_SIZE := Vector2i(1920, 1080)

## 立ち絵・背景の指定は「変更しない / 消す / 画像」の3択なので、
## Texture2D と clear フラグをまとめて1つの OptionButton で扱う
enum Pick { KEEP, CLEAR, TEXTURE }

var _cutscene: Cutscene
var _view: SubViewport
var _view_box: SubViewportContainer
var _preview_slot: Control

var _event_list: ItemList
var _line_list: ItemList
var _status: Label

var _speaker: LineEdit
var _text: TextEdit
var _note: TextEdit
var _speaking: OptionButton
var _left: OptionButton
var _right: OptionButton
var _background: OptionButton
var _popup: OptionButton
var _popup_kind: OptionButton
var _popup_hold: SpinBox
var _bgm: OptionButton
var _bgm_stop: CheckBox
var _bgm_fade: SpinBox
var _sfx: OptionButton
var _slide_in: CheckBox
var _auto_advance: SpinBox
var _delay: SpinBox
var _detail: Control
## そのコマが台本由来か、手で挿したものかの注意書き
var _origin: Label

var _keys: Array[String] = []
var _portraits: Array[Texture2D] = []
var _backgrounds: Array[Texture2D] = []
var _popups: Array[Texture2D] = []
var _bgms: Array[AudioStream] = []
var _sfxs: Array[AudioStream] = []

var _data: CutsceneData
var _path := ""
var _index := -1
var _dirty := false
## プレビューは await を挟むので、選び直しが追い越したときに古い方を捨てる
var _preview_gen := 0
## UI へ値を流し込んでいる最中。変更シグナルでリソースを触り返さないための目印
var _loading := false


func _ready() -> void:
	# 通し再生は get_tree().paused を立てるので、止まらないようにしておく
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_collect_textures()
	_build_ui()
	_refresh_event_list()
	if not _keys.is_empty():
		_event_list.select(0)
		_open(_keys[0])


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode == KEY_F5:
		_play_through()
		accept_event()
	elif key.keycode == KEY_S and key.ctrl_pressed:
		_save()
		accept_event()


# ─────────────────────────────── 素材集め

func _collect_textures() -> void:
	for name in _png_names(PORTRAIT_DIR):
		var base := name.get_basename()
		if base.ends_with("_eye") or base.ends_with("_mouth"):
			continue          # まばたき・口パクの差分は立ち絵そのものではない
		for prefix in PORTRAIT_PREFIXES:
			if base.begins_with(prefix):
				_portraits.append(load("%s/%s" % [PORTRAIT_DIR, name]))
				break
	for name in _png_names(BG_DIR):
		_backgrounds.append(load("%s/%s" % [BG_DIR, name]))
	for name in _png_names(EVENT_BG_DIR):
		_backgrounds.append(load("%s/%s" % [EVENT_BG_DIR, name]))
	for name in _png_names(POPUP_DIR):
		_popups.append(load("%s/%s" % [POPUP_DIR, name]))
	for name in _audio_names(BGM_DIR):
		_bgms.append(load("%s/%s" % [BGM_DIR, name]))
	for name in _audio_names(SFX_DIR):
		_sfxs.append(load("%s/%s" % [SFX_DIR, name]))


func _png_names(dir_path: String) -> PackedStringArray:
	var out: PackedStringArray = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		push_warning("CutsceneEditor: %s を開けません" % dir_path)
		return out
	for name in dir.get_files():
		# 書き出し済みのプロジェクトでは .import が付く。元の名前に戻して拾う
		var clean := name.trim_suffix(".import")
		if clean.get_extension().to_lower() in ["png", "jpg", "jpeg", "webp"]:
			if not out.has(clean):
				out.append(clean)
	out.sort()
	return out


## 置き場にある音源。BGM と効果音で同じ書き方をする
func _audio_names(dir_path: String) -> PackedStringArray:
	var out: PackedStringArray = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		push_warning("CutsceneEditor: %s を開けません" % dir_path)
		return out
	for name in dir.get_files():
		var clean := name.trim_suffix(".import")
		if clean.get_extension().to_lower() in ["ogg", "mp3", "wav"]:
			if not out.has(clean):
				out.append(clean)
	out.sort()
	return out


# ─────────────────────────────── イベント一覧

func _refresh_event_list() -> void:
	_keys = _event_keys()
	_event_list.clear()
	for key in _keys:
		_event_list.add_item(key)


## opening → stage01_intro → stage01_outro → … → ending の順に並べる。
## 単純な名前順だと ending が先頭に来て、台本の流れと合わない
func _event_keys() -> Array[String]:
	var found: Array[String] = []
	var dir := DirAccess.open(CUTSCENE_DIR)
	if dir == null:
		return found
	for name in dir.get_files():
		if name.trim_suffix(".remap").get_extension() == "tres":
			found.append(name.trim_suffix(".remap").get_basename())
	found.sort_custom(func(a: String, b: String) -> bool:
		return _sort_key(a) < _sort_key(b))
	return found


func _sort_key(key: String) -> String:
	if key == "opening":
		return "0"
	if key == "ending":
		return "z"
	return "1" + key


# ─────────────────────────────── 読み書き

func _open(key: String) -> void:
	if _dirty and not _confirm_discard():
		return
	_path = "%s/%s.tres" % [CUTSCENE_DIR, key]
	# キャッシュを避けないと、保存し直したあとに古い中身を拾うことがある
	_data = ResourceLoader.load(_path, "", ResourceLoader.CACHE_MODE_IGNORE) as CutsceneData
	_dirty = false
	if _data == null:
		_set_status("読み込めません: %s" % _path, true)
		return
	_refresh_line_list()
	if not _data.lines.is_empty():
		_line_list.select(0)
		_select_line(0)
	else:
		_select_line(-1)
	_set_status("%s を読み込み（%d コマ）" % [key, _data.lines.size()])


func _save() -> void:
	if _data == null or _path == "":
		return
	# 保存し直すと uid が振り直され、ステージシーンの ext_resource 参照が
	# 古い uid を指したままになる。上書き前の uid を控えて書き戻す
	var uid := _read_uid(_path)
	var err := ResourceSaver.save(_data, _path)
	if err == OK and uid != "":
		_write_uid(_path, uid)
	if err == OK:
		_dirty = false
		_refresh_line_list()
		_set_status("保存しました: %s" % _path)
	else:
		_set_status("保存に失敗: %s" % error_string(err), true)


## 編集を捨てて .tres を読み直す
func _reload() -> void:
	var at := _event_list.get_selected_items()
	if at.is_empty():
		return
	_dirty = false
	_open(_keys[at[0]])


func _confirm_discard() -> bool:
	# 別イベントへ移るときの取りこぼしだけ防ぐ。ダイアログを挟むと
	# 選択が戻せなくなるので、ここでは黙って保存してしまう
	_save()
	return true


# ─────────────────────────────── コマ一覧

func _refresh_line_list() -> void:
	var keep := _line_list.get_selected_items()
	_line_list.clear()
	if _data == null:
		return
	for i in _data.lines.size():
		_line_list.add_item("%2d %s %s" % [i, _mark(_data.lines[i]), _summary(_data.lines[i])])
	if not keep.is_empty() and keep[0] < _line_list.item_count:
		_line_list.select(keep[0])


## 一覧を見ただけで作業の残りが分かるように目印を付ける。
## ＋ = 台本に無い挿したコマ、※ = 台本に演出メモがある、● = 演出を入れ終えた
func _mark(line: CutsceneLine) -> String:
	if line == null:
		return "　　　"
	var fx := line.background != null or line.clear_background \
		or line.clear_left or line.clear_right or not line.slide_in \
		or line.auto_advance > 0.0 or line.delay > 0.0 \
		or line.popup != null \
		or line.bgm != null or line.bgm_stop or line.sfx != null
	return ("＋" if line.inserted else "　") \
		+ ("※" if line.note != "" else "　") \
		+ ("●" if fx else "　")


func _summary(line: CutsceneLine) -> String:
	if line == null:
		return "(空)"
	var body := line.text.replace("\n", " ")
	if body.length() > 26:
		body = body.substr(0, 26) + "…"
	if line.speaker == "":
		return body
	return "[%s] %s" % [line.speaker, body]


func _select_line(index: int) -> void:
	_index = index
	var line := _line() if index >= 0 else null
	_detail.visible = line != null
	if line == null:
		return

	if line.inserted:
		_origin.text = "＋ 手で挿したコマ。本文もここが正で、再生成しても残ります"
		_origin.add_theme_color_override("font_color", Color(0.6, 0.85, 0.95))
	else:
		_origin.text = "台本由来のコマ。話者と本文は台本が正で、ここで直しても再生成で戻ります"
		_origin.add_theme_color_override("font_color", Color(0.65, 0.68, 0.76))

	_loading = true
	_speaker.text = line.speaker
	_text.text = line.text
	_note.text = line.note
	_speaking.selected = line.speaking
	_set_pick(_left, line.left, line.clear_left, _portraits)
	_set_pick(_right, line.right, line.clear_right, _portraits)
	_set_pick(_background, line.background, line.clear_background, _backgrounds)
	_set_simple(_popup, line.popup, _popups)
	_popup_kind.selected = line.popup_kind
	_popup_hold.value = line.popup_hold
	_set_simple(_bgm, line.bgm, _bgms)
	_bgm_stop.button_pressed = line.bgm_stop
	_bgm_fade.value = line.bgm_fade
	_set_simple(_sfx, line.sfx, _sfxs)
	_slide_in.button_pressed = line.slide_in
	_auto_advance.value = line.auto_advance
	_delay.value = line.delay
	_loading = false

	_refresh_preview()


# ─────────────────────────────── コマの挿入・削除・並べ替え

## 選択中のコマの後ろに、台本に無いコマを1つ挟む。
## 本文を空のままにすると、立ち絵や背景だけを切り替える無音の間になる
func _insert_line() -> void:
	if _data == null:
		return
	var line := CutsceneLine.new()
	line.inserted = true
	line.speaking = CutsceneLine.Side.NONE
	var at := _index + 1 if _index >= 0 else _data.lines.size()
	_data.lines.insert(at, line)
	_dirty = true
	_refresh_line_list()
	_line_list.select(at)
	_select_line(at)
	_set_status("%d 番目にコマを挟みました。本文を空のままにすると無音の間になります" % at)


func _delete_line() -> void:
	var line := _line()
	if line == null:
		return
	var was_script := not line.inserted
	var at := _index
	_data.lines.remove_at(at)
	_dirty = true
	_refresh_line_list()
	var next := mini(at, _data.lines.size() - 1)
	if next >= 0:
		_line_list.select(next)
	_select_line(next)
	if was_script:
		_set_status("削除しました。ただし台本由来のコマなので、"
			+ "tools/make_cutscenes.gd を流すと戻ってきます", true)
	else:
		_set_status("削除しました")


func _move_line(step: int) -> void:
	var line := _line()
	if line == null:
		return
	var to := _index + step
	if to < 0 or to >= _data.lines.size():
		return
	_data.lines[_index] = _data.lines[to]
	_data.lines[to] = line
	_dirty = true
	_refresh_line_list()
	_line_list.select(to)
	_select_line(to)
	if not line.inserted:
		_set_status("並べ替えました。ただし台本由来のコマなので、"
			+ "再生成すると台本の順に戻ります", true)


func _line() -> CutsceneLine:
	if _data == null or _index < 0 or _index >= _data.lines.size():
		return null
	return _data.lines[_index]


func _refresh_preview() -> void:
	if _data == null or _index < 0:
		return
	_preview_gen += 1
	var gen := _preview_gen
	await _cutscene.preview(_data, _index)
	if gen != _preview_gen:
		return          # 待っている間に別のコマへ移った


func _play_through() -> void:
	if _data == null:
		return
	_set_status("通し再生中… Space で送り / Enter でスキップ")
	await _cutscene.play(_data)
	_set_status("通し再生おわり")
	_refresh_preview()


# ─────────────────────────────── 編集された値をリソースへ戻す

func _touch() -> void:
	_dirty = true
	_refresh_line_list()
	_refresh_preview()


func _on_speaker_changed(value: String) -> void:
	var line := _line()
	if _loading or line == null:
		return
	line.speaker = value
	_touch()


func _on_text_changed() -> void:
	var line := _line()
	if _loading or line == null:
		return
	line.text = _text.text
	_touch()


func _on_speaking_changed(index: int) -> void:
	var line := _line()
	if _loading or line == null:
		return
	line.speaking = index
	_touch()


func _on_left_changed(index: int) -> void:
	var line := _line()
	if _loading or line == null:
		return
	line.left = _pick_texture(_left, index, _portraits)
	line.clear_left = _left.get_item_id(index) == Pick.CLEAR
	_touch()


func _on_right_changed(index: int) -> void:
	var line := _line()
	if _loading or line == null:
		return
	line.right = _pick_texture(_right, index, _portraits)
	line.clear_right = _right.get_item_id(index) == Pick.CLEAR
	_touch()


func _on_background_changed(index: int) -> void:
	var line := _line()
	if _loading or line == null:
		return
	line.background = _pick_texture(_background, index, _backgrounds)
	line.clear_background = _background.get_item_id(index) == Pick.CLEAR
	_touch()


func _on_popup_changed(index: int) -> void:
	var line := _line()
	if _loading or line == null:
		return
	line.popup = _popups[index - 1] if index >= 1 and index <= _popups.size() else null
	# MISS-XX は誤答カットイン、POP-XX は実況ポップアップ。どちらかは資材リストの
	# 時点で決まっていて、ファイル名がそのまま表している。選んだ時点で種別も
	# 合わせておく。取り違えると視聴者が「今のは間違いなの？」と迷うので、
	# 人が毎回指定する手順にしない。必要なら下の種別欄で手直しできる
	if line.popup:
		var base := line.popup.resource_path.get_file().get_basename()
		line.popup_kind = (CutsceneLine.PopupKind.MISS if base.begins_with("MISS")
			else CutsceneLine.PopupKind.TALK)
		_popup_kind.selected = line.popup_kind
	_touch()


func _on_popup_kind_changed(index: int) -> void:
	var line := _line()
	if _loading or line == null:
		return
	line.popup_kind = index
	_touch()


func _on_popup_hold_changed(value: float) -> void:
	var line := _line()
	if _loading or line == null:
		return
	line.popup_hold = value
	_touch()


func _on_bgm_changed(index: int) -> void:
	var line := _line()
	if _loading or line == null:
		return
	line.bgm = _bgms[index - 1] if index >= 1 and index <= _bgms.size() else null
	_touch()


func _on_bgm_stop_changed(pressed: bool) -> void:
	var line := _line()
	if _loading or line == null:
		return
	line.bgm_stop = pressed
	_touch()


func _on_bgm_fade_changed(value: float) -> void:
	var line := _line()
	if _loading or line == null:
		return
	line.bgm_fade = value
	_touch()


func _on_sfx_changed(index: int) -> void:
	var line := _line()
	if _loading or line == null:
		return
	line.sfx = _sfxs[index - 1] if index >= 1 and index <= _sfxs.size() else null
	_touch()


func _on_slide_changed(pressed: bool) -> void:
	var line := _line()
	if _loading or line == null:
		return
	line.slide_in = pressed
	_touch()


func _on_auto_changed(value: float) -> void:
	var line := _line()
	if _loading or line == null:
		return
	line.auto_advance = value
	_touch()


func _on_delay_changed(value: float) -> void:
	var line := _line()
	if _loading or line == null:
		return
	line.delay = value
	_touch()


# ─────────────────────────────── 「変更しない / 消す / 画像」の3択

func _fill_pick(button: OptionButton, list: Array[Texture2D], clear_label: String) -> void:
	button.add_item("（変更しない）", Pick.KEEP)
	button.add_item(clear_label, Pick.CLEAR)
	for tex in list:
		button.add_item(tex.resource_path.get_file().get_basename(), Pick.TEXTURE)


func _set_pick(button: OptionButton, tex: Texture2D, clear: bool,
		list: Array[Texture2D]) -> void:
	if clear:
		button.selected = 1
		return
	if tex == null:
		button.selected = 0
		return
	var at := list.find(tex)
	# 一覧に無い画像が入っている（置き場の外を指している）場合は触らせない
	button.selected = at + 2 if at >= 0 else 0


## 「出さない」か画像かの2択。立ち絵・背景と違って持ち越しの概念が無い
func _fill_simple(button: OptionButton, list: Array, none_label: String) -> void:
	button.clear()
	button.add_item(none_label)
	for res in list:
		button.add_item(res.resource_path.get_file().get_basename())


func _set_simple(button: OptionButton, res: Resource, list: Array) -> void:
	var at := list.find(res) if res else -1
	button.selected = at + 1 if at >= 0 else 0


func _pick_texture(button: OptionButton, index: int, list: Array[Texture2D]) -> Texture2D:
	if button.get_item_id(index) != Pick.TEXTURE:
		return null
	var at := index - 2
	return list[at] if at >= 0 and at < list.size() else null


# ─────────────────────────────── uid の引き継ぎ

func _read_uid(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var re := RegEx.create_from_string('uid="(uid://[^"]+)"')
	var m := re.search(f.get_line())
	return m.get_string(1) if m else ""


func _write_uid(path: String, uid: String) -> void:
	var text := FileAccess.get_file_as_string(path)
	var head_end := text.find("\n")
	if text.is_empty() or head_end < 0:
		return
	var head := text.substr(0, head_end)
	var re := RegEx.create_from_string('uid="uid://[^"]+"')
	if re.search(head):
		head = re.sub(head, 'uid="%s"' % uid)
	else:
		var close := head.rfind("]")
		if close < 0:
			return
		head = head.substr(0, close) + ' uid="%s"' % uid + head.substr(close)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(head + text.substr(head_end))


# ─────────────────────────────── UI 組み立て

func _build_ui() -> void:
	var back := ColorRect.new()
	back.color = Color(0.09, 0.10, 0.13)
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(back)

	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.add_theme_constant_override("separation", 12)
	add_child(row)

	row.add_child(_build_panel())

	_preview_slot = Control.new()
	_preview_slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preview_slot.clip_contents = true
	_preview_slot.resized.connect(_fit_preview)
	row.add_child(_preview_slot)
	_build_preview()


func _build_preview() -> void:
	# SubViewportContainer は stretch を切ると中身の実寸を要求するので、
	# 1920x1080 のまま描かせて、表示だけ枠に合わせて縮める。
	# 枠に合わせて SubViewport 自体を縮めると、立ち絵の配置が本番とずれる
	_view_box = SubViewportContainer.new()
	_view_box.stretch = false
	_view_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preview_slot.add_child(_view_box)

	_view = SubViewport.new()
	_view.size = VIEW_SIZE
	_view.disable_3d = true
	_view.transparent_bg = false
	_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_view_box.add_child(_view)

	# 背景を指定していないコマでも立ち絵が見えるよう、下地を敷いておく
	var mat := ColorRect.new()
	mat.color = Color(0.13, 0.14, 0.18)
	mat.size = Vector2(VIEW_SIZE)
	_view.add_child(mat)

	_cutscene = Cutscene.new()
	_cutscene.name = "Cutscene"
	# 作りこみ中は台本の〔演出：…〕が見えていたほうがよいので既定で出す。F9 で消せる
	_cutscene.show_notes = true
	_view.add_child(_cutscene)
	_fit_preview()


func _fit_preview() -> void:
	if _view_box == null:
		return
	var avail := _preview_slot.size
	if avail.x <= 0.0 or avail.y <= 0.0:
		return          # レイアウトが決まる前。resized でもう一度呼ばれる
	var k: float = minf(avail.x / float(VIEW_SIZE.x), avail.y / float(VIEW_SIZE.y))
	_view_box.scale = Vector2(k, k)
	_view_box.position = (avail - Vector2(VIEW_SIZE) * k) * 0.5


func _build_panel() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = PANEL_WIDTH
	panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN

	# 縦に短い画面だと詳細まで入りきらないので、パネルの中身は巻けるようにしておく
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(col)

	col.add_child(_heading("イベント"))
	_event_list = ItemList.new()
	_event_list.custom_minimum_size.y = 150
	_event_list.item_selected.connect(func(i: int) -> void: _open(_keys[i]))
	col.add_child(_event_list)

	col.add_child(_heading("コマ　＋挿した / ※演出メモあり / ●演出を入れた"))
	_line_list = ItemList.new()
	_line_list.custom_minimum_size.y = 210
	_line_list.item_selected.connect(_select_line)
	col.add_child(_line_list)

	var edit_row := HBoxContainer.new()
	col.add_child(edit_row)
	_add_button(edit_row, "下に挿入", _insert_line)
	_add_button(edit_row, "削除", _delete_line)
	_add_button(edit_row, "↑", _move_line.bind(-1))
	_add_button(edit_row, "↓", _move_line.bind(1))

	col.add_child(_build_detail())

	var buttons := HBoxContainer.new()
	col.add_child(buttons)
	_add_button(buttons, "保存 (Ctrl+S)", _save)
	_add_button(buttons, "通し再生 (F5)", _play_through)
	_add_button(buttons, "読み直す", _reload)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size.y = 40
	col.add_child(_status)
	return panel


func _build_detail() -> Control:
	_detail = VBoxContainer.new()
	_detail.add_theme_constant_override("separation", 4)

	_detail.add_child(_heading("このコマ"))

	_origin = Label.new()
	_origin.add_theme_font_size_override("font_size", 12)
	_origin.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.add_child(_origin)

	_speaker = LineEdit.new()
	_speaker.text_changed.connect(_on_speaker_changed)
	_detail.add_child(_labeled("話者", _speaker))

	_text = TextEdit.new()
	_text.custom_minimum_size.y = 80
	_text.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_text.text_changed.connect(_on_text_changed)
	_detail.add_child(_labeled("本文 (BBCode可)", _text))

	_note = TextEdit.new()
	_note.custom_minimum_size.y = 56
	_note.editable = false
	_note.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_note.add_theme_color_override("font_readonly_color", Color(1.0, 0.86, 0.45))
	_detail.add_child(_labeled("演出メモ（台本の〔演出：…〕。読み取り専用）", _note))

	_speaking = OptionButton.new()
	for label in ["なし", "左が話す", "右が話す", "両方"]:
		_speaking.add_item(label)
	_speaking.item_selected.connect(_on_speaking_changed)
	_detail.add_child(_labeled("話している側", _speaking))

	_left = OptionButton.new()
	_fill_pick(_left, _portraits, "（消す）")
	_left.item_selected.connect(_on_left_changed)
	_detail.add_child(_labeled("左の立ち絵", _left))

	_right = OptionButton.new()
	_fill_pick(_right, _portraits, "（消す）")
	_right.item_selected.connect(_on_right_changed)
	_detail.add_child(_labeled("右の立ち絵", _right))

	_background = OptionButton.new()
	_fill_pick(_background, _backgrounds, "（消す＝暗転）")
	_background.item_selected.connect(_on_background_changed)
	_detail.add_child(_labeled("背景", _background))

	_popup = OptionButton.new()
	_fill_simple(_popup, _popups, "（出さない）")
	_popup.item_selected.connect(_on_popup_changed)
	_detail.add_child(_labeled("ポップアップ", _popup))

	_popup_kind = OptionButton.new()
	_popup_kind.add_item("青枠（実況／そのまま消える）")
	_popup_kind.add_item("赤枠（誤答／割れる）")
	_popup_kind.item_selected.connect(_on_popup_kind_changed)
	_detail.add_child(_labeled("ポップアップの種別（画像名から自動）", _popup_kind))

	_popup_hold = _spin(0.0, 5.0, 0.1)
	_popup_hold.value_changed.connect(_on_popup_hold_changed)
	_detail.add_child(_labeled("ポップアップ表示 秒 (0=既定)", _popup_hold))

	_bgm = OptionButton.new()
	_fill_simple(_bgm, _bgms, "（変えない）")
	_bgm.item_selected.connect(_on_bgm_changed)
	_detail.add_child(_labeled("BGM", _bgm))

	_bgm_stop = CheckBox.new()
	_bgm_stop.text = "ここでBGMを止める"
	_bgm_stop.toggled.connect(_on_bgm_stop_changed)
	_detail.add_child(_bgm_stop)

	_bgm_fade = _spin(0.0, 5.0, 0.1)
	_bgm_fade.value_changed.connect(_on_bgm_fade_changed)
	_detail.add_child(_labeled("BGMのフェード 秒 (0=既定)", _bgm_fade))

	_sfx = OptionButton.new()
	_fill_simple(_sfx, _sfxs, "（鳴らさない）")
	_sfx.item_selected.connect(_on_sfx_changed)
	_detail.add_child(_labeled("効果音", _sfx))

	_slide_in = CheckBox.new()
	_slide_in.text = "立ち絵を外側からスライドインさせる"
	_slide_in.toggled.connect(_on_slide_changed)
	_detail.add_child(_slide_in)

	_auto_advance = _spin(0.0, 10.0, 0.1)
	_auto_advance.value_changed.connect(_on_auto_changed)
	_detail.add_child(_labeled("自動送り 秒 (0=入力待ち)", _auto_advance))

	_delay = _spin(0.0, 5.0, 0.1)
	_delay.value_changed.connect(_on_delay_changed)
	_detail.add_child(_labeled("このコマの前の間 秒", _delay))
	return _detail


func _heading(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Color(1.0, 0.88, 0.45))
	return label


func _labeled(text: String, control: Control) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 13)
	box.add_child(label)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(control)
	return box


func _spin(min_value: float, max_value: float, step: float) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = min_value
	spin.max_value = max_value
	spin.step = step
	return spin


func _add_button(parent: Control, text: String, action: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(action)
	parent.add_child(button)


func _set_status(text: String, bad := false) -> void:
	_status.text = text
	_status.add_theme_color_override("font_color",
		Color(1.0, 0.5, 0.45) if bad else Color(0.7, 0.85, 0.7))
