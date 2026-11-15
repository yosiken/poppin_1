extends SceneTree
##
## クレジットの見た目を1枚だけ撮る（目視確認用）。
##
##   godot --path . --script res://tools/shot_credits.gd -- <保存先.png> [秒]
##
## 本番と同じ CreditsData をそのまま流し、指定秒後の画面を保存して終わる
##

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "user://credits.png"
	var at := float(args[1]) if args.size() > 1 else 2.0
	var data := load("res://resources/credits.tres") as CreditsData
	if data == null:
		print("NG  credits.tres が読めない")
		quit(1)
		return
	var ui := Credits.new()
	get_root().add_child(ui)
	var shot := Shot.new()
	shot.ui = ui
	shot.data = data
	shot.out = out
	shot.at = at
	get_root().add_child(shot)


class Shot extends Node:
	var ui: Credits
	var data: CreditsData
	var out: String
	var at := 2.0
	var time := 0.0
	var started := false

	func _init() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS

	func _process(delta: float) -> void:
		if not started:
			started = true
			ui.play(data)
			return
		time += delta
		if time < at:
			return
		set_process(false)
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var err := img.save_png(out)
		print("[shot] %.1f 秒の画面 -> %s （%s）" % [at, out,
			"保存した" if err == OK else "保存できない: %d" % err])
		get_tree().quit(0 if err == OK else 1)
