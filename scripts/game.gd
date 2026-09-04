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
##   F4 … レベルデザイン用の方眼の表示切替
##   R  … 現在のステージをやり直し
##   数字 1〜9 / 0 … ステージへ直接ジャンプ
##

## 地形が camera_bounds からこれだけはみ出すまでは警告しない (px)。
## 端の数十pxは実際には行けない場所なので、いちいち出すと本当の
## 作り忘れが埋もれる
const BOUNDS_SLACK := 64.0

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

@export_group("BGM")
## ステージBGM。stages と同じ順番・同じ長さで、各ステージに鳴らす曲を直接指定する
@export var stage_bgm: Array[AudioStream] = []

@export_group("Test play")
## テストプレイ用。有効な間は test_play_stage_count 番目のステージをクリアすると
## 感謝メッセージを出して最初のステージへ戻る。本編を最後まで通せるよう既定は false。
## 途中経過だけのテスト版を配る用途で true に戻す
@export var test_play_mode := false
## テストプレイの区切りとするステージ番号 (1 始まり)
@export_range(1, 10, 1) var test_play_stage_count := 5

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
## クリアデモと次のステージの冒頭デモの間に挟む時間経過の演出。
## 未設定なら実行時に作る
@export var time_passage: TimePassage
## ステージBGM再生用。未設定なら実行時に作る
@export var bgm_player: AudioStreamPlayer

# ─────────────────────────────── 内部状態
var _index := -1
var _stage: Stage
var _clear_overlay: CanvasLayer
var _select: PanelContainer
var _advancing := false
var _respawning := false
## 読み込みの世代。演出の待機中に別のステージへ切り替えられたら、
## 古い側の続きを止めるために使う
var _load_gen := 0
## 復帰地点。到達した中で最も進んだものの番号（-1 なら Spawn）
var _checkpoint := -1
var _points: Array[Marker2D] = []
## スコア用の記録
var _fall_count := 0
var _total_falls := 0
## 全ステージ合計のクリアタイム（オンラインランキングの total 用）
var _total_clear_time := 0.0


# ═══════════════════════════════ ライフサイクル

## BGが万一見切れても黒いvoidではなく空の水色が見えるようにする。
## プロジェクト設定で変えるとエディタの2Dビューにも影響するため、
## 実行時にここだけで書き換える
const PLAY_CLEAR_COLOR := Color(0.172549, 0.588235, 0.768627, 1.0)


func _ready() -> void:
	RenderingServer.set_default_clear_color(PLAY_CLEAR_COLOR)
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
	if time_passage == null:
		time_passage = get_node_or_null(^"TimePassage") as TimePassage
	if time_passage == null:
		time_passage = TimePassage.new()
		time_passage.name = "TimePassage"
		add_child(time_passage)
	if bgm_player == null:
		bgm_player = get_node_or_null(^"BgmPlayer") as AudioStreamPlayer
	if bgm_player == null:
		bgm_player = AudioStreamPlayer.new()
		bgm_player.name = "BgmPlayer"
		bgm_player.bus = "BGM"
		add_child(bgm_player)
	# 落下復帰中は get_tree().paused = true になるが、BGMは止めたくないので
	# ポーズの影響を受けないようにする
	bgm_player.process_mode = Node.PROCESS_MODE_ALWAYS
	if stages.is_empty():
		push_warning("Game: stages が空です")
		return
	_build_select_ui()
	# テストモードではタイトルとデモ(オープニング・ステージ冒頭イベント)を
	# 飛ばして、いきなりステージだけをプレイできるようにする
	var skip_demo := Settings.test_mode
	if opening and not skip_demo:
		await cutscene.play(opening)
	load_stage(start_index, not skip_demo)


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

	_kill(player.global_position, "場外")


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
		elif key == KEY_F4:
			var grid := get_node_or_null(^"DesignGrid")
			if grid:
				grid.visible = not grid.visible
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
		await _reveal()
		return

	_clear_overlay_hide()
	_advancing = false
	_load_gen += 1
	var gen := _load_gen
	_index = index

	if _stage:
		_stage.queue_free()
		stage_host.remove_child(_stage)   # 同フレームで次を足すので即座に外す
		_stage = null

	_stage = (stages[index].instantiate()) as Stage
	if _stage == null:
		push_error("Game: ステージ %d のルートが Stage ではありません" % index)
		await _reveal()
		return
	stage_host.add_child(_stage)

	for h in _stage.get_hazards():
		h.touched.connect(_on_hazard_touched)

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
	_check_stage_bounds()
	_refresh_select_ui()
	_play_stage_bgm(index)
	print("[Game] ステージ %d/%d '%s' を読み込み"
		% [index + 1, stages.size(), _stage.get_display_name()])
	stage_loaded.emit(index, _stage)

	# 時間経過の演出で暗転したままここへ来ている。差し替えが済んでから明ける。
	# 冒頭デモより先に明けるので「時間が飛んで、次の場所にいる」順に見える
	await _reveal()
	if gen != _load_gen:
		return

	if _stage.intro and (manual or play_intro_on_select):
		await cutscene.play(_stage.intro)
		if gen != _load_gen:
			return          # 待っている間に別のステージへ切り替わった

	await _show_stage_title(gen)


