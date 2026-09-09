class_name ReplayViewer
extends Node2D
##
## ランキング1位のリプレイを再生する専用画面。
## 実際のステージ・背景を読み込み、記録された座標をゴーストがなぞる。
## プレイヤーの入力・物理は一切使わない（見るだけ）。
##
## 再生するデータは Settings.pending_replay_stage_index /
## pending_replay_data 経由で受け取る（シーン切り替えを挟むため）。
## title.gd の「▶」ボタンがここへ値をセットしてから遷移してくる
##

const TITLE_SCENE := "res://scenes/Title.tscn"
const BACKGROUND_SCENE := preload("res://scenes/Background.tscn")

var _ghost: ReplayGhost
var _camera: Camera2D
var _end_label: Label

var _x: PackedFloat32Array
var _y: PackedFloat32Array
var _tilt: PackedFloat32Array
var _stride := 1
var _sample_pos := 0.0
var _playing := false


func _ready() -> void:
	var stage_index: int = Settings.pending_replay_stage_index
	var data: Dictionary = Settings.pending_replay_data
	Settings.pending_replay_stage_index = -1
	Settings.pending_replay_data = {}

	if stage_index < 0 or data.is_empty():
		_back_to_title()
		return

	_x = PackedFloat32Array(data.get("x", []))
	_y = PackedFloat32Array(data.get("y", []))
	_tilt = PackedFloat32Array(data.get("tilt", []))
	_stride = maxi(1, int(data.get("stride", 1)))

	if _x.size() < 2:
		_back_to_title()
		return

	add_child(BACKGROUND_SCENE.instantiate())

	var stage_path := "res://scenes/stages/Stage%02d.tscn" % (stage_index + 1)
	var stage_packed: PackedScene = load(stage_path)
	if stage_packed == null:
		_back_to_title()
		return
	var stage := stage_packed.instantiate()
	add_child(stage)

	_build_ghost(stage as Stage)
	_build_ui(stage_index)

	_ghost.position = Vector2(_x[0], _y[0])
	_playing = true


func _physics_process(_delta: float) -> void:
	if not _playing:
		return

	_sample_pos += 1.0 / float(_stride)
	var count := _x.size()
	var i := int(_sample_pos)
	var reached_end := i >= count - 1
	i = mini(i, count - 1)
	var next_i := mini(i + 1, count - 1)
	var frac := clampf(_sample_pos - float(i), 0.0, 1.0)

	_ghost.position = Vector2(lerpf(_x[i], _x[next_i], frac), lerpf(_y[i], _y[next_i], frac))
	_ghost.rotation = deg_to_rad(lerpf(_tilt[i], _tilt[next_i], frac))

	if reached_end:
		_playing = false
		_end_label.visible = true


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"pogo_retry"):
		get_viewport().set_input_as_handled()
		_restart()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if (event as InputEventKey).keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			_back_to_title()


func _restart() -> void:
	_sample_pos = 0.0
	_playing = true
	_end_label.visible = false


func _back_to_title() -> void:
	get_tree().change_scene_to_file(TITLE_SCENE)


# ═══════════════════════════════ 組み立て

func _build_ghost(stage: Stage) -> void:
	_ghost = ReplayGhost.new()
	_ghost.name = "Ghost"
	add_child(_ghost)

	_camera = Camera2D.new()
	_camera.zoom = Vector2(1.4, 1.4)
	_camera.position_smoothing_enabled = true
	_camera.position_smoothing_speed = 8.0
	if stage:
		var r := stage.camera_bounds
		if r.size.x > 0.0 and r.size.y > 0.0:
			_camera.limit_left = int(r.position.x)
			_camera.limit_top = int(r.position.y)
			_camera.limit_right = int(r.end.x)
			_camera.limit_bottom = int(r.end.y)
	_ghost.add_child(_camera)
	_camera.make_current()


func _build_ui(stage_index: int) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 40
	add_child(layer)

	var top := Label.new()
	top.text = "STAGE %d リプレイ再生中　[R] 最初から　[ESC] タイトルへ戻る" % (stage_index + 1)
	top.add_theme_font_size_override("font_size", 20)
	top.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.9))
	top.set_anchors_preset(Control.PRESET_TOP_LEFT)
	top.offset_left = 24
	top.offset_top = 20
	layer.add_child(top)

	_end_label = Label.new()
	_end_label.text = "再生終了　　[R] もう一度　　[ESC] タイトルへ戻る"
	_end_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_end_label.add_theme_font_size_override("font_size", 36)
	_end_label.add_theme_color_override("font_color", Color(1.0, 0.92, 0.4))
	_end_label.set_anchors_preset(Control.PRESET_CENTER)
	_end_label.visible = false
	layer.add_child(_end_label)
