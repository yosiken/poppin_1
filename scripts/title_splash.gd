class_name TitleSplash
extends Control
##
## 起動直後の画面。大きなタイトルロゴと「Press START」。
## なにかボタン（キー・パッド・マウス・タッチ）を押すと、メインメニュー
## （Title.tscn）へ移る。
##
## この画面は起動したときだけ。ゲームからタイトルへ戻るときは、
## これまでどおりメインメニューへ直接戻る（game.gd の TITLE_SCENE）。
##

const MENU_SCENE := "res://scenes/Title.tscn"

## ロゴの絵（余白を除いた部分）の大きさ。画面に収めるときに使う
const LOGO_ART_SIZE := Vector2(1968.0, 935.0)

## ロゴの横幅を、画面の何割にするか
@export_range(0.3, 1.0, 0.01) var logo_width := 0.8
## ロゴの高さの上限（画面の割合）
@export_range(0.3, 1.0, 0.01) var logo_height := 0.66
## ロゴの中心の高さ（画面の割合）
@export_range(0.0, 1.0, 0.01) var logo_center_y := 0.43
## Press START が点滅する1回の秒数
@export var blink_period := 1.4
## 押したときの音
@export var press_sound: AudioStream
## 起動してから、押しても反応しない秒数（起動前に押していたキーで飛ばさない）
@export var input_delay := 0.35

@onready var _logo: TitleLogo = $Logo
@onready var _press: Label = $PressStart
@onready var _fade: ColorRect = $Fade

var _t := 0.0
var _press_shown := false
var _press_alpha := 0.0
var _leaving := false


func _ready() -> void:
	# 曲はメインメニューへ移っても続ける（TitleMusic）
	TitleMusic.ensure(get_tree())
	resized.connect(_fit)
	_fit()
	_press.modulate.a = 0.0
	_fade.color.a = 0.0
	_logo.landed.connect(_on_logo_landed, CONNECT_ONE_SHOT)
	if not _logo.drop_in:
		_on_logo_landed()


func _fit() -> void:
	var s := minf(size.x * logo_width / LOGO_ART_SIZE.x, size.y * logo_height / LOGO_ART_SIZE.y)
	_logo.scale = Vector2(s, s)
	_logo.position = Vector2(size.x * 0.5, size.y * logo_center_y)


func _on_logo_landed() -> void:
	_press_shown = true


func _process(delta: float) -> void:
	_t += delta
	if _leaving:
		return
	if _press_shown:
		_press_alpha = minf(1.0, _press_alpha + delta * 2.5)
	var blink := 0.35 + 0.65 * (0.5 + 0.5 * cos(_t * TAU / blink_period))
	_press.modulate.a = _press_alpha * blink


func _input(event: InputEvent) -> void:
	if _leaving or _t < input_delay:
		return
	var pressed := false
	if event is InputEventKey:
		pressed = event.pressed and not event.echo
	elif event is InputEventJoypadButton or event is InputEventMouseButton or event is InputEventScreenTouch:
		pressed = event.pressed
	if pressed:
		get_viewport().set_input_as_handled()
		_leave()


func _leave() -> void:
	_leaving = true
	_logo.jump()
	_play_press_sound()
	# 押したら速く点滅して、暗くしてからメニューへ
	_press.modulate.a = 1.0
	var tw := create_tween()
	for i in 4:
		tw.tween_property(_press, "modulate:a", 0.15, 0.06)
		tw.tween_property(_press, "modulate:a", 1.0, 0.06)
	tw.tween_property(_fade, "color:a", 1.0, 0.35)
	tw.tween_callback(func() -> void:
		# メニュー側で「起動画面から来た」ことを知るため（イベント版の名前入力）
		Title.from_splash = true
		get_tree().change_scene_to_file(MENU_SCENE))


## 音はメニューへ移っても最後まで鳴らす（ルートに置き、鳴り終わったら消す）
func _play_press_sound() -> void:
	if press_sound == null:
		return
	var player := AudioStreamPlayer.new()
	player.stream = press_sound
	player.bus = &"SE" if AudioServer.get_bus_index(&"SE") >= 0 else &"Master"
	player.finished.connect(player.queue_free)
	get_tree().root.add_child(player)
	player.play()
