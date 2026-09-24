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
##   F6 … イベントセレクト（デバッグ）の表示切替。OP/ED・各面の前後の会話を単体で再生
##   F9 … 会話中に台本の〔演出：…〕を出す（Cutscene 側）
##   R  … 現在のステージをやり直し
##   数字 1〜9 / 0 … ステージへ直接ジャンプ
##

## 地形が camera_bounds からこれだけはみ出すまでは警告しない (px)。
## 端の数十pxは実際には行けない場所なので、いちいち出すと本当の
## 作り忘れが埋もれる
const BOUNDS_SLACK := 64.0

## ポーズメニューから戻る先
const TITLE_SCENE := "res://scenes/Title.tscn"

## 記憶コレクションに並べる既定の絵。ゴールに置いてあるものと同じ画像を使う。
##
## ステージ1〜9は foods.png の3x3スプライトシートから1コマずつ取る。
## コマ番号は各ステージの Goal/Sprite の frame と同じ並びなので、
## ゴールの絵を差し替えたらこちらも一緒に見直すこと。
## ステージ10だけ別の画像（カニエナガ）。
##
## resources/texture/foods/ の個別PNGは .gdignore で除外されていて
## 読めないので使わない
const MEMORY_SHEET := "res://resources/texture/foods.png"
const MEMORY_SHEET_COLS := 3
const MEMORY_SHEET_ROWS := 3
const MEMORY_LAST_ITEM := "res://resources/texture/goal.png"

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

## 記憶コレクションに並べる「10個の大好物」。ステージ1〜10の順。
## 空のままならゴールと同じ絵（foods.png のコマと goal.png）を読む
@export var memory_items: Array[Texture2D] = []

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
## 会話デモ（オープニング・ステージ前後・エンディング）を全て飛ばし、
## ステージだけを通しで遊ぶ。レベルデザインの確認用。
## 書き出しプリセットのカスタム機能に "testplay" が付いていると自動で有効になる。
## Settings.test_mode と違いスコアは通常どおり送信する
@export var skip_cutscenes := false
## デバッグ操作（F2 ステージ選択 / F3 即クリア / F4 方眼 / 数字でステージ移動）を
## 受け付けるか。配布版では切る。押されるとランキングに出鱈目な記録が載るため。
## skip_cutscenes と同じく "testplay" 付きの書き出しでは自動で false になる
@export var debug_shortcuts := true
## 会話デモ中に、台本の〔演出：…〕を画面の上に出す。まだ実装していない演出の
## 確認用。再生中に F9 でも切り替えられるので、これは最初から出したいときだけ
@export var show_cutscene_notes := false

@export_group("Stage title")
## ステージ開始時に出す見出しの表示秒数。0 で出さない
@export_range(0.0, 5.0, 0.1) var stage_title_duration := 1.0

@export_group("Fall")
## ステージ範囲の下端からこの距離だけ下へ出たら落下死とみなす (px)。
## 仕様書にある「連続下降距離」での判定は使わない。現在の重力(450)だと
## 強いバウンドで 1600px 以上上がるため、普通に跳んだだけで落下扱いになる
@export_range(0.0, 2000.0, 10.0) var fall_margin := 400.0
## 復帰地点に到達したとみなす距離 (px)
@export_range(50.0, 800.0, 10.0) var checkpoint_radius := 132.0
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
## 記憶コレクション画面。未割り当てなら実行時に作る
@export var memory: MemoryCollection
## クリアデモと次のステージの冒頭デモの間に挟む時間経過の演出。
## 未設定なら実行時に作る
@export var time_passage: TimePassage
## ステージBGM再生用。未設定なら実行時に作る
@export var bgm_player: AudioStreamPlayer

