class_name TitleMusic
extends AudioStreamPlayer
##
## 起動画面とメインメニューで流す曲（水都オーディナリィ）。
##
## ルートに1つだけ置くので、起動画面 → メインメニューへ移っても途切れない。
## メニューの中（OPTIONS・ランキング）でも鳴り続ける。
## それ以外のシーン（ゲーム・リプレイ）へ移ったら、フェードして消える。
## クレジット中はツリーが止まるので一緒に止まり、終われば続きから鳴る。
##
## 曲は前半と後半がほぼ同じ繰り返しなので、最後まで行くと後半の頭（107.8秒）へ
## 戻ってループする。
## 戻り先は title_suito.ogg.import の loop_offset。ファイルは戻り先とつながる所で
## 切ってある（元の曲は 228秒。最後のフェードアウトは使わない）。
##

const STREAM := preload("res://resources/sound/bgm/title_suito.ogg")
const NODE_NAME := &"TitleMusic"
## この曲を鳴らし続けるシーン
const SCENES: Array[String] = ["res://scenes/TitleSplash.tscn", "res://scenes/Title.tscn"]
## ほかのシーンへ移ったとき、消えるまでの秒数
const FADE_OUT := 0.6

var _leaving := false


## まだ鳴っていなければ鳴らし始める。起動画面とメニューの _ready から呼ぶ
static func ensure(tree: SceneTree) -> void:
	var existing := tree.root.get_node_or_null(NodePath(NODE_NAME)) as TitleMusic
	if existing and not existing._leaving:
		return
	var music := TitleMusic.new()
	music.name = NODE_NAME
	# シーンの _ready 中はルートに子を足せないので、あとで足す
	tree.root.add_child.call_deferred(music)


func _ready() -> void:
	stream = STREAM
	bus = &"BGM" if AudioServer.get_bus_index(&"BGM") >= 0 else &"Master"
	play()
	get_tree().scene_changed.connect(_on_scene_changed)


func _on_scene_changed() -> void:
	var scene := get_tree().current_scene
	if scene and scene.scene_file_path in SCENES:
		return
	_fade_out()


func _fade_out() -> void:
	if _leaving:
		return
	_leaving = true
	# 同じ名前で新しく作れるように、名前を空けておく
	name = &"TitleMusicLeaving"
	# ゲーム側はイベント中にツリーを止める。止まってもフェードは最後まで進める
	process_mode = Node.PROCESS_MODE_ALWAYS
	var tw := create_tween()
	tw.tween_property(self, "volume_db", -40.0, FADE_OUT)
	tw.tween_callback(queue_free)
