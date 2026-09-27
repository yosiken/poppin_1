class_name Title
extends Control
##
## 仮のタイトル画面。
##
## メニュー: NEW GAME / CONTINUE / オプション / スコアランキング
##
## CONTINUE はセーブ (SaveGame) があるときだけ押せる。
## NEW GAME はセーブを消すので、消す前に確認を挟む
## オプション: BGMボリューム / SEボリューム / プレイヤー名
##
## Settings.test_mode（オープニング等のデモ短縮・スコア送信抑制）は開発用の
## 隠しスイッチとして残しているが、この画面からは操作できない。
## タイトル自体をスキップする効果は過去に持たせていたが、一度ONにすると
## オプション画面（OFFに戻す唯一の手段）へも二度とたどり着けなくなる事故が
## 実際に起きたため廃止した。会話を飛ばしたいだけなら Enter でその場の
## カットシーンをスキップできる（cutscene.gd）のでそちらを使うこと

const MAIN_SCENE := "res://scenes/Main.tscn"
const REPLAY_SCENE := "res://scenes/ReplayViewer.tscn"
const PANEL_COLOR := Color(0.06, 0.07, 0.11, 0.92)
const BORDER_COLOR := Color(0.55, 0.65, 0.85, 0.7)
const ACCENT_COLOR := Color(1.0, 0.92, 0.4)

## タイトルでキャラクターを踊らせるか。
## 今は非表示にしている。戻したくなったら true にするだけでよい
## （表示まわりの実装は _add_dancer() にそのまま残してある）
const SHOW_DANCER := false

## タイトルで踊らせるモデルとモーション。本編と同じプレイヤーを使う。
## モーションは別リグ由来だが、PlayerVisual が載せ替えてくれる
const DANCER_MODEL := preload("res://resources/model/player_8.blend")
const DANCER_POSE := preload("res://resources/pogo_pose_default.tres")
## モーション素材はリポジトリに含めていない（.gitignore 参照）ので実行時に読む。
## preload だと無いときにこのスクリプトごとコンパイルできなくなる
const DANCER_CLIP_PATH := "res://resources/model/Twist Dance.fbx"
## 本編と同じ見え方にするため、ゲーム側の調整値をそのまま借りる
const DANCER_STATS := preload("res://resources/pogo_visual_default.tres")
## タイトルでの表示サイズ。camera_view_units ぶんを何pxで描くか
const DANCER_HEIGHT_PX := 840.0
## 画面右端からキャラクター中心までの距離 (px)
const DANCER_MARGIN_X := 340.0
## 画面中央からの上下のずらし (px)。カメラは足元より上を見ているので少し上げる
const DANCER_OFFSET_Y := 10.0

const RANKING_MAX := 10
## ページ送りで切り替えるリーダーボード。先頭が既定表示
const RANKING_BOARDS: Array[String] = ["total", "stage01", "stage02", "stage03", "stage04",
	"stage05", "stage06", "stage07", "stage08", "stage09", "stage10"]
const RANKING_LABELS: Array[String] = ["TOTAL", "STAGE 1", "STAGE 2", "STAGE 3", "STAGE 4",
	"STAGE 5", "STAGE 6", "STAGE 7", "STAGE 8", "STAGE 9", "STAGE 10"]

var _menu: VBoxContainer
var _options: Control
var _ranking: Control
var _ranking_status: Label
var _ranking_list: VBoxContainer
var _ranking_page_label: Label
var _ranking_board_index := 0
## 再読み込みのすれ違い防止。ページ送り連打時に古い結果で上書きしない
var _ranking_load_gen := 0


func _ready() -> void:
	_build_ui()


# ═══════════════════════════════ 組み立て