# ─────────────────────────────── 内部状態
var _index := -1
var _stage: Stage
var _clear_overlay: CanvasLayer
var _pause_overlay: CanvasLayer
## ポーズメニューの一行メッセージ。セーブした結果を出す
var _pause_note: Label
var _select: PanelContainer
## イベントセレクト（F6）。最初に開いたときに組み立てる
var _event_panel: PanelContainer
var _event_progress: Label
## 確認用に集めたイベント。[{"key": 表示名, "data": CutsceneData}]
var _events: Array[Dictionary] = []
## 全イベントの通し再生中。ESC で降ろす
var _playing_all := false
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

## リプレイ記録（そのステージの1位を更新した時だけスコアに添えて送信する。
## 何フレームに1回記録するか。小さいほど滑らかだが容量が増える）
const REPLAY_SAMPLE_STRIDE := 3
var _replay_x: PackedFloat32Array = PackedFloat32Array()
var _replay_y: PackedFloat32Array = PackedFloat32Array()
var _replay_tilt: PackedFloat32Array = PackedFloat32Array()
var _replay_frame_count := 0


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
	if show_cutscene_notes:
		cutscene.show_notes = true
	if memory == null:
		memory = get_node_or_null(^"MemoryCollection") as MemoryCollection
	if memory == null:
		memory = MemoryCollection.new()
		memory.name = "MemoryCollection"
		add_child(memory)
	if memory.items.is_empty():
		memory.items = _resolve_memory_items()
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
	# イベント中のBGMも同じプレイヤーで鳴らす。イベントで流した曲を
	# そのままステージへ続けたり、止めたまま次へ渡したりするため
	cutscene.bgm_player = bgm_player
	if stages.is_empty():
		push_warning("Game: stages が空です")
		return
	_build_select_ui()
	# テストモードではタイトルとデモ(オープニング・ステージ冒頭イベント)を
	# 飛ばして、いきなりステージだけをプレイできるようにする
	# Web(itch.io)版は通しプレイだけを解放するので、書き出し時のカスタム機能で切り替える
	if OS.has_feature("testplay"):
		skip_cutscenes = true
		debug_shortcuts = false
	var resumed := _apply_save()
	var skip_demo := Settings.test_mode or skip_cutscenes
	# 続きから始めるときは OP を出さない。もう見ているため
	if opening and not skip_demo and not resumed:
		await cutscene.play(opening)
	load_stage(start_index, not skip_demo)


## タイトルの CONTINUE から入っていれば、セーブの続きを組み立てる。
## 続きから始めるなら true。NEW GAME やタイトルを経由しない起動では何もしない
func _apply_save() -> bool:
	if not SaveGame.continue_requested:
		return false
	# 一度きりの合図。タイトルへ戻ったらもう一度選んでもらう
	SaveGame.continue_requested = false
	if not SaveGame.has_save() or stages.is_empty():
		return false
	start_index = clampi(SaveGame.stage_index, 0, stages.size() - 1)
	_total_clear_time = SaveGame.total_clear_time
	_total_falls = SaveGame.total_falls
	if memory:
		memory.restore(SaveGame.memory_indices)
	print("[Game] 続きから開始: ステージ %d" % (start_index + 1))
	return true


## 今の進行を書く。next_stage は次に始めるステージ番号。書けたら true。
## 試し遊びの結果で続きを上書きしないよう、テスト用の設定では書かない
func _write_save(next_stage: int) -> bool:
	if Settings.test_mode or test_play_mode:
		return false
	var acquired := memory.acquired_indices() if memory else PackedInt32Array()
	SaveGame.write(next_stage, _total_clear_time, _total_falls, acquired)
	return true


func _physics_process(_delta: float) -> void:
	_update_checkpoint()
	_check_fall()
	_record_replay_frame()


func _reset_replay() -> void:
	_replay_x.clear()
	_replay_y.clear()
	_replay_tilt.clear()
	_replay_frame_count = 0


