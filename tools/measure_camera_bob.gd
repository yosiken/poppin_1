extends SceneTree
##
## 跳ねている間にカメラが縦へどれだけ動くかを測る。
##
##   godot --headless --path . --script res://tools/measure_camera_bob.gd
##
## チュートリアルの区画1と本編のステージ1を、チャージを押しっぱなしで
## 同じ秒数ずつ跳ねさせて、
## プレイヤーの上下動のうちカメラが何割を追ってしまうかを見る。
## カメラが全部追うと、画面の中でキャラは止まって見え、地面のほうが揺れる
##

const SECONDS := 5.0

func _initialize() -> void:
	var save := get_root().get_node_or_null(^"SaveGame")
	save.set("tutorial_requested", true)
	save.set("continue_requested", false)
	var main := (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	main.set("skip_cutscenes", true)
	main.set("stage_title_duration", 0.0)
	get_root().add_child(main)
	var d := Driver.new()
	d.game = main
	get_root().add_child(d)


class Driver extends Node:
	var game: Node
	var phase := 0
	var time := 0.0
	var warm := 0.0
	var cam_min := INF
	var cam_max := -INF
	var p_min := INF
	var p_max := -INF
	var lines: Array[String] = []
	var pressing := false

	func _physics_process(delta: float) -> void:
		var player := game.get("player") as Node2D
		var cam := player.get_node_or_null(^"Camera2D") as Camera2D if player else null
		var stage: Node = game.get("_stage")
		if player == null or cam == null or stage == null:
			return
		warm += delta
		if warm < 1.0:               # 置かれた直後の1秒は数えない
			return
		if not pressing:             # 押しっぱなしで大きく跳ねさせる
			pressing = true
			Input.action_press(&"pogo_charge")
		time += delta
		var cy: float = cam.get_screen_center_position().y
		cam_min = minf(cam_min, cy)
		cam_max = maxf(cam_max, cy)
		p_min = minf(p_min, player.global_position.y)
		p_max = maxf(p_max, player.global_position.y)
		if time < SECONDS:
			return
		_record(stage)
		if phase == 0:
			phase = 1
			Input.action_release(&"pogo_charge")
			pressing = false
			game.call("load_stage", 0)
			_reset()
		else:
			_report()

	func _reset() -> void:
		time = 0.0
		warm = 0.0
		cam_min = INF
		cam_max = -INF
		p_min = INF
		p_max = -INF

	func _record(stage: Node) -> void:
		var bounds: Rect2 = stage.camera_bounds
		var view_h := 1080.0 / 1.4          # 画面の高さ / カメラのズーム
		var free_y: float = maxf(bounds.size.y - view_h, 0.0)
		var moved_cam := cam_max - cam_min
		var moved_player := p_max - p_min
		var ratio := 0.0 if moved_player <= 0.1 else moved_cam / moved_player * 100.0
		var view_top := cam_max - view_h * 0.5      # いちばん下にあったときの視界
		var view_bottom := cam_max + view_h * 0.5
		lines.append("%s" % stage.get_display_name())
		lines.append("  範囲 y %.0f..%.0f（高さ %.0f）/ カメラが動ける縦幅 %.0f"
			% [bounds.position.y, bounds.end.y, bounds.size.y, free_y])
		lines.append("  プレイヤー y %.0f..%.0f（上下動 %.0f px）"
			% [p_min, p_max, moved_player])
		lines.append("  カメラ中心 y %.0f..%.0f（上下動 %.0f px → %.0f%% を追う）"
			% [cam_min, cam_max, moved_cam, ratio])
		lines.append("  画面の下端 y %.0f … 立っているとき足元まで %.0f px"
			% [view_bottom, view_bottom - p_max])
		lines.append("  画面の上端 y %.0f … 最高到達点まで %.0f px"
			% [view_top, p_min - view_top])

	func _report() -> void:
		Input.action_release(&"pogo_charge")
		print("")
		print("=== 跳ねている間のカメラ（入力なし %.0f 秒） ===" % SECONDS)
		for l in lines:
			print(l)
		print("")
		print("100%% に近いほど、画面の中でキャラは止まり地面が揺れて見える")
		get_tree().quit(0)
