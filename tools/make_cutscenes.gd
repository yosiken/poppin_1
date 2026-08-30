extends SceneTree
##
## resources/cutscene/scenario.json からイベントの .tres を生成する開発用ツール。
##
##   python tools/scenario_to_json.py resources/dotonbori-isekai-scenario.md
##   godot --headless --path <project> --script res://tools/make_cutscenes.gd
##
## 既存の .tres は上書きされる。インスペクタで手を入れたあとに実行しないこと。
##

const JSON_PATH := "res://resources/cutscene/scenario.json"
const OUT_DIR := "res://resources/cutscene"

## ルイ（主人公）= 右、シマエナガ（ナビゲーター）= 左
const TEX_RIGHT := "res://resources/texture/ob_san.png"
const TEX_LEFT := "res://resources/texture/kanie.png"


func _initialize() -> void:
	var file := FileAccess.open(JSON_PATH, FileAccess.READ)
	if file == null:
		push_error("scenario.json がありません。先に tools/scenario_to_json.py を実行してください")
		quit(1)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("scenario.json を解釈できません")
		quit(1)
		return

	var left := load(TEX_LEFT)
	var right := load(TEX_RIGHT)
	var keys: Array = parsed.keys()
	keys.sort()

	for key in keys:
		var event: Dictionary = parsed[key]
		var data := CutsceneData.new()
		var lines: Array[CutsceneLine] = []
		for row in event["rows"]:
			var l := CutsceneLine.new()
			l.speaker = row.get("speaker", "")
			l.text = row.get("text", "")
			var is_left: bool = row.get("side", "") == "left"
			l.speaking = CutsceneLine.Side.LEFT if is_left else CutsceneLine.Side.RIGHT
			if row.get("show_left", false):
				l.left = left
			if row.get("show_right", false):
				l.right = right
			lines.append(l)
		data.lines = lines
		data.clear_on_finish = true

		var err := ResourceSaver.save(data, "%s/%s.tres" % [OUT_DIR, key])
		print("%-18s %2d コマ -> %s" % [key, lines.size(), error_string(err)])

	print("--- 演出メモ（未実装。SE を足すときの手掛かり）---")
	for key in keys:
		var notes: Array = parsed[key].get("notes", [])
		for n in notes:
			print("  [%s] %s" % [key, n])
	quit()
