class_name Game
extends Node2D
##
## ステージの読み込みと進行を受け持つ。
##
## 設計方針:
##   - プレイヤー・カメラ・チューナーはここに常駐させ、ステージ側は地形とゴールだけ持つ。
##     ステージを差し替えてもプレイヤーの設定は保たれる
##   - クリア演出はここが出す。Goal 側の組み込みオーバーレイは切って reached だけ使う
##
## 操作:
##   F2 … ステージセレクト（デバッグ）の表示切替
##   F3 … 現在のステージを即クリア（デバッグ）
##   R  … 現在のステージをやり直し
##   数字 1〜9 / 0 … ステージへ直接ジャンプ
##

signal stage_loaded(index: int, stage: Stage)
signal all_cleared()
## 場外へ落ちて開始位置へ戻された。引数は落ちた地点
signal player_fell(from_position: Vector2)

# ─────────────────────────────── 設定
## 進行順に並べたステージシーン
@export var stages: Array[PackedScene] = []
## 最初に読み込むステージ番号 (0 始まり)
@export var start_index := 0
## クリア表示を出してから次のステージへ移るまでの秒数
@export_range(0.0, 5.0, 0.1) var next_stage_delay := 1.6

@export_group("Event")
## 最初のステージに入る前に再生するイベント（OP）
@export var opening: CutsceneData
## 全ステージクリア後に再生するイベント（ED）
@export var ending: CutsceneData
## ステージセレクトで飛んだときも intro を再生するか
@export var play_intro_on_select := false

@export_group("Fall")
## ステージ範囲の下端からこの距離だけ下へ出たら場外落下とみなす (px)
@export_range(0.0, 2000.0, 10.0) var fall_margin := 400.0

@export_group("Nodes")
@export var player: PogoPlayer
@export var stage_host: Node2D
## 場外落下時に鳴らす SE
@export var sfx_fall: AudioStreamPlayer
## ゴール到達時に鳴らす SE
@export var sfx_goal: AudioStreamPlayer
## イベント再生用。未設定なら実行時に作る
@export var cutscene: Cutscene

# ─────────────────────────────── 内部状態
var _index := -1
var _stage: Stage
var _clear_overlay: CanvasLayer
var _select: PanelContainer
var _advancing := false
var _fall_count := 0


# ═══════════════════════════════ ライフサイクル

func _ready() -> void:
	# ノード型の @export は _ready の時点ではまだ解決されていないことがあるため、
	# 名前で引き直す。インスペクタで別のノードを差した場合はそちらが優先される
	if player == null:
		player = get_tree().get_first_node_in_group(&"player") as PogoPlayer
	if stage_host == null:
		stage_host = get_node_or_null(^"StageHost") as Node2D
	if sfx_fall == null:
		sfx_fall = get_node_or_null(^"SfxFall") as AudioStreamPlayer
	if sfx_goal == null:
		sfx_goal = get_node_or_null(^"SfxGoal") as AudioStreamPlayer
	if cutscene == null:
		cutscene = get_node_or_null(^"Cutscene") as Cutscene
	if cutscene == null:
		cutscene = Cutscene.new()
		cutscene.name = "Cutscene"
		add_child(cutscene)
	if stages.is_empty():
		push_warning("Game: stages が空です")
		return
	_build_select_ui()
	if opening:
		await cutscene.play(opening)
	load_stage(start_index)


func _physics_process(_delta: float) -> void:
	_check_fall()


## ステージの下へ抜けたら開始位置へ戻す。ステージの読み込み直しはしないので、
## 経過時間もチューナーの調整値もそのまま維持される
func _check_fall() -> void:
	if _stage == null or player == null or _advancing:
		return
	var bounds := _stage.camera_bounds
	if bounds.size.y <= 0.0:
		return          # 範囲が設定されていないステージでは判定しない
	if player.global_position.y <= bounds.end.y + fall_margin:
		return

	_fall_count += 1
	var from := player.global_position
	print("[Game] 場外落下 (%d回目) y=%.0f → 開始位置へ戻す" % [_fall_count, from.y])
	if sfx_fall:
		sfx_fall.play()
	player.teleport(_stage.get_spawn_position())
	player_fell.emit(from)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"pogo_retry"):
		get_viewport().set_input_as_handled()
		load_stage(_index)
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var key := (event as InputEventKey).keycode
		if key == KEY_F2 and _select:
			_select.visible = not _select.visible
			get_viewport().set_input_as_handled()
		elif key == KEY_F3:
			clear_stage()
			get_viewport().set_input_as_handled()
		elif key >= KEY_1 and key <= KEY_9 or key == KEY_0:
			# 1〜9 でステージ1〜9、0 で10番目
			var idx := 9 if key == KEY_0 else key - KEY_1
			if idx < stages.size():
				load_stage(idx, false)
				get_viewport().set_input_as_handled()


# ═══════════════════════════════ ステージ読み込み

