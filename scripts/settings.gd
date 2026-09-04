extends Node
##
## ゲーム全体の設定。オートロード（Settings）として常駐する。
##
## オプション画面から編集し、user://settings.cfg に保存する。
## BGM/SE の音量は AudioServer の "BGM"/"SE" バスへそのまま反映する
## （default_bus_layout.tres で用意してある）。
##
## SilentWolf（オンラインランキング）の設定もここでまとめて行う。
## APIキーはSilentWolf側の設計上クライアントに埋め込む前提のものなので、
## ここに直書きしている（サーバー側の秘密鍵ではない）
##

const SAVE_PATH := "user://settings.cfg"
## バス音量を 0 にしたとき、-INF ではなくこの dB を下限にする
const MIN_DB := -80.0

const SW_API_KEY := "FfnXkXz7uK3FI3yyltIRL44CGmyUE6R57hVHYVEx"
const SW_GAME_ID := "popping1"

var bgm_volume := 0.8:
	set(value):
		bgm_volume = clampf(value, 0.0, 1.0)
		_apply_bus_volume("BGM", bgm_volume)

var se_volume := 0.8:
	set(value):
		se_volume = clampf(value, 0.0, 1.0)
		_apply_bus_volume("SE", se_volume)

## デモ（オープニング・ステージ冒頭イベント）を飛ばす開発者用の隠しスイッチ。
## 有効な間はスコアをオンラインランキングへ送信しない（テストデータで汚さないため）。
##
## Title の画面からは操作できない（意図的）。以前はタイトル画面自体も
## スキップしていたが、一度ONにすると戻す手段（オプション画面）へ二度と
## たどり着けなくなる事故が実際に起きたため、その効果は撤去した。
## 有効にしたいときは user://settings.cfg を直接編集するか、
## リモートデバッガでこの変数を書き換えること
var test_mode := false

## オンラインランキングに載せるプレイヤー名
var player_name := "プレイヤー"

## ランキング表示(各順位の行)の文字サイズ (px)
var ranking_font_size := 14.0:
	set(value):
		ranking_font_size = clampf(value, 10.0, 32.0)


func _ready() -> void:
	SilentWolf.configure({
		"api_key": SW_API_KEY,
		"game_id": SW_GAME_ID,
		"log_level": 0,
	})
	_load()


## オプション画面を閉じるときなどに呼ぶ
func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "bgm_volume", bgm_volume)
	cfg.set_value("audio", "se_volume", se_volume)
	cfg.set_value("debug", "test_mode", test_mode)
	cfg.set_value("profile", "player_name", player_name)
	cfg.set_value("ui", "ranking_font_size", ranking_font_size)
	cfg.save(SAVE_PATH)


func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		bgm_volume = cfg.get_value("audio", "bgm_volume", bgm_volume)
		se_volume = cfg.get_value("audio", "se_volume", se_volume)
		test_mode = cfg.get_value("debug", "test_mode", test_mode)
		player_name = cfg.get_value("profile", "player_name", player_name)
		ranking_font_size = cfg.get_value("ui", "ranking_font_size", ranking_font_size)
	else:
		# セーブが無くても既定音量をバスへ反映する
		_apply_bus_volume("BGM", bgm_volume)
		_apply_bus_volume("SE", se_volume)


func _apply_bus_volume(bus_name: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		return
	var db := MIN_DB if linear <= 0.0001 else linear_to_db(linear)
	AudioServer.set_bus_volume_db(idx, db)
