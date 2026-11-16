extends SceneTree
##
## 階段を連続で何段登れるかを実測する。段差と段の奥行きの上限を決めるためのもの。
## 「溜め押しっぱなしのまま、1バウンドあたり何px まで登り続けられるか」を測る。
##
## 奥行き(run)は傾き角ごとの1バウンド水平距離に合わせる。合わせないと
## 1バウンドで2段ぶん飛び越してしまい、連続登坂の限界が測れない。
##
##   godot --headless --path . --script res://tools/measure_stairs.gd
##

const STEPS := 12
const LIMIT_FRAMES := 2700      # 45秒


func _initialize() -> void:
	var world := Node2D.new()
	get_root().add_child(world)
	var player := PogoPlayer.new()
	player.stats = load("res://resources/pogo_stats_default.tres")
	player.debug_draw = false
	world.add_child(player)
	var d := Driver.new()
	d.player = player
	d.world = world
	world.add_child(d)


class Driver extends Node:
	var player: PogoPlayer
	var world: Node2D
	var stairs: StaticBody2D

	# [傾き上限(度), 1段の奥行き(px)]  奥行きは §1 の実測水平距離に合わせる
	var tilts: Array = [[15.0, 350.0], [25.0, 550.0]]
	var rises: Array = [150.0, 200.0, 250.0, 300.0, 350.0]

	var ti := 0
	var ri := 0
	var started := false
	var frame := 0
	var start_frame := 0
	var best := 0.0
	var lines: Array = []

	func _ready() -> void:
		lines.append("傾き  奥行き  段差   登れた高さ  段数/全%d  結果" % STEPS)
		_build.call_deferred()

	func _build() -> void:
		if stairs:
			stairs.queue_free()
			stairs = null
		if ti >= tilts.size():
			_report()
			return
		var rise: float = rises[ri]
		var run: float = tilts[ti][1]
		stairs = StaticBody2D.new()
		_add_box(stairs, -1500.0, 0.0, 1500.0, 600.0)        # 助走路
		for i in STEPS:
			_add_box(stairs, float(i) * run, -rise * float(i),
				run, 600.0 + rise * float(i))
		world.add_child(stairs)
		for a in [&"pogo_charge", &"pogo_right"]:
			if Input.is_action_pressed(a):
				Input.action_release(a)
		player.teleport(Vector2(-1200.0, -28.0))
		best = 0.0
		start_frame = frame
		started = true

	func _add_box(parent: Node, x: float, top_y: float, w: float, h: float) -> void:
		var col := CollisionPolygon2D.new()
		col.polygon = PackedVector2Array([
			Vector2(x, top_y), Vector2(x + w, top_y),
			Vector2(x + w, top_y + h), Vector2(x, top_y + h)])
		parent.add_child(col)

	func _physics_process(_delta: float) -> void:
		if not started:
			return
		frame += 1
		if not Input.is_action_pressed(&"pogo_charge"):
			Input.action_press(&"pogo_charge")
		if not Input.is_action_pressed(&"pogo_right"):
			Input.action_press(&"pogo_right")
		player.tilt_deg = minf(player.tilt_deg, float(tilts[ti][0]))
		best = maxf(best, -player.global_position.y - 28.0)
		var rise: float = rises[ri]
		if best >= rise * float(STEPS - 1) - 20.0:
			_finish(true)
		elif frame - start_frame > LIMIT_FRAMES:
			_finish(false)

	func _finish(cleared: bool) -> void:
		started = false
		var rise: float = rises[ri]
		var run: float = tilts[ti][1]
		lines.append("%3.0f度 %6.0f %5.0f %10.0f %8.0f    %s" % [
			float(tilts[ti][0]), run, rise, best,
			floorf(best / rise + 0.05), "登り切り" if cleared else "頭打ち"])
		ri += 1
		if ri >= rises.size():
			ri = 0
			ti += 1
		_build.call_deferred()

	func _report() -> void:
		print("")
		print("=== 溜め押しっぱなしでの連続登坂 ===")
		for l in lines:
			print(l)
		print("")
		get_tree().quit()
