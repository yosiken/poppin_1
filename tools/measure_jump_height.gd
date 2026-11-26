extends SceneTree
##
## 平地での跳躍高さを実測する。レベルデザインの寸法決めに使う。
##
##   godot --headless --path . --script res://tools/measure_jump_height.gd
##
## 測るもの:
##   - 何も押さないときの1バウンドごとの到達高さ
##   - 溜め押しっぱなしのときの到達高さ（跳ぶたびに伸びて頭打ちになる）
##   - 傾けたときの到達高さと水平距離
##   - 落差から着地して溜めたときの到達高さ（飛び込み台）
##
## 傾き角ごとの細かい表は measure_tilt.gd、
## 階段を連続で登れる限界は measure_stairs.gd。
##

const STATS_PATH := "res://resources/pogo_stats_default.tres"


func _initialize() -> void:
	var world := Node2D.new()
	get_root().add_child(world)

	# 平らな地面 (y = 0 が上面)
	var body := StaticBody2D.new()
	var col := CollisionPolygon2D.new()
	col.polygon = PackedVector2Array([
		Vector2(-40000.0, 0.0), Vector2(40000.0, 0.0),
		Vector2(40000.0, 400.0), Vector2(-40000.0, 400.0)])
	body.add_child(col)
	world.add_child(body)

	var player := PogoPlayer.new()
	player.stats = load(STATS_PATH)
	player.debug_draw = false
	world.add_child(player)

	var driver := Driver.new()
	driver.player = player
	world.add_child(driver)


class Driver extends Node:
	var player: PogoPlayer

	var runs: Array = [
		{"name": "通常バウンド（入力なし）",      "charge": false, "tilt": 0, "drop": 0.0},
		{"name": "溜め押しっぱなし",              "charge": true,  "tilt": 0, "drop": 0.0},
		{"name": "通常バウンド＋最大傾き",        "charge": false, "tilt": 1, "drop": 0.0},
		{"name": "溜め押しっぱなし＋最大傾き",    "charge": true,  "tilt": 1, "drop": 0.0},
		{"name": "250px 落下から溜め",            "charge": true,  "tilt": 0, "drop": 250.0},
		{"name": "500px 落下から溜め",            "charge": true,  "tilt": 0, "drop": 500.0},
		{"name": "1000px 落下から溜め",           "charge": true,  "tilt": 0, "drop": 1000.0},
		{"name": "1500px 落下から溜め",           "charge": true,  "tilt": 0, "drop": 1500.0},
	]

	const MAX_BOUNCES := 10
	const REST_Y := -28.0        # body_height 56 の半分。接地時の中心 y

	var idx := -1
	var bounce_count := 0
	var apex_y := 0.0
	var last_x := 0.0
	var heights: Array = []
	var spans: Array = []
	var settle := 0
	var lines: Array = []

	func _ready() -> void:
		player.bounced.connect(_on_bounced)
		_next_run()

	func _next_run() -> void:
		if idx >= 0:
			var r: Dictionary = runs[idx]
			var h := ""
			for v in heights:
				h += "%6.1f" % v
			var s := ""
			for v in spans:
				s += "%6.1f" % v
			lines.append("%-26s 高さ:%s   / 水平:%s" % [r["name"], h, s])
		idx += 1
		if idx >= runs.size():
			_report()
			return
		var run: Dictionary = runs[idx]
		for a in [&"pogo_charge", &"pogo_left", &"pogo_right"]:
			if Input.is_action_pressed(a):
				Input.action_release(a)
		heights = []
		spans = []
		bounce_count = 0
		settle = 0
		player.teleport(Vector2(0.0, REST_Y - float(run["drop"])))
		apex_y = player.global_position.y
		last_x = 0.0

	func _physics_process(_delta: float) -> void:
		if idx < 0 or idx >= runs.size():
			return
		var run: Dictionary = runs[idx]
		if bool(run["charge"]) and not Input.is_action_pressed(&"pogo_charge"):
			Input.action_press(&"pogo_charge")
		if int(run["tilt"]) > 0 and not Input.is_action_pressed(&"pogo_right"):
			Input.action_press(&"pogo_right")
		apex_y = minf(apex_y, player.global_position.y)
		settle += 1
		if settle > 4000:
			_next_run()

	func _on_bounced(_strength: float, _normal: Vector2) -> void:
		var x := player.global_position.x
		if bounce_count > 0:
			heights.append(-apex_y + REST_Y)
			spans.append(x - last_x)
		bounce_count += 1
		last_x = x
		apex_y = player.global_position.y
		if bounce_count > MAX_BOUNCES:
			_next_run()

	func _report() -> void:
		print("")
		print("=== 平地での実測 (1バウンドごと) ===")
		for l in lines:
			print(l)
		print("")
		get_tree().quit()
