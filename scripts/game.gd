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
## ゴール到達からイベント開始までの最低待ち時間 (秒)。
## この間はクリア表示が出たままになる
@export_range(0.0, 15.0, 0.1) var next_stage_delay := 4.0
## 上の時間を過ぎてもクリアSEが鳴っていれば、鳴り終わるまで待つ上限 (秒)。
## mp3 はエンコード時に尺が伸びることがあるので秒数を決め打ちにせず実測で待つ。
## 長いファイルに差し替わっても止まらないよう上限を設けている
@export_range(0.0, 30.0, 0.5) var goal_sfx_max_wait := 8.0

@export_group("Event")
## 最初のステージに入る前に再生するイベント（OP）
@export var opening: CutsceneData
## 全ステージクリア後に再生するイベント（ED）
@export var ending: CutsceneData
## ステージセレクトで飛んだときも intro を再生するか
@export var play_intro_on_select := false

@export_group("Stage title")
## ステージ開始時に出す見出しの表示秒数。0 で出さない
@export_range(0.0, 5.0, 0.1) var stage_title_duration := 1.0

@export_group("Fall")
## ステージ範囲の下端からこの距離だけ下へ出たら落下死とみなす (px)。
## 仕様書にある「連続下降距離」での判定は使わない。現在の重力(450)だと
## 強いバウンドで 1600px 以上上がるため、普通に跳んだだけで落下扱いになる
@export_range(0.0, 2000.0, 10.0) var fall_margin := 400.0
## 復帰地点に到達したとみなす距離 (px)
@export_range(50.0, 800.0, 10.0) var checkpoint_radius := 220.0
## 落下から復帰までの演出時間 (秒)。これが実質的なペナルティになる
@export_range(0.0, 2.0, 0.05) var respawn_time := 0.5

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
var _respawning := false
## 復帰地点。到達した中で最も進んだものの番号（-1 なら Spawn）
var _checkpoint := -1
var _points: Array[Marker2D] = []
## スコア用の記録
var _fall_count := 0
var _total_falls := 0


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
	_update_checkpoint()
	_check_fall()


## 復帰地点への到達を記録する。番号は巻き戻さないので、
## 戻って手前の地点に触れても復帰先は下がらない
func _update_checkpoint() -> void:
	if _points.is_empty() or player == null or _advancing or _respawning:
		return
	for i in range(_points.size() - 1, _checkpoint, -1):
		if player.global_position.distance_to(_points[i].global_position) <= checkpoint_radius:
			_checkpoint = i
			print("[Game] 復帰地点 %d/%d に到達" % [i + 1, _points.size()])
			return


## 現在の復帰先
func _respawn_position() -> Vector2:
	if _checkpoint >= 0 and _checkpoint < _points.size():
		return _points[_checkpoint].global_position
	return _stage.get_spawn_position()


## ステージの下へ抜けたら開始位置へ戻す。ステージの読み込み直しはしないので、
## 経過時間もチューナーの調整値もそのまま維持される
func _check_fall() -> void:
	if _stage == null or player == null or _advancing or _respawning:
		return
	var bounds := _stage.camera_bounds
	if bounds.size.y <= 0.0:
		return          # 範囲が設定されていないステージでは判定しない
	if player.global_position.y <= bounds.end.y + fall_margin:
		return

	_fall_count += 1
	_total_falls += 1
	var from := player.global_position
	print("[Game] 落下 (このステージ %d回目) → 復帰地点 %s へ"
		% [_fall_count, "Spawn" if _checkpoint < 0 else str(_checkpoint + 1)])
	player_fell.emit(from)
	_respawn()


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
	_checkpoint = -1
	_points = _stage.get_recovery_points()
	_reset_player()
	_apply_camera_bounds()
	_refresh_select_ui()
	print("[Game] ステージ %d/%d '%s' を読み込み"
		% [index + 1, stages.size(), _stage.get_display_name()])
	stage_loaded.emit(index, _stage)

	if _stage.intro and (manual or play_intro_on_select):
		await cutscene.play(_stage.intro)

	await _show_stage_title()


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


## ステージ開始の見出しを出して、指定秒数だけ待つ。
## 待っている間はツリーを止める。止めないと、開始位置に置いたプレイヤーが
## 見出しの裏で落ち始めてしまう
func _show_stage_title() -> void:
	if stage_title_duration <= 0.0:
		return

	var layer := CanvasLayer.new()
	layer.layer = 48                      # イベント(32)より上、クリア表示(64)より下
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(layer)

	var label := Label.new()
	label.text = "STAGE %d" % (_index + 1)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.add_theme_font_size_override("font_size", 72)
	label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.8))
	layer.add_child(label)

	var was_paused := get_tree().paused
	get_tree().paused = true
	await get_tree().create_timer(stage_title_duration, true, false, true).timeout
	get_tree().paused = was_paused
	layer.queue_free()


## 落下からの復帰。暗転させてから戻す。この間だけツリーを止める
func _respawn() -> void:
	_respawning = true
	if sfx_fall:
		sfx_fall.play()

	var layer := CanvasLayer.new()
	layer.layer = 56
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(layer)
	var fade := ColorRect.new()
	fade.color = Color(0.02, 0.02, 0.04, 0.0)
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(fade)

	var half := maxf(respawn_time, 0.02) * 0.5
	get_tree().paused = true

	var tw := create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(fade, "color:a", 1.0, half)
	await tw.finished

	player.teleport(_respawn_position())

	var tw2 := create_tween()
	tw2.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw2.tween_property(fade, "color:a", 0.0, half)
	await tw2.finished

	get_tree().paused = false
	layer.queue_free()
	_respawning = false


# ═══════════════════════════════ スコア用の記録

## このステージでの落下回数
func get_stage_falls() -> int:
	return _fall_count


## 全ステージ通しての落下回数。ステージ選択で飛んでもリセットしない
func get_total_falls() -> int:
	return _total_falls


## 記録をリセットする。通しプレイを始め直すときに呼ぶ
func reset_score() -> void:
	_total_falls = 0
	_fall_count = 0


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
	await _wait_after_goal()
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


## クリアSEが鳴り終わるまでイベントを始めないための待ち
func _wait_after_goal() -> void:
	var elapsed := 0.0
	while elapsed < next_stage_delay:
		await get_tree().process_frame
		elapsed += get_process_delta_time()
	# まだ鳴っていれば上限まで待つ
	while sfx_goal and sfx_goal.playing and elapsed < goal_sfx_max_wait:
		await get_tree().process_frame
		elapsed += get_process_delta_time()


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
		_add_label(box, "FALLS  %d" % _total_falls, 26, Color(0.9, 0.94, 1.0))
		_add_label(box, "[R] もう一度  /  [F2] ステージ選択", 20, Color(0.65, 0.7, 0.8))
	else:
		_add_label(box, "STAGE %d CLEAR" % (_index + 1), 52, Color(1.0, 0.92, 0.4))
		_add_label(box, "TIME  %.2f    FALLS  %d" % [clear_time, _fall_count],
			28, Color(0.9, 0.94, 1.0))


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