## 時間経過の演出で暗転していたら明ける。暗転していなければ何もしない。
## 読み込みに失敗して途中で戻る経路からも必ず通す。通し忘れると
## 画面が暗いまま操作を受け付けなくなり、原因が追いにくい
func _reveal() -> void:
	if time_passage:
		await time_passage.fade_in()


func _reset_player() -> void:
	if player == null:
		return
	player.teleport(_stage.get_spawn_position())
	player.set_physics_process(true)


## stage_bgm[index] の曲を鳴らす。
## 同じ曲が既に鳴っていれば鳴らし直さない（リトライ時にぶつ切りにしない）
func _play_stage_bgm(index: int) -> void:
	if bgm_player == null or index < 0 or index >= stage_bgm.size():
		return
	var track := stage_bgm[index]
	if track == null:
		return
	if bgm_player.stream == track and bgm_player.playing:
		return
	if track is AudioStreamMP3:
		(track as AudioStreamMP3).loop = true
	elif track is AudioStreamOggVorbis:
		(track as AudioStreamOggVorbis).loop = true
	bgm_player.stream = track
	bgm_player.play()


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


## ステージの範囲設定が地形や開始位置と食い違っていないかを読み込み時に見る。
##
## camera_bounds はカメラの可動範囲と落下死の線を兼ねている。Rect2 なので
## 上を広げるつもりで position.y だけ動かすと下端も一緒に上がってしまい、
## 開始した瞬間に落下死する。見た目には何も起きないので原因を追いにくい。
## 仮データを流用したステージでも、地形だけ作り替えて範囲を直し忘れると
## 端がカメラに入らなくなる。どちらも起きやすいので毎回見る
func _check_stage_bounds() -> void:
	if _stage == null:
		return
	var bounds := _stage.camera_bounds
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		return
	var name := _stage.get_display_name()
	var death_line := bounds.end.y + fall_margin

	var spawn := _stage.get_spawn_position()
	if spawn.y > death_line:
		print("[Game] 警告: %s の開始位置 y=%.0f が落下死の線 y=%.0f より下です。"
			% [name, spawn.y, death_line]
			+ "開始した瞬間に死にます。camera_bounds の下端を伸ばしてください")
	for i in _points.size():
		var py := _points[i].global_position.y
		if py > death_line:
			print("[Game] 警告: %s の復帰地点 %d の y=%.0f が落下死の線 y=%.0f より下です"
				% [name, i + 1, py, death_line])

	var terrain := _terrain_rect()
	if terrain.size == Vector2.ZERO or bounds.grow(BOUNDS_SLACK).encloses(terrain):
		return
	print("[Game] 警告: %s の地形 x %.0f..%.0f / y %.0f..%.0f が "
		% [name, terrain.position.x, terrain.end.x, terrain.position.y, terrain.end.y]
		+ "camera_bounds x %.0f..%.0f / y %.0f..%.0f からはみ出しています。"
		% [bounds.position.x, bounds.end.x, bounds.position.y, bounds.end.y]
		+ "はみ出した先はカメラが追わないので画面に入りません")