## プレイヤーの座標・傾きをステージ開始からゴールまで記録する。
## 巻き戻し(復帰地点への瞬間移動)もそのまま座標として残るので、
## 再生側は素直になぞるだけで実際の動きを再現できる
func _record_replay_frame() -> void:
	if player == null or _stage == null:
		return
	_replay_frame_count += 1
	if _replay_frame_count % REPLAY_SAMPLE_STRIDE != 0:
		return
	_replay_x.append(snappedf(player.global_position.x, 0.1))
	_replay_y.append(snappedf(player.global_position.y, 0.1))
	_replay_tilt.append(snappedf(player.tilt_deg, 1.0))


## 記録済みのリプレイをスコアのmetadataに載せられる形に変換する
func _build_replay_payload() -> Dictionary:
	return {
		"stride": REPLAY_SAMPLE_STRIDE,
		"x": Array(_replay_x),
		"y": Array(_replay_y),
		"tilt": Array(_replay_tilt),
	}


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
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		if _playing_all:
			_playing_all = false      # 通し再生を降りる。今のイベントは最後まで出る
			return
		_open_pause_menu()
		return
	if event.is_action_pressed(&"pogo_retry"):
		if _playing_all:
			return                    # 通し再生中にステージを触らない
		get_viewport().set_input_as_handled()
		load_stage(_index)
		return
	if not debug_shortcuts:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var key := (event as InputEventKey).keycode
		if key == KEY_F6:
			_toggle_event_ui()
			get_viewport().set_input_as_handled()
		elif key == KEY_F2 and _select:
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
			# 1〜9 でステージ1〜9、0 で10番目。
			# Shift を足すと同じ番号の復帰地点へ飛ぶ（Shift+0 は開始位置）
			var idx := 9 if key == KEY_0 else key - KEY_1
			if (event as InputEventKey).shift_pressed:
				_warp_to_point(-1 if key == KEY_0 else idx)
				get_viewport().set_input_as_handled()
			elif idx < stages.size():
				load_stage(idx, false)
				get_viewport().set_input_as_handled()


## デバッグ用。復帰地点（-1 なら開始位置）へ飛ぶ。
## 落下したときの戻り先も揃えるので、そこから続けて試せる
func _warp_to_point(index: int) -> void:
	if player == null or _stage == null:
		return
	if index >= _points.size():
		print("[Game] デバッグ: 復帰地点 %d は無い（このステージは %d 個）"
			% [index + 1, _points.size()])
		return
	_checkpoint = index
	player.teleport(_respawn_position())
	if index < 0:
		print("[Game] デバッグ: 開始位置へ移動")
	else:
		print("[Game] デバッグ: 復帰地点 %d/%d へ移動" % [index + 1, _points.size()])


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
	# ツリーに入れる前に開始位置へ移す。前のステージのゴール前に立ったままだと、
	# ステージによってはそこが次のステージのゴール判定の中に入っていて、
	# 始まった瞬間にクリアになりうる（ステージ1と2のゴールは世界座標で重なっている）
	_reset_player()
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
	_reset_replay()
	_points = _stage.get_recovery_points()
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

	if _stage.intro and not skip_cutscenes and (manual or play_intro_on_select):
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
	var visual := _player_visual()
	if visual:
		visual.stop_clip()          # 勝利モーションが残っていれば通常の姿勢へ戻す
	player.teleport(_stage.get_spawn_position())
	player.set_physics_process(true)


func _player_visual() -> PlayerVisual:
	if player == null:
		return null
	return player.get_node_or_null(^"Visual") as PlayerVisual


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
	var visual := _player_visual()
	if visual:
		visual.play_goal_clip()          # 勝利モーション。次のステージへ移るまで踊り続ける
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
	if outro and not skip_cutscenes:
		await cutscene.play(outro)

	# 記憶コレクション。毎ステージ後に必ず挟んで「あと何個で帰れるのか」を見せる。
	# 最後のステージでは 10/10 が揃ってから ending へ繋ぐ
	if memory and not skip_cutscenes:
		await memory.acquire(_index)

	if is_test_end:
		load_stage(start_index)
		return

	if is_last:
		# 最後まで到達したので続きは無い。CONTINUE を残さない
		if not (Settings.test_mode or test_play_mode):
			SaveGame.erase()
		if ending and not skip_cutscenes:
			await cutscene.play(ending)
		all_cleared.emit()
		_show_clear(_total_clear_time, true)
		return

	# ここまでを自動で保存する。記憶コレクションを見せ終えた時点＝
	# そのステージが完全に終わった時点なので、区切りとして分かりやすい
	_write_save(_index + 1)

	# 時間経過。暗転したまま次のステージへ移り、load_stage の中で明ける
	if time_passage:
		var caption := _stage.time_passage_text if _stage else ""
		await time_passage.fade_out(caption)
	load_stage(_index + 1)