## manual=false はステージセレクトなど、進行以外での切り替え
func load_stage(index: int, manual := true) -> void:
	if index < 0 or index >= stages.size():
		push_warning("Game: ステージ番号が範囲外です: %d" % index)
		return

	_clear_overlay_hide()
	_advancing = false
	_index = index

	if _stage:
		_stage.queue_free()
		stage_host.remove_child(_stage)   # 同フレームで次を足すので即座に外す
		_stage = null

	_stage = (stages[index].instantiate()) as Stage
	if _stage == null:
		push_error("Game: ステージ %d のルートが Stage ではありません" % index)
		return
	stage_host.add_child(_stage)

	var goal := _stage.get_goal()
	if goal:
		goal.built_in_overlay = false     # クリア演出はこちらで出す
		goal.reached.connect(_on_goal_reached)
	else:
		push_warning("Game: ステージ %d にゴールがありません" % index)

	_fall_count = 0
	_reset_player()
	_apply_camera_bounds()
	_refresh_select_ui()
	print("[Game] ステージ %d/%d '%s' を読み込み"
		% [index + 1, stages.size(), _stage.get_display_name()])
	stage_loaded.emit(index, _stage)

	if _stage.intro and (manual or play_intro_on_select):
		await cutscene.play(_stage.intro)


func _reset_player() -> void:
	if player == null:
		return
	player.teleport(_stage.get_spawn_position())
	player.set_physics_process(true)


func _apply_camera_bounds() -> void:
	var cam := player.get_node_or_null(^"Camera2D") as Camera2D if player else null
	if cam == null:
		return
	var r := _stage.camera_bounds
	if r.size.x <= 0.0 or r.size.y <= 0.0:
		return
	cam.limit_left = int(r.position.x)
	cam.limit_top = int(r.position.y)
	cam.limit_right = int(r.end.x)
	cam.limit_bottom = int(r.end.y)
	cam.reset_smoothing()


# ═══════════════════════════════ デバッグ

## 現在のステージを即クリアする。
## ゴールに触れたときと同じ経路を通すので、outro やクリア演出も本番どおりに走る
func clear_stage() -> void:
	if _stage == null or player == null or _advancing:
		return
	var goal := _stage.get_goal()
	if goal == null:
		push_warning("Game: このステージにはゴールがありません")
		return
	print("[Game] デバッグ: ステージ %d を強制クリア" % (_index + 1))
	goal.force_reach(player)


# ═══════════════════════════════ クリア進行

func _on_goal_reached(clear_time: float) -> void:
	if _advancing:
		return
	_advancing = true
	if sfx_goal:
		sfx_goal.play()
	var is_last := _index >= stages.size() - 1
	_show_clear(clear_time, is_last)
	await get_tree().create_timer(next_stage_delay).timeout
	if not _advancing:                    # 待機中に手動で切り替えられていたら何もしない
		return
	_clear_overlay_hide()

	var outro := _stage.outro if _stage else null
	if outro:
		await cutscene.play(outro)

	if is_last:
		if ending:
			await cutscene.play(ending)
		all_cleared.emit()
		_show_clear(clear_time, true)
		return
	load_stage(_index + 1)


# ═══════════════════════════════ UI

func _show_clear(clear_time: float, is_last: bool) -> void:
	_clear_overlay_hide()
	_clear_overlay = CanvasLayer.new()
	_clear_overlay.layer = 64
	add_child(_clear_overlay)

	var back := ColorRect.new()
	back.color = Color(0.05, 0.06, 0.09, 0.55)
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	_clear_overlay.add_child(back)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 14)
	_clear_overlay.add_child(box)

	if is_last:
		_add_label(box, "ALL CLEAR", 64, Color(1.0, 0.92, 0.4))
		_add_label(box, "TIME  %.2f" % clear_time, 30, Color(0.9, 0.94, 1.0))
		_add_label(box, "[R] もう一度  /  [F2] ステージ選択", 20, Color(0.65, 0.7, 0.8))
	else:
		_add_label(box, "STAGE %d CLEAR" % (_index + 1), 52, Color(1.0, 0.92, 0.4))
		_add_label(box, "TIME  %.2f" % clear_time, 28, Color(0.9, 0.94, 1.0))


func _clear_overlay_hide() -> void:
	if _clear_overlay:
		_clear_overlay.queue_free()
		_clear_overlay = null


func _build_select_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100                     # チューナー(128)より下
	add_child(layer)

	_select = PanelContainer.new()
	_select.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_select.position = Vector2(12, 12)
	layer.add_child(_select)

	# 10件並ぶと画面に収まらないことがあるのでスクロールさせる
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(260, minf(560.0, 40.0 + stages.size() * 34.0))
	_select.add_child(scroll)

	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 2)
	scroll.add_child(box)
	_add_label(box, "STAGE SELECT  [F2]", 13, Color(0.55, 0.85, 1.0))
	_add_hint(box, "[F1] チューナー    [F3] このステージをクリア")
	_add_hint(box, "[R] やり直し    数字 1〜9 / 0 でステージ移動")

	for i in stages.size():
		var b := Button.new()
		b.text = "%d." % (i + 1)          # 読み込み後に名前を入れ直す
		b.pressed.connect(load_stage.bind(i, false))
		box.add_child(b)
	_select.visible = false


## ボタンの表示名を、実際に読み込んだステージ名で更新する
func _refresh_select_ui() -> void:
	if _select == null:
		return
	var box := _select.get_child(0).get_child(0)
	var buttons: Array[Button] = []
	for c in box.get_children():
		if c is Button:
			buttons.append(c as Button)
	for i in buttons.size():
		var label := "%d." % (i + 1)
		if i == _index and _stage:
			label += " " + _stage.get_display_name() + "   ←"
		elif i < stages.size():
			var packed := stages[i]
			label += " " + packed.resource_path.get_file().get_basename()
		buttons[i].text = label


## セレクトパネルに出す操作の手引き
func _add_hint(parent: Node, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", Color(0.62, 0.67, 0.74))
	parent.add_child(label)


func _add_label(parent: Node, text: String, size: int, color: Color) -> void:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