## 地形が実際に占めている範囲。回転しているパーツも含めて頂点から求める
func _terrain_rect() -> Rect2:
	var rect := Rect2()
	var first := true
	for node in _stage.find_children("*", "CollisionPolygon2D", true, false):
		var poly := node as CollisionPolygon2D
		if poly == null or poly.polygon.size() < 2:
			continue
		var xform := poly.global_transform
		for point in poly.polygon:
			var world := xform * point
			if first:
				rect = Rect2(world, Vector2.ZERO)
				first = false
			else:
				rect = rect.expand(world)
	return rect


## ステージ開始の見出しを出して、指定秒数だけ待つ。
## 待っている間はツリーを止める。止めないと、開始位置に置いたプレイヤーが
## 見出しの裏で落ち始めてしまう
func _show_stage_title(gen: int) -> void:
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

	get_tree().paused = true
	await get_tree().create_timer(stage_title_duration, true, false, true).timeout
	layer.queue_free()
	# 元の状態を復元すると、演出中に別のステージへ切り替えられたときに
	# paused=true を復元して固まる。見出しの後は必ず遊べる状態にする
	if gen == _load_gen:
		get_tree().paused = false


## 死亡して復帰地点へ戻す。落下床と場外の両方から呼ぶ
func _kill(from: Vector2, cause: String) -> void:
	if _advancing or _respawning or _stage == null:
		return
	_fall_count += 1
	_total_falls += 1
	print("[Game] 死亡:%s (このステージ %d回目) → 復帰地点 %s へ"
		% [cause, _fall_count, "Spawn" if _checkpoint < 0 else str(_checkpoint + 1)])
	player_fell.emit(from)
	_respawn()


func _on_hazard_touched(body: Node2D) -> void:
	_kill(body.global_position, "落下床")


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
	_total_clear_time = 0.0


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
	if bgm_player:
		bgm_player.stop()          # ステージBGMを止めて、ジングルと重ならないようにする
	if sfx_goal:
		sfx_goal.play()
	var is_last := _index >= stages.size() - 1
	var is_test_end := test_play_mode and _index + 1 >= test_play_stage_count
	_total_clear_time += clear_time
	if not Settings.test_mode:
		_submit_stage_score(_index, clear_time, _fall_count)
		if is_last:
			_submit_total_score(_total_clear_time, _total_falls)
	_show_clear(_total_clear_time if is_last else clear_time, is_last, is_test_end)
	await _wait_after_goal()
	if not _advancing:                    # 待機中に手動で切り替えられていたら何もしない
		return
	_clear_overlay_hide()

	var outro := _stage.outro if _stage else null
	if outro:
		await cutscene.play(outro)

	if is_test_end:
		load_stage(start_index)
		return

	if is_last:
		if ending:
			await cutscene.play(ending)
		all_cleared.emit()
		_show_clear(_total_clear_time, true)
		return

	# 時間経過。暗転したまま次のステージへ移り、load_stage の中で明ける
	if time_passage:
		var caption := _stage.time_passage_text if _stage else ""
		await time_passage.fade_out(caption)
	load_stage(_index + 1)


