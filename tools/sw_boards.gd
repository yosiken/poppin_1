extends SceneTree
##
## SilentWolf のリーダーボードの中身を数えるだけの確認用ツール（削除はしない）。
##
##   godot --headless --path . --script res://tools/sw_boards.gd
##

const BOARDS := ["total", "stage01", "stage02", "stage03", "stage04", "stage05",
	"stage06", "stage07", "stage08", "stage09", "stage10", "main"]


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	await process_frame
	var sw: Node = root.get_node_or_null(^"SilentWolf")
	if sw == null:
		print("BOARD SilentWolf が見つかりません")
		quit()
		return
	var total := 0
	for board in BOARDS:
		var res: Dictionary = await sw.Scores.get_scores(100, board).sw_get_scores_complete
		var scores: Array = res.get("scores", []) if res.get("success", false) else []
		total += scores.size()
		var head := ""
		if scores.size() > 0:
			head = "   1位: %s  %.2f" % [scores[0].get("player_name", "?"),
				float(scores[0].get("score", 0.0))]
		print("BOARD %-8s %3d 件%s" % [board, scores.size(), head])
	print("BOARD ---- 合計 %d 件" % total)
	quit()