## 記憶コレクションに並べる絵を決める。割り当てがあればそれを、
## 無ければ既定のパスから読む。読めなかったぶんは空の枠になる
func _resolve_memory_items() -> Array[Texture2D]:
	if not memory_items.is_empty():
		return memory_items
	var out: Array[Texture2D] = []
	var sheet := load(MEMORY_SHEET) as Texture2D
	if sheet == null:
		push_warning("Game: 記憶アイテムのシートが読めません: %s" % MEMORY_SHEET)
	else:
		var cell := sheet.get_size() / Vector2(MEMORY_SHEET_COLS, MEMORY_SHEET_ROWS)
		for i in MEMORY_SHEET_COLS * MEMORY_SHEET_ROWS:
			var col := i % MEMORY_SHEET_COLS
			var row := floori(i / float(MEMORY_SHEET_COLS))
			var at := AtlasTexture.new()
			at.atlas = sheet
			at.region = Rect2(Vector2(col, row) * cell, cell)
			out.append(at)
	var last := load(MEMORY_LAST_ITEM) as Texture2D
	if last == null:
		push_warning("Game: 最後の記憶アイテムの絵が読めません: %s" % MEMORY_LAST_ITEM)
	out.append(last)
	return out


## ステージ単体のスコアを "stage01"〜"stage10" のリーダーボードへ送る。
## スコアはクリアタイム（秒）。落下回数は metadata に添える。
## そのステージの現在の1位より速ければ、リプレイを添えて送信する。
## 及ばなければリプレイ無しで送る（1位の座を守っている記録だけが
## 結果的にリプレイを持ち続ける。await していても呼び出し側は
## 待たずに進む＝ゲーム進行を止めない）
func _submit_stage_score(index: int, clear_time: float, fall_count: int) -> void:
	var board := "stage%02d" % (index + 1)
	var metadata := {"falls": fall_count}

	var current: Dictionary = await SilentWolf.Scores.get_scores(1, board).sw_get_scores_complete
	var is_new_best := true
	if current.get("success", false):
		var scores: Array = current.get("scores", [])
		if not scores.is_empty():
			is_new_best = clear_time < float(scores[0].get("score", INF))

	if is_new_best:
		metadata["replay"] = _build_replay_payload()

	SilentWolf.Scores.save_score(Settings.player_name, clear_time, board, metadata)


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
		_add_label(box, "THANKS FOR PLAYTESTING!", 46, Color(1.0, 0.92, 0.4))
		return

	if is_last:
		_add_label(box, "ALL CLEAR", 64, Color(1.0, 0.92, 0.4))
		_add_label(box, "TIME  %.2f" % clear_time, 30, Color(0.9, 0.94, 1.0))
		_add_label(box, "FALLS  %d" % _total_falls, 26, Color(0.9, 0.94, 1.0))
		_add_label(box, "[R] RETRY  /  [F2] STAGE SELECT", 20, Color(0.65, 0.7, 0.8))
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
	status.text = "Loading..."
	status.add_theme_font_size_override("font_size", 14)
	status.add_theme_color_override("font_color", Color(0.8, 0.85, 0.95))
	box.add_child(status)

	var board := "stage%02d" % (stage_index + 1)
	var sw_result: Dictionary = await SilentWolf.Scores.get_scores(10, board).sw_get_scores_complete
	if not is_instance_valid(box):
		return          # 待っている間にクリア画面が閉じられた

	if not sw_result.get("success", false):
		status.text = "Failed to load"
		return
	var scores: Array = sw_result.get("scores", [])
	if scores.is_empty():
		status.text = "No records yet"
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
	_add_hint(box, "[F1] TUNER    [F3] CLEAR THIS STAGE")
	_add_hint(box, "[F4] GRID (250px)    [F6] EVENT SELECT")
	_add_hint(box, "[R] RETRY    1-9 / 0 TO JUMP TO STAGE")

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