func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var back := ColorRect.new()
	back.color = Color(0.08, 0.09, 0.14, 1.0)
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(back)

	var title_label := Label.new()
	title_label.text = "Popping"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 72)
	title_label.add_theme_color_override("font_color", ACCENT_COLOR)

	var note := Label.new()
	note.text = "(working title)"
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.add_theme_font_size_override("font_size", 18)
	note.add_theme_color_override("font_color", Color(0.6, 0.65, 0.75))

	var top_box := VBoxContainer.new()
	top_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	top_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	top_box.offset_top = 110
	top_box.add_theme_constant_override("separation", 8)
	top_box.add_child(title_label)
	top_box.add_child(note)
	add_child(top_box)

	if SHOW_DANCER:
		_add_dancer()

	_menu = VBoxContainer.new()
	_menu.set_anchors_preset(Control.PRESET_CENTER)
	_menu.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_menu.grow_vertical = Control.GROW_DIRECTION_BOTH
	_menu.add_theme_constant_override("separation", 20)
	add_child(_menu)

	_add_menu_button("NEW GAME", _new_game)
	var cont := _add_menu_button("CONTINUE", _continue_game)
	if SaveGame.has_save():
		cont.text = "CONTINUE  —  %s" % SaveGame.summary()
	else:
		cont.disabled = true
		# 押せないボタンに W/S のフォーカスが止まらないようにする
		cont.focus_mode = Control.FOCUS_NONE
	_add_menu_button("OPTIONS", _show_options)
	_add_menu_button("RANKING", _show_ranking)

	# ボタン群と名前欄はひとまとまりに見えないよう間を空ける
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 28)
	_menu.add_child(gap)
	_add_name_row(_menu)

	_options = _build_options_panel()
	add_child(_options)
	_options.visible = false

	_ranking = _build_ranking_panel()
	add_child(_ranking)
	_ranking.visible = false

	_grab_first_focus(_menu)


## W/Sでフォーカス移動。決定(Space/Enter)はGodot組み込みのui_acceptで
## フォーカス中のボタンに既に効くので、ここでは上下移動だけ見る
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key := (event as InputEventKey).keycode
		if key == KEY_W:
			_move_focus(-1)
			get_viewport().set_input_as_handled()
		elif key == KEY_S:
			_move_focus(1)
			get_viewport().set_input_as_handled()


func _move_focus(direction: int) -> void:
	var focused := get_viewport().gui_get_focus_owner()
	if focused == null:
		return
	var next := focused.find_next_valid_focus() if direction > 0 else focused.find_prev_valid_focus()
	if next:
		next.grab_focus()


## container 内で最初に見つかったフォーカス可能なControlへフォーカスを移す
func _grab_first_focus(container: Node) -> void:
	var target := _find_focusable(container)
	if target:
		target.grab_focus()


func _find_focusable(node: Node) -> Control:
	if node is Control:
		var c := node as Control
		if c.focus_mode != Control.FOCUS_NONE:
			return c
	for child in node.get_children():
		var found := _find_focusable(child)
		if found:
			return found
	return null


## 踊るキャラクターを出す。3Dを SubViewport へ描いて、その絵を2Dとして貼る。
## ゲーム本編の PlayerVisual と同じ考え方で、シーンに3Dノードを積まずに済ませる
func _add_dancer() -> void:
	# Sprite2D は Control の座標で描かれるので、位置合わせ用の空の Control を挟む。
	# こうしておけば解像度が変わってもアンカーが面倒を見てくれる
	var holder := Control.new()
	holder.name = "Dancer"
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	holder.offset_left = -DANCER_MARGIN_X
	holder.offset_right = -DANCER_MARGIN_X
	holder.offset_top = DANCER_OFFSET_Y
	holder.offset_bottom = DANCER_OFFSET_Y
	add_child(holder)

	# 本編のプレイヤー表示をそのまま流用する。トゥーン・輪郭線・ライトが
	# ゲーム中と揃うので、タイトルだけ別の見た目になる心配がない
	var visual := PlayerVisual.new()
	visual.name = "DancerVisual"
	visual.model = DANCER_MODEL
	visual.pose = DANCER_POSE
	# world_height_px だけ変えたいので、ゲーム側の調整値は複製して触る
	var stats := DANCER_STATS.duplicate() as PogoVisualStats
	stats.world_height_px = DANCER_HEIGHT_PX
	visual.visual_stats = stats
	visual.view_size = Vector2i(768, 768)
	if ResourceLoader.exists(DANCER_CLIP_PATH):
		visual.clip_source = load(DANCER_CLIP_PATH) as PackedScene
	visual.show_ball = false          # タイトルではキャラクターだけ見せる
	holder.add_child(visual)          # ここで _ready が走り、ビューポートが組み上がる
	visual.play_clip()


func _add_menu_button(text: String, callback: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(280, 56)
	b.add_theme_font_size_override("font_size", 26)
	b.pressed.connect(callback)
	_menu.add_child(b)
	return b


func _build_options_panel() -> Control:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(560, 360)
	panel.add_theme_stylebox_override("panel", _panel_style())

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 20)
	panel.add_child(box)

	_add_panel_title(box, "OPTIONS")
	_add_slider_row(box, "BGM VOLUME", Settings.bgm_volume,
		func(v: float) -> void: Settings.bgm_volume = v)
	_add_slider_row(box, "SE VOLUME", Settings.se_volume,
		func(v: float) -> void: Settings.se_volume = v)
	_add_slider_row(box, "RANKING FONT SIZE", Settings.ranking_font_size,
		func(v: float) -> void: Settings.ranking_font_size = v, 10.0, 32.0, 1.0)
	_add_back_row(box, func() -> void:
		Settings.save()
		_close_panels())

	return panel


