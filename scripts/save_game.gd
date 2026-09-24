extends Node
##
## 進行状況のセーブ。オートロード（SaveGame）として常駐する。
##
## スロットは1つだけ。ステージを1つ終えるたびに自動で書き、
## タイトルの CONTINUE から読む。ポーズメニューの SAVE でも書ける。
##
## 設定 (Settings) とは別のファイルにしてある。進行を消しても
## 音量やプレイヤー名まで巻き添えで消えないようにするため。
##
## 保存するのは「どこまで進んだか」だけで、ステージの途中の状態は持たない。
## CONTINUE は必ずステージの頭から始まる
##

## セーブの置き場
const SAVE_PATH := "user://progress_v1.cfg"

## セーブの作り。中身の形を変えたらここを上げる。
## 番号が合わないセーブは、壊れた状態で読み込むより無かったことにする
const VERSION := 1

## 次に始めるステージ番号 (0 始まり)
var stage_index := 0
## そこまでの合計タイムと落下回数。通算記録の続きを数えるために要る
var total_clear_time := 0.0
var total_falls := 0
## 取り戻した記憶のステージ番号
var memory_indices: PackedInt32Array = []
## 最後に書いた日時。CONTINUE のボタンに出す
var saved_at := ""

## タイトルの CONTINUE から入ったか。Game が起動時に見る。
## シーンをまたいで意図を渡すだけなので、ファイルには書かない
var continue_requested := false

var _has_save := false


func _ready() -> void:
	_load()


## 読めるセーブがあるか
func has_save() -> bool:
	return _has_save


## 今の進行を書く。next_stage は「次に始めるステージ番号」
func write(next_stage: int, clear_time: float, falls: int,
		memory: PackedInt32Array) -> void:
	stage_index = maxi(next_stage, 0)
	total_clear_time = clear_time
	total_falls = falls
	memory_indices = memory
	saved_at = Time.get_datetime_string_from_system(false, true)

	var cfg := ConfigFile.new()
	cfg.set_value("meta", "version", VERSION)
	cfg.set_value("meta", "saved_at", saved_at)
	cfg.set_value("progress", "stage_index", stage_index)
	cfg.set_value("progress", "total_clear_time", total_clear_time)
	cfg.set_value("progress", "total_falls", total_falls)
	cfg.set_value("progress", "memory", Array(memory_indices))
	var err := cfg.save(SAVE_PATH)
	if err != OK:
		push_warning("SaveGame: セーブに失敗しました (%s): %s"
			% [ProjectSettings.globalize_path(SAVE_PATH), error_string(err)])
		return
	_has_save = true
	print("[SaveGame] ステージ %d からの続きとして保存" % (stage_index + 1))


## セーブを消す。NEW GAME と、最後まで到達したときに呼ぶ
func erase() -> void:
	stage_index = 0
	total_clear_time = 0.0
	total_falls = 0
	memory_indices = []
	saved_at = ""
	_has_save = false
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var err := DirAccess.remove_absolute(SAVE_PATH)
	if err != OK:
		push_warning("SaveGame: セーブの削除に失敗しました: %s" % error_string(err))


## CONTINUE のボタンに出す一行。セーブが無ければ空文字
func summary() -> String:
	if not _has_save:
		return ""
	return "STAGE %d" % (stage_index + 1)


func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	if int(cfg.get_value("meta", "version", 0)) != VERSION:
		print("[SaveGame] 作りの違うセーブを無視します")
		return
	stage_index = int(cfg.get_value("progress", "stage_index", 0))
	total_clear_time = float(cfg.get_value("progress", "total_clear_time", 0.0))
	total_falls = int(cfg.get_value("progress", "total_falls", 0))
	memory_indices = PackedInt32Array(cfg.get_value("progress", "memory", []))
	saved_at = str(cfg.get_value("meta", "saved_at", ""))
	_has_save = true
	print("[SaveGame] ステージ %d からの続きを読み込み" % (stage_index + 1))