# ═══════════════════════════════ イベントセレクト（デバッグ）

## 確認できるイベントを、実際の繋がりから集める。
##
## ディレクトリを走査すると「.tres は在るがどのステージからも指されていない」
## 食い違いを見落とすので、Game の opening/ending と各ステージの intro/outro を
## そのまま並べる。ステージは読み込みが重いので、F6 を初めて押したときだけ走らせる
func _collect_events() -> void:
	_events.clear()
	if opening:
		_events.append({"key": "OP", "data": opening})
	for i in stages.size():
		var node := stages[i].instantiate()
		var st := node as Stage
		if st:
			if st.intro:
				_events.append({"key": "%2d intro" % (i + 1), "data": st.intro})
			if st.outro:
				_events.append({"key": "%2d outro" % (i + 1), "data": st.outro})
		node.free()
	if ending:
		_events.append({"key": "ED", "data": ending})


func _toggle_event_ui() -> void:
	if _event_panel == null:
		_collect_events()
		_build_event_ui()
		_event_panel.visible = true
		return
	_event_panel.visible = not _event_panel.visible


func _build_event_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100                     # チューナー(128)より下
	add_child(layer)

	_event_panel = PanelContainer.new()
	# ステージセレクト（左上）とぶつからないよう右上に置く
	_event_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_event_panel.position = Vector2(-272, 12)
	layer.add_child(_event_panel)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(260, minf(620.0, 80.0 + _events.size() * 28.0))
	_event_panel.add_child(scroll)

	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 2)
	scroll.add_child(box)
	_add_label(box, "EVENT SELECT  [F6]", 13, Color(1.0, 0.85, 0.45))
	_add_hint(box, "[F9] 演出メモ  [SPACE] 送り  [ENTER] スキップ")

	var all := Button.new()
	all.text = "▶ ALL (%d)  通し再生" % _events.size()
	all.pressed.connect(_play_all_events)
	box.add_child(all)

	# 通し再生中はパネルを隠すので、進み具合は別の帯で出す
	var progress_box := PanelContainer.new()
	progress_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	progress_box.position = Vector2(-140, 8)
	progress_box.custom_minimum_size.x = 280
	progress_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	progress_box.visible = false
	layer.add_child(progress_box)

	_event_progress = Label.new()
	_event_progress.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_event_progress.add_theme_font_size_override("font_size", 16)
	_event_progress.add_theme_color_override("font_color", Color(1.0, 0.85, 0.45))
	progress_box.add_child(_event_progress)

	for i in _events.size():
		var b := Button.new()
		var data: CutsceneData = _events[i]["data"]
		b.text = "%s  (%d)  %s" % [_events[i]["key"], data.lines.size(),
			data.resource_path.get_file().get_basename()]
		b.pressed.connect(_play_event.bind(i))
		box.add_child(b)


func _play_event(index: int) -> void:
	if index < 0 or index >= _events.size() or cutscene == null:
		return
	_event_panel.visible = false
	print("[Game] イベント確認 %s -> %s" % [_events[index]["key"],
		(_events[index]["data"] as CutsceneData).resource_path])
	await cutscene.play(_events[index]["data"])
	_event_panel.visible = true


