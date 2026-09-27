extends SceneTree
##
## SilentWolf のリーダーボードを空にする。元に戻せないので実行は慎重に。
##
##   godot --headless --path . --script res://tools/sw_wipe.gd
##

const BOARDS := ["total", "stage01", "stage02", "stage03", "stage04", "stage05",
	"stage06", "stage07", "stage08", "stage09", "stage10"]


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	await process_frame
	var sw: Node = root.get_node_or_null(^"SilentWolf")
	if sw == null:
		print("WIPE SilentWolf が見つかりません")
		quit()
		return
	for board in BOARDS:
		var res: Dictionary = await sw.Scores.wipe_leaderboard(board).sw_wipe_leaderboard_complete
		print("WIPE %-8s success=%s" % [board, res.get("success", false)])
	quit()