## ステージ単体のスコアを "stage01"〜"stage10" のリーダーボードへ送る。
## スコアはクリアタイム（秒）。落下回数は metadata に添える。
## 通信は待たない（結果を待ってゲーム進行を止めたくないため）
func _submit_stage_score(index: int, clear_time: float, fall_count: int) -> void:
	var board := "stage%02d" % (index + 1)
	SilentWolf.Scores.save_score(Settings.player_name, clear_time, board, {"falls": fall_count})


## 全ステージ合計のスコアを "total" リーダーボードへ送る
func _submit_total_score(total_time: float, total_falls: int) -> void:
	SilentWolf.Scores.save_score(Settings.player_name, total_time, "total", {"falls": total_falls})


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

func _show_clear(clear_time: float, is_last: bool, test_end := false) -> void:
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

	if test_end:
		_add_label(box, "テストプレイありがとうございます！！", 46, Color(1.0, 0.92, 0.4))
		return

	if is_last:
		_add_label(box, "ALL CLEAR", 64, Color(1.0, 0.92, 0.4))
		_add_label(box, "TIME  %.2f" % clear_time, 30, Color(0.9, 0.94, 1.0))
		_add_label(box, "FALLS  %d" % _total_falls, 26, Color(0.9, 0.94, 1.0))
		_add_label(box, "[R] もう一度  /  [F2] ステージ選択", 20, Color(0.65, 0.7, 0.8))
	else:
		_add_label(box, "STAGE %d CLEAR" % (_index + 1), 52, Color(1.0, 0.92, 0.4))
		_add_label(box, "TIME  %.2f    FALLS  %d" % [clear_time, _fall_count],
			28, Color(0.9, 0.94, 1.0))

	_show_stage_ranking(_clear_overlay, _index)


## クリアしたステージのランキング(1〜10位)を左上にテキストで出す
func _show_stage_ranking(overlay: CanvasLayer, stage_index: int) -> void:
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_TOP_LEFT)
	box.offset_left = 24
	box.offset_top = 24
	box.add_theme_constant_override("separation", 2)
	overlay.add_child(box)

	var title := Label.new()
	title.text = "STAGE %d RANKING" % (stage_index + 1)
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(1.0, 0.92, 0.4))
	box.add_child(title)

	var status := Label.new()
	status.text = "読み込み中…"
	status.add_theme_font_size_override("font_size", 14)
	status.add_theme_color_override("font_color", Color(0.8, 0.85, 0.95))
	box.add_child(status)

	var board := "stage%02d" % (stage_index + 1)
	var sw_result: Dictionary = await SilentWolf.Scores.get_scores(10, board).sw_get_scores_complete
	if not is_instance_valid(box):
		return          # 待っている間にクリア画面が閉じられた

	if not sw_result.get("success", false):
		status.text = "取得に失敗しました"
		return
	var scores: Array = sw_result.get("scores", [])
	if scores.is_empty():
		status.text = "まだ記録がありません"
		return

	# タイム(秒)なので短いほど上位
	scores.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.score < b.score)
	status.queue_free()
	var font_size := int(Settings.ranking_font_size)
	for i in range(scores.size()):
		var s: Dictionary = scores[i]
		var line := Label.new()
		line.add_theme_font_size_override("font_size", font_size)
		line.add_theme_color_override("font_color", _rank_color(i + 1, scores.size()))
		line.text = "%2d. %s  %.2fs" % [i + 1, str(s.get("player_name", "?")), float(s.get("score", 0.0))]
		box.add_child(line)


## 1位: 黄色、2位: 水色、それ以降は水色から白へ順にグラデーションする
func _rank_color(rank: int, total: int) -> Color:
	if rank <= 1:
		return Color(1.0, 0.92, 0.4)
	var mizuiro := Color(0.6, 0.9, 1.0)
	var span := maxf(float(maxi(total, 2) - 2), 1.0)
	var t := clampf(float(rank - 2) / span, 0.0, 1.0)
	return mizuiro.lerp(Color.WHITE, t)


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
	_add_hint(box, "[F4] 方眼(250px)")
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
