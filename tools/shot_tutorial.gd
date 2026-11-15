extends SceneTree
##
## チュートリアル面の見た目を1枚撮る（目視確認用）。
##
##   godot --path . --script res://tools/shot_tutorial.gd -- <保存先.png> [秒] [区画番号] [右へずらす量px]
##
## タイトルの TUTORIAL から入ったのと同じ状態で Main.tscn を動かし、
## 指定秒後の画面を保存して終わる
##

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "user://tutorial.png"
	var at := float(args[1]) if args.size() > 1 else 2.0
	var section := int(args[2]) if args.size() > 2 else 0
	var dx := float(args[3]) if args.size() > 3 else 0.0

	var save := get_root().get_node_or_null(^"SaveGame")
	if save == null:
		print("NG  SaveGame が見つからない")
		quit(1)
		return
	save.set("tutorial_requested", true)
	save.set("continue_requested", false)

	var main := (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	main.set("skip_cutscenes", true)
	main.set("stage_title_duration", 0.0)
	get_root().add_child(main)

	var shot := Shot.new()
	shot.game = main
	shot.out = out
	shot.at = at
	shot.section = section
	shot.dx = dx
	get_root().add_child(shot)


class Shot extends Node:
	var game: Node
	var out: String
	var at := 2.0
	var section := 0
	var dx := 0.0
	var time := 0.0
	var moved := false

	func _init() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS

	func _process(delta: float) -> void:
		time += delta
		if not moved and time > 0.5:
			moved = true
			if section > 0:
				game.call("start_tutorial_section", section, false)
			if dx != 0.0:
				var player := game.get("player") as Node2D
				if player:
					player.call("teleport", player.global_position + Vector2(dx, 0.0))
		if time < at:
			return
		set_process(false)
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var err := img.save_png(out)
		print("[shot] %.1f 秒 / 区画%d -> %s （%s）" % [at, section + 1, out,
			"保存した" if err == OK else "保存できない: %d" % err])
		get_tree().quit(0 if err == OK else 1)
