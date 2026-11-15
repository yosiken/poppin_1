extends SceneTree
##
## 傾き角ごとの「1バウンドで届く高さ・水平距離・周期」を実測する。
## 足場の間隔と段差を決めるときの早見表を作るためのもの。
##
##   godot --headless --path . --script res://tools/measure_tilt.gd
##
## 跳躍高さそのものは measure_jump_height.gd、
## 階段を連続で登れる限界は measure_stairs.gd。
##


func _initialize() -> void:
	var world := Node2D.new()
	get_root().add_child(world)

	var body := StaticBody2D.new()
	var col := CollisionPolygon2D.new()
	col.polygon = PackedVector2Array([
		Vector2(-80000.0, 0.0), Vector2(80000.0, 0.0),
		Vector2(80000.0, 400.0), Vector2(-80000.0, 400.0)])
	body.add_child(col)
	world.add_child(body)

	var player := PogoPlayer.new()
	player.stats = load("res://resources/pogo_stats_default.tres")
	player.debug_draw = false
	world.add_child(player)

	var driver := Driver.new()
	driver.player = player
	world.add_child(driver)


class Driver extends Node:
	var player: PogoPlayer

	# [溜めるか, 傾きの上限(度)]
	var runs: Array = [
		[false, 5.0], [false, 10.0], [false, 15.0], [false, 20.0], [false, 35.0],
		[true, 0.0], [true, 5.0], [true, 10.0], [true, 15.0],
		[true, 20.0], [true, 25.0], [true, 30.0], [true, 35.0],
	]

	const REST_Y := -28.0
	const WARMUP := 7        # 定常になるまで捨てるバウンド数
	const SAMPLE := 4        # 平均を取るバウンド数

	var idx := -1
	var n := 0
	var apex_y := 0.0
	var last_x := 0.0
	var last_frame := 0
	var frame := 0
	var h_sum := 0.0
	var x_sum := 0.0
	var t_sum := 0.0
	var lines: Array = []

	func _ready() -> void:
		player.bounced.connect(_on_bounced)
		lines.append("溜め  傾き上限   高さ(px)  水平(px/バウンド)  周期(秒)")
		_next_run()

	func _next_run() -> void:
		if idx >= 0 and n > WARMUP:
			var r: Array = runs[idx]
			lines.append("%-5s %5.0f度 %9.1f %13.1f %12.2f" % [
				"あり" if bool(r[0]) else "なし", float(r[1]),
				h_sum / SAMPLE, x_sum / SAMPLE, t_sum / SAMPLE])
		idx += 1
		if idx >= runs.size():
			_report()
			return
		for a in [&"pogo_charge", &"pogo_right"]:
			if Input.is_action_pressed(a):
				Input.action_release(a)
		n = 0
		h_sum = 0.0
		x_sum = 0.0
		t_sum = 0.0
		player.teleport(Vector2(0.0, REST_Y))
		apex_y = player.global_position.y
		last_x = 0.0
		last_frame = frame

	func _physics_process(_delta: float) -> void:
		if idx < 0 or idx >= runs.size():
			return
		frame += 1
		var run: Array = runs[idx]
		if bool(run[0]) and not Input.is_action_pressed(&"pogo_charge"):
			Input.action_press(&"pogo_charge")
		var cap := float(run[1])
		if cap > 0.0:
			if not Input.is_action_pressed(&"pogo_right"):
				Input.action_press(&"pogo_right")
			# 上限で頭打ちにする（キーを押しっぱなしのまま角度だけ止める）
			player.tilt_deg = minf(player.tilt_deg, cap)
		apex_y = minf(apex_y, player.global_position.y)

	func _on_bounced(_strength: float, _normal: Vector2) -> void:
		var x := player.global_position.x
		n += 1
		if n > WARMUP and n <= WARMUP + SAMPLE:
			h_sum += -apex_y + REST_Y
			x_sum += x - last_x
			t_sum += float(frame - last_frame) / 60.0
		last_x = x
		last_frame = frame
		apex_y = player.global_position.y
		if n >= WARMUP + SAMPLE:
			_next_run()

	func _report() -> void:
		print("")
		print("=== 平地・定常状態での実測 ===")
		for l in lines:
			print(l)
		print("")
		get_tree().quit()