## ランキングに載る名前。タイトル画面に置いて、遊び始める前に必ず目に入るようにする
func _add_name_row(box: VBoxContainer) -> void:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	box.add_child(row)

	var label := Label.new()
	label.text = "PLAYER NAME (shown in ranking)"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Color(0.6, 0.65, 0.75))
	row.add_child(label)

	var edit := LineEdit.new()
	edit.text = Settings.player_name
	edit.max_length = 16
	edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	edit.custom_minimum_size = Vector2(280, 40)
	edit.add_theme_font_size_override("font_size", 20)
	edit.text_changed.connect(func(v: String) -> void: Settings.player_name = v)
	row.add_child(edit)


func _build_ranking_panel() -> Control:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(560, 440)
	panel.add_theme_stylebox_override("panel", _panel_style())

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)

	_add_panel_title(box, "RANKING")
	_add_ranking_page_row(box)

	_ranking_status = Label.new()
	_ranking_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ranking_status.add_theme_font_size_override("font_size", 18)
	_ranking_status.add_theme_color_override("font_color", Color(0.8, 0.85, 0.95))
	box.add_child(_ranking_status)

	_ranking_list = VBoxContainer.new()
	_ranking_list.add_theme_constant_override("separation", 4)
	box.add_child(_ranking_list)

	_add_back_row(box, _close_panels)

	return panel


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_COLOR
	style.border_color = BORDER_COLOR
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(28)
	return style


func _add_panel_title(box: VBoxContainer, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 30)
	label.add_theme_color_override("font_color", ACCENT_COLOR)
	box.add_child(label)


func _add_slider_row(box: VBoxContainer, label_text: String, value: float,
		on_change: Callable, min_value := 0.0, max_value := 1.0, step := 0.01) -> void:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	box.add_child(row)

	var label := Label.new()
	label.text = label_text
	label.add_theme_font_size_override("font_size", 20)
	row.add_child(label)

	var slider := HSlider.new()
	slider.min_value = min_value
	slider.max_value = max_value
	slider.step = step
	slider.value = value
	slider.custom_minimum_size = Vector2(460, 24)
	slider.value_changed.connect(func(v: float) -> void: on_change.call(v))
	row.add_child(slider)