## OP → 各面の前後 → ED を順に流す。ESC で降りる
func _play_all_events() -> void:
	if cutscene == null or _playing_all:
		return
	_playing_all = true
	_event_panel.visible = false
	var bar := _event_progress.get_parent() as Control
	# 会話の枠より上に出したいので、Cutscene が pause する前に出しておく
	bar.visible = true
	for i in _events.size():
		if not _playing_all:
			break
		_event_progress.text = "%d/%d  %s" % [i + 1, _events.size(), _events[i]["key"]]
		await cutscene.play(_events[i]["data"])
	_playing_all = false
	bar.visible = false
	_event_panel.visible = true


## セレクトパネルに出す操作の手引き
func _add_hint(parent: Node, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", Color(0.62, 0.67, 0.74))
	parent.add_child(label)


# ═══════════════════════════════ ポーズメニュー

## ESC で開く。ツリーごと止めるので、クリアタイム（物理ステップの積算）も止まる
func _open_pause_menu() -> void:
	if _pause_overlay or _advancing or _respawning:
		return
	if cutscene and cutscene.visible:
		return          # イベント中は送りの ESC と取り合いになるので出さない

	_pause_overlay = CanvasLayer.new()
	_pause_overlay.layer = 72          # クリア表示(64)より上、チューナー(128)より下
	# ツリーを止めても操作できるようにする
	_pause_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_pause_overlay)

	var back := ColorRect.new()
	back.color = Color(0.05, 0.06, 0.09, 0.7)
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause_overlay.add_child(back)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 18)
	_pause_overlay.add_child(box)

	_add_label(box, "PAUSED", 52, Color(1.0, 0.92, 0.4))
	# ESC でも閉じられるようにショートカットを持たせる。ツリーが止まっている間は
	# Game 側の _unhandled_input が動かないので、ボタン自身に持たせるのが確実
	var resume := _add_pause_button(box, "RESUME", _close_pause_menu)
	var shortcut := Shortcut.new()
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	shortcut.events = [esc]
	resume.shortcut = shortcut
	_add_pause_button(box, "SAVE", _save_from_pause)
	_add_pause_button(box, "RETURN TO TITLE", _return_to_title)
	_add_pause_button(box, "QUIT GAME", _quit_game)

	_pause_note = Label.new()
	_pause_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pause_note.add_theme_font_size_override("font_size", 20)
	_pause_note.add_theme_color_override("font_color", Color(0.75, 0.85, 1.0))
	box.add_child(_pause_note)

	resume.grab_focus()

	get_tree().paused = true


func _add_pause_button(parent: Node, text: String, callback: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(360, 56)
	b.add_theme_font_size_override("font_size", 26)
	b.pressed.connect(callback)
	parent.add_child(b)
	return b


## ポーズメニューからの手動セーブ。ステージの途中の状態は持たないので、
## 「今のステージの頭から」として書く。次に CONTINUE すると
## このステージを最初からやり直すことになる
func _save_from_pause() -> void:
	if _write_save(_index):
		_set_pause_note("SAVED  —  STAGE %d の頭から再開できます" % (_index + 1))
	else:
		_set_pause_note("テスト用の設定が入っているので保存しません")


func _set_pause_note(text: String) -> void:
	if _pause_note:
		_pause_note.text = text


## ESC のメニューからゲームを終了する。
## 進行は各ステージの終わりに自動で書いているので、ここでは書かない。
## 途中まで進めたぶんを残したければ、先に SAVE を押してもらう
func _quit_game() -> void:
	get_tree().paused = false      # 終了処理の途中でツリーを止めたままにしない
	get_tree().quit()


func _close_pause_menu() -> void:
	if _pause_overlay == null:
		return
	_pause_overlay.queue_free()
	_pause_overlay = null
	_pause_note = null
	get_tree().paused = false


func _return_to_title() -> void:
	_close_pause_menu()
	get_tree().change_scene_to_file(TITLE_SCENE)


func _add_label(parent: Node, text: String, size: int, color: Color) -> void:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