## 「◀ 合計 ▶」のようなページ送り行。合計/ステージ別リーダーボードを切り替える
func _add_ranking_page_row(box: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	box.add_child(row)

	var prev := Button.new()
	prev.text = "<"
	prev.custom_minimum_size = Vector2(44, 40)
	prev.pressed.connect(func() -> void: _change_ranking_page(-1))
	row.add_child(prev)

	_ranking_page_label = Label.new()
	_ranking_page_label.custom_minimum_size = Vector2(140, 0)
	_ranking_page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ranking_page_label.add_theme_font_size_override("font_size", 20)
	row.add_child(_ranking_page_label)

	var next := Button.new()
	next.text = ">"
	next.custom_minimum_size = Vector2(44, 40)
	next.pressed.connect(func() -> void: _change_ranking_page(1))
	row.add_child(next)


func _change_ranking_page(direction: int) -> void:
	_ranking_board_index = wrapi(_ranking_board_index + direction, 0, RANKING_BOARDS.size())
	_load_ranking()


func _add_back_row(box: VBoxContainer, callback: Callable) -> void:
	var b := Button.new()
	b.text = "BACK"
	b.custom_minimum_size = Vector2(160, 44)
	b.pressed.connect(callback)
	box.add_child(b)


# ═══════════════════════════════ 画面遷移

## 最初から始める。セーブがあれば消してよいか訊いてから
func _new_game() -> void:
	if not SaveGame.has_save():
		_start_new()
		return
	var dlg := ConfirmationDialog.new()
	dlg.title = "NEW GAME"
	dlg.dialog_text = "セーブ（%s）を消して最初から始めます。\nよろしいですか？" % SaveGame.summary()
	dlg.ok_button_text = "はじめる"
	dlg.cancel_button_text = "やめる"
	dlg.confirmed.connect(_start_new)
	# 決定でも取り消しでも、閉じたら片付ける
	dlg.canceled.connect(dlg.queue_free)
	dlg.close_requested.connect(dlg.queue_free)
	dlg.confirmed.connect(dlg.queue_free)
	add_child(dlg)
	dlg.popup_centered()


func _start_new() -> void:
	SaveGame.erase()
	SaveGame.continue_requested = false
	get_tree().change_scene_to_file(MAIN_SCENE)


## セーブの続きから始める
func _continue_game() -> void:
	if not SaveGame.has_save():
		return
	SaveGame.continue_requested = true
	get_tree().change_scene_to_file(MAIN_SCENE)


func _start_replay(stage_index: int, replay_data: Dictionary) -> void:
	Settings.pending_replay_stage_index = stage_index
	Settings.pending_replay_data = replay_data
	get_tree().change_scene_to_file(REPLAY_SCENE)


func _show_options() -> void:
	_menu.visible = false
	_options.visible = true
	_grab_first_focus(_options)


func _show_ranking() -> void:
	_menu.visible = false
	_ranking.visible = true
	_load_ranking()
	_grab_first_focus(_ranking)


## SilentWolfの現在選択中のリーダーボード（合計 or ステージ別）を取得して表示する
func _load_ranking() -> void:
	var board := RANKING_BOARDS[_ranking_board_index]
	_ranking_page_label.text = RANKING_LABELS[_ranking_board_index]

	for c in _ranking_list.get_children():
		_ranking_list.remove_child(c)
		c.queue_free()
	_ranking_status.text = "Loading..."

	_ranking_load_gen += 1
	var gen := _ranking_load_gen
	var sw_result: Dictionary = await SilentWolf.Scores.get_scores(
		RANKING_MAX, board).sw_get_scores_complete
	if gen != _ranking_load_gen:
		return          # ページ送りで待っている間に別のページへ切り替わった

	if not sw_result.get("success", false):
		_ranking_status.text = "Failed to load"
		return

	var scores: Array = sw_result.get("scores", [])
	if scores.is_empty():
		_ranking_status.text = "No records yet"
		return

	# タイム(秒)なので短いほど上位
	scores.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.score < b.score)
	_ranking_status.text = ""
	for i in range(scores.size()):
		_add_ranking_row(i + 1, scores.size(), scores[i])


## 1位: 黄色、2位: 水色、それ以降は水色から白へ順にグラデーションする
func _rank_color(rank: int, total: int) -> Color:
	if rank <= 1:
		return ACCENT_COLOR
	var mizuiro := Color(0.6, 0.9, 1.0)
	var span := maxf(float(maxi(total, 2) - 2), 1.0)
	var t := clampf(float(rank - 2) / span, 0.0, 1.0)
	return mizuiro.lerp(Color.WHITE, t)


func _add_ranking_row(rank: int, total: int, score: Dictionary) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	_ranking_list.add_child(row)

	var font_size := int(Settings.ranking_font_size)
	var color := _rank_color(rank, total)

	var rank_label := Label.new()
	rank_label.text = "%2d." % rank
	rank_label.custom_minimum_size = Vector2(36, 0)
	rank_label.add_theme_font_size_override("font_size", font_size)
	rank_label.add_theme_color_override("font_color", color)
	row.add_child(rank_label)

	var name_label := Label.new()
	name_label.text = str(score.get("player_name", "?"))
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_font_size_override("font_size", font_size)
	name_label.add_theme_color_override("font_color", color)
	row.add_child(name_label)

	var falls := 0
	var metadata = score.get("metadata")
	if metadata is Dictionary and metadata.has("falls"):
		falls = int(metadata["falls"])

	var time_label := Label.new()
	time_label.text = "%.2fs  (falls %d)" % [float(score.get("score", 0.0)), falls]
	time_label.add_theme_font_size_override("font_size", font_size)
	time_label.add_theme_color_override("font_color", color)
	row.add_child(time_label)

	# "total" にはリプレイが無いので、ステージ別ページでのみボタンを出す
	if _ranking_board_index >= 1 and metadata is Dictionary and metadata.has("replay"):
		var stage_index := _ranking_board_index - 1
		var replay_data: Dictionary = metadata["replay"]
		var play_btn := Button.new()
		play_btn.text = "PLAY"
		play_btn.custom_minimum_size = Vector2(36, 28)
		play_btn.pressed.connect(func() -> void: _start_replay(stage_index, replay_data))
		row.add_child(play_btn)


func _close_panels() -> void:
	_options.visible = false
	_ranking.visible = false
	_menu.visible = true
	_grab_first_focus(_menu)
